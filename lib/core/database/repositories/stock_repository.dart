import '../database_helper.dart';
import 'package:sqflite/sqflite.dart';

/// Stocks repository aligned with @api schema
/// Table: stocks(stock_code TEXT PRIMARY KEY, stock_name TEXT, market TEXT, last_updated INTEGER)
class StockRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<void> _ensureTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stocks (
        stock_code TEXT PRIMARY KEY,
        stock_name TEXT NOT NULL,
        market TEXT NOT NULL,
        last_updated INTEGER
      )
    ''' );
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stocks_name ON stocks(stock_name)');
  }

  Future<int> getStockCount() async {
    final db = await _dbHelper.database;
    await _ensureTable(db);
    final res = await db.rawQuery('SELECT COUNT(*) AS cnt FROM stocks');
    return (res.first['cnt'] as int?) ?? 0;
  }

  Future<List<Map<String, dynamic>>> getAllStocks() async {
    final db = await _dbHelper.database;
    await _ensureTable(db);
    return await db.rawQuery('SELECT stock_code, stock_name, market FROM stocks ORDER BY stock_name ASC');
  }

  /// Upsert stocks; each item expects keys: stock_code, stock_name, market
  Future<void> saveStocks(List<Map<String, dynamic>> stocks) async {
    if (stocks.isEmpty) return;
    final db = await _dbHelper.database;
    await _ensureTable(db);
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final s in stocks) {
      final code = (s['stock_code'] ?? s['stockCode'] ?? s['fid_input_iscd'] ?? s['symb'])?.toString();
      final name = (s['stock_name'] ?? s['stockName'] ?? s['hts_kor_isnm'] ?? s['prdt_name'])?.toString() ?? '';
      final market = (s['market'] ?? s['excd'] ?? 'UNKNOWN').toString();
      if (code == null || code.isEmpty) continue;
      batch.insert(
        'stocks',
        {
          'stock_code': code,
          'stock_name': name,
          'market': market,
          'last_updated': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }
}
