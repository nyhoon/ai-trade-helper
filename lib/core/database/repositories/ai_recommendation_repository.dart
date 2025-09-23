import 'package:sqflite/sqflite.dart';
import '../database_helper.dart';

/// AI 추천 종목 Repository - 10분마다 업데이트되는 AI 추천 관리
class AiRecommendationRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  /// AI 추천 종목 삽입 또는 업데이트 (별칭)
  Future<void> insertOrUpdateRecommendation(Map<String, dynamic> recommendation) async {
    await insertOrUpdateAiRecommendation(
      stockCode: recommendation['stock_code'] as String,
      stockName: recommendation['stock_name'] as String,
      market: recommendation['market'] as String,
      currentPrice: recommendation['current_price'] as double,
      prevClose: recommendation['prev_close'] as double,
      changeRate: recommendation['change_rate'] as double,
      signalStrength: recommendation['signal_strength'] as double,
      confidenceScore: recommendation['confidence_score'] as double,
      targetPrice: recommendation['target_price'] as double?,
      recommendationReason: recommendation['recommendation_reason'] as String?,
    );
  }

  /// AI 추천 종목 삽입 또는 업데이트
  Future<void> insertOrUpdateAiRecommendation({
    required String stockCode,
    required String stockName,
    required String market,
    required double currentPrice,
    required double prevClose,
    required double changeRate,
    required double signalStrength,
    required double confidenceScore,
    double? targetPrice,
    String? recommendationReason,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.insert(
      'ai_recommendations',
      {
        'stock_code': stockCode,
        'stock_name': stockName,
        'market': market,
        'current_price': currentPrice,
        'prev_close': prevClose,
        'change_rate': changeRate,
        'signal_strength': signalStrength,
        'confidence_score': confidenceScore,
        'target_price': targetPrice,
        'recommendation_reason': recommendationReason,
        'is_recommended': 1,
        'is_notified': 0,
        'recommended_at': now,
        'created_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 여러 AI 추천 종목 일괄 삽입
  Future<void> insertMultipleAiRecommendations(List<Map<String, dynamic>> recommendationList) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      for (final data in recommendationList) {
        await txn.insert(
          'ai_recommendations',
          {
            'stock_code': data['stock_code'],
            'stock_name': data['stock_name'],
            'market': data['market'],
            'current_price': data['current_price'],
            'prev_close': data['prev_close'],
            'change_rate': data['change_rate'],
            'signal_strength': data['signal_strength'],
            'confidence_score': data['confidence_score'],
            'target_price': data['target_price'],
            'recommendation_reason': data['recommendation_reason'],
            'is_recommended': 1,
            'is_notified': 0,
            'recommended_at': now,
            'created_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// AI 추천 종목 조회 (전체)
  Future<List<Map<String, dynamic>>> getAllAiRecommendations() async {
    final db = await _dbHelper.database;

    final result = await db.query(
      'ai_recommendations',
      where: 'is_recommended = 1',
      orderBy: 'confidence_score DESC, signal_strength DESC',
    );

    return result;
  }

  /// 특정 종목의 AI 추천 조회
  Future<Map<String, dynamic>?> getAiRecommendation(String stockCode) async {
    final db = await _dbHelper.database;

    final result = await db.query(
      'ai_recommendations',
      where: 'stock_code = ? AND is_recommended = 1',
      whereArgs: [stockCode],
      limit: 1,
    );

    if (result.isNotEmpty) {
      return result.first;
    }

    return null;
  }

  /// 특정 시장의 AI 추천 종목 조회
  Future<List<Map<String, dynamic>>> getAiRecommendationsByMarket(String market) async {
    final db = await _dbHelper.database;

    final result = await db.query(
      'ai_recommendations',
      where: 'market = ? AND is_recommended = 1',
      whereArgs: [market],
      orderBy: 'confidence_score DESC, signal_strength DESC',
    );

    return result;
  }

  /// 신뢰도 기준 AI 추천 종목 조회
  Future<List<Map<String, dynamic>>> getAiRecommendationsByConfidence({
    double minConfidence = 0.7,
    int limit = 50,
  }) async {
    final db = await _dbHelper.database;

    final result = await db.query(
      'ai_recommendations',
      where: 'confidence_score >= ? AND is_recommended = 1',
      whereArgs: [minConfidence],
      orderBy: 'confidence_score DESC, signal_strength DESC',
      limit: limit,
    );

    return result;
  }

  /// 신호 강도 기준 AI 추천 종목 조회
  Future<List<Map<String, dynamic>>> getAiRecommendationsBySignalStrength({
    double minSignalStrength = 0.6,
    int limit = 50,
  }) async {
    final db = await _dbHelper.database;

    final result = await db.query(
      'ai_recommendations',
      where: 'signal_strength >= ? AND is_recommended = 1',
      whereArgs: [minSignalStrength],
      orderBy: 'signal_strength DESC, confidence_score DESC',
      limit: limit,
    );

    return result;
  }

  /// 미알림 AI 추천 종목 조회 (새로운 추천)
  Future<List<Map<String, dynamic>>> getUnnotifiedAiRecommendations() async {
    final db = await _dbHelper.database;

    final result = await db.query(
      'ai_recommendations',
      where: 'is_recommended = 1 AND is_notified = 0',
      orderBy: 'confidence_score DESC, signal_strength DESC',
    );

    return result;
  }

  /// 관심종목에 없는 AI 추천 종목 조회
  Future<List<Map<String, dynamic>>> getNewAiRecommendations() async {
    final db = await _dbHelper.database;

    final result = await db.rawQuery('''
      SELECT ar.* FROM ai_recommendations ar
      LEFT JOIN watchlist w ON ar.stock_code = w.stock_code AND w.is_active = 1
      WHERE ar.is_recommended = 1 AND w.stock_code IS NULL
      ORDER BY ar.confidence_score DESC, ar.signal_strength DESC
    ''');

    return result;
  }

  /// AI 추천 종목 알림 상태 업데이트
  Future<void> markAiRecommendationAsNotified(String stockCode) async {
    final db = await _dbHelper.database;

    await db.update(
      'ai_recommendations',
      {'is_notified': 1},
      where: 'stock_code = ?',
      whereArgs: [stockCode],
    );
  }

  /// 여러 AI 추천 종목 알림 상태 업데이트
  Future<void> markMultipleAiRecommendationsAsNotified(List<String> stockCodes) async {
    final db = await _dbHelper.database;

    if (stockCodes.isEmpty) return;

    final placeholders = List.filled(stockCodes.length, '?').join(',');
    await db.rawUpdate('''
      UPDATE ai_recommendations 
      SET is_notified = 1 
      WHERE stock_code IN ($placeholders)
    ''', stockCodes);
  }

  /// AI 추천 종목 비활성화
  Future<void> deactivateAiRecommendation(String stockCode) async {
    final db = await _dbHelper.database;

    await db.update(
      'ai_recommendations',
      {'is_recommended': 0},
      where: 'stock_code = ?',
      whereArgs: [stockCode],
    );
  }

  /// AI 추천 종목 삭제
  Future<int> deleteAiRecommendation(String stockCode) async {
    final db = await _dbHelper.database;

    return await db.delete(
      'ai_recommendations',
      where: 'stock_code = ?',
      whereArgs: [stockCode],
    );
  }

  /// 오래된 AI 추천 종목 정리 (7일 이상)
  Future<int> cleanupOldAiRecommendations() async {
    final db = await _dbHelper.database;
    final sevenDaysAgo = DateTime.now().millisecondsSinceEpoch - (7 * 24 * 60 * 60 * 1000);

    return await db.delete(
      'ai_recommendations',
      where: 'recommended_at < ?',
      whereArgs: [sevenDaysAgo],
    );
  }

  /// 오래된 AI 추천 종목 정리 (7일 이상) - Map 반환
  Future<Map<String, dynamic>> cleanupOldRecommendations() async {
    final db = await _dbHelper.database;
    
    try {
      final sevenDaysAgo = DateTime.now().millisecondsSinceEpoch - (7 * 24 * 60 * 60 * 1000);
      
      final deletedCount = await db.delete(
        'ai_recommendations',
        where: 'recommended_at < ?',
        whereArgs: [sevenDaysAgo],
      );
      
      return {
        'deleted_records': deletedCount,
        'cutoff_timestamp': sevenDaysAgo,
      };
    } catch (e) {
      print('❌ 오래된 AI 추천 데이터 정리 실패: $e');
      return {
        'deleted_records': 0,
        'cutoff_timestamp': 0,
        'error': e.toString(),
      };
    }
  }

  /// AI 추천 종목 통계 조회
  Future<Map<String, dynamic>> getAiRecommendationStats() async {
    final db = await _dbHelper.database;

    final totalCount = await db.rawQuery('SELECT COUNT(*) as count FROM ai_recommendations WHERE is_recommended = 1');
    final marketStats = await db.rawQuery('''
      SELECT market, COUNT(*) as count FROM ai_recommendations 
      WHERE is_recommended = 1 GROUP BY market
    ''');
    final confidenceStats = await db.rawQuery('''
      SELECT 
        AVG(confidence_score) as avg_confidence,
        MIN(confidence_score) as min_confidence,
        MAX(confidence_score) as max_confidence
      FROM ai_recommendations WHERE is_recommended = 1
    ''');
    final signalStats = await db.rawQuery('''
      SELECT 
        AVG(signal_strength) as avg_signal,
        MIN(signal_strength) as min_signal,
        MAX(signal_strength) as max_signal
      FROM ai_recommendations WHERE is_recommended = 1
    ''');

    return {
      'total_recommendations': totalCount.first['count'] as int,
      'market_stats': marketStats,
      'confidence_stats': confidenceStats.first,
      'signal_stats': signalStats.first,
    };
  }

  /// 특정 종목의 AI 추천 통계
  Future<Map<String, dynamic>> getStockAiRecommendationStats(String stockCode) async {
    final db = await _dbHelper.database;

    final result = await db.query(
      'ai_recommendations',
      where: 'stock_code = ? AND is_recommended = 1',
      whereArgs: [stockCode],
      limit: 1,
    );

    if (result.isEmpty) {
      return {
        'stock_code': stockCode,
        'has_recommendation': false,
      };
    }

    final data = result.first;
    return {
      'stock_code': stockCode,
      'has_recommendation': true,
      'signal_strength': data['signal_strength'],
      'confidence_score': data['confidence_score'],
      'target_price': data['target_price'],
      'recommendation_reason': data['recommendation_reason'],
      'is_notified': data['is_notified'] == 1,
      'recommended_at': data['recommended_at'],
    };
  }

  /// AI 추천 종목 백업 (JSON 형식)
  Future<Map<String, dynamic>> exportAiRecommendations({
    List<String>? stockCodes,
    String? market,
  }) async {
    final db = await _dbHelper.database;

    String whereClause = 'is_recommended = 1';
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
      'ai_recommendations',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'confidence_score DESC, signal_strength DESC',
    );

    return {
      'export_date': DateTime.now().toIso8601String(),
      'data_count': result.length,
      'ai_recommendations': result,
    };
  }

  /// AI 추천 종목 복원 (JSON 형식)
  Future<void> importAiRecommendations(Map<String, dynamic> exportData) async {
    final recommendationList = exportData['ai_recommendations'] as List<dynamic>;
    
    if (recommendationList.isEmpty) {
      return;
    }

    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      for (final data in recommendationList) {
        final recommendation = data as Map<String, dynamic>;
        await txn.insert(
          'ai_recommendations',
          {
            'stock_code': recommendation['stock_code'],
            'stock_name': recommendation['stock_name'],
            'market': recommendation['market'],
            'current_price': recommendation['current_price'],
            'prev_close': recommendation['prev_close'],
            'change_rate': recommendation['change_rate'],
            'signal_strength': recommendation['signal_strength'],
            'confidence_score': recommendation['confidence_score'],
            'target_price': recommendation['target_price'],
            'recommendation_reason': recommendation['recommendation_reason'],
            'is_recommended': 1,
            'is_notified': 0,
            'recommended_at': now,
            'created_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// AI 추천 종목 검증 (유효성 검사)
  Future<List<String>> validateAiRecommendations() async {
    final db = await _dbHelper.database;
    final errors = <String>[];

    // 1. 필수 필드 검증
    final invalidData = await db.rawQuery('''
      SELECT stock_code FROM ai_recommendations 
      WHERE stock_code IS NULL OR stock_name IS NULL OR market IS NULL
    ''');

    for (final row in invalidData) {
      errors.add('${row['stock_code']}: 필수 필드 누락');
    }

    // 2. 신뢰도 범위 검증 (0.0 ~ 1.0)
    final invalidConfidence = await db.rawQuery('''
      SELECT stock_code FROM ai_recommendations 
      WHERE confidence_score < 0 OR confidence_score > 1
    ''');

    for (final row in invalidConfidence) {
      errors.add('${row['stock_code']}: 신뢰도 범위 오류 (0.0~1.0)');
    }

    // 3. 신호 강도 범위 검증 (0.0 ~ 1.0)
    final invalidSignal = await db.rawQuery('''
      SELECT stock_code FROM ai_recommendations 
      WHERE signal_strength < 0 OR signal_strength > 1
    ''');

    for (final row in invalidSignal) {
      errors.add('${row['stock_code']}: 신호 강도 범위 오류 (0.0~1.0)');
    }

    // 4. 가격 유효성 검증
    final invalidPrice = await db.rawQuery('''
      SELECT stock_code FROM ai_recommendations 
      WHERE current_price < 0 OR prev_close < 0
    ''');

    for (final row in invalidPrice) {
      errors.add('${row['stock_code']}: 음수 가격 발견');
    }

    return errors;
  }

  /// AI 추천 종목 리셋 (모든 추천 비활성화)
  Future<void> resetAllAiRecommendations() async {
    final db = await _dbHelper.database;

    await db.update(
      'ai_recommendations',
      {'is_recommended': 0},
      where: 'is_recommended = 1',
    );
  }

  /// AI 추천 종목 알림 리셋 (모든 알림 상태 초기화)
  Future<void> resetAllNotifications() async {
    final db = await _dbHelper.database;

    await db.update(
      'ai_recommendations',
      {'is_notified': 0},
      where: 'is_notified = 1',
    );
  }

  /// 새로운 추천 종목 조회 (관심종목에 없는 종목)
  Future<List<Map<String, dynamic>>> getNewRecommendations() async {
    final db = await _dbHelper.database;
    
    try {
      // 관심종목에 없는 새로운 추천 종목 조회
      final result = await db.rawQuery('''
        SELECT ar.* FROM ai_recommendations ar
        LEFT JOIN watchlist w ON ar.stock_code = w.stock_code
        WHERE ar.is_recommended = 1 
        AND w.stock_code IS NULL
        ORDER BY ar.confidence_score DESC, ar.recommended_at DESC
      ''');
      
      return result;
    } catch (e) {
      print('❌ 새로운 추천 종목 조회 실패: $e');
      return [];
    }
  }

  /// 통계 정보 조회
  Future<Map<String, dynamic>> getStats() async {
    final db = await _dbHelper.database;
    
    try {
      // 전체 레코드 수
      final totalCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM ai_recommendations')
      ) ?? 0;
      
      // 활성 추천 수
      final activeCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM ai_recommendations WHERE is_recommended = 1')
      ) ?? 0;
      
      // 알림 발송 수
      final notifiedCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM ai_recommendations WHERE is_notified = 1')
      ) ?? 0;
      
      // 평균 신뢰도
      final avgConfidenceResult = await db.rawQuery('SELECT AVG(confidence_score) FROM ai_recommendations WHERE is_recommended = 1');
      final avgConfidence = avgConfidenceResult.isNotEmpty ? avgConfidenceResult.first['AVG(confidence_score)'] as double? ?? 0.0 : 0.0;
      
      // 평균 신호 강도
      final avgSignalStrengthResult = await db.rawQuery('SELECT AVG(signal_strength) FROM ai_recommendations WHERE is_recommended = 1');
      final avgSignalStrength = avgSignalStrengthResult.isNotEmpty ? avgSignalStrengthResult.first['AVG(signal_strength)'] as double? ?? 0.0 : 0.0;
      
      // 최신 추천 시간
      final latestRecommendation = Sqflite.firstIntValue(
        await db.rawQuery('SELECT MAX(recommended_at) FROM ai_recommendations')
      ) ?? 0;
      
      return {
        'total_recommendations': totalCount,
        'active_recommendations': activeCount,
        'notified_recommendations': notifiedCount,
        'avg_confidence_score': avgConfidence.toStringAsFixed(3),
        'avg_signal_strength': avgSignalStrength.toStringAsFixed(3),
        'latest_recommendation_time': latestRecommendation,
        'success_rate': totalCount > 0 ? (activeCount / totalCount * 100).toStringAsFixed(1) : '0.0',
      };
    } catch (e) {
      print('❌ AI 추천 통계 조회 실패: $e');
      return {
        'total_recommendations': 0,
        'active_recommendations': 0,
        'notified_recommendations': 0,
        'avg_confidence_score': '0.000',
        'avg_signal_strength': '0.000',
        'latest_recommendation_time': 0,
        'success_rate': '0.0',
        'error': e.toString(),
      };
    }
  }
}
