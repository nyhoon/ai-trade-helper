import 'package:sqflite/sqflite.dart';
import '../../constants/chart_constants.dart';
import '../database_helper.dart';
import 'chart_data_repository.dart';

/// 일별 히스토리 데이터 Repository (100일 관리) - 새로운 chart_data 테이블 사용
/// 
/// 📊 변경사항:
/// - 기존 historical_data 테이블 → 새로운 chart_data 테이블 사용
/// - 200일 보관 → 100일 보관으로 변경
/// - 새로운 ChartDataRepository 활용
class HistoricalDataRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final ChartDataRepository _chartRepo = ChartDataRepository();

  /// 일별 차트 데이터 저장 (새로운 chart_data 테이블 사용)
  Future<void> upsertDailyBars({
    required String stockCode,
    required String market,
    required List<Map<String, dynamic>> bars, // {date: yyyy-MM-dd, open, high, low, close, volume}
    int keepDays = 100, // 100일로 변경
  }) async {
    if (bars.isEmpty) return;

    try {
      // 새로운 ChartDataRepository 사용
      final formattedData = bars.map((b) => {
        'stock_code': stockCode,
        'market': market,
        'date': b['date'], // yyyy-MM-dd 형식
        'open': (b['open'] ?? 0.0).toDouble(),
        'high': (b['high'] ?? 0.0).toDouble(),
        'low': (b['low'] ?? 0.0).toDouble(),
        'close': (b['close'] ?? 0.0).toDouble(),
        'volume': (b['volume'] ?? 0).toInt(),
        'trade_amount': b['trade_amount'],
      }).toList();

      await _chartRepo.insertMultipleChartData(formattedData);
      
      print('📊 $stockCode: ${formattedData.length}일 차트 데이터 저장 완료');
    } catch (e) {
      print('❌ $stockCode 차트 데이터 저장 실패: $e');
      rethrow;
    }
  }

  /// 최근 차트 데이터 조회 (새로운 chart_data 테이블 사용)
  Future<List<Map<String, dynamic>>> getRecentBars(String stockCode, {int limit = ChartConstants.CHART_MIN_BARS}) async {
    try {
      final rows = await _chartRepo.getChartData(stockCode, limit: limit);
      print('📊 [ChartData] $stockCode 최근 ${rows.length}개 조회 (요청: $limit)');
      return rows;
    } catch (e) {
      print('❌ $stockCode 최근 차트 데이터 조회 실패: $e');
      return [];
    }
  }

  /// 특정 종목의 차트 데이터 삭제
  Future<void> deleteByStockCode(String stockCode) async {
    try {
      await _chartRepo.deleteChartData(stockCode);
      print('🗑️ $stockCode 차트 데이터 삭제 완료');
    } catch (e) {
      print('❌ $stockCode 차트 데이터 삭제 실패: $e');
      rethrow;
    }
  }

  /// 날짜 범위로 일별 데이터 조회 (새로운 chart_data 테이블 사용)
  Future<List<Map<String, dynamic>>> getDailyBars({
    required String stockCode,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final startDateStr = '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';
      final endDateStr = '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}';
      
      return await _chartRepo.getChartData(
        stockCode,
        startDate: startDateStr,
        endDate: endDateStr,
      );
    } catch (e) {
      print('❌ $stockCode 날짜 범위 차트 데이터 조회 실패: $e');
      return [];
    }
  }

  /// 특정 날짜 이전의 오래된 데이터 삭제 (100일 보관 정책)
  Future<void> deleteOldData({required DateTime before}) async {
    try {
      final cutoffDateStr = '${before.year}-${before.month.toString().padLeft(2, '0')}-${before.day.toString().padLeft(2, '0')}';
      
      // 100일 이전 데이터 삭제
      final deletedCount = await _chartRepo.deleteChartDataByDateRange('1900-01-01', cutoffDateStr);
      
      print('🗑️ 오래된 차트 데이터 삭제 완료: $deletedCount개');
    } catch (e) {
      print('❌ 오래된 차트 데이터 삭제 실패: $e');
      rethrow;
    }
  }

  /// 최신 날짜 조회
  Future<String?> getLatestDate(String stockCode) async {
    try {
      final latestData = await _chartRepo.getChartData(stockCode, limit: 1);
      if (latestData.isNotEmpty) {
        return latestData.first['date'] as String?;
      }
      return null;
    } catch (e) {
      print('❌ $stockCode 최신 날짜 조회 실패: $e');
      return null;
    }
  }

  /// 차트 데이터 통계 조회
  Future<Map<String, dynamic>> getChartDataStats() async {
    try {
      return await _chartRepo.getChartDataStats();
    } catch (e) {
      print('❌ 차트 데이터 통계 조회 실패: $e');
      return {};
    }
  }

  /// 특정 종목의 차트 데이터 통계
  Future<Map<String, dynamic>> getStockChartDataStats(String stockCode) async {
    try {
      return await _chartRepo.getStockChartDataStats(stockCode);
    } catch (e) {
      print('❌ $stockCode 차트 데이터 통계 조회 실패: $e');
      return {};
    }
  }

  /// 비활성 종목의 차트 데이터 정리
  Future<int> cleanupInactiveChartData() async {
    try {
      return await _chartRepo.cleanupInactiveChartData();
    } catch (e) {
      print('❌ 비활성 종목 차트 데이터 정리 실패: $e');
      return 0;
    }
  }

  /// 차트 데이터 백업
  Future<Map<String, dynamic>> exportChartData({
    List<String>? stockCodes,
    String? startDate,
    String? endDate,
  }) async {
    try {
      return await _chartRepo.exportChartData(
        stockCodes: stockCodes,
        startDate: startDate,
        endDate: endDate,
      );
    } catch (e) {
      print('❌ 차트 데이터 백업 실패: $e');
      return {};
    }
  }

  /// 차트 데이터 복원
  Future<void> importChartData(Map<String, dynamic> exportData) async {
    try {
      await _chartRepo.importChartData(exportData);
      print('✅ 차트 데이터 복원 완료');
    } catch (e) {
      print('❌ 차트 데이터 복원 실패: $e');
      rethrow;
    }
  }
}


