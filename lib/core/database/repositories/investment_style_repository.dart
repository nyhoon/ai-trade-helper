import '../database_helper.dart';
import 'package:sqflite/sqflite.dart';

/// 투자 스타일 설정 Repository
class InvestmentStyleRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

    /// 투자 스타일 저장 (간소화된 버전)
  Future<int> saveInvestmentStyle({
    required String styleName,
    required double partialProfit,
    required double fullProfit,
    required double stopLoss,
    required double positionSize,
    required int maxStocks,
    required double dailyLossLimit,
    required double buyThreshold,
    required double sellThreshold,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    print('💾 투자 스타일 저장: $styleName');
    print('   - buyThreshold: $buyThreshold');
    print('   - sellThreshold: $sellThreshold');

    return await db.insert(
      'investment_styles',
      {
        'style_name': styleName,
        'partial_profit': partialProfit,
        'full_profit': fullProfit,
        'stop_loss': stopLoss,
        'position_size': positionSize,
        'max_stocks': maxStocks,
        'daily_loss_limit': dailyLossLimit,
        'buy_threshold': buyThreshold,
        'sell_threshold': sellThreshold,
        // 새로운 스키마에 맞는 필드들
        'rsi_oversold': 30.0,
        'rsi_overbought': 70.0,
        'macd_signal': 0.0,
        'volume_threshold': 1.5,
        'momentum_threshold': 0.1,
        'price_drop_threshold': -0.05,
        'volume_spike_threshold': 3.0,
        'vix_spike_threshold': 30.0,
        'volume_price_divergence_threshold': 0.1,
        'bid_ask_imbalance_threshold': 1.5,
        'smart_money_flow_threshold': 0.1,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 투자 스타일 조회
  Future<Map<String, dynamic>?> getInvestmentStyle(String styleName) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'investment_styles',
      where: 'style_name = ? AND is_active = 1',
      whereArgs: [styleName],
      limit: 1,
    );

    return results.isNotEmpty ? results.first : null;
  }

  /// 모든 투자 스타일 조회
  Future<List<Map<String, dynamic>>> getAllInvestmentStyles() async {
    final db = await _dbHelper.database;
    return await db.query(
      'investment_styles',
      where: 'is_active = 1',
      orderBy: 'created_at DESC',
    );
  }

  /// 투자 스타일 업데이트 (없으면 생성)
  Future<int> updateInvestmentStyle({
    required String styleName,
    required double partialProfit,
    required double fullProfit,
    required double stopLoss,
    required double positionSize,
    required int maxStocks,
    required double dailyLossLimit,
    required double buyThreshold,
    required double sellThreshold,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    print('🔄 투자 스타일 업데이트: $styleName');
    print('   - buyThreshold: $buyThreshold');
    print('   - sellThreshold: $sellThreshold');

    // 먼저 해당 스타일이 존재하는지 확인
    final existingStyles = await db.query(
      'investment_styles',
      where: 'style_name = ?',
      whereArgs: [styleName],
    );

    if (existingStyles.isEmpty) {
      // 스타일이 없으면 새로 생성
      print('📝 $styleName 스타일이 없어서 새로 생성합니다.');
      return await db.insert(
        'investment_styles',
        {
          'style_name': styleName,
          'partial_profit': partialProfit,
          'full_profit': fullProfit,
          'stop_loss': stopLoss,
          'position_size': positionSize,
          'max_stocks': maxStocks,
          'daily_loss_limit': dailyLossLimit,
          'buy_threshold': buyThreshold,
          'sell_threshold': sellThreshold,
          // 새로운 스키마에 맞는 필드들
          'rsi_oversold': 30.0,
          'rsi_overbought': 70.0,
          'macd_signal': 0.0,
          'volume_threshold': 1.5,
          'momentum_threshold': 0.1,
          'price_drop_threshold': -0.05,
          'volume_spike_threshold': 3.0,
          'vix_spike_threshold': 30.0,
          'volume_price_divergence_threshold': 0.1,
          'bid_ask_imbalance_threshold': 1.5,
          'smart_money_flow_threshold': 0.1,
          'is_active': 1,
          'created_at': now,
          'updated_at': now,
        },
      );
    } else {
      // 스타일이 있으면 업데이트
      print('🔄 $styleName 스타일을 업데이트합니다.');
      return await db.update(
        'investment_styles',
        {
          'partial_profit': partialProfit,
          'full_profit': fullProfit,
          'stop_loss': stopLoss,
          'position_size': positionSize,
          'max_stocks': maxStocks,
          'daily_loss_limit': dailyLossLimit,
          'buy_threshold': buyThreshold,
          'sell_threshold': sellThreshold,
          'updated_at': now,
        },
        where: 'style_name = ?',
        whereArgs: [styleName],
      );
    }
  }

  /// 투자 스타일 삭제 (소프트 삭제)
  Future<int> deleteInvestmentStyle(String styleName) async {
    final db = await _dbHelper.database;
    return await db.update(
      'investment_styles',
      {'is_active': 0},
      where: 'style_name = ?',
      whereArgs: [styleName],
    );
  }

  /// 기본 투자 스타일 초기화
  Future<void> initializeDefaultStyles() async {
    final db = await _dbHelper.database;
    
    try {
      // 기존 스타일이 있는지 확인
      final existingStyles = await db.query(
        'investment_styles',
        where: 'is_active = 1',
        columns: ['style_name'],
      );
      
      print('📊 기존 투자 스타일 확인: ${existingStyles.length}개');
      for (final style in existingStyles) {
        print('   - ${style['style_name']}');
      }
      
      // 기존 데이터가 있으면 초기화하지 않음 (사용자 설정 보존)
      if (existingStyles.length > 0) {
        print('📊 기존 투자 스타일 데이터가 있습니다. 초기화를 건너뜁니다.');
        print('   - 사용자 설정을 보존합니다.');
        return;
      }
      
      print('🔄 기본 투자 스타일 초기화 시작...');

      // 안정적 투자 스타일
      await saveInvestmentStyle(
        styleName: '안정적 투자',
        partialProfit: 3.0,
        fullProfit: 7.0,
        stopLoss: -3.0,     // 음수로 통일
        positionSize: 0.05,
        maxStocks: 3,
        dailyLossLimit: -4.0, // 음수로 통일
        buyThreshold: 0.4,  // 매수 임계값 (양수)
        sellThreshold: -0.1, // 매도 임계값 (음수)
      );
      print('✅ 안정적 투자 스타일 초기화 완료');

      // 일반적 투자 스타일
      await saveInvestmentStyle(
        styleName: '일반적 투자',
        partialProfit: 5.0,
        fullProfit: 10.0,
        stopLoss: -5.0,     // 음수로 통일
        positionSize: 0.10,
        maxStocks: 4,
        dailyLossLimit: -6.0, // 음수로 통일
        buyThreshold: 0.35,  // 매수 임계값 (양수)
        sellThreshold: -0.15, // 매도 임계값 (음수)
      );
      print('✅ 일반적 투자 스타일 초기화 완료');

      // 공격적 투자 스타일
      await saveInvestmentStyle(
        styleName: '공격적 투자',
        partialProfit: 7.0,
        fullProfit: 15.0,
        stopLoss: -7.0,     // 음수로 통일
        positionSize: 0.20,
        maxStocks: 5,
        dailyLossLimit: -7.0, // 음수로 통일
        buyThreshold: 0.3,   // 매수 임계값 (양수)
        sellThreshold: -0.2,  // 매도 임계값 (음수)
      );
      print('✅ 공격적 투자 스타일 초기화 완료');
      
      print('🎉 모든 기본 투자 스타일 초기화 완료!');
      
    } catch (e) {
      print('❌ 기본 투자 스타일 초기화 실패: $e');
      rethrow;
    }
  }

  /// 투자 스타일 개수 조회
  Future<int> getInvestmentStyleCount() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM investment_styles WHERE is_active = 1');
    return result.first['count'] as int;
  }
}
