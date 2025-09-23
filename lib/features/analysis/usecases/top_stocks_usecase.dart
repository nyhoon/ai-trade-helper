import '../../../core/database/repositories/top_stocks_repository.dart';
import '../../../core/services/realtime_score_service.dart';
import '../../../core/data/app_data_manager.dart';
import '../../../core/data/recommended_stocks_data.dart';

/// 상위 점수 종목 UseCase
/// MVI 패턴의 Domain 계층에서 비즈니스 로직 처리
class TopStocksUseCase {
  final TopStocksRepository _repository;
  final RealtimeScoreService _scoreService;
  
  TopStocksUseCase({
    TopStocksRepository? repository,
    RealtimeScoreService? scoreService,
  }) : _repository = repository ?? TopStocksRepository(),
       _scoreService = scoreService ?? RealtimeScoreService();

  /// 상위 점수 종목 조회
  Future<List<Map<String, dynamic>>> getTopStocks({
    int limit = 50,
    double minScore = 0.3,
    String? market,
    bool useCache = true,
  }) async {
    try {
      // 캐시 사용 시 DB에서 조회
      if (useCache) {
        final cachedStocks = await _repository.getTopStocks(
          limit: limit,
          minScore: minScore,
          market: market,
          maxAgeMinutes: 5, // 5분 이내 데이터만 사용
        );
        
        // 캐시된 데이터가 충분하면 반환
        if (cachedStocks.length >= limit * 0.8) {
          return cachedStocks;
        }
      }
      
      // 실시간 서비스에서 최신 데이터 조회
      final realtimeStocks = await _scoreService.getTopStocks(
        limit: limit,
        minScore: minScore,
        market: market,
      );
      
      return realtimeStocks;
      
    } catch (e) {
      print('❌ 상위 점수 종목 조회 실패: $e');
      return [];
    }
  }

  /// 시장별 상위 점수 종목 조회
  Future<List<Map<String, dynamic>>> getTopStocksByMarket({
    required String market,
    int limit = 50,
    double minScore = 0.3,
  }) async {
    try {
      // 최소 거래대금: 국내(10억원 KRW), 해외(10억원/고정환율 USD)
      const double krwBase = 1000000000; // 10억원
      const double usdRate = 1400.0; // TODO: 환율 API 연동
      final bool isKr = (market == 'KOSPI' || market == 'KOSDAQ');
      final bool isUs = (market == 'NASDAQ' || market == 'NYSE');
      final double? minTradingAmountKrw = isKr ? krwBase : null;
      final double? minTradingAmountUsd = isUs ? (krwBase / usdRate) : null;
      return await _repository.getTopStocksByMarket(
        market: market,
        limit: limit,
        minScore: minScore,
        minTradingAmountKrw: minTradingAmountKrw,
        minTradingAmountUsd: minTradingAmountUsd,
      );
    } catch (e) {
      print('❌ 시장별 상위 점수 종목 조회 실패: $e');
      return [];
    }
  }

  /// 점수 범위별 종목 조회
  Future<List<Map<String, dynamic>>> getStocksByScoreRange({
    required double minScore,
    required double maxScore,
    int limit = 100,
    String? market,
  }) async {
    try {
      return await _repository.getStocksByScoreRange(
        minScore: minScore,
        maxScore: maxScore,
        limit: limit,
        market: market,
      );
    } catch (e) {
      print('❌ 점수 범위별 종목 조회 실패: $e');
      return [];
    }
  }

  /// 특정 종목의 점수 조회
  Future<Map<String, dynamic>?> getStockScore(String stockCode) async {
    try {
      // 실시간 서비스에서 먼저 조회
      final realtimeScore = _scoreService.getCurrentScore(stockCode);
      if (realtimeScore != null) {
        return {
          'stockCode': stockCode,
          'score': realtimeScore,
          'source': 'realtime',
          'timestamp': DateTime.now().toIso8601String(),
        };
      }
      
      // DB에서 조회
      return await _repository.getStockScore(stockCode);
      
    } catch (e) {
      print('❌ 종목 점수 조회 실패: $e');
      return null;
    }
  }

  /// 상위 점수 종목 통계 조회
  Future<Map<String, dynamic>> getTopStocksStatistics() async {
    try {
      return await _repository.getTopStocksStatistics();
    } catch (e) {
      print('❌ 상위 점수 종목 통계 조회 실패: $e');
      return {};
    }
  }

  /// 실시간 점수 스트림 구독
  Stream<Map<String, dynamic>> getScoreStream() {
    return _scoreService.scoreStream;
  }

  /// 실시간 상위 종목 스트림 구독
  Stream<List<Map<String, dynamic>>> getTopStocksStream() {
    return _scoreService.topStocksStream;
  }

  /// 실시간 점수 서비스 시작
  Future<void> startRealtimeScoreService() async {
    try {
      await _scoreService.start();
      print('✅ 실시간 점수 서비스 시작 완료');
    } catch (e) {
      print('❌ 실시간 점수 서비스 시작 실패: $e');
    }
  }

  /// 실시간 점수 서비스 중지
  void stopRealtimeScoreService() {
    _scoreService.stop();
    print('⏹️ 실시간 점수 서비스 중지');
  }

  /// 서비스 상태 조회
  Map<String, dynamic> getServiceStatus() {
    return _scoreService.getServiceStatus();
  }

  /// 데이터 초기화
  Future<void> initializeData() async {
    try {
      // 테이블 생성
      await _repository.createTopStocksTable();
      // market 필드 정규화 (비동기 실행으로 초기 체감 개선)
      // ignore: unawaited_futures
      _repository.normalizeStoredMarkets();
      
      // 실시간 서비스 시작
      await startRealtimeScoreService();
      
      print('✅ 상위 점수 종목 데이터 초기화 완료');
      
    } catch (e) {
      print('❌ 상위 점수 종목 데이터 초기화 실패: $e');
      rethrow;
    }
  }

  /// 데이터 정리
  Future<void> cleanupData({int daysOld = 30}) async {
    try {
      await _repository.cleanupOldData(daysOld: daysOld);
      print('✅ 상위 점수 종목 데이터 정리 완료');
    } catch (e) {
      print('❌ 상위 점수 종목 데이터 정리 실패: $e');
    }
  }

  /// 추천 종목에 상위 점수 종목 추가
  Future<bool> addTopStocksToRecommended({
    int limit = 20,
    double minScore = 0.5,
    String? market,
  }) async {
    try {
      // 상위 점수 종목 조회
      final topStocks = await getTopStocks(
        limit: limit,
        minScore: minScore,
        market: market,
      );
      
      if (topStocks.isEmpty) {
        print('⚠️ 추가할 상위 점수 종목이 없습니다.');
        return false;
      }
      
      // 추천 종목 데이터에 추가 (AppDataManager의 SymbolStore/DB 사용으로 대체 가능)
      // 기존 구조 유지: RecommendedStocksData 사용
      final recommendedStocks = RecommendedStocksData();
      final stocksToAdd = <String, String>{};
      
      for (final stock in topStocks) {
        final stockCode = stock['stockCode'] as String;
        final stockName = stock['stockName'] as String;
        stocksToAdd[stockCode] = stockName;
      }
      
      await recommendedStocks.addManyStocks(stocksToAdd);
      
      print('✅ 상위 점수 종목 ${stocksToAdd.length}개를 추천 종목에 추가 완료');
      return true;
      
    } catch (e) {
      print('❌ 상위 점수 종목 추천 종목 추가 실패: $e');
      return false;
    }
  }

  /// 추천 종목에서 상위 점수 종목 제거
  Future<bool> removeTopStocksFromRecommended({
    int limit = 20,
    double maxScore = 0.3,
    String? market,
  }) async {
    try {
      // 낮은 점수 종목 조회
      final lowScoreStocks = await getStocksByScoreRange(
        minScore: 0.0,
        maxScore: maxScore,
        limit: limit,
        market: market,
      );
      
      if (lowScoreStocks.isEmpty) {
        print('⚠️ 제거할 낮은 점수 종목이 없습니다.');
        return false;
      }
      
      // 추천 종목 데이터에서 제거
      final recommendedStocks = RecommendedStocksData();
      
      for (final stock in lowScoreStocks) {
        final stockCode = stock['stockCode'] as String;
        await recommendedStocks.removeStock(stockCode);
      }
      
      print('✅ 낮은 점수 종목 ${lowScoreStocks.length}개를 추천 종목에서 제거 완료');
      return true;
      
    } catch (e) {
      print('❌ 낮은 점수 종목 추천 종목 제거 실패: $e');
      return false;
    }
  }
}
