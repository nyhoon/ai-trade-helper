import 'dart:async';
import 'dart:math';
import '../data/app_data_manager.dart';
import '../analysis/unified_analysis_service.dart';
import '../database/repositories/stock_prices_repository.dart';
import '../database/repositories/chart_data_repository.dart';
import '../trading/investment_style_manager.dart';
import '../remote/analysis_functions_service.dart';

/// 실시간 점수 계산 및 스트림 서비스
/// 기존 실시간 파이프라인과 통합하여 점수를 실시간으로 계산하고 상위 종목을 추출
class RealtimeScoreService {
  static final RealtimeScoreService _instance = RealtimeScoreService._internal();
  factory RealtimeScoreService() => _instance;
  RealtimeScoreService._internal();

  // Repository 인스턴스
  final StockPricesRepository _priceRepo = StockPricesRepository();
  final ChartDataRepository _chartRepo = ChartDataRepository();
  final InvestmentStyleManager _styleManager = InvestmentStyleManager();
  
  // 실시간 점수 스트림
  final StreamController<Map<String, dynamic>> _scoreController = 
      StreamController<Map<String, dynamic>>.broadcast();
  
  // 상위 점수 종목 스트림
  final StreamController<List<Map<String, dynamic>>> _topStocksController = 
      StreamController<List<Map<String, dynamic>>>.broadcast();
  
  // 타이머
  Timer? _scoreUpdateTimer;
  Timer? _topStocksUpdateTimer;
  
  // 상태 관리
  bool _isRunning = false;
  final Map<String, double> _lastScores = {};
  final Map<String, DateTime> _lastScoreTimes = {};
  
  // 현재 분석 중인 종목 추적
  String _currentAnalyzingStock = '';
  String _currentAnalyzingStockName = '';
  int _totalStocksCount = 0;
  
  // 설정
  static const Duration _scoreUpdateInterval = Duration(seconds: 10); // 10초마다 점수 업데이트
  static const Duration _topStocksUpdateInterval = Duration(seconds: 30); // 30초마다 상위 종목 업데이트
  static const int _maxTopStocks = 100; // 상위 100개만 유지
  static const double _minScoreThreshold = 0.3; // 최소 점수 임계값
  
  // 스트림 getter
  Stream<Map<String, dynamic>> get scoreStream => _scoreController.stream;
  Stream<List<Map<String, dynamic>>> get topStocksStream => _topStocksController.stream;

  /// 서비스 시작
  Future<void> start() async {
    if (_isRunning) return;
    
    try {
      print('🔄 실시간 점수 서비스 시작...');
      
      _isRunning = true;
      
      // 필요한 테이블 생성
      try {
        await _priceRepo.createTable();
        await _chartRepo.createTable();
        print('✅ 데이터베이스 테이블 생성 완료');
      } catch (e) {
        print('❌ 데이터베이스 테이블 생성 실패: $e');
      }
      
      // 점수 업데이트 타이머 시작
      _startScoreUpdateTimer();
      
      // 상위 종목 업데이트 타이머 시작
      _startTopStocksUpdateTimer();
      
      // 초기 점수 계산
      await _performInitialScoreCalculation();
      
      print('✅ 실시간 점수 서비스 시작 완료');
      
    } catch (e) {
      print('❌ 실시간 점수 서비스 시작 실패: $e');
      _isRunning = false;
    }
  }

  /// 서비스 중지
  void stop() {
    if (!_isRunning) return;
    
    _scoreUpdateTimer?.cancel();
    _topStocksUpdateTimer?.cancel();
    _isRunning = false;
    
    print('⏹️ 실시간 점수 서비스 중지');
  }

  /// 점수 업데이트 타이머 시작
  void _startScoreUpdateTimer() {
    _scoreUpdateTimer?.cancel();
    _scoreUpdateTimer = Timer.periodic(_scoreUpdateInterval, (timer) async {
      if (_isRunning) {
        await _performScoreUpdate();
      }
    });
    print('⏰ 점수 업데이트 타이머 시작 (${_scoreUpdateInterval.inSeconds}초 간격)');
  }

  /// 상위 종목 업데이트 타이머 시작
  void _startTopStocksUpdateTimer() {
    _topStocksUpdateTimer?.cancel();
    _topStocksUpdateTimer = Timer.periodic(_topStocksUpdateInterval, (timer) async {
      if (_isRunning) {
        await _performTopStocksUpdate();
      }
    });
    print('⏰ 상위 종목 업데이트 타이머 시작 (${_topStocksUpdateInterval.inSeconds}초 간격)');
  }

  /// 초기 점수 계산
  Future<void> _performInitialScoreCalculation() async {
    try {
      print('📊 초기 점수 계산 시작...');
      
      // 활성 종목 목록 조회
      final activeStocks = await _getActiveStocks();
      if (activeStocks.isEmpty) {
        print('⚠️ 활성 종목이 없습니다.');
        return;
      }
      
      _totalStocksCount = activeStocks.length;
      print('📋 활성 종목: ${activeStocks.length}개');
      
      // 초기 계산은 최소한만 수행 (성능 최적화)
      final limitedStocks = activeStocks.take(10).toList(); // 처음 10개만 (더 적게)
      print('📊 초기 계산 대상: ${limitedStocks.length}개 (전체 ${activeStocks.length}개 중)');
      
      // 배치 처리로 성능 향상 (동시 처리 수 제한)
      const int batchSize = 3; // 동시 처리할 종목 수를 더 적게
      final batches = <List<Map<String, dynamic>>>[];
      
      for (int i = 0; i < limitedStocks.length; i += batchSize) {
        final end = (i + batchSize < limitedStocks.length) ? i + batchSize : limitedStocks.length;
        batches.add(limitedStocks.sublist(i, end));
      }
      
      // 각 배치를 순차적으로 처리 (메모리 사용량 제한)
      for (final batch in batches) {
        final futures = batch.map((stock) => 
          _calculateStockScore(stock['stock_code'], stock['market']));
        
        await Future.wait(futures, eagerError: false);
        
        // 배치 간 짧은 대기 (시스템 부하 분산)
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      // 상위 종목 업데이트
      await _performTopStocksUpdate();
      
      print('✅ 초기 점수 계산 완료');
      
    } catch (e) {
      print('❌ 초기 점수 계산 실패: $e');
    }
  }

  /// 점수 업데이트 수행
  Future<void> _performScoreUpdate() async {
    try {
      // 활성 종목 목록 조회
      final activeStocks = await _getActiveStocks();
      if (activeStocks.isEmpty) return;
      
      // 각 종목별 점수 계산 (병렬 처리)
      final futures = activeStocks.map((stock) => 
        _calculateStockScore(stock['stock_code'], stock['market']));
      
      await Future.wait(futures, eagerError: false);
      
    } catch (e) {
      print('❌ 점수 업데이트 실패: $e');
    }
  }

  /// 상위 종목 업데이트 수행
  Future<void> _performTopStocksUpdate() async {
    try {
      // 현재 점수 기준으로 상위 종목 선정
      final topStocks = await _getTopStocks();
      
      // 스트림으로 발행
      _topStocksController.add(topStocks);
      
      print('📈 상위 종목 업데이트: ${topStocks.length}개');
      
    } catch (e) {
      print('❌ 상위 종목 업데이트 실패: $e');
    }
  }

  /// 개별 종목 점수 계산
  Future<void> _calculateStockScore(String stockCode, String market) async {
    try {
      // 현재 분석 중인 종목 업데이트
      _currentAnalyzingStock = stockCode;
      _currentAnalyzingStockName = AppDataManager.instance.getStockName(stockCode);
      
      // 중복 계산 방지 (최근 30초 내 계산된 경우 스킵)
      final lastTime = _lastScoreTimes[stockCode];
      if (lastTime != null && 
          DateTime.now().difference(lastTime).inSeconds < 30) {
        return;
      }
      
      // 현재가 조회
      final currentPrice = await _priceRepo.getLatestPrice(stockCode);
      if (currentPrice == null) return;
      
      // 차트 데이터 조회 (최근 20일)
      final chartData = await _chartRepo.getChartData(
        stockCode,
        limit: 20,
      );
      
      if (chartData.isEmpty) return;
      
      // 지표 데이터 준비
      final indicatorData = _prepareIndicatorData(chartData, currentPrice);
      
      // 통합 분석 서비스를 통한 점수 계산
      final unifiedAnalysis = UnifiedAnalysisService.instance;
      final analysisResult = await unifiedAnalysis.analyzeStock(
        stockCode,
        currentPrice: currentPrice,
      ) ?? <String, dynamic>{};
      
      final score = analysisResult['compositeScore'] ?? 0.0;
      
      // 점수 저장 및 스트림 발행
      _lastScores[stockCode] = score;
      _lastScoreTimes[stockCode] = DateTime.now();
      
      _scoreController.add({
        'stockCode': stockCode,
        'market': market,
        'score': score,
        'currentPrice': currentPrice,
        'timestamp': DateTime.now().toIso8601String(),
        'analysisResult': analysisResult,
      });
      
    } catch (e) {
      print('❌ $stockCode 점수 계산 실패: $e');
    }
  }

  /// 지표 데이터 준비
  Map<String, dynamic> _prepareIndicatorData(
    List<Map<String, dynamic>> chartData, 
    double currentPrice
  ) {
    if (chartData.isEmpty) return {};
    
    final latest = chartData.first;
    final previous = chartData.length > 1 ? chartData[1] : latest;
    
    // 거래량 계산
    final volumes = chartData.map((d) => d['volume'] as int? ?? 0).toList();
    final averageVolume = volumes.reduce((a, b) => a + b) / volumes.length;
    final currentVolume = latest['volume'] as int? ?? 0;
    
    // 가격 변동률 계산
    final previousPrice = previous['close'] as double? ?? currentPrice;
    final priceChange = currentPrice - previousPrice;
    final priceChangeRate = previousPrice != 0 ? priceChange / previousPrice : 0.0;
    
    return {
      'currentPrice': currentPrice,
      'previousPrice': previousPrice,
      'priceChange': priceChange,
      'priceChangeRate': priceChangeRate,
      'currentVolume': currentVolume,
      'averageVolume': averageVolume.toInt(),
      'volumeRatio': averageVolume > 0 ? currentVolume / averageVolume : 1.0,
      'chartData': chartData,
    };
  }

  /// 상위 점수 종목 조회
  Future<List<Map<String, dynamic>>> _getTopStocks() async {
    try {
      // 점수 기준으로 정렬
      final sortedStocks = _lastScores.entries
          .where((entry) => entry.value >= _minScoreThreshold)
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      
      // 상위 N개만 선택
      final topStocks = sortedStocks
          .take(_maxTopStocks)
          .map((entry) async {
            final stockCode = entry.key;
            final score = entry.value;
            
            // 추가 정보 조회
            final currentPrice = await _priceRepo.getLatestPrice(stockCode);
            final stockInfo = await _getStockInfo(stockCode);
            
            return {
              'stockCode': stockCode,
              'stockName': stockInfo['name'] ?? stockCode,
              'market': stockInfo['market'] ?? 'UNKNOWN',
              'score': score,
              'currentPrice': currentPrice ?? 0.0,
              'timestamp': _lastScoreTimes[stockCode]?.toIso8601String() ?? 
                          DateTime.now().toIso8601String(),
            };
          })
          .toList();
      
      return await Future.wait(topStocks);
      
    } catch (e) {
      print('❌ 상위 종목 조회 실패: $e');
      return [];
    }
  }

  /// 종목 정보 조회
  Future<Map<String, dynamic>> _getStockInfo(String stockCode) async {
    try {
      // AppDataManager에서 종목명 조회 (마스터/캐시 일원화)
      final stockName = AppDataManager.instance.getStockName(stockCode);
      
      return {
        'name': stockName ?? stockCode,
        'market': _isKoreanStock(stockCode) ? 'KR' : 'US',
      };
    } catch (e) {
      return {
        'name': stockCode,
        'market': 'UNKNOWN',
      };
    }
  }

  /// 한국 주식 여부 확인
  bool _isKoreanStock(String symbol) {
    return symbol.length == 6 && int.tryParse(symbol) != null;
  }

  /// 활성 종목 목록 조회
  Future<List<Map<String, dynamic>>> _getActiveStocks() async {
    try {
      // 데이터베이스에서 실제 종목 데이터 가져오기
      final stockRepository = AppDataManager.instance.stockRepository;
      final allStocks = await stockRepository.getAllStocks();
      
      // 요청: ETF 제외 해제. 모든 상장 종목을 대상으로 사용
      final filteredStocks = allStocks.toList();
      
      print('📊 전체 종목: ${allStocks.length}개, 필터링 후: ${filteredStocks.length}개');
      
      return filteredStocks.map((stock) => {
        'stock_code': stock['stock_code'],
        'stock_name': stock['stock_name'],
        'market': stock['market'],
      }).toList();
      
    } catch (e) {
      print('❌ 활성 종목 목록 조회 실패: $e');
      return [];
    }
  }

  /// 특정 종목의 현재 점수 조회
  double? getCurrentScore(String stockCode) {
    return _lastScores[stockCode];
  }

  /// 상위 점수 종목 즉시 조회
  Future<List<Map<String, dynamic>>> getTopStocks({
    int limit = 50,
    double minScore = 0.3,
    String? market,
  }) async {
    try {
      final topStocks = await _getTopStocks();
      
      var filtered = topStocks.where((stock) => 
        stock['score'] >= minScore);
      
      if (market != null) {
        filtered = filtered.where((stock) => 
          stock['market'] == market);
      }
      
      return filtered.take(limit).toList();
      
    } catch (e) {
      print('❌ 상위 점수 종목 조회 실패: $e');
      return [];
    }
  }

  /// 서비스 상태 조회
  Map<String, dynamic> getServiceStatus() {
    return {
      'isRunning': _isRunning,
      'totalStocks': _totalStocksCount,
      'calculatedStocksCount': _lastScores.length,
      'currentStock': _currentAnalyzingStock,
      'currentStockName': _currentAnalyzingStockName,
      'lastUpdateTime': _lastScoreTimes.isNotEmpty 
          ? _lastScoreTimes.values.reduce((a, b) => a.isAfter(b) ? a : b)
          : null,
      'scoreUpdateInterval': _scoreUpdateInterval.inSeconds,
      'topStocksUpdateInterval': _topStocksUpdateInterval.inSeconds,
    };
  }

  final AnalysisFunctionsService _functions = AnalysisFunctionsService();

  Future<Map<String, dynamic>> analyzeStock(String symbol, {int days = 100}) async {
    return await _functions.analyzeStock(symbol: symbol, days: days);
  }
}
