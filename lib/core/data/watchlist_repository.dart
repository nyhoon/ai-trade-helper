import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';

class WatchlistRepository {
  static const String _tableName = 'watchlist';

  /// 테이블 생성
  Future<void> createTable() async {
    final db = await DatabaseHelper.instance.database;
    
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        stock_code TEXT NOT NULL UNIQUE,
        stock_name TEXT NOT NULL,
        added_at INTEGER NOT NULL,
        memo TEXT,
        market TEXT,
        sector TEXT
      )
    ''');
  }

  /// 관심종목 추가
  Future<void> addToWatchlist({
    required String stockCode,
    required String stockName,
    String? memo,
    String? market,
    String? sector,
  }) async {
    final db = await DatabaseHelper.instance.database;
    
    await db.insert(
      _tableName,
      {
        'stock_code': stockCode,
        'stock_name': stockName,
        'added_at': DateTime.now().millisecondsSinceEpoch,
        'memo': memo,
        'market': market,
        'sector': sector,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 관심종목 제거
  Future<void> removeFromWatchlist(String stockCode) async {
    final db = await DatabaseHelper.instance.database;
    
    await db.delete(
      _tableName,
      where: 'stock_code = ?',
      whereArgs: [stockCode],
    );
  }

  /// 관심종목 목록 조회
  Future<List<Map<String, dynamic>>> getWatchlist() async {
    final db = await DatabaseHelper.instance.database;
    
    final result = await db.query(
      _tableName,
      orderBy: 'added_at DESC',
    );
    
    return result;
  }

  /// 관심종목 상세 정보와 함께 조회
  Future<List<Map<String, dynamic>>> getWatchlistWithStockInfo() async {
    final watchlist = await getWatchlist();
    
    // 중복 제거 (종목코드 기준)
    final Map<String, Map<String, dynamic>> uniqueStocks = {};
    
    for (final item in watchlist) {
      final stockCode = item['stock_code'] as String;
      
      // 이미 존재하는 종목이면 더 최근에 추가된 것을 유지
      if (!uniqueStocks.containsKey(stockCode) || 
          (item['added_at'] as int) > (uniqueStocks[stockCode]!['added_at'] as int)) {
        uniqueStocks[stockCode] = {
          'stock_code': item['stock_code'],
          'stock_name': item['stock_name'],
          'added_at': item['added_at'],
          'memo': item['memo'],
          'market': item['market'],
          'sector': item['sector'],
        };
      }
    }
    
    return uniqueStocks.values.toList();
  }

  /// 특정 종목이 관심종목에 있는지 확인
  Future<bool> isInWatchlist(String stockCode) async {
    final db = await DatabaseHelper.instance.database;
    
    final result = await db.query(
      _tableName,
      where: 'stock_code = ?',
      whereArgs: [stockCode],
      limit: 1,
    );
    
    return result.isNotEmpty;
  }

  /// 중복된 종목들을 정리 (종목코드 기준으로 최신 것만 유지)
  Future<void> cleanupDuplicates() async {
    final db = await DatabaseHelper.instance.database;
    
    // 모든 종목을 종목코드별로 그룹화
    final allStocks = await db.query(_tableName);
    final Map<String, List<Map<String, dynamic>>> groupedStocks = {};
    
    for (final stock in allStocks) {
      final stockCode = stock['stock_code'] as String;
      if (!groupedStocks.containsKey(stockCode)) {
        groupedStocks[stockCode] = [];
      }
      groupedStocks[stockCode]!.add(stock);
    }
    
    // 각 종목코드별로 중복 제거
    for (final entry in groupedStocks.entries) {
      final stockCode = entry.key;
      final stocks = entry.value;
      
      if (stocks.length > 1) {
        // 가장 최근에 추가된 것만 유지하고 나머지 삭제
        stocks.sort((a, b) => (b['added_at'] as int).compareTo(a['added_at'] as int));
        
        for (int i = 1; i < stocks.length; i++) {
          await db.delete(
            _tableName,
            where: 'id = ?',
            whereArgs: [stocks[i]['id']],
          );
        }
        
        print('🧹 중복 종목 정리: $stockCode (${stocks.length - 1}개 중복 제거)');
      }
    }
  }

  /// 관심종목 메모 업데이트
  Future<void> updateMemo(String stockCode, String memo) async {
    final db = await DatabaseHelper.instance.database;
    
    await db.update(
      _tableName,
      {'memo': memo},
      where: 'stock_code = ?',
      whereArgs: [stockCode],
    );
  }

  /// 관심종목 통계 조회
  Future<Map<String, dynamic>> getWatchlistStatistics() async {
    final db = await DatabaseHelper.instance.database;
    
    // 전체 관심종목 수
    final totalResult = await db.rawQuery('SELECT COUNT(*) as count FROM $_tableName');
    final total = totalResult.first['count'] as int? ?? 0;
    
    // 시장별 분포
    final marketResult = await db.rawQuery('''
      SELECT market, COUNT(*) as count 
      FROM $_tableName 
      GROUP BY market
    ''');
    
    final marketStats = <String, int>{};
    for (final row in marketResult) {
      marketStats[row['market'] as String] = row['count'] as int;
    }
    
    // 섹터별 분포
    final sectorResult = await db.rawQuery('''
      SELECT sector, COUNT(*) as count 
      FROM $_tableName 
      GROUP BY sector
    ''');
    
    final sectorStats = <String, int>{};
    for (final row in sectorResult) {
      sectorStats[row['sector'] as String] = row['count'] as int;
    }
    
    return {
      'total': total,
      'byMarket': marketStats,
      'bySector': sectorStats,
    };
  }
}
