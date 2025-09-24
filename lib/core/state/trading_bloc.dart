import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/app_data_manager.dart';
import '../analysis/unified_analysis_service.dart';
import '../trading/investment_style_manager.dart';
import '../trading/investment_style.dart';
import '../api/kis_unified_api_service.dart';

// Events
abstract class TradingEvent {}

class LoadStockData extends TradingEvent {
  final String stockCode;
  LoadStockData(this.stockCode);
}

class RefreshTradingData extends TradingEvent {
  final String stockCode;
  RefreshTradingData({required this.stockCode});
}

// States
abstract class TradingState {}

class TradingInitial extends TradingState {}

class TradingLoading extends TradingState {}

class TradingLoaded extends TradingState {
  final Map<String, dynamic> stockData;
  final Map<String, dynamic>? analysisResult;
  final bool isSilentRefresh;
  final String? message;
  final List<Map<String, dynamic>> positions;
  
  TradingLoaded({
    required this.stockData,
    this.analysisResult,
    this.isSilentRefresh = false,
    this.message,
    this.positions = const [],
  });
}

class TradingError extends TradingState {
  final String message;
  TradingError(this.message);
}

// Bloc
class TradingBloc extends Bloc<TradingEvent, TradingState> {
  final AppDataManager _appDataManager;
  final KisUnifiedApiService _unifiedApiService;
  final UnifiedAnalysisService _unifiedAnalysis = UnifiedAnalysisService.instance;
  final InvestmentStyleManager _styleManager = InvestmentStyleManager();
  
  Timer? _refreshTimer;
  bool _isRefreshing = false;


  TradingBloc({
    required AppDataManager appDataManager,
    required KisUnifiedApiService unifiedApiService,
  }) : _appDataManager = appDataManager,
       _unifiedApiService = unifiedApiService,
       super(TradingInitial()) {
    on<LoadStockData>(_onLoadStockData);
    on<RefreshTradingData>(_onRefreshTradingData);
  }

  Future<void> _onLoadStockData(LoadStockData event, Emitter<TradingState> emit) async {
    try {
      emit(TradingLoading());
      
      final stockData = await _loadStockDataSilent(event.stockCode, {});
      final analysisResult = await _performAnalysis(event.stockCode);
      final positions = await _loadPositions();
      
      emit(TradingLoaded(
        stockData: stockData,
        analysisResult: analysisResult,
        positions: positions,
      ));
    } catch (e) {
      emit(TradingError('종목 데이터 로드 실패: $e'));
    }
  }



  Future<void> _onRefreshTradingData(RefreshTradingData event, Emitter<TradingState> emit) async {
    if (_isRefreshing) {
      print('⚠️ TradingBloc: 이미 새로고침 중 - 건너뛰기');
      return;
    }
    
    _isRefreshing = true;
    
    try {
      print('🔄 TradingBloc: 거래 데이터 새로고침 시작 - ${event.stockCode}');
      
      if (state is TradingLoaded) {
        final currentState = state as TradingLoaded;
        
        // 기존 데이터를 유지하면서 백그라운드에서 업데이트
        // 깜빡임 방지를 위해 즉시 현재 상태를 유지
        emit(TradingLoaded(
          stockData: currentState.stockData,
          analysisResult: currentState.analysisResult,
          positions: currentState.positions,
          isSilentRefresh: true, // 사일런트 새로고침 표시
        ));
        
        // 백그라운드에서 데이터 업데이트
        final updatedStockData = await _loadStockDataSilent(event.stockCode, currentState.stockData);
        final positions = await _loadPositions();
        
        // 업데이트된 데이터로 상태 변경 (깜빡임 없음)
        emit(TradingLoaded(
          stockData: updatedStockData,
          analysisResult: currentState.analysisResult, // 분석 결과는 캐시된 것 사용
          positions: positions,
          isSilentRefresh: false,
        ));
        
        print('✅ TradingBloc: 거래 데이터 새로고침 완료 - ${event.stockCode}');
      }
    } catch (e) {
      print('❌ TradingBloc: 거래 데이터 새로고침 실패 - ${event.stockCode}: $e');
      // 에러 발생 시 기존 상태 유지
    } finally {
      _isRefreshing = false;
    }
  }

  /// 기본 주식 데이터 로드 (초기 로드용)
  Future<Map<String, dynamic>> _loadStockData(String stockCode) async {
    try {
      print('📊 TradingBloc: 종목 데이터 로드 시작 - $stockCode');
      
      // 캐시된 데이터 우선 사용
      final cachedData = _appDataManager.getCachedStockData(stockCode);
      if (cachedData.isNotEmpty) {
        print('📊 TradingBloc: 캐시된 데이터 사용 - $stockCode');
        return cachedData;
      }
      
      print('📊 TradingBloc: API에서 데이터 조회 - $stockCode');
      
      // 확장 API의 자동 판별 메서드 사용
      final stockData = await _unifiedApiService.getStockPriceAuto(stockCode);
      
      if (stockData != null && stockData.isNotEmpty) {
        print('📊 TradingBloc: API 데이터 조회 성공 - $stockCode');
        print('  - 현재가: ${stockData['prpr']}');
        print('  - 시가: ${stockData['open']}');
        print('  - 고가: ${stockData['high']}');
        print('  - 저가: ${stockData['low']}');
        print('  - 거래량: ${stockData['acml_vol']}');
        
        // 캐시에 저장
        _appDataManager.updateCurrentPrice(stockCode, stockData);
        
        return stockData;
      } else {
        print('⚠️ TradingBloc: API 데이터가 비어있음 - $stockCode');
        return {};
      }
    } catch (e) {
      print('❌ TradingBloc: 종목 데이터 로드 실패 - $stockCode: $e');
      return {};
    }
  }

  /// 사일런트 현재가 데이터 로드 (캐시 우선)
  Future<Map<String, dynamic>> _loadStockDataSilent(String stockCode, Map<String, dynamic> currentData) async {
    try {
      print('📊 TradingBloc: 사일런트 현재가 데이터 로드 - $stockCode');
      
      // 1. 캐시된 데이터 우선 확인
      final cachedData = _appDataManager.getCachedStockData(stockCode);
      if (cachedData.isNotEmpty) {
        final cachedPrice = (cachedData['prpr'] ?? 0.0).toDouble();
        final currentPrice = (currentData['prpr'] ?? 0.0).toDouble();
        
        // 캐시된 가격이 유효하고 현재 가격과 다르면 업데이트
        if (cachedPrice > 0 && (cachedPrice - currentPrice).abs() > 0.01) {
          print('📊 TradingBloc: 캐시된 데이터로 업데이트 - $stockCode ($currentPrice → $cachedPrice)');
          return cachedData;
        }
      }
      
      // 2. 확장 API의 자동 판별 메서드 사용
      final stockData = await _unifiedApiService.getStockPriceAuto(stockCode);
      
      if (stockData != null && stockData.isNotEmpty) {
        final newPrice = (stockData['prpr'] ?? 0.0).toDouble();
        final currentPrice = (currentData['prpr'] ?? 0.0).toDouble();
        
        // 가격이 변경된 경우에만 업데이트
        if (newPrice > 0 && (newPrice - currentPrice).abs() > 0.01) {
          print('📊 TradingBloc: API 데이터로 업데이트 - $stockCode ($currentPrice → $newPrice)');
          
          // 캐시에 저장
          _appDataManager.updateCurrentPrice(stockCode, stockData);
          
          return stockData;
        } else {
          print('📊 TradingBloc: 가격 변경 없음 - $stockCode ($currentPrice)');
          return currentData; // 기존 데이터 유지
        }
      } else {
        print('⚠️ TradingBloc: API 데이터 없음 - $stockCode');
        return currentData; // 기존 데이터 유지
      }
    } catch (e) {
      print('❌ TradingBloc: 사일런트 현재가 로드 실패 - $stockCode: $e');
      return currentData; // 에러 시 기존 데이터 유지
    }
  }



  Future<Map<String, dynamic>?> _performAnalysis(String stockCode) async {
    try {
      final currentStyle = _styleManager.currentStyle;
      
      // 1. 현재 시장 데이터 가져오기 (API 우선, 캐시 폴백)
      final stockData = await _loadStockData(stockCode);
      if (stockData.isEmpty) {
        print('❌ TradingBloc: 시장 데이터 없음 - $stockCode');
        return null;
      }
      
      // 2. 명시적 파라미터로 analyzeStock 호출 (추천종목과 동일한 방식)
      // 🔧 모든 화면에서 동일한 데이터 소스 사용: SQL DB 우선 → API 폴백
      return await _unifiedAnalysis.analyzeStock(stockCode, days: 100);
    } catch (e) {
      print('❌ 분석 실패: $e');
      return null;
    }
  }

  /// 보유종목 로드 (국내 + 해외) - 캐시 우선 로드
  Future<List<Map<String, dynamic>>> _loadPositions() async {
    try {
      print('📊 TradingBloc: 보유종목 로드 시작 (캐시 우선)');
      
      // 1. 먼저 캐시된 데이터 확인 (데이터베이스 락 방지)
      final cachedPositions = _appDataManager.positions;
      if (cachedPositions.isNotEmpty) {
        print('📊 TradingBloc: 캐시된 보유종목 사용 - ${cachedPositions.length}개');
        return cachedPositions;
      }
      
      // 2. 캐시가 비어있을 때만 데이터베이스에서 로드
      print('📊 TradingBloc: 캐시가 비어있음 - 데이터베이스에서 로드');
      await _appDataManager.loadPositions();
      final positions = _appDataManager.positions;
      
      print('📊 TradingBloc: 보유종목 로드 완료 - ${positions.length}개');
      
      // 디버깅: 각 보유종목 정보 출력 (API 필드명 사용)
      for (int i = 0; i < positions.length; i++) {
        final pos = positions[i];
        print('  TradingBloc ${i+1}: ${pos['pdno'] ?? pos['stockCode']} - ${pos['prdt_name'] ?? pos['stockName']} (${pos['hldg_qty'] ?? pos['quantity']}주)');
        print('    - 원본 데이터: ${pos.keys.toList()}');
        print('    - 가격 데이터: prpr=${pos['prpr']}, pchs_avg_pric=${pos['pchs_avg_pric']}');
      }
      
      return positions;
    } catch (e) {
      print('❌ TradingBloc: 보유종목 로드 실패: $e');
      // 에러 시 빈 리스트 반환하여 UI 블로킹 방지
      return const [];
    }
  }

  /// 데이터 변경 여부 확인 (깜빡임 방지)
  bool _hasDataChanged(
    TradingLoaded currentState,
    Map<String, dynamic> newStockData,
    Map<String, dynamic>? newAnalysisResult,
  ) {
    try {
      // 주식 데이터 변경 확인
      final currentPrice = currentState.stockData['currentPrice'] ?? 0.0;
      final newPrice = newStockData['currentPrice'] ?? 0.0;
      
      if ((currentPrice - newPrice).abs() > 0.01) {
        return true;
      }
      
      // 분석 결과 변경 확인
      if (currentState.analysisResult != null && newAnalysisResult != null) {
        final currentSignal = currentState.analysisResult?['signal'] ?? '';
        final newSignal = newAnalysisResult['signal'] ?? '';
        
        if (currentSignal != newSignal) {
          return true;
        }
      }
      
      // 보유종목 변경 확인 (길이 기반 간단 체크)
      if (currentState.positions.length != (_appDataManager.positions.length)) {
        return true;
      }
      
      return false;
    } catch (e) {
      // 비교 실패 시 안전하게 true 반환
      return true;
    }
  }

  @override
  Future<void> close() {
    _refreshTimer?.cancel();
    return super.close();
  }
}
