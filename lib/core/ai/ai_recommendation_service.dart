import 'dart:async';
import 'dart:convert';
import '../analysis/unified_analysis_service.dart';
import '../data/recommended_stocks_data.dart';
import '../database/repositories/historical_data_repository.dart';
import '../database/repositories/current_price_repository.dart';
import '../database/repositories/holdings_repository.dart';
import '../database/repositories/recommended_stocks_repository.dart';
import '../data/app_data_manager.dart';
import '../api/kis_unified_api_service.dart';
import '../constants/chart_constants.dart';
import '../trading/investment_style.dart';
import '../trading/investment_style_manager.dart';
import '../services/local_notification_manager.dart';

/// AI 추천 서비스
///
/// - 자동매매와 동일한 7개 동적 지표 기반 종합점수 로직을 사용합니다.
/// - 스플래시 종료 후 메인 진입 시 백그라운드로 시작되며 15분 주기로 전체 분석을 수행합니다.
/// - 분석 대상은 `RecommendedStocksData.getAllStocks()`에서 제공하는 전체 목록(기본 ≈409개)입니다.
/// - 진행률 콜백을 통해 UI에 현재 종목(symbol, name)과 진행 상태(current/total)를 전달합니다.
/// - 추천 화면에서는 저장된 결과가 없을 때 강제 전체 스캔을 수행하여 초기 진입 UX를 보장합니다.
/// - 단방향 데이터 흐름: 분석 → 점수 저장 → 화면 조회. 화면은 분석을 직접 수행하지 않습니다.
///
/// MVI & Clean Architecture 준수:
/// - Intent(사용자 액션: 새로고침/추천 탭 진입) → Service(UseCase 역할) → Data(Repository) → ViewState(표시)
/// - 불필요한 상태 공유/전역 변경을 피하고, 진행률은 콜백으로만 노출합니다.
class AiRecommendationService {
  static final AiRecommendationService _instance = AiRecommendationService._internal();
  factory AiRecommendationService() => _instance;
  AiRecommendationService._internal();

  // 일봉 최소 확보 개수 (전 구간 공통)
  static const int CHART_MIN_BARS = 80;

  bool _isInitialized = false;
  bool _isInitialDataCollected = false;
  Timer? _updateTimer;
  bool _isUpdating = false;
  bool _isWarmupRunning = false;
  bool _isUserScanRunning = false; // 사용자가 강제 스캔 실행 중인지 여부 (재진입 방지)
  bool _isScannerRunning = false;
  
  // 실제 분석 서비스 사용 (자동매매와 동일)
  final UnifiedAnalysisService _unifiedAnalysis = UnifiedAnalysisService.instance;
  final RecommendedStocksData _recommendedStocksData = RecommendedStocksData();
  final HistoricalDataRepository _historicalDataRepo = HistoricalDataRepository();
  final CurrentPriceRepository _currentPriceRepo = CurrentPriceRepository();
  final HoldingsRepository _holdingsRepo = HoldingsRepository();
  final InvestmentStyleManager _styleManager = InvestmentStyleManager();
  
  // 시장 판별 캐시 (중복 연산/로그 억제)
  final Map<String, String> _marketCache = <String, String>{};
  final Set<String> _marketLogOnce = <String>{};
  
  // 통일된 API 서비스
  final KisUnifiedApiService _unifiedApiService = KisUnifiedApiService();

  final RecommendedStocksRepository _recommendedStocksRepo = RecommendedStocksRepository();
  final LocalNotificationManager _notifier = LocalNotificationManager();

  // 진행률 콜백 (UI 업데이트용)
  Function(int current, int total, String symbol, String name)? _onProgressUpdate;

  /// 진행률 콜백 설정
  void setProgressCallback(Function(int current, int total, String symbol, String name) callback) {
    _onProgressUpdate = callback;
  }

  String _resolveMarketOnce(String symbol) {
    final cached = _marketCache[symbol];
    if (cached != null) return cached;
    final market = _getMarketFromSymbol(symbol);
    _marketCache[symbol] = market;
    // 심볼당 1회만 시장 판별 로그
    if (!_marketLogOnce.contains(symbol)) {
      _marketLogOnce.add(symbol);
      // 필요하면 여기서만 1회 로깅
      // print('🔎 [AI 추천] 시장 판별: $symbol -> $market');
    }
    return market;
  }

  // NOTE: 기존 구현 존재. 중복 선언 방지를 위해 삭제됩니다.

  /// 특정 종목에 대해 즉시 점수를 계산하고 저장 (요청형 보정)
  Future<bool> computeAndSaveScore(String symbol) async {
    try {
      final scoreResult = await _calculateComprehensiveScore(symbol);
      if (scoreResult is Map<String, dynamic>) {
        final double price = scoreResult['price'] as double? ?? 0.0;
        final double score = scoreResult['score'] as double? ?? 0.0;
        final market = _resolveMarketOnce(symbol);
        await _recommendedStocksData.updateStockScore(symbol, score, metadata: {
          'price': price,
          'market': market,
          'timestamp': DateTime.now().toIso8601String(),
        });
        print('✅ [AI 추천] 즉시 점수 저장: $symbol score=$score price=$price');
        return true;
      }
      return false;
    } catch (e) {
      print('❌ [AI 추천] 즉시 점수 저장 실패: $symbol - $e');
      return false;
    }
  }

  /// 간단한 지수 백오프 재시도 헬퍼 (API 500 등 일시 오류 대응)
  Future<T> _retry<T>(Future<T> Function() action, {int retries = 3, Duration initialDelay = const Duration(milliseconds: 400)}) async {
    Duration delay = initialDelay;
    for (int attempt = 0; attempt < retries; attempt++) {
      try {
        return await action();
      } catch (e) {
        if (attempt == retries - 1) rethrow;
        await Future.delayed(delay);
        delay = Duration(milliseconds: (delay.inMilliseconds * 2).clamp(400, 4000));
      }
    }
    // Unreachable, but required by Dart type system
    // ignore: dead_code
    throw Exception('Retry failed');
  }

  /// 추천종목 화면 진입 시 전체 스캔 트리거 API
  Future<List<Map<String, dynamic>>> refreshRecommendationsFullScan() async {
    try {
      // 저장 일관성을 위해 시작 시 기존 점수 초기화
      if (_isUserScanRunning) {
        print('⏳ [AI 추천] 사용자 스캔이 이미 실행 중입니다. 중복 호출 건너뛰');
        final saved = await _getTop10Recommendations(forceScan: false);
        return saved;
      }
      
      _isUserScanRunning = true;
      print('🖱️ [AI 추천] 사용자 요청으로 전체 스캔 시작');
      
      try {
        // 1. RecommendedStocksData에서 기존 400개+ 종목 목록 가져오기
        print('📡 [AI 추천] RecommendedStocksData에서 종목 목록 조회...');
        final existingStocks = await _recommendedStocksData.getAllStocks();
        print('✅ [AI 추천] 기존 종목 목록 조회 완료: ${existingStocks.length}개');
        
        // 2. 초기 진행 상태를 명시적으로 통지 (0/N)
        try {
          final countInit = await _getTopStocks();
          _onProgressUpdate?.call(0, countInit.length, '', '');
        } catch (_) {}
        
        // 3. 전체 분석 수행
        final result = await _getTop10Recommendations(forceScan: true);
        print('🖱️ [AI 추천] 전체 스캔 완료: ${result.length}개');
        return result;
        
      } finally {
        _isUserScanRunning = false;
      }
      
    } catch (e) {
      print('❌ [AI 추천] 전체 스캔 실패: $e');
      _isUserScanRunning = false;
      return [];
    }
  }

  /// 앱 진입 시 15분에 걸쳐 천천히 초기 데이터 수집
  void _startPacedWarmup({required Duration duration}) {
    if (_isWarmupRunning || _isInitialDataCollected) return;
    _isWarmupRunning = true;
    Future<void>(() async {
      try {
        final allStocks = await _getTopStocks();
        if (allStocks.isEmpty) {
          _isWarmupRunning = false;
          return;
        }
        final total = allStocks.length;
        final perItemMs = duration.inMilliseconds ~/ (total > 0 ? total : 1);
        final delayMs = perItemMs.clamp(200, 3000);
        print('🕒 [AI 추천] 워밍업 시작: '+total.toString()+'종목, 약 '+delayMs.toString()+'ms 간격');
        for (int i = 0; i < total; i++) {
          final stock = allStocks[i];
          final symbol = stock['symbol']!;
          await _collectChartDataForStock(symbol);
          _onProgressUpdate?.call(i + 1, total, symbol, stock['name']!);
          if (i < total - 1) {
            await Future.delayed(Duration(milliseconds: delayMs));
          }
        }
        _isInitialDataCollected = true;
        print('✅ [AI 추천] 워밍업 완료: '+total.toString()+'개 종목');
        await _updateBackgroundAnalysis();
      } catch (e) {
        print('❌ [AI 추천] 워밍업 실패: $e');
      } finally {
        _isWarmupRunning = false;
      }
    });
  }

  /// 서비스 초기화 (자동 시작/워밍업/주기 타이머 비활성화)
  Future<void> initialize() async {
    try {
      if (_isInitialized) return;
      
      print('🤖 AI 추천 서비스 초기화 시작...');
      // 자동 주기/워밍업은 비활성화. 사용자가 추천 화면에서 명시적으로 실행할 때만 동작
      
      _isInitialized = true;
      print('✅ AI 추천 서비스 초기화 완료');
    } catch (e) {
      print('❌ AI 추천 서비스 초기화 실패: $e');
      rethrow;
    }
  }

  // 주기 타이머/워밍업 관련 메서드는 더 이상 호출되지 않습니다.

  /// 주기적 업데이트 수행 (15분마다)
  Future<void> _performPeriodicUpdate() async {
    // 사용 안함 (자동 주기 업데이트 비활성화)
  }

  /// 스플래시 후 백그라운드에서 409개 종목 차트 데이터 수집 (한 번만)
  Future<void> startInitialDataCollection() async {
    // 사용 안함 (초기 대량 수집 비활성화)
  }

  /// 개별 종목의 차트 데이터 수집 및 로컬DB 저장
  Future<void> _collectChartDataForStock(String symbol) async {
    try {
      // 이미 수집된 데이터가 있는지 확인 (60개 미만이면 재수집)
      final existingData = await _historicalDataRepo.getRecentBars(symbol, limit: ChartConstants.CHART_MIN_BARS);
      print('📊 [AI 추천] $symbol 기존 차트 데이터 개수: ${existingData.length}개');
      
      if (existingData.length >= ChartConstants.CHART_MIN_BARS) {
        print('📊 [AI 추천] $symbol 충분한 차트 데이터 존재 (${existingData.length}개), 건너뛰기');
        return;
      }
      
      if (existingData.isNotEmpty) {
        print('⚠️ [AI 추천] $symbol 차트 데이터 부족 (${existingData.length}개 < '+ChartConstants.CHART_MIN_BARS.toString()+'개), 재수집 필요');
      }
      
      // API에서 차트 데이터 조회 (재시도 포함)
      final chartData = await _retry(() {
        final market = _getMarketFromSymbol(symbol);
        if (market == 'NASDAQ') {
          // 분석/자동매매와 동일한 해외 전용 API 사용 (통일된 API 서비스)
          return _unifiedApiService.getOverseasDailyChart(symbol: symbol, exchangeCode: 'NAS', count: ChartConstants.CHART_MIN_BARS);
        }
        // 국내: 일별 차트 60개 강제 확보
        return _fetchDomesticDailyChartData(symbol, minCount: ChartConstants.CHART_MIN_BARS);
      });
      
      if (chartData.isNotEmpty) {
        // 0.0 값 필터링 및 데이터 검증
        final validChartData = chartData.where((data) {
          final open = (data['open'] ?? 0.0).toDouble();
          final high = (data['high'] ?? 0.0).toDouble();
          final low = (data['low'] ?? 0.0).toDouble();
          final close = (data['close'] ?? 0.0).toDouble();
          
          // 0.0 값이 있거나 유효하지 않은 데이터 제외
          if (open <= 0 || high <= 0 || low <= 0 || close <= 0) {
            print('⚠️ [AI 추천] $symbol 유효하지 않은 차트 데이터 제외: open=$open, high=$high, low=$low, close=$close');
            return false;
          }
          
          // OHLC 관계 검증
          if (high < low || high < open || high < close || low > open || low > close) {
            print('⚠️ [AI 추천] $symbol OHLC 관계 오류 데이터 제외: open=$open, high=$high, low=$low, close=$close');
            return false;
          }
          
          return true;
        }).toList();
        
        if (validChartData.isEmpty) {
          print('❌ [AI 추천] $symbol 유효한 차트 데이터 없음, 저장 건너뛰기');
          return;
        }
        
        print('📊 [AI 추천] $symbol 유효한 차트 데이터: ${validChartData.length}개 (전체: ${chartData.length}개)');
        
        // 로컬DB에 저장
        final formattedData = validChartData.map((data) => {
          'stock_code': symbol,
          'market': _getMarketFromSymbol(symbol),
          'date': data['date'] ?? DateTime.now().toIso8601String().split('T')[0],
          'open': (data['open'] ?? 0.0).toDouble(),
          'high': (data['high'] ?? 0.0).toDouble(),
          'low': (data['low'] ?? 0.0).toDouble(),
          'close': (data['close'] ?? 0.0).toDouble(),
          'volume': (data['volume'] ?? 0).toInt(),
          'trade_amount': data['trade_amount'],
        }).toList();
        
        await _historicalDataRepo.upsertDailyBars(
          stockCode: symbol,
          market: _resolveMarketOnce(symbol),
          bars: formattedData,
        );
        
        print('💾 [AI 추천] $symbol 차트 데이터 저장 완료: ${chartData.length}개');
      }
      
    } catch (e) {
      print('❌ [AI 추천] $symbol 차트 데이터 수집 실패: $e');
    }
  }

  /// 국내 일봉 60개 이상 강제 확보를 위한 보조 수집 함수
  Future<List<Map<String, dynamic>>> _fetchDomesticDailyChartData(
    String symbol, {
    int minCount = CHART_MIN_BARS,
  }) async {
    try {
      // 1차 시도: 표준 일봉 API (통일된 API 서비스)
      List<Map<String, dynamic>> data = await _retry(
        () => _unifiedApiService.getDomesticDailyChart(stockCode: symbol, count: minCount),
        retries: 3,
        initialDelay: const Duration(milliseconds: 300),
      );
      if (data.length >= minCount) return data;

      // 2차 시도: Raw API 대체 호출 (폴백용 - 통일된 API 서비스 실패 시에만 사용)
      final raw = await _retry(
        () => _unifiedApiService.getDomesticDailyChart(stockCode: symbol, count: minCount),
        retries: 3,
        initialDelay: const Duration(milliseconds: 300),
      );
      if (raw.isNotEmpty && data.isEmpty) data = raw;

      // 정렬 및 중복 제거 (최신 minCount개만 유지)
      if (data.isNotEmpty) {
        data.sort((a, b) => (a['date'] ?? '').toString().compareTo((b['date'] ?? '').toString()));
        final seen = <String>{};
        data = data.reversed.where((e) {
          final d = (e['date'] ?? '').toString();
          if (d.isEmpty || seen.contains(d)) return false;
          seen.add(d);
          return true;
        }).take(minCount).toList().reversed.toList();
      }

      print('📊 [AI 추천] '+symbol+' 국내 일봉 확보: '+data.length.toString()+'개 (요청: '+minCount.toString()+')');
      return data;
    } catch (e) {
      print('❌ [AI 추천] 국내 일봉 확보 실패 ('+symbol+'): '+e.toString());
      return [];
    }
  }

  /// 백그라운드에서 409개 종목 분석 (자동매매와 동일한 방식)
  Future<void> _updateBackgroundAnalysis() async {
    try {
      print('🤖 백그라운드 종목 분석 시작 (자동매매와 동일한 로직)...');
      
      // 추천종목 데이터에서 모든 종목 조회 (409개)
      final allStocks = await _getTopStocks();
      
      // 각 종목의 종합점수 계산 (자동매매와 동일한 7개 지표)
      final stockScores = <Map<String, dynamic>>[];
      
      for (int i = 0; i < allStocks.length; i++) {
        final stock = allStocks[i];
        final symbol = stock['symbol']!;
        
        final progress = ((i + 1) / allStocks.length * 100).toStringAsFixed(1);
        print('📊 [AI 추천] 분석 진행률: ${i + 1}/${allStocks.length} ($progress%) - $symbol');
        // 진행률 콜백 전달 (UI 진척도 표시용)
        _onProgressUpdate?.call(i + 1, allStocks.length, symbol, stock['name']!);
        
        final scoreResult = await _calculateComprehensiveScore(symbol);
        if (scoreResult is Map<String, dynamic>) {
          final score = scoreResult['score'] as double;
          final price = scoreResult['price'] as double;
          
          // 음수 점수도 저장/표시: 분석/자동매매와 동일 동작
          stockScores.add({
            'symbol': stock['symbol'],
            'name': stock['name'],
            'comprehensiveScore': score,
            'market': stock['market'] ?? _getMarketFromSymbol(stock['symbol']!),
            'price': price,
            'timestamp': DateTime.now().toIso8601String(),
          });
          
          // 개별 종목의 점수 정보를 저장 (가격/시장/타임스탬프 포함)
          await _recommendedStocksData.updateStockScore(stock['symbol']!, score, metadata: {
            'price': price,
            'market': stock['market'] ?? _getMarketFromSymbol(stock['symbol']!),
            'timestamp': DateTime.now().toIso8601String(),
          });
        }
        
        // API 호출 간격 조절 (과도한 호출 방지)
        if (i < allStocks.length - 1) {
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }
      
      // 종합점수 기준으로 정렬 (높은 순)
      stockScores.sort((a, b) => (b['comprehensiveScore'] as double).compareTo(a['comprehensiveScore'] as double));
      
      // 상위 10개만 선택하여 추천종목 데이터 업데이트
      final top10Recommendations = stockScores.take(10).toList();
      await _updateRecommendedStocksData(top10Recommendations);
      
      print('✅ 백그라운드 분석 완료: ${stockScores.length}개 분석, ${top10Recommendations.length}개 추천');
    } catch (e) {
      print('❌ 백그라운드 분석 실패: $e');
    }
  }

  /// 추천종목 화면 진입 시 상위 10개 추천종목 조회 (최신값 유지)
  Future<List<Map<String, dynamic>>> getTopRecommendations() async {
    try {
      print('📱 추천종목 화면 진입 - 상위 10개 조회 시작...');
      // 화면 진입 시 즉시 전체 스캔을 트리거하지 않음
      // 상위 10개 추천종목 반환
      final recommendations = await _getTop10Recommendations();
      
      print('📱 추천종목 화면 진입 - 상위 10개 조회 완료: ${recommendations.length}개');
      return recommendations;
      
    } catch (e) {
      print('❌ 추천종목 화면 진입 - 상위 10개 조회 실패: $e');
      return [];
    }
  }

  /// 상위 10개 추천종목 조회
  Future<List<Map<String, dynamic>>> _getTop10Recommendations({bool forceScan = false}) async {
    try {
      // 1) 강제 스캔이면 단일 경로로 전체 분석 후 저장값에서 Top10 반환
      if (forceScan) {
        print('🧮 [AI 추천] 전체 분석 실행 (forceScan)');
        await _updateBackgroundAnalysis();
        final savedAfter = await _recommendedStocksData.getAllStocksWithScores();
        if (savedAfter.isEmpty) return [];
        final listAfter = savedAfter.entries.map((entry) => {
          'symbol': entry.key,
          'name': entry.value['name'],
          'comprehensiveScore': entry.value['score'],
          'market': entry.value['market'],
          'price': entry.value['price'],
          'timestamp': entry.value['timestamp'],
        }).toList();
        listAfter.sort((a, b) => (b['comprehensiveScore'] as double).compareTo(a['comprehensiveScore'] as double));
        return listAfter.take(10).toList();
      }

      // 2) 저장된 점수 우선 사용
      final savedScores = await _recommendedStocksData.getAllStocksWithScores();
      if (savedScores.isNotEmpty) {
        print('📊 [AI 추천] 저장된 점수 정보 사용: ${savedScores.length}개 종목');
        final stockScores = savedScores.entries.map((entry) => {
          'symbol': entry.key,
          'name': entry.value['name'],
          'comprehensiveScore': entry.value['score'],
          'market': entry.value['market'],
          'price': entry.value['price'],
          'timestamp': entry.value['timestamp'],
        }).toList();
        stockScores.sort((a, b) => (b['comprehensiveScore'] as double).compareTo(a['comprehensiveScore'] as double));
        return stockScores.take(10).toList();
      }

      // 3) 저장값이 없으면 단일 경로 분석 실행 후 반환
      print('🧮 [AI 추천] 전체 분석 실행 (no saved scores)');
      await _updateBackgroundAnalysis();
      final savedAfterCalc = await _recommendedStocksData.getAllStocksWithScores();
      if (savedAfterCalc.isEmpty) return [];
      final list = savedAfterCalc.entries.map((entry) => {
        'symbol': entry.key,
        'name': entry.value['name'],
        'comprehensiveScore': entry.value['score'],
        'market': entry.value['market'],
        'price': entry.value['price'],
        'timestamp': entry.value['timestamp'],
      }).toList();
      list.sort((a, b) => (b['comprehensiveScore'] as double).compareTo(a['comprehensiveScore'] as double));
      return list.take(10).toList();
      
    } catch (e) {
      print('❌ 상위 10개 추천종목 조회 실패: $e');
      return [];
    }
  }

  /// 종합점수 계산 (자동매매와 동일한 7개 지표)
  Future<Map<String, dynamic>> _calculateComprehensiveScore(String symbol) async {
    try {
      print('📊 [AI 추천] $symbol 종목 분석 시작...');
      
      // 기존 0.0 값의 차트 데이터가 있으면 제거 (데이터 일관성 확보)
      final existingChartData = await _historicalDataRepo.getRecentBars(symbol, limit: ChartConstants.CHART_MIN_BARS);
      if (existingChartData.isNotEmpty) {
        final hasZeroValues = existingChartData.any((data) => 
          (data['open'] ?? 0.0) == 0.0 || 
          (data['high'] ?? 0.0) == 0.0 || 
          (data['low'] ?? 0.0) == 0.0 || 
          (data['close'] ?? 0.0) == 0.0
        );
        
        if (hasZeroValues) {
          print('⚠️ [AI 추천] $symbol 기존 0.0 값 차트 데이터 발견, 제거 후 재수집');
          await _historicalDataRepo.deleteByStockCode(symbol);
        }
      }
      
      // 로컬DB에서 차트 데이터 조회 (0.0 값 검사 포함)
      var localChartData = await _historicalDataRepo.getRecentBars(symbol, limit: ChartConstants.CHART_MIN_BARS);
      
      // 로컬DB 데이터가 있지만 0.0 값이 포함되어 있으면 무효화
      if (localChartData.isNotEmpty) {
        final hasZeroValues = localChartData.any((data) => 
          (data['open'] ?? 0.0) == 0.0 || 
          (data['high'] ?? 0.0) == 0.0 || 
          (data['low'] ?? 0.0) == 0.0 || 
          (data['close'] ?? 0.0) == 0.0
        );
        
        if (hasZeroValues) {
          print('⚠️ [AI 추천] $symbol 로컬DB에 0.0 값 발견, 데이터 무효화');
          localChartData = [];
        }
      }
      
      // 데이터가 없거나 최소 바 미만이면 API 재수집 (분석/자동매매와 동일 기준)
      if (localChartData.isEmpty || localChartData.length < ChartConstants.CHART_MIN_BARS) {
        print('📊 [AI 추천] $symbol 로컬DB 데이터 없음, API에서 수집 시도...');
        
        try {
          // 로컬DB에 없으면 API에서 차트 데이터 수집
          List<Map<String, dynamic>> chartData = [];
          
          if (_getMarketFromSymbol(symbol) == 'NASDAQ') {
            // 나스닥 종목: 해외 전용 차트 API (실패 시 현재가 API로 대체) - 통일된 API 서비스
            print('📊 [AI 추천] $symbol 나스닥 종목, 해외 주식 차트 데이터 수집 시도...');
            chartData = await _retry(() => _unifiedApiService.getOverseasDailyChart(symbol: symbol, exchangeCode: 'NAS', count: ChartConstants.CHART_MIN_BARS), retries: 3, initialDelay: const Duration(milliseconds: 300));
            
            // 차트 데이터가 없으면 현재가 API로 기본 데이터 생성
            if (chartData.isEmpty) {
              print('📊 [AI 추천] $symbol 차트 데이터 없음, 현재가 API로 기본 데이터 생성...');
              final currentPriceData = await _retry(() => _unifiedApiService.getOverseasStockPrice(symbol: symbol, exchangeCode: 'NAS'), retries: 3, initialDelay: const Duration(milliseconds: 300));
              
              if (currentPriceData != null && currentPriceData.isNotEmpty) {
                final currentPrice = _parseDouble(currentPriceData['currentPrice']);
                final prevClose = _parseDouble(currentPriceData['prevClose']);
                
                // 현재가로 기본 차트 데이터 생성 (1일치)
                chartData = [{
                  'date': DateTime.now().toIso8601String().split('T')[0],
                  'open': currentPrice,
                  'high': currentPrice,
                  'low': currentPrice,
                  'close': currentPrice,
                  'volume': _parseInt(currentPriceData['volume']),
                  'trade_amount': 0,
                }];
                
                print('📊 [AI 추천] $symbol 현재가 기반 기본 차트 데이터 생성: ${chartData.length}개');
              }
            }
          } else {
            // 국내 종목: 일별 차트 최소 바 수 강제 확보
            print('📊 [AI 추천] $symbol 국내 종목, 국내 주식 차트 데이터 수집');
            chartData = await _fetchDomesticDailyChartData(symbol, minCount: ChartConstants.CHART_MIN_BARS);
          }
          
          if (chartData.isNotEmpty) {
            // 수집된 데이터를 로컬DB에 저장
            final formattedData = chartData.map((data) => {
              'stock_code': symbol,
              'market': _getMarketFromSymbol(symbol),
              'date': data['date'] ?? DateTime.now().toIso8601String().split('T')[0],
              'open': (data['open'] ?? 0.0).toDouble(),
              'high': (data['high'] ?? 0.0).toDouble(),
              'low': (data['low'] ?? 0.0).toDouble(),
              'close': (data['close'] ?? 0.0).toDouble(),
              'volume': (data['volume'] ?? 0).toInt(),
              'trade_amount': data['trade_amount'],
            }).toList();
            
            await _historicalDataRepo.upsertDailyBars(
              stockCode: symbol,
              market: _getMarketFromSymbol(symbol),
              bars: formattedData,
            );
            
            // 로컬DB에서 다시 조회 후 개수 검증
            localChartData = await _historicalDataRepo.getRecentBars(symbol, limit: ChartConstants.CHART_MIN_BARS);
            if (localChartData.length < ChartConstants.CHART_MIN_BARS) {
              print('⚠️ [AI 추천] '+symbol+' 재수집 필요: 저장 후 '+localChartData.length.toString()+'개 < '+ChartConstants.CHART_MIN_BARS.toString()+'개');
              final more = await _fetchDomesticDailyChartData(symbol, minCount: ChartConstants.CHART_MIN_BARS);
              if (more.isNotEmpty) {
                final moreFormatted = more.map((data) => {
                  'stock_code': symbol,
                  'market': _getMarketFromSymbol(symbol),
                  'date': data['date'] ?? DateTime.now().toIso8601String().split('T')[0],
                  'open': (data['open'] ?? 0.0).toDouble(),
                  'high': (data['high'] ?? 0.0).toDouble(),
                  'low': (data['low'] ?? 0.0).toDouble(),
                  'close': (data['close'] ?? 0.0).toDouble(),
                  'volume': (data['volume'] ?? 0).toInt(),
                  'trade_amount': data['trade_amount'],
                }).toList();
                await _historicalDataRepo.upsertDailyBars(
                  stockCode: symbol,
                  market: _getMarketFromSymbol(symbol),
                  bars: moreFormatted,
                );
                localChartData = await _historicalDataRepo.getRecentBars(symbol, limit: ChartConstants.CHART_MIN_BARS);
              }
            }
            print('📊 [AI 추천] $symbol API에서 데이터 수집 완료: ${localChartData.length}개');
          } else {
            print('📊 [AI 추천] $symbol 차트 데이터 없음, 현재가 API로 시도...');
            // 차트 데이터가 없어도 현재가 API는 시도해보기
          }
        } catch (e) {
          print('📊 [AI 추천] $symbol API 데이터 수집 실패: $e, 로컬 재조회 후 판단');
          // 마지막 시도: 혹시 기존에 저장된 데이터가 있으면 활용
          localChartData = await _historicalDataRepo.getRecentBars(symbol, limit: ChartConstants.CHART_MIN_BARS);
          if (localChartData.isEmpty) {
            return {
              'score': 0.0,
              'price': 0.0,
            };
          }
        }
      }
      
      // 현재가 조회 (로컬 DB 우선 사용 - 분석탭과 동일한 로직)
      var currentPrice = await _currentPriceRepo.getCurrentPrice(symbol);
      if (currentPrice == null) {
        print('📊 [AI 추천] $symbol 로컬 DB에 현재가 데이터 없음, 히스토리 데이터에서 복구 시도...');
        
        // 분석탭과 동일한 로직: 히스토리 데이터에서 현재가 복구
        if (localChartData.isNotEmpty) {
          final latest = localChartData.first;
          final priceFromChart = (latest['close'] ?? latest['open'] ?? 0.0).toDouble();
          currentPrice = {
            'currentPrice': priceFromChart,
            'prevClose': localChartData.length >= 2 ? (localChartData[1]['close'] ?? priceFromChart).toDouble() : priceFromChart,
            'openPrice': (latest['open'] ?? priceFromChart).toDouble(),
            'highPrice': (latest['high'] ?? priceFromChart).toDouble(),
            'lowPrice': (latest['low'] ?? priceFromChart).toDouble(),
            'volume': (latest['volume'] ?? 0).toInt(),
          };
          
          print('✅ [AI 추천] $symbol 히스토리 데이터에서 현재가 복구:');
          print('  - 현재가: ${currentPrice['currentPrice']}');
          print('  - 전일가: ${currentPrice['prevClose']}');
          print('  - 거래량: ${currentPrice['volume']}');
        } else {
          print('❌ [AI 추천] $symbol 히스토리 데이터도 없음, 분석 불가');
          return {
            'score': 0.0,
            'price': 0.0,
          };
        }
      } else {
        print('✅ [AI 추천] $symbol 로컬 DB에서 현재가 데이터 발견:');
        print('  - 현재가: ${currentPrice['currentPrice']}');
        print('  - 전일가: ${currentPrice['prevClose']}');
        print('  - 거래량: ${currentPrice['volume']}');
      }
      
      // API 호출 제거 - 로컬 DB 데이터만 사용 (분석탭과 동일)
      // 기존 API 호출 로직은 주석 처리하여 분석탭과 동일한 데이터 사용
      
      /*
      // 기존 API 호출 로직 (주석 처리)
      if (_getMarketFromSymbol(symbol) == 'NASDAQ') {
            // 나스닥 종목: 해외 전용 현재가 API (분석/자동매매와 동일) - 통일된 API 서비스
            print('📊 [AI 추천] $symbol 나스닥 종목, 해외 주식 현재가 API 사용');
            final data = await _retry(() => _unifiedApiService.getOverseasStockPrice(symbol: symbol, exchangeCode: 'NAS'), retries: 5, initialDelay: const Duration(milliseconds: 600));
            if (data != null && data.isNotEmpty) {
              // API 응답 구조 디버깅
              print('🔍 [AI 추천] $symbol 나스닥 API 응답 구조 분석:');
              print('  - 응답 키들: ${data.keys.toList()}');
              print('  - currentPrice: ${data['currentPrice']}');
              print('  - prevClose: ${data['prevClose']}');
              print('  - open: ${data['open']}');
              print('  - high: ${data['high']}');
              print('  - low: ${data['low']}');
              print('  - volume: ${data['volume']}');
              
              // API 응답에서 직접 추출 (해외 주식 API 응답 구조에 맞춤)
              final currentPriceRaw = data['currentPrice'];
              final prevCloseRaw = data['prevClose'];
              final openRaw = data['open'];
              final highRaw = data['high'];
              final lowRaw = data['low'];
              final volumeRaw = data['volume'];
              
              // 숫자 변환 및 유효성 검증
              final currentPrice = _parseDouble(currentPriceRaw);
              final prevClose = _parseDouble(prevCloseRaw);
              final open = _parseDouble(openRaw);
              final high = _parseDouble(highRaw);
              final low = _parseDouble(lowRaw);
              final volume = _parseInt(volumeRaw);
              
              print('🔍 [AI 추천] $symbol 나스닥 파싱된 데이터:');
              print('  - 현재가: $currentPrice (원본: $currentPriceRaw)');
              print('  - 전일가: $prevClose (원본: $prevCloseRaw)');
              print('  - 시가: $open (원본: $openRaw)');
              print('  - 고가: $high (원본: $highRaw)');
              print('  - 저가: $low (원본: $lowRaw)');
              print('  - 거래량: $volume (원본: $volumeRaw)');
              
              priceData = {
                'currentPrice': currentPrice,
                'prevClose': prevClose,
                'change': (data['change'] ?? 0.0).toDouble(),
                'changeRate': (data['changeRate'] ?? 0.0).toDouble(),
                'openPrice': open,
                'highPrice': high,
                'lowPrice': low,
                'volume': volume,
                'timestamp': DateTime.now().toIso8601String(),
              };
              
              // 나스닥 종목도 현재가 API 데이터를 차트 데이터로 사용하여 일관성 확보
              final today = DateTime.now().toIso8601String().split('T')[0];
              final chartDataFromPrice = [{
                'stock_code': symbol,
                'market': _getMarketFromSymbol(symbol),
                'date': today,
                'open': open,
                'high': high,
                'low': low,
                'close': currentPrice,
                'volume': volume,
                'trade_amount': null,
              }];
              
              // 차트 데이터도 로컬DB에 저장 (현재가와 일치하도록)
              await _historicalDataRepo.upsertDailyBars(
                stockCode: symbol,
                market: _getMarketFromSymbol(symbol),
                bars: chartDataFromPrice,
              );
              
              print('🔍 [AI 추천] $symbol 나스닥 차트 데이터 동기화 완료: ${chartDataFromPrice.length}개');
            }
          } else {
            // 국내 종목: getStockPrice 사용 (국내 주식 시세 API) - 통일된 API 서비스
            print('📊 [AI 추천] $symbol 국내 종목, 국내 주식 시세 API 사용');
            final data = await _retry(() => _unifiedApiService.getStockPrice(symbol), retries: 5, initialDelay: const Duration(milliseconds: 600));
            if (data != null && data.isNotEmpty) {
              // API 응답 구조 디버깅
              print('🔍 [AI 추천] $symbol 국내 API 응답 구조 분석:');
              print('  - 응답 키들: ${data.keys.toList()}');
              print('  - stck_prpr: ${data['stck_prpr']}');
              print('  - stck_prdy_clpr: ${data['stck_prdy_clpr']}');
              print('  - stck_oprc: ${data['stck_oprc']}');
              print('  - stck_hgpr: ${data['stck_hgpr']}');
              print('  - stck_lwpr: ${data['stck_lwpr']}');
              print('  - acml_vol: ${data['acml_vol']}');
              
              // API 응답에서 직접 추출 (KIS API 응답 구조에 맞춤)
              final currentPriceRaw = data['stck_prpr'] ?? data['currentPrice'];
              final prevCloseRaw = data['stck_prdy_clpr'] ?? data['prevClose'];
              final openRaw = data['stck_oprc'] ?? data['open'];
              final highRaw = data['stck_hgpr'] ?? data['high'];
              final lowRaw = data['stck_lwpr'] ?? data['low'];
              final volumeRaw = data['acml_vol'] ?? data['volume'];
              
              print('🔍 [AI 추천] $symbol 원본 데이터 값:');
              print('  - stck_prpr: ${data['stck_prpr']} (타입: ${data['stck_prpr']?.runtimeType})');
              print('  - stck_prdy_clpr: ${data['stck_prdy_clpr']} (타입: ${data['stck_prdy_clpr']?.runtimeType})');
              print('  - stck_oprc: ${data['stck_oprc']} (타입: ${data['stck_oprc']?.runtimeType})');
              print('  - stck_hgpr: ${data['stck_hgpr']} (타입: ${data['stck_hgpr']?.runtimeType})');
              print('  - stck_lwpr: ${data['stck_lwpr']} (타입: ${data['stck_lwpr']?.runtimeType})');
              print('  - acml_vol: ${data['acml_vol']} (타입: ${data['acml_vol']?.runtimeType})');
              
              // 숫자 변환 및 유효성 검증
              final currentPrice = _parseDouble(currentPriceRaw);
              final prevClose = _parseDouble(prevCloseRaw);
              final open = _parseDouble(openRaw);
              final high = _parseDouble(highRaw);
              final low = _parseDouble(lowRaw);
              final volume = _parseInt(volumeRaw);
              
              print('🔍 [AI 추천] $symbol 국내 파싱된 데이터:');
              print('  - 현재가: $currentPrice (원본: $currentPriceRaw)');
              print('  - 전일가: $prevClose (원본: $prevCloseRaw)');
              print('  - 시가: $open (원본: $openRaw)');
              print('  - 고가: $high (원본: $highRaw)');
              print('  - 저가: $low (원본: $lowRaw)');
              print('  - 거래량: $volume (원본: $volumeRaw)');
              
              // 데이터 유효성 검증
              if (currentPrice <= 0) {
                print('⚠️ [AI 추천] $symbol 현재가가 유효하지 않음: $currentPrice');
              }
              if (prevClose <= 0) {
                print('⚠️ [AI 추천] $symbol 전일가가 유효하지 않음: $prevClose');
              }
              if (open <= 0) {
                print('⚠️ [AI 추천] $symbol 시가가 유효하지 않음: $open');
              }
              if (high <= 0) {
                print('⚠️ [AI 추천] $symbol 고가가 유효하지 않음: $high');
              }
              if (low <= 0) {
                print('⚠️ [AI 추천] $symbol 저가가 유효하지 않음: $low');
              }
              if (volume <= 0) {
                print('⚠️ [AI 추천] $symbol 거래량이 유효하지 않음: $volume');
              }
              
              priceData = {
                'currentPrice': currentPrice,
                'prevClose': prevClose,
                'change': (data['prdy_vrss'] ?? 0.0).toDouble(),
                'changeRate': (data['prdy_ctrt'] ?? 0.0).toDouble(),
                'openPrice': open,
                'highPrice': high,
                'lowPrice': low,
                'volume': volume,
                'timestamp': DateTime.now().toIso8601String(),
              };
            }
          }
          
          if (priceData != null && priceData.isNotEmpty) {
            // 수집된 데이터를 로컬DB에 저장 (IncrementalDataManager와 동일한 키 사용)
            await _currentPriceRepo.insertOrUpdateCurrentPrice(
              stockCode: symbol,
              market: _getMarketFromSymbol(symbol),
              currentPrice: priceData['currentPrice'] ?? 0.0,
              prevClose: priceData['prevClose'] ?? priceData['currentPrice'] ?? 0.0,
              changeAmount: priceData['change'] ?? 0.0,
              changeRate: priceData['changeRate'] ?? 0.0,
              volume: priceData['volume'] ?? 0,
              tradeAmount: 0.0, // 거래대금은 별도 계산 필요
              highPrice: priceData['highPrice'] ?? 0.0,
              lowPrice: priceData['lowPrice'] ?? 0.0,
              openPrice: priceData['openPrice'] ?? 0.0,
            );
            
            // 현재가 API 데이터를 차트 데이터로도 사용하여 일관성 확보
            final today = DateTime.now().toIso8601String().split('T')[0];
            final chartDataFromPrice = [{
              'stock_code': symbol,
              'market': _getMarketFromSymbol(symbol),
              'date': today,
              'open': priceData['openPrice'] ?? 0.0,
              'high': priceData['highPrice'] ?? 0.0,
              'low': priceData['lowPrice'] ?? 0.0,
              'close': priceData['currentPrice'] ?? 0.0,
              'volume': priceData['volume'] ?? 0,
              'trade_amount': null,
            }];
            
            // 차트 데이터도 로컬DB에 저장 (현재가와 일치하도록)
            await _historicalDataRepo.upsertDailyBars(
              stockCode: symbol,
              market: _getMarketFromSymbol(symbol),
              bars: chartDataFromPrice,
            );
            
            print('🔍 [AI 추천] $symbol 로컬DB 저장 완료 (현재가 + 차트 데이터):');
            print('  - 현재가: ${priceData['currentPrice']}');
            print('  - 전일가: ${priceData['prevClose']}');
            print('  - 거래량: ${priceData['volume']}');
            print('  - 고가: ${priceData['highPrice']}');
            print('  - 저가: ${priceData['lowPrice']}');
            print('  - 시가: ${priceData['openPrice']}');
            print('  - 차트 데이터: ${chartDataFromPrice.length}개 저장');
            
            // priceData를 currentPrice 형태로 변환하여 일관성 유지
            currentPrice = {
              'currentPrice': priceData['currentPrice'],
              'prevClose': priceData['prevClose'],
              'volume': priceData['volume'],
              'highPrice': priceData['highPrice'],
              'lowPrice': priceData['lowPrice'],
              'openPrice': priceData['openPrice'],
            };
            
            print('📊 [AI 추천] $symbol API에서 현재가 수집 완료 (차트 데이터 동기화)');
          } else {
            print('📊 [AI 추천] $symbol API에서도 현재가 데이터 없음, 건너뛰기');
            return {
              'score': 0.0,
              'price': 0.0,
            };
          }
        } catch (e) {
          print('📊 [AI 추천] $symbol API 현재가 수집 실패: $e, 폴백 시도');
                      // 폴백: 차트의 최근 종가를 현재가로 사용 (보수적)
            if (localChartData.isNotEmpty) {
              final latest = localChartData.first;
              final priceFromChart = (latest['close'] ?? latest['open'] ?? 0.0).toDouble();
              currentPrice = {
                'currentPrice': priceFromChart,
                'prevClose': localChartData.length >= 2 ? (localChartData[1]['close'] ?? priceFromChart).toDouble() : priceFromChart,
                'openPrice': (latest['open'] ?? priceFromChart).toDouble(),
                'highPrice': (latest['high'] ?? priceFromChart).toDouble(),
                'lowPrice': (latest['low'] ?? priceFromChart).toDouble(),
                'volume': (latest['volume'] ?? 0).toInt(),
              };
              
              print('⚠️ [AI 추천] $symbol 폴백 데이터 사용 (차트 기반):');
              print('  - 현재가: ${currentPrice['currentPrice']}');
              print('  - 전일가: ${currentPrice['prevClose']}');
              print('  - 거래량: ${currentPrice['volume']}');
              print('  - 고가: ${currentPrice['highPrice']}');
              print('  - 저가: ${currentPrice['lowPrice']}');
              print('  - 시가: ${currentPrice['openPrice']}');
              
              // 폴백 데이터도 로컬DB에 저장
              await _currentPriceRepo.insertOrUpdateCurrentPrice(
                stockCode: symbol,
                market: _getMarketFromSymbol(symbol),
                currentPrice: currentPrice['currentPrice'] ?? 0.0,
                prevClose: currentPrice['prevClose'] ?? currentPrice['currentPrice'] ?? 0.0,
                changeAmount: 0.0,
                changeRate: 0.0,
                volume: currentPrice['volume'] ?? 0,
                tradeAmount: 0.0,
                highPrice: currentPrice['highPrice'] ?? currentPrice['currentPrice'] ?? 0.0,
                lowPrice: currentPrice['lowPrice'] ?? currentPrice['currentPrice'] ?? 0.0,
                openPrice: currentPrice['openPrice'] ?? currentPrice['currentPrice'] ?? 0.0,
              );
            } else {
              return {
                'score': 0.0,
                'price': 0.0,
              };
            }
        }
      }
      */
      
      // UnifiedAnalysisService를 사용하여 실제 분석 수행 (자동매매와 동일한 7개 지표 계산)
      print('🔍 [AI 추천] $symbol UnifiedAnalysisService 호출 파라미터:');
      print('  - 현재가: ${currentPrice?['currentPrice'] ?? 0.0}');
      print('  - 전일가: ${currentPrice?['prevClose'] ?? 0.0}');
      print('  - 거래량: ${currentPrice?['volume'] ?? 0.0}');
      print('  - 고가: ${currentPrice?['highPrice'] ?? 0.0}');
      print('  - 저가: ${currentPrice?['lowPrice'] ?? 0.0}');
      print('  - 시가: ${currentPrice?['openPrice'] ?? 0.0}');
      
            // 현재가가 0.0이면 히스토리 데이터에서 현재가를 가져오기 (분석탭과 동일한 로직)
      if ((currentPrice?['currentPrice'] ?? 0.0) == 0.0) {
        print('⚠️ [AI 추천] $symbol 현재가 0.0, 히스토리 데이터에서 현재가 가져오기');
        
        // 히스토리 데이터에서 현재가 가져오기
        final priceHistory = localChartData.map((data) => (data['close'] ?? 0.0).toDouble()).toList();
        if (priceHistory.isNotEmpty) {
          final currentPriceFromHistory = priceHistory.first;
          final prevCloseFromHistory = priceHistory.length >= 2 ? priceHistory[1] : currentPriceFromHistory;
          
          currentPrice = {
            'currentPrice': currentPriceFromHistory,
            'prevClose': prevCloseFromHistory,
            'volume': localChartData.isNotEmpty ? (localChartData.first['volume'] ?? 0).toInt() : 0,
            'highPrice': localChartData.isNotEmpty ? (localChartData.first['high'] ?? currentPriceFromHistory).toDouble() : currentPriceFromHistory,
            'lowPrice': localChartData.isNotEmpty ? (localChartData.first['low'] ?? currentPriceFromHistory).toDouble() : currentPriceFromHistory,
            'openPrice': localChartData.isNotEmpty ? (localChartData.first['open'] ?? currentPriceFromHistory).toDouble() : currentPriceFromHistory,
          };
          print('✅ [AI 추천] $symbol 히스토리에서 현재가 복구: ${currentPrice['currentPrice']}');
        } else {
          print('❌ [AI 추천] $symbol 히스토리 데이터도 없음, 로컬DB에서 재조회');
          final localPriceData = await _currentPriceRepo.getCurrentPrice(symbol);
          if (localPriceData != null && localPriceData['current_price'] != null && (localPriceData['current_price'] as num) > 0) {
            currentPrice = {
              'currentPrice': (localPriceData['current_price'] as num).toDouble(),
              'prevClose': (localPriceData['prev_close'] as num?)?.toDouble() ?? (localPriceData['current_price'] as num).toDouble(),
              'volume': (localPriceData['volume'] as num?)?.toInt() ?? 0,
              'highPrice': (localPriceData['high_price'] as num?)?.toDouble() ?? (localPriceData['current_price'] as num).toDouble(),
              'lowPrice': (localPriceData['low_price'] as num?)?.toDouble() ?? (localPriceData['current_price'] as num).toDouble(),
              'openPrice': (localPriceData['open_price'] as num?)?.toDouble() ?? (localPriceData['current_price'] as num).toDouble(),
            };
            print('✅ [AI 추천] $symbol 로컬DB에서 현재가 복구: ${currentPrice['currentPrice']}');
          } else {
            print('❌ [AI 추천] $symbol 로컬DB에도 유효한 현재가 없음, API 재호출 필요');
            // API에서 현재가를 다시 가져오기 (통일된 API 서비스)
            try {
              final data = await _retry(() => _unifiedApiService.getStockPrice(symbol), retries: 3, initialDelay: const Duration(milliseconds: 300));
              if (data != null && data.isNotEmpty) {
                final apiCurrentPrice = _parseDouble(data['stck_prpr']);
                if (apiCurrentPrice > 0) {
                  currentPrice = {
                    'currentPrice': apiCurrentPrice,
                    'prevClose': _parseDouble(data['stck_prdy_clpr']),
                    'volume': _parseInt(data['acml_vol']),
                    'highPrice': _parseDouble(data['stck_hgpr']),
                    'lowPrice': _parseDouble(data['stck_lwpr']),
                    'openPrice': _parseDouble(data['stck_oprc']),
                  };
                  print('✅ [AI 추천] $symbol API에서 현재가 복구: ${currentPrice['currentPrice']}');
                }
              }
            } catch (e) {
              print('❌ [AI 추천] $symbol API 재호출 실패: $e');
            }
          }
        }
      }
      
      // 타입 안전성을 위한 명시적 변환
      final currentPriceValue = _parseDouble(currentPrice?['currentPrice']);
      final prevCloseValue = _parseDouble(currentPrice?['prevClose']);
      final volumeValue = _parseDouble(currentPrice?['volume']);
      final highPriceValue = _parseDouble(currentPrice?['highPrice']);
      final lowPriceValue = _parseDouble(currentPrice?['lowPrice']);
      final openPriceValue = _parseDouble(currentPrice?['openPrice']);
      
      print('🔍 [AI 추천] $symbol 타입 변환된 파라미터:');
      print('  - 현재가: $currentPriceValue (타입: ${currentPriceValue.runtimeType})');
      print('  - 전일가: $prevCloseValue (타입: ${prevCloseValue.runtimeType})');
      print('  - 거래량: $volumeValue (타입: ${volumeValue.runtimeType})');
      print('  - 고가: $highPriceValue (타입: ${highPriceValue.runtimeType})');
      print('  - 저가: $lowPriceValue (타입: ${lowPriceValue.runtimeType})');
      print('  - 시가: $openPriceValue (타입: ${openPriceValue.runtimeType})');
      
      // 현재 사용자의 투자 스타일 가져오기
      final currentStyle = _styleManager.currentStyle;
      
      final analysisResult = await _unifiedAnalysis.analyzeStock(
        symbol,
        currentPrice: currentPriceValue,
        prevClose: prevCloseValue,
        volume: volumeValue,
        highPrice: highPriceValue,
        lowPrice: lowPriceValue,
        openPrice: openPriceValue,
        investmentStyle: currentStyle, // 사용자가 설정한 투자 스타일 사용
      );
      
      if (analysisResult == null) {
        print('📊 [AI 추천] $symbol 분석 결과 없음');
        return {
          'score': 0.0,
          'price': 0.0,
        };
      }
      
      // 실제 분석 결과에서 종합점수 추출
      final comprehensiveScore = analysisResult['comprehensiveScore'] ?? 0.0;
      final finalCurrentPrice = currentPrice?['currentPrice'] ?? 0.0;
      
      print('📊 [AI 추천] $symbol 종합점수: ${comprehensiveScore.toStringAsFixed(1)}, 현재가: $finalCurrentPrice');
      
      // 종합점수와 현재가를 함께 반환
      return {
        'score': comprehensiveScore,
        'price': finalCurrentPrice,
      };
      
    } catch (e) {
      print('❌ [AI 추천] $symbol 종합점수 계산 실패: $e');
      return {
        'score': 0.0,
        'price': 0.0,
      };
    }
  }

  /// 추천종목 데이터 업데이트
  Future<void> _updateRecommendedStocksData(List<Map<String, dynamic>> recommendations) async {
    try {
      print('📊 추천종목 데이터 업데이트:');
      
      // 기존 추천종목 데이터 초기화
      await _recommendedStocksData.resetToDefault();
      
      // 새로운 추천종목 데이터 추가
      for (final rec in recommendations) {
        final symbol = rec['symbol'] as String;
        final name = rec['name'] as String;
        final score = rec['comprehensiveScore'] as double;
        final price = rec['price'] as double;
        
        // 추천종목 목록에 추가
        await _recommendedStocksData.addStock(symbol, name);
        
        // 점수와 가격 정보 저장
        await _recommendedStocksData.updateStockScore(symbol, score, metadata: {
          'price': price,
          'market': rec['market'] ?? 'UNKNOWN',
        });
        
        print('  - ${rec['symbol']} (${rec['name']}): ${rec['comprehensiveScore'].toStringAsFixed(1)}점, 가격: ${price.toStringAsFixed(2)}');
      }
      
      print('✅ 추천종목 데이터 업데이트 완료: ${recommendations.length}개');
    } catch (e) {
      print('❌ 추천종목 데이터 업데이트 실패: $e');
    }
  }

  /// 🧪 단일 종목 테스트 분석 (112040)
  Future<void> testSingleStock(String symbol) async {
    try {
      print('🧪 [추천종목] $symbol 단일 종목 테스트 분석 시작');
      
      // 현재 사용자의 투자 스타일 확인
      final currentStyle = _styleManager.currentStyle;
      print('📊 [추천종목] 현재 투자 스타일: ${currentStyle.name}');
      
      // 종합점수 계산
      final result = await _calculateComprehensiveScore(symbol);
      
      print('✅ [추천종목] $symbol 테스트 분석 완료:');
      print('  - 종합점수: ${result['score']}');
      print('  - 현재가: ${result['price']}');
      print('  - 투자스타일: ${currentStyle.name}');
      
    } catch (e) {
      print('❌ [추천종목] $symbol 테스트 분석 실패: $e');
    }
  }

  /// 추천종목 데이터에서 모든 종목 조회 (409개) - 시장별 통계 포함
  Future<List<Map<String, String>>> _getTopStocks() async {
    try {
      // 이미 RecommendedStocksData에 있는 409개 종목을 모두 가져옴
      final allStocks = await _recommendedStocksData.getAllStocks();
      
      // Map<String, String> 형태로 변환 (개선된 시장 구분 적용)
      final stockList = allStocks.entries.map((entry) {
        final symbol = entry.key;
        final name = entry.value;
        final market = _getMarketFromSymbol(symbol);
        
        return {
          'symbol': symbol,
          'name': name,
          'market': market,
        };
      }).toList();
      
      // 시장별 통계 계산 및 출력
      final marketStats = <String, int>{};
      for (final stock in stockList) {
        final market = stock['market'] ?? 'UNKNOWN';
        marketStats[market] = (marketStats[market] ?? 0) + 1;
      }
      
      print('📊 [AI 추천] 분석 대상 종목 수: ${stockList.length}개');
      print('📊 [AI 추천] 시장별 분포:');
      marketStats.forEach((market, count) {
        print('  - $market: $count개');
      });
      
      // 나스닥 종목 상세 확인 (디버깅용)
      final nasdaqStocks = stockList.where((stock) => 
        (stock['market'] ?? '').toUpperCase().contains('NASDAQ')).toList();
      if (nasdaqStocks.isNotEmpty) {
        print('🇺🇸 [AI 추천] 나스닥 종목 상세 (첫 10개):');
        nasdaqStocks.take(10).forEach((stock) {
          print('  - ${stock['symbol']} (${stock['name']}) → ${stock['market']}');
        });
        if (nasdaqStocks.length > 10) {
          print('  ... 외 ${nasdaqStocks.length - 10}개');
        }
      }
      
      return stockList;
      
    } catch (e) {
      print('❌ [AI 추천] 종목 목록 조회 실패: $e');
      return [];
    }
  }

  /// API에서 409개 종목 목록 조회 (기존 RecommendedStocksData 활용)
  Future<List<Map<String, String>>> _fetchStocksFromAPI() async {
    try {
      print('📡 [AI 추천] RecommendedStocksData에서 기존 종목 목록 조회...');
      
      // 이미 RecommendedStocksData에 400개+ 종목이 정의되어 있음
      final existingStocks = await _recommendedStocksData.getAllStocks();
      
      // Map<String, String> 형태로 변환
      final stockList = existingStocks.entries.map((entry) => {
        'symbol': entry.key,
        'name': entry.value,
      }).toList();
      
      print('✅ [AI 추천] 기존 종목 목록 조회 완료: 총 ${stockList.length}개');
      return stockList;
      
    } catch (e) {
      print('❌ [AI 추천] 기존 종목 목록 조회 실패: $e');
      // 에러 발생 시 빈 리스트 반환
      return [];
    }
  }

  /// KOSPI 종목 조회 (기존 RecommendedStocksData 활용)
  Future<List<Map<String, String>>> _fetchKospiStocks() async {
    try {
      print('📊 [AI 추천] KOSPI 종목 - 기존 데이터 활용');
      
      // 기존 데이터에서 KOSPI 종목들 필터링
      final allStocks = await _recommendedStocksData.getAllStocks();
      final kospiStocks = allStocks.entries.where((entry) {
        final symbol = entry.key;
        return symbol.startsWith('0') && symbol.length == 6;
      }).map((entry) => {
        'symbol': entry.key,
        'name': entry.value,
      }).toList();
      
      return kospiStocks;
      
    } catch (e) {
      print('⚠️ [AI 추천] KOSPI 종목 조회 실패: $e');
      return [];
    }
  }

  /// KOSDAQ 종목 조회 (기존 RecommendedStocksData 활용)
  Future<List<Map<String, String>>> _fetchKosdaqStocks() async {
    try {
      print('📊 [AI 추천] KOSDAQ 종목 - 기존 데이터 활용');
      
      // 기존 데이터에서 KOSDAQ 종목들 필터링
      final allStocks = await _recommendedStocksData.getAllStocks();
      final kosdaqStocks = allStocks.entries.where((entry) {
        final symbol = entry.key;
        return !symbol.startsWith('0') && symbol.length == 6;
      }).map((entry) => {
        'symbol': entry.key,
        'name': entry.value,
      }).toList();
      
      return kosdaqStocks;
      
    } catch (e) {
      print('⚠️ [AI 추천] KOSDAQ 종목 조회 실패: $e');
      return [];
    }
  }

  /// NASDAQ 종목 조회 (기존 RecommendedStocksData 활용)
  Future<List<Map<String, String>>> _fetchNasdaqStocks() async {
    try {
      print('📊 [AI 추천] NASDAQ 종목 - 기존 데이터 활용');
      
      // 기존 데이터에서 NASDAQ 종목들 필터링
      final allStocks = await _recommendedStocksData.getAllStocks();
      final nasdaqStocks = allStocks.entries.where((entry) {
        final symbol = entry.key;
        return symbol.length <= 5 && RegExp(r'^[A-Z]+$').hasMatch(symbol);
      }).map((entry) => {
        'symbol': entry.key,
        'name': entry.value,
      }).toList();
      
      return nasdaqStocks;
      
    } catch (e) {
      print('⚠️ [AI 추천] NASDAQ 종목 조회 실패: $e');
      return [];
    }
  }

  /// NYSE 종목 조회 (기존 RecommendedStocksData 활용)
  Future<List<Map<String, String>>> _fetchNyseStocks() async {
    try {
      print('📊 [AI 추천] NYSE 종목 - 기존 데이터 활용');
      
      // 기존 데이터에서 NYSE 종목들 필터링 (현재는 NASDAQ과 동일하게 처리)
      final allStocks = await _recommendedStocksData.getAllStocks();
      final nyseStocks = allStocks.entries.where((entry) {
        final symbol = entry.key;
        return symbol.length <= 5 && RegExp(r'^[A-Z]+$').hasMatch(symbol);
      }).map((entry) => {
        'symbol': entry.key,
        'name': entry.value,
      }).toList();
      
      return nyseStocks;
      
    } catch (e) {
      print('⚠️ [AI 추천] NYSE 종목 조회 실패: $e');
      return [];
    }
  }

  /// 종목코드로 시장 구분 (분석탭과 동일한 다단계 검증)
  String _getMarketFromSymbol(String symbol) {
    try {
      // print('🔍 [AI 추천] $symbol 시장 구분 시작');
      
      // 1. AppDataManager에서 종목 정보 확인 (가장 정확한 방법)
      try {
        final info = AppDataManager.instance.getStockInfo(symbol);
        final dynamic marketFromInfo = info?['market'];
        if (marketFromInfo is String && marketFromInfo.isNotEmpty) {
          final marketUpper = marketFromInfo.toUpperCase();
          if (marketUpper == 'NASDAQ' || marketUpper == 'NASD' || 
              marketUpper == 'NYSE' || marketUpper == 'AMEX' || 
              marketUpper == 'US' || marketUpper == 'USA') {
            print('🔍 [AI 추천] AppDataManager에서 시장 확인: $symbol → $marketUpper');
            return marketUpper;
          }
        }
      } catch (e) {
        print('⚠️ [AI 추천] AppDataManager 시장 정보 조회 실패 ($symbol): $e');
      }

      // 2. 데이터베이스에서 관심종목/보유종목 market 정보 확인
      try {
        // 관심종목에서 해당 종목의 market 정보 확인
        final watchlist = AppDataManager.instance.watchlist;
        final watchlistItem = watchlist.firstWhere(
          (item) => (item['stock_code'] as String?) == symbol,
          orElse: () => <String, dynamic>{},
        );
        
        // 보유종목에서 해당 종목의 market 정보 확인
        final holdings = AppDataManager.instance.positions;
        final holdingItem = holdings.firstWhere(
          (item) => (item['stockCode'] as String?) == symbol,
          orElse: () => <String, dynamic>{},
        );
        
        final dynamic marketRaw = watchlistItem['market'] ?? holdingItem['market'];
        if (marketRaw is String && marketRaw.isNotEmpty) {
          final marketUpper = marketRaw.toUpperCase();
          if (marketUpper == 'NASDAQ' || marketUpper == 'NASD' || 
              marketUpper == 'NYSE' || marketUpper == 'AMEX' || 
              marketUpper == 'US' || marketUpper == 'USA') {
            print('🔍 [AI 추천] DB에서 시장 확인: $symbol → $marketUpper');
            return marketUpper;
          }
        }
      } catch (e) {
        print('⚠️ [AI 추천] DB 시장 정보 조회 실패 ($symbol): $e');
      }

      // 3. 패턴 기반 휴리스틱 (분석탭과 동일한 로직)
      final String code = symbol.trim().toUpperCase();
      
      // 미국 시장 패턴 확인 (영문자만, 1-10자, 점 포함 가능)
      final bool isLikelyUsTicker =
          RegExp(r'^[A-Z\.]{1,10}$').hasMatch(code) ||
          (RegExp(r'[A-Z]').hasMatch(code) && !RegExp(r'^\d+$').hasMatch(code));
      
      if (isLikelyUsTicker) {
        print('🔍 [AI 추천] 패턴 기반 시장 확인: $symbol → NASDAQ (휴리스틱)');
        return 'NASDAQ';
      }

      // 4. 국내 종목 패턴 매칭 (더 정확한 구분)
      if (code.length == 6) {
        if (code.startsWith('0')) {
          print('🔍 [AI 추천] 패턴 기반 시장 확인: $symbol → KOSPI (6자리, 0으로 시작)');
          return 'KOSPI'; // 코스피 (005930, 000660 등)
        } else {
          print('🔍 [AI 추천] 패턴 기반 시장 확인: $symbol → KOSDAQ (6자리, 0으로 시작하지 않음)');
          return 'KOSDAQ'; // 코스닥 (035720, 068760 등)
        }
      } else if (code.length <= 5 && RegExp(r'^[A-Z]+$').hasMatch(code)) {
        print('🔍 [AI 추천] 패턴 기반 시장 확인: $symbol → NASDAQ (5자 이하 영문)');
        return 'NASDAQ';
      } else {
        // 기본값: 6자리가 아니면 코스닥으로 간주
        print('🔍 [AI 추천] 패턴 기반 시장 확인: $symbol → KOSDAQ (기본값)');
        return 'KOSDAQ';
      }
      
    } catch (e) {
      print('❌ [AI 추천] 시장 구분 실패 ($symbol): $e');
      // 에러 발생 시 기본 패턴으로 폴백
      if (symbol.length <= 5 && RegExp(r'^[A-Z]+$').hasMatch(symbol)) {
        return 'NASDAQ';
      } else if (symbol.startsWith('0')) {
        return 'KOSPI';
      } else {
        return 'KOSDAQ';
      }
    }
  }

  /// 안전한 double 파싱 (API 응답의 다양한 타입 대응)
  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return 0.0;
      final parsed = double.tryParse(trimmed);
      return parsed ?? 0.0;
    }
    if (value is num) return value.toDouble();
    return 0.0;
  }

  /// 안전한 int 파싱 (API 응답의 다양한 타입 대응)
  int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return 0;
      final parsed = int.tryParse(trimmed);
      return parsed ?? 0;
    }
    if (value is num) return value.toInt();
    return 0;
  }

  /// 서비스 시작
  Future<void> start() async {
    try {
      if (!_isInitialized) {
        await initialize();
      }
      // 자동 타이머 시작은 비활성화 (수동 실행 전용)
      print('🤖 AI 추천 서비스 시작됨');
    } catch (e) {
      print('❌ AI 추천 서비스 시작 실패: $e');
      rethrow;
    }
  }

  /// 서비스 재시작
  Future<void> restart() async {
    try {
      print('🔄 AI 추천 서비스 재시작 시작...');
      
      // 기존 타이머 정리
      _updateTimer?.cancel();
      
      // 서비스 재초기화
      _isInitialized = false;
      _isInitialDataCollected = false;
      await initialize();
      
      print('✅ AI 추천 서비스 재시작 완료');
    } catch (e) {
      print('❌ AI 추천 서비스 재시작 실패: $e');
      rethrow;
    }
  }

  /// 서비스 실행 상태 확인
  bool get isRunning => _updateTimer?.isActive ?? false;

  /// 초기 데이터 수집 상태 확인
  bool get isInitialDataCollected => _isInitialDataCollected;

  /// 서비스 상태 확인
  Map<String, dynamic> getServiceStatus() {
    return {
      'isInitialized': _isInitialized,
      'isRunning': isRunning,
      'isInitialDataCollected': _isInitialDataCollected,
      'lastUpdate': _updateTimer?.tick ?? 0,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// 저장된 모든 점수(전체 409개 기준)를 정렬하여 반환
  /// market이 지정되면 해당 시장만 필터링 (NASDAQ/KOSPI/KOSDAQ)
  Future<List<Map<String, dynamic>>> getAllScoredStocksSorted({String? market}) async {
    final savedScores = await _recommendedStocksData.getAllStocksWithScores();
    if (savedScores.isEmpty) return [];

    final list = savedScores.entries.map((entry) {
      final info = entry.value;
      return {
        'symbol': entry.key,
        'name': info['name'],
        'comprehensiveScore': (info['score'] as num?)?.toDouble() ?? 0.0,
        'market': info['market'] ?? _getMarketFromSymbol(entry.key),
        'price': (info['price'] as num?)?.toDouble() ?? 0.0,
        'timestamp': info['timestamp'],
      };
    }).toList();

    if (market != null && market.isNotEmpty && market != 'all') {
      list.retainWhere((e) => (e['market']?.toString().toUpperCase() ?? '') == market.toUpperCase());
    }

    list.sort((a, b) => (b['comprehensiveScore'] as double).compareTo(a['comprehensiveScore'] as double));
    return list;
  }

  /// 추천종목 화면 이탈 시 임시 수집한 409개 데이터 정리
  /// - 관심종목/보유종목은 유지
  Future<void> cleanupTemporaryUniverseData() async {
    try {
      // 1) 409개 우주 구성
      final allStocks = await _recommendedStocksData.getAllStocks();
      final universe = allStocks.keys.toSet();

      // 2) 관심/보유 종목 수집
      final watchlist = await AppDataManager.instance.getWatchlist();
      final watchlistCodes = watchlist.map((e) => (e['stock_code'] as String)).toSet();
      final holdings = await _holdingsRepo.getAllHoldings();
      final holdingCodes = holdings.map((e) => (e['stockCode'] as String)).toSet();

      // 3) 보존 대상 집합
      final retain = <String>{}
        ..addAll(watchlistCodes)
        ..addAll(holdingCodes);

      // 4) 삭제 대상 = 409개 - 보존 대상
      final targets = universe.difference(retain).toList();
      int deletedPrice = 0;
      int deletedChart = 0;

      for (final code in targets) {
        try {
          final c1 = await _currentPriceRepo.deleteCurrentPrice(code);
          if (c1 > 0) deletedPrice += c1;
        } catch (_) {}
        try {
          await _historicalDataRepo.deleteByStockCode(code);
          deletedChart += 1;
        } catch (_) {}
      }

      print('🧹 [AI 추천] 임시 데이터 정리 완료: price ${deletedPrice}개 삭제, chart ${deletedChart}종목 삭제 (retain=${retain.length}, universe=${universe.length})');
    } catch (e) {
      print('❌ [AI 추천] 임시 데이터 정리 실패: $e');
    }
  }

  /// 서비스 정리
  void dispose() {
    _updateTimer?.cancel();
    _isInitialized = false;
    _isInitialDataCollected = false;
    print('🤖 AI 추천 서비스 정리 완료');
  }

  /// 백그라운드 순차 스캔 시작 (재진입 방지, 재시작 복구)
  Future<void> startResumableBackgroundScan() async {
    if (_isScannerRunning) {
      print('⏳ [AI 추천] 스캐너 이미 실행 중, 재진입 방지');
      return;
    }
    _isScannerRunning = true;

    try {
      // 테이블 보장
      try {
        await _recommendedStocksRepo.createTable();
      } catch (e) {
        print('⚠️ [AI 추천] 진행률 테이블 보장 실패: $e');
      }

      // 전체 대상 목록 확보
      final allMap = await _recommendedStocksData.getAllStocks();
      final symbols = allMap.keys.toList(growable: false);
      final total = symbols.length;

      // 진행률 복구
      final progress = await _recommendedStocksRepo.getScanProgress();
      int startIndex = (progress['current_index'] as int?) ?? 0;
      if (startIndex < 0 || startIndex >= total) startIndex = 0;

      print('🚦 [AI 추천] 스캔 시작: index=$startIndex / total=$total');

      // 초기 진행률 기록 (UI가 0/total로 보이도록)
      await _recommendedStocksRepo.saveScanProgress(
        currentIndex: startIndex,
        totalCount: total,
        currentSymbol: '',
        currentName: '',
        isCompleted: false,
      );

      for (int i = startIndex; i < total; i++) {
        final symbol = symbols[i];
        final name = allMap[symbol] ?? '';

        // 진행률 콜백 (UI)
        try {
          _onProgressUpdate?.call(i + 1, total, symbol, name);
        } catch (_) {}

        // DB 진행률 저장 (락 최소화, 단건 업데이트)
        // 진행률 저장은 best-effort. 실패해도 다음 루프로 진행
        await _recommendedStocksRepo.saveScanProgress(
          currentIndex: i + 1,
          totalCount: total,
          currentSymbol: symbol,
          currentName: name,
          isCompleted: false,
        );

        // 단일 종목 순차 처리: 현재가/차트 조회 → 점수 계산 → 점수 저장
        try {
          // 실패 시 자동 재시도
          final scoreResult = await _retry(() async {
            return await _calculateComprehensiveScore(symbol);
          }, retries: 3, initialDelay: const Duration(milliseconds: 300));
          if (scoreResult is Map<String, dynamic>) {
            final double price = scoreResult['price'] as double? ?? 0.0;
            final double score = scoreResult['score'] as double? ?? 0.0;

            final market = _resolveMarketOnce(symbol);

            await _recommendedStocksData.updateStockScore(symbol, score, metadata: {
              'price': price,
              'market': market,
              'timestamp': DateTime.now().toIso8601String(),
            });

            if (symbol == '003465') {
              print('✅ [AI 추천] 003465 점수 저장: score=$score price=$price market=$market idx=${i + 1}/$total');
            }
          }
        } catch (e) {
          print('⚠️ [AI 추천] $symbol 분석 실패: $e');
        }

        // 과도한 호출 방지 딜레이 (DB 락/네트워크 스로틀링)
        // 최하위 우선순위: 여유를 두고 다른 API들을 방해하지 않도록 느리게 진행
        await Future.delayed(const Duration(milliseconds: 900));
        // 프레임 양보
        await Future(() {});
      }

      // 완료 처리
      await _recommendedStocksRepo.saveScanProgress(
        currentIndex: total,
        totalCount: total,
        currentSymbol: '',
        currentName: '',
        isCompleted: true,
      );

      // 완료 알림
      await _notifier.showNotification(
        title: '추천종목 분석 완료',
        body: '8397개 종목 분석이 끝났습니다. 상위 종목을 확인하세요.',
      );

      print('✅ [AI 추천] 스캔 완료: $total 종목');
    } finally {
      _isScannerRunning = false;
    }
  }
}
