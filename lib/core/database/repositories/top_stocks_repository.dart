import '../database_helper.dart';
import 'package:sqflite/sqflite.dart';
import '../../trading/market_time_validator.dart';

/// 상위 점수 종목 전용 Repository
/// 실시간 점수 계산 결과를 DB에 저장하고 상위 종목을 빠르게 조회
class TopStocksRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// 상위 점수 종목 테이블 생성
  Future<void> createTopStocksTable() async {
    final db = await _dbHelper.database;
    
    await db.execute('''
      CREATE TABLE IF NOT EXISTS top_stocks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        stock_code TEXT NOT NULL UNIQUE,
        stock_name TEXT NOT NULL,
        market TEXT NOT NULL,
        score REAL NOT NULL,
        current_price REAL NOT NULL,
        price_change REAL DEFAULT 0,
        price_change_rate REAL DEFAULT 0,
        volume INTEGER DEFAULT 0,
        volume_ratio REAL DEFAULT 1.0,
        trading_amount REAL DEFAULT 0,
        trading_currency TEXT DEFAULT 'KRW',
        rank INTEGER NOT NULL,
        last_updated INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    
    // 인덱스 생성 (성능 최적화)
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_top_stocks_score 
      ON top_stocks(score DESC)
    ''');
    
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_top_stocks_market 
      ON top_stocks(market, score DESC)
    ''');
    
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_top_stocks_rank 
      ON top_stocks(rank ASC)
    ''');
    
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_top_stocks_updated 
      ON top_stocks(last_updated DESC)
    ''');

    // 마이그레이션: 누락된 컬럼 추가 (SQLite는 ADD COLUMN만 지원)
    try { await db.execute("ALTER TABLE top_stocks ADD COLUMN trading_amount REAL DEFAULT 0"); } catch (_) {}
    try { await db.execute("ALTER TABLE top_stocks ADD COLUMN trading_currency TEXT DEFAULT 'KRW'"); } catch (_) {}
    
    print('✅ 상위 점수 종목 테이블 생성 완료');
  }

  /// 상위 점수 종목 저장/업데이트
  Future<int> saveTopStock({
    required String stockCode,
    required String stockName,
    required String market,
    required double score,
    required double currentPrice,
    double priceChange = 0,
    double priceChangeRate = 0,
    int volume = 0,
    double volumeRatio = 1.0,
    required int rank,
    double? tradingAmount,
    String? tradingCurrency,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    return await db.insert(
      'top_stocks',
      {
        'stock_code': stockCode,
        'stock_name': stockName,
        'market': MarketTimeValidator.instance.getMarketFromSymbol(stockCode),
        'score': score,
        'current_price': currentPrice,
        'price_change': priceChange,
        'price_change_rate': priceChangeRate,
        'volume': volume,
        'volume_ratio': volumeRatio,
        'trading_amount': tradingAmount ?? 0,
        'trading_currency': tradingCurrency ?? (market == 'KOSPI' || market == 'KOSDAQ' ? 'KRW' : 'USD'),
        'rank': rank,
        'last_updated': now,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 여러 상위 점수 종목 일괄 저장/업데이트
  Future<void> saveManyTopStocks(List<Map<String, dynamic>> stocks) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      for (final stock in stocks) {
        final String code = stock['stockCode'];
        await txn.insert(
          'top_stocks',
          {
            'stock_code': code,
            'stock_name': stock['stockName'],
            'market': MarketTimeValidator.instance.getMarketFromSymbol(code),
            'score': stock['score'],
            'current_price': stock['currentPrice'],
            'price_change': stock['priceChange'] ?? 0,
            'price_change_rate': stock['priceChangeRate'] ?? 0,
            'volume': stock['volume'] ?? 0,
            'volume_ratio': stock['volumeRatio'] ?? 1.0,
            'trading_amount': stock['tradingAmount'] ?? 0,
            'trading_currency': stock['tradingCurrency'] ?? 'KRW',
            'rank': stock['rank'],
            'last_updated': now,
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    
    print('📊 상위 점수 종목 ${stocks.length}개 저장 완료');
  }

  /// 저장된 market 필드 일괄 정규화 (코드 기반 재판별)
  Future<int> normalizeStoredMarkets() async {
    final db = await _dbHelper.database;
    final rows = await db.query('top_stocks', columns: ['stock_code', 'market']);
    int updated = 0;
    for (final row in rows) {
      final code = row['stock_code'] as String;
      final current = row['market'] as String? ?? '';
      final normalized = MarketTimeValidator.instance.getMarketFromSymbol(code);
      if (normalized.isNotEmpty && normalized != current) {
        await db.update(
          'top_stocks',
          {'market': normalized, 'updated_at': DateTime.now().millisecondsSinceEpoch},
          where: 'stock_code = ?',
          whereArgs: [code],
        );
        updated++;
      }
    }
    print('🛠️ market 필드 정규화 완료: ${updated}건 수정');
    return updated;
  }

  /// 상위 점수 종목 조회 (점수 기준 정렬)
  Future<List<Map<String, dynamic>>> getTopStocks({
    int limit = 50,
    double minScore = 0.0,
    String? market,
    int? maxAgeMinutes,
    double? minTradingAmountKrw,
    double? minTradingAmountUsd,
  }) async {
    final db = await _dbHelper.database;
    
    String whereClause = 'score >= ?';
    List<dynamic> whereArgs = [minScore];
    
    if (market != null) {
      whereClause += ' AND market = ?';
      whereArgs.add(market);
    }
    if (minTradingAmountKrw != null || minTradingAmountUsd != null) {
      if (market == null) {
        // 시장 미지정: KRW/ USD 모두에 대해 조건 적용
        final hasKrw = minTradingAmountKrw != null;
        final hasUsd = minTradingAmountUsd != null;
        if (hasKrw && hasUsd) {
          whereClause +=
              " AND ((market IN ('KOSPI','KOSDAQ') AND trading_amount >= ?) OR (market IN ('NASDAQ','NYSE') AND trading_currency = 'USD' AND trading_amount >= ?))";
          whereArgs.add(minTradingAmountKrw);
          whereArgs.add(minTradingAmountUsd);
        } else if (hasKrw) {
          whereClause += " AND (market IN ('KOSPI','KOSDAQ') AND trading_amount >= ?)";
          whereArgs.add(minTradingAmountKrw);
        } else if (hasUsd) {
          whereClause += " AND (market IN ('NASDAQ','NYSE') AND trading_currency = 'USD' AND trading_amount >= ?)";
          whereArgs.add(minTradingAmountUsd);
        }
      } else if (market == 'KOSPI' || market == 'KOSDAQ') {
        if (minTradingAmountKrw != null) {
          whereClause += " AND trading_amount >= ?";
          whereArgs.add(minTradingAmountKrw);
        }
      } else if (market == 'NASDAQ' || market == 'NYSE') {
        if (minTradingAmountUsd != null) {
          whereClause += " AND trading_currency = 'USD' AND trading_amount >= ?";
          whereArgs.add(minTradingAmountUsd);
        }
      }
    }
    
    if (maxAgeMinutes != null) {
      final cutoffTime = DateTime.now()
          .subtract(Duration(minutes: maxAgeMinutes))
          .millisecondsSinceEpoch;
      whereClause += ' AND last_updated >= ?';
      whereArgs.add(cutoffTime);
    }
    
    final results = await db.query(
      'top_stocks',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'score DESC, rank ASC',
      limit: limit,
    );
    
    return results.map((row) => {
      'stockCode': row['stock_code'],
      'stockName': row['stock_name'],
      'market': row['market'],
      'score': row['score'],
      'currentPrice': row['current_price'],
      'priceChange': row['price_change'],
      'priceChangeRate': row['price_change_rate'],
      'volume': row['volume'],
      'volumeRatio': row['volume_ratio'],
      'tradingAmount': row['trading_amount'],
      'tradingCurrency': row['trading_currency'],
      'rank': row['rank'],
      'lastUpdated': DateTime.fromMillisecondsSinceEpoch(row['last_updated'] as int),
    }).toList();
  }

  /// 특정 종목의 점수 조회
  Future<Map<String, dynamic>?> getStockScore(String stockCode) async {
    final db = await _dbHelper.database;
    
    final results = await db.query(
      'top_stocks',
      where: 'stock_code = ?',
      whereArgs: [stockCode],
      limit: 1,
    );
    
    if (results.isEmpty) return null;
    
    final row = results.first;
    return {
      'stockCode': row['stock_code'],
      'stockName': row['stock_name'],
      'market': row['market'],
      'score': row['score'],
      'currentPrice': row['current_price'],
      'priceChange': row['price_change'],
      'priceChangeRate': row['price_change_rate'],
      'volume': row['volume'],
      'volumeRatio': row['volume_ratio'],
      'rank': row['rank'],
      'lastUpdated': DateTime.fromMillisecondsSinceEpoch(row['last_updated'] as int),
    };
  }

  /// 시장별 상위 점수 종목 조회
  Future<List<Map<String, dynamic>>> getTopStocksByMarket({
    required String market,
    int limit = 50,
    double minScore = 0.0,
    double? minTradingAmountKrw,
    double? minTradingAmountUsd,
  }) async {
    return await getTopStocks(
      limit: limit,
      minScore: minScore,
      market: market,
      minTradingAmountKrw: minTradingAmountKrw,
      minTradingAmountUsd: minTradingAmountUsd,
    );
  }

  /// 점수 범위별 종목 조회
  Future<List<Map<String, dynamic>>> getStocksByScoreRange({
    required double minScore,
    required double maxScore,
    int limit = 100,
    String? market,
  }) async {
    final db = await _dbHelper.database;
    
    String whereClause = 'score >= ? AND score <= ?';
    List<dynamic> whereArgs = [minScore, maxScore];
    
    if (market != null) {
      whereClause += ' AND market = ?';
      whereArgs.add(market);
    }
    
    final results = await db.query(
      'top_stocks',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'score DESC',
      limit: limit,
    );
    
    return results.map((row) => {
      'stockCode': row['stock_code'],
      'stockName': row['stock_name'],
      'market': row['market'],
      'score': row['score'],
      'currentPrice': row['current_price'],
      'priceChange': row['price_change'],
      'priceChangeRate': row['price_change_rate'],
      'volume': row['volume'],
      'volumeRatio': row['volume_ratio'],
      'rank': row['rank'],
      'lastUpdated': DateTime.fromMillisecondsSinceEpoch(row['last_updated'] as int),
    }).toList();
  }

  /// 상위 점수 종목 통계 조회
  Future<Map<String, dynamic>> getTopStocksStatistics() async {
    final db = await _dbHelper.database;
    
    // 전체 통계
    final totalResult = await db.rawQuery('''
      SELECT 
        COUNT(*) as total_count,
        AVG(score) as avg_score,
        MAX(score) as max_score,
        MIN(score) as min_score,
        MAX(last_updated) as last_update_time
      FROM top_stocks
    ''');
    
    // 시장별 통계
    final marketResult = await db.rawQuery('''
      SELECT 
        market,
        COUNT(*) as count,
        AVG(score) as avg_score,
        MAX(score) as max_score
      FROM top_stocks
      GROUP BY market
    ''');
    
    // 점수 분포
    final distributionResult = await db.rawQuery('''
      SELECT 
        CASE 
          WHEN score >= 0.8 THEN 'high'
          WHEN score >= 0.6 THEN 'medium'
          WHEN score >= 0.4 THEN 'low'
          ELSE 'very_low'
        END as score_range,
        COUNT(*) as count
      FROM top_stocks
      GROUP BY score_range
    ''');
    
    final total = totalResult.first;
    final marketStats = marketResult.map((row) => {
      'market': row['market'],
      'count': row['count'],
      'avgScore': row['avg_score'],
      'maxScore': row['max_score'],
    }).toList();
    
    final distribution = distributionResult.map((row) => {
      'range': row['score_range'],
      'count': row['count'],
    }).toList();
    
    return {
      'total': {
        'count': total['total_count'],
        'avgScore': total['avg_score'],
        'maxScore': total['max_score'],
        'minScore': total['min_score'],
        'lastUpdateTime': total['last_update_time'] != null 
            ? DateTime.fromMillisecondsSinceEpoch(total['last_update_time'] as int)
            : null,
      },
      'byMarket': marketStats,
      'distribution': distribution,
    };
  }

  /// 오래된 데이터 정리 (30일 이상)
  Future<int> cleanupOldData({int daysOld = 30}) async {
    final db = await _dbHelper.database;
    final cutoffTime = DateTime.now()
        .subtract(Duration(days: daysOld))
        .millisecondsSinceEpoch;
    
    final result = await db.delete(
      'top_stocks',
      where: 'last_updated < ?',
      whereArgs: [cutoffTime],
    );
    
    print('🧹 오래된 상위 점수 데이터 ${result}개 정리 완료');
    return result;
  }

  /// 모든 상위 점수 종목 삭제
  Future<int> deleteAllTopStocks() async {
    final db = await _dbHelper.database;
    final result = await db.delete('top_stocks');
    print('🗑️ 모든 상위 점수 종목 삭제 완료');
    return result;
  }

  /// 특정 종목 삭제
  Future<int> deleteTopStock(String stockCode) async {
    final db = await _dbHelper.database;
    return await db.delete(
      'top_stocks',
      where: 'stock_code = ?',
      whereArgs: [stockCode],
    );
  }

  /// 테이블 존재 여부 확인
  Future<bool> tableExists() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery('''
      SELECT name FROM sqlite_master 
      WHERE type='table' AND name='top_stocks'
    ''');
    return result.isNotEmpty;
  }
}
