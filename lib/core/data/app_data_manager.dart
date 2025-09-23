import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:flutter/foundation.dart';
import '../api/kis_unified_api_service.dart';
import '../config/api_config.dart';
import '../trading/stock_cache_manager.dart';
import '../database/repositories/watchlist_repository.dart';
import '../database/repositories/holdings_repository.dart';
import '../database/repositories/analysis_repository.dart';
import '../database/repositories/trade_history_repository.dart';
import 'stock_master_parser.dart';
import 'symbol_store.dart';
import '../database/database_helper.dart';
import '../database/repositories/stock_repository.dart';
import '../database/repositories/watchlist_repository.dart';
import '../database/repositories/realtime_data_repository.dart';
import '../database/repositories/investment_style_repository.dart';
import '../database/repositories/signal_history_repository.dart';
import '../database/repositories/historical_data_repository.dart';
import '../database/repositories/chart_data_repository.dart';
import '../database/repositories/notification_history_repository.dart';
import '../services/signal_tracker.dart';
import '../analysis/unified_analysis_service.dart';
import '../services/trade_status_tracker.dart';
import '../services/realtime_price_service.dart';
import '../services/realtime_score_service.dart';
import '../services/local_notification_manager.dart';
import '../ui/realtime_ui_manager.dart';
import '../trading/auto_trading_cycle.dart';
import '../trading/background_trading_service.dart';
import '../services/trading_event_channel.dart';
import '../services/data_management_service.dart';
import '../ai/ai_recommendation_service.dart';
import '../database/repositories/top_stocks_repository.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:async';

/// 앱 전체 데이터 관리자
class AppDataManager {
  static AppDataManager? _instance;
  static AppDataManager get instance => _instance ??= AppDataManager._();
  
  AppDataManager._();

  // API 서비스 인스턴스 - 직접 사용
  KisUnifiedApiService get _unifiedApiService => KisUnifiedApiService();

  // 종목 데이터
  Map<String, String> _stockNames = {};

  // 데이터베이스 헬퍼 접근자
  DatabaseHelper get databaseHelper => _databaseHelper;
  Map<String, String> get stockNames => _stockNames;
  final SymbolStore _symbolStore = SymbolStore();
  
  // 종목 마스터 파서
  final StockMasterParser _stockMasterParser = StockMasterParser();

  // 데이터베이스 관련
  final DatabaseHelper _databaseHelper = DatabaseHelper();
  final StockRepository _stockRepository = StockRepository();
  final WatchlistRepository _watchlistRepository = WatchlistRepository();
  final HoldingsRepository _holdingsRepository = HoldingsRepository();
  final AnalysisRepository _analysisRepository = AnalysisRepository();
  final RealtimeDataRepository _realtimeDataRepository = RealtimeDataRepository();
  final InvestmentStyleRepository _investment_styleRepository = InvestmentStyleRepository();
  final SignalHistoryRepository _signalHistoryRepository = SignalHistoryRepository();
  final HistoricalDataRepository _historicalDataRepository = HistoricalDataRepository();
  final ChartDataRepository _chartDataRepository = ChartDataRepository();
  final TradeHistoryRepository _tradeHistoryRepository = TradeHistoryRepository();
  final NotificationHistoryRepository _notificationHistoryRepository = NotificationHistoryRepository();
  final TopStocksRepository _topStocksRepository = TopStocksRepository();

  // 실시간 가격 서비스 (지연 초기화)
  RealtimePriceService? _realtimePriceService;
  
  // 실시간 점수 서비스 (지연 초기화)
  RealtimeScoreService? _realtimeScoreService;
  
  // 로컬 알림 매니저 (지연 초기화)
  LocalNotificationManager? _localNotificationManager;
  
  // 실시간 UI 매니저 (지연 초기화)
  RealtimeUIManager? _realtimeUIManager;

  // 데이터 관리 서비스 (지연 초기화)
  DataManagementService? _dataManagementService;
  
  // AI 추천 서비스 (지연 초기화)
  AiRecommendationService? _aiRecommendationService;

  // 관심종목 (메모리 캐시)
  List<Map<String, dynamic>> _watchlist = [];
  List<Map<String, dynamic>> get watchlist => _watchlist;
  
  // 현재가 캐시
  Map<String, Map<String, dynamic>> _currentPrices = {};
  Map<String, Map<String, dynamic>> get currentPrices => _currentPrices;
  
  // 보유종목 캐시
  List<Map<String, dynamic>> _positions = [];
  List<Map<String, dynamic>> get positions => _positions;
  set positions(List<Map<String, dynamic>> value) {
    _positions = List<Map<String, dynamic>>.from(value);
    print('📊 AppDataManager: 보유종목 업데이트 - ${_positions.length}개');
  }
  
  // 관심종목 데이터 캐시
  Map<String, dynamic> _watchlistDataCache = {};
  DateTime? _watchlistCacheTimestamp;
  
  // 보유종목 데이터 캐시
  Map<String, dynamic> _holdingsDataCache = {};
  DateTime? _holdingsCacheTimestamp;
  
  // 차트 데이터 캐시
  Map<String, List<Map<String, dynamic>>> _chartDataCache = {};
  DateTime? _chartDataCacheTimestamp;
  
  // 캐시 만료 시간 (1분으로 단축)
  static const Duration _cacheExpiry = Duration(minutes: 1);
  
  // 관심종목 변경 알림을 위한 Stream
  final StreamController<List<Map<String, dynamic>>> _watchlistChangeController = 
    StreamController<List<Map<String, dynamic>>>.broadcast();
  Stream<List<Map<String, dynamic>>> get watchlistChangeStream => _watchlistChangeController.stream;

  /// StockRepository 접근용 getter
  StockRepository get stockRepository => _stockRepository;

  /// WatchlistRepository 접근용 getter
  WatchlistRepository get watchlistRepository => _watchlistRepository;

  /// HoldingsRepository 접근용 getter
  HoldingsRepository get holdingsRepository => _holdingsRepository;

  /// AnalysisRepository 접근용 getter
  AnalysisRepository get analysisRepository => _analysisRepository;

  /// RealtimePriceService 접근용 getter (지연 초기화)
  RealtimePriceService get realtimePriceService => _realtimePriceService ??= RealtimePriceService();

  /// RealtimeScoreService 접근용 getter (지연 초기화)
  RealtimeScoreService get realtimeScoreService => _realtimeScoreService ??= RealtimeScoreService();

  /// TopStocksRepository 접근용 getter
  TopStocksRepository get topStocksRepository => _topStocksRepository;

  /// SignalHistoryRepository 접근용 getter
  SignalHistoryRepository get signalHistoryRepository => _signalHistoryRepository;

  /// LocalNotificationManager 접근용 getter (지연 초기화)
  LocalNotificationManager get localNotificationManager => _localNotificationManager ??= LocalNotificationManager();
  
  /// NotificationHistoryRepository 접근용 getter
  NotificationHistoryRepository get notificationHistoryRepository => _notificationHistoryRepository;
  
  /// TradeHistoryRepository 접근용 getter
  TradeHistoryRepository get tradeHistoryRepository => _tradeHistoryRepository;
  
  /// HistoricalDataRepository 접근용 getter
  HistoricalDataRepository get historicalDataRepo => _historicalDataRepository;
  
  /// CurrentPriceRepository 접근용 getter
  RealtimeDataRepository get currentPriceRepo => _realtimeDataRepository;
  
  /// RealtimeUIManager 접근용 getter (지연 초기화)
  RealtimeUIManager get realtimeUIManager => _realtimeUIManager ??= RealtimeUIManager();
  
  /// AI 추천 서비스 접근용 getter (지연 초기화)
  AiRecommendationService get aiRecommendationService => _aiRecommendationService ??= AiRecommendationService();
  
  /// SharedPreferences 접근용 getter
  Future<SharedPreferences> get sharedPreferences => SharedPreferences.getInstance();


  /// 관심종목 목록 가져오기 (자동매매 사이클용)
  Future<List<Map<String, dynamic>>> getWatchlist() async {
    try {
      print('📋 getWatchlist() 호출됨');
      print('📊 현재 메모리 캐시 관심종목 수: ${_watchlist.length}개');
      
      if (_watchlist.isEmpty) {
        print('⚠️ 메모리 캐시가 비어있어 관심종목을 다시 로드합니다.');
        await _loadWatchlist();
      }
      
      print('✅ getWatchlist() 완료: ${_watchlist.length}개');
      
      // 관심종목 상세 출력
      if (_watchlist.isNotEmpty) {
        print('📋 관심종목 상세 목록:');
        for (int i = 0; i < _watchlist.length; i++) {
          final item = _watchlist[i];
          final stockCode = item['stock_code'] ?? item['stockCode'] ?? 'Unknown';
          final stockName = item['stock_name'] ?? item['stockName'] ?? 'Unknown';
          print('  ${i + 1}. $stockCode: $stockName');
        }
      } else {
        print('⚠️ 관심종목이 비어있습니다!');
      }
      
      return _watchlist;
    } catch (e) {
      print('❌ 관심종목 조회 실패: $e');
      return [];
    }
  }

  /// SQL에서 점수/가격을 조인하여 관심종목을 최신값으로 반환 (UI용)
  Future<List<Map<String, dynamic>>> getWatchlistWithScores() async {
    try {
      // DB에서 즉시 조회 (watchlist x top_stocks)
      final db = await DatabaseHelper.instance.database;
      final rows = await db.rawQuery('''
        SELECT w.stock_code, w.stock_name, w.added_at,
               ts.score, ts.current_price, ts.last_updated
        FROM watchlist w
        LEFT JOIN top_stocks ts ON ts.stock_code = w.stock_code
        WHERE w.is_active = 1
        ORDER BY w.added_at DESC
      ''');

      final result = <Map<String, dynamic>>[];
      for (final r in rows) {
        result.add({
          'stock_code': r['stock_code'],
          'stock_name': r['stock_name'],
          'added_at': r['added_at'],
          'score': r['score'] ?? 0.0,
          'current_price': r['current_price'] ?? 0.0,
          'last_updated': r['last_updated'],
        });
      }
      return result;
    } catch (e) {
      print('❌ getWatchlistWithScores 실패: $e');
      return [];
    }
  }

  /// 자동매매 상태 저장
  Future<void> setAutoTradingStatus(bool isEnabled) async {
    try {
      // ApiConfig를 통해 SQLite에 저장
      await ApiConfig.instance.setAutoTradingEnabled(isEnabled);
      
      // 호환성을 위해 SharedPreferences에도 저장
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auto_trading_last_update', DateTime.now().toIso8601String());
      print('💾 자동매매 상태 저장: enabled=$isEnabled');
      
      // 자동매매 OFF 시 모든 서비스 중지
      if (!isEnabled) {
        print('🛑 자동매매 OFF - 모든 서비스 중지 중...');
        
        // 1. AutoTradingCycle 중지
        try {
          await AutoTradingCycle().stopCycle();
          print('✅ AutoTradingCycle 중지 완료');
        } catch (e) {
          print('⚠️ AutoTradingCycle 중지 실패: $e');
        }
        
        // 2. BackgroundTradingService 중지
        try {
          await BackgroundTradingService().stopBackgroundService();
          print('✅ BackgroundTradingService 중지 완료');
        } catch (e) {
          print('⚠️ BackgroundTradingService 중지 실패: $e');
        }
        
        // 3. 실시간 가격 서비스 중지
        try {
          await realtimePriceService.stop();
          print('✅ 실시간 가격 서비스 중지 완료');
        } catch (e) {
          print('⚠️ 실시간 가격 서비스 중지 실패: $e');
        }
        
        // 4. TradingEventChannel 중지
        try {
          TradingEventChannel.stopListening();
          print('✅ TradingEventChannel 중지 완료');
        } catch (e) {
          print('⚠️ TradingEventChannel 중지 실패: $e');
        }
        
        print('🛑 자동매매 OFF - 모든 서비스 중지 완료');
      }
    } catch (e) {
      print('❌ 자동매매 상태 저장 실패: $e');
    }
  }

  /// 자동매매 상태 조회
  Future<bool> getAutoTradingStatus() async {
    try {
      // ApiConfig를 통해 SQLite에서 조회
      final isEnabled = await ApiConfig.instance.getAutoTradingEnabled();
      print('🔍 자동매매 상태 조회: enabled=$isEnabled');
      return isEnabled;
    } catch (e) {
      print('❌ 자동매매 상태 조회 실패: $e');
      return false;
    }
  }

  /// 자동매매 상태 복원 및 안전성 검사
  Future<void> _restoreAutoTradingStatus() async {
    try {
      print('🔍 자동매매 상태 복원 및 안전성 검사 시작...');
      
      // 1. SQLite에서 자동매매 상태 조회 (타임아웃 설정)
      bool isCurrentlyEnabled = false;
      try {
        isCurrentlyEnabled = await getAutoTradingStatus().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            print('⚠️ 자동매매 상태 조회 타임아웃 - 기본값 false 사용');
            return false;
          },
        );
      } catch (e) {
        print('⚠️ 자동매매 상태 조회 실패 - 기본값 false 사용: $e');
        isCurrentlyEnabled = false;
      }
      
      print('📊 SQLite에서 조회된 자동매매 상태: $isCurrentlyEnabled');
      
      // 2. 앱 시작 시 자동매매 상태를 그대로 유지 (강제 OFF 제거)
      if (isCurrentlyEnabled) {
        print('✅ 자동매매 상태 정상 (ON) - 사용자 설정 유지');
        
        // 3. 자동매매가 ON이면 백그라운드 서비스 시작 (타임아웃 설정)
        try {
          await BackgroundTradingService().startBackgroundService().timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              print('⚠️ 백그라운드 서비스 시작 타임아웃');
              return;
            },
          );
          print('✅ 백그라운드 서비스 시작 완료');
        } catch (e) {
          print('⚠️ 백그라운드 서비스 시작 실패: $e');
        }
      } else {
        print('✅ 자동매매 상태 정상 (OFF)');
      }
      
      // 4. 앱 시작 시간 기록
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('app_start_time', DateTime.now().toIso8601String());
      } catch (e) {
        print('⚠️ 앱 시작 시간 기록 실패: $e');
      }
      
    } catch (e) {
      print('❌ 자동매매 상태 복원 실패: $e');
    }
  }

  /// 데이터베이스에서 관심종목 로드
  Future<void> _loadWatchlistFromDatabase() async {
    try {
      // getWatchlistWithStockInfo 대신 getWatchlist 사용 (stocks 테이블 의존성 제거)
      final watchlistData = await _watchlistRepository.getWatchlist();
      _watchlist = watchlistData.map((item) => {
        'stock_code': item['stock_code'],
        'stock_name': item['stock_name'],
        'added_at': item['added_at'],
        'memo': item['memo'],
        'market': 'UNKNOWN', // 기본값
      }).toList();
      print('✅ 데이터베이스에서 관심종목 로드: ${_watchlist.length}개');
      
      // 관심종목 상세 출력
      if (_watchlist.isNotEmpty) {
        print('📋 관심종목 상세 목록:');
        for (int i = 0; i < _watchlist.length; i++) {
          final item = _watchlist[i];
          final stockCode = item['stock_code'] ?? 'Unknown';
          final stockName = item['stock_name'] ?? 'Unknown';
          print('  ${i + 1}. $stockCode: $stockName');
        }
      }
    } catch (e) {
      print('❌ 데이터베이스에서 관심종목 로드 실패: $e');
      // 폴백: 기존 SharedPreferences 방식 사용
      await _loadWatchlistFromSharedPreferences();
    }
  }



  /// SharedPreferences에서 관심종목 로드 (폴백)
  Future<void> _loadWatchlistFromSharedPreferences() async {
    try {
      // 올바른 WatchlistRepository 인스턴스 사용
      final watchlistItems = await _watchlistRepository.getWatchlist();
      _watchlist = watchlistItems.map((item) => {
        'stockCode': item['stock_code'],
        'stockName': item['stock_name'],
        'addedAt': item['added_at'],
      }).toList();
      print('✅ SharedPreferences에서 관심종목 로드: ${_watchlist.length}개');
    } catch (e) {
      print('❌ SharedPreferences에서 관심종목 로드 실패: $e');
      _watchlist = [];
    }
  }

  // 계좌 정보
  Map<String, dynamic>? _accountInfo;
  Map<String, dynamic>? get accountInfo => _accountInfo;

  // 거래 내역
  List<Map<String, dynamic>> _tradeHistory = [];
  List<Map<String, dynamic>> get tradeHistory => _tradeHistory;


  // 초기화 완료 여부
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  bool _backgroundWarmupStarted = false;
  bool _suppressBackgroundHeavyTasks = false; // 거래 탭 활성 시 무거운 백그라운드 작업 일시 중지

  /// 앱 데이터 초기화 (최적화된 버전)
  Future<void> initialize() async {
    if (_isInitialized) {
      print('✅ AppDataManager가 이미 초기화되어 있습니다.');
      return;
    }

    try {
      print('🚀 AppDataManager 초기화 시작...');
      
      // 웹 환경에서 데이터베이스 초기화
      if (kIsWeb) {
        print('🌐 웹 환경 감지 - AppDataManager에서 데이터베이스 초기화');
        try {
          // 웹 전용 데이터베이스 초기화
          databaseFactory = databaseFactoryFfiWeb;
          print('✅ AppDataManager에서 웹용 데이터베이스 팩토리 초기화 완료');
        } catch (e) {
          print('❌ AppDataManager에서 웹용 데이터베이스 초기화 실패: $e');
        }
      }
      
      // 0. DB 스키마 오류 해결을 위한 강제 재생성 (필요시에만)
      try {
        // 기존 데이터베이스가 있는지 확인
        final dbPath = await _databaseHelper.database;
        print('✅ 기존 데이터베이스 사용');
      } catch (e) {
        print('🆕 새로운 데이터베이스 생성');
        await _databaseHelper.forceRecreate();
      }
      
      // 중복 알림 정리 (새로 추가된 기능)
      await _cleanupDuplicateNotifications();
      
      // 1. API 설정 초기화
      await ApiConfig.instance.initialize();
      
      // 2. API 설정 유효성 검사
      if (!ApiConfig.instance.isValid) {
        throw Exception('API 설정이 유효하지 않습니다. 설정 화면에서 API 키를 등록해주세요.');
      }
      
      // 3. KisUnifiedApiService 초기화
      final unifiedApiService = KisUnifiedApiService();
      await unifiedApiService.initialize(
        appKey: ApiConfig.instance.appKey!,
        appSecret: ApiConfig.instance.appSecret!,
        accountNumber: ApiConfig.instance.accountNo!,
      );
      print('✅ KisUnifiedApiService 초기화 완료');
      
      // 4. 토큰 발급 (스플래시 블로킹 방지: 비동기로 선발급)
      Future.microtask(() async {
        try {
          await unifiedApiService.initialize(
            appKey: ApiConfig.instance.appKey!,
            appSecret: ApiConfig.instance.appSecret!,
            accountNumber: ApiConfig.instance.accountNo!,
          );
          print('✅ 토큰 선발급 성공');
        } catch (e) {
          print('⚠️ 토큰 선발급 실패(백그라운드): $e');
          // 토큰 발급 실패 시 재시도 로직
          Future.delayed(const Duration(seconds: 30), () async {
            try {
              await _unifiedApiService.initialize(
                appKey: ApiConfig.instance.appKey!,
                appSecret: ApiConfig.instance.appSecret!,
                accountNumber: ApiConfig.instance.accountNo!,
              );
              print('✅ 토큰 재발급 성공');
            } catch (retryError) {
              print('❌ 토큰 재발급 실패: $retryError');
            }
          });
        }
      });
      
      // 5. 필수 데이터만 우선 로드 (스플래시 빠르게)
      await _loadEssentialData();
      
      // 6. 데이터 관리 서비스 시작
      await (_dataManagementService ??= DataManagementService.instance).start();
      
      _isInitialized = true;
      print('✅ AppDataManager 초기화 완료');
      
      // 7. 백그라운드에서 나머지 데이터 로드
      _loadBackgroundData();
      
    } catch (e) {
      print('❌ AppDataManager 초기화 실패: $e');
      rethrow;
    }
  }

  /// 중복 알림 정리 (새로 추가된 기능)
  Future<void> _cleanupDuplicateNotifications() async {
    try {
      print('🧹 중복 알림 정리 시작...');
      await _notificationHistoryRepository.cleanupDuplicateNotifications();
      print('✅ 중복 알림 정리 완료');
    } catch (e) {
      print('⚠️ 중복 알림 정리 실패: $e');
    }
  }

  /// 필수 데이터만 우선 로드 (스플래시 최적화)
  Future<void> _loadEssentialData() async {
    print('⚡ 필수 데이터 로드 시작...');
    
    // 가장 필수적인 작업만 우선 실행
    await _initializeInvestmentStyles();
    
    // 나머지는 백그라운드에서 실행
    Future.microtask(() async {
      try {
        await Future.wait([
          _loadAccountInfo(),
          _loadWatchlist(),
          _loadPositions(),
          _restoreAutoTradingStatus(),
        ]);
        print('✅ 백그라운드 필수 데이터 로드 완료');
      } catch (e) {
        print('⚠️ 백그라운드 필수 데이터 로드 실패: $e');
      }
    });
    
    print('✅ 필수 데이터 로드 완료');
  }

  /// 백그라운드에서 실행할 데이터 로드
  Future<void> _loadBackgroundData() async {
    print('🔄 백그라운드 데이터 로드 시작...');
    
    try {
      if (_suppressBackgroundHeavyTasks) {
        print('⏸️ 거래화면 활성화로 무거운 백그라운드 작업 일시 중지');
        return;
      }
      // 1. 종목 데이터 로드 (필요시에만)
      await _forceLoadStockData();
      
      // 2. 거래 내역 로드
      await _loadTradeHistory();
      
      // 3. 히스토리 데이터 백필은 더 나중에 실행 (매우 무거운 작업)
      Future.delayed(const Duration(minutes: 2), () async {
        try {
          if (_suppressBackgroundHeavyTasks) {
            print('⏸️ 거래화면 활성화로 히스토리 백필 건너뜀');
            return;
          }
          await _backfillHistoricalDataInBackground();
        } catch (e) {
          print('⚠️ 지연된 히스토리 백필 실패: $e');
        }
      });
      
      print('✅ 백그라운드 데이터 로드 완료');
    } catch (e) {
      print('⚠️ 백그라운드 데이터 로드 실패: $e');
    }
  }

  /// 백그라운드에서 히스토리 데이터 백필
  Future<void> _backfillHistoricalDataInBackground() async {
    try {
      if (_suppressBackgroundHeavyTasks) {
        print('⏸️ 거래화면 활성화로 백그라운드 히스토리 백필 중단');
        return;
      }
      final Set<String> codes = {};
      for (final w in _watchlist) {
        final c = (w['stock_code'] ?? w['stockCode'])?.toString();
        if (c != null && c.isNotEmpty) codes.add(c);
      }
      for (final p in _positions) {
        final c = p['stockCode']?.toString();
        if (c != null && c.isNotEmpty) codes.add(c);
      }
      
      if (codes.isNotEmpty) {
        print('📦 백그라운드 히스토리 백필: ${codes.length}종목');
        await _backfillHistoricalBars(codes.toList());
      }
    } catch (e) {
      print('⚠️ 백그라운드 히스토리 백필 실패: $e');
    }
  }

  /// 관심종목 추가 시 백그라운드에서 실행할 작업들 (최적화)
  void _runBackgroundTasksForWatchlistOptimized(String stockCode, String stockName) {
    // 백그라운드에서 실행
    Future.microtask(() async {
      try {
        // 1. DB 저장 (가장 중요)
        await _watchlistRepository.addToWatchlist(
          stockCode: stockCode,
          stockName: stockName,
        );
        print('💾 관심종목 DB 저장 완료: $stockCode');
        
        // 2. 병렬로 무거운 작업들 실행 (순차 실행에서 병렬로 변경)
        await Future.wait([
          // 분석 데이터 미리 로드
          _loadStockDataForCache(stockCode).catchError((e) {
            print('⚠️ 분석 데이터 로드 실패: $stockCode - $e');
          }),
          
          // 100일 히스토리 백필 (성능 개선)
          _backfillHistoricalBars([stockCode], days: 100).catchError((e) {
            print('⚠️ 히스토리 백필 실패: $stockCode - $e');
          }),
        ]);
        
        print('📊 관심종목 백그라운드 작업 완료: $stockCode');
        
        // 3. 시그널 확인 및 알림 (가장 마지막에 실행)
        _checkAndNotifyInitialSignal(stockCode, stockName);
        
      } catch (e) {
        print('⚠️ 관심종목 백그라운드 작업 실패: $stockCode - $e');
      }
    });
  }

  /// 데이터베이스 상태 확인
  Future<void> checkDatabaseStatus() async {
    try {
      final stats = await _databaseHelper.getDatabaseStats();
      print('📊 데이터베이스 상태:');
      for (final entry in stats.entries) {
        print('  - ${entry.key}: ${entry.value}개');
      }
    } catch (e) {
      print('❌ 데이터베이스 상태 확인 실패: $e');
    }
  }

  /// 종목 데이터 강제 로드
  Future<void> _forceLoadStockData() async {
    try {
      print('💪 종목 데이터 강제 로드 시작...');
      
      // 1. StockMasterParser 초기화 (백그라운드에서)
      if (!_stockMasterParser.isInitialized) {
        print('🔄 StockMasterParser 백그라운드 초기화 중...');
        // 백그라운드에서 초기화
        Future.microtask(() async {
          try {
            await _stockMasterParser.initialize();
            print('✅ StockMasterParser 초기화 완료');
          } catch (e) {
            print('⚠️ StockMasterParser 초기화 실패: $e');
          }
        });
      }
      
      // 2. 데이터베이스에서 현재 종목 개수 확인
      final currentCount = await _stockRepository.getStockCount();
      print('📊 현재 데이터베이스 종목 개수: $currentCount개');
      
      // 3. 종목이 부족하면 강제로 저장
      if (currentCount < 1000) {
        print('⚠️ 종목 데이터가 부족합니다. 강제로 종목 데이터를 저장합니다.');
        await saveStockDataToDatabase();
        
        // 4. 저장 후 다시 확인
        final newCount = await _stockRepository.getStockCount();
        print('📊 저장 후 데이터베이스 종목 개수: $newCount개');
        
        if (newCount == 0) {
          print('❌ 종목 데이터 저장이 실패했습니다. 수동으로 종목 데이터를 생성합니다.');
          await createDefaultStockData();
        }
      } else {
        print('✅ 데이터베이스에 충분한 종목 데이터가 있습니다.');
      }
      
      // 5. 캐시에서 종목 이름 로드
      _stockNames = await StockCacheManager.getCachedStockNames();
      print('📈 캐시에서 종목 이름 로드: ${_stockNames.length}개');
      
      // 6. 캐시가 비어있으면 데이터베이스에서 로드
      if (_stockNames.isEmpty) {
        // DB 의존 회피: 초기 구동 시에는 마스터/API 기반으로 점진 구축
        print('⚠️ 캐시가 비어있습니다. DB 로드는 건너뜁니다(초기화 중). @api/마스터 데이터로 점진 구축합니다.');
      }
      
      print('✅ 종목 데이터 강제 로드 완료: ${_stockNames.length}개');
      
    } catch (e) {
      print('❌ 종목 데이터 강제 로드 실패: $e');
    }
  }

  /// 기본 종목 데이터 생성 (수동)
  Future<void> createDefaultStockData() async {
    try {
      print('🔧 기본 종목 데이터 수동 생성 시작...');
      
      // 주요 종목들 수동 생성
      final defaultStocks = [
        {'stock_code': '005930', 'stock_name': '삼성전자', 'market': 'KOSPI', 'sector': '전기전자'},
        {'stock_code': '000660', 'stock_name': 'SK하이닉스', 'market': 'KOSPI', 'sector': '전기전자'},
        {'stock_code': '035420', 'stock_name': 'NAVER', 'market': 'KOSPI', 'sector': '서비스업'},
        {'stock_code': '051910', 'stock_name': 'LG화학', 'market': 'KOSPI', 'sector': '화학'},
        {'stock_code': '006400', 'stock_name': '삼성SDI', 'market': 'KOSPI', 'sector': '전기전자'},
        {'stock_code': '035720', 'stock_name': '카카오', 'market': 'KOSPI', 'sector': '서비스업'},
        {'stock_code': '207940', 'stock_name': '삼성바이오로직스', 'market': 'KOSPI', 'sector': '의약품'},
        {'stock_code': '068270', 'stock_name': '셀트리온', 'market': 'KOSPI', 'sector': '의약품'},
        {'stock_code': '323410', 'stock_name': '카카오뱅크', 'market': 'KOSPI', 'sector': '금융업'},
        {'stock_code': '373220', 'stock_name': 'LG에너지솔루션', 'market': 'KOSPI', 'sector': '전기전자'},
        {'stock_code': '327260', 'stock_name': 'LG에너지솔루션우', 'market': 'KOSPI', 'sector': '전기전자'},
        {'stock_code': '228760', 'stock_name': '삼성전자우', 'market': 'KOSPI', 'sector': '전기전자'},
      ];
      
      await _stockRepository.saveStocks(defaultStocks);
      print('✅ 기본 종목 데이터 저장 완료: ${defaultStocks.length}개');
      
      // 캐시에도 저장
      final stockNames = <String, String>{};
      for (final stock in defaultStocks) {
        stockNames[stock['stock_code']!] = stock['stock_name']!;
      }
      _stockNames = stockNames;
      await StockCacheManager.cacheStockNames(stockNames);
      print('✅ 기본 종목 캐시 저장 완료');
      
    } catch (e) {
      print('❌ 기본 종목 데이터 생성 실패: $e');
    }
  }

  /// 앱 백그라운드에서 점진적 보정/캐싱 수행
  void _startBackgroundWarmupIfNeeded() {
    if (_backgroundWarmupStarted) return;
    _backgroundWarmupStarted = true;
    Future<void>(() async {
      // 남은 코드들 중 한글 없는 항목 위주로 50개씩 배치 보정
      for (int i = 0; i < 10; i++) {
        if (_stockNames.isEmpty) break;
        final batch = getSuspiciousCodes(limit: 50);
        if (batch.isEmpty) break;
        final fixed = await resolveNamesByApi(batch);
        if (fixed.isNotEmpty) {
          _stockNames.addAll(fixed);
          await _symbolStore.setMany(fixed);
        }
        await Future.delayed(const Duration(seconds: 1));
      }
    });
  }

  /// 종목 데이터 로드 (필요한 종목만 로드)
  Future<void> _loadStockData() async {
    try {
      print('📈 종목 데이터 로드 시작...');
      
      // 1. 데이터베이스에서 종목 개수 확인
      final stockCount = await _stockRepository.getStockCount();
      print('📊 데이터베이스 종목 개수: $stockCount개');
      
      if (stockCount == 0) {
        print('⚠️ 데이터베이스에 종목 정보가 없습니다. 종목 정보를 저장합니다.');
        await saveStockDataToDatabase();
      } else {
        print('✅ 데이터베이스에 종목 정보가 이미 있습니다.');
      }
      
      // 2. 캐시에서 종목 이름 로드
      _stockNames = await StockCacheManager.getCachedStockNames();
      print('📈 캐시에서 종목 이름 로드: ${_stockNames.length}개');
      
      // 3. 캐시가 비어있으면 데이터베이스에서 로드
      if (_stockNames.isEmpty) {
        print('⚠️ 캐시가 비어있습니다. 데이터베이스에서 종목 정보를 로드합니다.');
        await _loadStockNamesFromDatabase();
      }
      
      if (_stockNames.isNotEmpty) {
        print('✅ 종목 데이터 사용: ${_stockNames.length}개');
      }
      
      // 종목 데이터 샘플 출력
      if (_stockNames.isNotEmpty) {
        final sampleStocks = _stockNames.entries.take(5).toList();
        print('📈 종목 데이터 샘플:');
        for (final entry in sampleStocks) {
          print('  ${entry.key}: ${entry.value}');
        }
      }
      
      // 심볼 스토어 동기화
      if (_stockNames.isNotEmpty) {
        await _symbolStore.setMany(_stockNames);
      }
    } catch (e) {
      print('❌ 종목 데이터 로드 실패: $e');
      print('❌ 오류 타입: ${e.runtimeType}');
    }
  }

  /// 종목 정보를 데이터베이스에 저장
  Future<void> saveStockDataToDatabase() async {
    try {
      print('💾 종목 정보를 데이터베이스에 저장 시작...');
      
      // 1. StockMasterParser에서 종목 데이터 가져오기
      List<Map<String, dynamic>> allStocks = [];
      
      try {
        print('📡 StockMasterParser에서 종목 정보 로드 중...');
        
        // StockMasterParser 초기화 확인 (중복 초기화 방지)
        if (!_stockMasterParser.isInitialized) {
          print('🔄 StockMasterParser 초기화 중...');
          await _stockMasterParser.initialize();
        } else {
          print('✅ StockMasterParser가 이미 초기화되어 있습니다.');
        }
        
        // 초기화 후에도 데이터가 없으면 경고만 출력 (재초기화는 하지 않음)
        if (_stockMasterParser.getKospiStockCodes().isEmpty && 
            _stockMasterParser.getKosdaqStockCodes().isEmpty &&
            _stockMasterParser.getNasdaqStockCodes().isEmpty) {
          print('⚠️ StockMasterParser에 데이터가 없습니다. 기본 종목 데이터를 생성합니다.');
        }
        
        // 모든 종목 코드 가져오기
        final kospiCodes = _stockMasterParser.getKospiStockCodes();
        final kosdaqCodes = _stockMasterParser.getKosdaqStockCodes();
        final nasdaqCodes = _stockMasterParser.getNasdaqStockCodes();
        
        print('✅ 종목 코드 로드 완료:');
        print('  - KOSPI: ${kospiCodes.length}개');
        print('  - KOSDAQ: ${kosdaqCodes.length}개');
        print('  - NASDAQ: ${nasdaqCodes.length}개');
        
        // 종목 정보를 Map 형태로 변환
        for (final code in kospiCodes) {
          final info = _stockMasterParser.getStockInfo(code);
          if (info != null) {
            allStocks.add({
              'stock_code': code,
              'stock_name': info['name'] ?? '',
              'market': 'KOSPI',
              'sector': info['sector'] ?? '',
            });
          }
        }
        
        for (final code in kosdaqCodes) {
          final info = _stockMasterParser.getStockInfo(code);
          if (info != null) {
            allStocks.add({
              'stock_code': code,
              'stock_name': info['name'] ?? '',
              'market': 'KOSDAQ',
              'sector': info['sector'] ?? '',
            });
          }
        }
        
        for (final code in nasdaqCodes) {
          final info = _stockMasterParser.getStockInfo(code);
          if (info != null) {
            allStocks.add({
              'stock_code': code,
              'stock_name': info['name'] ?? '',
              'market': 'NASDAQ',
              'sector': info['sector'] ?? '',
            });
          }
        }
        
        if (allStocks.isNotEmpty) {
          print('✅ 총 ${allStocks.length}개 종목 데이터 로드 완료');
          
          // 샘플 데이터 출력
          final sampleStocks = allStocks.take(10).toList();
          print('📈 종목 데이터 샘플 (처음 10개):');
          for (final stock in sampleStocks) {
            print('  ${stock['stock_code']}: ${stock['stock_name']} (${stock['market']})');
          }
        } else {
          print('⚠️ 파싱된 종목 데이터가 없습니다.');
          print('🔍 StockMasterParser 상태 확인:');
          print('  - 초기화됨: ${_stockMasterParser.isInitialized}');
          print('  - KOSPI 종목 수: ${kospiCodes.length}');
          print('  - KOSDAQ 종목 수: ${kosdaqCodes.length}');
        }
        
      } catch (e) {
        print('❌ StockMasterParser에서 종목 데이터 로드 실패: $e');
        print('⚠️ 빈 리스트로 시작합니다.');
        allStocks = [];
      }
      
      // 2. 데이터베이스에 저장
      if (allStocks.isNotEmpty) {
        print('💾 데이터베이스에 ${allStocks.length}개 종목 저장 중...');
        await _stockRepository.saveStocks(allStocks);
        print('✅ 종목 정보 저장 완료: ${allStocks.length}개');
        
        // 저장된 종목 개수 확인
        final savedCount = await _stockRepository.getStockCount();
        print('📊 데이터베이스에 저장된 종목 개수: $savedCount개');
        
        // 3. 캐시에도 저장
        final stockNames = <String, String>{};
        for (final stock in allStocks) {
          final code = stock['stock_code']?.toString();
          final name = stock['stock_name']?.toString();
          if (code != null && name != null && name.isNotEmpty) {
            stockNames[code] = name;
          }
        }
        _stockNames = stockNames;
        await StockCacheManager.cacheStockNames(stockNames);
        print('✅ 종목 이름 캐시 저장 완료: ${stockNames.length}개');
        
        // 4. 샘플 캐시 데이터 출력
        if (stockNames.isNotEmpty) {
          final sampleCache = stockNames.entries.take(10).toList();
          print('📈 캐시 데이터 샘플 (처음 10개):');
          for (final entry in sampleCache) {
            print('  ${entry.key}: ${entry.value}');
          }
        }
      } else {
        print('⚠️ 저장할 종목 정보가 없습니다.');
      }
      
    } catch (e) {
      print('❌ 종목 정보 저장 실패: $e');
    }
  }

  /// 데이터베이스에서 종목 이름 로드
  Future<void> _loadStockNamesFromDatabase() async {
    try {
      print('📊 데이터베이스에서 종목 이름 로드 시작...');
      
      final stocks = await _stockRepository.getAllStocks();
      final stockNames = <String, String>{};
      
      for (final stock in stocks) {
        final code = stock['stock_code']?.toString();
        final name = stock['stock_name']?.toString();
        if (code != null && name != null) {
          stockNames[code] = name;
        }
      }
      
      _stockNames = stockNames;
      await StockCacheManager.cacheStockNames(stockNames);
      print('✅ 데이터베이스에서 종목 이름 로드 완료: ${stockNames.length}개');
      
    } catch (e) {
      print('❌ 데이터베이스에서 종목 이름 로드 실패: $e');
    }
  }

  /// 관심종목 로드
  Future<void> _loadWatchlist() async {
    try {
      print('📋 관심종목 로드 시작...');
      
      // 데이터베이스에서 로드 시도
      await _loadWatchlistFromDatabase();
      
      // 여전히 비어있다면 SharedPreferences에서 로드
      if (_watchlist.isEmpty) {
        print('⚠️ 데이터베이스에 관심종목이 없어 SharedPreferences에서 로드 시도...');
        await _loadWatchlistFromSharedPreferences();
      }
      
      print('✅ 관심종목 로드 완료: ${_watchlist.length}개');
      
      // 관심종목 변경 알림 전송
      _watchlistChangeController.add(_watchlist);
      
    } catch (e) {
      print('❌ 관심종목 로드 실패: $e');
      _watchlist = [];
    }
  }

  /// 계좌 정보 로드
  Future<void> _loadAccountInfo() async {
    try {
      if (_unifiedApiService.isAuthenticated) {
        _accountInfo = await _unifiedApiService.getAccountBalanceCompat();
        print('✅ 계좌 정보 로드 완료');
      } else {
        print('⚠️ KisUnifiedApiService가 초기화되지 않았습니다.');
      }
    } catch (e) {
      print('❌ 계좌 정보 로드 실패: $e');
    }
  }

  /// 보유종목 로드 (public 메서드)
  Future<void> loadPositions() async {
    await _loadPositions();
  }

  /// 보유종목 로드 (private 구현) - DB 동기화 포함 - 동시 로드
  Future<void> _loadPositions() async {
    try {
      if (_unifiedApiService.isAuthenticated) {
        print('🔍 AppDataManager: 보유종목 동시 로드 시작...');
        
        // 1) 국내와 해외 보유를 동시에 로드
        final futures = await Future.wait([
          _unifiedApiService.getPositions(),
          _loadOverseasPositions(),
        ]);
        
        final domestic = futures[0];
        final overseas = futures[1];
        
        // 2) 병합 및 0주 필터링
        final allPositions = [...domestic, ...overseas];
        _positions = allPositions.where((position) {
          final hldgQty = position['hldg_qty'];
          final quantity = position['quantity'];
          
          // 안전한 타입 변환
          int qty = 0;
          if (hldgQty != null) {
            if (hldgQty is int) {
              qty = hldgQty;
            } else if (hldgQty is String) {
              qty = int.tryParse(hldgQty) ?? 0;
            }
          } else if (quantity != null) {
            if (quantity is int) {
              qty = quantity;
            } else if (quantity is String) {
              qty = int.tryParse(quantity) ?? 0;
            }
          }
          
          return qty > 0;
        }).toList();
        
        print('✅ AppDataManager: 보유종목 동시 로드 완료: 국내=${domestic.length}, 해외=${overseas.length}, 총=${allPositions.length}개 (0주 필터링 후: ${_positions.length}개)');
        
        // 보유종목 상세 정보 출력
        for (int i = 0; i < _positions.length; i++) {
          final item = _positions[i];
          final currentPrice = item['prpr'] ?? 0.0;
          print('  $i. ${item['stockCode']}: ${item['stockName']} (${item['quantity']}주, 현재가: $currentPrice)');
        }
        
        // 종목명 매핑 개선
        await _improvePositionsStockNames();
        
        // 🔄 NEW: 보유종목 DB 동기화
        await _syncPositionsToDatabase();
        
      } else {
        print('⚠️ KisUnifiedApiService가 초기화되지 않았습니다.');
        _positions = [];
      }
    } catch (e) {
      print('❌ 보유 종목 로드 실패: $e');
      print('❌ 에러 상세: ${e.toString()}');
      print('❌ 에러 스택: ${StackTrace.current}');
      
      // 에러 발생 시 빈 배열로 설정
      // setState(() { // This line was removed as per the new_code, as setState is not in the new_code.
      //   _positions = [];
      // });
      print('✅ 에러 후 빈 보유종목 설정');
    }
    print('💼 _loadHoldings() 함수 종료');
  }

  /// 해외 보유종목 로드 (동시 로드용) - 안정성 강화
  Future<List<Map<String, dynamic>>> _loadOverseasPositions() async {
    try {
      print('🌍 AppDataManager: 해외 보유종목 안정적 로드 시작...');
      
      List<Map<String, dynamic>> allOverseas = [];
      
      // 1. 나스닥 보유종목 로드 (거래소 코드 대체 포함) - 첫 성공 즉시 단락
      List<Map<String, dynamic>> nasdaq = [];
      try {
        print('🇺🇸 나스닥 보유종목 로드 시도 1: OVRS_EXCG_CD=NASD');
        nasdaq = await _unifiedApiService.getOverseasPresentBalanceCompat(exchangeCode: 'NASD');
        print('✅ 나스닥(NASD) present-balance: ${nasdaq.length}개');
        if (nasdaq.isNotEmpty) {
          final sample = nasdaq.first;
          print('🔍 [NASD raw] keys=${sample.keys.toList()}');
          print('🔍 [NASD raw] sample=$sample');
        }
        if (nasdaq.isEmpty) {
          print('🇺🇸 나스닥 보유종목 로드 시도 1b: OVRS_EXCG_CD=NAS');
          final alt = await _unifiedApiService.getOverseasPresentBalanceCompat(exchangeCode: 'NAS');
          if (alt.isNotEmpty) {
            nasdaq = alt;
            final sample = nasdaq.first;
            print('🔍 [NAS raw] keys=${sample.keys.toList()}');
            print('🔍 [NAS raw] sample=$sample');
          }
          print('✅ 나스닥(NAS) present-balance: ${alt.length}개');
        }
        if (nasdaq.isNotEmpty) {
          final normalized = _normalizeOverseasHoldings(nasdaq);
          if (normalized.isNotEmpty) {
            print('🔍 [NASD norm] sample=${normalized.first}');
          }
          nasdaq = await _enrichOverseasPrices(normalized);
          allOverseas.addAll(nasdaq);
          print('🔚 나스닥 보유 단락 반환');
        }
      } catch (e) {
        print('⚠️ 나스닥 present-balance 실패: $e');
      }
      
      // 2. 뉴욕 보유종목 로드 (거래소 코드 대체 포함) - 첫 성공 즉시 단락
      List<Map<String, dynamic>> nyse = [];
      try {
        print('🇺🇸 뉴욕 보유종목 로드 시도 1: OVRS_EXCG_CD=NYSE');
        nyse = await _unifiedApiService.getOverseasPresentBalanceCompat(exchangeCode: 'NYSE');
        print('✅ 뉴욕(NYSE) present-balance: ${nyse.length}개');
        if (nyse.isNotEmpty) {
          final sample = nyse.first;
          print('🔍 [NYSE raw] keys=${sample.keys.toList()}');
          print('🔍 [NYSE raw] sample=$sample');
        }
        if (nyse.isEmpty) {
          print('🇺🇸 뉴욕 보유종목 로드 시도 1b: OVRS_EXCG_CD=NYS');
          final alt = await _unifiedApiService.getOverseasPresentBalanceCompat(exchangeCode: 'NYS');
          if (alt.isNotEmpty) {
            nyse = alt;
            final sample = nyse.first;
            print('🔍 [NYS raw] keys=${sample.keys.toList()}');
            print('🔍 [NYS raw] sample=$sample');
          }
          print('✅ 뉴욕(NYS) present-balance: ${alt.length}개');
        }
        if (nyse.isNotEmpty) {
          nyse = await _enrichOverseasPrices(_normalizeOverseasHoldings(nyse));
          allOverseas.addAll(nyse);
        }
      } catch (e) {
        print('⚠️ 뉴욕 present-balance 실패: $e');
      }
      
      // 3. 모든 해외 보유종목 합치기 (정규화된 결과)
      
      print('✅ AppDataManager: 해외 보유종목 안정적 로드 완료: 나스닥=${nasdaq.length}, 뉴욕=${nyse.length}, 총=${allOverseas.length}');
      
      // 4. 해외 보유종목 상세 정보 출력
      if (allOverseas.isNotEmpty) {
        print('🌍 해외 보유종목 상세 정보:');
        for (int i = 0; i < allOverseas.length; i++) {
          final item = allOverseas[i];
        final stockCode = item['stockCode']?.toString() ?? '';
        final stockName = item['stockName']?.toString() ?? '';
        final quantity = item['quantity'] is int ? item['quantity'] as int : int.tryParse(item['quantity']?.toString() ?? '0') ?? 0;
          final avgPrice = item['avgPrice'] as double? ?? 0.0;
          final currentPrice = item['prpr'] as double? ?? 0.0;
          final profit = item['profit'] as double? ?? 0.0;
          print('  $i. $stockCode: $stockName (${quantity}주, 평균가: \$${avgPrice.toStringAsFixed(2)}, 현재가: \$${currentPrice.toStringAsFixed(2)}, 손익: \$${profit.toStringAsFixed(2)})');
        }
      } else {
        print('ℹ️ 해외 보유종목이 없습니다. (정상적인 상황일 수 있음)');
      }
      
      return allOverseas;
    } catch (e) {
      print('❌ AppDataManager: 해외 보유종목 로드 실패: $e');
      print('❌ 에러 상세: ${e.toString()}');
      print('❌ 에러 스택: ${StackTrace.current}');
      return <Map<String, dynamic>>[];
    }
  }

  /// 해외 보유 응답을 DB 스키마(API 필드명)로 정규화
  List<Map<String, dynamic>> _normalizeOverseasHoldings(List<Map<String, dynamic>> raw) {
    final normalized = raw.map((row) {
      final code = (row['pdno'] ?? row['ovrs_item_cd'] ?? row['ovrs_pdno'] ?? row['ITEM_CD'] ?? row['item_cd'] ?? row['SYMB'] ?? row['symb'] ?? '').toString();
      final name = (row['prdt_name'] ?? row['ovrs_item_name'] ?? row['item_name'] ?? '').toString();
      final qty = _safeInt(row['ovrs_cblc_qty'] ?? row['hldg_qty'] ?? row['quantity'] ?? row['cblc_qty']);
      final avg = _safeDouble(row['pchs_avg_pric'] ?? row['frcr_pchs_avg_pric'] ?? row['avgPrice']);
      // 현재가: present-balance 응답은 now_pric2/ovrs_now_prpr 등이 온다
      final cur = _safeDouble(row['now_pric2'] ?? row['ovrs_now_prpr'] ?? row['now_prpr'] ?? row['prpr'] ?? row['last']);
      final excg = (row['ovrs_excg_cd'] ?? row['EXCD'] ?? row['excd'] ?? '').toString();
      // 평가금액: 응답에 ovrs_stck_evlu_amt가 있으면 우선 사용
      final evluAmt = _safeDouble(row['ovrs_stck_evlu_amt']) > 0
          ? _safeDouble(row['ovrs_stck_evlu_amt'])
          : (qty * cur);
      double profitAmt = _safeDouble(row['frcr_evlu_pfls_amt'] ?? row['evlu_pfls_amt']);
      double profitRt = _safeDouble(row['evlu_pfls_rt']);
      if (profitAmt == 0.0 && avg > 0) {
        profitAmt = (cur - avg) * qty;
      }
      if (profitRt == 0.0 && avg > 0) {
        profitRt = ((cur - avg) / avg) * 100.0;
      }
      return {
        'pdno': code,
        'prdt_name': name,
        'market': 'US',
        'hldg_qty': qty,
        'pchs_avg_pric': avg,
        'prpr': cur,
        'evlu_amt': evluAmt,
        'evlu_pfls_amt': profitAmt,
        'evlu_pfls_rt': profitRt,
        'excg': excg,
      };
    }).toList();
    return normalized;
  }

  /// 해외 보유 현재가 보강 (0이면 API로 한 번만 조회)
  Future<List<Map<String, dynamic>>> _enrichOverseasPrices(List<Map<String, dynamic>> list) async {
    final updated = <Map<String, dynamic>>[];
    for (final h in list) {
      final code = (h['pdno'] as String? ?? '').trim();
      if ((h['prpr'] ?? 0.0) == 0.0 && code.isNotEmpty) {
        try {
          final excg = (h['excg'] as String? ?? '').toUpperCase();
          // KIS 1호가(EXCD) 표준: NAS(나스닥), NYS(뉴욕)
          final exchangeCode = excg.isEmpty
              ? 'NAS'
              : (excg.startsWith('NY') ? 'NYS' : (excg.startsWith('NAS') ? 'NAS' : excg));
          final data = await _unifiedApiService.getOverseasStockPrice(symbol: code, exchangeCode: exchangeCode);
          final last = _extractPrice(data);
          if (last > 0) {
            final qty = _safeInt(h['hldg_qty']);
            h['prpr'] = last;
            h['evlu_amt'] = last * qty;
          }
        } catch (_) {}
      }
      updated.add(h);
    }
    return updated;
  }

  double _extractPrice(Map<String, dynamic>? data) {
    if (data == null) return 0.0;
    final candidates = ['last', 'ovrs_prpr', 'ovrs_prod_prpr', 'prpr', 'close'];
    for (final k in candidates) {
      final v = _safeDouble(data[k]);
      if (v > 0) return v;
    }
    return 0.0;
  }

  int _safeInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  double _safeDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  /// 보유종목 DB 동기화
  Future<void> _syncPositionsToDatabase() async {
    try {
      print('💾 보유종목 DB 동기화 시작...');
      
      if (_positions.isNotEmpty) {
        // HoldingsRepository를 통해 DB에 저장
        await _holdingsRepository.saveHoldings(_positions);
        print('✅ 보유종목 DB 동기화 완료: ${_positions.length}개');
      } else {
        print('⚠️ 보유종목이 없어 DB 동기화를 건너뜁니다.');
      }
    } catch (e) {
      print('❌ 보유종목 DB 동기화 실패: $e');
    }
  }

  /// 분석 결과 DB 저장
  Future<void> saveAnalysisResult(Map<String, dynamic> analysis) async {
    try {
      print('💾 분석 결과 DB 저장 시작: ${analysis['stockCode']}');
      await _analysisRepository.saveAnalysisResult(analysis);
      print('✅ 분석 결과 DB 저장 완료: ${analysis['stockCode']}');
    } catch (e) {
      print('❌ 분석 결과 DB 저장 실패: $e');
    }
  }

  /// 분석 결과 일괄 DB 저장
  Future<void> saveAnalysisResults(List<Map<String, dynamic>> analyses) async {
    try {
      print('💾 분석 결과 일괄 DB 저장 시작: ${analyses.length}개');
      await _analysisRepository.saveAnalysisResults(analyses);
      print('✅ 분석 결과 일괄 DB 저장 완료: ${analyses.length}개');
    } catch (e) {
      print('❌ 분석 결과 일괄 DB 저장 실패: $e');
    }
  }

  /// DB에서 보유종목 조회
  Future<List<Map<String, dynamic>>> getHoldingsFromDatabase() async {
    try {
      print('📊 DB에서 보유종목 조회 시작...');
      final holdings = await _holdingsRepository.getHoldings();
      print('✅ DB에서 보유종목 조회 완료: ${holdings.length}개');
      return holdings;
    } catch (e) {
      print('❌ DB에서 보유종목 조회 실패: $e');
      return [];
    }
  }

  /// DB에서 보유종목 조회 (동기 버전)
  List<Map<String, dynamic>> getHoldingsFromDatabaseSync() {
    try {
      // 메모리에 있는 보유종목 데이터 반환
      if (_positions.isNotEmpty) {
        return List.from(_positions);
      }
      
      // 메모리에 없으면 빈 배열 반환
      return [];
    } catch (e) {
      print('❌ 동기 보유종목 조회 실패: $e');
      return [];
    }
  }

  /// DB에서 최신 분석 결과 조회
  Future<List<Map<String, dynamic>>> getLatestAnalysisResultsFromDatabase() async {
    try {
      print('📊 DB에서 최신 분석 결과 조회 시작...');
      final results = await _analysisRepository.getLatestAnalysisResults();
      print('✅ DB에서 최신 분석 결과 조회 완료: ${results.length}개');
      return results;
    } catch (e) {
      print('❌ DB에서 최신 분석 결과 조회 실패: $e');
      return [];
    }
  }

  /// 특정 종목의 최신 분석 결과 조회
  Future<Map<String, dynamic>?> getLatestAnalysisResultFromDatabase(String stockCode) async {
    try {
      print('📊 DB에서 특정 종목 분석 결과 조회 시작: $stockCode');
      final result = await _analysisRepository.getLatestAnalysisResult(stockCode);
      if (result != null) {
        print('✅ DB에서 특정 종목 분석 결과 조회 완료: $stockCode');
      } else {
        print('⚠️ DB에서 특정 종목 분석 결과 없음: $stockCode');
      }
      return result;
    } catch (e) {
      print('❌ DB에서 특정 종목 분석 결과 조회 실패: $e');
      return null;
    }
  }

  /// 분석 결과 통계 조회
  Future<Map<String, dynamic>> getAnalysisStats() async {
    try {
      print('📊 분석 결과 통계 조회 시작...');
      final stats = await _analysisRepository.getAnalysisStats();
      print('✅ 분석 결과 통계 조회 완료');
      return stats;
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

  /// 보유종목 통계 조회
  Future<Map<String, dynamic>> getHoldingsStats() async {
    try {
      print('📊 보유종목 통계 조회 시작...');
      final stats = await _holdingsRepository.getHoldingsStats();
      print('✅ 보유종목 통계 조회 완료');
      return stats;
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

  /// 보유종목 종목명 매핑 개선
  Future<void> _improvePositionsStockNames() async {
    try {
      print('🔍 AppDataManager: 보유종목 종목명 매핑 개선 시작...');
      
      for (int i = 0; i < _positions.length; i++) {
        final item = _positions[i];
        final stockCode = item['stockCode']?.toString() ?? '';
        
        if (stockCode.isEmpty) continue;
        
        // 현재 종목명 확인
        final currentName = item['stockName']?.toString() ?? '';
        print('📝 AppDataManager: 종목 $i ($stockCode): 현재명=$currentName');
        
        // 종목명이 비어있거나 "Unknown"인 경우 개선
        if (currentName.isEmpty || currentName == 'Unknown' || currentName == stockCode) {
          try {
            // 종목명 조회 (마스터 파서 우선)
            final improvedName = getStockName(stockCode);
            print('📝 AppDataManager: 종목 $i ($stockCode): 개선된명=$improvedName');
            
            if (improvedName.isNotEmpty && improvedName != stockCode) {
              _positions[i]['stockName'] = improvedName;
              print('✅ AppDataManager: 종목명 개선 완료: $stockCode -> $improvedName');
            }
          } catch (e) {
            print('❌ AppDataManager: 종목명 개선 실패 ($stockCode): $e');
          }
        }
      }
      
      print('✅ AppDataManager: 보유종목 종목명 매핑 개선 완료');
    } catch (e) {
      print('❌ AppDataManager: 보유종목 종목명 매핑 개선 실패: $e');
    }
  }

  /// 거래 내역 로드
  Future<void> _loadTradeHistory() async {
    try {
      if (_unifiedApiService != null) {
        _tradeHistory = await _unifiedApiService.getOverseasExecutionsCompat(limit: 100);
        print('✅ 거래 내역 로드 완료: ${_tradeHistory.length}개');
      } else {
        print('⚠️ KisUnifiedApiService가 초기화되지 않았습니다.');
        _tradeHistory = [];
      }
    } catch (e) {
      // 해외주식 거래내역 API가 제공되지 않는 경우 정상적인 상황
      if (e.toString().contains('404')) {
        print('ℹ️ 해외주식 거래내역 API가 제공되지 않습니다. (정상적인 상황)');
      } else {
        print('❌ 거래 내역 로드 실패: $e');
      }
      _tradeHistory = [];
    }
  }

  /// 종목 이름 가져오기
  String getStockName(String stockCode) {
    // 1. 마스터 파서에서 먼저 조회 (실제 종목 데이터)
    final masterName = _stockMasterParser.getStockName(stockCode);
    if (masterName != null && masterName.isNotEmpty) {
      return masterName;
    }
    
    // 2. 데이터베이스에서 종목명 조회
    final dbName = _stockNames[stockCode];
    if (dbName != null && dbName.isNotEmpty) {
      return dbName;
    }
    
    // 3. 최후 수단으로 종목코드 반환
    return stockCode;
  }

  /// 종목 정보 조회
  Map<String, dynamic>? getStockInfo(String stockCode) {
    return _stockMasterParser.getStockInfo(stockCode);
  }

  /// 종목 이름 가져오기 (비동기 - KIS API 포함)
  Future<String> getStockNameAsync(String stockCode) async {
    // 1. 마스터 파서에서 먼저 조회 (실제 종목 데이터)
    final masterName = _stockMasterParser.getStockName(stockCode);
    if (masterName != null && masterName.isNotEmpty) {
      return masterName;
    }
    
    // 2. 데이터베이스에서 종목명 조회
    final dbName = _stockNames[stockCode];
    if (dbName != null && dbName.isNotEmpty) {
      return dbName;
    }
    
    // 3. KIS API에서 실시간 종목명 조회
    try {
      // AppDataManager가 초기화되지 않은 경우 자동으로 초기화
      if (!_unifiedApiService.isAuthenticated) {
        print('🔍 AppDataManager가 초기화되지 않았습니다. 자동으로 초기화를 진행합니다...');
        await initialize();
      }
      
      if (_unifiedApiService != null) {
        final apiName = await _unifiedApiService.getStockName(stockCode);
        if (apiName != null && apiName.isNotEmpty) {
          // 캐시에 저장
          _stockNames[stockCode] = apiName;
          return apiName;
        }
      }
    } catch (e) {
      print('❌ KIS API 종목명 조회 실패: $stockCode - $e');
    }
    
    // 4. 최후 수단으로 종목코드 반환
    return stockCode;
  }


  /// 계좌 잔고 조회 (계좌 정보 + 보유종목)
  Future<Map<String, dynamic>?> getAccountBalance() async {
    try {
      // AppDataManager가 초기화되지 않은 경우 자동으로 초기화
      if (!_unifiedApiService.isAuthenticated) {
        print('🔍 AppDataManager가 초기화되지 않았습니다. 자동으로 초기화를 진행합니다...');
        await initialize();
      }
      
      if (_unifiedApiService != null) {
        print('🔍 계좌 잔고 조회 시작...');
        
        // 1. 통일된 API 서비스로 계좌 정보 조회
        final unifiedApiService = KisUnifiedApiService();
        final accountInfo = await unifiedApiService.getAccountBalanceCompat();
        print('✅ 통일된 API 계좌 정보 조회 완료');
        
        // 2. 보유종목 조회 (국내 + 해외 병합) - 통일된 API 서비스 사용
        List<Map<String, dynamic>> holdings = [];
        print('📊 통일된 API에서 보유종목 데이터 조회 (최신 데이터)...');
        
        // 국내주식 보유 조회
        print('📊 국내주식 보유 조회 시작...');
        final domestic = await unifiedApiService.getPositionsCompat();
        print('📊 국내주식 보유: ${domestic.length}개');
        
        // 해외주식 보유 조회
        print('📊 해외주식 보유 조회 시작...');
        final overseas = await unifiedApiService.getOverseasHoldingsCompat();
        print('📊 해외주식 보유: ${overseas.length}개');
        for (final stock in overseas) {
          print('📊 해외 보유: ${stock['stockCode']} (${stock['stockName']}) - ${stock['quantity']}주');
        }
        
        final allHoldings = [...domestic, ...overseas];
        holdings = allHoldings.where((position) {
          final hldgQty = position['hldg_qty'];
          final quantity = position['quantity'];
          
          // 안전한 타입 변환
          int qty = 0;
          if (hldgQty != null) {
            if (hldgQty is int) {
              qty = hldgQty;
            } else if (hldgQty is String) {
              qty = int.tryParse(hldgQty) ?? 0;
            }
          } else if (quantity != null) {
            if (quantity is int) {
              qty = quantity;
            } else if (quantity is String) {
              qty = int.tryParse(quantity) ?? 0;
            }
          }
          
          return qty > 0;
        }).toList();
        _positions = holdings; // 메모리에 저장
        print('✅ 보유종목 조회 완료: 총 ${allHoldings.length}개 (국내: ${domestic.length}, 해외: ${overseas.length}) → 0주 필터링 후: ${holdings.length}개');
        
        // 3. 종목명 매핑 개선
        await _improvePositionsStockNames();
        
        // 4-a. 보유 DB 저장(화면 공통 소스)
        try {
          await _holdingsRepository.saveHoldings(holdings);
        } catch (e) {
          print('⚠️ 보유종목 DB 저장 실패: $e');
        }

        // 4-b. 달러 잔고 추가 (정확한 조회)
        try {
          print('📊 달러 잔고 조회 시작...');
          
          // 여러 방법으로 달러 잔고 조회 시도
          double usd = 0.0;
          
          // 1. 통일된 API 서비스로 달러 잔고 조회
          try {
            usd = await unifiedApiService.getOverseasPaymentStandardBalance();
            print('📊 통일된 API getAvailableDollar() 결과: \$${usd.toStringAsFixed(2)}');
          } catch (e) {
            print('⚠️ 통일된 API getAvailableDollar() 실패: $e');
          }
          
          // 2. 달러 잔고가 0이거나 실패한 경우 매수가능금액 조회 시도
          if (usd <= 0) {
            try {
              // 해외 매수가능금액 조회
              final buyableAmount = await unifiedApiService.getOverseasBuyableAmountCompat2(exchangeCode: 'NASD', currency: 'USD');
              if (buyableAmount > 0) {
                usd = buyableAmount;
                print('📊 통일된 API getOverseasBuyableAmount() 결과: \$${usd.toStringAsFixed(2)}');
              }
            } catch (e) {
              print('⚠️ 통일된 API getOverseasBuyableAmount() 실패: $e');
            }
          }
          
          // 3. 여전히 0인 경우 결제기준잔고에서 조회
          if (usd <= 0) {
            try {
              final paymt = await _unifiedApiService.getOverseasPaymentStandardBalanceCompat();
              if (paymt > 0) {
                usd = paymt;
                print('📊 getOverseasPaymentStandardBalance() 결과: \$${usd.toStringAsFixed(2)}');
              }
            } catch (e) {
              print('⚠️ getOverseasPaymentStandardBalance() 실패: $e');
            }
          }
          
          print('📊 최종 달러 잔고: \$${usd.toStringAsFixed(2)}');
          
          // accountInfo에 달러 잔고 저장
          if (accountInfo is Map<String, dynamic>) {
            final inner = accountInfo['accountInfo'];
            if (inner is Map<String, dynamic>) {
              inner['availableDollar'] = usd;
              print('✅ 달러 잔고를 inner accountInfo에 저장: \$${usd.toStringAsFixed(2)}');
            } else {
              accountInfo['availableDollar'] = usd;
              print('✅ 달러 잔고를 accountInfo에 저장: \$${usd.toStringAsFixed(2)}');
            }
          }
        } catch (e) {
          print('❌ 달러 잔고 조회 실패: $e');
        }

        // 5. 결과 구성
        final result = {
          'accountInfo': accountInfo ?? {},
          'holdings': holdings,
        };
        
        print('✅ 계좌 잔고 조회 완료: 계좌정보=${accountInfo != null ? '있음' : '없음'}, 보유종목=${holdings.length}개');
        return result;
        
      } else {
        print('⚠️ KisUnifiedApiService가 초기화되지 않았습니다.');
        return null;
      }
    } catch (e) {
      print('❌ 계좌 잔고 조회 실패: $e');
      return null;
    }
  }

  /// 캐시된 주식 데이터 조회
  Map<String, dynamic> getCachedStockData(String stockCode) {
    if (_currentPrices.containsKey(stockCode)) {
      return _currentPrices[stockCode] ?? {};
    }
    return {};
  }

  /// 현재가 업데이트
  void updateCurrentPrice(String stockCode, Map<String, dynamic> priceData) {
    _currentPrices[stockCode] = priceData;
  }

  /// 캐시된 관심종목 데이터 조회
  Map<String, dynamic> getCachedWatchlistData() {
    if (_isCacheExpired(_watchlistCacheTimestamp)) {
      return {};
    }
    return Map.unmodifiable(_watchlistDataCache);
  }

  /// 캐시된 보유종목 데이터 조회
  Map<String, dynamic> getCachedHoldingsData() {
    if (_isCacheExpired(_holdingsCacheTimestamp)) {
      return {};
    }
    return Map.unmodifiable(_holdingsDataCache);
  }

  /// 캐시된 차트 데이터 조회
  List<Map<String, dynamic>> getCachedChartData(String stockCode) {
    if (_isCacheExpired(_chartDataCacheTimestamp)) {
      return [];
    }
    final cachedData = _chartDataCache[stockCode];
    return cachedData != null ? List.from(cachedData) : [];
  }

  /// 차트 데이터 타임스탬프 조회
  DateTime? getChartDataTimestamp(String stockCode) {
    return _chartDataCacheTimestamp;
  }

  /// 차트 데이터 캐시
  void cacheChartData(String stockCode, List<Map<String, dynamic>> chartData) {
    _chartDataCache[stockCode] = List.from(chartData);
    _chartDataCacheTimestamp = DateTime.now();
  }

  /// 캐시된 가격 조회
  Map<String, dynamic>? getCachedPrice(String stockCode) {
    return _currentPrices[stockCode];
  }

  /// 관심종목 여부 확인
  bool isInWatchlist(String stockCode) {
    return _watchlist.any((item) => 
        (item['stock_code'] == stockCode || item['stockCode'] == stockCode));
  }

  /// 모든 보유종목 로드
  Future<List<Map<String, dynamic>>> loadAllHoldings() async {
    try {
      await _loadPositions();
      return List.from(_positions);
    } catch (e) {
      print('❌ 모든 보유종목 로드 실패: $e');
      return [];
    }
  }

  /// 캐시 무효화
  void invalidateCache() {
    _currentPrices.clear();
    _watchlistDataCache.clear();
    _holdingsDataCache.clear();
    _chartDataCache.clear();
  }

  /// 거래 데이터 로드
  Future<void> loadTradingData() async {
    await refreshData();
  }

  /// 데이터 새로고침
  Future<void> refreshData() async {
    await _loadAccountInfo();
    await _loadPositions();
    await _loadTradeHistory();
  }

  /// 시장 데이터 새로고침 (캐시만 관리, 데이터베이스 락 방지)
  Future<void> refreshMarketData() async {
    try {
      // 캐시 무효화만 수행 (실제 데이터 로딩은 RealtimeUpdateService에서 담당)
      // 데이터베이스 락 방지를 위해 비동기로 처리
      Future.microtask(() {
        invalidateCache();
        print('📊 시장 데이터 캐시 무효화 완료 (비동기)');
      });
    } catch (e) {
      print('❌ 시장 데이터 캐시 무효화 실패: $e');
    }
  }




  // 실시간 데이터 미리 로드 메서드들은 RealtimeUpdateService로 이동됨

  /// 캐시 만료 확인
  bool _isCacheExpired(DateTime? timestamp) {
    if (timestamp == null) return true;
    return DateTime.now().difference(timestamp) > _cacheExpiry;
  }




  /// 관심종목 추가 (성능 최적화)
  Future<bool> addToWatchlist(String stockCode, String stockName) async {
    try {
      print('📋 관심종목 추가 시작: $stockCode ($stockName)');
      
      // AppDataManager가 초기화되지 않은 경우 자동으로 초기화
      if (!_unifiedApiService.isAuthenticated) {
        print('🔍 AppDataManager가 초기화되지 않았습니다. 자동으로 초기화를 진행합니다...');
        await initialize();
      }
      
      // 이미 관심종목에 있는지 확인
      final isAlreadyInWatchlist = _watchlist.any((item) => 
          (item['stock_code'] == stockCode || item['stockCode'] == stockCode));
      
      if (isAlreadyInWatchlist) {
        print('⚠️ 이미 관심종목에 존재: $stockCode');
        return true; // 이미 있으면 성공으로 처리
      }
      
      // 즉시 UI 반응을 위해 메모리 캐시에 먼저 추가
      _watchlist.add({
        'stock_code': stockCode,
        'stock_name': stockName,
        'added_at': DateTime.now().millisecondsSinceEpoch,
        'market': 'UNKNOWN',
      });
      
      // 관심종목 변경 알림 즉시 전송 (UI 반응)
      _watchlistChangeController.add(_watchlist);
      
      print('✅ 관심종목 추가 완료 (즉시 반영): $stockCode ($stockName)');
      
      // 백그라운드에서 DB 저장 및 무거운 작업들 실행
      _runBackgroundTasksForWatchlistOptimized(stockCode, stockName);
      
      return true;
    } catch (e) {
      print('❌ 관심종목 추가 실패: $e');
      // 실패 시 메모리 캐시에서 제거
      _watchlist.removeWhere((item) => 
          (item['stock_code'] == stockCode || item['stockCode'] == stockCode));
      _watchlistChangeController.add(_watchlist);
      return false;
    }
  }

  /// 관심종목 추가 시 초기 시그널 확인 및 알림 (최적화)
  Future<void> _checkAndNotifyInitialSignal(String stockCode, String stockName) async {
    try {
      print('📌 관심종목 추가 시 알림 시작: $stockCode ($stockName)');
      
      // 간단한 시그널 확인 (무거운 AI 분석 대신 기본 시그널)
      String currentSignal = '관망';
      
      try {
        // 간단한 분석만 수행 (무거운 100일 분석 제거)
        final ai = UnifiedAnalysisService.instance;
        final analysis = await ai.analyzeStock(stockCode);
        
        if (analysis != null && analysis.isNotEmpty) {
          currentSignal = analysis['signal']?.toString() ?? '관망';
          print('📊 관심종목 추가 시 간단 분석 완료: $stockCode - $currentSignal');
        }
      } catch (e) {
        print('⚠️ 관심종목 추가 시 분석 실패: $stockCode - $e');
      }
      
      // 분석 결과와 함께 알림 표시
      await SignalTracker().onWatchlistAdded(stockCode, stockName, currentSignal);
      
    } catch (e) {
      print('⚠️ 관심종목 추가 시 알림 실패: $stockCode - $e');
    }
  }


  /// 백테스트용 과거 데이터 조회 (200일치)
  Future<List<Map<String, dynamic>>> getBacktestData(String stockCode, {int days = 200}) async {
    try {
      print('📊 백테스트용 과거 데이터 조회: $stockCode ($days일치)');
      
      // ChartDataRepository를 통해 과거 데이터 조회
      final chartData = await _chartDataRepository.getChartData(
        stockCode, 
        limit: days
      );
      
      if (chartData.isEmpty) {
        print('⚠️ $stockCode 과거 데이터 없음 (요청: $days일치)');
        return [];
      }
      
      print('✅ $stockCode 과거 데이터 조회 완료: ${chartData.length}일치');
      return chartData;
      
    } catch (e) {
      print('❌ 백테스트용 과거 데이터 조회 실패: $stockCode - $e');
      return [];
    }
  }



  /// 관심종목 제거
  Future<bool> removeFromWatchlist(String stockCode) async {
    try {
      // AppDataManager가 초기화되지 않은 경우 자동으로 초기화
      if (!_unifiedApiService.isAuthenticated) {
        print('🔍 AppDataManager가 초기화되지 않았습니다. 자동으로 초기화를 진행합니다...');
        await initialize();
      }
      
      // 올바른 WatchlistRepository 인스턴스 사용
      await _watchlistRepository.removeFromWatchlist(stockCode);
      await _loadWatchlist(); // 관심종목 리스트 새로고침
      
      // 시그널 추적에서도 제거
      SignalTracker().removeStock(stockCode);
      
      // 200일 히스토리 삭제
      try {
        await removeHistoricalBarsFor(stockCode);
      } catch (e) {
        print('⚠️ 관심종목 히스토리 삭제 실패: $stockCode - $e');
      }
      
      return true;
    } catch (e) {
      print('❌ 관심종목 제거 실패: $e');
      return false;
    }
  }

  /// 거래 화면 실시간 데이터 로드
  Future<void> loadTradingScreenData() async {
    try {
      _suppressBackgroundHeavyTasks = true; // 거래화면 진입: 무거운 작업 일시 중지
      await Future.wait([
        _loadAccountInfo(),
        _loadPositions(),
        _loadTradeHistory(),
      ]);
      
      print('✅ 거래 화면 실시간 데이터 로드 완료');
    } catch (e) {
      print('❌ 거래 화면 실시간 데이터 로드 실패: $e');
    }
    finally {
      // 거래화면 데이터 로드 이후에도 사용자 체감 성능을 위해 약간 지연 후 재개
      Future.delayed(const Duration(seconds: 10), () {
        _suppressBackgroundHeavyTasks = false;
        print('▶️ 무거운 백그라운드 작업 재개');
      });
    }
  }

  /// 데이터 새로고침 (백그라운드)
  Future<void> refreshDataBackground() async {
    try {
      await _loadAccountInfo();
      await _loadPositions(); // 국내
      try {
        // 해외 보유도 병합 로드(잔고 우선 present-balance → fallback positions)
        List<Map<String, dynamic>> ovNas = await _unifiedApiService.getOverseasPresentBalanceCompat(exchangeCode: 'NASD');
        List<Map<String, dynamic>> ovNy = await _unifiedApiService.getOverseasPresentBalanceCompat(exchangeCode: 'NYSE');
        if (ovNas.isEmpty && ovNy.isEmpty) {
          ovNas = await _unifiedApiService.getOverseasPresentBalanceCompat(exchangeCode: 'NASD');
          ovNy = await _unifiedApiService.getOverseasPresentBalanceCompat(exchangeCode: 'NYSE');
        }
        _positions = [..._positions, ...ovNas, ...ovNy];
        // 병합 보유를 DB에 저장
        await _syncPositionsToDatabase();
      } catch (_) {}
      await _loadTradeHistory();

      // 해외 체결내역을 가져와 내역 DB에 역주입(과거 체결 복구)
      try {
        final overseasExecs = await _unifiedApiService.getOverseasExecutionsCompat(limit: 100);
        if (overseasExecs.isNotEmpty) {
          final repo = _tradeHistoryRepository;
          for (final e in overseasExecs) {
            await repo.insertTradeHistory(
              stockCode: e['stockCode'] ?? '',
              stockName: e['stockName'] ?? (await getStockNameAsync(e['stockCode'] ?? '')),
              orderType: e['orderType'] ?? '매수',
              quantity: (e['quantity'] ?? 0) as int,
              price: (e['price'] ?? 0.0) as double,
              totalAmount: (e['totalAmount'] ?? 0.0) as double,
              orderDate: e['orderDate'] ?? _today(),
              orderTime: e['orderTime'] ?? _nowHm(),
              isAutoTrade: false,
            );
          }
          print('✅ 해외 체결내역 역주입 완료: ${overseasExecs.length}건');
        }

        // 기간 체결(최근 7일) 보강
        final start = _daysAgo(7);
        final end = _todayCompact();
        final periodList = await _unifiedApiService.getOverseasPeriodTransactions(startDate: start, endDate: end, exchangeCode: 'NASD');
        for (final e in periodList) {
          await _tradeHistoryRepository.insertTradeHistory(
            stockCode: e['stockCode'] ?? '',
            stockName: e['stockName'] ?? (await getStockNameAsync(e['stockCode'] ?? '')),
            orderType: e['orderType'] ?? '매수',
            quantity: (e['quantity'] ?? 0) as int,
            price: (e['price'] ?? 0.0) as double,
            totalAmount: (e['totalAmount'] ?? 0.0) as double,
            orderDate: e['orderDate'] ?? _today(),
            orderTime: e['orderTime'] ?? _nowHm(),
            isAutoTrade: false,
          );
        }
      } catch (e) {
        // 해외주식 거래내역 API가 제공되지 않는 경우 정상적인 상황
        if (e.toString().contains('404')) {
          print('ℹ️ 해외주식 거래내역 API가 제공되지 않습니다. (정상적인 상황)');
        }
        print('⚠️ 해외 체결내역 역주입 실패: $e');
      }

      // 거래 상태 재구성(보유/완료 카운팅 포함)
      try {
        await TradeStatusTracker().rebuildTradeStatuses();
      } catch (e) {
        print('⚠️ 거래 상태 재구성 실패: $e');
      }
      
      print('✅ 데이터 새로고침 완료');
    } catch (e) {
      print('❌ 데이터 새로고침 실패: $e');
    }
  }

  String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
  String _nowHm() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }
  String _todayCompact() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  }
  String _daysAgo(int d) {
    final t = DateTime.now().subtract(Duration(days: d));
    return '${t.year}${t.month.toString().padLeft(2, '0')}${t.day.toString().padLeft(2, '0')}';
  }

  /// API 가이드 엑셀 로드(옵션) - 필요시 매핑용
  Future<void> loadApiGuideFromExcelIfNeeded() async {
    try {
      // 여유가 있을 때만 읽도록 선택적으로 사용 (지금은 설정/디버그에서 호출 가능)
      // 최적화를 위해 상수화 혹은 캐시 권장
      // final bytes = await rootBundle.load('assets/open-trading-api-main/open-trading-api-main/stocks_info/api_guide.xlsx');
      // final excel = Excel.decodeBytes(bytes.buffer.asUint8List());
      // print('📘 API GUIDE 시트: ${excel.tables.keys}');
    } catch (e) {
      print('⚠️ API 가이드 엑셀 로드 실패: $e');
    }
  }

    /// 종목 검색 (마스터 데이터 사용)
  Future<List<Map<String, dynamic>>> searchStocks(
    String query, {
    int offset = 0,
    int limit = 10, // 10개씩 페이징
  }) async {
    try {
      final String q = query.trim();
      print('🔎 searchStocks | query="$q" offset=$offset limit=$limit');
      
      // 1. StockMasterParser 초기화 확인
      if (!_stockMasterParser.isInitialized) {
        print('🔄 StockMasterParser 초기화 중...');
        await _stockMasterParser.initialize();
      }
      
      // 2. 마스터 파서에서 종목 검색
      final results = _stockMasterParser.searchStocks(q, offset: offset, limit: limit);
      
      // 3. 결과가 없으면 기본 종목들에서 검색
      if (results.isEmpty) {
        print('⚠️ 마스터 데이터에서 검색 결과가 없습니다. 기본 종목들에서 검색합니다.');
        final defaultResults = _searchInDefaultStocks(q);
        if (defaultResults.isNotEmpty) {
          print('✅ 기본 종목에서 검색 결과 발견: ${defaultResults.length}개');
          return defaultResults;
        }
      }
      
      // 4. 결과 형식 변환
      final List<Map<String, dynamic>> formattedResults = results.map((stock) {
        final code = stock['code']?.toString() ?? '';
        final name = stock['name']?.toString() ?? '';
        final market = stock['market']?.toString() ?? _classifyMarket(code);
        
        print('📝 Master stock: $code -> $name ($market)');
        
        return {
          'stockCode': code,
          'stockName': name,
          'market': market,
        };
      }).toList();
      
      print('✅ 마스터 데이터 기반 종목 검색 완료: ${formattedResults.length}개');
      return formattedResults;
    } catch (e) {
      print('❌ 종목 검색 실패: $e');
      // 오류 발생 시 기본 종목들에서 검색
      print('🔄 오류로 인해 기본 종목들에서 검색합니다.');
      return _searchInDefaultStocks(query.trim());
    }
  }

  /// 기본 종목들에서 검색
  List<Map<String, dynamic>> _searchInDefaultStocks(String query) {
    final String q = query.toLowerCase();
    final List<Map<String, dynamic>> results = [];
    
    // 기본 KOSPI 종목들
    final defaultKospiStocks = {
      '005930': '삼성전자',
      '000660': 'SK하이닉스',
      '035420': 'NAVER',
      '051910': 'LG화학',
      '006400': '삼성SDI',
      '035720': '카카오',
      '207940': '삼성바이오로직스',
      '068270': '셀트리온',
      '323410': '카카오뱅크',
      '373220': 'LG에너지솔루션',
    };
    
    // 기본 KOSDAQ 종목들
    final defaultKosdaqStocks = {
      '091990': '셀트리온헬스케어',
      '068760': '셀트리온제약',
      '086520': '에코프로',
      '096770': 'SK이노베이션',
      '018260': '삼성에스디에스',
      '017670': 'SK텔레콤',
      '028260': '삼성물산',
      '034020': '두산에너빌리티',
      '015760': '한국전력',
      '003670': '포스코퓨처엠',
    };
    

    
    // KOSPI 검색
    for (final entry in defaultKospiStocks.entries) {
      if (entry.key.contains(q) || entry.value.toLowerCase().contains(q)) {
        results.add({
          'stockCode': entry.key,
          'stockName': entry.value,
          'market': 'KOSPI',
        });
      }
    }
    
    // KOSDAQ 검색
    for (final entry in defaultKosdaqStocks.entries) {
      if (entry.key.contains(q) || entry.value.toLowerCase().contains(q)) {
        results.add({
          'stockCode': entry.key,
          'stockName': entry.value,
          'market': 'KOSDAQ',
        });
      }
    }
    
    // NASDAQ 검색 - 실제 데이터베이스에서 검색
    try {
      final stockMasterParser = StockMasterParser();
      if (stockMasterParser.isInitialized) {
        final nasdaqStocks = stockMasterParser.getNasdaqStockCodes();
        for (final code in nasdaqStocks) {
          final info = stockMasterParser.getStockInfo(code);
          if (info != null) {
            final name = info['name']?.toString() ?? '';
            if (code.toLowerCase().contains(q) || name.toLowerCase().contains(q)) {
              results.add({
                'stockCode': code,
                'stockName': name,
                'market': 'NASDAQ',
              });
            }
          }
        }
      }
    } catch (e) {
      print('⚠️ NASDAQ 종목 검색 실패: $e');
    }
    
    return results;
  }


  /// API 응답에서 종목명 추출 (인코딩 문제 해결)
  String _resolveStockName(Map<String, dynamic> stockData) {
    final candidates = [
      stockData['stockName']?.toString(),
      stockData['hts_kor_isnm']?.toString(),
      stockData['hts_kor_isnm1']?.toString(),
      stockData['prdt_name']?.toString(),
    ];

    for (final candidate in candidates) {
      if (candidate != null && candidate.isNotEmpty) {
        // 한글이 포함되어 있고 깨진 문자가 없으면 사용
        if (_hasHangul(candidate) && !candidate.contains('')) {
          return candidate;
        }
      }
    }
    
    // 모든 API 응답이 깨졌으면 종목코드 반환
    return stockData['stockCode']?.toString() ?? '';
  }

  /// 한글 포함 여부 확인
  bool _hasHangul(String text) {
    return RegExp(r'[가-힣]').hasMatch(text);
  }

  /// 시장 분류
  String _classifyMarket(String code) {
    // 나스닥 종목 확인 (1-5자리 알파벳)
    if (RegExp(r'^[A-Z]{1,5}$').hasMatch(code)) {
      return 'NASDAQ';
    }
    // 국내 종목 분류
    return code.startsWith('0') ? 'KOSPI' : 'KOSDAQ';
  }

  /// 기본 종목명 제공 (마스터 데이터 사용)
  String _getDefaultStockName(String code) {
    try {
      final stockMasterParser = StockMasterParser();
      if (stockMasterParser.isInitialized) {
        final stockName = stockMasterParser.getStockName(code);
        if (stockName != null && stockName.isNotEmpty) {
          return stockName;
        }
      }
    } catch (e) {
      print('❌ 마스터 데이터에서 종목명 조회 실패: $e');
    }
    return code; // 기본 종목명이 없으면 종목코드 반환
  }

  /// API로 종목명 보정 (인코딩 이슈시 대체)
  Future<Map<String, String>> resolveNamesByApi(List<String> codes) async {
    final Map<String, String> codeToName = {};
    for (final code in codes) {
      try {
        final data = await _unifiedApiService?.getStockPrice(code);
        final name = (data != null && data['stockName'] != null) ? data!['stockName']?.toString() ?? '' : '';
        if (name.isNotEmpty) codeToName[code] = name;
      } catch (_) {
        // ignore per item
      }
      await Future.delayed(const Duration(milliseconds: 80)); // 레이트 제한 가드(짧게)
    }
    return codeToName;
  }

  /// 의심스러운(한글 없음) 종목명 보정 대상 코드 추출
  List<String> getSuspiciousCodes({int limit = 20}) {
    final List<String> picked = [];
    for (final entry in _stockNames.entries) {
      final name = entry.value;
      final hasHangul = RegExp(r'[가-힣]').hasMatch(name);
      if (!hasHangul) {
        picked.add(entry.key);
        if (picked.length >= limit) break;
      }
    }
    return picked;
  }

  /// 지정된 코드들에 대해 백그라운드로 이름 보정 및 저장
  Future<void> warmupNamesForCodes(List<String> codes, {int batchSize = 50}) async {
    if (codes.isEmpty) return;
    final List<String> pending = [];
    for (final code in codes) {
      final current = _stockNames[code] ?? '';
      final hasHangul = RegExp(r'[가-힣]').hasMatch(current);
      if (!hasHangul || current.isEmpty) {
        pending.add(code);
      }
      if (pending.length >= batchSize) {
        final fixed = await resolveNamesByApi(pending);
        if (fixed.isNotEmpty) {
          _stockNames.addAll(fixed);
          await _symbolStore.setMany(fixed);
        }
        pending.clear();
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
    if (pending.isNotEmpty) {
      final fixed = await resolveNamesByApi(pending);
      if (fixed.isNotEmpty) {
        _stockNames.addAll(fixed);
        await _symbolStore.setMany(fixed);
      }
    }
  }


  /// 관심종목 실시간 데이터 미리 로드 (스플래시용)
  Future<void> preloadWatchlistData() async {
    try {
      print('📋 관심종목 실시간 데이터 미리 로드 시작...');
      
      // 관심종목 목록 가져오기
      final watchlist = await getWatchlist();
      if (watchlist.isEmpty) {
        print('⚠️ 관심종목이 비어있습니다');
        return;
      }

      // API 인증 확인
      if (_unifiedApiService == null || !_unifiedApiService.isAuthenticated) {
        print('⚠️ API 미인증 - 관심종목 데이터 로드 건너뜀');
        return;
      }

      // 각 관심종목의 실시간 데이터 조회
      final List<Future<void>> futures = [];
      for (final item in watchlist) {
        final stockCode = item['stock_code']?.toString();
        if (stockCode != null && stockCode.isNotEmpty) {
          futures.add(_loadStockDataForCache(stockCode));
        }
      }

      // 병렬로 데이터 로드
      await Future.wait(futures);
      _watchlistCacheTimestamp = DateTime.now();
      
      print('✅ 관심종목 실시간 데이터 미리 로드 완료: ${_watchlistDataCache.length}개');
    } catch (e) {
      print('❌ 관심종목 실시간 데이터 미리 로드 실패: $e');
    }
  }

  /// 보유종목 실시간 데이터 미리 로드 (스플래시용)
  Future<void> preloadHoldingsData() async {
    try {
      print('💼 보유종목 실시간 데이터 미리 로드 시작...');
      
      // API 인증 확인
      if (_unifiedApiService == null || !_unifiedApiService.isAuthenticated) {
        print('⚠️ API 미인증 - 보유종목 데이터 로드 건너뜀');
        return;
      }

      // 보유종목 목록 조회
      final holdings = await _unifiedApiService.getPositions();
      if (holdings.isEmpty) {
        print('⚠️ 보유종목이 없습니다');
        return;
      }

      // 각 보유종목의 실시간 데이터 조회
      final List<Future<void>> futures = [];
      for (final holding in holdings) {
        final stockCode = holding['stockCode']?.toString();
        if (stockCode != null && stockCode.isNotEmpty) {
          futures.add(_loadStockDataForCache(stockCode));
        }
      }

      // 병렬로 데이터 로드
      await Future.wait(futures);
      _holdingsCacheTimestamp = DateTime.now();
      
      print('✅ 보유종목 실시간 데이터 미리 로드 완료: ${_holdingsDataCache.length}개');
    } catch (e) {
      print('❌ 보유종목 실시간 데이터 미리 로드 실패: $e');
    }
  }

  /// 개별 종목 데이터를 캐시에 로드
  Future<void> _loadStockDataForCache([String? stockCode]) async {
    try {
      // stockCode가 제공되지 않은 경우 관심종목 전체 처리
      if (stockCode == null) {
        for (final stock in _watchlist) {
          final code = stock['stockCode']?.toString();
          if (code != null) {
            await _loadStockDataForCache(code);
          }
        }
        return;
      }
      
      // 실시간 가격 데이터 조회
      final priceData = await _unifiedApiService?.getStockPrice(stockCode);
      if (priceData != null) {
        // 메모리 캐시에 저장
        _watchlistDataCache[stockCode] = priceData;
        _holdingsDataCache[stockCode] = priceData;
        
        // 데이터베이스에 저장 (중복 방지를 위해 한 번만 저장)
        try {
          await _realtimeDataRepository.saveRealtimeData(
            stockCode: stockCode,
            market: 'UNKNOWN',
            currentPrice: _toDouble(priceData['prpr']),
            prevClose: _toDouble(priceData['stck_prdy_clpr']),
            changeAmount: _toDouble(priceData['diff']),
            changeRate: _toDouble(priceData['rate']),
            volume: (priceData['acml_vol'] ?? 0).toInt(),
            tradeAmount: _toDouble(priceData['tradeAmount'] ?? priceData['amount']),
            highPrice: _toDouble(priceData['high']),
            lowPrice: _toDouble(priceData['low']),
            openPrice: _toDouble(priceData['open']),
            marketCap: priceData['marketCap'] != null ? _toDouble(priceData['marketCap']) : null,
            per: priceData['per'] != null ? _toDouble(priceData['per']) : null,
            pbr: priceData['pbr'] != null ? _toDouble(priceData['pbr']) : null,
          );
          print('📊 종목 데이터 캐시 및 DB 저장: $stockCode');
        } catch (dbError) {
          print('⚠️ 데이터베이스 저장 실패: $stockCode - $dbError');
        }
      }
    } catch (e) {
      print('❌ 종목 데이터 캐시 로드 실패: $stockCode - $e');
    }
  }


  /// 캐시 새로고침 (수동 새로고침용)
  Future<void> refreshCache() async {
    print('🔄 캐시 새로고침 시작...');
    await preloadWatchlistData();
    await preloadHoldingsData();
    print('✅ 캐시 새로고침 완료');
  }

  /// 데이터베이스에서 실시간 데이터 가져오기
  Future<Map<String, dynamic>?> getRealtimeDataFromDatabase(String stockCode) async {
    try {
      return await _realtimeDataRepository.getLatestRealtimeData(stockCode);
    } catch (e) {
      print('❌ 데이터베이스에서 실시간 데이터 조회 실패: $stockCode - $e');
      return null;
    }
  }

  /// 데이터베이스에서 관심종목 실시간 데이터 일괄 가져오기
  Future<List<Map<String, dynamic>>> getWatchlistRealtimeDataFromDatabase() async {
    try {
      final watchlist = await getWatchlist();
      final stockCodes = watchlist.map((item) => item['stock_code']?.toString() ?? '').where((code) => code.isNotEmpty).toList();
      
      if (stockCodes.isEmpty) return [];
      
      return await _realtimeDataRepository.getWatchlistRealtimeData(stockCodes);
    } catch (e) {
      print('❌ 데이터베이스에서 관심종목 실시간 데이터 조회 실패: $e');
      return [];
    }
  }

  /// 데이터베이스 통계 조회
  Future<Map<String, dynamic>> getDatabaseStats() async {
    try {
      final stats = await _databaseHelper.getDatabaseStats();
      final realtimeStats = await _realtimeDataRepository.getRealtimeDataStats();
      
      return {
        'tables': stats,
        'realtime_data': realtimeStats,
      };
    } catch (e) {
      print('❌ 데이터베이스 통계 조회 실패: $e');
      return {};
    }
  }

  /// 캐시 정리
  Future<void> cleanupDatabase() async {
    try {
      print('🧹 데이터베이스 정리 시작...');
      
      // 오래된 데이터 정리
      await _realtimeDataRepository.deleteOldData(before: DateTime.now().subtract(const Duration(days: 7)));
      await _holdingsRepository.cleanupOldHoldings(daysToKeep: 30);
      await _analysisRepository.cleanupOldAnalysisResults(daysToKeep: 30);
      await _tradeHistoryRepository.cleanupOldTradeHistory(daysToKeep: 90);
      
      print('✅ 데이터베이스 정리 완료');
    } catch (e) {
      print('❌ 데이터베이스 정리 실패: $e');
    }
  }

  /// 백그라운드 시장 데이터 새로고침
  Future<void> refreshMarketDataBackground() async {
    try {
      // 관심/보유 종목의 200일 일봉 수집 및 저장
      try {
        final Set<String> codes = {};
        for (final w in _watchlist) {
          final c = (w['stock_code'] ?? w['stockCode'])?.toString();
          if (c != null && c.isNotEmpty) codes.add(c);
        }
        for (final p in _positions) {
          final c = p['stockCode']?.toString();
          if (c != null && c.isNotEmpty) codes.add(c);
        }
        if (codes.isNotEmpty) {
          await _backfillHistoricalBars(codes.toList());
          print('HIST200_INIT codes=${codes.length}');
        }
      } catch (e) {
        print('⚠️ 200일 히스토리 수집 실패: $e');
      }
      
      // 캐시 정리
      await cleanupDatabase();
      
      print('✅ 백그라운드 시장 데이터 새로고침 완료');
      
    } catch (e) {
      print('❌ 백그라운드 시장 데이터 새로고침 실패: $e');
      rethrow;
    }
  }

  Future<void> _backfillHistoricalBars(List<String> stockCodes, {int days = 100}) async {
    if (!_unifiedApiService.isAuthenticated) return;
    final unifiedApiService = _unifiedApiService;
    for (final code in stockCodes) {
      try {
        final info = getStockInfo(code);
        final market = (info?['market']?.toString().toUpperCase() ?? (RegExp(r'^[A-Z]{1,5}$').hasMatch(code) ? 'NASDAQ' : 'KOSPI'));
        List<Map<String, dynamic>> bars;
        if (market == 'NASDAQ' || market == 'NYSE') {
          bars = await unifiedApiService.getOverseasDailyChart(
            symbol: code,
            exchangeCode: 'NAS',
            count: days + 20,
          );
        } else {
          bars = await unifiedApiService.getDomesticDailyChart(
            stockCode: code,
            count: days + 20,
          );
        }
        // bars: {date, open, high, low, close, volume}
        if (bars.isNotEmpty) {
          final first = bars.first['date'];
          final last = bars.last['date'];
          final firstVolume = bars.first['volume'];
          final lastVolume = bars.last['volume'];
          print('HIST${days}_FETCH $code market=$market n=${bars.length} first=$first last=$last');
          print('🔍 [거래량 디버깅] $code 첫 번째 거래량: $firstVolume');
          print('🔍 [거래량 디버깅] $code 마지막 거래량: $lastVolume');
        } else {
          print('HIST${days}_FETCH $code market=$market n=0');
        }
        // 저장
        await _historicalDataRepository.upsertDailyBars(
          stockCode: code,
          market: market,
          bars: bars.map((e) => {
            'date': (e['date'] ?? '').toString().replaceAll('-', ''),
            'open': (e['open'] ?? 0.0).toDouble(),
            'high': (e['high'] ?? 0.0).toDouble(),
            'low': (e['low'] ?? 0.0).toDouble(),
            'close': (e['close'] ?? 0.0).toDouble(),
            'volume': (e['volume'] ?? 0).toInt(),
          }).toList(),
          keepDays: days,
        );
      } catch (e) {
        print('⚠️ $code 히스토리 저장 실패: $e');
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<void> removeHistoricalBarsFor(String stockCode) async {
    try {
      await _historicalDataRepository.deleteByStockCode(stockCode);
      print('🧹 $stockCode 200일 히스토리 삭제 완료');
    } catch (e) {
      print('⚠️ $stockCode 200일 히스토리 삭제 실패: $e');
    }
  }

  /// 투자 스타일 설정 초기화
  Future<void> _initializeInvestmentStyles() async {
    try {
      print('🔄 투자 스타일 설정 초기화 시작...');
      final repository = InvestmentStyleRepository();
      await repository.initializeDefaultStyles();
      print('✅ 투자 스타일 설정 초기화 완료');
    } catch (e) {
      print('❌ 투자 스타일 설정 초기화 실패: $e');
    }
  }



  /// 헬퍼 메서드: 동적 값을 double로 변환
  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  /// 헬퍼 메서드: 나스닥 종목인지 확인
  bool _isNasdaqStock(String stockCode) {
    return RegExp(r'^[A-Z]{1,6}$').hasMatch(stockCode);
  }

}

