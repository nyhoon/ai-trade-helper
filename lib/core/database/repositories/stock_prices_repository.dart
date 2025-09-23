import 'package:sqflite/sqflite.dart';
import '../database_helper.dart';

class StockPricesRepository {
  static const String _tableName = 'stock_prices';

  /// 테이블 생성
  Future<void> createTable() async {
    final db = await DatabaseHelper.instance.database;
    
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        stock_code TEXT NOT NULL,
        price REAL NOT NULL,
        timestamp INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    
    // 인덱스 생성
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_prices_code ON $_tableName (stock_code)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_prices_timestamp ON $_tableName (timestamp)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_prices_code_timestamp ON $_tableName (stock_code, timestamp)');
  }

  /// 가격 저장
  Future<void> savePrice({
    required String stockCode,
    required double price,
    required DateTime timestamp,
  }) async {
    final db = await DatabaseHelper.instance.database;
    
    await db.insert(_tableName, {
      'stock_code': stockCode,
      'price': price,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 최신 가격 조회
  Future<double?> getLatestPrice(String stockCode) async {
    final db = await DatabaseHelper.instance.database;
    
    final result = await db.query(
      _tableName,
      where: 'stock_code = ?',
      whereArgs: [stockCode],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    
    if (result.isNotEmpty) {
      return result.first['price'] as double?;
    }
    return null;
  }

  /// 특정 시간 범위의 가격 조회
  Future<List<Map<String, dynamic>>> getPricesByDateRange(
    String stockCode,
    DateTime start,
    DateTime end,
  ) async {
    final db = await DatabaseHelper.instance.database;
    
    final startMs = start.millisecondsSinceEpoch;
    final endMs = end.millisecondsSinceEpoch;
    
    final result = await db.query(
      _tableName,
      where: 'stock_code = ? AND timestamp >= ? AND timestamp <= ?',
      whereArgs: [stockCode, startMs, endMs],
      orderBy: 'timestamp ASC',
    );
    
    return result.map((row) => {
      'price': row['price'] as double,
      'timestamp': DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
    }).toList();
  }

  /// 오늘 가격 데이터 조회
  Future<List<Map<String, dynamic>>> getTodayPrices(String stockCode) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    
    return await getPricesByDateRange(stockCode, today, tomorrow);
  }

  /// 최근 N개 가격 조회
  Future<List<Map<String, dynamic>>> getRecentPrices(String stockCode, int limit) async {
    final db = await DatabaseHelper.instance.database;
    
    final result = await db.query(
      _tableName,
      where: 'stock_code = ?',
      whereArgs: [stockCode],
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    
    return result.map((row) => {
      'price': row['price'] as double,
      'timestamp': DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
    }).toList();
  }

  /// 가격 변동률 계산
  Future<double?> getPriceChangeRate(String stockCode, Duration period) async {
    final now = DateTime.now();
    final past = now.subtract(period);
    
    final prices = await getPricesByDateRange(stockCode, past, now);
    if (prices.length < 2) return null;
    
    final latestPrice = prices.last['price'] as double;
    final oldestPrice = prices.first['price'] as double;
    
    if (oldestPrice <= 0) return null;
    
    return (latestPrice - oldestPrice) / oldestPrice;
  }

  /// 일일 가격 변동률
  Future<double?> getDailyPriceChangeRate(String stockCode) async {
    return await getPriceChangeRate(stockCode, const Duration(days: 1));
  }

  /// 시간별 가격 변동률
  Future<double?> getHourlyPriceChangeRate(String stockCode) async {
    return await getPriceChangeRate(stockCode, const Duration(hours: 1));
  }

  /// 가격 통계 조회
  Future<Map<String, dynamic>> getPriceStatistics(String stockCode, Duration period) async {
    final now = DateTime.now();
    final past = now.subtract(period);
    
    final prices = await getPricesByDateRange(stockCode, past, now);
    if (prices.isEmpty) {
      return {
        'min': 0.0,
        'max': 0.0,
        'avg': 0.0,
        'latest': 0.0,
        'change': 0.0,
      };
    }
    
    final priceList = prices.map((p) => p['price'] as double).toList();
    final min = priceList.reduce((a, b) => a < b ? a : b);
    final max = priceList.reduce((a, b) => a > b ? a : b);
    final avg = priceList.reduce((a, b) => a + b) / priceList.length;
    final latest = priceList.last;
    final change = priceList.length > 1 ? (latest - priceList.first) / priceList.first : 0.0;
    
    return {
      'min': min,
      'max': max,
      'avg': avg,
      'latest': latest,
      'change': change,
    };
  }

  /// 오래된 가격 데이터 삭제 (7일 이상)
  Future<void> deleteOldPrices() async {
    final db = await DatabaseHelper.instance.database;
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    
    await db.delete(
      _tableName,
      where: 'timestamp < ?',
      whereArgs: [sevenDaysAgo],
    );
  }

  /// 특정 종목의 모든 가격 데이터 삭제
  Future<void> deletePricesByStock(String stockCode) async {
    final db = await DatabaseHelper.instance.database;
    
    await db.delete(
      _tableName,
      where: 'stock_code = ?',
      whereArgs: [stockCode],
    );
  }

  /// 모든 가격 데이터 삭제
  Future<void> deleteAllPrices() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(_tableName);
  }

  /// 가격 데이터 개수 조회
  Future<int> getPriceCount(String stockCode) async {
    final db = await DatabaseHelper.instance.database;
    
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_tableName WHERE stock_code = ?',
      [stockCode],
    );
    
    return result.first['count'] as int? ?? 0;
  }

  /// 전체 가격 데이터 개수 조회
  Future<int> getTotalPriceCount() async {
    final db = await DatabaseHelper.instance.database;
    
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM $_tableName');
    return result.first['count'] as int? ?? 0;
  }
}
