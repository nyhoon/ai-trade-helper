import 'package:sqflite/sqflite.dart';
import '../database_helper.dart';
import 'current_price_repository.dart';

/// 실시간 데이터 Repository - 새로운 current_price 테이블 사용
/// 
/// 📊 변경사항:
/// - 기존 realtime_data 테이블 → 새로운 current_price 테이블 사용
/// - 새로운 CurrentPriceRepository 활용
/// - 실시간 현재가 데이터 최적화
class RealtimeDataRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final CurrentPriceRepository _currentPriceRepo = CurrentPriceRepository();

  /// 실시간 데이터 저장 (새로운 current_price 테이블 사용)
  Future<void> saveRealtimeData({
    required String stockCode,
    required String market,
    required double currentPrice,
    required double prevClose,
    required double changeAmount,
    required double changeRate,
    required int volume,
    required double tradeAmount,
    required double highPrice,
    required double lowPrice,
    required double openPrice,
    double? marketCap,
    double? per,
    double? pbr,
  }) async {
    try {
      await _currentPriceRepo.insertOrUpdateCurrentPrice(
        stockCode: stockCode,
        market: market,
        currentPrice: currentPrice,
        prevClose: prevClose,
        changeAmount: changeAmount,
        changeRate: changeRate,
        volume: volume,
        tradeAmount: tradeAmount,
        highPrice: highPrice,
        lowPrice: lowPrice,
        openPrice: openPrice,
        marketCap: marketCap,
        per: per,
        pbr: pbr,
      );
    } catch (e) {
      print('❌ $stockCode 실시간 데이터 저장 실패: $e');
      rethrow;
    }
  }

  /// 실시간 데이터 일괄 저장 (새로운 current_price 테이블 사용)
  Future<void> saveMultipleRealtimeData(List<Map<String, dynamic>> dataList) async {
    try {
      await _currentPriceRepo.insertMultipleCurrentPrice(dataList);
      print('✅ ${dataList.length}개 종목 실시간 데이터 일괄 저장 완료');
    } catch (e) {
      print('❌ 실시간 데이터 일괄 저장 실패: $e');
      rethrow;
    }
  }

  /// 최신 실시간 데이터 조회 (새로운 current_price 테이블 사용)
  Future<Map<String, dynamic>?> getLatestRealtimeData(String stockCode) async {
    try {
      return await _currentPriceRepo.getCurrentPrice(stockCode);
    } catch (e) {
      print('❌ $stockCode 최신 실시간 데이터 조회 실패: $e');
      return null;
    }
  }

  /// 관심종목들의 최신 실시간 데이터 조회 (새로운 current_price 테이블 사용)
  Future<List<Map<String, dynamic>>> getWatchlistRealtimeData(List<String> stockCodes) async {
    if (stockCodes.isEmpty) return [];

    try {
      final currentPriceData = await _currentPriceRepo.getMultipleCurrentPrice(stockCodes);
      return currentPriceData.values.toList();
    } catch (e) {
      print('❌ 관심종목 실시간 데이터 조회 실패: $e');
      return [];
    }
  }

  /// 활성 종목들의 실시간 데이터 조회 (새로운 current_price 테이블 사용)
  Future<Map<String, Map<String, dynamic>>> getActiveRealtimeData() async {
    try {
      return await _currentPriceRepo.getActiveCurrentPrice();
    } catch (e) {
      print('❌ 활성 종목 실시간 데이터 조회 실패: $e');
      return {};
    }
  }

  /// 특정 시장의 실시간 데이터 조회
  Future<List<Map<String, dynamic>>> getRealtimeDataByMarket(String market) async {
    try {
      return await _currentPriceRepo.getCurrentPriceByMarket(market);
    } catch (e) {
      print('❌ $market 실시간 데이터 조회 실패: $e');
      return [];
    }
  }

  /// 상승률 기준 정렬된 실시간 데이터 조회
  Future<List<Map<String, dynamic>>> getRealtimeDataByChangeRate({
    String? market,
    int limit = 50,
    bool ascending = false,
  }) async {
    try {
      return await _currentPriceRepo.getCurrentPriceByChangeRate(
        market: market,
        limit: limit,
        ascending: ascending,
      );
    } catch (e) {
      print('❌ 상승률 기준 실시간 데이터 조회 실패: $e');
      return [];
    }
  }

  /// 거래량 기준 정렬된 실시간 데이터 조회
  Future<List<Map<String, dynamic>>> getRealtimeDataByVolume({
    String? market,
    int limit = 50,
    bool ascending = false,
  }) async {
    try {
      return await _currentPriceRepo.getCurrentPriceByVolume(
        market: market,
        limit: limit,
        ascending: ascending,
      );
    } catch (e) {
      print('❌ 거래량 기준 실시간 데이터 조회 실패: $e');
      return [];
    }
  }

  /// 실시간 데이터 존재 여부 확인
  Future<bool> hasRealtimeData(String stockCode) async {
    try {
      return await _currentPriceRepo.hasCurrentPrice(stockCode);
    } catch (e) {
      print('❌ $stockCode 실시간 데이터 존재 여부 확인 실패: $e');
      return false;
    }
  }

  /// 특정 종목의 실시간 데이터 삭제
  Future<int> deleteRealtimeData(String stockCode) async {
    try {
      return await _currentPriceRepo.deleteCurrentPrice(stockCode);
    } catch (e) {
      print('❌ $stockCode 실시간 데이터 삭제 실패: $e');
      return 0;
    }
  }

  /// 특정 시장의 실시간 데이터 삭제
  Future<int> deleteRealtimeDataByMarket(String market) async {
    try {
      return await _currentPriceRepo.deleteCurrentPriceByMarket(market);
    } catch (e) {
      print('❌ $market 실시간 데이터 삭제 실패: $e');
      return 0;
    }
  }

  /// 오래된 실시간 데이터 삭제 (타임스탬프 기준)
  Future<void> deleteOldData({required DateTime before}) async {
    try {
      final db = await _dbHelper.database;
      final cutoffTime = before.millisecondsSinceEpoch;
      await db.delete(
        'realtime_data',
        where: 'timestamp < ?',
        whereArgs: [cutoffTime],
      );
    } catch (e) {
      print('❌ 오래된 실시간 데이터 삭제 실패: $e');
    }
  }

  /// 오래된 실시간 데이터 정리 (1시간 이상)
  Future<int> cleanupOldRealtimeData() async {
    try {
      return await _currentPriceRepo.cleanupOldCurrentPrice();
    } catch (e) {
      print('❌ 오래된 실시간 데이터 정리 실패: $e');
      return 0;
    }
  }

  /// 실시간 데이터 통계 조회
  Future<Map<String, dynamic>> getRealtimeDataStats() async {
    try {
      return await _currentPriceRepo.getCurrentPriceStats();
    } catch (e) {
      print('❌ 실시간 데이터 통계 조회 실패: $e');
      return {};
    }
  }

  /// 특정 종목의 실시간 데이터 통계
  Future<Map<String, dynamic>> getStockRealtimeDataStats(String stockCode) async {
    try {
      return await _currentPriceRepo.getStockCurrentPriceStats(stockCode);
    } catch (e) {
      print('❌ $stockCode 실시간 데이터 통계 조회 실패: $e');
      return {};
    }
  }

  /// 실시간 데이터 백업
  Future<Map<String, dynamic>> exportRealtimeData({
    List<String>? stockCodes,
    String? market,
  }) async {
    try {
      return await _currentPriceRepo.exportCurrentPrice(
        stockCodes: stockCodes,
        market: market,
      );
    } catch (e) {
      print('❌ 실시간 데이터 백업 실패: $e');
      return {};
    }
  }

  /// 실시간 데이터 복원
  Future<void> importRealtimeData(Map<String, dynamic> exportData) async {
    try {
      await _currentPriceRepo.importCurrentPrice(exportData);
      print('✅ 실시간 데이터 복원 완료');
    } catch (e) {
      print('❌ 실시간 데이터 복원 실패: $e');
      rethrow;
    }
  }

  /// 실시간 데이터 검증
  Future<List<String>> validateRealtimeData() async {
    try {
      return await _currentPriceRepo.validateCurrentPriceData();
    } catch (e) {
      print('❌ 실시간 데이터 검증 실패: $e');
      return [];
    }
  }
}
