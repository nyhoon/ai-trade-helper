import 'package:sqflite/sqflite.dart';
import '../database_helper.dart';

class TradeHistoryRepository {
  final DatabaseHelper _databaseHelper = DatabaseHelper();

  /// 거래 내역 테이블 생성
  Future<void> createTable() async {
    final db = await _databaseHelper.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS trade_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        stock_code TEXT NOT NULL,
        stock_name TEXT NOT NULL,
        order_type TEXT NOT NULL, -- '매수' 또는 '매도'
        quantity INTEGER NOT NULL,
        price REAL NOT NULL,
        total_amount REAL NOT NULL,
        order_date TEXT NOT NULL,
        order_time TEXT NOT NULL,
        profit_loss REAL DEFAULT 0, -- 매도 시 손익
        profit_rate REAL DEFAULT 0, -- 매도 시 수익률
        trade_reason TEXT, -- 매수/매도 이유 (AI 시그널 등)
        investment_style TEXT, -- 투자 스타일
        met_conditions INTEGER DEFAULT 0, -- 만족한 조건 수
        total_conditions INTEGER DEFAULT 6, -- 총 조건 수
        is_auto_trade BOOLEAN DEFAULT 0, -- 자동매매 여부
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_trade_history_stock_code ON trade_history (stock_code)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_trade_history_created_at ON trade_history (created_at)');
  }

  /// 거래 내역 추가
  Future<int> insertTradeHistory({
    required String stockCode,
    required String stockName,
    required String orderType,
    required int quantity,
    required double price,
    required double totalAmount,
    required String orderDate,
    required String orderTime,
    double profitLoss = 0,
    double profitRate = 0,
    String? tradeReason,
    String? investmentStyle,
    int metConditions = 0,
    int totalConditions = 6,
    bool isAutoTrade = false,
  }) async {
    final db = await _databaseHelper.database;
    
    return await db.insert('trade_history', {
      'stock_code': stockCode,
      'stock_name': stockName,
      'order_type': orderType,
      'quantity': quantity,
      'price': price,
      'total_amount': totalAmount,
      'order_date': orderDate,
      'order_time': orderTime,
      'profit_loss': profitLoss,
      'profit_rate': profitRate,
      'trade_reason': tradeReason,
      'investment_style': investmentStyle,
      'met_conditions': metConditions,
      'total_conditions': totalConditions,
      'is_auto_trade': isAutoTrade ? 1 : 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// 모든 거래 내역 조회 (최신순)
  Future<List<Map<String, dynamic>>> getAllTradeHistory() async {
    final db = await _databaseHelper.database;
    
    final List<Map<String, dynamic>> result = await db.query(
      'trade_history',
      orderBy: 'created_at DESC',
    );
    
    return result.map((row) => {
      'id': row['id'],
      'stockCode': row['stock_code'],
      'stockName': row['stock_name'],
      'orderType': row['order_type'],
      'quantity': row['quantity'],
      'price': row['price'],
      'totalAmount': row['total_amount'],
      'orderDate': row['order_date'],
      'orderTime': row['order_time'],
      'profitLoss': row['profit_loss'],
      'profitRate': row['profit_rate'],
      'tradeReason': row['trade_reason'],
      'investmentStyle': row['investment_style'],
      'metConditions': row['met_conditions'],
      'totalConditions': row['total_conditions'],
      'isAutoTrade': row['is_auto_trade'] == 1,
      'createdAt': row['created_at'],
    }).toList();
  }

  /// 특정 종목의 거래 내역 조회
  Future<List<Map<String, dynamic>>> getTradeHistoryByStock(String stockCode) async {
    final db = await _databaseHelper.database;
    
    final List<Map<String, dynamic>> result = await db.query(
      'trade_history',
      where: 'stock_code = ?',
      whereArgs: [stockCode],
      orderBy: 'created_at DESC',
    );
    
    return result.map((row) => {
      'id': row['id'],
      'stockCode': row['stock_code'],
      'stockName': row['stock_name'],
      'orderType': row['order_type'],
      'quantity': row['quantity'],
      'price': row['price'],
      'totalAmount': row['total_amount'],
      'orderDate': row['order_date'],
      'orderTime': row['order_time'],
      'profitLoss': row['profit_loss'],
      'profitRate': row['profit_rate'],
      'tradeReason': row['trade_reason'],
      'investmentStyle': row['investment_style'],
      'metConditions': row['met_conditions'],
      'totalConditions': row['total_conditions'],
      'isAutoTrade': row['is_auto_trade'] == 1,
      'createdAt': row['created_at'],
    }).toList();
  }

  /// 자동매매 거래 내역만 조회
  Future<List<Map<String, dynamic>>> getAutoTradeHistory() async {
    final db = await _databaseHelper.database;
    
    final List<Map<String, dynamic>> result = await db.query(
      'trade_history',
      where: 'is_auto_trade = ?',
      whereArgs: [1],
      orderBy: 'created_at DESC',
    );
    
    return result.map((row) => {
      'id': row['id'],
      'stockCode': row['stock_code'],
      'stockName': row['stock_name'],
      'orderType': row['order_type'],
      'quantity': row['quantity'],
      'price': row['price'],
      'totalAmount': row['total_amount'],
      'orderDate': row['order_date'],
      'orderTime': row['order_time'],
      'profitLoss': row['profit_loss'],
      'profitRate': row['profit_rate'],
      'tradeReason': row['trade_reason'],
      'investmentStyle': row['investment_style'],
      'metConditions': row['met_conditions'],
      'totalConditions': row['total_conditions'],
      'isAutoTrade': row['is_auto_trade'] == 1,
      'createdAt': row['created_at'],
    }).toList();
  }

  /// 수동 거래 내역만 조회
  Future<List<Map<String, dynamic>>> getManualTradeHistory() async {
    final db = await _databaseHelper.database;
    
    final List<Map<String, dynamic>> result = await db.query(
      'trade_history',
      where: 'is_auto_trade = ?',
      whereArgs: [0],
      orderBy: 'created_at DESC',
    );
    
    return result.map((row) => {
      'id': row['id'],
      'stockCode': row['stock_code'],
      'stockName': row['stock_name'],
      'orderType': row['order_type'],
      'quantity': row['quantity'],
      'price': row['price'],
      'totalAmount': row['total_amount'],
      'orderDate': row['order_date'],
      'orderTime': row['order_time'],
      'profitLoss': row['profit_loss'],
      'profitRate': row['profit_rate'],
      'tradeReason': row['trade_reason'],
      'investmentStyle': row['investment_style'],
      'metConditions': row['met_conditions'],
      'totalConditions': row['total_conditions'],
      'isAutoTrade': row['is_auto_trade'] == 1,
      'createdAt': row['created_at'],
    }).toList();
  }

  /// 최근 거래 내역 조회 (limit 개수만큼)
  Future<List<Map<String, dynamic>>> getRecentTrades({int limit = 50}) async {
    final db = await _databaseHelper.database;
    
    final List<Map<String, dynamic>> result = await db.query(
      'trade_history',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    
    return result.map((row) => {
      'id': row['id'],
      'stockCode': row['stock_code'],
      'stockName': row['stock_name'],
      'orderType': row['order_type'],
      'quantity': row['quantity'],
      'price': row['price'],
      'totalAmount': row['total_amount'],
      'orderDate': row['order_date'],
      'orderTime': row['order_time'],
      'profitLoss': row['profit_loss'],
      'profitRate': row['profit_rate'],
      'tradeReason': row['trade_reason'],
      'investmentStyle': row['investment_style'],
      'metConditions': row['met_conditions'],
      'totalConditions': row['total_conditions'],
      'isAutoTrade': row['is_auto_trade'] == 1,
      'createdAt': row['created_at'],
    }).toList();
  }

  /// 날짜 범위로 거래 내역 조회
  Future<List<Map<String, dynamic>>> getTradesByDateRange(int startTimestamp, int endTimestamp) async {
    final db = await _databaseHelper.database;
    
    final startDate = DateTime.fromMillisecondsSinceEpoch(startTimestamp);
    final endDate = DateTime.fromMillisecondsSinceEpoch(endTimestamp);
    
    final List<Map<String, dynamic>> result = await db.query(
      'trade_history',
      where: 'created_at BETWEEN ? AND ?',
      whereArgs: [startDate.toIso8601String(), endDate.toIso8601String()],
      orderBy: 'created_at DESC',
    );
    
    return result.map((row) => {
      'id': row['id'],
      'stockCode': row['stock_code'],
      'stockName': row['stock_name'],
      'orderType': row['order_type'],
      'quantity': row['quantity'],
      'price': row['price'],
      'totalAmount': row['total_amount'],
      'orderDate': row['order_date'],
      'orderTime': row['order_time'],
      'profitLoss': row['profit_loss'],
      'profitRate': row['profit_rate'],
      'tradeReason': row['trade_reason'],
      'investmentStyle': row['investment_style'],
      'metConditions': row['met_conditions'],
      'totalConditions': row['total_conditions'],
      'isAutoTrade': row['is_auto_trade'] == 1,
      'createdAt': row['created_at'],
    }).toList();
  }

  /// 특정 기간의 거래 내역 조회
  Future<List<Map<String, dynamic>>> getTradeHistoryByDateRange(
    String startDate,
    String endDate,
  ) async {
    final db = await _databaseHelper.database;
    
    final List<Map<String, dynamic>> result = await db.query(
      'trade_history',
      where: 'order_date BETWEEN ? AND ?',
      whereArgs: [startDate, endDate],
      orderBy: 'created_at DESC',
    );
    
    return result.map((row) => {
      'id': row['id'],
      'stockCode': row['stock_code'],
      'stockName': row['stock_name'],
      'orderType': row['order_type'],
      'quantity': row['quantity'],
      'price': row['price'],
      'totalAmount': row['total_amount'],
      'orderDate': row['order_date'],
      'orderTime': row['order_time'],
      'profitLoss': row['profit_loss'],
      'profitRate': row['profit_rate'],
      'tradeReason': row['trade_reason'],
      'investmentStyle': row['investment_style'],
      'metConditions': row['met_conditions'],
      'totalConditions': row['total_conditions'],
      'isAutoTrade': row['is_auto_trade'] == 1,
      'createdAt': row['created_at'],
    }).toList();
  }

  /// 거래 내역 삭제
  Future<int> deleteTradeHistory(int id) async {
    final db = await _databaseHelper.database;
    return await db.delete(
      'trade_history',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 모든 거래 내역 삭제
  Future<int> deleteAllTradeHistory() async {
    final db = await _databaseHelper.database;
    return await db.delete('trade_history');
  }

  /// 거래 내역 통계 조회
  Future<Map<String, dynamic>> getTradeStatistics() async {
    final db = await _databaseHelper.database;
    
    // 전체 거래 수
    final totalTradesResult = await db.rawQuery('SELECT COUNT(*) as count FROM trade_history');
    final totalTrades = totalTradesResult.first['count'] as int? ?? 0;
    
    // 매수 거래 수
    final buyTradesResult = await db.rawQuery("SELECT COUNT(*) as count FROM trade_history WHERE order_type = '매수'");
    final buyTrades = buyTradesResult.first['count'] as int? ?? 0;
    
    // 매도 거래 수
    final sellTradesResult = await db.rawQuery("SELECT COUNT(*) as count FROM trade_history WHERE order_type = '매도'");
    final sellTrades = sellTradesResult.first['count'] as int? ?? 0;
    
    // 자동매매 거래 수
    final autoTradesResult = await db.rawQuery('SELECT COUNT(*) as count FROM trade_history WHERE is_auto_trade = 1');
    final autoTrades = autoTradesResult.first['count'] as int? ?? 0;
    
    // 수동 거래 수
    final manualTradesResult = await db.rawQuery('SELECT COUNT(*) as count FROM trade_history WHERE is_auto_trade = 0');
    final manualTrades = manualTradesResult.first['count'] as int? ?? 0;
    
    // 총 손익
    final totalProfitLossResult = await db.rawQuery('SELECT SUM(profit_loss) as total FROM trade_history');
    final totalProfitLoss = (totalProfitLossResult.first['total'] as num?)?.toDouble() ?? 0.0;
    
    // 평균 수익률
    final avgProfitRateResult = await db.rawQuery('SELECT AVG(profit_rate) as avg FROM trade_history WHERE profit_rate != 0');
    final avgProfitRate = (avgProfitRateResult.first['avg'] as num?)?.toDouble() ?? 0.0;
    
    return {
      'totalTrades': totalTrades,
      'buyTrades': buyTrades,
      'sellTrades': sellTrades,
      'autoTrades': autoTrades,
      'manualTrades': manualTrades,
      'totalProfitLoss': totalProfitLoss,
      'avgProfitRate': avgProfitRate,
    };
  }

  /// 오래된 거래 내역 정리
  Future<void> cleanupOldTradeHistory({int daysToKeep = 90}) async {
    try {
      final db = await _databaseHelper.database;
      final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));
      final cutoffDateString = cutoffDate.toIso8601String();
      
      final deletedCount = await db.delete(
        'trade_history',
        where: 'created_at < ?',
        whereArgs: [cutoffDateString],
      );
      
      print('✅ 오래된 거래 내역 정리 완료: $deletedCount개 삭제');
    } catch (e) {
      print('❌ 오래된 거래 내역 정리 실패: $e');
    }
  }
}
