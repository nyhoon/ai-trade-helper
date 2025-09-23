import 'package:sqflite/sqflite.dart';
import '../database_helper.dart';

/// 보유종목 Repository
class HoldingsRepository {
  final DatabaseHelper _databaseHelper = DatabaseHelper();

  Future<String> _resolveMarket(DatabaseExecutor db, String pdno) async {
    try {
      final List<Map<String, Object?>> rows = await db.query(
        'stock_master',
        columns: ['market'],
        where: 'stock_code = ?',
        whereArgs: [pdno],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final market = rows.first['market'] as String?;
        if (market != null && market.isNotEmpty) return market;
      }
    } catch (_) {}
    return 'UNKNOWN';
  }

  /// 테이블 생성 (API 필드명 사용)
  Future<void> createTable() async {
    final db = await _databaseHelper.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS holdings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pdno TEXT NOT NULL, -- API 필드명: 종목코드
        prdt_name TEXT NOT NULL, -- API 필드명: 종목명
        market TEXT NOT NULL,
        hldg_qty INTEGER NOT NULL, -- API 필드명: 보유수량
        pchs_avg_pric REAL NOT NULL, -- API 필드명: 평균단가
        prpr REAL NOT NULL, -- API 필드명: 현재가
        evlu_amt REAL NOT NULL, -- API 필드명: 평가금액
        evlu_pfls_amt REAL NOT NULL, -- API 필드명: 평가손익금액
        evlu_pfls_rt REAL NOT NULL, -- API 필드명: 평가손익률
        updated_at INTEGER NOT NULL,
        UNIQUE(pdno)
      )
    ''');
    
    // 인덱스 생성
    await db.execute('CREATE INDEX IF NOT EXISTS idx_holdings_pdno ON holdings (pdno)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_holdings_updated_at ON holdings (updated_at)');
  }

  /// 보유종목 저장/업데이트
  Future<void> saveHoldings(List<Map<String, dynamic>> holdings) async {
    try {
      await createTable();
      final db = await _databaseHelper.database;
      
      await db.transaction((txn) async {
        // 기존 데이터 삭제
        await txn.delete('holdings');
        
        // 새 데이터 삽입 (API 필드명 그대로 사용)
        for (final holding in holdings) {
          // API 필드명 그대로 사용 (변환하지 않음)
          final String pdno = (holding['pdno'] ?? '').toString();
          final String prdtName = holding['prdt_name'] ?? '';
          final int hldgQty = _parseInt(holding['hldg_qty']) ?? 0;
          final double pchsAvgPric = _parseDouble(holding['pchs_avg_pric']) ?? 0.0;
          final double prpr = _parseDouble(holding['prpr']) ?? 0.0;
          final double evluAmt = _parseDouble(holding['evlu_amt']) ?? 0.0;
          final double evluPflsAmt = _parseDouble(holding['evlu_pfls_amt']) ?? 0.0;
          final double evluPflsRt = _parseDouble(holding['evlu_pfls_rt']) ?? 0.0;
          final String resolvedMarket = await _resolveMarket(txn, pdno);
          
          if (pdno.isEmpty || (pdno.trim().isEmpty)) {
            // 빈 코드 스킵 (UNIQUE 제약 충돌 방지)
            continue;
          }

          print('📊 [HoldingsRepository] saveHoldings API 필드명 그대로 사용:');
          print('  - pdno: $pdno');
          print('  - prdt_name: $prdtName');
          print('  - hldg_qty: $hldgQty');
          print('  - pchs_avg_pric: $pchsAvgPric');
          print('  - prpr: $prpr');
          print('  - evlu_amt: $evluAmt');
          print('  - evlu_pfls_amt: $evluPflsAmt');
          print('  - evlu_pfls_rt: $evluPflsRt');
          
          await txn.insert('holdings', {
            'pdno': pdno,
            'prdt_name': prdtName,
            'market': resolvedMarket,
            'hldg_qty': hldgQty,
            'pchs_avg_pric': pchsAvgPric,
            'prpr': prpr,
            'evlu_amt': evluAmt,
            'evlu_pfls_amt': evluPflsAmt,
            'evlu_pfls_rt': evluPflsRt,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          });
        }
      });
      
      print('✅ 보유종목 저장 완료: ${holdings.length}개');
    } catch (e) {
      print('❌ 보유종목 저장 실패: $e');
      rethrow;
    }
  }

  /// 보유종목 조회 (getAllHoldings와 동일)
  Future<List<Map<String, dynamic>>> getHoldings() async {
    return await getAllHoldings();
  }

  /// 모든 보유종목 조회
  Future<List<Map<String, dynamic>>> getAllHoldings() async {
    try {
      final db = await _databaseHelper.database;
      
      final List<Map<String, dynamic>> results = await db.query(
        'holdings',
        orderBy: 'updated_at DESC',
      );
      
      // API 필드명 그대로 반환
      final List<Map<String, dynamic>> holdings = results.map((row) {
        return {
          'pdno': row['pdno'],
          'prdt_name': row['prdt_name'],
          'market': row['market'],
          'hldg_qty': row['hldg_qty'],
          'pchs_avg_pric': row['pchs_avg_pric'],
          'prpr': row['prpr'],
          'evlu_amt': row['evlu_amt'],
          'evlu_pfls_amt': row['evlu_pfls_amt'],
          'evlu_pfls_rt': row['evlu_pfls_rt'],
          'updated_at': row['updated_at'],
        };
      }).toList();
      
      print('✅ 보유종목 조회 완료: ${holdings.length}개');
      return holdings;
    } catch (e) {
      print('❌ 보유종목 조회 실패: $e');
      return [];
    }
  }

  /// API 데이터와 로컬 DB 동기화
  Future<void> syncWithApi(List<Map<String, dynamic>> apiPositions) async {
    try {
      await createTable();
      final db = await _databaseHelper.database;
      
      await db.transaction((txn) async {
        // 기존 데이터 삭제
        await txn.delete('holdings');
        
        // API 데이터로 새로 저장 (API 필드명 그대로 사용)
        for (final position in apiPositions) {
          // API 필드명 그대로 사용 (변환하지 않음)
          final String pdno = (position['pdno'] ?? '').toString();
          final String prdtName = position['prdt_name'] ?? '';
          final int hldgQty = _parseInt(position['hldg_qty']) ?? 0;
          final double pchsAvgPric = _parseDouble(position['pchs_avg_pric']) ?? 0.0;
          final double prpr = _parseDouble(position['prpr']) ?? 0.0;
          final double evluAmt = _parseDouble(position['evlu_amt']) ?? 0.0;
          final double evluPflsAmt = _parseDouble(position['evlu_pfls_amt']) ?? 0.0;
          final double evluPflsRt = _parseDouble(position['evlu_pfls_rt']) ?? 0.0;
          final String resolvedMarket = await _resolveMarket(txn, pdno);
          
          print('📊 [HoldingsRepository] syncWithApi API 필드명 그대로 사용:');
          print('  - 원본: ${position.keys.toList()}');
          print('  - pdno: $pdno');
          print('  - prdt_name: $prdtName');
          print('  - hldg_qty: $hldgQty');
          print('  - pchs_avg_pric: $pchsAvgPric');
          print('  - prpr: $prpr');
          print('  - evlu_amt: $evluAmt');
          print('  - evlu_pfls_amt: $evluPflsAmt');
          print('  - evlu_pfls_rt: $evluPflsRt');
          
          await txn.insert('holdings', {
            'pdno': pdno,
            'prdt_name': prdtName,
            'market': resolvedMarket,
            'hldg_qty': hldgQty,
            'pchs_avg_pric': pchsAvgPric,
            'prpr': prpr,
            'evlu_amt': evluAmt,
            'evlu_pfls_amt': evluPflsAmt,
            'evlu_pfls_rt': evluPflsRt,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          });
        }
      });
      
      print('✅ API와 보유종목 동기화 완료: ${apiPositions.length}개');
    } catch (e) {
      print('❌ API와 보유종목 동기화 실패: $e');
    }
  }

  /// 특정 종목 보유 정보 업데이트
  Future<void> updateHolding({
    required String stockCode,
    double? currentPrice, // prpr
    double? profitRate,   // evlu_pfls_rt
    double? currentValue, // evlu_amt
    DateTime? updatedAt,
  }) async {
    try {
      final db = await _databaseHelper.database;
      
      final updateData = <String, dynamic>{};
      if (currentPrice != null) updateData['prpr'] = currentPrice;
      if (profitRate != null) updateData['evlu_pfls_rt'] = profitRate;
      if (currentValue != null) updateData['evlu_amt'] = currentValue;
      updateData['updated_at'] = (updatedAt ?? DateTime.now()).millisecondsSinceEpoch;
      
      await db.update(
        'holdings',
        updateData,
        where: 'pdno = ?',
        whereArgs: [stockCode],
      );
      
      print('✅ 보유종목 업데이트 완료: $stockCode');
    } catch (e) {
      print('❌ 보유종목 업데이트 실패: $e');
    }
  }

  /// 특정 종목 보유 정보 조회
  Future<Map<String, dynamic>?> getHolding(String stockCode) async {
    try {
      final db = await _databaseHelper.database;
      
      final List<Map<String, dynamic>> results = await db.query(
        'holdings',
        where: 'stock_code = ?',
        whereArgs: [stockCode],
        limit: 1,
      );
      
      if (results.isEmpty) return null;
      
      final row = results.first;
      return {
        'stockCode': row['stock_code'],
        'stockName': row['stock_name'],
        'quantity': row['quantity'],
        'avgPrice': row['avg_price'],
        'currentPrice': row['current_price'],
        'profit': row['profit_loss'],
        'profitRate': row['profit_rate'],
        'totalValue': row['total_value'],
        'updatedAt': row['updated_at'],
      };
    } catch (e) {
      print('❌ 특정 종목 보유 정보 조회 실패: $e');
      return null;
    }
  }

  /// 보유종목 개수 조회
  Future<int> getHoldingsCount() async {
    try {
      final db = await _databaseHelper.database;
      
      final result = await db.rawQuery('SELECT COUNT(*) as count FROM holdings');
      return result.first['count'] as int;
    } catch (e) {
      print('❌ 보유종목 개수 조회 실패: $e');
      return 0;
    }
  }

  /// 보유종목 삭제
  Future<void> deleteHoldings() async {
    try {
      await createTable();
      final db = await _databaseHelper.database;
      
      await db.delete('holdings');
      print('✅ 보유종목 삭제 완료');
    } catch (e) {
      print('❌ 보유종목 삭제 실패: $e');
      rethrow;
    }
  }

  /// 특정 종목 보유 정보 삭제
  Future<void> deleteHolding(String stockCode) async {
    try {
      final db = await _databaseHelper.database;
      
      await db.delete(
        'holdings',
        where: 'stock_code = ?',
        whereArgs: [stockCode],
      );
      print('✅ 특정 종목 보유 정보 삭제 완료: $stockCode');
    } catch (e) {
      print('❌ 특정 종목 보유 정보 삭제 실패: $e');
      rethrow;
    }
  }

  /// 오래된 보유종목 데이터 정리
  Future<void> cleanupOldHoldings({int daysToKeep = 7}) async {
    try {
      await createTable();
      final db = await _databaseHelper.database;
      
      final cutoffTime = DateTime.now().subtract(Duration(days: daysToKeep)).millisecondsSinceEpoch;
      
      final deletedCount = await db.delete(
        'holdings',
        where: 'updated_at < ?',
        whereArgs: [cutoffTime],
      );
      
      print('✅ 오래된 보유종목 데이터 정리 완료: $deletedCount개 삭제');
    } catch (e) {
      print('❌ 오래된 보유종목 데이터 정리 실패: $e');
    }
  }

  /// 보유종목 통계 조회
  Future<Map<String, dynamic>> getHoldingsStats() async {
    try {
      final db = await _databaseHelper.database;
      
      final result = await db.rawQuery('''
        SELECT 
          COUNT(*) as total_count,
          SUM(evlu_amt) as total_value,
          SUM(evlu_pfls_amt) as total_profit_loss,
          AVG(evlu_pfls_rt) as avg_profit_rate,
          MAX(updated_at) as last_updated
        FROM holdings
      ''');
      
      final stats = result.first;
      return {
        'totalCount': stats['total_count'] ?? 0,
        'totalValue': stats['total_value'] ?? 0.0,
        'totalProfitLoss': stats['total_profit_loss'] ?? 0.0,
        'avgProfitRate': stats['avg_profit_rate'] ?? 0.0,
        'lastUpdated': stats['last_updated'] ?? 0,
      };
    } catch (e) {
      print('❌ 보유종목 통계 조회 실패: $e');
      return {
        'totalCount': 0,
        'totalValue': 0.0,
        'totalProfitLoss': 0.0,
        'avgProfitRate': 0.0,
        'lastUpdated': 0,
      };
    }
  }

  /// 문자열을 정수로 변환
  int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      return parsed;
    }
    return null;
  }

  /// 문자열을 실수로 변환
  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed;
    }
    return null;
  }
}
