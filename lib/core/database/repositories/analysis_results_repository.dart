import 'package:sqflite/sqflite.dart';
import '../database_helper.dart';

/// 분석 결과 Repository - 실시간 분석 결과 저장 및 관리
///
/// 📊 주요 기능:
/// - 실시간 분석 결과 저장
/// - 분석 결과 조회 및 검색
/// - 오래된 분석 결과 정리
/// - 통계 정보 제공
class AnalysisResultsRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  /// 분석 결과 저장
  Future<void> insertAnalysisResult(Map<String, dynamic> result) async {
    try {
      final db = await _dbHelper.database;
      final now = DateTime.now().millisecondsSinceEpoch;

      // 기존 분석 결과가 있으면 업데이트, 없으면 삽입
      await db.insert(
        'analysis_results',
        {
          'stock_code': result['stock_code'] as String,
          'stock_name': result['stock_name'] as String,
          'market': result['market'] as String? ?? _inferMarketFromCode(result['stock_code'] as String),
          'analysis_date': result['analysis_date'] as int? ?? now,
          'analysis_time': result['analysis_time'] as int? ?? now,
          'comprehensive_score': (result['comprehensive_score'] as num?)?.toDouble() ?? 0.0,
          'trading_decision': result['trading_decision'] as String? ?? 'HOLD',
          'signal_strength': result['signal_strength'] as String? ?? 'WEAK',
          'signal': result['signal'] as String? ?? result['trading_decision'] as String? ?? 'HOLD',
          'confidence': (result['confidence'] as num?)?.toDouble() ?? (result['confidence_score'] as num?)?.toDouble() ?? 0.0,
          'confidence_score': (result['confidence_score'] as num?)?.toDouble() ?? 0.0,
          'target_price': (result['target_price'] as num?)?.toDouble() ?? 0.0,
          'current_price': (result['current_price'] as num?)?.toDouble() ?? 0.0,
          'prev_close': (result['prev_close'] as num?)?.toDouble() ?? 0.0,
          'change_rate': (result['change_rate'] as num?)?.toDouble() ?? 0.0,
          // 'analysis_details': _serializeAnalysisDetails(result['analysis_details']), // 컬럼이 없어서 임시 주석 처리
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      print('✅ 분석 결과 저장 완료: ${result['stock_code']}');
    } catch (e) {
      print('❌ 분석 결과 저장 실패: $e');
      rethrow;
    }
  }

  /// 모든 분석 결과 조회
  Future<List<Map<String, dynamic>>> getAnalysisResults() async {
    try {
      final db = await _dbHelper.database;
      final results = await db.query(
        'analysis_results',
        orderBy: 'analysis_time DESC',
      );

      return results.map((result) => {
        'stock_code': result['stock_code'] as String,
        'stock_name': result['stock_name'] as String,
        'market': result['market'] as String? ?? _inferMarketFromCode(result['stock_code'] as String),
        'analysis_time': result['analysis_time'] as int,
        'comprehensive_score': (result['comprehensive_score'] as num?)?.toDouble() ?? 0.0,
        'trading_decision': result['trading_decision'] as String,
        'signal_strength': result['signal_strength'] as String,
        'confidence': (result['confidence'] as num?)?.toDouble() ?? 0.0,
        'confidence_score': (result['confidence_score'] as num?)?.toDouble() ?? 0.0,
        'target_price': (result['target_price'] as num?)?.toDouble() ?? 0.0,
        'current_price': (result['current_price'] as num?)?.toDouble() ?? 0.0,
        'prev_close': (result['prev_close'] as num?)?.toDouble() ?? 0.0,
        'change_rate': (result['change_rate'] as num?)?.toDouble() ?? 0.0,
        // 'analysis_details': _deserializeAnalysisDetails(result['analysis_details'] as String?), // 컬럼이 없어서 임시 주석 처리
        'created_at': result['created_at'] as int,
        'updated_at': (result['updated_at'] as int?) ?? (result['created_at'] as int),
      }).toList();
    } catch (e) {
      print('❌ 모든 분석 결과 조회 실패: $e');
      return [];
    }
  }

  /// 최신 분석 결과 조회
  Future<Map<String, dynamic>?> getLatestAnalysisResult(String stockCode) async {
    try {
      final db = await _dbHelper.database;
      final results = await db.query(
        'analysis_results',
        where: 'stock_code = ?',
        whereArgs: [stockCode],
        orderBy: 'analysis_time DESC',
        limit: 1,
      );

      if (results.isEmpty) {
        return null;
      }

      final result = results.first;
      return {
        'stock_code': result['stock_code'] as String,
        'stock_name': result['stock_name'] as String,
        'market': result['market'] as String? ?? _inferMarketFromCode(result['stock_code'] as String),
        'analysis_time': result['analysis_time'] as int,
        'comprehensive_score': (result['comprehensive_score'] as num?)?.toDouble() ?? 0.0,
        'trading_decision': result['trading_decision'] as String,
        'signal_strength': result['signal_strength'] as String,
        'confidence': (result['confidence'] as num?)?.toDouble() ?? 0.0,
        'confidence_score': (result['confidence_score'] as num?)?.toDouble() ?? 0.0,
        'target_price': (result['target_price'] as num?)?.toDouble() ?? 0.0,
        'current_price': (result['current_price'] as num?)?.toDouble() ?? 0.0,
        'prev_close': (result['prev_close'] as num?)?.toDouble() ?? 0.0,
        'change_rate': (result['change_rate'] as num?)?.toDouble() ?? 0.0,
        // 'analysis_details': _deserializeAnalysisDetails(result['analysis_details'] as String?), // 컬럼이 없어서 임시 주석 처리
        'created_at': result['created_at'] as int,
        'updated_at': (result['updated_at'] as int?) ?? (result['created_at'] as int),
      };
    } catch (e) {
      print('❌ 최신 분석 결과 조회 실패: $e');
      return null;
    }
  }

  /// 특정 기간 분석 결과 조회
  Future<List<Map<String, dynamic>>> getAnalysisResultsByPeriod({
    required String stockCode,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final db = await _dbHelper.database;
      final startTime = startDate.millisecondsSinceEpoch;
      final endTime = endDate.millisecondsSinceEpoch;

      final results = await db.query(
        'analysis_results',
        where: 'stock_code = ? AND analysis_time BETWEEN ? AND ?',
        whereArgs: [stockCode, startTime, endTime],
        orderBy: 'analysis_time DESC',
      );

      return results.map((result) => {
        'stock_code': result['stock_code'] as String,
        'stock_name': result['stock_name'] as String,
        'market': result['market'] as String? ?? _inferMarketFromCode(result['stock_code'] as String),
        'analysis_time': result['analysis_time'] as int,
        'comprehensive_score': (result['comprehensive_score'] as num?)?.toDouble() ?? 0.0,
        'trading_decision': result['trading_decision'] as String,
        'signal_strength': result['signal_strength'] as String,
        'confidence': (result['confidence'] as num?)?.toDouble() ?? 0.0,
        'confidence_score': (result['confidence_score'] as num?)?.toDouble() ?? 0.0,
        'target_price': (result['target_price'] as num?)?.toDouble() ?? 0.0,
        'current_price': (result['current_price'] as num?)?.toDouble() ?? 0.0,
        'prev_close': (result['prev_close'] as num?)?.toDouble() ?? 0.0,
        'change_rate': (result['change_rate'] as num?)?.toDouble() ?? 0.0,
        // 'analysis_details': _deserializeAnalysisDetails(result['analysis_details'] as String?), // 컬럼이 없어서 임시 주석 처리
        'created_at': result['created_at'] as int,
        'updated_at': (result['updated_at'] as int?) ?? (result['created_at'] as int),
      }).toList();
    } catch (e) {
      print('❌ 기간별 분석 결과 조회 실패: $e');
      return [];
    }
  }

  /// 매수 신호 분석 결과 조회
  Future<List<Map<String, dynamic>>> getBuySignals({
    double minConfidence = 0.7,
    int limit = 50,
  }) async {
    try {
      final db = await _dbHelper.database;
      final results = await db.query(
        'analysis_results',
        where: 'trading_decision = ? AND confidence_score >= ?',
        whereArgs: ['BUY', minConfidence],
        orderBy: 'confidence_score DESC',
        limit: limit,
      );

      return results.map((result) => {
        'stock_code': result['stock_code'] as String,
        'stock_name': result['stock_name'] as String,
        'analysis_time': result['analysis_time'] as int,
        'comprehensive_score': (result['comprehensive_score'] as num?)?.toDouble() ?? 0.0,
        'trading_decision': result['trading_decision'] as String,
        'signal_strength': result['signal_strength'] as String,
        'confidence': (result['confidence'] as num?)?.toDouble() ?? 0.0,
        'confidence_score': (result['confidence_score'] as num?)?.toDouble() ?? 0.0,
        'target_price': (result['target_price'] as num?)?.toDouble() ?? 0.0,
        'current_price': (result['current_price'] as num?)?.toDouble() ?? 0.0,
        'prev_close': (result['prev_close'] as num?)?.toDouble() ?? 0.0,
        'change_rate': (result['change_rate'] as num?)?.toDouble() ?? 0.0,
        // 'analysis_details': _deserializeAnalysisDetails(result['analysis_details'] as String?), // 컬럼이 없어서 임시 주석 처리
        'created_at': result['created_at'] as int,
        'updated_at': (result['updated_at'] as int?) ?? (result['created_at'] as int),
      }).toList();
    } catch (e) {
      print('❌ 매수 신호 분석 결과 조회 실패: $e');
      return [];
    }
  }

  /// 매도 신호 분석 결과 조회
  Future<List<Map<String, dynamic>>> getSellSignals({
    double minConfidence = 0.7,
    int limit = 50,
  }) async {
    try {
      final db = await _dbHelper.database;
      final results = await db.query(
        'analysis_results',
        where: 'trading_decision = ? AND confidence_score >= ?',
        whereArgs: ['SELL', minConfidence],
        orderBy: 'confidence_score DESC',
        limit: limit,
      );

      return results.map((result) => {
        'stock_code': result['stock_code'] as String,
        'stock_name': result['stock_name'] as String,
        'analysis_time': result['analysis_time'] as int,
        'comprehensive_score': (result['comprehensive_score'] as num?)?.toDouble() ?? 0.0,
        'trading_decision': result['trading_decision'] as String,
        'signal_strength': result['signal_strength'] as String,
        'confidence': (result['confidence'] as num?)?.toDouble() ?? 0.0,
        'confidence_score': (result['confidence_score'] as num?)?.toDouble() ?? 0.0,
        'target_price': (result['target_price'] as num?)?.toDouble() ?? 0.0,
        'current_price': (result['current_price'] as num?)?.toDouble() ?? 0.0,
        'prev_close': (result['prev_close'] as num?)?.toDouble() ?? 0.0,
        'change_rate': (result['change_rate'] as num?)?.toDouble() ?? 0.0,
        // 'analysis_details': _deserializeAnalysisDetails(result['analysis_details'] as String?), // 컬럼이 없어서 임시 주석 처리
        'created_at': result['created_at'] as int,
        'updated_at': (result['updated_at'] as int?) ?? (result['created_at'] as int),
      }).toList();
    } catch (e) {
      print('❌ 매도 신호 분석 결과 조회 실패: $e');
      return [];
    }
  }

  /// 모든 분석 결과 조회
  Future<List<Map<String, dynamic>>> getAllAnalysisResults({
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      final db = await _dbHelper.database;
      final results = await db.query(
        'analysis_results',
        orderBy: 'analysis_time DESC',
        limit: limit,
        offset: offset,
      );

      return results.map((result) => {
        'stock_code': result['stock_code'] as String,
        'stock_name': result['stock_name'] as String,
        'market': result['market'] as String? ?? _inferMarketFromCode(result['stock_code'] as String),
        'analysis_time': result['analysis_time'] as int,
        'comprehensive_score': (result['comprehensive_score'] as num?)?.toDouble() ?? 0.0,
        'trading_decision': result['trading_decision'] as String,
        'signal_strength': result['signal_strength'] as String,
        'confidence': (result['confidence'] as num?)?.toDouble() ?? 0.0,
        'confidence_score': (result['confidence_score'] as num?)?.toDouble() ?? 0.0,
        'target_price': (result['target_price'] as num?)?.toDouble() ?? 0.0,
        'current_price': (result['current_price'] as num?)?.toDouble() ?? 0.0,
        'prev_close': (result['prev_close'] as num?)?.toDouble() ?? 0.0,
        'change_rate': (result['change_rate'] as num?)?.toDouble() ?? 0.0,
        // 'analysis_details': _deserializeAnalysisDetails(result['analysis_details'] as String?), // 컬럼이 없어서 임시 주석 처리
        'created_at': result['created_at'] as int,
        'updated_at': (result['updated_at'] as int?) ?? (result['created_at'] as int),
      }).toList();
    } catch (e) {
      print('❌ 모든 분석 결과 조회 실패: $e');
      return [];
    }
  }

  /// 특정 종목 분석 결과 삭제
  Future<void> deleteAnalysisResultsByStock(String stockCode) async {
    try {
      final db = await _dbHelper.database;
      final deletedCount = await db.delete(
        'analysis_results',
        where: 'stock_code = ?',
        whereArgs: [stockCode],
      );

      print('✅ $stockCode 분석 결과 삭제 완료: $deletedCount개');
    } catch (e) {
      print('❌ 분석 결과 삭제 실패: $e');
      rethrow;
    }
  }

  /// 오래된 분석 결과 정리 (7일 초과)
  Future<Map<String, dynamic>> cleanupOldAnalysisResults({int keepDays = 7}) async {
    try {
      final db = await _dbHelper.database;
      final cutoffTime = DateTime.now().subtract(Duration(days: keepDays)).millisecondsSinceEpoch;

      final deletedCount = await db.delete(
        'analysis_results',
        where: 'analysis_time < ?',
        whereArgs: [cutoffTime],
      );

      print('✅ 오래된 분석 결과 정리 완료: $deletedCount개 삭제');
      return {
        'deleted_count': deletedCount,
        'cutoff_time': cutoffTime,
        'keep_days': keepDays,
      };
    } catch (e) {
      print('❌ 오래된 분석 결과 정리 실패: $e');
      rethrow;
    }
  }

  /// 분석 결과 통계 조회
  Future<Map<String, dynamic>> getAnalysisStatistics() async {
    try {
      final db = await _dbHelper.database;
      
      // 전체 분석 결과 수
      final totalResult = await db.rawQuery('SELECT COUNT(*) as count FROM analysis_results');
      final totalCount = totalResult.first['count'] as int? ?? 0;

      // 매수 신호 수
      final buyResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM analysis_results WHERE trading_decision = ?',
        ['BUY'],
      );
      final buyCount = buyResult.first['count'] as int? ?? 0;

      // 매도 신호 수
      final sellResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM analysis_results WHERE trading_decision = ?',
        ['SELL'],
      );
      final sellCount = sellResult.first['count'] as int? ?? 0;

      // 보유 신호 수
      final holdResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM analysis_results WHERE trading_decision = ?',
        ['HOLD'],
      );
      final holdCount = holdResult.first['count'] as int? ?? 0;

      // 평균 신뢰도
      final avgConfidenceResult = await db.rawQuery(
        'SELECT AVG(confidence_score) as avg_confidence FROM analysis_results',
      );
      final avgConfidence = avgConfidenceResult.first['avg_confidence'] as double? ?? 0.0;

      // 최신 분석 시간
      final latestResult = await db.rawQuery('SELECT MAX(analysis_time) as latest FROM analysis_results');
      final latestAnalysis = latestResult.first['latest'] as int? ?? 0;

      return {
        'total_count': totalCount,
        'buy_count': buyCount,
        'sell_count': sellCount,
        'hold_count': holdCount,
        'avg_confidence': avgConfidence,
        'latest_analysis_time': latestAnalysis,
        'latest_analysis_date': latestAnalysis > 0 ? DateTime.fromMillisecondsSinceEpoch(latestAnalysis) : null,
      };
    } catch (e) {
      print('❌ 분석 결과 통계 조회 실패: $e');
      return {};
    }
  }

  /// 분석 상세 정보 직렬화 (임시 주석 처리)
  String _serializeAnalysisDetails(Map<String, dynamic>? details) {
    // return details != null ? jsonEncode(details) : '';
    return ''; // 임시로 빈 문자열 반환
  }

  /// 종목코드로 시장 추정
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

  /// 분석 상세 정보 역직렬화 (임시 주석 처리)
  Map<String, dynamic>? _deserializeAnalysisDetails(String? details) {
    // if (details == null || details.isEmpty) return null;
    // try {
    //   return jsonDecode(details) as Map<String, dynamic>;
    // } catch (e) {
    //   print('❌ 분석 상세 정보 역직렬화 실패: $e');
    //   return null;
    // }
    return null; // 임시로 null 반환
  }
}
