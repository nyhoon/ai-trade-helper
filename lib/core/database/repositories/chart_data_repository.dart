import 'package:sqflite/sqflite.dart';
import '../database_helper.dart';

/// 차트 데이터 Repository - 최신 100일 보관, 증분 업데이트
class ChartDataRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  /// 차트 데이터 테이블 생성
  Future<void> createTable() async {
    final db = await _dbHelper.database;
    
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chart_data (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        stock_code TEXT NOT NULL,
        market TEXT NOT NULL,
        date TEXT NOT NULL,
        open REAL NOT NULL,
        high REAL NOT NULL,
        low REAL NOT NULL,
        close REAL NOT NULL,
        volume INTEGER NOT NULL,
        trade_amount REAL,
        created_at INTEGER NOT NULL
      )
    ''');
    
    // 인덱스 생성
    await db.execute('CREATE INDEX IF NOT EXISTS idx_chart_data_stock_code ON chart_data (stock_code)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_chart_data_date ON chart_data (date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_chart_data_stock_date ON chart_data (stock_code, date)');
    
    print('✅ 차트 데이터 테이블 생성 완료');
  }

  /// 차트 데이터 삽입 또는 업데이트
  Future<void> insertOrUpdateChartData({
    required String stockCode,
    required String market,
    required String date,
    required double open,
    required double high,
    required double low,
    required double close,
    required int volume,
    double? tradeAmount,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.insert(
      'chart_data',
      {
        'stock_code': stockCode,
        'market': market,
        'date': date,
        'open': open,
        'high': high,
        'low': low,
        'close': close,
        'volume': volume,
        'trade_amount': tradeAmount,
        'created_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

    /// 여러 종목의 차트 데이터 일괄 삽입 (최적화)
  Future<void> insertMultipleChartData(List<Map<String, dynamic>> chartDataList) async {
    if (chartDataList.isEmpty) return;
    
    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    try {
      // 트랜잭션 사용으로 락 방지 및 성능 향상
      await db.transaction((txn) async {
        // 배치 삽입으로 성능 향상
        final batch = txn.batch();
        
        for (final data in chartDataList) {
          // stockCode와 stock_code 필드 모두 지원
          final stockCode = data['stock_code'] ?? data['stockCode'];
          if (stockCode == null) {
            print('⚠️ 차트 데이터에 stock_code가 없음: $data');
            continue;
          }
          
          batch.insert(
            'chart_data',
            {
              'stock_code': stockCode,
              'market': data['market'],
              'date': data['date'],
              'open': data['open'],
              'high': data['high'],
              'low': data['low'],
              'close': data['close'],
              'volume': data['volume'],
              'trade_amount': data['trade_amount'],
              'created_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        
        // 배치 실행
        await batch.commit(noResult: true);
      });
      
      print('📊 차트 데이터 일괄 삽입 완료: ${chartDataList.length}개');
    } catch (e) {
      print('❌ 차트 데이터 일괄 삽입 실패: $e');
      rethrow;
    }
  }

  /// 특정 종목의 차트 데이터 조회 (최신 100일)
  Future<List<Map<String, dynamic>>> getChartData(
    String stockCode, {
    int limit = 100,
    String? startDate,
    String? endDate,
  }) async {
    final db = await _dbHelper.database;

    String whereClause = 'stock_code = ?';
    List<dynamic> whereArgs = [stockCode];

    if (startDate != null) {
      whereClause += ' AND date >= ?';
      whereArgs.add(startDate);
    }

    if (endDate != null) {
      whereClause += ' AND date <= ?';
      whereArgs.add(endDate);
    }

    final result = await db.query(
      'chart_data',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'date ASC',   // 🔧 과거→최신 순서로 변경 (기술지표 계산 표준)
      limit: limit,
    );

    return result;
  }

  /// 여러 종목의 차트 데이터 조회
  Future<Map<String, List<Map<String, dynamic>>>> getMultipleChartData(
    List<String> stockCodes, {
    int limit = 100,
    String? startDate,
    String? endDate,
  }) async {
    final db = await _dbHelper.database;
    final result = <String, List<Map<String, dynamic>>>{};

    for (final stockCode in stockCodes) {
      final chartData = await getChartData(
        stockCode,
        limit: limit,
        startDate: startDate,
        endDate: endDate,
      );
      result[stockCode] = chartData;
    }

    return result;
  }

  /// 관심종목과 보유종목의 차트 데이터 조회
  Future<Map<String, List<Map<String, dynamic>>>> getActiveChartData({
    int limit = 100,
    String? startDate,
    String? endDate,
  }) async {
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

    return await getMultipleChartData(
      stockCodes,
      limit: limit,
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// 최신 차트 데이터 조회 (특정 날짜)
  Future<List<Map<String, dynamic>>> getLatestChartData(
    List<String> stockCodes,
    String date,
  ) async {
    final db = await _dbHelper.database;

    final placeholders = List.filled(stockCodes.length, '?').join(',');
    final result = await db.rawQuery('''
      SELECT * FROM chart_data 
      WHERE stock_code IN ($placeholders) AND date = ?
      ORDER BY stock_code
    ''', [...stockCodes, date]);

    return result;
  }

  /// 증분 업데이트용 최신 날짜 조회
  Future<String?> getLatestDate(String stockCode) async {
    final db = await _dbHelper.database;

    final result = await db.query(
      'chart_data',
      columns: ['date'],
      where: 'stock_code = ?',
      whereArgs: [stockCode],
      orderBy: 'date DESC',  // 최신 날짜는 DESC 유지
      limit: 1,
    );

    if (result.isNotEmpty) {
      return result.first['date'] as String;
    }

    return null;
  }

  /// 증분 업데이트용 최신 날짜들 조회
  Future<Map<String, String>> getLatestDates(List<String> stockCodes) async {
    final db = await _dbHelper.database;
    final result = <String, String>{};

    for (final stockCode in stockCodes) {
      final latestDate = await getLatestDate(stockCode);
      if (latestDate != null) {
        result[stockCode] = latestDate;
      }
    }

    return result;
  }

  /// 특정 종목의 차트 데이터 존재 여부 확인
  Future<bool> hasChartData(String stockCode, String date) async {
    final db = await _dbHelper.database;

    final result = await db.query(
      'chart_data',
      columns: ['id'],
      where: 'stock_code = ? AND date = ?',
      whereArgs: [stockCode, date],
      limit: 1,
    );

    return result.isNotEmpty;
  }

  /// 차트 데이터 삭제 (특정 종목)
  Future<int> deleteChartData(String stockCode) async {
    final db = await _dbHelper.database;

    return await db.delete(
      'chart_data',
      where: 'stock_code = ?',
      whereArgs: [stockCode],
    );
  }

  /// 차트 데이터 삭제 (특정 날짜 범위)
  Future<int> deleteChartDataByDateRange(String startDate, String endDate) async {
    final db = await _dbHelper.database;

    return await db.delete(
      'chart_data',
      where: 'date BETWEEN ? AND ?',
      whereArgs: [startDate, endDate],
    );
  }

  /// 차트 데이터 통계 조회
  Future<Map<String, dynamic>> getChartDataStats() async {
    final db = await _dbHelper.database;

    final totalCount = await db.rawQuery('SELECT COUNT(*) as count FROM chart_data');
    final uniqueStocks = await db.rawQuery('SELECT COUNT(DISTINCT stock_code) as count FROM chart_data');
    final dateRange = await db.rawQuery('''
      SELECT MIN(date) as min_date, MAX(date) as max_date FROM chart_data
    ''');

    return {
      'total_records': totalCount.first['count'] as int,
      'unique_stocks': uniqueStocks.first['count'] as int,
      'date_range': {
        'min_date': dateRange.first['min_date'] as String?,
        'max_date': dateRange.first['max_date'] as String?,
      },
    };
  }

  /// 특정 종목의 차트 데이터 통계
  Future<Map<String, dynamic>> getStockChartDataStats(String stockCode) async {
    final db = await _dbHelper.database;

    final count = await db.rawQuery('''
      SELECT COUNT(*) as count FROM chart_data WHERE stock_code = ?
    ''', [stockCode]);

    final dateRange = await db.rawQuery('''
      SELECT MIN(date) as min_date, MAX(date) as max_date 
      FROM chart_data WHERE stock_code = ?
    ''', [stockCode]);

    return {
      'stock_code': stockCode,
      'record_count': count.first['count'] as int,
      'date_range': {
        'min_date': dateRange.first['min_date'] as String?,
        'max_date': dateRange.first['max_date'] as String?,
      },
    };
  }

  /// 오래된 차트 데이터 정리 (100일 초과)
  Future<Map<String, dynamic>> cleanupOldChartData() async {
    final db = await _dbHelper.database;
    
    try {
      // 100일 전 날짜 계산
      final hundredDaysAgo = DateTime.now().subtract(const Duration(days: 100));
      final cutoffDate = '${hundredDaysAgo.year.toString().padLeft(4, '0')}-${hundredDaysAgo.month.toString().padLeft(2, '0')}-${hundredDaysAgo.day.toString().padLeft(2, '0')}';
      
      final deletedCount = await db.delete(
        'chart_data',
        where: 'date < ?',
        whereArgs: [cutoffDate],
      );
      
      return {
        'deleted_records': deletedCount,
        'cutoff_date': cutoffDate,
      };
    } catch (e) {
      print('❌ 오래된 차트 데이터 정리 실패: $e');
      return {
        'deleted_records': 0,
        'cutoff_date': '',
        'error': e.toString(),
      };
    }
  }

  /// 비활성 종목의 차트 데이터 정리
  Future<int> cleanupInactiveChartData() async {
    final db = await _dbHelper.database;

    return await db.rawDelete('''
      DELETE FROM chart_data 
      WHERE stock_code NOT IN (
        SELECT stock_code FROM watchlist WHERE is_active = 1
        UNION
        SELECT stock_code FROM holdings
      )
    ''');
  }

  /// 비활성 종목의 차트 데이터 정리 (Map 반환)
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
        DELETE FROM chart_data 
        WHERE stock_code NOT IN ($placeholders)
      ''', activeStocks);
      
      return {
        'deleted_records': deletedCount,
        'active_stocks_count': activeStocks.length,
      };
    } catch (e) {
      print('❌ 비활성 종목 차트 데이터 정리 실패: $e');
      return {
        'deleted_records': 0,
        'active_stocks_count': activeStocks.length,
        'error': e.toString(),
      };
    }
  }

  /// 차트 데이터 백업 (JSON 형식)
  Future<Map<String, dynamic>> exportChartData({
    List<String>? stockCodes,
    String? startDate,
    String? endDate,
  }) async {
    final db = await _dbHelper.database;

    String whereClause = '1=1';
    List<dynamic> whereArgs = [];

    if (stockCodes != null && stockCodes.isNotEmpty) {
      final placeholders = List.filled(stockCodes.length, '?').join(',');
      whereClause += ' AND stock_code IN ($placeholders)';
      whereArgs.addAll(stockCodes);
    }

    if (startDate != null) {
      whereClause += ' AND date >= ?';
      whereArgs.add(startDate);
    }

    if (endDate != null) {
      whereClause += ' AND date <= ?';
      whereArgs.add(endDate);
    }

    final result = await db.query(
      'chart_data',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'stock_code, date',
    );

    return {
      'export_date': DateTime.now().toIso8601String(),
      'data_count': result.length,
      'chart_data': result,
    };
  }

  /// 차트 데이터 복원 (JSON 형식)
  Future<void> importChartData(Map<String, dynamic> exportData) async {
    final chartDataList = exportData['chart_data'] as List<dynamic>;
    
    if (chartDataList.isEmpty) {
      return;
    }

    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      for (final data in chartDataList) {
        final chartData = data as Map<String, dynamic>;
        await txn.insert(
          'chart_data',
          {
            'stock_code': chartData['stock_code'],
            'market': chartData['market'],
            'date': chartData['date'],
            'open': chartData['open'],
            'high': chartData['high'],
            'low': chartData['low'],
            'close': chartData['close'],
            'volume': chartData['volume'],
            'trade_amount': chartData['trade_amount'],
            'created_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// 활성 종목의 차트 데이터 조회 (메모리 최적화)
  Future<List<Map<String, dynamic>>> getActiveStocksChartData({int limit = 1000}) async {
    final db = await _dbHelper.database;
    
    try {
      // 메모리 부족 방지를 위해 LIMIT 절 추가 및 필요한 컬럼만 SELECT
      final result = await db.rawQuery('''
        SELECT cd.stock_code, cd.market, cd.date, cd.close, cd.volume
        FROM chart_data cd
        WHERE cd.stock_code IN (
          SELECT stock_code FROM watchlist WHERE is_active = 1
          UNION
          SELECT stock_code FROM holdings
        )
        ORDER BY cd.stock_code, cd.date DESC
        LIMIT ?
      ''', [limit]);
      
      return result;
    } catch (e) {
      print('❌ 활성 종목 차트 데이터 조회 실패: $e');
      return [];
    }
  }

  /// 통계 정보 조회
  Future<Map<String, dynamic>> getStats() async {
    final db = await _dbHelper.database;
    
    try {
      // 전체 레코드 수
      final totalCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM chart_data')
      ) ?? 0;
      
      // 종목별 레코드 수
      final stockCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(DISTINCT stock_code) FROM chart_data')
      ) ?? 0;
      
      // 최신 데이터 날짜
      final latestDateResult = await db.rawQuery('SELECT MAX(date) FROM chart_data');
      final latestDate = latestDateResult.isNotEmpty ? latestDateResult.first['MAX(date)'] as String? ?? '' : '';
      
      // 오래된 데이터 날짜
      final oldestDateResult = await db.rawQuery('SELECT MIN(date) FROM chart_data');
      final oldestDate = oldestDateResult.isNotEmpty ? oldestDateResult.first['MIN(date)'] as String? ?? '' : '';
      
      return {
        'total_records': totalCount,
        'unique_stocks': stockCount,
        'latest_date': latestDate,
        'oldest_date': oldestDate,
        'avg_records_per_stock': stockCount > 0 ? (totalCount / stockCount).toStringAsFixed(2) : '0',
      };
    } catch (e) {
      print('❌ 차트 데이터 통계 조회 실패: $e');
      return {
        'total_records': 0,
        'unique_stocks': 0,
        'latest_date': '',
        'oldest_date': '',
        'avg_records_per_stock': '0',
        'error': e.toString(),
      };
    }
  }
}
