import 'package:sqflite/sqflite.dart';
import '../database_helper.dart';

/// 현재가 데이터 Repository - 실시간 현재가 관리
class CurrentPriceRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  /// 현재가 데이터 삽입 또는 업데이트
  Future<void> insertOrUpdateCurrentPrice({
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
    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.insert(
      'current_price',
      {
        'stock_code': stockCode,
        'market': market,
        'current_price': currentPrice,
        'prev_close': prevClose,
        'change_amount': changeAmount,
        'change_rate': changeRate,
        'volume': volume,
        'trade_amount': tradeAmount,
        'high_price': highPrice,
        'low_price': lowPrice,
        'open_price': openPrice,
        'market_cap': marketCap,
        'per': per,
        'pbr': pbr,
        'timestamp': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 여러 종목의 현재가 데이터 일괄 삽입 (최적화)
  Future<void> insertMultipleCurrentPrice(List<Map<String, dynamic>> priceDataList) async {
    if (priceDataList.isEmpty) return;
    
    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    try {
      // 트랜잭션 사용으로 락 방지 및 성능 향상
      await db.transaction((txn) async {
        // 배치 삽입으로 성능 향상
        final batch = txn.batch();
        
        for (final data in priceDataList) {
          batch.insert(
            'current_price',
            {
              'stock_code': data['stock_code'],
              'market': data['market'],
              'current_price': data['current_price'],
              'prev_close': data['prev_close'],
              'change_amount': data['change_amount'],
              'change_rate': data['change_rate'],
              'volume': data['volume'],
              'trade_amount': data['trade_amount'],
              'high_price': data['high_price'],
              'low_price': data['low_price'],
              'open_price': data['open_price'],
              'market_cap': data['market_cap'],
              'per': data['per'],
              'pbr': data['pbr'],
              'timestamp': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        
        // 배치 실행
        await batch.commit(noResult: true);
      });
      
      print('📊 현재가 데이터 일괄 삽입 완료: ${priceDataList.length}개');
    } catch (e) {
      print('❌ 현재가 데이터 일괄 삽입 실패: $e');
      rethrow;
    }
  }

  /// 특정 종목의 현재가 조회
  Future<Map<String, dynamic>?> getCurrentPrice(String stockCode) async {
    final db = await _dbHelper.database;

    final result = await db.query(
      'current_price',
      where: 'stock_code = ?',
      whereArgs: [stockCode],
      limit: 1,
    );

    if (result.isNotEmpty) {
      return result.first;
    }

    return null;
  }

  /// 여러 종목의 현재가 조회
  Future<Map<String, Map<String, dynamic>>> getMultipleCurrentPrice(List<String> stockCodes) async {
    final db = await _dbHelper.database;
    final result = <String, Map<String, dynamic>>{};

    if (stockCodes.isEmpty) {
      return result;
    }

    final placeholders = List.filled(stockCodes.length, '?').join(',');
    final queryResult = await db.rawQuery('''
      SELECT * FROM current_price 
      WHERE stock_code IN ($placeholders)
      ORDER BY stock_code
    ''', stockCodes);

    for (final row in queryResult) {
      result[row['stock_code'] as String] = row;
    }

    return result;
  }

  /// 관심종목과 보유종목의 현재가 조회
  Future<Map<String, Map<String, dynamic>>> getActiveCurrentPrice() async {
    final db = await _dbHelper.database;

    // 관심종목과 보유종목 조회
    final activeStocks = await db.rawQuery('''
      SELECT DISTINCT stock_code FROM (
        SELECT stock_code FROM watchlist WHERE is_active = 1
        UNION
        SELECT stock_code FROM holdings
      )
    ''');

    final stockCodes = activeStocks.map((e) => e['stock_code'] as String).toList();
    
    if (stockCodes.isEmpty) {
      return {};
    }

    return await getMultipleCurrentPrice(stockCodes);
  }

  /// 특정 시장의 현재가 조회
  Future<List<Map<String, dynamic>>> getCurrentPriceByMarket(String market) async {
    final db = await _dbHelper.database;

    final result = await db.query(
      'current_price',
      where: 'market = ?',
      whereArgs: [market],
      orderBy: 'stock_code',
    );

    return result;
  }

  /// 상승률 기준 정렬된 현재가 조회
  Future<List<Map<String, dynamic>>> getCurrentPriceByChangeRate({
    String? market,
    int limit = 50,
    bool ascending = false, // false: 상승률 높은 순, true: 하락률 높은 순
  }) async {
    final db = await _dbHelper.database;

    String whereClause = '1=1';
    List<dynamic> whereArgs = [];

    if (market != null) {
      whereClause += ' AND market = ?';
      whereArgs.add(market);
    }

    final result = await db.query(
      'current_price',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'change_rate ${ascending ? 'ASC' : 'DESC'}',
      limit: limit,
    );

    return result;
  }

  /// 거래량 기준 정렬된 현재가 조회
  Future<List<Map<String, dynamic>>> getCurrentPriceByVolume({
    String? market,
    int limit = 50,
    bool ascending = false, // false: 거래량 많은 순, true: 거래량 적은 순
  }) async {
    final db = await _dbHelper.database;

    String whereClause = '1=1';
    List<dynamic> whereArgs = [];

    if (market != null) {
      whereClause += ' AND market = ?';
      whereArgs.add(market);
    }

    final result = await db.query(
      'current_price',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'volume ${ascending ? 'ASC' : 'DESC'}',
      limit: limit,
    );

    return result;
  }

  /// 현재가 데이터 존재 여부 확인
  Future<bool> hasCurrentPrice(String stockCode) async {
    final db = await _dbHelper.database;

    final result = await db.query(
      'current_price',
      columns: ['id'],
      where: 'stock_code = ?',
      whereArgs: [stockCode],
      limit: 1,
    );

    return result.isNotEmpty;
  }

  /// 현재가 데이터 삭제 (특정 종목)
  Future<int> deleteCurrentPrice(String stockCode) async {
    final db = await _dbHelper.database;

    return await db.delete(
      'current_price',
      where: 'stock_code = ?',
      whereArgs: [stockCode],
    );
  }

  /// 현재가 데이터 삭제 (특정 시장)
  Future<int> deleteCurrentPriceByMarket(String market) async {
    final db = await _dbHelper.database;

    return await db.delete(
      'current_price',
      where: 'market = ?',
      whereArgs: [market],
    );
  }

  /// 오래된 현재가 데이터 정리 (1시간 이상)
  Future<int> cleanupOldCurrentPrice() async {
    final db = await _dbHelper.database;
    final oneHourAgo = DateTime.now().millisecondsSinceEpoch - (60 * 60 * 1000);

    return await db.delete(
      'current_price',
      where: 'timestamp < ?',
      whereArgs: [oneHourAgo],
    );
  }

  /// 비활성 종목의 현재가 데이터 정리
  Future<Map<String, dynamic>> cleanupInactiveStocks(List<String> activeStocks) async {
    final db = await _dbHelper.database;
    
    try {
      if (activeStocks.isEmpty) {
        return {
          'deleted_records': 0,
          'active_stocks_count': 0,
        };
      }
      
      final placeholders = List.filled(activeStocks.length, '?').join(',');
      final deletedCount = await db.rawDelete('''
        DELETE FROM current_price 
        WHERE stock_code NOT IN ($placeholders)
      ''', activeStocks);
      
      return {
        'deleted_records': deletedCount,
        'active_stocks_count': activeStocks.length,
      };
    } catch (e) {
      print('❌ 비활성 종목 현재가 데이터 정리 실패: $e');
      return {
        'deleted_records': 0,
        'active_stocks_count': activeStocks.length,
        'error': e.toString(),
      };
    }
  }

  /// 오래된 현재가 데이터 정리 (1시간 이상) - Map 반환
  Future<Map<String, dynamic>> cleanupOldCurrentPriceData() async {
    final db = await _dbHelper.database;
    
    try {
      final oneHourAgo = DateTime.now().millisecondsSinceEpoch - (60 * 60 * 1000);
      
      final deletedCount = await db.delete(
        'current_price',
        where: 'timestamp < ?',
        whereArgs: [oneHourAgo],
      );
      
      return {
        'deleted_records': deletedCount,
        'cutoff_timestamp': oneHourAgo,
      };
    } catch (e) {
      print('❌ 오래된 현재가 데이터 정리 실패: $e');
      return {
        'deleted_records': 0,
        'cutoff_timestamp': 0,
        'error': e.toString(),
      };
    }
  }

  /// 현재가 데이터 통계 조회
  Future<Map<String, dynamic>> getCurrentPriceStats() async {
  
  /// 거래량 기준 상위 종목 조회
  Future<List<Map<String, dynamic>>> getCurrentPriceByVolume({
    String? market,
    int limit = 50,
    bool ascending = false,
  }) async {
    final db = await _dbHelper.database;
    
    String whereClause = '1=1';
    List<dynamic> whereArgs = [];
    
    if (market != null && market.isNotEmpty) {
      whereClause += ' AND market = ?';
      whereArgs.add(market);
    }
    
    final orderBy = ascending ? 'volume ASC' : 'volume DESC';
    
    final result = await db.query(
      'current_price',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
    );
    
    return result;
  }
  
  /// 모든 현재가 데이터 조회
  Future<List<Map<String, dynamic>>> getAllCurrentPrices() async {
    final db = await _dbHelper.database;
    return await db.query('current_price');
  }
    final db = await _dbHelper.database;

    final totalCount = await db.rawQuery('SELECT COUNT(*) as count FROM current_price');
    final uniqueStocks = await db.rawQuery('SELECT COUNT(DISTINCT stock_code) as count FROM current_price');
    final marketStats = await db.rawQuery('''
      SELECT market, COUNT(*) as count FROM current_price GROUP BY market
    ''');

    return {
      'total_records': totalCount.first['count'] as int,
      'unique_stocks': uniqueStocks.first['count'] as int,
      'market_stats': marketStats,
    };
  }

  /// 특정 종목의 현재가 통계
  Future<Map<String, dynamic>> getStockCurrentPriceStats(String stockCode) async {
    final db = await _dbHelper.database;

    final result = await db.query(
      'current_price',
      where: 'stock_code = ?',
      whereArgs: [stockCode],
      limit: 1,
    );

    if (result.isEmpty) {
      return {
        'stock_code': stockCode,
        'has_data': false,
      };
    }

    final data = result.first;
    return {
      'stock_code': stockCode,
      'has_data': true,
      'current_price': data['current_price'],
      'change_rate': data['change_rate'],
      'volume': data['volume'],
      'timestamp': data['timestamp'],
    };
  }

  /// 현재가 데이터 백업 (JSON 형식)
  Future<Map<String, dynamic>> exportCurrentPrice({
    List<String>? stockCodes,
    String? market,
  }) async {
    final db = await _dbHelper.database;

    String whereClause = '1=1';
    List<dynamic> whereArgs = [];

    if (stockCodes != null && stockCodes.isNotEmpty) {
      final placeholders = List.filled(stockCodes.length, '?').join(',');
      whereClause += ' AND stock_code IN ($placeholders)';
      whereArgs.addAll(stockCodes);
    }

    if (market != null) {
      whereClause += ' AND market = ?';
      whereArgs.add(market);
    }

    final result = await db.query(
      'current_price',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'stock_code',
    );

    return {
      'export_date': DateTime.now().toIso8601String(),
      'data_count': result.length,
      'current_price_data': result,
    };
  }

  /// 현재가 데이터 복원 (JSON 형식)
  Future<void> importCurrentPrice(Map<String, dynamic> exportData) async {
    final priceDataList = exportData['current_price_data'] as List<dynamic>;
    
    if (priceDataList.isEmpty) {
      return;
    }

    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      for (final data in priceDataList) {
        final priceData = data as Map<String, dynamic>;
        await txn.insert(
          'current_price',
          {
            'stock_code': priceData['stock_code'],
            'market': priceData['market'],
            'current_price': priceData['current_price'],
            'prev_close': priceData['prev_close'],
            'change_amount': priceData['change_amount'],
            'change_rate': priceData['change_rate'],
            'volume': priceData['volume'],
            'trade_amount': priceData['trade_amount'],
            'high_price': priceData['high_price'],
            'low_price': priceData['low_price'],
            'open_price': priceData['open_price'],
            'market_cap': priceData['market_cap'],
            'per': priceData['per'],
            'pbr': priceData['pbr'],
            'timestamp': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// 현재가 데이터 검증 (유효성 검사)
  Future<List<String>> validateCurrentPriceData() async {
    final db = await _dbHelper.database;
    final errors = <String>[];

    // 1. 필수 필드 검증
    final invalidData = await db.rawQuery('''
      SELECT stock_code FROM current_price 
      WHERE current_price IS NULL OR prev_close IS NULL OR volume IS NULL
    ''');

    for (final row in invalidData) {
      errors.add('${row['stock_code']}: 필수 필드 누락');
    }

    // 2. 가격 유효성 검증 (음수 가격)
    final negativePrice = await db.rawQuery('''
      SELECT stock_code FROM current_price 
      WHERE current_price < 0 OR prev_close < 0 OR high_price < 0 OR low_price < 0 OR open_price < 0
    ''');

    for (final row in negativePrice) {
      errors.add('${row['stock_code']}: 음수 가격 발견');
    }

    // 3. 거래량 유효성 검증 (음수 거래량)
    final negativeVolume = await db.rawQuery('''
      SELECT stock_code FROM current_price 
      WHERE volume < 0
    ''');

    for (final row in negativeVolume) {
      errors.add('${row['stock_code']}: 음수 거래량 발견');
    }

    return errors;
  }

  /// 모든 현재가 데이터 조회
  Future<List<Map<String, dynamic>>> getAllCurrentPrices() async {
    final db = await _dbHelper.database;
    
    try {
      final result = await db.query(
        'current_price',
        orderBy: 'stock_code',
      );
      
      return result;
    } catch (e) {
      print('❌ 모든 현재가 데이터 조회 실패: $e');
      return [];
    }
  }

  /// 활성 종목의 현재가 데이터 조회 (메모리 최적화)
  Future<List<Map<String, dynamic>>> getActiveStocksCurrentPrices({int limit = 500}) async {
    final db = await _dbHelper.database;
    
    try {
      // 메모리 부족 방지를 위해 LIMIT 절 추가 및 필요한 컬럼만 SELECT
      final result = await db.rawQuery('''
        SELECT cp.stock_code, cp.market, cp.current_price, cp.change_rate, cp.volume, cp.timestamp
        FROM current_price cp
        WHERE cp.stock_code IN (
          SELECT stock_code FROM watchlist WHERE is_active = 1
          UNION
          SELECT stock_code FROM holdings
        )
        ORDER BY cp.timestamp DESC
        LIMIT ?
      ''', [limit]);
      
      return result;
    } catch (e) {
      print('❌ 활성 종목 현재가 데이터 조회 실패: $e');
      return [];
    }
  }

  /// 통계 정보 조회
  Future<Map<String, dynamic>> getStats() async {
    final db = await _dbHelper.database;
    
    try {
      // 전체 레코드 수
      final totalCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM current_price')
      ) ?? 0;
      
      // 종목별 레코드 수
      final stockCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(DISTINCT stock_code) FROM current_price')
      ) ?? 0;
      
      // 최신 데이터 시간
      final latestTimestamp = Sqflite.firstIntValue(
        await db.rawQuery('SELECT MAX(timestamp) FROM current_price')
      ) ?? 0;
      
      // 오래된 데이터 시간
      final oldestTimestamp = Sqflite.firstIntValue(
        await db.rawQuery('SELECT MIN(timestamp) FROM current_price')
      ) ?? 0;
      
      // 평균 가격
      final avgPriceResult = await db.rawQuery('SELECT AVG(current_price) FROM current_price WHERE current_price > 0');
      final avgPrice = avgPriceResult.isNotEmpty ? avgPriceResult.first['AVG(current_price)'] as double? ?? 0.0 : 0.0;
      
      return {
        'total_records': totalCount,
        'unique_stocks': stockCount,
        'latest_timestamp': latestTimestamp,
        'oldest_timestamp': oldestTimestamp,
        'avg_price': avgPrice.toStringAsFixed(2),
        'avg_records_per_stock': stockCount > 0 ? (totalCount / stockCount).toStringAsFixed(2) : '0',
      };
    } catch (e) {
      print('❌ 현재가 데이터 통계 조회 실패: $e');
      return {
        'total_records': 0,
        'unique_stocks': 0,
        'latest_timestamp': 0,
        'oldest_timestamp': 0,
        'avg_price': '0.00',
        'avg_records_per_stock': '0',
        'error': e.toString(),
      };
    }
  }
}
