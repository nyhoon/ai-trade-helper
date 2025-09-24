import 'utils/analysis_reason_utils.dart';
import 'utils/indicator_utils.dart';
import 'widgets/loading_section.dart';
import 'utils/signal_helpers.dart';
import 'utils/datetime_utils.dart';
import 'utils/style_utils.dart';
import 'widgets/recommended_tab.dart';
import 'utils/trade_status_actions.dart';
import 'utils/signal_summary_utils.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import '../../core/api/kis_unified_api_service.dart';
import '../../core/remote/remote_kis_service.dart';
import '../../core/remote/analysis_functions_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/data/app_data_manager.dart';
import '../../core/data/unified_stock_data_manager.dart';
import '../../core/trading/investment_style_manager.dart';
import '../../core/trading/investment_style.dart';
import '../../core/widgets/gradient_app_bar.dart';
import '../../core/utils/formatters.dart';
import '../../core/database/repositories/watchlist_repository.dart';
import '../../core/config/api_config.dart';
import 'package:intl/intl.dart';
// import '../../core/trading/auto_trading_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import '../../core/trading/style_based_trading_service.dart';
import '../../core/services/signal_tracker.dart';
import '../../core/services/trade_status_tracker.dart' show TradeStatusTracker, TradeStatus;
import '../../core/services/local_notification_manager.dart';
import '../../core/analysis/unified_analysis_service.dart';
import '../../core/database/repositories/notification_history_repository.dart';
import '../../core/trading/market_time_validator.dart';
import '../../core/database/database_helper.dart';
import '../../core/database/repositories/realtime_data_repository.dart';
import '../../core/database/repositories/historical_data_repository.dart';
import '../../core/database/repositories/current_price_repository.dart';
import '../../core/services/recommended_stocks_service.dart';
import 'stock_price_dialog.dart';
import '../trading/recommended_stocks_screen.dart';
import 'widgets/analysis_data_tab.dart';
import 'widgets/analysis_overlays.dart';
import 'widgets/analysis_section.dart';
import 'widgets/analysis_list.dart';
import 'widgets/analysis_card.dart';
import 'widgets/stock_header.dart';
import 'widgets/holdings_info.dart';
import 'widgets/colored_signal_summary.dart';
import 'widgets/integrated_analysis_section.dart';
import 'widgets/technical_indicators_section.dart';
import 'widgets/watchlist_tab.dart';
import 'widgets/holdings_tab.dart';
import 'widgets/api_setup_guide.dart';
import 'utils/analysis_formatters.dart';
import 'widgets/investment_style_info.dart';
import 'widgets/no_api_message.dart';
import 'widgets/analysis_item.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> with TickerProviderStateMixin {
  // KisApiService 제거됨 - KisUnifiedApiService 사용
  final KisUnifiedApiService _unifiedApiService = KisUnifiedApiService();
  final AnalysisFunctionsService _analysisFunctionsService = AnalysisFunctionsService();
  final UnifiedAnalysisService _unifiedAnalysis = UnifiedAnalysisService.instance;
  final InvestmentStyleManager _styleManager = InvestmentStyleManager();
  final UnifiedStockDataManager _unifiedDataManager = UnifiedStockDataManager.instance;
  bool _isAutoTradingEnabled = false;
  
  // 탭 컨트롤러
  late TabController _tabController;
  
  // 데이터 상태
  List<Map<String, dynamic>> _watchlistItems = [];
  List<Map<String, dynamic>> _holdingsItems = [];
  List<Map<String, dynamic>> _recommendedStocks = [];
  Map<String, Map<String, dynamic>> _currentPrices = {};
  Map<String, Map<String, dynamic>> _analysisResults = {};
  
  // 캐시된 실시간 데이터
  Map<String, Map<String, dynamic>> _watchlistDataCache = {};
  Map<String, Map<String, dynamic>> _holdingsDataCache = {};
  Map<String, Map<String, dynamic>> _recommendedStocksCache = {};
  
  // UI 상태
  bool _isLoading = true;
  bool _isFirstLoading = true; // 첫 진입 로딩 상태 유지
  bool _isSelectionMode = false;
  Set<String> _selectedItems = {};
  bool _needsRefresh = false; // UI 강제 새로고침 플래그
  // 세션 전환 감지용 상태 (종목별 장중 여부 스냅샷)
  final Map<String, bool> _prevTradingStates = {};
  
  // AI 추천 분석 진행률 상태
  bool _isAnalyzingRecommendedStocks = false;
  int _currentProgress = 0;
  int _totalProgress = 0;
  String _currentAnalyzingSymbol = '';
  String _currentAnalyzingName = '';
  
  // 실시간 분석 타이머 (차트 데이터 포함)
  Timer? _analysisTimer;
  static const Duration _analysisInterval = Duration(minutes: 1); // 3분으로 변경 (차트 데이터 조회)
  
  // 빠른 업데이트 타이머 (현재가만)
  Timer? _quickUpdateTimer;
  static const Duration _quickUpdateInterval = Duration(seconds: 5); // 5초마다 현재가만 업데이트
  
  // 데이터 정리 타이머
  Timer? _cleanupTimer;
  static const Duration _cleanupInterval = Duration(hours: 1); // 1시간마다 데이터 정리
  
  // 현재 투자 스타일
  InvestmentStyle _currentStyle = InvestmentStyle.moderate;
  
  // 투자 스타일 변경 리스너
  StreamSubscription? _styleSubscription;
  
  // 관심종목 변경 리스너
  StreamSubscription? _watchlistChangeSubscription;
  
  // 거래 상태 추적기
  final TradeStatusTracker _tradeStatusTracker = TradeStatusTracker();
  StreamSubscription? _tradeStatusSubscription;
  
  // 시그널 시간 추적
  Map<String, DateTime> _signalTimestamps = {};
  Map<String, String> _lastSignals = {};
  // 최근 주문 시도 시간 (중복 방지)
  final Map<String, DateTime> _lastTradeAttemptTimes = {};
  
  // 커스터마이징 모드 상태
  bool _isCustomMode = false;
  
  // 스크롤 위치 유지를 위한 컨트롤러들
  final ScrollController _watchlistScrollController = ScrollController(keepScrollOffset: true);
  final ScrollController _holdingsScrollController = ScrollController(keepScrollOffset: true);
  final ScrollController _analysisScrollController = ScrollController(keepScrollOffset: true);

  // 안전 변환 유틸
  double _toDouble(dynamic v, [double def = 0.0]) {
    if (v == null) return def;
    if (v is num) return v.toDouble();
    if (v is String) {
      final p = double.tryParse(v.trim());
      return p ?? def;
    }
    return def;
  }

  int _toInt(dynamic v, [int def = 0]) {
    if (v == null) return def;
    if (v is num) return v.toInt();
    if (v is String) {
      final pi = int.tryParse(v.trim());
      if (pi != null) return pi;
      final pd = double.tryParse(v.trim());
      return pd != null ? pd.toInt() : def;
    }
    return def;
  }
  
  // 스크롤 위치 저장
  double _watchlistScrollOffset = 0.0;
  double _holdingsScrollOffset = 0.0;
  double _analysisScrollOffset = 0.0;
  
  final DatabaseHelper _databaseHelper = DatabaseHelper();
  final RealtimeDataRepository _realtimeDataRepository = RealtimeDataRepository();
  final HistoricalDataRepository _historicalDataRepository = HistoricalDataRepository();
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    // 스크롤 리스너 제거(일반 스크롤로 단순화하여 버벅임 방지)
    
    // 초기화
    _initializeData();
    
    // 전달받은 탭 인덱스가 있으면 해당 탭으로 이동
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null && args['initialTab'] != null) {
        final initialTab = args['initialTab'] as int;
        if (initialTab >= 0 && initialTab < 4) {
          _tabController.animateTo(initialTab);
        }
      }
    });
    
    // 탭 변경 리스너 추가
    _tabController.addListener(() {
      // 탭이 변경되면 선택 모드 초기화
      if (_isSelectionMode && mounted) {
        setState(() {
          _isSelectionMode = false;
          _selectedItems.clear();
        });
      }
      // 추천종목 탭은 더 이상 AnalysisScreen에서 데이터 로드/스캔을 수행하지 않음
      // 호출 로직 제거: UI만 유지
    });
    
    // 투자 스타일 변경 스트림 구독
    _styleSubscription = _styleManager.styleStream.listen((newStyle) {
      print('🔄 투자 스타일 변경 감지: ${_getStyleName(newStyle)}');
      if (mounted) {
        setState(() {
          _currentStyle = newStyle;
        });
        // 스타일 변경 시 즉시 분석 재실행
        _refreshAllAnalysis();
      }
    });
    
    // 커스터마이징 모드 변경 스트림 구독
    _styleManager.customModeStream.listen((isCustom) {
      print('🔄 커스터마이징 모드 변경 감지: ${isCustom ? "사용자 커스터마이징" : "AI 최적화"}');
      if (mounted) {
        // 모드 변경 시 즉시 분석 재실행
        _refreshAllAnalysis();
      }
    });
    
    // 스타일 설정 변경 스트림 구독
    _styleManager.styleSettingsStream.listen((settings) {
      print('🔄 스타일 설정 변경 감지: ${settings['style_name']}');
      if (mounted) {
        // 설정 변경 시 즉시 분석 재실행
        _refreshAllAnalysis();
      }
    });
    
    // 관심종목 변경 스트림 구독
    _watchlistChangeSubscription = AppDataManager.instance.watchlistChangeStream.listen((newWatchlist) {
      print('🔄 관심종목 변경 감지 (Stream): ${newWatchlist.length}개');
      if (mounted) {
        setState(() {
          _watchlistItems = newWatchlist;
        });
        // 새로운 종목들 즉시 분석
        _analyzeNewWatchlistItems(newWatchlist);
      }
    });
    
    // 거래 상태 변경 리스너 추가
    _tradeStatusSubscription = _tradeStatusTracker.statusChangeStream.listen((_) {
      if (mounted) {
        setState(() {
          // UI 새로고침
        });
      }
    });
    
    _startRealTimeAnalysis();
    _startQuickUpdateTimer();
    _startCleanupTimer();
    // 추천종목 자동 업데이트는 전용 화면에서만 수행 (중복/깜빡임 방지)
    // _startRecommendedStocksUpdateTimer();
    _startWatchlistChangeDetection();
  }



  /// 투자 스타일 로드
  Future<void> _loadInvestmentStyle() async {
    try {
      // InvestmentStyleManager에서 현재 스타일 로드
      _currentStyle = _styleManager.currentStyle;
      print('✅ 투자 스타일 로드: $_currentStyle (${_getStyleName(_currentStyle)})');
    } catch (e) {
      print('❌ 투자 스타일 로드 실패: $e');
      // 기본값으로 moderate 설정
      _currentStyle = InvestmentStyle.moderate;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 화면이 다시 표시될 때마다 자동매매 상태 확인
    _checkAutoTradingStatus();
  }

  @override
  void dispose() {
    _analysisTimer?.cancel();
    _quickUpdateTimer?.cancel();
    _cleanupTimer?.cancel();
    _tabController.dispose();
    _styleSubscription?.cancel();
    _watchlistChangeSubscription?.cancel();
    _tradeStatusSubscription?.cancel();
    _watchlistScrollController.dispose();
    _holdingsScrollController.dispose();
    _analysisScrollController.dispose();
    super.dispose();
  }

  /// 자동매매 상태 확인 및 업데이트
  Future<void> _checkAutoTradingStatus() async {
    try {
      final isAutoTradingEnabled = await AppDataManager.instance.getAutoTradingStatus();
      if (mounted) {
        setState(() {
          _isAutoTradingEnabled = isAutoTradingEnabled;
        });
        print('✅ 자동매매 상태 확인: $_isAutoTradingEnabled');
      }
    } catch (e) {
      print('❌ 자동매매 상태 확인 실패: $e');
    }
  }

  /// 데이터 초기화 (성능 최적화)
  Future<void> _initializeData() async {
    print('🚀 데이터 초기화 시작...');
    if (mounted) {
      setState(() {
        _isFirstLoading = true;
        _isLoading = true;
      });
    }

    try {
      // 1. 캐시된 데이터 우선 로드 (빠른 UI 표시)
      await _loadDataFromCache();
      
      if (mounted) {
        setState(() {
          _isFirstLoading = false;
        });
        print('✅ _isFirstLoading을 false로 설정 완료');
      }
      
      // 2. 백그라운드에서 나머지 데이터 로드
      Future.microtask(() async {
        try {
          // 현재 투자 스타일 로드
          _currentStyle = _styleManager.currentStyle;
          print('✅ 투자 스타일 로드: $_currentStyle');
          
          // 자동매매 상태 확인 및 업데이트
          await _checkAutoTradingStatus();
          
          // 거래 상태 로드 및 동기화
          await _tradeStatusTracker.loadTradeStatuses();
          await _tradeStatusTracker.syncTradeStatusesFromHistory();
          
          // 3. 최신 데이터 로딩
          await _loadLatestData();
          
          // 4. 추천종목 데이터는 탭 변경 시에만 로드 (성능 최적화)
          // await _loadRecommendedStocksData();
          
          // 6. 초기 분석 수행 (백그라운드)
          await _performInitialAnalysis();
          
          print('✅ 백그라운드 데이터 초기화 완료');
          print('📊 최종 데이터 상태:');
          print('  - 관심종목: ${_watchlistItems.length}개');
          print('  - 보유종목: ${_holdingsItems.length}개');
          // 첫 진입 로딩은 이미 완료됨
          
        } catch (e) {
          print('❌ 백그라운드 데이터 초기화 실패: $e');
        } finally {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        }
      });
      
    } catch (e) {
      print('❌ 데이터 초기화 실패: $e');
      if (mounted) {
        setState(() {
          _isFirstLoading = false;
          _isLoading = false;
        });
        print('✅ 예외 발생 시에도 _isFirstLoading을 false로 설정 완료');
      }
    }
  }

  /// 최신 데이터 로딩 (백그라운드)
  Future<void> _loadLatestData() async {
    try {
      print('📡 최신 데이터 로딩 시작');
      // 관심종목/보유종목 모두 최신화
      await _refreshWatchlistData();
      await _loadHoldings();
      print('✅ 최신 데이터 로딩 완료 (관심/보유 모두 새로고침)');
      print('📊 최종 데이터 상태:');
      print('  - 관심종목: ${_watchlistItems.length}개');
      print('  - 보유종목: ${_holdingsItems.length}개');
      
    } catch (e) {
      print('❌ 최신 데이터 로딩 실패: $e');
    }
  }

  /// 관심종목 데이터 새로고침
  Future<void> _refreshWatchlistData() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'debug-user';
      final results = await AnalysisFunctionsService().analyzeWatchlist(uid: uid, days: 100);
      // 서버 결과를 화면 아이템 포맷으로 매핑
      _watchlistItems = results
          .map((r) => {
                'stock_code': r['symbol'] ?? r['id'],
                'analysis': r,
                'comprehensiveScore': r['comprehensiveScore'],
              })
          .toList();
      _watchlistItems.sort((a, b) {
        final sa = (a['comprehensiveScore'] as num?)?.toDouble() ?? 0.0;
        final sb = (b['comprehensiveScore'] as num?)?.toDouble() ?? 0.0;
        return sb.compareTo(sa);
      });
      setState(() {});
    } catch (e) {
      // 캐시 로드 실패 시 일반 로드로 폴백
      try {
        await _loadWatchlist();
        await _loadHoldings();
      } catch (fallbackError) {
        
      }
    }
  }

  /// 보유종목 데이터 새로고침 (항상 최신 데이터 반영)
  Future<void> _refreshHoldingsData() async {
    try {
      print('🔄 보유종목 데이터 새로고침 시작...');
      // API에서 최신 보유종목 강제 로드
      await _loadHoldings();
      print('✅ 보유종목 데이터 새로고침 완료: ${_holdingsItems.length}개');
    } catch (e) {
      print('❌ 보유종목 새로고침 실패: $e');
    }
  }

  /// 추천종목 데이터 로드
  Future<void> _loadRecommendedStocksData() async {
    // 호출 로직 제거: AnalysisScreen에서는 추천 데이터를 로드하지 않음
    if (mounted) {
      setState(() {
        _isAnalyzingRecommendedStocks = false;
      });
    }
  }

  /// 🧪 테스트 분석 (001340, 096770만)
  Future<void> _testAnalysis() async {
    try {
      print('🧪 [분석탭] 테스트 분석 시작: 001340, 096770, 112040');
      
      // 테스트용 종목 정보
      final testStocks = [
        {'code': '112040', 'name': '위메이드'},
      ];
      
      // 각 종목 분석
      for (final stock in testStocks) {
        final code = stock['code']!;
        final name = stock['name']!;
        
        print('🧪 [분석탭] $code ($name) 분석 중...');
        
        try {
          // 1. 실시간 현재가 데이터 수집 및 캐시
          print('🔍 [AnalysisScreen] 테스트 분석 - 현재가 데이터 수집 시작: $code');
          final currentPriceData = await _collectAndCacheCurrentPriceData(code);
          if (currentPriceData == null) {
            print('❌ 테스트 분석 - 현재가 데이터 수집 실패 ($code)');
            continue;
          }
          print('✅ [AnalysisScreen] 테스트 분석 - 현재가 데이터 수집 완료: $code');
          print('📊 [AnalysisScreen] 테스트 분석 - 수집된 데이터: $currentPriceData');

          // 2. 차트 데이터 수집 및 캐시
          final chartData = await _collectAndCacheChartData(code);
          if (chartData.isEmpty) {
            print('⚠️ 테스트 분석 - 차트 데이터 없음 ($code) - 기본값으로 분석 진행');
          }

          // 3. UnifiedAnalysisService를 통해 분석 (추천종목과 동일한 로직)
          final analysisResult = await _unifiedAnalysis.analyzeStock(code, days: 100);
          
          if (analysisResult != null) {
            final score = analysisResult['comprehensiveScore'] ?? 0.0;
            final price = analysisResult['currentPrice'] ?? 0.0;
            final market = analysisResult['market'] ?? 'UNKNOWN';
            
            print('✅ [분석탭] $code 분석 완료:');
            print('  - 종목명: $name');
            print('  - 종합점수: ${score.toStringAsFixed(3)}');
            print('  - 현재가: $price');
            print('  - 시장: $market');
            print('  - 개별지표: ${analysisResult['individualScores']?.keys.toList() ?? []}');
            
            // 분석 결과를 _analysisResults에 저장 (UI에서 확인 가능)
            _analysisResults[code] = analysisResult;
            
          } else {
            print('❌ [분석탭] $code 분석 결과 없음');
          }
        } catch (e) {
          print('❌ [분석탭] $code 분석 실패: $e');
        }
        
        // 잠시 대기
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      print('🧪 [분석탭] 테스트 분석 완료');
      
      // UI 업데이트
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🧪 테스트 분석 완료: ${testStocks.length}개 종목'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      
    } catch (e) {
      print('❌ [분석탭] 테스트 분석 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 테스트 분석 실패: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }



  /// API 직접 호출로 데이터 로드 (캐시 무시)
  Future<void> _loadDataFromCache() async {
    try {
      print('📋 API 직접 호출로 데이터 로드 시작... (캐시 무시)');
      
      // 강력한 캐시 무효화 (모든 캐시 레이어 무효화)
      AppDataManager.instance.invalidateCache();
      UnifiedStockDataManager.instance.clearCache();
      _watchlistDataCache.clear();
      _holdingsDataCache.clear();
      _currentPrices.clear();
      _analysisResults.clear();
      
      // 로컬 DB 캐시도 무효화 (기존 데이터 정리)
      try {
        // 오래된 현재가 데이터 정리 (1시간 이상)
        final currentPriceRepo = CurrentPriceRepository();
        await currentPriceRepo.cleanupOldCurrentPrice();
        print('✅ 로컬 DB 캐시 무효화 완료');
      } catch (e) {
        print('⚠️ 로컬 DB 캐시 무효화 실패: $e');
      }
      
      // 1. 관심종목 데이터 로드 (캐시 여부와 관계없이 항상 로드)
      final watchlistRepository = AppDataManager.instance.watchlistRepository;
      final watchlist = await watchlistRepository.getWatchlistWithStockInfo();
      if (mounted) {
        setState(() {
          _watchlistItems = watchlist;
        });
      }
      print('✅ 관심종목 데이터 로드 완료: ${watchlist.length}개');
      
      // 2. 캐시된 관심종목 실시간 데이터
      final cachedWatchlistData = AppDataManager.instance.getCachedWatchlistData();
      if (cachedWatchlistData.isNotEmpty) {
        print('📊 캐시된 관심종목 실시간 데이터: ${cachedWatchlistData.length}개');
        // 캐시된 실시간 데이터 저장 (API에서 반환하는 타입 그대로 사용)
        _watchlistDataCache = Map<String, Map<String, dynamic>>.from(
          cachedWatchlistData.map((key, value) => MapEntry(key, Map<String, dynamic>.from(value)))
        );
        print('✅ 캐시된 관심종목 실시간 데이터 로드 완료');
      }
      
      // 3. 캐시된 보유종목 실시간 데이터
      final cachedHoldingsData = AppDataManager.instance.getCachedHoldingsData();
      if (cachedHoldingsData.isNotEmpty) {
        print('📊 캐시된 보유종목 실시간 데이터: ${cachedHoldingsData.length}개');
        // 캐시된 실시간 데이터 저장 (API에서 반환하는 타입 그대로 사용)
        _holdingsDataCache = Map<String, Map<String, dynamic>>.from(
          cachedHoldingsData.map((key, value) => MapEntry(key, Map<String, dynamic>.from(value)))
        );
        print('✅ 캐시된 보유종목 실시간 데이터 로드 완료');
      }
      
      // 4. 보유종목은 완전한 API 조회로 처리 (캐시 사용 안함)
      print('🔄 보유종목 완전 API 조회 시작...');
      await _loadHoldings();
      
      // 5. 모든 보유종목 데이터 강제 갱신
      await _forceRefreshAllHoldingsData();
      
      print('✅ 캐시된 데이터 로드 완료');
      print('📊 최종 데이터 상태:');
      print('  - 관심종목: ${_watchlistItems.length}개');
      print('  - 보유종목: ${_holdingsItems.length}개');
      
    } catch (e) {
      print('❌ 캐시된 데이터 로드 실패: $e');
      // 캐시 로드 실패 시 일반 로드로 폴백
      try {
      await _loadWatchlist();
      await _loadHoldings();
      } catch (fallbackError) {
        print('❌ 폴백 로드도 실패: $fallbackError');
      }
    }
  }

  /// 실시간 분석 시작
  void _startRealTimeAnalysis() {
    _analysisTimer?.cancel();
    _analysisTimer = Timer.periodic(_analysisInterval, (timer) {
      _performRealTimeAnalysis();
    });
    print('🔄 실시간 분석 타이머 시작 (3분 간격 - 차트 데이터 포함)');
  }

  /// 추천종목 업데이트 타이머 시작
  void _startRecommendedStocksUpdateTimer() {
    Timer.periodic(const Duration(minutes: 5), (timer) {
      _updateRecommendedStocks();
    });
    print('⭐ 추천종목 업데이트 타이머 시작 (5분 간격)');
  }

  /// 추천종목 업데이트
  Future<void> _updateRecommendedStocks() async {
    try {
      if (_analysisResults.isNotEmpty && _currentPrices.isNotEmpty) {
        await _loadRecommendedStocksData();
        print('✅ 추천종목 업데이트 완료');
      }
    } catch (e) {
      print('❌ 추천종목 업데이트 실패: $e');
    }
  }

  /// 빠른 업데이트 타이머 시작 (현재가만)
  void _startQuickUpdateTimer() {
    _quickUpdateTimer?.cancel();
    _quickUpdateTimer = Timer.periodic(_quickUpdateInterval, (timer) {
      _performQuickPriceUpdate();
    });
    print('⚡ 빠른 업데이트 타이머 시작 (5초 간격 - 현재가만)');
  }

  /// 데이터 정리 타이머 시작
  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(_cleanupInterval, (timer) {
      _performDataCleanup();
    });
    print('🧹 데이터 정리 타이머 시작 (1시간 간격)');
  }
  /// 관심종목 로드
  Future<void> _loadWatchlist() async {
    print('📋 _loadWatchlist() 함수 시작 (캐시 무시)');
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'debug-user';
      final results = await AnalysisFunctionsService().analyzeWatchlist(uid: uid, days: 100);
      _watchlistItems = results
          .map((r) => {
                'stock_code': r['symbol'] ?? r['id'],
                'analysis': r,
                'comprehensiveScore': r['comprehensiveScore'],
              })
          .toList();
      _watchlistItems.sort((a, b) {
        final sa = (a['comprehensiveScore'] as num?)?.toDouble() ?? 0.0;
        final sb = (b['comprehensiveScore'] as num?)?.toDouble() ?? 0.0;
        return sb.compareTo(sa);
      });
      setState(() {});
    } catch (e) {
      print('❌ _loadWatchlist 실패: $e');
      _watchlistItems = [];
    }
    print('📋 _loadWatchlist() 함수 종료');
  }
  /// 보유종목 로드 (국내 + 해외 완전 로드 후 화면 업데이트)
  Future<void> _loadHoldings() async {
    print('💼 _loadHoldings() 서버 호출 시작');
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'debug-user';
      final results = await AnalysisFunctionsService().analyzeHoldings(uid: uid, days: 100);
      setState(() {
        _holdingsItems = results
            .map((r) => {
                  'stockCode': (r['symbol'] ?? r['id']).toString(),
                  'analysis': r,
                  'comprehensiveScore': r['comprehensiveScore'],
                })
            .toList();
        _holdingsItems.sort((a, b) {
          final sa = (a['comprehensiveScore'] as num?)?.toDouble() ?? 0.0;
          final sb = (b['comprehensiveScore'] as num?)?.toDouble() ?? 0.0;
          return sb.compareTo(sa);
        });
      });
      print('✅ 보유종목 서버 분석 로드 완료: ${_holdingsItems.length}개');
    } catch (e) {
      print('❌ 보유종목 서버 호출 실패: $e');
      if (mounted) setState(() => _holdingsItems = []);
    }
    print('💼 _loadHoldings() 서버 호출 종료');
  }

  /// 종목명 매핑 개선
  Future<void> _improveStockNames() async {
    print('🔍 종목명 매핑 개선 시작...');
    
    for (int i = 0; i < _holdingsItems.length; i++) {
      final item = _holdingsItems[i];
      final stockCode = item['stockCode'] as String? ?? '';
      
      if (stockCode.isEmpty) continue;
      
      // 현재 종목명 확인
      final currentName = item['stockName'] as String? ?? '';
      print('📝 종목 $i ($stockCode): 현재명=$currentName');
      
      // 종목명이 비어있거나 "Unknown"인 경우 개선
      if (currentName.isEmpty || currentName == 'Unknown' || currentName == stockCode) {
        try {
          // AppDataManager에서 종목명 조회
          final improvedName = await AppDataManager.instance.getStockNameAsync(stockCode);
          print('📝 종목 $i ($stockCode): 개선된명=$improvedName');
          
          if (improvedName.isNotEmpty && improvedName != stockCode) {
            if (mounted) {
              setState(() {
                _holdingsItems[i]['stockName'] = improvedName;
              });
              print('✅ 종목명 개선 완료: $stockCode -> $improvedName');
            }
          }
        } catch (e) {
          print('❌ 종목명 개선 실패 ($stockCode): $e');
        }
      }
    }
    
    print('✅ 종목명 매핑 개선 완료');
  }

  /// 보유종목 차트 데이터 선로딩
  Future<void> _prefetchHoldingsCharts({int maxConcurrency = 3}) async {
    try {
      int inFlight = 0;
      int index = 0;
      Future<void> scheduleNext() async {
        if (index >= _holdingsItems.length) return;
        final item = _holdingsItems[index++];
        final stockCode = item['stockCode'] as String? ?? '';
        if (stockCode.isEmpty) return;
        inFlight++;
        try {
          // 보유 항목에서 거래소 코드 힌트
          final holding = item;
          final exc = (holding['exchangeCode'] as String?) ?? '';
          if (exc.isNotEmpty) {
            print('📈 차트 선로딩(보유): $stockCode @ $exc');
          } else {
            print('📈 차트 선로딩(보유): $stockCode');
          }
          await _collectAndCacheChartData(stockCode);
        } catch (e) {
          print('⚠️ 차트 선로딩 실패: $stockCode - $e');
        } finally {
          inFlight--;
          await scheduleNext();
        }
      }
      final runners = <Future<void>>[];
      for (int i = 0; i < maxConcurrency && i < _holdingsItems.length; i++) {
        runners.add(scheduleNext());
      }
      await Future.wait(runners);
    } catch (e) {
      print('❌ 보유종목 차트 선로딩 중 오류: $e');
    }
  }

  /// 초기 분석 수행
  Future<void> _performInitialAnalysis() async {
    print('🔍 분석탭 초기 분석 시작');
    print('📊 현재 데이터 상태:');
    print('  - 관심종목: ${_watchlistItems.length}개');
    print('  - 보유종목: ${_holdingsItems.length}개');
    print('🔍 _performInitialAnalysis 호출됨 - 스택 트레이스: ${StackTrace.current.toString().split('\n').take(3).join('\n')}');
    
    final allStocks = <String>[];
    
    // 관심종목 추가
    for (final item in _watchlistItems) {
      allStocks.add(item['stock_code']);
      print('📝 관심종목 추가: ${item['stock_code']} - ${item['stock_name']}');
    }
    
    // 보유종목 추가
    for (final holding in _holdingsItems) {
      final stockCode = holding['stockCode'] as String?;
      if (stockCode != null && !allStocks.contains(stockCode)) {
        allStocks.add(stockCode);
        print('📝 보유종목 추가: $stockCode - ${holding['stockName']}');
      }
    }
    
    print('📊 분석 대상 종목: $allStocks');
    
    if (allStocks.isNotEmpty) {
      // 초기 진입 시 API 조회로 최신 데이터 확보
      await _refreshLatestDataFromAPI(allStocks);
      await _analyzeStocksFromLocalData(allStocks);
    } else {
      print('⚠️ 분석할 종목이 없습니다.');
    }
  }

  /// API에서 최신 데이터를 가져와서 로컬 DB 업데이트
  Future<void> _refreshLatestDataFromAPI(List<String> stockCodes) async {
    print('🔄 API에서 최신 데이터 수집 시작 (${stockCodes.length}개 종목)');
    
    for (final stockCode in stockCodes) {
      try {
        print('📊 API 데이터 수집: $stockCode');
        
        // API에서 현재가 데이터 조회 (통일된 API 서비스 사용)
        Map<String, dynamic>? priceData = await _unifiedApiService.getStockPrice(stockCode);
        
        if (priceData != null && priceData.isNotEmpty) {
          // 로컬 DB에 저장 (올바른 매개변수 사용)
          await _realtimeDataRepository.saveRealtimeData(
            stockCode: stockCode,
            market: 'UNKNOWN',
            currentPrice: (priceData['currentPrice'] ?? 0.0).toDouble(),
            prevClose: (priceData['prevClose'] ?? 0.0).toDouble(),
            changeAmount: (priceData['change'] ?? 0.0).toDouble(),
            changeRate: (priceData['changeRate'] ?? 0.0).toDouble(),
            volume: (priceData['volume'] ?? 0).toInt(),
            tradeAmount: (priceData['tradeAmount'] ?? 0.0).toDouble(),
            highPrice: (priceData['high'] ?? priceData['highPrice'] ?? 0.0).toDouble(),
            lowPrice: (priceData['low'] ?? priceData['lowPrice'] ?? 0.0).toDouble(),
            openPrice: (priceData['open'] ?? priceData['openPrice'] ?? 0.0).toDouble(),
            marketCap: priceData['marketCap']?.toDouble(),
            per: priceData['per']?.toDouble(),
            pbr: priceData['pbr']?.toDouble(),
          );
          print('✅ API 데이터 저장 완료: $stockCode');
        } else {
          print('⚠️ API 데이터 없음: $stockCode');
        }
        
        // 차트 데이터도 조회 (일봉 데이터) - 통일된 API 서비스 사용
        try {
          List<Map<String, dynamic>> chartData = await RemoteKisService.instance.getDailyChart(stockCode, days: 100);
          
          if (chartData.isNotEmpty) {
            // 로컬 DB에 저장 (upsertDailyBars 사용)
            final market = _isNasdaqStock(stockCode) ? 'NASDAQ' : 'KOSPI';
            final bars = chartData.map((e) => {
              'date': (e['date'] ?? '').toString().replaceAll('-', ''),
              'open': (e['open'] ?? 0.0).toDouble(),
              'high': (e['high'] ?? 0.0).toDouble(),
              'low': (e['low'] ?? 0.0).toDouble(),
              'close': (e['close'] ?? 0.0).toDouble(),
              'volume': (e['volume'] ?? 0).toInt(),
            }).toList();

            await _historicalDataRepository.upsertDailyBars(
              stockCode: stockCode,
              market: market,
              bars: bars,
              keepDays: 100,
            );
            print('✅ 차트 데이터 저장 완료: $stockCode');
          }
        } catch (e) {
          print('⚠️ 차트 데이터 조회 실패 ($stockCode): $e');
        }
        
        // API 호출 간격 조절 (서버 부하 방지)
        await Future.delayed(const Duration(milliseconds: 200));
        
      } catch (e) {
        print('❌ API 데이터 수집 실패 ($stockCode): $e');
      }
    }
    
    print('✅ API 최신 데이터 수집 완료');
  }

  /// 로컬 DB에서 데이터를 가져와서 분석 수행
  Future<void> _analyzeStocksFromLocalData(List<String> stockCodes) async {
    print('🔍 로컬 DB 데이터로 분석 시작');
    
    // 배치 업데이트를 위한 임시 저장소
    final Map<String, Map<String, dynamic>> tempAnalysisResults = {};
    
    for (final stockCode in stockCodes) {
      try {
        print('📊 종목 분석 시작: $stockCode');
        
        // 1. 로컬 DB에서 실시간 데이터 가져오기
        final realtimeData = await _realtimeDataRepository.getLatestRealtimeData(stockCode);
        
        // 2. 로컬 DB에서 히스토리 데이터 가져오기
        final historicalData = await _historicalDataRepository.getRecentBars(stockCode, limit: 100);
        
        if (realtimeData != null && historicalData.isNotEmpty) {
          print('✅ 로컬 DB 데이터 발견: $stockCode');
          
          // 3. UnifiedAnalysisService를 사용하여 분석 수행 (서버 위임)
          final analysisResult = await _unifiedAnalysis.analyzeStock(stockCode, days: 100);
          
          if (analysisResult != null) {
            // 종목 정보 추가
            final stockName = await AppDataManager.instance.getStockNameAsync(stockCode);
            analysisResult['stockName'] = stockName.isNotEmpty ? stockName : stockCode;
            
            // 수집된 데이터 추가
            analysisResult['currentPriceData'] = {
              'currentPrice': (realtimeData['current_price'] ?? 0.0).toDouble(),
              'prevClose': (realtimeData['prev_close'] ?? 0.0).toDouble(),
              'volume': (realtimeData['volume'] ?? 0).toInt(),
              'highPrice': (realtimeData['high_price'] ?? 0.0).toDouble(),
              'lowPrice': (realtimeData['low_price'] ?? 0.0).toDouble(),
              'openPrice': (realtimeData['open_price'] ?? 0.0).toDouble(),
              'timestamp': realtimeData['timestamp'] != null ? DateTime.fromMillisecondsSinceEpoch(realtimeData['timestamp']).toIso8601String() : null,
            };
            
            analysisResult['chartData'] = historicalData.map((bar) => {
              'date': bar['date'] ?? '',
              'open': (bar['open'] ?? 0.0).toDouble(),
              'high': (bar['high'] ?? 0.0).toDouble(),
              'low': (bar['low'] ?? 0.0).toDouble(),
              'close': (bar['close'] ?? 0.0).toDouble(),
              'volume': (bar['volume'] ?? 0).toInt(),
            }).toList();
            
            tempAnalysisResults[stockCode] = analysisResult;
            print('✅ 로컬 DB 분석 완료: $stockCode - ${analysisResult['signal']}');
          }
        } else {
          print('⚠️ 로컬 DB 데이터 없음: $stockCode - API 분석으로 폴백');
          // 로컬 DB에 데이터가 없으면 기존 API 분석으로 폴백
          final result = await _performSingleStockAnalysis(stockCode);
          if (result != null) {
            tempAnalysisResults[stockCode] = result;
          }
        }
      } catch (e) {
        print('❌ 로컬 DB 분석 실패 ($stockCode): $e');
        // 에러 발생 시 기존 API 분석으로 폴백
        try {
          final result = await _performSingleStockAnalysis(stockCode);
          if (result != null) {
            tempAnalysisResults[stockCode] = result;
          }
        } catch (fallbackError) {
          print('❌ 폴백 분석도 실패 ($stockCode): $fallbackError');
        }
      }
    }
    
    // 배치 업데이트 - 한 번에 모든 결과를 UI에 반영
    if (mounted) {
      setState(() {
        _analysisResults.addAll(tempAnalysisResults);
      });
      print('✅ 로컬 DB 분석 배치 업데이트 완료: ${tempAnalysisResults.length}개 종목');
    }
  }



  /// 실시간 분석 수행 (차트 데이터 포함, 1분 간격)
  Future<void> _performRealTimeAnalysis() async {
    print('🔄 실시간 분석 시작 (차트 데이터 포함 - 1분 간격)...');
    
    // 사일런트 리프레시 상태 확인
    final realtimeUIManager = AppDataManager.instance.realtimeUIManager;
    if (realtimeUIManager.isSilentRefresh) {
      print('📊 사일런트 리프레시 중 - UI 업데이트 건너뛰기');
      return;
    }
    
    // 🔧 강제 새로고침: 캐시 무효화 후 새로 계산
    await _forceRefreshAnalysis();
    
    final allStocks = <String>[];
    
    // 관심종목 추가
    for (final item in _watchlistItems) {
      allStocks.add(item['stock_code']);
    }
    
    // 보유종목 추가
    for (final holding in _holdingsItems) {
      final stockCode = holding['stockCode'] as String?;
      if (stockCode != null && !allStocks.contains(stockCode)) {
        allStocks.add(stockCode);
      }
    }
    
    // 기존 분석 결과 백업 (깜빡임 방지)
    final Map<String, Map<String, dynamic>> existingResults = Map.from(_analysisResults);
    bool hasChanges = false;
    
    // API에서 최신 데이터 수집 (1분마다)
    await _refreshLatestDataFromAPI(allStocks);
    
    // 모든 종목 분석 (로컬 DB 데이터 우선 사용)
    for (final stockCode in allStocks) {
      try {
        final result = await _performSingleStockAnalysisWithLocalData(stockCode);
        if (result != null) {
          // 변경사항이 있는지 확인 (더 정확한 비교)
          final existingResult = existingResults[stockCode];
          if (existingResult == null || !_isAnalysisResultEqual(existingResult, result)) {
            existingResults[stockCode] = result;
            hasChanges = true;
            print('📊 분석 결과 변경 감지: $stockCode');
          }
        }
      } catch (e) {
        print('❌ 실시간 분석 실패 ($stockCode): $e');
      }
    }
    
    // 변경사항이 있을 때만 UI 업데이트 (깜빡임 완전 방지)
    if (mounted && hasChanges) {
      // 사일런트 업데이트를 위한 플래그 설정
      final wasSilentRefresh = realtimeUIManager.isSilentRefresh;
      
      // 부분적 업데이트로 깜빡임 방지
      _updateAnalysisResultsSilently(existingResults);
      
      print('✅ 실시간 분석 완료: ${existingResults.length}개 종목 업데이트 (변경사항 있음)');
      
      // 시그널 처리 (실시간 분석에서만)
      await _processSignalsFromRealTimeAnalysis(existingResults);
      
      // 추천종목 업데이트
      await _updateRecommendedStocks();
      
      print('✅ 실시간 분석 완료: ${existingResults.length}개 종목 업데이트 (변경사항 있음)');
    } else {
      print('✅ 실시간 분석 완료: 변경사항 없음 (사일런트)');
    }
  }
  /// 사일런트 업데이트로 깜빡임 방지
  void _updateAnalysisResultsSilently(Map<String, Map<String, dynamic>> newResults) {
    // 변경된 항목만 업데이트하여 깜빡임 방지
    for (final entry in newResults.entries) {
      final stockCode = entry.key;
      final newResult = entry.value;
      
      // 기존 결과와 비교하여 실제로 변경된 경우만 업데이트
      final existingResult = _analysisResults[stockCode];
      if (existingResult == null || !_isAnalysisResultEqual(existingResult, newResult)) {
        _analysisResults[stockCode] = newResult;
      }
    }
    
    // UI 업데이트는 한 번만 호출
    if (mounted) {
      setState(() {
        // _analysisResults는 이미 업데이트됨
      });
    }
  }

  /// API에서 최신 데이터를 가져와서 분석하는 단일 종목 분석
  Future<Map<String, dynamic>?> _performSingleStockAnalysisWithLocalData(String stockCode) async {
    try {
      print('🔍 API 최신 데이터로 단일 종목 분석: $stockCode');
      
      // 1. API에서 최신 실시간 데이터 가져오기 (로컬 DB 우선 사용 안함)
      final currentPriceData = await _collectAndCacheCurrentPriceData(stockCode);
      if (currentPriceData == null) {
        print('❌ 현재가 데이터 수집 실패: $stockCode');
        return null;
      }
      
      // 2. API에서 최신 차트 데이터 가져오기
      final chartData = await _collectAndCacheChartData(stockCode);
      if (chartData.isEmpty) {
        print('⚠️ 차트 데이터 없음: $stockCode - 기본값으로 분석 진행');
      }
      
      print('✅ API 최신 데이터 사용: $stockCode');
        
        // 3. UnifiedAnalysisService를 사용하여 분석 수행 (서버 위임)
        final analysisResult = await _unifiedAnalysis.analyzeStock(stockCode, days: 100);
        
        if (analysisResult != null) {
          // 종목 정보 추가
          final stockName = await AppDataManager.instance.getStockNameAsync(stockCode);
          analysisResult['stockName'] = stockName.isNotEmpty ? stockName : stockCode;
          
          // 수집된 데이터 추가 (API에서 가져온 최신 데이터)
          analysisResult['currentPriceData'] = {
            'currentPrice': _toDouble(currentPriceData['currentPrice']),
            'prevClose': _toDouble(currentPriceData['prevClose']),
            'volume': _toInt(currentPriceData['volume']),
            'highPrice': _toDouble(currentPriceData['highPrice']),
            'lowPrice': _toDouble(currentPriceData['lowPrice']),
            'openPrice': _toDouble(currentPriceData['openPrice']),
            'timestamp': currentPriceData['timestamp'] ?? DateTime.now().toIso8601String(),
          };
          
          analysisResult['chartData'] = chartData.map((bar) => {
            'date': bar['date'] ?? '',
            'open': _toDouble(bar['open']),
            'high': _toDouble(bar['high']),
            'low': _toDouble(bar['low']),
            'close': _toDouble(bar['close']),
            'volume': _toInt(bar['volume']),
          }).toList();
          
          print('✅ API 최신 데이터 분석 완료: $stockCode - ${analysisResult['signal']}');
          return analysisResult;
      }
      
      return null;
    } catch (e) {
      print('❌ 로컬 DB 분석 실패 ($stockCode): $e');
      // 에러 발생 시 기존 API 분석으로 폴백
      return await _performSingleStockAnalysis(stockCode);
    }
  }

  /// 실시간 분석에서 시그널 처리
  Future<void> _processSignalsFromRealTimeAnalysis(Map<String, Map<String, dynamic>> analysisResults) async {
    print('🔄 실시간 분석 시그널 처리 시작...');
    
    for (final entry in analysisResults.entries) {
      final stockCode = entry.key;
      final analysis = entry.value;
      
      try {
        // 관심종목에서 해당 종목 찾기
        final watchlistItem = _watchlistItems.firstWhere(
          (item) => item['stock_code'] == stockCode,
          orElse: () => <String, dynamic>{},
        );
        
        if (watchlistItem.isNotEmpty) {
          await _handleSignalAndAutoTrading(
            watchlistItem, 
            stockCode, 
            analysis, 
            _currentPrices[stockCode]
          );
        } else {
          // 보유종목에서 찾기
          final holdingItem = _holdingsItems.firstWhere(
            (item) => item['stockCode'] == stockCode,
            orElse: () => <String, dynamic>{},
          );
          
          if (holdingItem.isNotEmpty) {
            await _handleSignalAndAutoTrading(
              holdingItem, 
              stockCode, 
              analysis, 
              _currentPrices[stockCode]
            );
          }
        }
      } catch (e) {
        print('❌ 실시간 시그널 처리 실패 ($stockCode): $e');
      }
    }
    
    print('✅ 실시간 분석 시그널 처리 완료');
  }

  /// 분석 결과 비교 (깜빡임 방지용)
  bool _isAnalysisResultEqual(Map<String, dynamic> result1, Map<String, dynamic> result2) {
    try {
      // 주요 필드만 비교
      final price1 = result1['currentPrice'] ?? 0.0;
      final price2 = result2['currentPrice'] ?? 0.0;
      final signal1 = result1['signal'] ?? '';
      final signal2 = result2['signal'] ?? '';
      final confidence1 = result1['confidence'] ?? 0.0;
      final confidence2 = result2['confidence'] ?? 0.0;
      
      return (price1 == price2 && signal1 == signal2 && confidence1 == confidence2);
    } catch (e) {
      return false;
    }
  }
  /// 빠른 현재가 업데이트 (현재가만 - 차트 데이터 제외, 5초 간격)
  Future<void> _performQuickPriceUpdate() async {
    if (!mounted) return;
    
    // 사일런트 리프레시 상태 확인
    final realtimeUIManager = AppDataManager.instance.realtimeUIManager;
    if (realtimeUIManager.isSilentRefresh) {
      print('📊 사일런트 리프레시 중 - 빠른 업데이트 건너뛰기');
      return;
    }
    
    try {
      print('⚡ 빠른 업데이트 시작 (현재가만 - 5초 간격)');
      
      final allStocks = <String>[];
      
      // 관심종목 추가
      for (final item in _watchlistItems) {
        allStocks.add(item['stock_code']);
      }
      
      // 보유종목 추가
      for (final holding in _holdingsItems) {
        final stockCode = holding['stockCode'] as String?;
        if (stockCode != null && !allStocks.contains(stockCode)) {
          allStocks.add(stockCode);
        }
      }
      
      // 기존 분석 결과에서 현재가만 업데이트
      final Map<String, Map<String, dynamic>> updatedResults = Map.from(_analysisResults);
      bool hasUpdates = false;
      
      for (final stockCode in allStocks) {
        try {
          // 현재가만 빠르게 조회 (차트 데이터 제외)
          final currentPrice = await _getQuickCurrentPrice(stockCode);
          if (currentPrice > 0 && updatedResults.containsKey(stockCode)) {
            final existingResult = updatedResults[stockCode]!;
            final oldPrice = existingResult['currentPrice'] ?? 0.0;
            final threshold = _getPriceUpdateThreshold(stockCode);
            if ((currentPrice - oldPrice).abs() > threshold) {
              existingResult['currentPrice'] = currentPrice;
              
              // 현재가 캐시 업데이트 (새로운 맵으로 복사)
              AppDataManager.instance.updateCurrentPrice(stockCode, {
                'currentPrice': currentPrice,
                'timestamp': DateTime.now().toIso8601String(),
              });
              
              hasUpdates = true;
              print('📊 현재가 변경 감지: $stockCode ${oldPrice.toStringAsFixed(2)} → ${currentPrice.toStringAsFixed(2)}');
            }

            // 거래량 동시 업데이트: 장중에는 증가 값 반영, 장외에는 0으로 덮어쓰지 않음
            try {
              // 캐시된 데이터 대신 최신 분석 결과에서 거래량 가져오기
              final int newVolume = (existingResult['currentVolume'] ?? 0).toInt();
              final bool isTrading = _isTradingTime(stockCode);
              final bool wasTrading = _prevTradingStates[stockCode] ?? false;
              final int oldVolume = (existingResult['currentVolume'] ?? 0).toInt();

              // 거래량은 분석 결과에서 이미 올바른 값이 설정되어 있으므로 업데이트 불필요
              // 캐시된 오래된 데이터로 덮어쓰지 않음

              // 세션 상태 스냅샷 갱신
              _prevTradingStates[stockCode] = isTrading;
            } catch (e) {
              print('⚠️ 빠른 거래량 업데이트 실패 ($stockCode): $e');
            }
          }
        } catch (e) {
          // 빠른 업데이트 실패는 무시
          print('⚠️ 빠른 업데이트 실패 ($stockCode): $e');
        }
      }
      
      // 변경사항이 있을 때만 UI 업데이트 (사일런트)
      if (hasUpdates && mounted) {
        _updateAnalysisResultsSilently(updatedResults);
        print('✅ 빠른 업데이트 완료: 현재가 변경사항 반영');
        
        // 현재가 변경 시 추천종목 업데이트
        await _updateRecommendedStocks();
      } else {
        print('✅ 빠른 업데이트 완료: 변경사항 없음');
      }
      
    } catch (e) {
      print('❌ 빠른 업데이트 실패: $e');
    }
  }

  /// 🔧 강제 새로고침: 캐시 무효화 후 새로 계산
  Future<void> _forceRefreshAnalysis() async {
    try {
      print('🔄 강제 새로고침 시작: 캐시 무효화 후 새로 계산');
      
      // 1. 모든 캐시 무효화
      AppDataManager.instance.invalidateCache();
      UnifiedStockDataManager.instance.clearCache();
      
      // 2. 현재가 캐시도 무효화 (잘못된 가격 방지)
      _watchlistDataCache.clear();
      _holdingsDataCache.clear();
      _currentPrices.clear();
      
      // 3. 분석 결과 캐시도 무효화
      _analysisResults.clear();
      
      // 4. 로컬 DB 캐시도 강제 무효화 (기존 데이터 정리)
      try {
        // 오래된 현재가 데이터 정리 (1시간 이상)
        final currentPriceRepo = CurrentPriceRepository();
        await currentPriceRepo.cleanupOldCurrentPrice();
        print('✅ 로컬 DB 캐시 강제 무효화 완료');
      } catch (e) {
        print('⚠️ 로컬 DB 캐시 무효화 실패: $e');
      }
      
      // 3. 모든 종목에 대해 새로 분석 수행
      final allStocks = <String>[];
      
      // 관심종목 추가
      for (final item in _watchlistItems) {
        allStocks.add(item['stock_code']);
      }
      
      // 보유종목 추가
      for (final holding in _holdingsItems) {
        final stockCode = holding['stockCode'] as String?;
        if (stockCode != null && !allStocks.contains(stockCode)) {
          allStocks.add(stockCode);
        }
      }
      
      // 4. 각 종목별로 새로 분석
      for (final stockCode in allStocks) {
        try {
          print('🔄 강제 새로고침: $stockCode 분석 중...');
          
          // API에서 최신 데이터 조회
          print('🔍 [AnalysisScreen] 강제 새로고침 - 현재가 데이터 수집 시작: $stockCode');
          final currentPriceData = await _collectAndCacheCurrentPriceData(stockCode);
          print('📊 [AnalysisScreen] 강제 새로고침 - 현재가 데이터: $currentPriceData');
          final chartData = await _collectAndCacheChartData(stockCode);
          
          // 새로 분석 수행 (서버 위임)
          final analysisResult = await _unifiedAnalysis.analyzeStock(stockCode, days: 100);
          
          if (analysisResult != null) {
            _analysisResults[stockCode] = analysisResult;
            print('✅ 강제 새로고침: $stockCode 분석 완료');
          }
        } catch (e) {
          print('❌ 강제 새로고침 실패 ($stockCode): $e');
        }
      }
      
      print('✅ 강제 새로고침 완료: ${allStocks.length}개 종목');
      
    } catch (e) {
      print('❌ 강제 새로고침 실패: $e');
    }
  }

  /// 빠른 현재가 조회 (차트 데이터 제외)
  Future<double> _getQuickCurrentPrice(String stockCode) async {
    try {
      if (stockCode.isEmpty) return 0.0;
      // 캐시된 데이터 우선 확인
      final cachedData = AppDataManager.instance.getCachedStockData(stockCode);
      if (cachedData.isNotEmpty) {
        final cachedPrice = (cachedData['currentPrice'] ?? 0.0).toDouble();
        final ts = (cachedData['timestamp'] ?? '').toString();
        DateTime? cachedAt;
        if (ts.isNotEmpty) {
          try { cachedAt = DateTime.parse(ts); } catch (_) {}
        }
        final isFresh = cachedAt != null && DateTime.now().difference(cachedAt!).inSeconds <= 3;
        if (cachedPrice > 0 && isFresh) {
          return cachedPrice;
        }
      }
      
      // API에서 현재가만 빠르게 조회
      Map<String, dynamic>? priceData = await _unifiedApiService.getStockPrice(stockCode);
      
      if (priceData != null && priceData.isNotEmpty) {
        // API에서 반환된 데이터가 불변 맵일 수 있으므로 새로운 맵으로 복사
        final Map<String, dynamic> safePriceData = priceData;
        final currentPrice = _toDouble(safePriceData['currentPrice']);
        if (currentPrice > 0) {
          // 캐시 업데이트 (새로운 맵으로 복사)
          AppDataManager.instance.updateCurrentPrice(stockCode, safePriceData);
          return currentPrice;
        }
      }
      
      return 0.0;
    } catch (e) {
      print('❌ 빠른 현재가 조회 실패 ($stockCode): $e');
      return 0.0;
    }
  }

  double _getPriceUpdateThreshold(String stockCode) {
    // 국내: 0.005, 해외: 0.001
    return _isNasdaqStock(stockCode) ? 0.001 : 0.005;
  }

  /// 단일 종목 분석 (UI 업데이트 없이)
  Future<Map<String, dynamic>?> _performSingleStockAnalysis(String stockCode) async {
    try {
      // 관심종목에서 찾기
      final watchlistItem = _watchlistItems.firstWhere(
        (item) => item['stock_code'] == stockCode,
        orElse: () => <String, dynamic>{},
      );
      
      if (watchlistItem.isNotEmpty) {
        return await _performAnalysisForStock(watchlistItem);
      }
      
      // 보유종목에서 찾기
      final holdingItem = _holdingsItems.firstWhere(
        (item) => item['stockCode'] == stockCode,
        orElse: () => <String, dynamic>{},
      );
      
      if (holdingItem.isNotEmpty) {
        return await _performAnalysisForHolding(holdingItem);
      }
      
      return null;
    } catch (e) {
      print('❌ 단일 종목 분석 실패 ($stockCode): $e');
      return null;
    }
  }

  /// 종목들 분석
  Future<void> _analyzeStocks(List<String> stockCodes) async {
    print('🔍 분석탭 _analyzeStocks 함수 시작');
    print('📊 전달받은 stockCodes: $stockCodes');
    print('📊 _watchlistItems 개수: ${_watchlistItems.length}');
    print('📊 _holdingsItems 개수: ${_holdingsItems.length}');
    
    // 나스닥 종목 확인
    final nasdaqStocks = stockCodes.where((code) => _isNasdaqStock(code)).toList();
    print('🇺🇸 분석 대상 나스닥 종목: $nasdaqStocks');
    
    final config = KisUnifiedApiService().apiConfig;
    
    // 배치 업데이트를 위한 임시 저장소
    final Map<String, Map<String, dynamic>> tempAnalysisResults = {};
    
    // 관심종목 분석
    print('📋 관심종목 분석 시작...');
    for (final item in _watchlistItems) {
      print('📝 관심종목 분석: ${item['stock_code']} - ${item['stock_name']}');
      try {
        final result = await _performAnalysisForStock(item);
        if (result != null) {
          tempAnalysisResults[item['stock_code']] = result;
        }
      } catch (e) {
        print('❌ 관심종목 분석 실패 (${item['stock_code']}): $e');
      }
    }
    
    // 보유종목 분석
    print('💼 보유종목 분석 시작...');
    for (final holding in _holdingsItems) {
      print('📝 보유종목 분석: ${holding['stockCode']} - ${holding['stockName']}');
      try {
        final stockCode = holding['stockCode'] as String? ?? '';
        if (stockCode.isNotEmpty) {
          final result = await _performAnalysisForHolding(holding);
          if (result != null) {
            tempAnalysisResults[stockCode] = result;
          }
        }
      } catch (e) {
        print('❌ 보유종목 분석 실패 (${holding['stockCode']}): $e');
      }
    }
    
    // 배치 업데이트 - 한 번에 모든 결과를 UI에 반영 (화면 깜빡임 방지)
    if (mounted) {
      setState(() {
        _analysisResults.addAll(tempAnalysisResults);
      });
      print('✅ 배치 업데이트 완료: ${tempAnalysisResults.length}개 종목');
    }
    print('🔍 _analyzeStocks 함수 종료');
  }

  /// 주식별 분석 수행 (관심종목용)
  Future<Map<String, dynamic>?> _performAnalysisForStock(Map<String, dynamic> item) async {
    final stockCode = (item['stockCode'] ?? item['stock_code'] ?? '').toString();
    final stockName = item['stockName'] as String? ?? stockCode;
    print('🤖 [AnalysisScreen] 관심종목 분석 시작 ($stockCode - $stockName)');
    print('🔍 [AnalysisScreen] 입력 데이터: $item');

    try {
      // 1. 실시간 현재가 데이터 수집 및 캐시
      print('🔍 [AnalysisScreen] 현재가 데이터 수집 시작: $stockCode');
      final currentPriceData = await _collectAndCacheCurrentPriceData(stockCode);
      if (currentPriceData == null) {
        print('❌ 현재가 데이터 수집 실패 ($stockCode)');
        return null;
      }
      print('✅ [AnalysisScreen] 현재가 데이터 수집 완료: $stockCode');
      print('📊 [AnalysisScreen] 수집된 데이터: $currentPriceData');

      // 2. 차트 데이터 수집 및 캐시
      final chartData = await _collectAndCacheChartData(stockCode);
      if (chartData.isEmpty) {
        print('⚠️ 차트 데이터 없음 ($stockCode) - 기본값으로 분석 진행');
      }

      // 3. UnifiedAnalysisService를 사용하여 분석 수행 (서버 위임)
      final analysisResult = await _unifiedAnalysis.analyzeStock(stockCode, days: 100);

      if (analysisResult != null) {
        // 종목 정보 추가
        analysisResult['stockName'] = stockName;
        analysisResult['isWatchlist'] = true;
        
        // 수집된 데이터 추가
        analysisResult['currentPriceData'] = currentPriceData;
        analysisResult['chartData'] = chartData;
        
        print('✅ 관심종목 분석 완료 ($stockCode): ${analysisResult['signal']} (신뢰도: ${analysisResult['confidence']}%)');
        print('📊 종합 점수: ${analysisResult['comprehensiveScore']?.toStringAsFixed(3) ?? 'N/A'}');
        return analysisResult;
      } else {
        print('❌ 관심종목 분석 실패 ($stockCode)');
        return null;
      }
    } catch (e) {
      print('❌ 관심종목 분석 실패 ($stockCode): $e');
      return null;
    }
  }

  /// 주식별 분석 수행 (보유종목용)
  Future<Map<String, dynamic>?> _performAnalysisForHolding(Map<String, dynamic> holding) async {
    final stockCode = holding['stockCode'] as String? ?? '';
    final stockName = holding['stockName'] as String? ?? stockCode;
    final avgPrice = (holding['avgPrice'] ?? 0.0).toDouble();
    final quantity = (holding['quantity'] ?? 0).toInt();
    
    print('🤖 보유종목 분석 시작 ($stockCode - $stockName)');

    try {
      // 1. 실시간 현재가 데이터 수집 및 캐시
      print('🔍 [AnalysisScreen] 현재가 데이터 수집 시작: $stockCode');
      final currentPriceData = await _collectAndCacheCurrentPriceData(stockCode);
      if (currentPriceData == null) {
        print('❌ 현재가 데이터 수집 실패 ($stockCode)');
        return null;
      }
      print('✅ [AnalysisScreen] 현재가 데이터 수집 완료: $stockCode');
      print('📊 [AnalysisScreen] 수집된 데이터: $currentPriceData');

      // 2. 차트 데이터 수집 및 캐시
      final chartData = await _collectAndCacheChartData(stockCode);
      if (chartData.isEmpty) {
        print('⚠️ 차트 데이터 없음 ($stockCode) - 기본값으로 분석 진행');
      }

      // 3. UnifiedAnalysisService를 사용하여 분석 수행 (서버 위임)
      final analysisResult = await _unifiedAnalysis.analyzeStock(stockCode, days: 100);

      if (analysisResult != null) {
        // 보유종목 정보 추가
        analysisResult['stockName'] = stockName;
        analysisResult['avgPrice'] = avgPrice;
        analysisResult['quantity'] = quantity;
        analysisResult['isHolding'] = true;
        
        // 수집된 데이터 추가 (mappedData 사용)
        analysisResult['currentPriceData'] = {
          'currentPrice': _toDouble(currentPriceData['currentPrice']),
          'prevClose': _toDouble(currentPriceData['prevClose']),
          'volume': _toInt(currentPriceData['volume']),
          'highPrice': _toDouble(currentPriceData['highPrice']),
          'lowPrice': _toDouble(currentPriceData['lowPrice']),
          'openPrice': _toDouble(currentPriceData['openPrice']),
          'timestamp': currentPriceData['timestamp'] ?? DateTime.now().toIso8601String(),
        };
        analysisResult['chartData'] = chartData;
        
        // 수익률 계산
        final currentPrice = analysisResult['currentPrice'] ?? 0.0;
        double profitRate = 0.0;
        if (avgPrice > 0) {
          profitRate = ((currentPrice - avgPrice) / avgPrice) * 100;
        }
        analysisResult['profitRate'] = profitRate;
        
        print('✅ 보유종목 분석 완료 ($stockCode): ${analysisResult['signal']} (수익률: ${profitRate.toStringAsFixed(2)}%)');
        print('📊 종합 점수: ${analysisResult['comprehensiveScore']?.toStringAsFixed(3) ?? 'N/A'}');
        return analysisResult;
      } else {
        print('❌ 보유종목 분석 실패 ($stockCode)');
        return null;
      }
    } catch (e) {
      print('❌ 보유종목 분석 실패 ($stockCode): $e');
      return null;
    }
  }
  /// 실시간 현재가 데이터 수집 및 캐시 (강제 캐시 무효화)
  Future<Map<String, dynamic>?> _collectAndCacheCurrentPriceData(String stockCode) async {
    try {
      if (stockCode.isEmpty) {
        print('⚠️ 현재가 수집 스킵: 종목코드가 비어있음');
        return null;
      }
      print('📊 현재가 데이터 수집 시작 ($stockCode) - 강제 캐시 무효화');
      
      
      // 1. 모든 캐시 강제 무효화
      AppDataManager.instance.invalidateCache();
      UnifiedStockDataManager.instance.clearCache();
      _watchlistDataCache.remove(stockCode);
      _holdingsDataCache.remove(stockCode);
      _currentPrices.remove(stockCode);
      
      // 2. API에서 최신 데이터 조회 (캐시 완전 무시) - 추천종목과 동일한 방식
      Map<String, dynamic>? realtimeData = await RemoteKisService.instance.getCurrentPrice(stockCode);

      if (realtimeData != null && realtimeData.isNotEmpty) {
        print('🔍 [AnalysisScreen] 실시간 데이터 원본: $realtimeData');
        
        // API에서 반환된 데이터가 불변 맵일 수 있으므로 새로운 맵으로 복사
        final Map<String, dynamic> safeRealtimeData = realtimeData;
        
        // KIS API 서비스에서 공식 필드명 사용
        final currentPrice = _toDouble(safeRealtimeData['prpr']);
        final prevClose = _toDouble(safeRealtimeData['stck_prdy_clpr']);
        final volume = _toInt(safeRealtimeData['acml_vol']);
        final highPrice = _toDouble(safeRealtimeData['high']);
        final lowPrice = _toDouble(safeRealtimeData['low']);
        final openPrice = _toDouble(safeRealtimeData['open'] ?? safeRealtimeData['stck_oprc'] ?? 0.0);
        final changeAmount = _toDouble(safeRealtimeData['diff']);
        final changeRate = _toDouble(safeRealtimeData['rate']);
        final tradeAmount = _toDouble(safeRealtimeData['tradeAmount']);
        
        print('🔍 [AnalysisScreen] 파싱된 데이터: currentPrice=$currentPrice, prevClose=$prevClose, volume=$volume');
        print('🔍 [AnalysisScreen] 원본 API 데이터 상세:');
        print('  - prpr: ${safeRealtimeData['prpr']}');
        print('  - stck_prdy_clpr: ${safeRealtimeData['stck_prdy_clpr']}');
        print('  - high: ${safeRealtimeData['high']}');
        print('  - low: ${safeRealtimeData['low']}');
        print('  - open: ${safeRealtimeData['open']}');
        print('  - stck_oprc: ${safeRealtimeData['stck_oprc']}');
        print('  - 최종 openPrice: $openPrice');
        
        // 매핑된 데이터로 새로운 맵 생성
        final mappedData = {
          'currentPrice': currentPrice,
          'prevClose': prevClose,
          'volume': volume,
          'highPrice': highPrice,
          'lowPrice': lowPrice,
          'openPrice': openPrice,
          'changeAmount': changeAmount,
          'changeRate': changeRate,
          'tradeAmount': tradeAmount,
          'timestamp': DateTime.now().toIso8601String(),
        };
        
        // API에서 받은 실시간 데이터를 그대로 사용 (히스토리 데이터 보정 제거)
        print('✅ [AnalysisScreen] $stockCode 실시간 API 데이터 사용:');
            print('  - 현재가: ${mappedData['currentPrice']}');
            print('  - 전일가: ${mappedData['prevClose']}');
            print('  - 고가: ${mappedData['highPrice']}');
            print('  - 저가: ${mappedData['lowPrice']}');
            print('  - 시가: ${mappedData['openPrice']}');
            print('  - 거래량: ${mappedData['volume']}');
        
        if (currentPrice > 0) {
          // 캐시에 저장 (새로운 맵으로 복사)
          _watchlistDataCache[stockCode] = mappedData;
          _holdingsDataCache[stockCode] = mappedData;
          
          // AppDataManager 캐시에도 저장 (안전한 복사)
          try {
            AppDataManager.instance.updateCurrentPrice(stockCode, mappedData);
          } catch (e) {
            print('⚠️ AppDataManager 캐시 업데이트 실패 ($stockCode): $e');
          }
          
          // 로컬 DB 저장은 중앙 데이터 파이프라인에서 처리 (중복 저장 방지)
          
          print('📊 실시간 현재가 데이터 수집 완료 ($stockCode): $currentPrice');
          return mappedData;
        }
      }

      print('❌ 현재가 데이터 수집 실패 ($stockCode)');
      return null;
    } catch (e) {
      print('❌ 현재가 데이터 수집 실패 ($stockCode): $e');
      return null;
    }
  }

  /// 차트 데이터 수집 및 캐시 (3분 간격)
  Future<List<Map<String, dynamic>>> _collectAndCacheChartData(String stockCode) async {
    try {
      if (stockCode.isEmpty) {
        print('⚠️ 차트 수집 스킵: 종목코드가 비어있음');
        return [];
      }
      print('📈 차트 데이터 수집 시작 ($stockCode)');
      
      // 1. 캐시된 차트 데이터 확인 (3분 이내)
      final cachedChartData = AppDataManager.instance.getCachedChartData(stockCode);
      if (cachedChartData.isNotEmpty) {
        final cachedTimestamp = AppDataManager.instance.getChartDataTimestamp(stockCode);
        if (cachedTimestamp != null && DateTime.now().difference(cachedTimestamp).inMinutes < 3) {
          print('📊 캐시된 차트 데이터 사용 ($stockCode): ${cachedChartData.length}개 (${DateTime.now().difference(cachedTimestamp).inMinutes}분 전)');
          return cachedChartData;
        }
      }

      // 2. API에서 차트 데이터 조회 (여유 있게 요청)
      List<Map<String, dynamic>> chartData = await RemoteKisService.instance.getDailyChart(stockCode, days: 100);

      if (chartData.isNotEmpty) {
        print('🔍 [AnalysisScreen] 차트 데이터 원본 (첫 3개): ${chartData.take(3).toList()}');
        
        // KIS API 서비스에서 이미 변환된 키 사용 (차트 데이터)
        final mappedChartData = chartData.map((data) {
          return {
            'date': data['date'] ?? '',
            'open': _toDouble(data['open']),
            'high': _toDouble(data['high']),
            'low': _toDouble(data['low']),
            'close': _toDouble(data['close']),
            'volume': _toInt(data['volume']),
          };
        }).toList();
        
        print('🔍 [AnalysisScreen] 매핑된 차트 데이터 (첫 3개): ${mappedChartData.take(3).toList()}');
        
        // 2-1. 최근 100 거래일로 슬라이싱 (정렬 및 결측 제거 포함) - 추천종목과 통일
        mappedChartData.sort((a, b) {
          final da = (a['date'] ?? '').toString();
          final db = (b['date'] ?? '').toString();
          return da.compareTo(db);
        });
        final cleaned = mappedChartData.where((e) =>
          (e['date'] ?? '').toString().isNotEmpty &&
          (e['open'] != null && e['high'] != null && e['low'] != null && e['close'] != null)
        ).toList();
        final int n = 100; // 🔧 60 → 100으로 통일 (추천종목과 동일)
        final int start = cleaned.length > n ? cleaned.length - n : 0;
        final recentN = cleaned.sublist(start);
        
        // AppDataManager 캐시에 저장 (로컬 DB 저장은 중앙 파이프라인에서 처리)
        AppDataManager.instance.cacheChartData(stockCode, recentN);
        
        print('📊 차트 데이터 수집 완료 ($stockCode): 총 ${mappedChartData.length}개 → 최근 ${recentN.length}개(100거래일)');
        return recentN;
      }

      print('⚠️ 차트 데이터 없음 ($stockCode)');
      return [];
    } catch (e) {
      print('❌ 차트 데이터 수집 실패 ($stockCode): $e');
      return [];
    }
  }

  // 제거: 로컬 DB 직접 저장 메서드 (중앙 데이터 파이프라인으로 통합)

  // 제거: 히스토리 데이터 로컬 DB 저장 (중앙 파이프라인에서 수행)

  /// 데이터 정리 수행 (1시간 간격)
  Future<void> _performDataCleanup() async {
    try {
      print('🧹 데이터 정리 시작...');
      
      // 1. 오래된 실시간 데이터 정리 (24시간 이상)
      final oneDayAgo = DateTime.now().subtract(const Duration(days: 1));
      await _realtimeDataRepository.deleteOldData(before: oneDayAgo);
      print('🧹 오래된 실시간 데이터 정리 완료');
      
      // 2. 오래된 히스토리 데이터 정리 (90일 이상)
      final threeMonthsAgo = DateTime.now().subtract(const Duration(days: 90));
      await _historicalDataRepository.deleteOldData(before: threeMonthsAgo);
      print('🧹 오래된 히스토리 데이터 정리 완료');
      
      // 3. 메모리 캐시 정리 (1시간 이상)
      _cleanupMemoryCache();
      print('🧹 메모리 캐시 정리 완료');
      
      print('✅ 데이터 정리 완료');
    } catch (e) {
      print('❌ 데이터 정리 실패: $e');
    }
  }

  /// 메모리 캐시 정리
  void _cleanupMemoryCache() {
    final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
    
    // 현재가 캐시 정리
    _watchlistDataCache.removeWhere((stockCode, data) {
      final timestamp = data['timestamp'] as String?;
      if (timestamp != null) {
        final cacheTime = DateTime.tryParse(timestamp);
        return cacheTime != null && cacheTime.isBefore(oneHourAgo);
      }
      return false;
    });
    
    _holdingsDataCache.removeWhere((stockCode, data) {
      final timestamp = data['timestamp'] as String?;
      if (timestamp != null) {
        final cacheTime = DateTime.tryParse(timestamp);
        return cacheTime != null && cacheTime.isBefore(oneHourAgo);
      }
      return false;
    });
    
    print('🧹 메모리 캐시 정리: ${_watchlistDataCache.length}개 관심종목, ${_holdingsDataCache.length}개 보유종목');
  }

  /// 가격 표시 형식 결정 (나스닥/국내 종목 구분)
  String _formatPriceForDisplay(double price, bool isNasdaq, {bool showSign = false}) =>
      AnalysisFormatters.formatPriceForDisplay(price, isNasdaq, showSign: showSign);

  /// 현재가와 등락률을 함께 표시
  String _formatPriceWithChange(double currentPrice, double prevClose, bool isNasdaq) =>
      AnalysisFormatters.formatPriceWithChange(currentPrice, prevClose, isNasdaq);

  /// 분석 데이터 새로고침 (수동 새로고침 - 로딩 표시 포함)
  Future<void> _refreshAnalysisData() async {
    print('🔄 분석 데이터 새로고침 시작 (수동 - 강제 새로고침)...');
    
    try {
      // 현재 스크롤 위치 저장
      final currentTab = _tabController.index;
      
      // 🔧 강제 새로고침: 캐시 무효화 후 새로 계산
      await _forceRefreshAnalysis();
      
      // 현재 탭 유지
      if (mounted && _tabController.index != currentTab) {
        _tabController.animateTo(currentTab);
      }
      
      print('✅ 분석 데이터 새로고침 완료 (수동 - 강제 새로고침)');
    } catch (e) {
      print('❌ 분석 데이터 새로고침 실패: $e');
    }
  }

  // 더미 데이터 함수들 제거됨 - 실제 API 데이터만 사용

  /// 종목 이름 가져오기
  String _getDisplayName(dynamic item) {
    String stockCode = '';
    String stockName = '';
    
    if (item is Map<String, dynamic>) {
      // 보유종목과 관심종목의 키 구조가 다름
      stockCode = item['stock_code'] as String? ?? 
                  item['stockCode'] as String? ?? '';
      stockName = item['stock_name'] as String? ?? 
                  item['stockName'] as String? ?? '';
      
      print('�� _getDisplayName 디버그:');
      print('  - item 키들: ${item.keys.toList()}');
      print('  - stockCode: $stockCode');
      print('  - stockName: $stockName');
    }
    
    // 1. 데이터베이스에서 가져온 종목명이 있으면 사용
    if (stockName.isNotEmpty && stockName != stockCode) {
      print('📝 종목명 사용 (데이터베이스): $stockName');
      return stockName;
    }
    
    // 2. AppDataManager에서 종목명 조회
    if (stockCode.isNotEmpty) {
      final masterName = AppDataManager.instance.getStockName(stockCode);
      if (masterName.isNotEmpty && masterName != stockCode) {
        print('📝 종목명 조회 (AppDataManager) ($stockCode): $masterName');
        return masterName;
      }
    }
    
    // 3. 최후 수단으로 종목코드 반환
    final result = stockCode.isNotEmpty ? stockCode : 'Unknown';
    print('📝 최종 종목명: $result');
    return result;
  }

  /// 투자 스타일 이름 반환
  String _getStyleName(InvestmentStyle style) {
    switch (style) {
      case InvestmentStyle.conservative:
        return '안정적 투자';
      case InvestmentStyle.moderate:
        return '일반적 투자';
      case InvestmentStyle.aggressive:
        return '공격적 투자';
    }
  }

  /// 투자 스타일 색상 가져오기
  Color _getStyleColor(InvestmentStyle style) {
    switch (style) {
      case InvestmentStyle.conservative:
        return Colors.green; // 초록색 (방패)
      case InvestmentStyle.moderate:
        return const Color(0xFF3B5BA9); // 파란색 (천칭)
      case InvestmentStyle.aggressive:
        return Colors.red; // 빨간색 (상향)
    }
  }
  /// 투자 스타일 아이콘 가져오기
  IconData _getStyleIcon(InvestmentStyle style) {
    switch (style) {
      case InvestmentStyle.conservative:
        return Icons.security; // 방패 아이콘
      case InvestmentStyle.moderate:
        return Icons.balance; // 천칭 아이콘
      case InvestmentStyle.aggressive:
        return Icons.trending_up; // 상향 아이콘
    }
  }

  /// 선택된 종목 삭제
  Future<void> _deleteSelectedItems() async {
    if (_selectedItems.isEmpty) {
      print('⚠️ 삭제할 종목이 선택되지 않음');
      return;
    }
    
    print('🗑️ 선택된 종목 삭제 시작: ${_selectedItems.length}개');
    print('🗑️ 삭제할 종목 코드: ${_selectedItems.toList()}');
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('종목 삭제'),
        content: Text('선택된 ${_selectedItems.length}개 종목을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      print('✅ 삭제 확인됨, 관심종목에서 제거 시작');
      
      // 관심종목에서 삭제
      final watchlistRepository = WatchlistRepository();
      for (final stockCode in _selectedItems) {
        try {
          await watchlistRepository.removeFromWatchlist(stockCode);
          print('✅ $stockCode 관심종목에서 제거 완료');
        } catch (e) {
          print('❌ $stockCode 제거 실패: $e');
        }
      }
      
      // UI 업데이트
      await _loadWatchlist();
      setState(() {
        _selectedItems.clear();
        _isSelectionMode = false;
      });
      
      print('✅ 삭제 완료 및 UI 업데이트');
    } else {
      print('❌ 삭제 취소됨');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 상태표시줄을 투명하게 설정하여 앱바와 연속되도록 함
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );
    
    final hasApiConfig = KisUnifiedApiService().apiConfig['isValid'] as bool? ?? false;
    final isHoldingsTab = _tabController.index == 1; // 보유종목 탭인지 확인
    
    return Scaffold(
      appBar: GradientAppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '분석',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              _getStyleIcon(_styleManager.currentStyle),
              color: Colors.white,
              size: 24,
            ),
            if (_isAutoTradingEnabled) ...[
              const SizedBox(width: 8),
              const Text(
                'AI 자동매매중',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ],
        ),
        colors: _styleManager.getGradientColors(),
        actions: [
          // 새로고침 아이콘 (모든 탭에서 사용 가능)
          IconButton(
            onPressed: _refreshAnalysisData,
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: '분석 데이터 새로고침',
          ),
          // 보유종목 탭이 아닐 때만 삭제 관련 UI 표시
          if (!isHoldingsTab) ...[
            if (_isSelectionMode && _selectedItems.isNotEmpty)
              TextButton.icon(
                onPressed: _deleteSelectedItems,
                icon: const Icon(Icons.delete_outline, color: Colors.white),
                label: const Text('삭제', style: TextStyle(color: Colors.white)),
              ),
            IconButton(
              onPressed: () {
                setState(() {
                  _isSelectionMode = !_isSelectionMode;
                  if (!_isSelectionMode) {
                    _selectedItems.clear();
                  }
                });
              },
              icon: Icon(
                _isSelectionMode ? Icons.close : Icons.delete_outline,
                color: Colors.white,
              ),
            ),
          ],
          // 거래 상태 관리 메뉴
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: _handleTradeStatusAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'sync',
                child: Row(
                  children: [
                    Icon(Icons.sync, size: 16),
                    SizedBox(width: 8),
                    Text('거래 상태 동기화'),
                  ],
                ),
              ),
                              const PopupMenuItem(
                  value: 'rebuild',
                  child: Row(
                    children: [
                      Icon(Icons.refresh, size: 16),
                      SizedBox(width: 8),
                      Text('거래 상태 재구성'),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'detect',
                child: Row(
                  children: [
                    Icon(Icons.search, size: 16),
                    SizedBox(width: 8),
                    Text('보유종목 자동감지'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.clear_all, size: 16),
                    SizedBox(width: 8),
                    Text('거래 상태 초기화'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            // API 설정 안내
            if (!hasApiConfig) _buildApiSetupGuide(),
            
            // 탭 바
            Container(
              color: Colors.white,
              child: TabBar(
                controller: _tabController,
                labelColor: _getStyleColor(_currentStyle),
                unselectedLabelColor: Colors.grey,
                indicatorColor: _getStyleColor(_currentStyle),
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.favorite, size: 16),
                        const SizedBox(width: 4),
                        Text('관심종목 (${_watchlistItems.length})'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.account_balance_wallet, size: 16),
                        const SizedBox(width: 4),
                        Text('보유종목 (${_holdingsItems.length})'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.star, size: 16),
                        const SizedBox(width: 4),
                        const Text('추천종목'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // 탭 내용
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // 관심종목 탭
                  _buildWatchlistTab(),
                  // 보유종목 탭
                  _buildHoldingsTab(),
                  // 추천종목 탭
                  _buildRecommendedStocksTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  /// 관심종목 탭
  Widget _buildWatchlistTab() {
    return WatchlistTab(
      key: const PageStorageKey('watchlist-tab'),
      isLoading: _isLoading,
      isFirstLoading: _isFirstLoading,
      watchlistItems: _watchlistItems,
      getStyleName: (style) => _getStyleName(_currentStyle),
      onRefresh: () async => _refreshAllAnalysis(),
      buildEmptyApiGuide: () => _buildApiSetupGuide(),
      buildAnalysisList: (items) => _buildAnalysisList(items),
    );
  }

  /// 보유종목 탭
  Widget _buildHoldingsTab() {
    final hasApiConfig = KisUnifiedApiService().apiConfig['isValid'] as bool? ?? false;
    return HoldingsTab(
      key: const PageStorageKey('holdings-tab'),
      isLoading: _isLoading,
      isFirstLoading: _isFirstLoading,
      hasApiConfig: hasApiConfig,
      holdingsItems: _holdingsItems,
      onApiReconnect: () async {
                  try {
                    await KisUnifiedApiService().initialize(
            appKey: ApiConfig.instance.appKey!,
            appSecret: ApiConfig.instance.appSecret!,
            accountNumber: ApiConfig.instance.accountNo!,
          );
                    await _loadHoldings();
                  } catch (e) {
                    print('❌ API 재인증 실패: $e');
                  }
                },
      onRefresh: () async => _refreshAllAnalysis(),
      buildAnalysisList: (items) => _buildAnalysisList(items),
    );
  }

  /// 시그널 처리 및 자동매매 실행 (비동기)
  Future<void> _handleSignalAndAutoTrading(
    dynamic item,
    String stockCode,
    Map<String, dynamic>? analysis,
    Map<String, dynamic>? currentPriceData,
  ) async {
    if (analysis == null) return;
    
    final signal = analysis['signal'] as String? ?? '관망';
    final stockName = analysis['stockName'] as String? ?? '';
    
    // 시그널 시간 추적 및 고정
    if (signal == '매수' || signal == '매도') {
      final now = DateTime.now();
      final lastSignal = _lastSignals[stockCode];
      
      print('🔍 시그널 처리 중: $stockCode - 현재시그널=$signal, 이전시그널=$lastSignal');
      
      // 새로운 시그널이거나 시그널이 변경된 경우에만 시간 기록 (중복 방지)
      if (lastSignal != signal) {
        // 중복 시그널 방지 (15분 내 동일 시그널 무시)
        final lastTimestamp = _signalTimestamps[stockCode];
        if (lastTimestamp != null) {
          final timeDiff = now.difference(lastTimestamp);
          if (timeDiff < const Duration(minutes: 15)) {
            print('⏱️ 중복 시그널 방지: $stockCode - $signal (${timeDiff.inMinutes}분 전 발생)');
            return;
          }
        }
        
        _signalTimestamps[stockCode] = now;
        _lastSignals[stockCode] = signal;
        
        // 자동매매 상태 확인
        final isAutoTradingEnabled = await AppDataManager.instance.getAutoTradingStatus();
        print('🔍 자동매매 상태 확인: enabled=$isAutoTradingEnabled');
        
        // 자동매매 상태에 따라 시그널 타입 결정
        String signalType = signal;
        if (!isAutoTradingEnabled) {
          signalType = signal == '매수' ? '매수 기회' : '매도 기회';
          print('📊 자동매매 OFF - 시그널 타입 변경: $signal → $signalType');
        }
        
        // 시그널 추적은 AutoTradingCycle에서 처리하므로 여기서는 건너뜀
        print('🎯 분석탭 시그널 감지: $stockCode ($stockName) - $signalType (${now.hour}:${now.minute.toString().padLeft(2, '0')})');
        print('⚠️ 분석탭 시그널은 AutoTradingCycle에서 처리됨: $stockCode $signal');
      } else {
        print('ℹ️ 시그널 중복 무시: $stockCode - $signal (이전과 동일)');
      }
    }
  }

  /// 분석 리스트 공통 위젯
  Widget _buildAnalysisList(List<dynamic> items) {
    return AnalysisListView(
      items: items,
      watchlistScrollController: _watchlistScrollController,
      holdingsScrollController: _holdingsScrollController,
      currentTabIndex: _tabController.index,
      currentPrices: _currentPrices,
      analysisResults: _analysisResults,
      selectedItems: _selectedItems,
      buildAnalysisCard: (item, currentPriceData, analysis, isSelected) => _buildAnalysisCard(
              item,
              currentPriceData,
                  analysis,
              isSelected,
              ),
    );
  }

  /// API 설정 안내
  Widget _buildApiSetupGuide() => const ApiSetupGuide();

  /// 분석 카드
  Widget _buildAnalysisCard(
    dynamic item,
    Map<String, dynamic>? currentPriceData,
    Map<String, dynamic>? analysisData,
    bool isSelected,
  ) {
    final stockCode = item['stock_code'] as String? ?? item['stockCode'] as String? ?? '';
    
    return AnalysisCard(
      item: Map<String, dynamic>.from(item as Map),
      currentPriceData: currentPriceData,
      analysisData: analysisData,
      isSelected: isSelected,
      isSelectionMode: _isSelectionMode && _tabController.index != 1, // 보유종목 탭이 아닐 때만
      onSelectionChanged: () {
        setState(() {
          if (stockCode.isNotEmpty) {
            if (isSelected) {
              _selectedItems.remove(stockCode);
            } else {
              _selectedItems.add(stockCode);
            }
          }
        });
      },
      buildStockHeader: (it, cp) => StockHeader(
        item: Map<String, dynamic>.from(it as Map),
        currentPriceData: cp,
        getAnalysisForCode: (code) => _analysisResults[code],
        isNasdaqStock: _isNasdaqStock,
        getDisplayName: _getDisplayName,
      ),
      buildHoldingsInfo: (holding, analysis) => HoldingsInfo(
        holding: Map<String, dynamic>.from(holding as Map),
        analysis: analysis,
        getCurrentPrices: () => _currentPrices,
        isNasdaqStock: _isNasdaqStock,
      ),
      buildInvestmentStyleInfo: _buildInvestmentStyleInfo,
      buildIntegratedAnalysisSection: (i, a) async => IntegratedAnalysisSection(
        item: Map<String, dynamic>.from(i as Map),
        analysis: a,
        isNasdaqStock: _isNasdaqStock,
        getIndicatorScore: _getIndicatorScore,
        getKoreanIndicatorName: _getKoreanIndicatorName,
        getIndicatorKey: _getIndicatorKey,
        formatNumber: _formatNumber,
        generateDetailedReason: _generateDetailedReason,
        generateComprehensiveAnalysisReason: _generateComprehensiveAnalysisReason,
        loadStyleParams: () async {
          final currentUserStyle = await _styleManager.getCurrentStyle();
          return _styleManager.getStyleParameters(currentUserStyle);
        },
      ),
      buildLoadingSection: _buildLoadingSection,
      buildNoApiMessage: _buildNoApiMessage,
      buildAnalysisTimeInfo: _buildAnalysisTimeInfo,
      buildSignalTimeInfo: _buildSignalTimeInfo,
      buildTradeStatusOverlay: _buildTradeStatusOverlay,
      buildTradingTimeOverlay: _buildTradingTimeOverlay,
    );
  }
  

  /// 나스닥 종목인지 확인 (실제 데이터베이스 market 필드 사용)
  bool _isNasdaqStock(String stockCode) {
    // 관심종목에서 해당 종목의 market 정보 확인
    final watchlistItem = _watchlistItems.firstWhere(
      (item) => item['stock_code'] == stockCode,
      orElse: () => <String, dynamic>{},
    );
    
    // 보유종목에서 해당 종목의 market 정보 확인
    final holdingItem = _holdingsItems.firstWhere(
      (item) => item['stockCode'] == stockCode,
      orElse: () => <String, dynamic>{},
    );
    
    // market이 'NASDAQ'이면 나스닥 종목
    final dynamic marketRaw = watchlistItem['market'] ?? holdingItem['market'];
    final String? market = marketRaw is String ? marketRaw : null;

    // AppDataManager에서 보조 정보 확인
    String? marketFromInfo;
    try {
      final info = AppDataManager.instance.getStockInfo(stockCode);
      final dynamic m = info?['market'];
      marketFromInfo = m is String ? m : null;
    } catch (_) {}

    final String marketUpper = (market ?? marketFromInfo ?? '').toUpperCase();
    final String code = stockCode.trim().toUpperCase();

    // 미국 시장 코드 전반을 달러 표기로 처리 (NASDAQ, NASD, NYSE, AMEX 등)
    final bool isUsMarket = marketUpper == 'NASDAQ' ||
        marketUpper == 'NASD' ||
        marketUpper == 'NYSE' ||
        marketUpper == 'AMEX' ||
        marketUpper == 'US' ||
        marketUpper == 'USA';

    // 패턴 기반 휴리스틱
    // - 전부 대문자 알파벳/점(.) 1~10자리 → 미국 티커로 간주 (예: BRK.B)
    // - 하나라도 알파벳이 포함되고 전체가 숫자만은 아님 → 미국 티커로 간주
    final bool isLikelyUsTicker =
        RegExp(r'^[A-Z\.]{1,10}$').hasMatch(code) ||
        (RegExp(r'[A-Z]').hasMatch(code) && !RegExp(r'^\d+$').hasMatch(code));

    final bool isNasdaq = isUsMarket || isLikelyUsTicker;

    // 디버그 로그 (필요시에만 출력)
    if (code.startsWith('A') || code.startsWith('Q') || code.startsWith('T') || code.startsWith('N')) {
      print('🔍 나스닥/미국 종목 확인: $code -> market=$marketUpper, isUsMarket=$isUsMarket, heuristic=$isLikelyUsTicker, result=$isNasdaq');
    }
    
    return isNasdaq;
  }
  /// 모든 보유종목 데이터 강제 갱신
  Future<void> _forceRefreshAllHoldingsData() async {
    try {
      print('🔍 모든 보유종목 데이터 강제 갱신 시작...');
      
      int updatedCount = 0;
      
      // 모든 보유종목에 대해 API에서 최신 데이터 조회
      for (int i = 0; i < _holdingsItems.length; i++) {
        final holding = _holdingsItems[i];
        final stockCode = holding['stockCode'] as String?;
        final stockName = holding['stockName'] as String?;
        
        if (stockCode != null && stockCode.isNotEmpty) {
            try {
              print('🔄 보유종목 데이터 갱신: $stockCode ($stockName)');
              
              // 캐시 강제 무효화
              UnifiedStockDataManager.instance.clearCache();
              AppDataManager.instance.invalidateCache();
              
              // API 호출 간격 조정 (모든 종목 동일 처리)
              await Future.delayed(const Duration(milliseconds: 200));
              
              // 1. API에서 최신 데이터 조회
            final currentPriceData = await _collectAndCacheCurrentPriceData(stockCode);
            if (currentPriceData != null && currentPriceData['currentPrice'] != null) {
              // 2. 보유종목 데이터에서 현재가 업데이트
              final updatedHolding = Map<String, dynamic>.from(holding);
              final oldPrice = holding['currentPrice'] ?? holding['current_price'] ?? 0.0;
              final newPrice = currentPriceData['currentPrice'];
              
              updatedHolding['currentPrice'] = newPrice;
              updatedHolding['current_price'] = newPrice;
              _holdingsItems[i] = updatedHolding;
              
              updatedCount++;
              print('✅ $stockCode 보유종목 데이터 업데이트: $oldPrice → $newPrice');
            } else {
              print('⚠️ $stockCode API 데이터 조회 실패');
            }
          } catch (e) {
            print('❌ $stockCode 데이터 갱신 실패: $e');
          }
        }
      }
      
      // 3. UI 업데이트
      if (mounted && updatedCount > 0) {
        setState(() {
          // 상태 업데이트로 UI 갱신
        });
        print('✅ 보유종목 데이터 강제 갱신 완료: $updatedCount개 종목 업데이트');
      } else {
        print('✅ 보유종목 데이터 강제 갱신 완료: 변경사항 없음');
      }
    } catch (e) {
      print('❌ 모든 보유종목 데이터 강제 갱신 실패: $e');
    }
  }

  /// 보유종목 정보 표시
  

  Widget _buildAnalysisSection(dynamic item, Map<String, dynamic> analysis) {
    return AnalysisSectionView(
      item: Map<String, dynamic>.from(item as Map),
      analysis: analysis,
      isNasdaqStock: _isNasdaqStock,
      buildColoredSignalSummary: _buildColoredSignalSummary,
    );
  }

  /// 시그널 요약 생성 (개별 지표 점수 기반)
  Widget _buildColoredSignalSummary(Map<String, dynamic> analysis) {
    return ColoredSignalSummary(
      analysis: analysis,
      isNasdaqStock: _isNasdaqStock,
      getIndicatorKey: _getIndicatorKey,
      generateDetailedReason: _generateDetailedReason,
      getKoreanIndicatorName: _getKoreanIndicatorName,
      getActualValueText: _getActualValueText,
    );
  }
  /// 지표별 상세한 이유 생성 (한글)
  String _generateDetailedReason(String indicatorName, double score, String signal, Map<String, dynamic> analysis) {
    // 상세 분석 결과가 있으면 사용
    final detailedAnalysis = analysis['detailedAnalysis'] as Map<String, dynamic>? ?? {};
    
    // 지표명 매핑
    final indicatorKey = _getIndicatorKey(indicatorName);
    final indicatorAnalysis = detailedAnalysis[indicatorKey];
    
    if (indicatorAnalysis != null && indicatorAnalysis['analysis'] != null) {
      return indicatorAnalysis['analysis'] as String;
    }
    
    // 상세 분석이 없으면 기존 로직 사용
    final currentPrice = (analysis['currentPrice'] as num?)?.toDouble() ?? 0.0;
    final prevClose = (analysis['prevClose'] as num?)?.toDouble() ?? currentPrice;
    final technicalData = analysis['technicalData'] as Map<String, dynamic>? ?? {};
    
    // 가격 변화율 계산
    final priceChangePercent = prevClose > 0 ? ((currentPrice - prevClose) / prevClose) * 100 : 0.0;
    
    // 지표명 한글화 매핑
    final koreanName = _getKoreanIndicatorName(indicatorName);
    
    switch (indicatorName.toLowerCase()) {
      case 'rsi':
        // 실제 분석된 RSI 값 사용
        final rsiValue = (technicalData['rsi'] as num?)?.toDouble();
        if (rsiValue == null || rsiValue == 0.0) {
          return 'RSI 데이터 부족 - 관망 권장';
        }
        
        if (signal == '매수') {
          if (rsiValue <= 30) {
            return 'RSI ${rsiValue.toStringAsFixed(1)} (과매도) - 🔥 강한 매수 신호! 반등 기대';
          } else if (rsiValue <= 40) {
            return 'RSI ${rsiValue.toStringAsFixed(1)} (매수 구간) - 📈 매수 신호';
          } else if (rsiValue <= 50) {
            return 'RSI ${rsiValue.toStringAsFixed(1)} (중립 하회) - 📊 약한 매수 신호';
          } else {
            return 'RSI ${rsiValue.toStringAsFixed(1)} (상승 추세) - 📈 매수 신호';
          }
        } else if (signal == '매도') {
          if (rsiValue >= 70) {
            return 'RSI ${rsiValue.toStringAsFixed(1)} (과매수) - ⚠️ 강한 매도 신호! 하락 예상';
          } else if (rsiValue >= 60) {
            return 'RSI ${rsiValue.toStringAsFixed(1)} (매도 구간) - 📉 매도 신호';
          } else if (rsiValue >= 50) {
            return 'RSI ${rsiValue.toStringAsFixed(1)} (중립 상회) - 📊 약한 매도 신호';
          } else {
            return 'RSI ${rsiValue.toStringAsFixed(1)} (하락 추세) - 📉 매도 신호';
          }
        } else {
          return 'RSI ${rsiValue.toStringAsFixed(1)} (중립) - ⚖️ 관망';
        }
        
      case 'macd':
        final macdValue = (technicalData['macd'] as num?)?.toDouble();
        final signalValue = (technicalData['signal'] as num?)?.toDouble();
        
        if (macdValue == null || signalValue == null) {
          return 'MACD 데이터 부족 - 관망 권장';
        }
        
        final histogram = macdValue - signalValue;
        
        if (signal == '매수') {
          if (histogram > 0) {
            return 'MACD ${macdValue.toStringAsFixed(3)} > 신호선 ${signalValue.toStringAsFixed(3)} (골든크로스) - 🔥 강한 매수 신호! 상승 모멘텀';
          } else {
            return 'MACD ${macdValue.toStringAsFixed(3)} < 신호선 ${signalValue.toStringAsFixed(3)} (골든크로스 예상) - 📈 매수 신호';
          }
        } else if (signal == '매도') {
          if (histogram < 0) {
            return 'MACD ${macdValue.toStringAsFixed(3)} < 신호선 ${signalValue.toStringAsFixed(3)} (데드크로스) - ⚠️ 강한 매도 신호! 하락 모멘텀';
          } else {
            return 'MACD ${macdValue.toStringAsFixed(3)} > 신호선 ${signalValue.toStringAsFixed(3)} (데드크로스 예상) - 📉 매도 신호';
          }
        } else {
          return 'MACD ${macdValue.toStringAsFixed(3)} ≈ 신호선 ${signalValue.toStringAsFixed(3)} (중립) - ⚖️ 관망';
        }
        
      case '볼린저밴드':
        final bbUpper = (technicalData['bbUpper'] as num?)?.toDouble();
        final bbLower = (technicalData['bbLower'] as num?)?.toDouble();
        final bbMiddle = (technicalData['bbMiddle'] as num?)?.toDouble();
        
        if (bbUpper == null || bbLower == null || bbMiddle == null) {
          return '가격 변동성이 낮아 분석이 어려움 - 관망 권장';
        }
        
        // 현재가가 볼린저밴드의 어느 위치에 있는지 계산
        final bandWidth = bbUpper - bbLower;
        final position = bandWidth > 0 ? ((currentPrice - bbLower) / bandWidth) * 100 : 50.0;
        
        if (signal == '매수') {
          if (currentPrice <= bbLower) {
            return '현재가 \$${_formatNumber(currentPrice)}이 하단 지지선 \$${_formatNumber(bbLower)}에 닿아 반등 기대 - 매수 기회';
          } else if (position < 30) {
            return '현재가 \$${_formatNumber(currentPrice)}이 하단 근처 (${position.toStringAsFixed(0)}% 위치) - 저점 매수 기회';
          } else {
            return '현재가 \$${_formatNumber(currentPrice)}이 중간선 \$${_formatNumber(bbMiddle)} 위로 상승 중 - 매수 신호';
          }
        } else if (signal == '매도') {
          if (currentPrice >= bbUpper) {
            return '현재가 \$${_formatNumber(currentPrice)}이 상단 저항선 \$${_formatNumber(bbUpper)}에 닿아 하락 예상 - 매도 권장';
          } else if (position > 70) {
            return '현재가 \$${_formatNumber(currentPrice)}이 상단 근처 (${position.toStringAsFixed(0)}% 위치) - 고점 매도 기회';
          } else {
            return '현재가 \$${_formatNumber(currentPrice)}이 중간선 \$${_formatNumber(bbMiddle)} 아래로 하락 중 - 매도 신호';
          }
        } else {
          return '현재가 \$${_formatNumber(currentPrice)}이 중간선 \$${_formatNumber(bbMiddle)} 근처 (${position.toStringAsFixed(0)}% 위치) - 관망';
        }
        
      case '이동평균선':
        final ma5 = (technicalData['ma5'] as num?)?.toDouble();
        final ma20 = (technicalData['ma20'] as num?)?.toDouble();
        final ma60 = (technicalData['ma60'] as num?)?.toDouble();
        
        if (ma5 == null || ma20 == null || ma60 == null) {
          return '이동평균선 데이터 부족 - 관망 권장';
        }
        
        if (signal == '매수') {
          if (currentPrice > ma5 && ma5 > ma20 && ma20 > ma60) {
            return '현재가 \$${_formatNumber(currentPrice)}이 모든 이동평균선 위 (MA5: \$${_formatNumber(ma5)}, MA20: \$${_formatNumber(ma20)}) - 강한 상승 추세, 매수 기회';
          } else if (currentPrice > ma20) {
            return '현재가 \$${_formatNumber(currentPrice)}이 20일 평균선 \$${_formatNumber(ma20)} 위로 돌파 - 상승 신호';
          } else if (ma5 > ma20) {
            return '단기 평균선 \$${_formatNumber(ma5)}이 장기 평균선 \$${_formatNumber(ma20)} 위로 상승 - 매수 신호';
          } else {
            return '이동평균선이 상승 추세로 전환 중 - 매수 고려';
          }
        } else if (signal == '매도') {
          if (currentPrice < ma5 && ma5 < ma20 && ma20 < ma60) {
            return '현재가 \$${_formatNumber(currentPrice)}이 모든 이동평균선 아래 (MA5: \$${_formatNumber(ma5)}, MA20: \$${_formatNumber(ma20)}) - 강한 하락 추세, 매도 권장';
          } else if (currentPrice < ma20) {
            return '현재가 \$${_formatNumber(currentPrice)}이 20일 평균선 \$${_formatNumber(ma20)} 아래로 하락 - 매도 신호';
          } else if (ma5 < ma20) {
            return '단기 평균선 \$${_formatNumber(ma5)}이 장기 평균선 \$${_formatNumber(ma20)} 아래로 하락 - 매도 신호';
          } else {
            return '이동평균선이 하락 추세로 전환 중 - 매도 고려';
          }
        } else {
          return '현재가 \$${_formatNumber(currentPrice)}이 20일 평균선 \$${_formatNumber(ma20)} 근처 - 관망';
        }
        
      case '거래량':
        final currentVolume = (technicalData['currentVolume'] as num?)?.toInt();
        final avgVolume = (technicalData['avgVolume'] as num?)?.toDouble();
        
        if (currentVolume == null || avgVolume == null) {
          return '거래량 데이터 부족 - 관망 권장';
        }
        
        final volumeRatio = avgVolume > 0 ? currentVolume / avgVolume : 1.0;
        
        if (signal == '매수') {
          if (volumeRatio > 2.0) {
            return '거래량이 평균의 ${volumeRatio.toStringAsFixed(1)}배로 급증 (${_formatNumber(currentVolume)}주) - 🔥 강한 매수 신호! 거래량 폭증';
          } else if (volumeRatio > 1.5) {
            return '거래량이 평균의 ${volumeRatio.toStringAsFixed(1)}배로 증가 (${_formatNumber(currentVolume)}주) - 📈 매수 신호';
          } else if (priceChangePercent > 0) {
            return '거래량 ${_formatNumber(currentVolume)}주로 가격 상승 동반 - 📊 약한 매수 신호';
          } else {
            return '거래량 ${_formatNumber(currentVolume)}주로 상승 추세 - 📈 매수 고려';
          }
        } else if (signal == '매도') {
          if (volumeRatio > 2.0) {
            return '거래량이 평균의 ${volumeRatio.toStringAsFixed(1)}배로 급증 (${_formatNumber(currentVolume)}주) - ⚠️ 강한 매도 신호! 거래량 폭증';
          } else if (volumeRatio > 1.5) {
            return '거래량이 평균의 ${volumeRatio.toStringAsFixed(1)}배로 증가 (${_formatNumber(currentVolume)}주) - 📉 매도 신호';
          } else if (priceChangePercent < 0) {
            return '거래량 ${_formatNumber(currentVolume)}주로 가격 하락 동반 - 📊 약한 매도 신호';
          } else {
            return '거래량 ${_formatNumber(currentVolume)}주로 하락 추세 - 📉 매도 고려';
          }
        } else {
          return '거래량 ${_formatNumber(currentVolume)}주 (평균의 ${volumeRatio.toStringAsFixed(1)}배) - ⚖️ 관망';
        }
        
      case 'vwap':
        final vwapValue = (technicalData['vwap'] as num?)?.toDouble();
        
        if (vwapValue == null) {
          return '거래량 가중 평균가격 데이터 부족 - 관망 권장';
        }
        
        final vwapDiff = ((currentPrice - vwapValue) / vwapValue) * 100;
        
        if (signal == '매수') {
          if (vwapDiff < -2.0) {
            return '현재가 \$${_formatNumber(currentPrice)}이 평균가격 \$${_formatNumber(vwapValue)}보다 ${vwapDiff.abs().toStringAsFixed(1)}% 낮음 - 저점 매수 기회';
          } else if (vwapDiff < 0) {
            return '현재가 \$${_formatNumber(currentPrice)}이 평균가격 \$${_formatNumber(vwapValue)}보다 ${vwapDiff.abs().toStringAsFixed(1)}% 낮음 - 반등 기대';
          } else {
            return '현재가 \$${_formatNumber(currentPrice)}이 평균가격 \$${_formatNumber(vwapValue)}보다 ${vwapDiff.toStringAsFixed(1)}% 높음 - 상승 추세';
          }
        } else if (signal == '매도') {
          if (vwapDiff > 2.0) {
            return '현재가 \$${_formatNumber(currentPrice)}이 평균가격 \$${_formatNumber(vwapValue)}보다 ${vwapDiff.toStringAsFixed(1)}% 높음 - 고점 매도 기회';
          } else if (vwapDiff > 0) {
            return '현재가 \$${_formatNumber(currentPrice)}이 평균가격 \$${_formatNumber(vwapValue)}보다 ${vwapDiff.toStringAsFixed(1)}% 높음 - 하락 예상';
          } else {
            return '현재가 \$${_formatNumber(currentPrice)}이 평균가격 \$${_formatNumber(vwapValue)}과 비슷 (${vwapDiff.abs().toStringAsFixed(1)}% 차이) - 하락 추세';
          }
        } else {
          return '현재가 \$${_formatNumber(currentPrice)}이 평균가격 \$${_formatNumber(vwapValue)}과 비슷 (${vwapDiff.abs().toStringAsFixed(1)}% 차이) - 관망';
        }
        
      case 'adx':
        final adxValue = (technicalData['adx'] as num?)?.toDouble();
        
        if (adxValue == null) {
          return '추세 강도 데이터 부족 - 관망 권장';
        }
        
        if (signal == '매수') {
          if (adxValue >= 25) {
            return '추세 강도 ${adxValue.toStringAsFixed(1)} (강한 상승 추세) - 매수 기회';
          } else if (adxValue >= 20) {
            return '추세 강도 ${adxValue.toStringAsFixed(1)} (상승 추세 형성) - 매수 고려';
          } else {
            return '추세 강도 ${adxValue.toStringAsFixed(1)} (약한 상승 추세) - 매수 고려';
          }
        } else if (signal == '매도') {
          if (adxValue >= 25) {
            return '추세 강도 ${adxValue.toStringAsFixed(1)} (강한 하락 추세) - 매도 권장';
          } else if (adxValue >= 20) {
            return '추세 강도 ${adxValue.toStringAsFixed(1)} (하락 추세 형성) - 매도 고려';
          } else {
            return '추세 강도 ${adxValue.toStringAsFixed(1)} (약한 하락 추세) - 매도 고려';
          }
        } else {
          return '추세 강도 ${adxValue.toStringAsFixed(1)} (중립) - 관망';
        }
        
      default:
        if (signal == '매수') {
          return '${indicatorName} 상승 신호로 매수';
        } else if (signal == '매도') {
          return '${indicatorName} 하락 신호로 매도';
        } else {
          return '${indicatorName} 중립 구간으로 관망';
        }
    }
  }

  Widget _buildAnalysisItem(String label, String value, Color color, IconData icon) =>
      AnalysisItem(label: label, value: value, color: color, icon: icon);

  /// 투자 스타일 정보 표시
  Widget _buildInvestmentStyleInfo(Map<String, dynamic> analysis) {
    final styleName = analysis['investmentStyle'] ?? _getStyleName(_currentStyle);
    final styleColor = _getStyleColor(_currentStyle);
    final styleIcon = _getStyleIcon(_currentStyle);
    return InvestmentStyleInfo(styleName: styleName, styleColor: styleColor, styleIcon: styleIcon);
  }

  /// 통합 분석 결과 섹션 (AI 분석 + 기술적 지표)

  /// 종합적인 일봉 분석 이유 생성
  String _generateComprehensiveAnalysisReason(Map<String, dynamic> analysis, String signal, double aggregateScore, Map<String, dynamic> individualScores) =>
      AnalysisReasonUtils.generateComprehensiveAnalysisReason(
        analysis: analysis,
        signal: signal,
        aggregateScore: aggregateScore,
        individualScores: individualScores,
        getKoreanIndicatorName: _getKoreanIndicatorName,
      );
  /// 기술적 지표 조건 표시 (2열 배치, 매수/매도 색상 구분)
  Future<Widget> _buildTechnicalIndicatorsSection(Map<String, dynamic> analysis) async {
    return TechnicalIndicatorsSection(
      analysis: analysis,
      getKoreanIndicatorName: _getKoreanIndicatorName,
      generateDetailedReason: _generateDetailedReason,
      getIndicatorScore: _getIndicatorScore,
      loadThresholds: () async {
    final currentUserStyle = await _styleManager.getCurrentStyle();
    final styleParams = await _styleManager.getStyleParameters(currentUserStyle);
        return {
          'buyThreshold': (styleParams['buyThreshold'] as num?)?.toDouble() ?? 0.0,
          'sellThreshold': (styleParams['sellThreshold'] as num?)?.toDouble() ?? 0.0,
        };
      },
    );
  }

  /// 지표 값 포맷팅 (통합)
  String _formatIndicatorValue(dynamic value, String indicatorName) =>
      AnalysisFormatters.formatIndicatorValue(value, indicatorName);



  /// 거래 상태 오버레이
  Widget _buildTradeStatusOverlay(String stockCode) {
    return TradeStatusOverlay(stockCode: stockCode);
  }

  /// 거래 상태 관리 액션 핸들러
  Future<void> _handleTradeStatusAction(String action) async {
    await TradeStatusActions.handle(context, _tradeStatusTracker, action);
  }

  /// 거래 상태에 따른 텍스트 색상 반환
  Color _getTradeStatusTextColor(TradeStatus status) {
    switch (status) {
      case TradeStatus.none:
        return Colors.black;
      case TradeStatus.bought:
        return Colors.red[700]!;
      case TradeStatus.sold:
        return Colors.blue[700]!;
      case TradeStatus.holding:
        return Colors.green[700]!;
      case TradeStatus.buyOrdered:
        return Colors.orange[700]!;
      case TradeStatus.sellOrdered:
        return Colors.purple[700]!;
    }
  }

  /// 분석 시간 정보 표시
  Widget _buildAnalysisTimeInfo(Map<String, dynamic> analysis) {
    return AnalysisTimeInfo(analysis: analysis);
  }

  Widget _buildNoApiMessage() => const NoApiMessage();

  String _formatDateTime(DateTime dateTime) => DateTimeUtils.formatMonthDayHourMinute(dateTime);
  /// 시그널 시간 정보 표시
  Widget _buildSignalTimeInfo(String stockCode, Map<String, dynamic> analysis) {
    final signalTime = _signalTimestamps[stockCode];
    return SignalTimeInfo(stockCode: stockCode, analysis: analysis, signalTime: signalTime);
  }

  /// 정규장 시간 체크
  bool _isTradingTime(String stockCode) {
    return MarketTimeValidator.instance.isTradingTimeForSymbol(stockCode);
  }

  /// 정규장 시간 오버레이 (지표는 표시하되 매매 시그널만 제한)
  Widget _buildTradingTimeOverlay(String stockCode) {
    return TradingTimeOverlay(stockCode: stockCode);
  }

  /// 데이터 테이블 탭
  Widget _buildDataTableTab() {
    return AnalysisDataTableTab(
      isLoading: _isLoading,
      analysisScrollController: _analysisScrollController,
      watchlistItems: _watchlistItems,
      holdingsItems: _holdingsItems,
      analysisResults: _analysisResults,
      currentStyle: _styleManager.currentStyle,
      getStyleName: _getStyleName,
      getStyleIcon: _getStyleIcon,
      getStyleColor: _getStyleColor,
      isNasdaqStock: _isNasdaqStock,
      getDisplayName: _getDisplayName,
      formatPriceWithChange: _formatPriceWithChange,
      formatPriceForDisplay: (num price, bool isNasdaq, {bool showSign = false}) =>
          _formatPriceForDisplay(price.toDouble(), isNasdaq, showSign: showSign),
      formatIndicatorValue: _formatIndicatorValue,
    );
  }

  

  

  

  /// 투자 스타일 설명
  String _getStyleDescription(InvestmentStyle style) => StyleUtils.getStyleDescription(style);
  // 제거: 사용하지 않는 투자스타일 상세 조건 빌더 (UI 미사용)

  // 제거: 미사용 지표 포맷팅 함수들 (통합 포맷터 사용)
  // 제거: 미사용 자동매매 분석 스트림 구독 더미 구현

  String _formatSignalTime(String timestamp) => DateTimeUtils.formatMonthDayHourMinute(DateTime.parse(timestamp));
  /// 자동 거래 실행
  Future<void> _executeAutoTrade(String stockCode, String stockName, String signal, Map<String, dynamic>? priceData) async {
    try {
      print('🤖 자동거래 실행 시작: $stockCode ($stockName) - $signal');
      print('📊 현재가 데이터: $priceData');
      
      double currentPrice = (priceData?['currentPrice'] ?? 0.0).toDouble();
      if (currentPrice <= 0) {
        // Fallback: KIS API에서 즉시 현재가 조회 (통일된 API 서비스 사용)
        try {
          final priceResp = await _unifiedApiService.getStockPrice(stockCode);
          final fetched = (priceResp?['currentPrice'] ?? priceResp?['close'] ?? 0.0).toDouble();
          if (fetched > 0) {
            currentPrice = fetched;
            print('✅ 현재가 보정 완료: $stockCode -> $currentPrice');
          } else {
            print('❌ 자동거래 실패: 현재가 조회 실패 - $stockCode');
            return;
          }
        } catch (e) {
          print('❌ 현재가 보정 실패 ($stockCode): $e');
          return;
        }
      }
      
      print('💰 현재가: $currentPrice');

      // 보유 수량 확인
      final holdings = _holdingsItems.where((item) => 
        (item['stock_code'] ?? item['stockCode']) == stockCode
      ).toList();
      
      final hasHoldings = holdings.isNotEmpty && (holdings.first['quantity'] ?? 0) > 0;
      
      // 매도 시그널인데 보유하지 않은 경우: 실패 알림/히스토리 저장
      if (signal == '매도' && !hasHoldings) {
        print('ℹ️ 매도 시그널 실패: 보유하지 않은 종목 - $stockCode');
        await LocalNotificationManager().showSellFailureNotification(
          stockCode: stockCode,
          stockName: stockName,
          reason: '보유중이 아님 (자동매매 미실행)',
          price: currentPrice,
        );
        final notificationRepository = NotificationHistoryRepository();
        await notificationRepository.addNotification(
          type: '매도 시도 실패',
          stockCode: stockCode,
          stockName: stockName,
          message: '보유중이 아님 (자동매매 미실행)'
        );
        return;
      }

      // 매수 시그널인 경우 보유/잔고 확인
      if (signal == '매수') {
        // 이미 보유 중이면 분할 매수 전략 허용 (알림은 보내되 매수는 선택적)
        if (hasHoldings) {
          print('ℹ️ 매수 시그널 정보: 이미 보유 중인 종목 - $stockCode');
          // 보유 중이어도 시그널은 생성 (분할 매수 전략)
          // 실제 매수는 사용자가 결정하도록 알림만 표시
        }
        final isNasdaq = _isNasdaqStock(stockCode);
        final requiredAmount = currentPrice * 1; // 1주 기준
        
        if (isNasdaq) {
          // 나스닥 종목인 경우 달러 잔고 확인 (통일된 API 서비스 사용)
          final availableDollar = await _unifiedApiService.getOverseasPaymentStandardBalanceCompat();
          
          if (availableDollar < requiredAmount) {
            print('❌ 자동거래 실패: 달러 잔고 부족 - $stockCode (필요: \$${requiredAmount.toStringAsFixed(2)}, 보유: \$${availableDollar.toStringAsFixed(2)})');
            
            // 알림 발송
            await LocalNotificationManager().showBuyFailureNotification(
              stockCode: stockCode,
              stockName: stockName,
              reason: '달러 잔고 부족 (\$${requiredAmount.toStringAsFixed(2)} 필요)',
              price: currentPrice,
            );
            
            // 알림 히스토리에 저장
            final notificationRepository = NotificationHistoryRepository();
            await notificationRepository.addNotification(
              type: '매수 주문 실패',
              stockCode: stockCode,
              stockName: stockName,
              message: '달러 잔고 부족 (\$${requiredAmount.toStringAsFixed(2)} 필요)',
            );
            return;
          }
        } else {
          // 국내 종목인 경우 원화 잔고 확인 (통일된 API 서비스 사용)
          final balanceResp = await _unifiedApiService.getAccountBalanceCompat();
          final accountInfo = balanceResp?['domestic']?['accountInfo'] as List?;
          final availableBalance = accountInfo?.isNotEmpty == true 
            ? (accountInfo!.first as Map<String, dynamic>)['ord_able_amt'] ?? 0.0
            : 0.0;
          
          if (availableBalance < requiredAmount) {
            print('❌ 자동거래 실패: 원화 잔고 부족 - $stockCode (필요: ${Formatters.formatPrice(requiredAmount)}, 보유: ${Formatters.formatPrice(availableBalance)})');
            
            // 알림 발송
            await LocalNotificationManager().showBuyFailureNotification(
              stockCode: stockCode,
              stockName: stockName,
              reason: '원화 잔고 부족 (${Formatters.formatPrice(requiredAmount)} 필요)',
              price: currentPrice,
            );
            
            // 알림 히스토리에 저장
            final notificationRepository = NotificationHistoryRepository();
            await notificationRepository.addNotification(
              type: '매수 주문 실패',
              stockCode: stockCode,
              stockName: stockName,
              message: '원화 잔고 부족 (${Formatters.formatPrice(requiredAmount)} 필요)',
            );
            return;
          }
        }
      }

      // 자동거래는 AutoTradingCycle(OrderProcessor) 경로 사용 권장
      // 화면에서 직접 주문 실행은 지양 (DB/사이드이펙트 동기화 보장 위해)
      // TODO: 필요 시 OrderProcessor를 직접 호출하는 유즈케이스로 치환
      final result = {'success': false, 'message': 'UI 직접 주문 비활성'};

      if (result['success'] == true) {
        print('✅ 자동거래 성공: $stockCode $signal - ${result['message']}');
        
        // 거래 성공 후 데이터 갱신
        await AppDataManager.instance.refreshData();
        
        // UI 갱신을 위한 플래그 설정
        if (mounted) {
          setState(() {
            _needsRefresh = true;
          });
        }
      } else {
        print('❌ 자동거래 실패: $stockCode $signal - ${result['message']}');
      }
      
    } catch (e) {
      print('❌ 자동거래 실행 중 오류: $e');
    }
  }

  /// 모든 분석 결과 새로고침 (자동 새로고침용 - 화면 새로 호출 없음)
  Future<void> _refreshAllAnalysis() async {
    print('🔄 모든 분석 결과 새로고침 시작 (자동)');
    
    try {
      // 로딩 상태를 true로 설정하지 않고 백그라운드에서 분석 수행
      await _performRealTimeAnalysis();
      
      // 분석 완료 후 UI 업데이트 (화면 새로 호출 없이)
      if (mounted) {
        setState(() {
          // 필터링된 결과만 업데이트
        });
      }
      
      print('✅ 모든 분석 결과 새로고침 완료 (자동)');
    } catch (e) {
      print('❌ 모든 분석 결과 새로고침 실패: $e');
    }
  }
  /// 모든 분석 결과 새로고침 (수동 새로고침용 - 화면 새로 호출)
  Future<void> _refreshAllAnalysisWithLoading() async {
    print('🔄 모든 분석 결과 새로고침 시작 (수동)');
    
    try {
      // 로딩 상태 설정
      if (mounted) {
        setState(() {
          _isLoading = true;
        });
      }
      
      // 전체 데이터 새로고침
      await _performRealTimeAnalysis();
      
      // 분석 완료 후 UI 업데이트
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      
      print('✅ 모든 분석 결과 새로고침 완료 (수동)');
    } catch (e) {
      print('❌ 모든 분석 결과 새로고침 실패: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 관심종목 변경 감지 시작
  void _startWatchlistChangeDetection() {
    Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      try {
        // 현재 관심종목 목록 가져오기
        final watchlistRepository = AppDataManager.instance.watchlistRepository;
        final currentWatchlist = await watchlistRepository.getWatchlistWithStockInfo();
        
        // 기존 목록과 비교
        if (_watchlistItems.length != currentWatchlist.length) {
          print('🔄 관심종목 변경 감지: ${_watchlistItems.length} → ${currentWatchlist.length}');
          
          // 나스닥 종목 확인
          final nasdaqItems = currentWatchlist.where((item) => 
            (item['market'] as String? ?? '') == 'NASDAQ').toList();
          print('🇺🇸 새 관심종목 중 나스닥 종목: ${nasdaqItems.length}개');
          for (final item in nasdaqItems) {
            print('  - ${item['stock_name']} (${item['stock_code']})');
          }
          
          setState(() {
            _watchlistItems = currentWatchlist;
          });
          
          // 새로운 종목들 즉시 분석
          await _analyzeNewWatchlistItems(currentWatchlist);
        }
      } catch (e) {
        print('❌ 관심종목 변경 감지 실패: $e');
      }
    });
  }

  /// 새로운 관심종목들 즉시 분석
  Future<void> _analyzeNewWatchlistItems(List<Map<String, dynamic>> newWatchlist) async {
    try {
      print('🔍 새로운 관심종목들 즉시 분석 시작...');
      
      for (final item in newWatchlist) {
        final stockCode = item['stock_code'] as String? ?? '';
        final stockName = item['stock_name'] as String? ?? stockCode;
        
        // 이미 분석된 종목은 건너뛰기
        if (_analysisResults.containsKey(stockCode)) {
          continue;
        }
        
        print('📊 새로운 관심종목 즉시 분석: $stockCode ($stockName)');
        
        // 즉시 분석 수행
        await _performAnalysisForStock({
          'stockCode': stockCode,
          'stockName': stockName,
        });
      }
      
      print('✅ 새로운 관심종목들 즉시 분석 완료');
    } catch (e) {
      print('❌ 새로운 관심종목들 즉시 분석 실패: $e');
    }
  }





  String _buildSignalSummary(Map<String, dynamic> analysis) => SignalSummaryUtils.buildSummary(analysis);

  /// 투자 스타일에 맞는 종목만 필터링 (임계값 기반)
  Future<List<Map<String, dynamic>>> _filterItemsByStyle(List<Map<String, dynamic>> items) async {
    if (items.isEmpty) return [];
    
    try {
      // 스타일 파라미터를 미리 가져오기
      final styleParams = await _styleManager.getStyleParameters(_currentStyle);
      final buyThreshold = (styleParams['buyThreshold'] as num?)?.toDouble();
    if (buyThreshold == null) {
      print('⚠️ 매수 임계값이 설정되지 않았습니다.');
      return items;
    }
      
      return items.where((item) {
        final stockCode = item['stock_code'] ?? item['stockCode'];
        if (stockCode == null) return false;
        
        // 분석 결과 확인
        final analysis = _analysisResults[stockCode];
        if (analysis == null) return false;
        
        final aggregateScore = analysis['aggregateScore'] ?? 0.0;
        
        // 매수 조건 확인 (종합점수가 매수 임계값 이상)
        final isSuitable = aggregateScore >= buyThreshold;
        
        if (isSuitable) {
          print('✅ 필터링 통과 ($stockCode): 종합점수=${aggregateScore.toStringAsFixed(2)}, 매수임계값=${buyThreshold.toStringAsFixed(2)}');
        }
        
        return isSuitable;
      }).toList();
    } catch (e) {
      print('❌ 투자 스타일 필터링 실패: $e');
      return items; // 오류 시 모든 종목 반환
    }
  }
  
  /// 필터링된 관심종목 반환
  Future<List<Map<String, dynamic>>> get _filteredWatchlistItems async {
    return await _filterItemsByStyle(_watchlistItems);
  }
  
  /// 필터링된 보유종목 반환
  Future<List<Map<String, dynamic>>> get _filteredHoldingsItems async {
    return await _filterItemsByStyle(_holdingsItems);
  }

  /// 주식 분석 수행
  Future<Map<String, dynamic>?> _analyzeStock(String stockCode) async {
    try {
      print('🔍 주식 분석 시작: $stockCode');
      
      // 1. 종목 정보에서 시장 확인
      final stockInfo = AppDataManager.instance.getStockInfo(stockCode);
      final market = stockInfo?['market'] ?? _detectMarket(stockCode);
      print('📊 종목 시장: $market');
      
      // 2. 시장별 현재가 데이터 조회
      Map<String, dynamic>? realtimeData;
      double currentPrice = 0.0;
      double prevClose = 0.0;
      
      try {
        // 캐시에서 먼저 확인
        realtimeData = _watchlistDataCache[stockCode];
        if (realtimeData != null && realtimeData.isNotEmpty) {
          currentPrice = (realtimeData['currentPrice'] ?? 0.0).toDouble();
          prevClose = (realtimeData['prevClose'] ?? currentPrice).toDouble();
          print('📊 캐시에서 데이터 조회 ($stockCode): 현재가=$currentPrice, 전일가=$prevClose');
        }

        // 캐시가 없거나 만료된 경우 실시간 데이터 조회 (통일된 API 서비스 사용)
        if (currentPrice <= 0) {
          realtimeData = await _unifiedApiService.getStockPrice(stockCode);
          if (realtimeData != null && realtimeData.isNotEmpty) {
            currentPrice = (realtimeData['currentPrice'] ?? 0.0).toDouble();
            prevClose = (realtimeData['prevClose'] ?? currentPrice).toDouble();
            
            // 캐시에 저장
            _watchlistDataCache[stockCode] = realtimeData;
            print('📊 실시간 데이터 조회 ($stockCode): 현재가=$currentPrice, 전일가=$prevClose');
          }
        }
      } catch (e) {
        print('❌ 실시간 데이터 조회 실패 ($stockCode): $e');
        return null;
      }

      if (currentPrice <= 0) {
        print('⚠️ 유효하지 않은 현재가 ($stockCode): $currentPrice');
        return null;
      }

      // 3. 시장별 차트 데이터 조회 (통일된 API 서비스 사용)
      List<Map<String, dynamic>> rawKisData = [];
      try {
        rawKisData = await RemoteKisService.instance.getDailyChart(stockCode, days: 100);
        print('📊 차트 데이터 조회 ($stockCode): ${rawKisData.length}개');
        
        if (rawKisData.isNotEmpty) {
          print('📊 차트 데이터 샘플 ($stockCode):');
          print('  - 키들: ${rawKisData.first.keys.toList()}');
          print('  - 첫 번째 데이터: ${rawKisData.first}');
        }
      } catch (e) {
        print('❌ 차트 데이터 조회 실패 ($stockCode): $e');
        return null;
      }

      if (rawKisData.isEmpty) {
        print('⚠️ 차트 데이터가 없습니다 ($stockCode)');
        return null;
      }

      // 4. 투자스타일 파라미터 로드
      // 현재 사용자의 투자스타일을 가져와서 사용
      final currentUserStyle = await _styleManager.getCurrentStyle();
      final styleParams = await _styleManager.getStyleParameters(currentUserStyle);
      print('🔍 투자스타일 파라미터 로드 ($stockCode):');
      print('  - 매수 임계값: ${styleParams['buyThreshold']}');
      print('  - 매도 임계값: ${styleParams['sellThreshold']}');
      print('  - RSI 조건: ${styleParams['rsiCondition']}');
      print('  - 거래량 조건: ${styleParams['volumeCondition']}');
      
      // 5. 차트 데이터에서 현재가 정보 추출
      final latestData = rawKisData.isNotEmpty ? rawKisData.last : {};
      final chartCurrentPrice = (latestData['stck_prpr'] as num?)?.toDouble() ?? currentPrice;
      final chartVolume = (latestData['acml_vol'] as num?)?.toDouble() ?? 0.0;
      final chartHighPrice = (latestData['stck_hgpr'] as num?)?.toDouble() ?? currentPrice;
      final chartLowPrice = (latestData['stck_lwpr'] as num?)?.toDouble() ?? currentPrice;
      final chartOpenPrice = (latestData['stck_oprc'] as num?)?.toDouble() ?? currentPrice;
      
      print('📊 차트 데이터 추출 ($stockCode):');
      print('  - 현재가: $chartCurrentPrice');
      print('  - 거래량: $chartVolume');
      print('  - 고가: $chartHighPrice');
      print('  - 저가: $chartLowPrice');
      print('  - 시가: $chartOpenPrice');
      
      // 6. AI 분석 서비스로 분석 수행 (서버 위임)
      print('🤖 AI 분석 시작 ($stockCode) - 투자 스타일: ${_getStyleName(currentUserStyle)}');
      final analysis = await _unifiedAnalysis.analyzeStock(stockCode, days: 100);

      // 5. 분석 결과 반환
      if (analysis != null) {
        final metConditions = analysis['metConditions'] ?? 0;
        final totalConditions = analysis['totalConditions'] ?? 1;
        final signals = analysis['signals'] ?? [];
        
        print('✅ 분석 완료 ($stockCode):');
        print('  - 만족한 조건: $metConditions/$totalConditions');
        print('  - 시그널 개수: ${signals.length}개');
        print('  - RSI: ${analysis['indicators']?['rsi']?.toStringAsFixed(2) ?? 'N/A'}');
        print('  - 거래량 조건: ${analysis['volumeCondition']?.toStringAsFixed(2) ?? 'N/A'}');
        
        final result = {
          'currentPrice': currentPrice,
          'prevClose': prevClose,
          'market': market,
          'indicators': analysis['indicators'] ?? {},
          'signal': analysis['signal'] ?? '관망',
          'confidence': analysis['confidence'] ?? 0,
          'targetPrice': analysis['targetPrice'] ?? currentPrice,
          'reason': analysis['reason'] ?? '분석 완료',
          'signals': signals,
          'metConditions': metConditions,
          'totalConditions': totalConditions,
          'volumeCondition': analysis['volumeCondition'],
          'lastSignal': analysis['lastSignal'],
          'analysisTime': DateTime.now().toIso8601String(),
          'analysisPrice': currentPrice,
          // 투자스타일 파라미터 추가 (로컬 DB에서 실제 저장된 값 사용)
          'buyThreshold': (styleParams['buyThreshold'] as num?)?.toDouble() ?? 0.3,
          'sellThreshold': (styleParams['sellThreshold'] as num?)?.toDouble() ?? -0.3,
          'investmentStyle': currentUserStyle.toString(),
        };
        
        return result;
      } else {
        print('❌ 분석 실패 ($stockCode): AI 분석 서비스에서 null 반환');
        return null;
      }
    } catch (e) {
      print('❌ 주식 분석 중 오류 발생 ($stockCode): $e');
      return null;
    }
  }

  /// 종목코드로 시장 감지
  String _detectMarket(String stockCode) {
    if (stockCode.startsWith('00') || stockCode.startsWith('01') || stockCode.startsWith('02')) {
      return 'KOSPI';
    } else if (stockCode.startsWith('03') || stockCode.startsWith('04') || stockCode.startsWith('05')) {
      return 'KOSDAQ';
    } else if (RegExp(r'^[A-Z]{1,6}$').hasMatch(stockCode)) {
      return 'NASDAQ';
    } else {
      return 'UNKNOWN';
    }
  }
  /// 지표별 점수 반환 (ComprehensiveIndicatorCalculator에서 계산된 개별 점수 사용)
  double _getIndicatorScore(String indicatorName, Map<String, dynamic> analysis) {
    // ComprehensiveIndicatorCalculator에서 계산된 individualScores 사용 (가중치 적용 전 원래 점수)
    final contributions = analysis['contributions'] as Map<String, double>? ?? {};
    final individualScores = analysis['individualScores'] as Map<String, double>? ?? {};
    
    // 지표명 매핑 (한글명 → 영문 키)
    final Map<String, String> indicatorMapping = {
      'RSI': 'rsi',
      'MACD': 'macd',
      '볼린저밴드': 'bollinger',
      '이동평균선': 'movingAverage',
      '거래량': 'volume',
      'VWAP': 'vwap',
      'ADX': 'adx',
    };
    
    // 먼저 한글명으로 매핑 시도
    String mappedName = indicatorMapping[indicatorName] ?? '';
    
    // 매핑이 실패하면 원본 이름 그대로 사용 (이미 영문 키인 경우)
    if (mappedName.isEmpty) {
      mappedName = indicatorName;
    }
    
    final contribution = contributions[mappedName] ?? 0.0;
    final individualScore = individualScores[mappedName] ?? 0.0;
    
    print('🔍 지표점수 디버깅:');
    print('  - 지표명: $indicatorName');
    print('  - 매핑된 키: $mappedName');
    print('  - 개별 점수 (원래): ${individualScore.toStringAsFixed(3)}');
    print('  - 기여도 (가중치 적용): ${contribution.toStringAsFixed(3)}');
    print('  - 전체 individualScores: $individualScores');
    print('  - 전체 contributions: $contributions');
    print('  - individualScores 키들: ${individualScores.keys.toList()}');
    print('  - contributions 키들: ${contributions.keys.toList()}');
    print('  - UI에 표시할 값: ${contribution.toStringAsFixed(3)}');
    
    // UI에는 가중치가 적용된 기여도(contribution)를 표시
    return contribution;
  }

  /// 매수/매도 기회 시그널 저장
  Future<void> _saveOpportunitySignal(
    String stockCode, 
    String stockName, 
    String signalType, 
    Map<String, dynamic>? currentPriceData,
  ) async {
      final currentPrice = (currentPriceData?['currentPrice'] as num?)?.toDouble() ?? 0.0;
    await SignalHelpers.saveOpportunitySignal(
        stockCode: stockCode,
      stockName: stockName,
        signalType: signalType,
      currentPrice: currentPrice,
      styleName: _currentStyle.toString(),
    );
      print('✅ 매수/매도 기회 시그널 저장 완료: $stockCode ($stockName) - $signalType');
    }
  /// 로딩 섹션
  Widget _buildLoadingSection() => const LoadingSection();
  /// 지표명 한글화
  String _getKoreanIndicatorName(String indicatorName) => IndicatorUtils.getKoreanIndicatorName(indicatorName);

  /// 지표명을 키로 변환
  String _getIndicatorKey(String indicatorName) => IndicatorUtils.getIndicatorKey(indicatorName);

  /// 숫자에 쉼표 추가 (3자리마다)
  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    try {
      final parsed = value is num ? value : double.parse(value.toString());
      return AnalysisFormatters.formatNumber(parsed);
    } catch (_) {
      return value.toString();
    }
  }

  /// 지표별 실제 값 텍스트 생성
  String _getActualValueText(String indicatorName, Map<String, dynamic> analysis) =>
      AnalysisReasonUtils.getActualValueText(
        indicatorName: indicatorName,
        analysis: analysis,
        formatNumber: _formatNumber,
      );
  /// 추천종목 탭
  Widget _buildRecommendedStocksTab() {
    return RecommendedTab(isLoading: _isLoading, isFirstLoading: _isFirstLoading);
  }
}