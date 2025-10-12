import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/app_data_manager.dart';
import '../analysis/unified_analysis_service.dart';
import '../trading/investment_style_manager.dart';
import '../trading/investment_style.dart';
import '../api/unified_stock_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/firestore_stock_service.dart';

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
  // 서버 전환: 통일API 제거
  final UnifiedAnalysisService _unifiedAnalysis = UnifiedAnalysisService.instance;
  final InvestmentStyleManager _styleManager = InvestmentStyleManager();
  
  Timer? _refreshTimer;
  bool _isRefreshing = false;


  TradingBloc({
    required AppDataManager appDataManager,
  }) : _appDataManager = appDataManager,
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
      
      // Firestore에서 직접 데이터 조회 (서버 저장된 데이터 사용)
      final stockData = await FirestoreStockService.getStockData(stockCode);
      if (stockData != null && stockData.isNotEmpty) {
        final currentPrice = stockData['current'] as Map<String, dynamic>?;
        if (currentPrice != null && currentPrice.isNotEmpty) {
          print('📊 TradingBloc: Firestore 데이터 사용 - $stockCode');
          // 표준 스키마로 정규화 후 반환
          return _normalizePriceData(stockCode, currentPrice);
        }
      }
      
      // Firestore 구독으로 대체되므로 직접 API 호출 비활성화
      print('📊 TradingBloc: 직접 API 호출 비활성화 - Firestore 구독 사용 - $stockCode');
      
      // 캐시된 데이터가 있으면 사용
      final cachedData = _appDataManager.getCachedStockData(stockCode);
      if (cachedData.isNotEmpty) {
        print('📊 TradingBloc: 캐시된 데이터 사용 - $stockCode');
        return _normalizePriceData(stockCode, cachedData);
      }
      
      print('⚠️ TradingBloc: 캐시된 데이터 없음 - $stockCode');
      return {};
    } catch (e) {
      print('❌ TradingBloc: 종목 데이터 로드 실패 - $stockCode: $e');
      return {};
    }
  }

  /// 사일런트 현재가 데이터 로드 (캐시 우선)
  Future<Map<String, dynamic>> _loadStockDataSilent(String stockCode, Map<String, dynamic> currentData) async {
    try {
      print('📊 TradingBloc: 사일런트 현재가 데이터 로드 - $stockCode');
      
      // 1. 캐시된 데이터 우선 확인 (거래량도 함께 확인)
      final cachedData = _appDataManager.getCachedStockData(stockCode);
      if (cachedData.isNotEmpty) {
        final cachedNorm = _normalizePriceData(stockCode, cachedData);
        final currentNorm = _normalizePriceData(stockCode, currentData);
        
        final cachedPrice = (cachedNorm['currentPrice'] as num?)?.toDouble() ?? 0.0;
        final currentPrice = (currentNorm['currentPrice'] as num?)?.toDouble() ?? 0.0;
        final cachedVolume = (cachedNorm['volume'] as num?)?.toDouble() ?? 0.0;
        final currentVolume = (currentNorm['volume'] as num?)?.toDouble() ?? 0.0;
        
        // 가격 또는 거래량이 변경된 경우 업데이트
        final priceChanged = cachedPrice > 0 && (cachedPrice - currentPrice).abs() > 0.01;
        final volumeChanged = cachedVolume > 0 && (cachedVolume - currentVolume).abs() > 0.01;
        
        if (priceChanged || volumeChanged) {
          print('📊 TradingBloc: 캐시된 데이터로 업데이트 - $stockCode (가격: $priceChanged, 거래량: $volumeChanged)');
          return cachedNorm;
        }
      }
      
      // 2. Firestore 구독으로 대체되므로 직접 API 호출 비활성화
      print('📊 TradingBloc: 사일런트 API 호출 비활성화 - Firestore 구독 사용 - $stockCode');
      
      // 기존 데이터 유지
      return _normalizePriceData(stockCode, currentData);
    } catch (e) {
      print('❌ TradingBloc: 사일런트 현재가 로드 실패 - $stockCode: $e');
      return _normalizePriceData(stockCode, currentData); // 에러 시 기존 데이터 유지(정규화)
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

  /// 현재가 응답/캐시를 표준 스키마로 정규화 (int/double 안전 변환, 키 통일)
  Map<String, dynamic> _normalizePriceData(String stockCode, Map<String, dynamic> raw) {
    try {
      if (raw.isEmpty) return {};
      double _asDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;
      int _asInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

      final cp = _asDouble(raw['currentPrice'] ?? raw['prpr']);
      final pc = _asDouble(raw['prevClose'] ?? raw['stck_prdy_clpr']);
      final op = _asDouble(raw['open'] ?? raw['openPrice'] ?? raw['stck_oprc']);
      final hp = _asDouble(raw['high'] ?? raw['highPrice'] ?? raw['stck_hgpr']);
      final lp = _asDouble(raw['low'] ?? raw['lowPrice'] ?? raw['stck_lwpr']);
      final vol = _asInt(raw['volume'] ?? raw['acml_vol']);

      // 변동액/변동률: 서버 응답(change_amount/change_rate) 우선 → 계산 폴백
      double diff = _asDouble(raw['diff']);
      double rate = _asDouble(raw['rate']);
      if (diff == 0.0 && raw.containsKey('changeAmount')) {
        diff = _asDouble(raw['changeAmount']);
      }
      if (rate == 0.0 && raw.containsKey('changeRate')) {
        rate = _asDouble(raw['changeRate']);
      }
      if ((diff == 0.0 || rate == 0.0) && pc > 0.0 && cp > 0.0) {
        final calculatedDiff = cp - pc;
        final calculatedRate = (calculatedDiff / pc) * 100.0;
        if (diff == 0.0) diff = calculatedDiff;
        if (rate == 0.0) rate = calculatedRate;
      }
      final name = (raw['stockName'] ?? raw['hts_kor_isnm'] ?? '').toString();

      // UI 호환: currentPrice/prpr 모두 제공, openPrice/highPrice/lowPrice 포함
      return {
        'stock_code': stockCode,
        'stockName': name,
        'currentPrice': cp,
        'prpr': cp,
        'prevClose': pc,
        // 거래탭에서 기대하는 키들(구 키 호환)
        'open': op,
        'high': hp,
        'low': lp,
        'diff': diff,
        'rate': rate,
        'openPrice': op,
        'highPrice': hp,
        'lowPrice': lp,
        // 구 키 호환(차트/기존 위젯)
        'stck_prdy_clpr': pc,
        'stck_oprc': op,
        'stck_hgpr': hp,
        'stck_lwpr': lp,
        'volume': vol,
        'timestamp': raw['timestamp'] ?? DateTime.now().toIso8601String(),
      };
    } catch (_) {
      return raw;
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
