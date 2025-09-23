import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// 최적화된 자동매매 데이터베이스 헬퍼
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static DatabaseHelper get instance => _instance;

  DatabaseHelper._internal();
  
  factory DatabaseHelper() => _instance;

  static Database? _database;
  static const int _version = 7; // API 필드명으로 holdings 테이블 구조 변경

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// 데이터베이스 초기화
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'trading_app_v2.db');

    return await openDatabase(
      path,
      version: _version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        // 성능 PRAGMA 적용: 동시성(WAL) 및 안전/속도 균형
        try {
          await db.execute('PRAGMA journal_mode=WAL;');
          await db.execute('PRAGMA synchronous=NORMAL;');
          await db.execute('PRAGMA temp_store=MEMORY;');
          // 캐시 페이지 수(음수: KB 단위), 모바일 메모리 고려해 2MB 수준
          await db.execute('PRAGMA cache_size=-2000;');
        } catch (e) {
          print('⚠️ PRAGMA 설정 실패: $e');
        }
      },
    );
  }

  /// 데이터베이스 생성 - 최적화된 구조
  Future<void> _onCreate(Database db, int version) async {
    print('🗄️ 최적화된 자동매매 데이터베이스 생성 시작...');

    // 1. 종목 마스터 테이블 (기본 정보)
    await db.execute('''
      CREATE TABLE stock_master (
        stock_code TEXT PRIMARY KEY,
        stock_name TEXT NOT NULL,
        market TEXT NOT NULL, -- KOSPI, KOSDAQ, NASDAQ, NYSE 등
        sector TEXT,
        is_active INTEGER DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // 2. 관심종목 테이블 (사용자 설정)
    await db.execute('''
      CREATE TABLE watchlist (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        stock_code TEXT NOT NULL,
        stock_name TEXT NOT NULL,
        market TEXT NOT NULL,
        added_at INTEGER NOT NULL,
        memo TEXT,
        is_active INTEGER DEFAULT 1,
        UNIQUE(stock_code)
      )
    ''');

    // 3. 보유종목 테이블 (API 필드명 사용)
    await db.execute('''
      CREATE TABLE holdings (
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

    // 4. 차트 데이터 테이블 (최신 100일 보관)
    await db.execute('''
      CREATE TABLE chart_data (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        stock_code TEXT NOT NULL,
        market TEXT NOT NULL,
        date TEXT NOT NULL, -- YYYY-MM-DD 형식
        open REAL NOT NULL,
        high REAL NOT NULL,
        low REAL NOT NULL,
        close REAL NOT NULL,
        volume INTEGER NOT NULL,
        trade_amount REAL,
        created_at INTEGER NOT NULL,
        UNIQUE(stock_code, date)
      )
    ''');

    // 5. 실시간 현재가 테이블 (최신 데이터만)
    await db.execute('''
      CREATE TABLE current_price (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        stock_code TEXT NOT NULL,
        market TEXT NOT NULL,
        current_price REAL NOT NULL,
        prev_close REAL NOT NULL,
        change_amount REAL NOT NULL,
        change_rate REAL NOT NULL,
        volume INTEGER NOT NULL,
        trade_amount REAL NOT NULL,
        high_price REAL NOT NULL,
        low_price REAL NOT NULL,
        open_price REAL NOT NULL,
        market_cap REAL,
        per REAL,
        pbr REAL,
        timestamp INTEGER NOT NULL,
        UNIQUE(stock_code)
      )
    ''');

    // 6. 분석 결과 테이블 (최신 분석만)
    await db.execute('''
      CREATE TABLE analysis_results (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        stock_code TEXT NOT NULL,
        stock_name TEXT NOT NULL,
        market TEXT NOT NULL,
        current_price REAL NOT NULL,
        prev_close REAL NOT NULL,
        -- 기술적 지표
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
        -- 고급 지표
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
        -- 신호 및 결과
        signal TEXT NOT NULL, -- BUY, SELL, HOLD
        trading_decision TEXT, -- BUY, SELL, HOLD (호환)
        comprehensive_score REAL, -- 종합 점수
        signal_strength TEXT, -- 신호 강도 (매우 약한 신호, 약한 신호, 강한 신호 등)
        confidence REAL NOT NULL, -- 0.0 ~ 1.0
        confidence_score REAL, -- 호환
        change_rate REAL, -- 전일대비 등락률 (%)
        target_price REAL,
        reason TEXT,
        investment_style TEXT,
        met_conditions INTEGER,
        total_conditions INTEGER,
        analysis_date INTEGER NOT NULL,
        analysis_time INTEGER, -- 타임스탬프 (호환)
        analysis_details TEXT, -- 분석 상세 정보 (JSON)
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        UNIQUE(stock_code)
      )
    ''');

    // 7. AI 추천 종목 테이블 (10분마다 업데이트)
    await db.execute('''
      CREATE TABLE ai_recommendations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        stock_code TEXT NOT NULL,
        stock_name TEXT NOT NULL,
        market TEXT NOT NULL,
        current_price REAL NOT NULL,
        prev_close REAL NOT NULL,
        change_rate REAL NOT NULL,
        -- AI 분석 결과
        signal_strength REAL NOT NULL, -- 0.0 ~ 1.0
        confidence_score REAL NOT NULL, -- 0.0 ~ 1.0
        target_price REAL,
        recommendation_reason TEXT,
        -- 추천 상태
        is_recommended INTEGER DEFAULT 1,
        is_notified INTEGER DEFAULT 0,
        recommended_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        UNIQUE(stock_code)
      )
    ''');

    // 8. 거래 내역 테이블 (완료된 거래만)
    await db.execute('''
      CREATE TABLE trade_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        stock_code TEXT NOT NULL,
        stock_name TEXT NOT NULL,
        market TEXT NOT NULL,
        order_type TEXT NOT NULL, -- BUY, SELL
        quantity INTEGER NOT NULL,
        price REAL NOT NULL,
        total_amount REAL NOT NULL,
        order_date TEXT NOT NULL, -- YYYY-MM-DD
        order_time TEXT NOT NULL, -- HH:MM:SS
        profit_loss REAL DEFAULT 0,
        profit_rate REAL DEFAULT 0,
        trade_reason TEXT,
        investment_style TEXT,
        met_conditions INTEGER DEFAULT 0,
        total_conditions INTEGER DEFAULT 6,
        is_auto_trade INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    // 9. 투자 스타일 설정 테이블
    await db.execute('''
      CREATE TABLE investment_styles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        style_name TEXT NOT NULL,
        -- 수익 관리
        partial_profit REAL NOT NULL,
        full_profit REAL NOT NULL,
        stop_loss REAL NOT NULL,
        position_size REAL NOT NULL,
        max_stocks INTEGER NOT NULL,
        daily_loss_limit REAL NOT NULL,
        -- 매매 조건
        buy_threshold REAL NOT NULL,
        sell_threshold REAL NOT NULL,
        rsi_oversold REAL NOT NULL,
        rsi_overbought REAL NOT NULL,
        macd_signal REAL NOT NULL,
        volume_threshold REAL NOT NULL,
        momentum_threshold REAL NOT NULL,
        price_drop_threshold REAL NOT NULL,
        volume_spike_threshold REAL NOT NULL,
        vix_spike_threshold REAL NOT NULL,
        volume_price_divergence_threshold REAL NOT NULL,
        bid_ask_imbalance_threshold REAL NOT NULL,
        smart_money_flow_threshold REAL NOT NULL,
        is_active INTEGER DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // 10. 시그널 히스토리 테이블 (최신 30일)
    await db.execute('''
      CREATE TABLE signal_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        stock_code TEXT NOT NULL,
        stock_name TEXT NOT NULL,
        market TEXT NOT NULL,
        signal_type TEXT NOT NULL, -- BUY, SELL, HOLD
        signal_strength REAL NOT NULL,
        price REAL NOT NULL,
        volume REAL NOT NULL,
        -- 지표 값들
        rsi REAL,
        macd REAL,
        macd_signal REAL,
        sma20 REAL,
        sma50 REAL,
        bollinger_position TEXT,
        confidence REAL,
        triggered_at INTEGER NOT NULL,
        is_executed INTEGER DEFAULT 0,
        execution_price REAL,
        execution_quantity INTEGER,
        execution_date INTEGER,
        memo TEXT,
        dedup_key TEXT,
        UNIQUE(dedup_key)
      )
    ''');

    // 11. 포트폴리오 성과 테이블 (일별)
    await db.execute('''
      CREATE TABLE portfolio_performance (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date INTEGER NOT NULL, -- YYYYMMDD
        total_value REAL NOT NULL,
        total_profit REAL NOT NULL,
        total_profit_rate REAL NOT NULL,
        daily_profit REAL NOT NULL,
        daily_profit_rate REAL NOT NULL,
        max_drawdown REAL NOT NULL,
        sharpe_ratio REAL,
        win_rate REAL,
        trade_count INTEGER NOT NULL,
        style_name TEXT,
        created_at INTEGER NOT NULL,
        UNIQUE(date)
      )
    ''');

    // 12. 알림 히스토리 테이블 (최신 30일)
    await db.execute('''
      CREATE TABLE notification_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL, -- SIGNAL, AI_RECOMMENDATION, TRADE, ALERT
        stock_code TEXT NOT NULL,
        stock_name TEXT NOT NULL,
        market TEXT NOT NULL,
        message TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    // 13. API 설정 테이블
    await db.execute('''
      CREATE TABLE api_config (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        app_key TEXT,
        app_secret TEXT,
        account_no TEXT,
        is_real INTEGER DEFAULT 1,
        auto_trading_enabled INTEGER DEFAULT 0,
        ai_recommendation_enabled INTEGER DEFAULT 1,
        updated_at INTEGER NOT NULL
      )
    ''');
    
    // 기본 API 설정 삽입
    await db.insert('api_config', {
      'id': 1,
      'app_key': null,
      'app_secret': null,
      'account_no': null,
      'is_real': 1,
      'auto_trading_enabled': 0,
      'ai_recommendation_enabled': 1,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });

    // 14. 데이터 동기화 상태 테이블
    await db.execute('''
      CREATE TABLE sync_status (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        last_chart_sync INTEGER NOT NULL,
        last_price_sync INTEGER NOT NULL,
        last_analysis_sync INTEGER NOT NULL,
        last_ai_recommendation_sync INTEGER NOT NULL,
        last_cleanup INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    
    // 기본 동기화 상태 삽입
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('sync_status', {
      'id': 1,
      'last_chart_sync': now,
      'last_price_sync': now,
      'last_analysis_sync': now,
      'last_ai_recommendation_sync': now,
      'last_cleanup': now,
      'created_at': now,
      'updated_at': now,
    });

    // 성능 최적화 인덱스 생성
    await db.execute('CREATE INDEX idx_chart_data_stock_date ON chart_data (stock_code, date)');
    await db.execute('CREATE INDEX idx_current_price_stock ON current_price (stock_code)');
    await db.execute('CREATE INDEX idx_analysis_results_stock ON analysis_results (stock_code)');
    await db.execute('CREATE INDEX idx_ai_recommendations_stock ON ai_recommendations (stock_code)');
    await db.execute('CREATE INDEX idx_trade_history_stock_date ON trade_history (stock_code, order_date)');
    await db.execute('CREATE INDEX idx_signal_history_stock_date ON signal_history (stock_code, triggered_at)');
    await db.execute('CREATE INDEX idx_signal_history_type ON signal_history (signal_type)');
    await db.execute('CREATE INDEX idx_portfolio_performance_date ON portfolio_performance (date)');
    await db.execute('CREATE INDEX idx_notification_history_timestamp ON notification_history (timestamp)');
    await db.execute('CREATE INDEX idx_watchlist_active ON watchlist (is_active)');
    await db.execute('CREATE INDEX idx_holdings_active ON holdings (pdno)');

    print('✅ 최적화된 자동매매 데이터베이스 생성 완료');
  }

  /// 데이터베이스 업그레이드
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print('🔄 데이터베이스 업그레이드: $oldVersion → $newVersion');
    
    if (oldVersion < 7) {
      // API 필드명으로 holdings 테이블 구조 변경
      print('🔄 holdings 테이블을 API 필드명으로 재구성...');
      await db.execute('DROP TABLE IF EXISTS holdings');
      await db.execute('''
        CREATE TABLE holdings (
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
      print('✅ holdings 테이블 재구성 완료');
    }
    
    if (oldVersion < 3) {
      // analysis_results 컬럼 보강을 위해 테이블 재생성
      await db.execute('ALTER TABLE analysis_results RENAME TO analysis_results_old');
      await _onCreate(db, newVersion);
      try {
        // 가능한 컬럼만 매핑하여 이전 데이터 이관
        await db.execute('''
          INSERT OR IGNORE INTO analysis_results (
            stock_code, stock_name, market, current_price, prev_close,
            rsi, macd, macd_signal, macd_histogram, sma20, sma50,
            bollinger_upper, bollinger_middle, bollinger_lower,
            stochastic_k, stochastic_d, vwap, vix,
            support_resistance_support, support_resistance_resistance,
            volume_ratio, volume_threshold, volume_time_slot, volume_market,
            momentum, price_drop, volume_spike, vix_spike, volume_price_divergence,
            bid_ask_imbalance, smart_money_flow,
            signal, confidence, target_price, reason, investment_style,
            met_conditions, total_conditions, analysis_date, created_at
          )
          SELECT 
            stock_code, stock_name, market, current_price, prev_close,
            rsi, macd, macd_signal, macd_histogram, sma20, sma50,
            bollinger_upper, bollinger_middle, bollinger_lower,
            stochastic_k, stochastic_d, vwap, vix,
            support_resistance_support, support_resistance_resistance,
            volume_ratio, volume_threshold, volume_time_slot, volume_market,
            momentum, price_drop, volume_spike, vix_spike, volume_price_divergence,
            bid_ask_imbalance, smart_money_flow,
            signal, confidence, target_price, reason, investment_style,
            met_conditions, total_conditions, analysis_date, created_at
          FROM analysis_results_old
        ''');
      } catch (e) {
        print('⚠️ analysis_results 데이터 이관 실패: $e');
      }
      await db.execute('DROP TABLE IF EXISTS analysis_results_old');
    }
    
    if (oldVersion < 4) {
      // signal_strength 컬럼 추가
      try {
        await db.execute('ALTER TABLE analysis_results ADD COLUMN signal_strength TEXT');
        print('✅ signal_strength 컬럼 추가 완료');
      } catch (e) {
        print('⚠️ signal_strength 컬럼 추가 실패: $e');
      }
    }
    
    if (oldVersion < 5) {
      // change_rate 컬럼 추가
      try {
        await db.execute('ALTER TABLE analysis_results ADD COLUMN change_rate REAL');
        print('✅ change_rate 컬럼 추가 완료');
      } catch (e) {
        print('⚠️ change_rate 컬럼 추가 실패: $e');
      }
    }
    
    if (oldVersion < 6) {
      // updated_at 컬럼이 없는 경우 추가
      try {
        await db.execute('ALTER TABLE analysis_results ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0');
        print('✅ updated_at 컬럼 추가 완료');
      } catch (e) {
        print('⚠️ updated_at 컬럼 추가 실패: $e');
      }
    }
  }

  /// 데이터베이스 강제 재생성
  Future<void> forceRecreate() async {
    print('🗄️ 데이터베이스 강제 재생성 시작...');
      
    // 기존 데이터베이스 닫기
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
      
    // 데이터베이스 파일 삭제
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'trading_app_v2.db');
      
    try {
      await deleteDatabase(path);
      print('✅ 기존 데이터베이스 파일 삭제 완료');
    } catch (e) {
      print('⚠️ 기존 데이터베이스 파일 삭제 실패: $e');
    }
      
    // 새 데이터베이스 생성
    _database = await _initDatabase();
    print('✅ 새 데이터베이스 생성 완료');
  }

  /// 데이터베이스 닫기
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  /// 데이터베이스 통계 조회
  Future<Map<String, int>> getDatabaseStats() async {
    final db = await database;
    final stats = <String, int>{};
    
    final tables = [
      'stock_master', 'watchlist', 'holdings', 'chart_data', 'current_price',
      'analysis_results', 'ai_recommendations', 'trade_history', 'investment_styles',
      'signal_history', 'portfolio_performance', 'notification_history', 'api_config', 'sync_status'
    ];
    
    for (final table in tables) {
      try {
        final result = await db.rawQuery('SELECT COUNT(*) as count FROM $table');
        stats[table] = result.first['count'] as int;
      } catch (e) {
        stats[table] = 0;
      }
    }
    
    return stats;
  }

  /// 스마트 데이터 정리 (100일 보관 정책)
  Future<void> cleanupData() async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    print('🧹 스마트 데이터 정리 시작...');
    
    try {
      // 1. 차트 데이터: 최신 100일만 보관
      final hundredDaysAgo = DateTime.now().subtract(const Duration(days: 100));
      final cutoffDate = '${hundredDaysAgo.year.toString().padLeft(4, '0')}-${hundredDaysAgo.month.toString().padLeft(2, '0')}-${hundredDaysAgo.day.toString().padLeft(2, '0')}';
      
      final chartDeleted = await db.delete(
        'chart_data',
        where: 'date < ?',
        whereArgs: [cutoffDate],
      );
      print('📊 차트 데이터 정리: $chartDeleted개 삭제 (100일 초과)');

      // 2. AI 추천: 7일 이상된 데이터 정리
      final sevenDaysAgo = now - (7 * 24 * 60 * 60 * 1000);
      final aiDeleted = await db.delete(
        'ai_recommendations',
        where: 'recommended_at < ?',
        whereArgs: [sevenDaysAgo],
      );
      print('🤖 AI 추천 데이터 정리: $aiDeleted개 삭제 (7일 초과)');

      // 3. 시그널 히스토리: 30일 이상된 데이터 정리
      final thirtyDaysAgo = now - (30 * 24 * 60 * 60 * 1000);
      final signalDeleted = await db.delete(
        'signal_history',
        where: 'triggered_at < ?',
        whereArgs: [thirtyDaysAgo],
      );
      print('🔔 시그널 히스토리 정리: $signalDeleted개 삭제 (30일 초과)');

      // 4. 알림 히스토리: 30일 이상된 데이터 정리
      final notificationDeleted = await db.delete(
        'notification_history',
        where: 'timestamp < ?',
        whereArgs: [thirtyDaysAgo],
      );
      print('📱 알림 히스토리 정리: $notificationDeleted개 삭제 (30일 초과)');

      // 5. 포트폴리오 성과: 1년 이상된 데이터 정리
      final oneYearAgo = now - (365 * 24 * 60 * 60 * 1000);
      final portfolioDeleted = await db.delete(
        'portfolio_performance',
        where: 'date < ?',
        whereArgs: [oneYearAgo],
      );
      print('📊 포트폴리오 성과 정리: $portfolioDeleted개 삭제 (1년 초과)');

      // 6. 비활성 종목 정리 (관심종목에서 제거된 종목의 차트 데이터)
      await db.execute('''
        DELETE FROM chart_data 
        WHERE stock_code NOT IN (
          SELECT stock_code FROM watchlist WHERE is_active = 1
          UNION
          SELECT stock_code FROM holdings
        )
      ''');

      // 7. 동기화 상태 업데이트
      await db.update('sync_status', {
        'last_cleanup': now,
        'updated_at': now,
      }, where: 'id = 1');

      print('✅ 스마트 데이터 정리 완료');
    } catch (e) {
      print('❌ 데이터 정리 실패: $e');
    }
  }

  /// 특정 테이블의 데이터 정리
  Future<int> cleanupTable(String tableName, {int? daysToKeep}) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    if (daysToKeep == null) {
      // 기본 정리 정책
      switch (tableName) {
        case 'chart_data':
          daysToKeep = 100;
          break;
        case 'ai_recommendations':
          daysToKeep = 7;
          break;
        case 'signal_history':
          daysToKeep = 30;
          break;
        case 'notification_history':
          daysToKeep = 30;
          break;
        case 'portfolio_performance':
          daysToKeep = 365;
          break;
        default:
          daysToKeep = 30;
      }
    }
    
    final cutoffTime = now - (daysToKeep * 24 * 60 * 60 * 1000);
    
    String whereClause;
    List<dynamic> whereArgs;
    
    switch (tableName) {
      case 'chart_data':
        final cutoffDate = DateTime.fromMillisecondsSinceEpoch(cutoffTime);
        final dateStr = '${cutoffDate.year.toString().padLeft(4, '0')}-${cutoffDate.month.toString().padLeft(2, '0')}-${cutoffDate.day.toString().padLeft(2, '0')}';
        whereClause = 'date < ?';
        whereArgs = [dateStr];
        break;
      case 'ai_recommendations':
        whereClause = 'recommended_at < ?';
        whereArgs = [cutoffTime];
        break;
      case 'signal_history':
        whereClause = 'triggered_at < ?';
        whereArgs = [cutoffTime];
        break;
      case 'notification_history':
        whereClause = 'timestamp < ?';
        whereArgs = [cutoffTime];
        break;
      case 'portfolio_performance':
        whereClause = 'date < ?';
        whereArgs = [cutoffTime];
        break;
      default:
        return 0;
    }
    
    return await db.delete(tableName, where: whereClause, whereArgs: whereArgs);
  }

  /// 데이터베이스 크기 최적화 (메모리 부족 방지 강화)
  Future<void> optimizeDatabase() async {
    final db = await database;
    
    print('⚡ 데이터베이스 최적화 시작...');
    
    try {
      // 1. 오래된 데이터 정리 (메모리 부족 방지)
      await cleanupOldData();
      
      // 2. VACUUM 실행으로 데이터베이스 크기 최적화
      await db.execute('VACUUM');
      
      // 3. 인덱스 재구성
      await db.execute('REINDEX');
      
      // 4. 통계 정보 업데이트
      await db.execute('ANALYZE');
      
      print('✅ 데이터베이스 최적화 완료');
    } catch (e) {
      print('❌ 데이터베이스 최적화 실패: $e');
    }
  }

  /// 오래된 데이터 정리 (메모리 부족 방지)
  Future<void> cleanupOldData() async {
    final db = await database;
    
    try {
      print('🧹 오래된 데이터 정리 시작...');
      
      // 1. 30일 이상 된 차트 데이터 정리
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      final dateStr = '${thirtyDaysAgo.year.toString().padLeft(4, '0')}-${thirtyDaysAgo.month.toString().padLeft(2, '0')}-${thirtyDaysAgo.day.toString().padLeft(2, '0')}';
      
      final chartDeleted = await db.delete(
        'chart_data',
        where: 'date < ?',
        whereArgs: [dateStr],
      );
      
      // 2. 1시간 이상 된 현재가 데이터 정리
      final oneHourAgo = DateTime.now().millisecondsSinceEpoch - (60 * 60 * 1000);
      final priceDeleted = await db.delete(
        'current_price',
        where: 'timestamp < ?',
        whereArgs: [oneHourAgo],
      );
      
      // 3. 7일 이상 된 AI 추천 데이터 정리
      final sevenDaysAgo = DateTime.now().millisecondsSinceEpoch - (7 * 24 * 60 * 60 * 1000);
      final aiDeleted = await db.delete(
        'ai_recommendations',
        where: 'recommended_at < ?',
        whereArgs: [sevenDaysAgo],
      );
      
      print('✅ 오래된 데이터 정리 완료: 차트 $chartDeleted개, 현재가 $priceDeleted개, AI추천 $aiDeleted개 삭제');
      
    } catch (e) {
      print('❌ 오래된 데이터 정리 실패: $e');
    }
  }

  /// 동기화 상태 조회
  Future<Map<String, int>> getSyncStatus() async {
    final db = await database;
    final result = await db.query('sync_status', where: 'id = 1');
    
    if (result.isEmpty) {
      return {};
    }
    
    return {
      'last_chart_sync': result.first['last_chart_sync'] as int,
      'last_price_sync': result.first['last_price_sync'] as int,
      'last_analysis_sync': result.first['last_analysis_sync'] as int,
      'last_ai_recommendation_sync': result.first['last_ai_recommendation_sync'] as int,
      'last_cleanup': result.first['last_cleanup'] as int,
    };
  }

  /// 동기화 상태 업데이트
  Future<void> updateSyncStatus(String syncType) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    final updateData = <String, dynamic>{
      'updated_at': now,
    };
    
    switch (syncType) {
      case 'chart':
        updateData['last_chart_sync'] = now;
        break;
      case 'price':
        updateData['last_price_sync'] = now;
        break;
      case 'analysis':
        updateData['last_analysis_sync'] = now;
        break;
      case 'ai_recommendation':
        updateData['last_ai_recommendation_sync'] = now;
        break;
      case 'cleanup':
        updateData['last_cleanup'] = now;
        break;
    }
    
    await db.update('sync_status', updateData, where: 'id = 1');
  }

  /// SQL 실행 메서드
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    final db = await database;
    await db.execute(sql, arguments);
  }

  /// SQL 쿼리 메서드
  Future<List<Map<String, dynamic>>> query(String sql, [List<Object?>? arguments]) async {
    final db = await database;
    return await db.rawQuery(sql, arguments);
  }

  /// 트랜잭션 메서드
  Future<T> transaction<T>(Future<T> Function(Transaction) action) async {
    final db = await database;
    return await db.transaction(action);
  }
}
