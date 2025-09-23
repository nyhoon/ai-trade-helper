import 'package:sqflite/sqflite.dart';
import '../database_helper.dart';

/// 분석 결과 Repository
class AnalysisRepository {
  final DatabaseHelper _databaseHelper = DatabaseHelper();

  /// 테이블 생성
  Future<void> createTable() async {
    final db = await _databaseHelper.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS analysis_results (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        stock_code TEXT NOT NULL,
        stock_name TEXT NOT NULL,
        current_price REAL NOT NULL,
        prev_close REAL NOT NULL,
        rsi REAL,
        macd REAL,
        macd_signal REAL,
        macd_histogram REAL,
        sma20 REAL,
        sma50 REAL,
        bollinger_upper REAL,
        bollinger_middle REAL,
        bollinger_lower REAL,
        stochastic_k REAL,
        stochastic_d REAL,
        vwap REAL,
        vix REAL,
        support_resistance_support REAL,
        support_resistance_resistance REAL,
        volume_ratio REAL,
        volume_threshold REAL,
        volume_time_slot TEXT,
        volume_market TEXT,
        momentum REAL,
        price_drop REAL,
        volume_spike REAL,
        vix_spike REAL,
        volume_price_divergence REAL,
        bid_ask_imbalance REAL,
        smart_money_flow REAL,
        signal TEXT NOT NULL,
        confidence REAL NOT NULL,
        target_price REAL,
        reason TEXT,
        investment_style TEXT,
        met_conditions INTEGER,
        total_conditions INTEGER,
        analysis_date INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    
    // 인덱스 생성
    await db.execute('CREATE INDEX IF NOT EXISTS idx_analysis_stock_code ON analysis_results (stock_code)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_analysis_date ON analysis_results (analysis_date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_analysis_signal ON analysis_results (signal)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_analysis_style ON analysis_results (investment_style)');
    
    print('✅ 분석 결과 테이블 생성 완료');
  }

  /// 분석 결과 저장
  Future<void> saveAnalysisResult(Map<String, dynamic> analysis) async {
    try {
      final db = await _databaseHelper.database;
      
      // Map<dynamic, dynamic>을 Map<String, dynamic>으로 변환
      final indicatorsRaw = analysis['indicators'];
      final indicators = indicatorsRaw is Map 
          ? Map<String, dynamic>.from(indicatorsRaw)
          : <String, dynamic>{};
      
      final signals = analysis['signals'] as List<dynamic>? ?? [];
      
      // 필수 컬럼만 포함하여 저장 (스키마 오류 방지)
      final insertData = {
        'stock_code': analysis['stockCode'] ?? '',
        'stock_name': analysis['stockName'] ?? '',
        'current_price': analysis['currentPrice'] ?? 0.0,
        'prev_close': analysis['prevClose'] ?? 0.0,
        'rsi': indicators['rsi'],
        'macd': indicators['macd'],
        'macd_signal': indicators['macd_signal'],
        'macd_histogram': indicators['macd_histogram'],
        'sma20': indicators['sma20'],
        'sma50': indicators['sma50'],
        'bollinger_upper': indicators['bollinger_upper'],
        'bollinger_middle': indicators['bollinger_middle'],
        'bollinger_lower': indicators['bollinger_lower'],
        'stochastic_k': indicators['stochastic_k'],
        'stochastic_d': indicators['stochastic_d'],
        'vwap': indicators['vwap'],
        'vix': indicators['vix'],
        'support_resistance_support': indicators['support_resistance_support'],
        'support_resistance_resistance': indicators['support_resistance_resistance'],
        'volume_ratio': indicators['volume_ratio'],
        'momentum': indicators['momentum'],
        'price_drop': indicators['priceDrop'],
        'volume_spike': indicators['volumeSpike'],
        'vix_spike': indicators['vixSpike'],
        'volume_price_divergence': indicators['volumePriceDivergence'],
        'bid_ask_imbalance': indicators['bidAskImbalance'],
        'smart_money_flow': indicators['smartMoneyFlow'],
        'signal': analysis['signal'] ?? analysis['tradingDecision'] ?? '관망',
        'confidence': analysis['confidence'] ?? 0.0,
        'target_price': analysis['targetPrice'],
        'reason': analysis['reason'],
        'investment_style': analysis['investmentStyle'],
        'met_conditions': analysis['metConditions'],
        'total_conditions': analysis['totalConditions'],
        'analysis_date': analysis['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      };
      
      // 누락된 컬럼들이 있으면 추가 (스키마 오류 방지)
      if (indicators['volume_threshold'] != null) {
        insertData['volume_threshold'] = indicators['volume_threshold'];
      }
      if (indicators['volume_time_slot'] != null) {
        insertData['volume_time_slot'] = indicators['volume_time_slot'];
      }
      if (indicators['volume_market'] != null) {
        insertData['volume_market'] = indicators['volume_market'];
      }
      
      await db.insert('analysis_results', insertData);
      
      print('✅ 분석 결과 저장 완료: ${analysis['stockCode']}');
    } catch (e) {
      print('❌ 분석 결과 저장 실패: $e');
      rethrow;
    }
  }

  /// 분석 결과 일괄 저장
  Future<void> saveAnalysisResults(List<Map<String, dynamic>> analyses) async {
    try {
      final db = await _databaseHelper.database;
      
      await db.transaction((txn) async {
        for (final analysis in analyses) {
          // Map<dynamic, dynamic>을 Map<String, dynamic>으로 변환
          final indicatorsRaw = analysis['indicators'];
          final indicators = indicatorsRaw is Map 
              ? Map<String, dynamic>.from(indicatorsRaw)
              : <String, dynamic>{};
          
          // 필수 컬럼만 포함하여 저장 (스키마 오류 방지)
          final insertData = {
            'stock_code': analysis['stockCode'] ?? '',
            'stock_name': analysis['stockName'] ?? '',
            'current_price': analysis['currentPrice'] ?? 0.0,
            'prev_close': analysis['prevClose'] ?? 0.0,
            'rsi': indicators['rsi'],
            'macd': indicators['macd'],
            'macd_signal': indicators['macd_signal'],
            'macd_histogram': indicators['macd_histogram'],
            'sma20': indicators['sma20'],
            'sma50': indicators['sma50'],
            'bollinger_upper': indicators['bollinger_upper'],
            'bollinger_middle': indicators['bollinger_middle'],
            'bollinger_lower': indicators['bollinger_lower'],
            'stochastic_k': indicators['stochastic_k'],
            'stochastic_d': indicators['stochastic_d'],
            'vwap': indicators['vwap'],
            'vix': indicators['vix'],
            'support_resistance_support': indicators['support_resistance_support'],
            'support_resistance_resistance': indicators['support_resistance_resistance'],
            'volume_ratio': indicators['volume_ratio'],
            'momentum': indicators['momentum'],
            'price_drop': indicators['priceDrop'],
            'volume_spike': indicators['volumeSpike'],
            'vix_spike': indicators['vixSpike'],
            'volume_price_divergence': indicators['volumePriceDivergence'],
            'bid_ask_imbalance': indicators['bidAskImbalance'],
            'smart_money_flow': indicators['smartMoneyFlow'],
            'signal': analysis['signal'] ?? analysis['tradingDecision'] ?? '관망',
            'confidence': analysis['confidence'] ?? 0.0,
            'target_price': analysis['targetPrice'],
            'reason': analysis['reason'],
            'investment_style': analysis['investmentStyle'],
            'met_conditions': analysis['metConditions'],
            'total_conditions': analysis['totalConditions'],
            'analysis_date': analysis['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
            'created_at': DateTime.now().millisecondsSinceEpoch,
          };
          
          // 누락된 컬럼들이 있으면 추가 (스키마 오류 방지)
          if (indicators['volume_threshold'] != null) {
            insertData['volume_threshold'] = indicators['volume_threshold'];
          }
          if (indicators['volume_time_slot'] != null) {
            insertData['volume_time_slot'] = indicators['volume_time_slot'];
          }
          if (indicators['volume_market'] != null) {
            insertData['volume_market'] = indicators['volume_market'];
          }
          
          await txn.insert('analysis_results', insertData);
        }
      });
      
      print('✅ 분석 결과 일괄 저장 완료: ${analyses.length}개');
    } catch (e) {
      print('❌ 분석 결과 일괄 저장 실패: $e');
      rethrow;
    }
  }

  /// 최신 분석 결과 조회
  Future<List<Map<String, dynamic>>> getLatestAnalysisResults() async {
    try {
      await createTable();
      final db = await _databaseHelper.database;
      
      final List<Map<String, dynamic>> results = await db.rawQuery('''
        SELECT * FROM analysis_results 
        WHERE analysis_date = (
          SELECT MAX(analysis_date) FROM analysis_results
        )
        ORDER BY stock_code
      ''');
      
      return _convertResults(results);
    } catch (e) {
      print('❌ 최신 분석 결과 조회 실패: $e');
      return [];
    }
  }

  /// 특정 종목의 최신 분석 결과 조회
  Future<Map<String, dynamic>?> getLatestAnalysisResult(String stockCode) async {
    try {
      await createTable();
      final db = await _databaseHelper.database;
      
      final List<Map<String, dynamic>> results = await db.query(
        'analysis_results',
        where: 'stock_code = ?',
        whereArgs: [stockCode],
        orderBy: 'analysis_date DESC',
        limit: 1,
      );
      
      if (results.isEmpty) return null;
      
      final converted = _convertResults(results);
      return converted.isNotEmpty ? converted.first : null;
    } catch (e) {
      print('❌ 특정 종목 분석 결과 조회 실패: $e');
      return null;
    }
  }

  /// 특정 종목의 분석 히스토리 조회
  Future<List<Map<String, dynamic>>> getAnalysisHistory(String stockCode, {int limit = 10}) async {
    try {
      await createTable();
      final db = await _databaseHelper.database;
      
      final List<Map<String, dynamic>> results = await db.query(
        'analysis_results',
        where: 'stock_code = ?',
        whereArgs: [stockCode],
        orderBy: 'analysis_date DESC',
        limit: limit,
      );
      
      return _convertResults(results);
    } catch (e) {
      print('❌ 분석 히스토리 조회 실패: $e');
      return [];
    }
  }

  /// 매수/매도 시그널이 있는 분석 결과 조회
  Future<List<Map<String, dynamic>>> getSignalAnalysisResults({String? signal}) async {
    try {
      await createTable();
      final db = await _databaseHelper.database;
      
      String whereClause = 'signal IN (?, ?)';
      List<String> whereArgs = ['매수', '매도'];
      
      if (signal != null) {
        whereClause = 'signal = ?';
        whereArgs = [signal];
      }
      
      final List<Map<String, dynamic>> results = await db.query(
        'analysis_results',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'analysis_date DESC',
      );
      
      return _convertResults(results);
    } catch (e) {
      print('❌ 시그널 분석 결과 조회 실패: $e');
      return [];
    }
  }

  /// 투자 스타일별 분석 결과 조회
  Future<List<Map<String, dynamic>>> getAnalysisResultsByStyle(String investmentStyle) async {
    try {
      await createTable();
      final db = await _databaseHelper.database;
      
      final List<Map<String, dynamic>> results = await db.query(
        'analysis_results',
        where: 'investment_style = ?',
        whereArgs: [investmentStyle],
        orderBy: 'analysis_date DESC',
      );
      
      return _convertResults(results);
    } catch (e) {
      print('❌ 투자 스타일별 분석 결과 조회 실패: $e');
      return [];
    }
  }

  /// 분석 결과 통계 조회
  Future<Map<String, dynamic>> getAnalysisStats() async {
    try {
      await createTable();
      final db = await _databaseHelper.database;
      
      final result = await db.rawQuery('''
        SELECT 
          COUNT(*) as total_count,
          COUNT(CASE WHEN signal = '매수' THEN 1 END) as buy_count,
          COUNT(CASE WHEN signal = '매도' THEN 1 END) as sell_count,
          COUNT(CASE WHEN signal = '관망' THEN 1 END) as hold_count,
          AVG(confidence) as avg_confidence,
          MAX(analysis_date) as last_analysis_date
        FROM analysis_results
      ''');
      
      final stats = result.first;
      return {
        'totalCount': stats['total_count'] ?? 0,
        'buyCount': stats['buy_count'] ?? 0,
        'sellCount': stats['sell_count'] ?? 0,
        'holdCount': stats['hold_count'] ?? 0,
        'avgConfidence': stats['avg_confidence'] ?? 0.0,
        'lastAnalysisDate': stats['last_analysis_date'] ?? 0,
      };
    } catch (e) {
      print('❌ 분석 결과 통계 조회 실패: $e');
      return {
        'totalCount': 0,
        'buyCount': 0,
        'sellCount': 0,
        'holdCount': 0,
        'avgConfidence': 0.0,
        'lastAnalysisDate': 0,
      };
    }
  }

  /// 오래된 분석 결과 정리
  Future<void> cleanupOldAnalysisResults({int daysToKeep = 30}) async {
    try {
      await createTable();
      final db = await _databaseHelper.database;
      
      final cutoffTime = DateTime.now().subtract(Duration(days: daysToKeep)).millisecondsSinceEpoch;
      
      final deletedCount = await db.delete(
        'analysis_results',
        where: 'analysis_date < ?',
        whereArgs: [cutoffTime],
      );
      
      print('✅ 오래된 분석 결과 정리 완료: $deletedCount개 삭제');
    } catch (e) {
      print('❌ 오래된 분석 결과 정리 실패: $e');
    }
  }

  /// 분석 결과 삭제
  Future<void> deleteAnalysisResults() async {
    try {
      await createTable();
      final db = await _databaseHelper.database;
      
      await db.delete('analysis_results');
      print('✅ 분석 결과 삭제 완료');
    } catch (e) {
      print('❌ 분석 결과 삭제 실패: $e');
      rethrow;
    }
  }

  /// 결과 형식 변환
  List<Map<String, dynamic>> _convertResults(List<Map<String, dynamic>> results) {
    return results.map((row) {
      return {
        'stockCode': row['stock_code'],
        'stockName': row['stock_name'],
        'currentPrice': row['current_price'],
        'prevClose': row['prev_close'],
        'indicators': {
          'rsi': row['rsi'],
          'macd': row['macd'],
          'macd_signal': row['macd_signal'],
          'macd_histogram': row['macd_histogram'],
          'sma20': row['sma20'],
          'sma50': row['sma50'],
          'bollinger_upper': row['bollinger_upper'],
          'bollinger_middle': row['bollinger_middle'],
          'bollinger_lower': row['bollinger_lower'],
          'stochastic_k': row['stochastic_k'],
          'stochastic_d': row['stochastic_d'],
          'vwap': row['vwap'],
          'vix': row['vix'],
          'support_resistance_support': row['support_resistance_support'],
          'support_resistance_resistance': row['support_resistance_resistance'],
          'volume_ratio': row['volume_ratio'],
          'volume_threshold': row['volume_threshold'],
          'volume_time_slot': row['volume_time_slot'],
          'volume_market': row['volume_market'],
          'momentum': row['momentum'],
          'priceDrop': row['price_drop'],
          'volumeSpike': row['volume_spike'],
          'vixSpike': row['vix_spike'],
          'volumePriceDivergence': row['volume_price_divergence'],
          'bidAskImbalance': row['bid_ask_imbalance'],
          'smartMoneyFlow': row['smart_money_flow'],
        },
        'signal': row['signal'],
        'confidence': row['confidence'],
        'targetPrice': row['target_price'],
        'reason': row['reason'],
        'investmentStyle': row['investment_style'],
        'metConditions': row['met_conditions'],
        'totalConditions': row['total_conditions'],
        'timestamp': row['analysis_date'],
        'createdAt': row['created_at'],
      };
    }).toList();
  }
}
