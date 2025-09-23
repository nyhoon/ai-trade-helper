import 'package:sqflite/sqflite.dart';
import '../database_helper.dart';
import '../../data/app_data_manager.dart';
import 'chart_data_repository.dart';
import '../../api/kis_unified_api_service.dart';

/// 관심종목 Repository
class WatchlistRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<String> _resolveMarket(DatabaseExecutor db, String stockCode) async {
    try {
      final rows = await db.query(
        'stock_master',
        columns: ['market'],
        where: 'stock_code = ?',
        whereArgs: [stockCode],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final market = rows.first['market'] as String?;
        if (market != null && market.isNotEmpty) return market;
      }
    } catch (_) {}
    return 'UNKNOWN';
  }

  /// 관심종목 추가 (차트 데이터 자동 수집)
  Future<int> addToWatchlist({
    required String stockCode,
    required String stockName,
    String? memo,
  }) async {
    try {
      print('🔍 관심종목 추가 시작: $stockCode ($stockName)');
      final db = await _dbHelper.database;
      final now = DateTime.now().millisecondsSinceEpoch;

      // 이미 존재하는지 확인
      final existing = await db.query(
        'watchlist',
        where: 'stock_code = ?',
        whereArgs: [stockCode],
      );

      if (existing.isNotEmpty) {
        print('⚠️ 이미 관심종목에 존재: $stockCode');
        return existing.first['id'] as int;
      }

      print('📝 관심종목 데이터베이스에 삽입 중...');
      final resolvedMarket = await _resolveMarket(db, stockCode);
      final id = await db.insert(
        'watchlist',
        {
          'stock_code': stockCode,
          'stock_name': stockName,
          'market': resolvedMarket,
          'added_at': now,
          'memo': memo,
        },
      );

      print('✅ 관심종목 추가 완료: $stockName ($stockCode) - ID: $id');
      
      // 저장 확인
      final saved = await db.query(
        'watchlist',
        where: 'id = ?',
        whereArgs: [id],
      );
      print('🔍 저장 확인: ${saved.length}개 레코드 발견');
      
      // 새 종목의 차트 데이터 수집 (백그라운드에서 실행)
      _collectChartDataForNewStock(stockCode, resolvedMarket);
      
      return id;
    } catch (e) {
      print('❌ 관심종목 추가 실패: $e');
      rethrow;
    }
  }

  /// 새 종목의 차트 데이터 수집 (백그라운드)
  Future<void> _collectChartDataForNewStock(String stockCode, String market) async {
    try {
      print('📊 새 관심종목 차트 데이터 수집 시작: $stockCode');
      
      // AppDataManager를 통해 KIS API 호출
      final appDataManager = AppDataManager.instance;
      final unifiedApiService = KisUnifiedApiService();
      final chartRepo = ChartDataRepository();
      
      // 나스닥 종목인지 확인
      final isNasdaq = market == 'NASDAQ' || market == 'NYSE';
      
      List<Map<String, dynamic>> chartData;
      if (isNasdaq) {
        print('🌍 나스닥 차트 데이터 조회: $stockCode');
        chartData = await unifiedApiService.getOverseasDailyChart(
          symbol: stockCode,
          exchangeCode: 'NAS',
          count: 80,
        );
      } else {
        print('🇰🇷 국내주식 차트 데이터 조회: $stockCode');
        chartData = await unifiedApiService.getDomesticDailyChart(
          stockCode: stockCode,
          count: 80,
        );
      }
      
      if (chartData.isNotEmpty) {
        // 로컬DB에 저장 (일괄 삽입)
        await chartRepo.insertMultipleChartData(chartData);
        print('✅ 새 관심종목 $stockCode 차트 데이터 저장 완료 (${chartData.length}개)');
      } else {
        print('⚠️ 새 관심종목 $stockCode 차트 데이터가 비어있음');
      }
    } catch (e) {
      print('❌ 새 관심종목 $stockCode 차트 데이터 수집 실패: $e');
    }
  }

  /// 관심종목 제거 (하드 삭제 + 데이터 정리)
  Future<void> removeFromWatchlist(String stockCode) async {
    try {
      print('🗑️ 관심종목 제거 시작: $stockCode');
      
      final db = await _dbHelper.database;
      await db.delete(
        'watchlist',
        where: 'stock_code = ?',
        whereArgs: [stockCode],
      );

      print('✅ 관심종목 완전 제거: $stockCode');
      
      // 해당 종목의 차트 데이터 정리 (비활성 종목 정리)
      await _cleanupInactiveChartData();
      
    } catch (e) {
      print('❌ 관심종목 제거 실패: $e');
      rethrow;
    }
  }

  /// 비활성 종목의 차트 데이터 정리
  Future<void> _cleanupInactiveChartData() async {
    try {
      print('🧹 비활성 종목 차트 데이터 정리 시작...');
      
      // AppDataManager를 통해 차트 데이터 정리
      final appDataManager = AppDataManager.instance;
      final chartRepo = ChartDataRepository();
      
      // ChartDataRepository의 cleanupInactiveChartData 메서드 호출
      await chartRepo.cleanupInactiveChartData();
      
      print('✅ 비활성 종목 차트 데이터 정리 완료');
    } catch (e) {
      print('❌ 비활성 종목 차트 데이터 정리 실패: $e');
    }
  }

  /// 관심종목 목록 조회
  Future<List<Map<String, dynamic>>> getWatchlist() async {
    try {
      print('🔍 관심종목 목록 조회 시작...');
      final db = await _dbHelper.database;
      final results = await db.query(
        'watchlist',
        orderBy: 'added_at DESC',
      );

      print('✅ 관심종목 목록 조회 완료: ${results.length}개');
      for (final item in results) {
        print('  - ${item['stock_code']}: ${item['stock_name']}');
      }

      return results;
    } catch (e) {
      print('❌ 관심종목 목록 조회 실패: $e');
      return [];
    }
  }

  /// 관심종목 상세 정보 조회 (종목 정보와 JOIN)
  Future<List<Map<String, dynamic>>> getWatchlistWithStockInfo() async {
    final db = await _dbHelper.database;
    final results = await db.rawQuery('''
      SELECT 
        w.id,
        w.stock_code,
        w.stock_name,
        w.added_at,
        w.memo,
        sm.market,
        sm.sector
      FROM watchlist w
      LEFT JOIN stock_master sm ON w.stock_code = sm.stock_code
      ORDER BY w.added_at DESC
    ''');

    return results;
  }

  /// 관심종목 여부 확인
  Future<bool> isInWatchlist(String stockCode) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'watchlist',
      where: 'stock_code = ?',
      whereArgs: [stockCode],
    );

    return results.isNotEmpty;
  }

  /// 관심종목 메모 업데이트
  Future<void> updateMemo(String stockCode, String memo) async {
    final db = await _dbHelper.database;
    await db.update(
      'watchlist',
      {'memo': memo},
      where: 'stock_code = ?',
      whereArgs: [stockCode],
    );
  }

  /// 관심종목 개수 조회
  Future<int> getWatchlistCount() async {
  
  /// 특정 종목이 관심종목에 있는지 확인
  Future<bool> isInWatchlist(String stockCode) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'watchlist',
      where: 'stock_code = ? AND is_active = 1',
      whereArgs: [stockCode],
      limit: 1,
    );
    return result.isNotEmpty;
  }
    final db = await _dbHelper.database;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count 
      FROM watchlist 
      WHERE is_active = 1
    ''');
    return result.first['count'] as int;
  }

  /// 관심종목 일괄 추가
  Future<void> addMultipleToWatchlist(List<Map<String, String>> stocks) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      for (final stock in stocks) {
        // 이미 존재하는지 확인
        final existing = await txn.query(
          'watchlist',
          where: 'stock_code = ? AND is_active = 1',
          whereArgs: [stock['stock_code']],
        );

        if (existing.isEmpty) {
          final resolvedMarket = await _resolveMarket(txn, stock['stock_code']!);
          await txn.insert(
            'watchlist',
            {
              'stock_code': stock['stock_code']!,
              'stock_name': stock['stock_name']!,
              'market': resolvedMarket,
              'added_at': now,
              'memo': stock['memo'],
              'is_active': 1,
            },
          );
        }
      }
    });

    print('✅ 관심종목 일괄 추가: ${stocks.length}개');
  }

  /// 관심종목 정렬 순서 변경
  Future<void> reorderWatchlist(List<String> stockCodes) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      for (int i = 0; i < stockCodes.length; i++) {
        await txn.update(
          'watchlist',
          {'added_at': now + i}, // 순서대로 시간차를 두어 정렬
          where: 'stock_code = ? AND is_active = 1',
          whereArgs: [stockCodes[i]],
        );
      }
    });
  }
}
