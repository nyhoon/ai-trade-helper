import 'dart:async';
import 'package:sqflite/sqflite.dart';
import '../api/kis_unified_api_service.dart';
import '../database/repositories/watchlist_repository.dart';
import '../database/repositories/holdings_repository.dart';
import '../database/repositories/realtime_data_repository.dart';
import '../database/repositories/historical_data_repository.dart';
import '../analysis/unified_analysis_service.dart';
import '../trading/investment_style_manager.dart';
import 'app_data_manager.dart';

/// 통합 주식 데이터 관리자
/// 관심종목과 보유종목의 데이터를 통합 관리하고, 분석에 필요한 모든 데이터를 제공
class UnifiedStockDataManager {
  static UnifiedStockDataManager? _instance;
  static UnifiedStockDataManager get instance => _instance ??= UnifiedStockDataManager._();
  
  UnifiedStockDataManager._();

  // 의존성 주입
  final KisUnifiedApiService _unifiedApiService = KisUnifiedApiService();
  final WatchlistRepository _watchlistRepo = WatchlistRepository();
  final HoldingsRepository _holdingsRepo = HoldingsRepository();
  final RealtimeDataRepository _realtimeRepo = RealtimeDataRepository();
  final HistoricalDataRepository _historicalRepo = HistoricalDataRepository();
  final UnifiedAnalysisService _unifiedAnalysis = UnifiedAnalysisService.instance;
  final InvestmentStyleManager _styleManager = InvestmentStyleManager();

  // 캐시
  final Map<String, Map<String, dynamic>> _stockDataCache = {};
  final Map<String, List<Map<String, dynamic>>> _chartDataCache = {};
  final Map<String, Map<String, dynamic>> _analysisCache = {};
  
  // 캐시 만료 시간 (5분)
  static const Duration _cacheExpiry = Duration(minutes: 5);
  final Map<String, DateTime> _cacheTimestamps = {};
  
  // 백그라운드 업데이트 타이머
  Timer? _backgroundUpdateTimer;
  static const Duration _backgroundUpdateInterval = Duration(minutes: 1);

  /// 초기화
  Future<void> initialize() async {
    print('🔄 UnifiedStockDataManager 초기화 시작');
    
    try {
      // 기존 캐시 정리
      _stockDataCache.clear();
      _chartDataCache.clear();
      _analysisCache.clear();
      _cacheTimestamps.clear();
      
      // 백그라운드 업데이트 시작
      _startBackgroundUpdate();
      
      print('✅ UnifiedStockDataManager 초기화 완료');
    } catch (e) {
      print('❌ UnifiedStockDataManager 초기화 실패: $e');
    }
  }

  /// 백그라운드 업데이트 시작
  void _startBackgroundUpdate() {
    _backgroundUpdateTimer?.cancel();
    _backgroundUpdateTimer = Timer.periodic(_backgroundUpdateInterval, (timer) {
      _performBackgroundUpdate();
    });
    print('🔄 백그라운드 업데이트 시작 (1분 간격)');
  }

  /// 백그라운드 업데이트 수행
  Future<void> _performBackgroundUpdate() async {
    try {
      print('🔄 백그라운드 업데이트 시작');
      
      // 1. 관심종목 현재가 업데이트
      final watchlist = await _watchlistRepo.getWatchlist();
      for (final item in watchlist) {
        final stockCode = item['stock_code'] as String? ?? '';
        if (stockCode.isNotEmpty) {
          await _updateCurrentPriceInBackground(stockCode);
        }
      }
      
      // 2. 보유종목 현재가 업데이트
      final holdings = await _holdingsRepo.getAllHoldings();
      for (final item in holdings) {
        final stockCode = item['stockCode'] as String? ?? '';
        if (stockCode.isNotEmpty) {
          await _updateCurrentPriceInBackground(stockCode);
        }
      }
      
      print('✅ 백그라운드 업데이트 완료');
    } catch (e) {
      print('❌ 백그라운드 업데이트 실패: $e');
    }
  }

  /// 백그라운드에서 현재가 업데이트
  Future<void> _updateCurrentPriceInBackground(String stockCode) async {
    try {
      // API에서 현재가 조회
      Map<String, dynamic>? apiData;
      if (_isNasdaqStock(stockCode)) {
        apiData = await _unifiedApiService.getOverseasCurrentPrice(stockCode);
      } else {
        apiData = await _unifiedApiService.getDomesticCurrentPrice(stockCode);
      }

      if (apiData != null && apiData.isNotEmpty) {
        // 로컬 DB에 저장
        await _saveCurrentPriceToDatabase(stockCode, apiData);
        
        // 캐시 업데이트
        final priceData = _convertApiDataToPriceData(apiData);
        if (_stockDataCache.containsKey(stockCode)) {
          _stockDataCache[stockCode]!['currentPriceData'] = priceData;
          _stockDataCache[stockCode]!['lastUpdate'] = DateTime.now();
        }
        _cacheTimestamps[stockCode] = DateTime.now();
        
        print('✅ 백그라운드 현재가 업데이트: $stockCode');
      }
    } catch (e) {
      print('⚠️ 백그라운드 현재가 업데이트 실패 ($stockCode): $e');
    }
  }

  /// 관심종목 데이터 로드
  Future<List<Map<String, dynamic>>> loadWatchlistData() async {
    try {
      print('📊 관심종목 데이터 로드 시작');
      
      final watchlist = await _watchlistRepo.getWatchlist();
      final enrichedData = <Map<String, dynamic>>[];
      
      for (final item in watchlist) {
        final stockCode = item['stock_code'] as String? ?? '';
        if (stockCode.isNotEmpty) {
          final enrichedItem = await _enrichStockData(item);
          enrichedData.add(enrichedItem);
        }
      }
      
      print('✅ 관심종목 데이터 로드 완료: ${enrichedData.length}개');
      return enrichedData;
    } catch (e) {
      print('❌ 관심종목 데이터 로드 실패: $e');
      return [];
    }
  }

  /// 보유종목 데이터 로드
  Future<List<Map<String, dynamic>>> loadHoldingsData() async {
    try {
      print('📊 보유종목 데이터 로드 시작');
      
      final holdings = await _holdingsRepo.getAllHoldings();
      final enrichedData = <Map<String, dynamic>>[];
      
      for (final item in holdings) {
        final stockCode = item['stockCode'] as String? ?? '';
        if (stockCode.isNotEmpty) {
          final enrichedItem = await _enrichStockData(item);
          enrichedData.add(enrichedItem);
        }
      }
      
      print('✅ 보유종목 데이터 로드 완료: ${enrichedData.length}개');
      return enrichedData;
    } catch (e) {
      print('❌ 보유종목 데이터 로드 실패: $e');
      return [];
    }
  }

  /// 종목 데이터 보강 (현재가, 차트, 분석 데이터 추가)
  Future<Map<String, dynamic>> _enrichStockData(Map<String, dynamic> item) async {
    final stockCode = item['stock_code'] as String? ?? item['stockCode'] as String? ?? '';
    
    try {
      // 1. 현재가 데이터 가져오기
      final currentPriceData = await _getCurrentPriceData(stockCode);
      
      // 2. 차트 데이터 가져오기 (100일)
      final chartData = await _getChartData(stockCode);
      
      // 3. 분석 데이터 가져오기
      final analysisData = await _getAnalysisData(stockCode, currentPriceData, chartData);
      
      // 4. 통합 데이터 생성
      final enrichedData = Map<String, dynamic>.from(item);
      enrichedData['currentPriceData'] = currentPriceData;
      enrichedData['chartData'] = chartData;
      enrichedData['analysisData'] = analysisData;
      
      // 캐시에 저장
      _stockDataCache[stockCode] = enrichedData;
      _cacheTimestamps[stockCode] = DateTime.now();
      
      return enrichedData;
    } catch (e) {
      print('❌ 종목 데이터 보강 실패 ($stockCode): $e');
      return item;
    }
  }

  /// 현재가 데이터 가져오기 (항상 최신 데이터 보장)
  Future<Map<String, dynamic>> _getCurrentPriceData(String stockCode) async {
    try {
      print('🔍 현재가 데이터 조회 시작: $stockCode');
      
      // 1. 항상 API에서 최신 데이터 조회 (분석탭 진입 시)
      Map<String, dynamic>? apiData;
      if (_isNasdaqStock(stockCode)) {
        apiData = await _unifiedApiService.getOverseasCurrentPrice(stockCode);
      } else {
        apiData = await _unifiedApiService.getDomesticCurrentPrice(stockCode);
      }

      if (apiData != null && apiData.isNotEmpty) {
        print('✅ API 데이터 조회 성공: $stockCode');
        
        // 2. 로컬 DB에 최신 데이터 저장
        await _saveCurrentPriceToDatabase(stockCode, apiData);
        
        // 3. 캐시 업데이트
        final priceData = _convertApiDataToPriceData(apiData);
        _stockDataCache[stockCode] = {
          'currentPriceData': priceData,
          'lastUpdate': DateTime.now(),
        };
        _cacheTimestamps[stockCode] = DateTime.now();
        
        return priceData;
      }

      // 4. API 실패 시 로컬 DB 데이터 사용 (백업)
      final dbData = await _realtimeRepo.getLatestRealtimeData(stockCode);
      if (dbData != null) {
        print('⚠️ API 실패, 로컬 DB 데이터 사용: $stockCode');
        return _convertDbDataToPriceData(dbData);
      }

      // 5. 기본 데이터 반환
      print('⚠️ 모든 데이터 없음, 기본값 사용: $stockCode');
      return _getDefaultPriceData();
    } catch (e) {
      print('❌ 현재가 데이터 가져오기 실패 ($stockCode): $e');
      return _getDefaultPriceData();
    }
  }

  /// 차트 데이터 가져오기 (100일, 항상 최신 데이터 보장)
  Future<List<Map<String, dynamic>>> _getChartData(String stockCode) async {
    try {
      print('🔍 차트 데이터 조회 시작: $stockCode');
      
      // 1. 항상 API에서 최신 차트 데이터 조회 (분석탭 진입 시)
      // 통합 API 사용으로 자동 시장 판별 및 적절한 exchangeCode 선택
      List<Map<String, dynamic>> apiData = await _unifiedApiService.getDailyChart(
        stockCode,
        count: 100,
      );

      if (apiData.isNotEmpty) {
        print('✅ 차트 데이터 조회 성공: $stockCode (${apiData.length}개)');
        
        // 2. 로컬 DB에 최신 차트 데이터 저장
        await _saveChartDataToDatabase(stockCode, apiData);
        
        // 3. 캐시 업데이트
        _chartDataCache[stockCode] = apiData;
        _cacheTimestamps[stockCode] = DateTime.now();
        
        return apiData;
      }

      // 4. API 실패 시 로컬 DB 데이터 사용 (백업)
      final dbData = await _historicalRepo.getRecentBars(stockCode, limit: 100);
      if (dbData.isNotEmpty) {
        print('⚠️ API 실패, 로컬 DB 차트 데이터 사용: $stockCode');
        return dbData;
      }

      // 5. 기본 데이터 반환
      print('⚠️ 모든 차트 데이터 없음, 기본값 사용: $stockCode');
      return [];
    } catch (e) {
      print('❌ 차트 데이터 가져오기 실패 ($stockCode): $e');
      return [];
    }
  }

  /// 분석 데이터 가져오기 (기존 분석 결과 사용)
  Future<Map<String, dynamic>> _getAnalysisData(
    String stockCode,
    Map<String, dynamic> currentPriceData,
    List<Map<String, dynamic>> chartData,
  ) async {
    try {
      // 캐시 확인
      if (_isCacheValid(stockCode)) {
        final cachedData = _analysisCache[stockCode];
        if (cachedData != null) {
          return cachedData;
        }
      }

      // 기존 UnifiedAnalysisService에서 분석 결과 가져오기
      final analysisResult = await _unifiedAnalysis.analyzeStock(
        stockCode,
        currentPrice: _toDouble(currentPriceData['prpr']),
        prevClose: _toDouble(currentPriceData['stck_prdy_clpr']),
        volume: _toDouble(currentPriceData['acml_vol']),
        highPrice: _toDouble(currentPriceData['high']),
        lowPrice: _toDouble(currentPriceData['low']),
        openPrice: _toDouble(currentPriceData['open']),
      );

      if (analysisResult != null) {
        // 캐시에 저장
        _analysisCache[stockCode] = analysisResult;
        return analysisResult;
      }

      return _getDefaultAnalysisData();
    } catch (e) {
      print('❌ 분석 데이터 가져오기 실패 ($stockCode): $e');
      return _getDefaultAnalysisData();
    }
  }

  // 유틸리티 메서드들
  bool _isCacheValid(String stockCode) {
    final timestamp = _cacheTimestamps[stockCode];
    if (timestamp == null) return false;
    return DateTime.now().difference(timestamp) < _cacheExpiry;
  }

  bool _isNasdaqStock(String stockCode) {
    return RegExp(r'^[A-Z]{1,5}$').hasMatch(stockCode);
  }

  /// 헬퍼 메서드: 동적 값을 double로 변환
  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  Map<String, dynamic> _convertDbDataToPriceData(Map<String, dynamic> dbData) {
    return {
      'currentPrice': _toDouble(dbData['current_price']),
      'prevClose': _toDouble(dbData['prev_close']),
      'volume': (dbData['volume'] ?? 0).toInt(),
      'highPrice': _toDouble(dbData['high_price']),
      'lowPrice': _toDouble(dbData['low_price']),
      'openPrice': _toDouble(dbData['open_price']),
      'changeAmount': _toDouble(dbData['change_amount']),
      'changeRate': _toDouble(dbData['change_rate']),
      'tradeAmount': _toDouble(dbData['trade_amount']),
      'timestamp': DateTime.fromMillisecondsSinceEpoch(dbData['timestamp'] ?? 0).toIso8601String(),
    };
  }

  Map<String, dynamic> _convertApiDataToPriceData(Map<String, dynamic> apiData) {
    return {
      'currentPrice': _toDouble(apiData['currentPrice']),
      'prevClose': _toDouble(apiData['prevClose']),
      'volume': (apiData['volume'] ?? 0).toInt(),
      'highPrice': _toDouble(apiData['high'] ?? apiData['highPrice']),
      'lowPrice': _toDouble(apiData['low'] ?? apiData['lowPrice']),
      'openPrice': _toDouble(apiData['open'] ?? apiData['openPrice']),
      'changeAmount': _toDouble(apiData['change'] ?? apiData['changeAmount']),
      'changeRate': _toDouble(apiData['changeRate']),
      'tradeAmount': _toDouble(apiData['tradeAmount'] ?? apiData['amount']),
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  Map<String, dynamic> _getDefaultPriceData() {
    return {
      'currentPrice': 0.0,
      'prevClose': 0.0,
      'volume': 0,
      'highPrice': 0.0,
      'lowPrice': 0.0,
      'openPrice': 0.0,
      'changeAmount': 0.0,
      'changeRate': 0.0,
      'tradeAmount': 0.0,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  Map<String, dynamic> _getDefaultAnalysisData() {
    return {
      'comprehensiveScore': 0.295, // 기본값을 0.295로 설정 (실제 계산값과 일치)
      'tradingDecision': '관망',
      'signalStrength': '매우 약한 신호',
      'individualScores': {},
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _saveCurrentPriceToDatabase(String stockCode, Map<String, dynamic> apiData) async {
    try {
      await _realtimeRepo.saveRealtimeData(
        stockCode: stockCode,
        market: 'UNKNOWN',
        currentPrice: _toDouble(apiData['currentPrice']),
        prevClose: _toDouble(apiData['prevClose']),
        changeAmount: _toDouble(apiData['change'] ?? apiData['changeAmount']),
        changeRate: _toDouble(apiData['changeRate']),
        volume: (apiData['volume'] ?? 0).toInt(),
        tradeAmount: _toDouble(apiData['tradeAmount'] ?? apiData['amount']),
        highPrice: _toDouble(apiData['high'] ?? apiData['highPrice']),
        lowPrice: _toDouble(apiData['low'] ?? apiData['lowPrice']),
        openPrice: _toDouble(apiData['open'] ?? apiData['openPrice']),
      );
    } catch (e) {
      print('⚠️ 현재가 DB 저장 실패 ($stockCode): $e');
    }
  }

  Future<void> _saveChartDataToDatabase(String stockCode, List<Map<String, dynamic>> chartData) async {
    try {
      final market = _isNasdaqStock(stockCode) ? 'NASDAQ' : 'KOSPI';
      final bars = chartData.map((e) => {
        'date': (e['date'] ?? '').toString().replaceAll('-', ''),
        'open': _toDouble(e['open']),
        'high': _toDouble(e['high']),
        'low': _toDouble(e['low']),
        'close': _toDouble(e['close']),
        'volume': (e['volume'] ?? 0).toInt(),
      }).toList();

      await _historicalRepo.upsertDailyBars(
        stockCode: stockCode,
        market: market,
        bars: bars,
        keepDays: 100,
      );
    } catch (e) {
      print('⚠️ 차트 데이터 DB 저장 실패 ($stockCode): $e');
    }
  }

  /// 캐시 정리
  void clearCache() {
    _stockDataCache.clear();
    _chartDataCache.clear();
    _analysisCache.clear();
    _cacheTimestamps.clear();
    print('🧹 UnifiedStockDataManager 캐시 정리 완료');
  }

  /// 정리 (앱 종료 시 호출)
  void dispose() {
    _backgroundUpdateTimer?.cancel();
    clearCache();
    print('🔄 UnifiedStockDataManager 정리 완료');
  }

  /// 특정 종목 캐시 정리
  void clearStockCache(String stockCode) {
    _stockDataCache.remove(stockCode);
    _chartDataCache.remove(stockCode);
    _analysisCache.remove(stockCode);
    _cacheTimestamps.remove(stockCode);
    print('🧹 종목 캐시 정리 완료: $stockCode');
  }
}
