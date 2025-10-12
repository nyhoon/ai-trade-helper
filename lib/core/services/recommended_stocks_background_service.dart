import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/app_data_manager.dart';
import '../ai/ai_recommendation_service.dart';
import '../data/recommended_stocks_data.dart';
import '../api/kis_unified_api_service.dart';
import '../trading/investment_style_manager.dart';
import '../database/database_helper.dart';
import '../database/repositories/top_stocks_repository.dart';
import '../utils/stock_filter_utils.dart';
import '../trading/market_time_validator.dart';

/// 추천종목 백그라운드 계산 서비스
/// 8397개 종목의 점수를 백그라운드에서 계산하고 상위 10개를 관리
class RecommendedStocksBackgroundService {
  static final RecommendedStocksBackgroundService _instance = RecommendedStocksBackgroundService._internal();
  factory RecommendedStocksBackgroundService() => _instance;
  RecommendedStocksBackgroundService._internal();

  // 서비스 상태
  bool _isServiceEnabled = false;
  bool _isServiceRunning = false;
  Timer? _calculationTimer;
  Timer? _updateTimer;

  // 기존 시스템 인스턴스
  final AppDataManager _appDataManager = AppDataManager.instance;
  final AiRecommendationService _aiService = AiRecommendationService();
  final RecommendedStocksData _recommendedStocksData = RecommendedStocksData();
  final InvestmentStyleManager _styleManager = InvestmentStyleManager();

  // 계산 상태
  int _totalStocksCount = 0;
  int _calculatedStocksCount = 0;
  String _currentMarket = '';
  String _currentStock = '';
  DateTime? _lastUpdateTime;
  
  // 진행 상황 저장
  int _lastProcessedIndex = 0;
  String _lastProcessedMarket = '';
  List<String> _processedStocks = [];
  Map<String, int> _marketProgress = {
    'KOSPI': 0,
    'KOSDAQ': 0,
    'NASDAQ': 0,
    'NYSE': 0,
  };

  // API 호출 레이트 리밋(백그라운드 대량 호출 보호)
  static const int _maxConcurrentPriceCalls = 2;
  static const Duration _minIntervalBetweenCalls = Duration(milliseconds: 150);
  int _inflightPriceCalls = 0;
  DateTime _lastPriceCallAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<Map<String, dynamic>?> _rateLimitedGetPrice(String stockCode) async {
    // 호출 간 최소 간격 보장
    final elapsed = DateTime.now().difference(_lastPriceCallAt);
    if (elapsed < _minIntervalBetweenCalls) {
      await Future.delayed(_minIntervalBetweenCalls - elapsed);
    }
    // 동시 호출 제한
    while (_inflightPriceCalls >= _maxConcurrentPriceCalls) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    _inflightPriceCalls++;
    _lastPriceCallAt = DateTime.now();
    try {
      // ✅ API 직접 호출 비활성화 - Firestore 구독 사용
      print('🔍 [current 보호] RecommendedStocksBackgroundService에서 API 직접 호출 비활성화');
      return null;
      // final api = KisUnifiedApiService();
      // return await api.getStockPrice(stockCode);
    } catch (_) {
      return null;
    } finally {
      _inflightPriceCalls--;
    }
  }
  
  // 거래대금 필터링 설정
  double _minTradingAmount = 1000000000; // 10억원 (기본값)
  
  // 실시간 업데이트용 상위 종목 캐시
  Map<String, List<Map<String, dynamic>>> _topStocksCache = {
    'KOSPI': [],
    'KOSDAQ': [],
    'NASDAQ': [],
    'NYSE': [],
  };

  // 상태 변경 콜백
  Function(bool)? onServiceStatusChanged;
  Function(Map<String, dynamic>)? onCalculationProgress;
  Function(List<Map<String, dynamic>>)? onTopStocksUpdated;

  /// 서비스 활성화 상태
  bool get isServiceEnabled => _isServiceEnabled;
  
  /// 서비스 실행 상태
  bool get isServiceRunning => _isServiceRunning;
  
  /// 계산 진행률 (0.0 ~ 1.0)
  double get calculationProgress => _totalStocksCount > 0 ? _calculatedStocksCount / _totalStocksCount : 0.0;
  
  /// 현재 계산 중인 시장
  String get currentMarket => _currentMarket;
  
  /// 현재 계산 중인 종목
  String get currentStock => _currentStock;
  
  /// 마지막 업데이트 시간
  DateTime? get lastUpdateTime => _lastUpdateTime;
  
  /// 최소 거래대금 설정
  double get minTradingAmount => _minTradingAmount;
  
  /// 상위 종목 캐시
  Map<String, List<Map<String, dynamic>>> get topStocksCache => _topStocksCache;

  /// 서비스 초기화
  Future<void> initialize() async {
    print('🔧 추천종목 백그라운드 서비스 초기화...');
    
    // 기존 시스템 초기화
    await _appDataManager.initialize();
    await _aiService.initialize();
    await _recommendedStocksData.load();
    // UnifiedAnalysisService는 싱글톤이므로 별도 초기화 불필요
    
    // 저장된 설정 로드
    final prefs = await SharedPreferences.getInstance();
    _isServiceEnabled = prefs.getBool('recommended_stocks_background_enabled') ?? false;
    _minTradingAmount = prefs.getDouble('recommended_stocks_min_trading_amount') ?? 1000000000; // 기본 10억원
    
    // 진행 상황 복구
    await _loadProgress();
    
    print('📊 서비스 활성화 상태: $_isServiceEnabled');
    print('📊 복구된 진행 상황: $_calculatedStocksCount/$_totalStocksCount (${(_calculatedStocksCount / (_totalStocksCount > 0 ? _totalStocksCount : 1) * 100).toStringAsFixed(1)}%)');
    
    // 서비스가 활성화되어 있으면 자동 시작
    if (_isServiceEnabled) {
      await startService();
    } else {
      // 비활성화 상태여도 기본 데이터는 로드
      print('📊 서비스 비활성화 상태 - 기본 데이터 로드만 수행');
      await _loadBasicData();
    }
  }

  /// 기본 데이터 로드 (서비스 비활성화 상태에서도 실행)
  Future<void> _loadBasicData() async {
    try {
      print('📊 기본 데이터 로드 시작...');
      
      // 추천종목 데이터 로드
      final allStocks = await _recommendedStocksData.getAllStocks();
      print('📊 로드된 종목 수: ${allStocks.length}개');
      
      // 상위 종목 캐시 초기화
      _topStocksCache = {
        'KOSPI': [],
        'KOSDAQ': [],
        'NASDAQ': [],
        'NYSE': [],
      };
      
      // 기본 종목 정보로 캐시 구성 (점수는 0.0으로 설정)
      for (final entry in allStocks.entries.take(30)) { // 상위 30개만
        final stockCode = entry.key;
        final stockName = entry.value;
        final market = _getMarketFromSymbol(stockCode);
        
        if (_topStocksCache.containsKey(market)) {
          _topStocksCache[market]!.add({
            'stockCode': stockCode,
            'stockName': stockName,
            'market': market,
            'score': 0.0,
            'currentPrice': 0.0,
            'priceChangeRate': 0.0,
            'lastUpdated': DateTime.now().toIso8601String(),
          });
        }
      }
      
      // 상위 10개만 유지
      for (final market in _topStocksCache.keys) {
        _topStocksCache[market] = _topStocksCache[market]!.take(10).toList();
      }
      
      print('✅ 기본 데이터 로드 완료');
      
    } catch (e) {
      print('❌ 기본 데이터 로드 실패: $e');
    }
  }

  /// 진행 상황 저장
  Future<void> _saveProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_processed_index', _lastProcessedIndex);
      await prefs.setString('last_processed_market', _lastProcessedMarket);
      await prefs.setInt('calculated_stocks_count', _calculatedStocksCount);
      await prefs.setInt('total_stocks_count', _totalStocksCount);
      await prefs.setStringList('processed_stocks', _processedStocks);
      
      // 시장별 진행 상황 저장
      for (final entry in _marketProgress.entries) {
        await prefs.setInt('market_progress_${entry.key}', entry.value);
      }
      
      print('💾 진행 상황 저장 완료: $_calculatedStocksCount/$_totalStocksCount');
    } catch (e) {
      print('❌ 진행 상황 저장 실패: $e');
    }
  }

  /// 진행 상황 로드
  Future<void> _loadProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _lastProcessedIndex = prefs.getInt('last_processed_index') ?? 0;
      _lastProcessedMarket = prefs.getString('last_processed_market') ?? '';
      _calculatedStocksCount = prefs.getInt('calculated_stocks_count') ?? 0;
      _totalStocksCount = prefs.getInt('total_stocks_count') ?? 0;
      _processedStocks = prefs.getStringList('processed_stocks') ?? [];
      
      // 시장별 진행 상황 로드
      final markets = ['KOSPI', 'KOSDAQ', 'NASDAQ', 'NYSE'];
      for (final market in markets) {
        _marketProgress[market] = prefs.getInt('market_progress_$market') ?? 0;
      }
      
      print('📂 진행 상황 로드 완료: $_calculatedStocksCount/$_totalStocksCount');
    } catch (e) {
      print('❌ 진행 상황 로드 실패: $e');
    }
  }

  /// 서비스 활성화/비활성화 토글
  Future<void> toggleService() async {
    try {
      print('🔄 추천종목 백그라운드 서비스 토글: $_isServiceEnabled → ${!_isServiceEnabled}');
      
      final newState = !_isServiceEnabled;
      _isServiceEnabled = newState;
      
      // 설정 저장 (타임아웃 설정)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('recommended_stocks_background_enabled', _isServiceEnabled).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print('⚠️ 설정 저장 타임아웃');
          throw TimeoutException('설정 저장 타임아웃', const Duration(seconds: 5));
        },
      );
      
      // 서비스 상태에 따라 시작/중지 (타임아웃 설정)
      if (_isServiceEnabled) {
        await startService().timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            print('⚠️ 서비스 시작 타임아웃');
            throw TimeoutException('서비스 시작 타임아웃', const Duration(seconds: 15));
          },
        );
      } else {
        await stopService().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            print('⚠️ 서비스 중지 타임아웃');
            throw TimeoutException('서비스 중지 타임아웃', const Duration(seconds: 10));
          },
        );
      }
      
      // 상태 변경 알림
      onServiceStatusChanged?.call(_isServiceEnabled);
      
      print('✅ 추천종목 백그라운드 서비스 토글 완료: $_isServiceEnabled');
    } catch (e) {
      print('❌ 추천종목 백그라운드 서비스 토글 실패: $e');
      // 실패 시 이전 상태로 롤백
      _isServiceEnabled = !_isServiceEnabled;
      rethrow;
    }
  }
  
  /// 최소 거래대금 설정
  Future<void> setMinTradingAmount(double amount) async {
    _minTradingAmount = amount;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('recommended_stocks_min_trading_amount', amount);
    print('💰 최소 거래대금 설정: ${(amount / 100000000).toStringAsFixed(1)}억원');
  }

  /// 서비스 시작
  Future<void> startService() async {
    if (_isServiceRunning) {
      print('⚠️ 추천종목 백그라운드 서비스가 이미 실행 중입니다.');
      return;
    }

    print('🚀 추천종목 백그라운드 서비스 시작...');
    
    _isServiceRunning = true;
    
    // 서비스 상태 변경 알림
    onServiceStatusChanged?.call(true);
    
    // 1. 초기 계산 실행 (비동기로 실행하여 UI 블로킹 방지)
    _performInitialCalculation().catchError((error) {
      print('❌ 초기 계산 실패: $error');
    });
    
    // 2. 주기적 계산 타이머 시작 (30분마다)
    _calculationTimer = Timer.periodic(const Duration(minutes: 30), (timer) {
      _performPeriodicCalculation();
    });
    
    // 3. 상위 종목 업데이트 타이머 시작 (5분마다)
    _updateTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      _updateTopStocks();
    });
    
    print('✅ 추천종목 백그라운드 서비스 시작 완료');
  }

  /// 서비스 중지
  Future<void> stopService() async {
    if (!_isServiceRunning) {
      print('⚠️ 추천종목 백그라운드 서비스가 실행 중이 아닙니다.');
      return;
    }

    print('🛑 추천종목 백그라운드 서비스 중지...');
    
    _isServiceRunning = false;
    
    // 타이머 정리
    _calculationTimer?.cancel();
    _updateTimer?.cancel();
    _calculationTimer = null;
    _updateTimer = null;
    
    // 상태 초기화
    _totalStocksCount = 0;
    _calculatedStocksCount = 0;
    _currentMarket = '';
    _currentStock = '';
    
    print('✅ 추천종목 백그라운드 서비스 중지 완료');
  }

  /// 초기 계산 수행 (이어서 처리)
  Future<void> _performInitialCalculation() async {
    print('📊 추천종목 계산 시작... (이어서 처리)');
    
    try {
      // 1. 전체 종목 수 조회
      final allStocks = await _getAllStocks();
      _totalStocksCount = allStocks.length;
      
      print('📋 전체 종목 수: $_totalStocksCount개');
      print('📊 복구된 진행 상황: $_calculatedStocksCount/$_totalStocksCount (${(_calculatedStocksCount / _totalStocksCount * 100).toStringAsFixed(1)}%)');
      
      // 초기 진행률 알림
      _notifyProgress();
      
      // 2. 시장별로 나누어 처리 (이어서 처리)
      final markets = ['KOSPI', 'KOSDAQ', 'NASDAQ', 'NYSE'];
      
      for (final market in markets) {
        _currentMarket = market;
        await _processMarketStocksResume(market, allStocks);
      }
      
      _lastUpdateTime = DateTime.now();
      print('✅ 추천종목 계산 완료');
      
    } catch (e) {
      print('❌ 추천종목 계산 실패: $e');
    }
  }

  /// 주기적 계산 수행
  Future<void> _performPeriodicCalculation() async {
    if (!_isServiceRunning) return;
    
    print('🔄 주기적 추천종목 계산 시작...');
    await _performInitialCalculation();
  }

  /// 시장별 종목 처리 (이어서 처리)
  Future<void> _processMarketStocksResume(String market, List<Map<String, dynamic>> allStocks) async {
    print('📊 $market 시장 종목 처리 시작... (이어서 처리)');
    
    // 시장별 종목 필터링
    final marketStocks = allStocks.where((stock) => 
      stock['market'] == market).toList();
    
    print('📋 $market 종목 수: ${marketStocks.length}개');
    
    // 이전 진행 상황에서 이어서 처리
    final startIndex = _marketProgress[market] ?? 0;
    print('🔄 $market 시장 이어서 처리: $startIndex/${marketStocks.length}');
    
    // 한 종목씩 처리하되, 내부에서 API 동시성은 제한적으로 수행
    for (int i = startIndex; i < marketStocks.length; i++) {
      if (!_isServiceRunning) {
        print('⏹️ 서비스 중지됨 - $market 시장 처리 중단');
        break;
      }
      
      final stock = marketStocks[i];
      final stockCode = stock['stock_code'] as String;
      final stockName = stock['stock_name'] as String;
      
      _currentStock = '$stockName ($stockCode)';
      
      try {
        // 점수 계산
        final score = await _calculateStockScore(stockCode);

        // SQL 단일화: SharedPreferences 제거, SQL 배치 저장만
        _pendingSaves.add({'stockCode': stockCode, 'market': market, 'score': score});

        _calculatedStocksCount++;
        _marketProgress[market] = i + 1;
        _lastProcessedIndex = _calculatedStocksCount;
        _lastProcessedMarket = market;

        // 진행률 업데이트 (매 항목)
        _notifyProgress();
        if (_calculatedStocksCount % 10 == 0) {
          print('📊 점수 업데이트 중: $_calculatedStocksCount/$_totalStocksCount (${(calculationProgress * 100).toStringAsFixed(1)}%)');
        }

        // 체감 주기 개선: 10개마다 배치 저장, 스캔 단건/소수 케이스 보완
        if (_pendingSaves.length >= 10) {
          await _flushPendingSaves();
          await _updateTopStocksForMarket(market);
          await _saveProgress();
        } else {
          // 한 건 처리 직후에도 Top10 스냅샷을 빠르게 반영 (시장별 상위 변화가 있으면 즉시 반영)
          // 과도한 호출 방지를 위해 소규모에서는 _getTopStocksForMarket만 호출
          final quickTop = await _getTopStocksForMarket(market, 10);
          if (quickTop.isNotEmpty) {
            onTopStocksUpdated?.call(quickTop.map((s) => {
              ...s,
              'market': market,
            }).toList());
          }
        }

      } catch (e) {
        print('❌ $stockCode 점수 계산 실패: $e');
      }
      
      // 한 종목 처리 후 대기 (DB 락/트래픽 완화) - 락 방지를 위해 지연 시간 증가
      await Future.delayed(const Duration(milliseconds: 200));
    }
    
    print('✅ $market 시장 처리 완료: ${marketStocks.length}개');
    // 루프 종료 시 잔여 배치 저장 및 최종 Top10 반영 (특히 소수 처리 케이스)
    if (_pendingSaves.isNotEmpty) {
      await _flushPendingSaves();
      await _updateTopStocksForMarket(market);
      await _saveProgress();
    }
  }


  /// 종목 점수 계산 (UnifiedAnalysisService 활용)
  Future<double> _calculateStockScore(String stockCode) async {
    try {
      // UnifiedAnalysisService를 사용하여 분석탭과 동일한 점수 계산 (명시 파라미터 전달)
      // 최신 현재가 데이터를 우선 캐시에서 확인, 부족 시 API 조회
      final cached = _appDataManager.getCachedStockData(stockCode);
      double currentPrice = (cached['prpr'] ?? cached['currentPrice'] ?? 0.0).toDouble();
      double prevClose = (cached['stck_prdy_clpr'] ?? cached['prevClose'] ?? currentPrice).toDouble();
      double volume = (cached['acml_vol'] ?? cached['volume'] ?? 0.0).toDouble();
      double high = (cached['high'] ?? 0.0).toDouble();
      double low = (cached['low'] ?? 0.0).toDouble();
      double open = (cached['open'] ?? 0.0).toDouble();

      // 신선도(3분) 검사를 통과하지 못하면 현재가/차트를 병렬로 수집
      final String? tsStr = cached['timestamp'] as String?;
      final bool fresh = (() {
        if (tsStr == null || tsStr.isEmpty) return false;
        final dt = DateTime.tryParse(tsStr);
        if (dt == null) return false;
        return DateTime.now().difference(dt).inMinutes < 3;
      })();

      if (!fresh) {
        try {
          // ✅ API 직접 호출 비활성화 - Firestore 구독 사용
          print('🔍 [current 보호] RecommendedStocksBackgroundService에서 API 직접 호출 비활성화');
          final results = await Future.wait([
            // KisUnifiedApiService().getStockPrice(stockCode),
            null, // API 호출 비활성화
            // SQL DB에서 차트 데이터 먼저 확인
            _appDataManager.historicalDataRepo.getRecentBars(stockCode, limit: 100),
          ]);
          final priceData = results[0] as Map<String, dynamic>?;
          final localChartData = results[1] as List<Map<String, dynamic>>?;
          
          if (priceData != null && priceData.isNotEmpty) {
            currentPrice = (priceData['currentPrice'] ?? 0.0).toDouble();
            prevClose = (priceData['prevClose'] ?? currentPrice).toDouble();
            volume = (priceData['volume'] ?? volume).toDouble();
            high = (priceData['highPrice'] ?? high).toDouble();
            low = (priceData['lowPrice'] ?? low).toDouble();
            open = (priceData['openPrice'] ?? open).toDouble();
            // 🔄 거래량 덮어쓰기 방지 - volume 제외하고 업데이트
            _appDataManager.updateCurrentPrice(stockCode, {
              'currentPrice': currentPrice,
              'prevClose': prevClose,
              // 'volume': volume,  // ← 거래량 덮어쓰기 방지
              'high': high,
              'low': low,
              'open': open,
              'timestamp': DateTime.now().toIso8601String(),
            });
          }
          
          if (localChartData != null && localChartData.isNotEmpty) {
            // SQL DB에 데이터가 있으면 사용
            _appDataManager.cacheChartData(stockCode, localChartData);
            print('📊 [백그라운드] SQL DB에서 차트 데이터 사용: $stockCode (${localChartData.length}개)');
          } else {
            // SQL DB에 없으면 API 호출
            // Firestore 구독으로 대체되므로 직접 API 호출 비활성화
            print('📊 [RecommendedStocksBackground] 차트 데이터 API 호출 비활성화 - Firestore 구독 사용: $stockCode');
            final chartData = <Map<String, dynamic>>[];
            if (chartData.isNotEmpty) {
              _appDataManager.cacheChartData(stockCode, chartData);
              print('📊 [백그라운드] API에서 차트 데이터 사용: $stockCode (${chartData.length}개)');
            }
          }
        } catch (_) {}
      }

      // 해외/특수 케이스 보정: 현재가/전일가가 0이면 차트 최신 종가로 보정하여 분석 일관성 유지
      if (currentPrice == 0.0 || prevClose == 0.0) {
        try {
          // Firestore 구독으로 대체되므로 직접 API 호출 비활성화
          print('📊 [RecommendedStocksBackground] 차트 데이터 API 호출 비활성화 - Firestore 구독 사용: $stockCode');
          final chart = <Map<String, dynamic>>[];
          if (chart.isNotEmpty) {
            final lastClose = (chart.last['close'] as num?)?.toDouble() ?? 0.0;
            if (lastClose > 0) {
              currentPrice = currentPrice == 0.0 ? lastClose : currentPrice;
              prevClose = prevClose == 0.0 ? lastClose : prevClose;
            }
          }
        } catch (_) {}
      }

      final analysisResult = await _unifiedAnalysis.analyzeStock(
        stockCode,
        currentPrice: currentPrice,
        prevClose: prevClose,
        volume: volume,
        highPrice: high,
        lowPrice: low,
        openPrice: open,
        investmentStyle: _styleManager.currentStyle,
      );
      
      if (analysisResult != null) {
        final score = analysisResult['comprehensiveScore'] as double? ?? 0.0;
        print('📊 $stockCode 종합점수 계산 완료: $score');
        return score;
      } else {
        print('⚠️ $stockCode 분석 결과가 없음');
        return 0.0;
      }
    } catch (e) {
      print('❌ $stockCode 점수 계산 실패: $e');
      return 0.0;
    }
  }

  // 배치 저장 큐와 플러시 로직
  final List<Map<String, dynamic>> _pendingSaves = [];
  Future<void> _flushPendingSaves() async {
    if (_pendingSaves.isEmpty) return;
    final saves = List<Map<String, dynamic>>.from(_pendingSaves);
    _pendingSaves.clear();
    try {
      // SQL 단일화: SharedPreferences 제거, SQL만 사용
      // 서버 전환: 클라이언트 top_stocks 접근 제거
      final toSave = <Map<String, dynamic>>[];
      for (final s in saves) {
        final code = s['stockCode'] as String;
        final name = _appDataManager.getStockName(code);
        final market = s['market'] as String;
        final score = (s['score'] as num).toDouble();
        final cached = _appDataManager.getCachedStockData(code);
        final currentPrice = (cached['currentPrice'] ?? cached['prpr'] ?? 0.0).toDouble();
        toSave.add({
          'stockCode': code,
          'stockName': name,
          'market': market,
          'score': score,
          'currentPrice': currentPrice,
          'priceChange': 0.0,
          'priceChangeRate': 0.0,
          'volume': (cached['volume'] ?? cached['acml_vol'] ?? 0).toInt(),
          'volumeRatio': 1.0,
          'rank': 0,
        });
      }
      if (toSave.isNotEmpty) {
        // 비동기 배치 저장으로 트랜잭션 락 최소화 (지연 실행)
        Future.delayed(const Duration(milliseconds: 50), () async {
          try {
            // 저장 스킵 (서버 Functions 전용)
            print('📊 배치 점수 계산 완료(서버 저장 스킵): ${toSave.length}개');
          } catch (e) {
            print('⚠️ SQL 배치 저장 실패: $e');
          }
        });
      }
    } catch (e) {
      print('❌ 배치 저장 실패: $e');
    }
  }

  /// 단일 시장을 즉시 스캔하여 점수를 계산하고 캐시에 저장
  /// 화면에서 NASDAQ/KOSPI/KOSDAQ 버튼을 눌렀을 때 호출됨
  Future<void> scanMarketOnce(String market) async {
    try {
      // 기존 RecommendedStocksData에서 모든 종목 가져오기
      final allStocksMap = await _recommendedStocksData.getAllStocks();

      // Map<String, String> -> List<Map<String, dynamic>> 형태 변환 + 시장 식별
      final List<Map<String, dynamic>> allStocks = allStocksMap.entries.map((e) => {
        'stock_code': e.key,
        'stock_name': e.value,
        'market': _getMarketFromSymbol(e.key),
      }).toList();

      _isServiceRunning = true; // 진행 표시를 위해 실행 상태로 설정
      _currentMarket = market;
      _calculatedStocksCount = 0;
      _totalStocksCount = allStocks.where((s) => s['market'] == market).length;
      _marketProgress[market] = 0;
      _notifyProgress();

      await _processMarketStocksResume(market, allStocks);

    } catch (e) {
      print('❌ scanMarketOnce 실패: $e');
    } finally {
      _isServiceRunning = false;
      _notifyProgress();
    }
  }

  /// 종목 점수 저장 (기존 RecommendedStocksRepository 활용)
  Future<void> _saveStockScore(String stockCode, double score, String market) async {
    try {
      // 기존 RecommendedStocksData의 updateStockScore 메서드 활용
      await _recommendedStocksData.updateStockScore(stockCode, score, metadata: {
        'market': market,
        'timestamp': DateTime.now().toIso8601String(),
        'source': 'background_service',
      });
      
      print('💾 $stockCode 점수 저장 완료: $score ($market)');
      
      // 실시간 상위 종목 업데이트 (락 방지를 위해 지연)
      await Future.delayed(const Duration(milliseconds: 100));
      await _updateTopStocksForMarket(market);
      
    } catch (e) {
      print('❌ $stockCode 점수 저장 실패: $e');
    }
  }

  /// 상위 종목 업데이트
  Future<void> _updateTopStocks() async {
    if (!_isServiceRunning) return;
    
    print('📈 상위 종목 업데이트...');
    
    try {
      // 시장별 상위 10개 조회
      final markets = ['KOSPI', 'KOSDAQ', 'NASDAQ', 'NYSE'];
      final topStocks = <Map<String, dynamic>>[];
      
      for (final market in markets) {
        await _updateTopStocksForMarket(market);
        final marketTopStocks = await _getTopStocksForMarket(market, 10);
        topStocks.addAll(marketTopStocks);
      }
      
      // 상위 종목 업데이트 알림
      onTopStocksUpdated?.call(topStocks);
      
      _lastUpdateTime = DateTime.now();
      print('✅ 상위 종목 업데이트 완료: ${topStocks.length}개');
      
    } catch (e) {
      print('❌ 상위 종목 업데이트 실패: $e');
    }
  }
  
  /// 특정 시장의 상위 종목 업데이트
  Future<void> _updateTopStocksForMarket(String market) async {
    try {
      final topStocks = await _getTopStocksForMarket(market, 10);
      
      if (topStocks.isNotEmpty) {
        // 캐시 업데이트
        _topStocksCache[market] = topStocks;
        
        print('📊 $market 상위 10개 업데이트: ${topStocks.length}개');
        
        // UI 콜백 호출 (시장 정보 포함)
        onTopStocksUpdated?.call(topStocks.map((stock) => {
          ...stock,
          'market': market,
        }).toList());
      }
      
    } catch (e) {
      print('❌ $market 상위 종목 업데이트 실패: $e');
    }
  }

  /// 전체 종목 조회 (기존 RecommendedStocksData 활용)
  Future<List<Map<String, dynamic>>> _getAllStocks() async {
    try {
      print('📊 기존 RecommendedStocksData에서 8397개 종목 조회...');
      
      // 기존 RecommendedStocksData에서 모든 종목 가져오기
      final allStocks = await _recommendedStocksData.getAllStocks();
      print('✅ 기존 종목 목록 조회 완료: ${allStocks.length}개');
      
      // Map<String, String> 형태를 List<Map<String, dynamic>> 형태로 변환
      final stockList = allStocks.entries.map((entry) {
        final symbol = entry.key;
        final name = entry.value;
        final market = _getMarketFromSymbol(symbol);
        
        return {
          'stock_code': symbol,
          'stock_name': name,
          'market': market,
        };
      }).toList();
      
      // 거래대금 필터링 적용
      final tradingAmountFiltered = await _filterStocksByTradingAmount(stockList);
      print('💰 거래대금 필터링 적용: ${stockList.length}개 → ${tradingAmountFiltered.length}개');
      
      // 국내주식(코스피/코스닥)만 개별주 필터링 적용 (ETF/ETN/펀드 제외)
      final individualStocks = <Map<String, dynamic>>[];
      final marketStats = <String, int>{};
      final filteredMarketStats = <String, int>{};
      
      for (final stock in tradingAmountFiltered) {
        final market = stock['market'] ?? '';
        marketStats[market] = (marketStats[market] ?? 0) + 1;
        
        if (market == 'KOSPI' || market == 'KOSDAQ') {
          // 국내주식만 개별주 필터링
          if (!StockFilterUtils.isNonIndividualStockByName(stock['stock_name'] ?? '')) {
            individualStocks.add(stock);
            filteredMarketStats[market] = (filteredMarketStats[market] ?? 0) + 1;
          } else {
            print('🚫 국내 ETF/ETN/펀드 제외: ${stock['stock_name']} (${stock['stock_code']})');
          }
        } else {
          // 해외주식(나스닥/뉴욕)은 필터링 없이 포함
          individualStocks.add(stock);
          filteredMarketStats[market] = (filteredMarketStats[market] ?? 0) + 1;
        }
      }
      
      print('📈 국내주식 개별주 필터링 적용: ${tradingAmountFiltered.length}개 → ${individualStocks.length}개');
      print('📊 시장별 필터링 결과:');
      for (final market in marketStats.keys) {
        final total = marketStats[market] ?? 0;
        final filtered = filteredMarketStats[market] ?? 0;
        final rate = total > 0 ? (filtered / total * 100).toStringAsFixed(1) : '0.0';
        print('  - $market: $total개 → $filtered개 (${rate}%)');
      }
      
      final filteredStocks = individualStocks;
      
      print('📊 최종 분석 대상 종목 수: ${filteredStocks.length}개');
      
      return filteredStocks;
      
    } catch (e) {
      print('❌ 전체 종목 조회 실패: $e');
      return [];
    }
  }
  
  /// 거래대금 기준으로 종목 필터링
  Future<List<Map<String, dynamic>>> _filterStocksByTradingAmount(List<Map<String, dynamic>> stocks) async {
    try {
      print('💰 거래대금 필터링 시작: 최소 ${(_minTradingAmount / 100000000).toStringAsFixed(1)}억원');
      
      final filteredStocks = <Map<String, dynamic>>[];
      int processedCount = 0;
      
      for (final stock in stocks) {
        final stockCode = stock['stock_code'] as String;
        final market = stock['market'] as String;
        
        try {
          // 현재가와 거래량 조회
          double? currentPrice;
          double? volume;
          // 최근 거래일 확인을 위한 변수 (YYYYMMDD or ISO)
          DateTime? lastDataDate;
          
          final priceData = _appDataManager.getCachedStockData(stockCode);
          // 우선 표준 키 → 폴백 구 키 순으로 읽기
          currentPrice = (priceData['currentPrice'] as num?)?.toDouble()
              ?? (priceData['prpr'] as num?)?.toDouble();
          volume = (priceData['volume'] as num?)?.toDouble()
              ?? (priceData['acml_vol'] as num?)?.toDouble();
          // 캐시 타임스탬프
          final ts = (priceData['timestamp'] as String?) ?? '';
          if (ts.isNotEmpty) {
            try { lastDataDate = DateTime.tryParse(ts); } catch (_) {}
          }

          // 캐시/차트로도 없으면, 레이트리밋을 적용해 API로 단건 보강 시도
          if ((currentPrice == null || currentPrice == 0) || (volume == null || volume == 0)) {
            final price = await _rateLimitedGetPrice(stockCode);
            if (price != null && price.isNotEmpty) {
              currentPrice = currentPrice ?? (price['currentPrice'] as num?)?.toDouble()
                  ?? (price['prpr'] as num?)?.toDouble();
              volume = volume ?? (price['volume'] as num?)?.toDouble()
                  ?? (price['acml_vol'] as num?)?.toDouble();
              // 캐시 보강
              try {
                // 🔄 거래량 덮어쓰기 방지 - volume 제외하고 업데이트
                _appDataManager.updateCurrentPrice(stockCode, {
                  'currentPrice': currentPrice ?? 0.0,
                  'prevClose': (price['prevClose'] as num?)?.toDouble() ?? 0.0,
                  // 'volume': volume ?? 0.0,  // ← 거래량 덮어쓰기 방지
                  'timestamp': DateTime.now().toIso8601String(),
                });
                lastDataDate = DateTime.now();
              } catch (_) {}
            }
          }

          // 폴백: 로컬 차트 마지막 봉 사용 (전일 종가/거래량 추정)
          if ((currentPrice == null || currentPrice == 0) || (volume == null || volume == 0)) {
            try {
              final bars = await _appDataManager.historicalDataRepo.getRecentBars(stockCode, limit: 2);
              if (bars.isNotEmpty) {
                final last = bars.last;
                currentPrice = currentPrice ?? (last['close'] as num?)?.toDouble();
                volume = volume ?? (last['volume'] as num?)?.toDouble();
                // 최근 거래일 추출(YYYYMMDD)
                final d = last['date'];
                if (d != null) {
                  try {
                    final s = d.toString();
                    if (RegExp(r'^\d{8}$').hasMatch(s)) {
                      lastDataDate = DateTime(
                        int.parse(s.substring(0,4)),
                        int.parse(s.substring(4,6)),
                        int.parse(s.substring(6,8)),
                      );
                    }
                  } catch (_) {}
                }
              }
            } catch (_) {}
          }

          // 여전히 데이터가 없으면 스킵 (API 500/레이트 초과 시)
          if ((currentPrice == null || currentPrice == 0) || (volume == null || volume == 0)) {
            processedCount++;
            if (processedCount % 200 == 0) {
              print('⚠️ 거래대금 필터: 데이터 부족으로 스킵 누적 $processedCount/${stocks.length}');
            }
            continue;
          }

          // 추가 규칙: 최근 거래일이 10일 이상 과거이면 제외(상폐/장기정지 추정)
          try {
            // 차트 기반이 최우선, 없으면 캐시 타임스탬프
            final refDate = lastDataDate ?? DateTime.now();
            final tenDaysAgo = DateTime.now().subtract(const Duration(days: 10));
            if (refDate.isBefore(tenDaysAgo)) {
              if (market == 'KOSPI' || market == 'KOSDAQ') {
                print('🚫 거래중단(10일↑) 제외: $stockCode (${refDate.toIso8601String().substring(0,10)})');
              }
              processedCount++;
              continue;
            }
          } catch (_) {}
          
          if (currentPrice != null && volume != null) {
            double tradingAmount;
            
            if (market == 'KOSPI' || market == 'KOSDAQ') {
              // 국내 주식: 원화 단위 그대로 사용
              tradingAmount = currentPrice * volume;
            } else {
              // 해외 주식: 달러를 원화로 변환
              // TODO: 실시간 환율 API 연동 필요
              // 현재는 고정 환율 사용 (1달러 = 1400원)
              const double usdToKrw = 1400.0;
              tradingAmount = (currentPrice * volume) * usdToKrw;
              
              print('💱 해외주식 거래대금 변환: \$${currentPrice} × $volume × $usdToKrw = ₩${tradingAmount.toStringAsFixed(0)}');
            }
            
            if (tradingAmount >= _minTradingAmount) {
              filteredStocks.add({
                ...stock,
                'current_price': currentPrice,
                'volume': volume,
                'trading_amount': tradingAmount,
                'currency': market == 'KOSPI' || market == 'KOSDAQ' ? 'KRW' : 'USD',
              });
            } else {
              // 거래대금 부족으로 제외된 경우 (코스닥만 로그 출력)
              if (market == 'KOSDAQ') {
                print('💰 코스닥 거래대금 부족: ${stock['stock_name']} (${(tradingAmount / 100000000).toStringAsFixed(1)}억원)');
              }
            }
          }
          
          processedCount++;
          if (processedCount % 100 == 0) {
            print('💰 거래대금 필터링 진행: $processedCount/${stocks.length} (${filteredStocks.length}개 통과)');
          }
          
          // API 부하 방지를 위한 간격
          if (processedCount % 10 == 0) {
            await Future.delayed(const Duration(milliseconds: 50));
          }
          
        } catch (e) {
          // 개별 종목 조회 실패 시 건너뛰기
          continue;
        }
      }
      
      print('✅ 거래대금 필터링 완료: ${stocks.length}개 → ${filteredStocks.length}개');
      return filteredStocks;
      
    } catch (e) {
      print('❌ 거래대금 필터링 실패: $e');
      return stocks; // 필터링 실패 시 원본 반환
    }
  }

  /// 종목 코드로 시장 구분 (기존 AiRecommendationService 로직 활용)
  String _getMarketFromSymbol(String symbol) {
    return MarketTimeValidator.instance.getMarketFromSymbol(symbol);
  }

  /// 시장별 상위 종목 조회 (기존 RecommendedStocksData 활용)
  Future<List<Map<String, dynamic>>> _getTopStocksForMarket(String market, int limit) async {
    try {
      // 기존 RecommendedStocksData에서 모든 종목 가져오기
      final allStocks = await _recommendedStocksData.getAllStocks();
      
      // 시장별 필터링 및 점수 기준 정렬
      final marketStocks = <Map<String, dynamic>>[];
      
      for (final entry in allStocks.entries) {
        final symbol = entry.key;
        final name = entry.value;
        final stockMarket = _getMarketFromSymbol(symbol);
        
        if (stockMarket == market) {
          // 국내주식(코스피/코스닥)만 개별주 필터링 적용
          if (market == 'KOSPI' || market == 'KOSDAQ') {
            if (StockFilterUtils.isNonIndividualStockByName(name)) {
              print('🚫 국내 ETF/ETN/펀드 제외: $name ($symbol)');
              continue;
            }
          }
          // 해외주식(나스닥/뉴욕)은 필터링 없이 포함
          
          // 점수 조회 (기존 시스템에서)
          final score = await _recommendedStocksData.getStockScore(symbol) ?? 0.0;
          
          marketStocks.add({
            'stock_code': symbol,
            'stock_name': name,
            'market': market,
            'score': score,
          });
        }
      }
      
      // 점수 기준 내림차순 정렬
      marketStocks.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
      
      // 상위 N개 반환
      final topStocks = marketStocks.take(limit).toList();
      print('📈 $market 상위 $limit개 종목 조회 완료: ${topStocks.length}개');
      
      return topStocks;
      
    } catch (e) {
      print('❌ $market 상위 종목 조회 실패: $e');
      return [];
    }
  }

  /// 진행률 알림
  void _notifyProgress() {
    final progress = calculationProgress;
    final currentIndex = _calculatedStocksCount;
    final totalIndex = _totalStocksCount;
    
    onCalculationProgress?.call({
      'totalStocks': _totalStocksCount,
      'calculatedStocks': _calculatedStocksCount,
      'progress': progress,
      'currentMarket': _currentMarket,
      'currentStock': _currentStock,
      'currentIndex': currentIndex,
      'totalIndex': totalIndex,
      'marketProgress': Map.from(_marketProgress),
    });
    
    // 진행 상황 로그 출력
    if (currentIndex % 100 == 0 || progress >= 1.0) {
      print('📊 진행 상황: $currentIndex/$totalIndex (${(progress * 100).toStringAsFixed(1)}%) - $_currentMarket');
    }
  }

  /// 서비스 정리
  Future<void> dispose() async {
    await stopService();
  }
}
