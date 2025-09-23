import 'package:sqflite/sqflite.dart';
import '../database_helper.dart';

class NotificationHistoryRepository {
  static const String _tableName = 'notification_history';

  /// 테이블 생성
  Future<void> createTable() async {
    final db = await DatabaseHelper.instance.database;
    
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        stock_code TEXT NOT NULL,
        stock_name TEXT NOT NULL,
        market TEXT NOT NULL,
        message TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_notif_stock_code ON $_tableName (stock_code)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_notif_timestamp ON $_tableName (timestamp)');

    // 마이그레이션: market 컬럼이 없으면 추가
    try {
      await db.execute("ALTER TABLE $_tableName ADD COLUMN market TEXT NOT NULL DEFAULT 'KOSPI'");
    } catch (_) {
      // 이미 있으면 무시
    }
  }

  /// 알림 히스토리 저장
  Future<void> saveNotification({
    required String type,
    required String stockCode,
    required String stockName,
    required String message,
    String? market,
  }) async {
    final db = await DatabaseHelper.instance.database;
    
    // 시장 정보가 누락되면 종목코드 기반으로 추정
    final inferredMarket = market ?? _inferMarketFromCode(stockCode);

    await db.insert(_tableName, {
      'type': type,
      'stock_code': stockCode,
      'stock_name': stockName,
      'message': message,
      'market': inferredMarket,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 알림 추가 (별칭)
  Future<void> addNotification({
    required String type,
    required String stockCode,
    required String stockName,
    required String message,
    String? market,
  }) async {
    await saveNotification(
      type: type,
      stockCode: stockCode,
      stockName: stockName,
      message: message,
      market: market,
    );
  }

  /// 종목코드로 시장 추정 (간단 휴리스틱)
  String _inferMarketFromCode(String stockCode) {
    final upper = stockCode.toUpperCase();
    if (RegExp(r'^[A-Z]{1,6}$').hasMatch(upper)) {
      return 'NASDAQ';
    }
    if (upper.startsWith('0')) {
      return 'KOSPI';
    }
    return 'KOSDAQ';
  }

  /// 최근 알림 조회
  Future<List<Map<String, dynamic>>> getRecentNotifications({int limit = 20}) async {
    final db = await DatabaseHelper.instance.database;
    
    final result = await db.query(
      _tableName,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    
    return result;
  }

  /// 특정 종목의 알림 조회
  Future<List<Map<String, dynamic>>> getNotificationsByStock(String stockCode, {int limit = 10}) async {
    final db = await DatabaseHelper.instance.database;
    
    final result = await db.query(
      _tableName,
      where: 'stock_code = ?',
      whereArgs: [stockCode],
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    
    return result;
  }

  /// 특정 타입의 알림 조회
  Future<List<Map<String, dynamic>>> getNotificationsByType(String type, {int limit = 10}) async {
    final db = await DatabaseHelper.instance.database;
    
    final result = await db.query(
      _tableName,
      where: 'type = ?',
      whereArgs: [type],
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    
    return result;
  }

  /// 날짜 범위로 알림 조회
  Future<List<Map<String, dynamic>>> getNotificationsByDateRange(DateTime start, DateTime end) async {
    final db = await DatabaseHelper.instance.database;
    
    final startMs = start.millisecondsSinceEpoch;
    final endMs = end.millisecondsSinceEpoch;
    
    final result = await db.query(
      _tableName,
      where: 'timestamp >= ? AND timestamp <= ?',
      whereArgs: [startMs, endMs],
      orderBy: 'timestamp DESC',
    );
    
    return result;
  }

  /// 오래된 알림 삭제 (30일 이상)
  Future<void> deleteOldNotifications() async {
    final db = await DatabaseHelper.instance.database;
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    
    await db.delete(
      _tableName,
      where: 'timestamp < ?',
      whereArgs: [thirtyDaysAgo],
    );
  }

  /// 모든 알림 삭제
  Future<void> deleteAllNotifications() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(_tableName);
  }

  /// 개별 알림 삭제
  Future<bool> deleteNotification(int id) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final result = await db.delete(
        _tableName,
        where: 'id = ?',
        whereArgs: [id],
      );
      return result > 0;
    } catch (e) {
      print('❌ 알림 삭제 실패: $e');
      return false;
    }
  }

  /// 특정 종목의 모든 알림 삭제
  Future<bool> deleteNotificationsByStock(String stockCode) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final result = await db.delete(
        _tableName,
        where: 'stock_code = ?',
        whereArgs: [stockCode],
      );
      return result > 0;
    } catch (e) {
      print('❌ 종목별 알림 삭제 실패: $e');
      return false;
    }
  }

  /// 알림 통계 조회
  Future<Map<String, dynamic>> getNotificationStatistics() async {
    final db = await DatabaseHelper.instance.database;
    
    // 전체 알림 수
    final totalResult = await db.rawQuery('SELECT COUNT(*) as count FROM $_tableName');
    final total = totalResult.first['count'] as int? ?? 0;
    
    // 오늘 알림 수
    final today = DateTime.now().millisecondsSinceEpoch - (24 * 60 * 60 * 1000);
    final todayResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_tableName WHERE timestamp > ?',
      [today]
    );
    final todayCount = todayResult.first['count'] as int? ?? 0;
    
    // 타입별 알림 수
    final typeResult = await db.rawQuery('''
      SELECT type, COUNT(*) as count 
      FROM $_tableName 
      GROUP BY type
    ''');
    
    final typeStats = <String, int>{};
    for (final row in typeResult) {
      typeStats[row['type'] as String] = row['count'] as int;
    }
    
    return {
      'total': total,
      'today': todayCount,
      'byType': typeStats,
    };
  }

  /// 중복 알림 정리 (같은 종목의 같은 타입 알림 중 최신 것만 유지)
  Future<void> cleanupDuplicateNotifications() async {
    final db = await DatabaseHelper.instance.database;
    
    try {
      print('🧹 중복 알림 정리 시작...');
      
      // 모든 알림을 가져와서 종목코드와 타입별로 그룹화
      final allNotifications = await db.query(_tableName);
      final Map<String, List<Map<String, dynamic>>> groupedNotifications = {};
      
      for (final notification in allNotifications) {
        final stockCode = notification['stock_code'] as String;
        final type = notification['type'] as String;
        final key = '$stockCode:$type';
        
        if (!groupedNotifications.containsKey(key)) {
          groupedNotifications[key] = [];
        }
        groupedNotifications[key]!.add(notification);
      }
      
      // 각 그룹에서 중복 제거
      int removedCount = 0;
      for (final entry in groupedNotifications.entries) {
        final notifications = entry.value;
        
        if (notifications.length > 1) {
          // 타임스탬프 기준으로 정렬 (최신이 위로)
          notifications.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));
          
          // 첫 번째(최신) 것만 유지하고 나머지 삭제
          for (int i = 1; i < notifications.length; i++) {
            await db.delete(
              _tableName,
              where: 'id = ?',
              whereArgs: [notifications[i]['id']],
            );
            removedCount++;
          }
        }
      }
      
      print('✅ 중복 알림 정리 완료: $removedCount개 제거됨');
      
    } catch (e) {
      print('❌ 중복 알림 정리 실패: $e');
    }
  }

  /// 특정 종목의 중복 알림 정리
  Future<void> cleanupDuplicateNotificationsForStock(String stockCode) async {
    final db = await DatabaseHelper.instance.database;
    
    try {
      print('🧹 $stockCode 중복 알림 정리 시작...');
      
      // 해당 종목의 모든 알림을 가져와서 타입별로 그룹화
      final stockNotifications = await db.query(
        _tableName,
        where: 'stock_code = ?',
        whereArgs: [stockCode],
      );
      
      final Map<String, List<Map<String, dynamic>>> groupedNotifications = {};
      
      for (final notification in stockNotifications) {
        final type = notification['type'] as String;
        
        if (!groupedNotifications.containsKey(type)) {
          groupedNotifications[type] = [];
        }
        groupedNotifications[type]!.add(notification);
      }
      
      // 각 타입별로 중복 제거
      int removedCount = 0;
      for (final entry in groupedNotifications.entries) {
        final type = entry.key;
        final notifications = entry.value;
        
        if (notifications.length > 1) {
          // 타임스탬프 기준으로 정렬 (최신이 위로)
          notifications.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));
          
          // 첫 번째(최신) 것만 유지하고 나머지 삭제
          for (int i = 1; i < notifications.length; i++) {
            await db.delete(
              _tableName,
              where: 'id = ?',
              whereArgs: [notifications[i]['id']],
            );
            removedCount++;
          }
        }
      }
      
      print('✅ $stockCode 중복 알림 정리 완료: $removedCount개 제거됨');
      
    } catch (e) {
      print('❌ $stockCode 중복 알림 정리 실패: $e');
    }
  }
}
