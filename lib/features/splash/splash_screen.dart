import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/data/app_data_manager.dart';
import '../../core/data/stock_master_parser.dart';
import '../../core/trading/stock_cache_manager.dart';
import '../../core/database/repositories/watchlist_repository.dart';
import '../../core/database/repositories/holdings_repository.dart';
import '../../core/database/repositories/chart_data_repository.dart';
import '../../core/database/repositories/current_price_repository.dart';
import '../../core/data/incremental_data_manager.dart';
import '../../core/services/realtime_update_service.dart';
import '../../core/services/smart_lifecycle_manager.dart';
import '../../core/analysis/realtime_analysis_engine.dart';
import '../../core/ai/ai_recommendation_service.dart';
import '../../core/services/integrated_monitoring_service.dart';
import '../../core/services/performance_monitor.dart';
import '../../core/testing/integrated_test_system.dart';
import '../../core/remote/remote_kis_service.dart';
import '../../core/data/firestore_stock_service.dart';
import '../../core/remote/analysis_functions_service.dart';
import '../../core/trading/market_time_validator.dart';
import '../../core/api/kis_unified_api_service.dart';
import '../../core/api/unified_stock_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/trading/auto_trading_cycle.dart';
import '../main/main_screen.dart';
import '../onboarding/api_key_setup_screen.dart';
import '../../core/config/api_config.dart';
import '../../core/services/permission_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  double _progress = 0.0;
  String _currentTask = '앱을 시작하는 중...';
  bool _isLoading = true;
  bool _isInitializing = false; // 중복 초기화 방지
  late final AnimationController _iconBounceController;
  late final Animation<double> _iconBounce;
  late final Animation<double> _iconScale;

  // 새로운 데이터 매니저
  late final IncrementalDataManager _dataManager;
  late final WatchlistRepository _watchlistRepo;
  late final HoldingsRepository _holdingsRepo;
  late final ChartDataRepository _chartRepo;
  late final CurrentPriceRepository _currentPriceRepo;
  late final RealtimeUpdateService _realtimeService;
  late final SmartLifecycleManager _lifecycleManager;
  late final RealtimeAnalysisEngine _analysisEngine;
  late final AiRecommendationService _aiRecommendationService;
  late final IntegratedMonitoringService _monitoringService;
  late final IntegratedTestSystem _testSystem;

  @override
  void initState() {
    super.initState();
    print('🚀 SplashScreen initState 호출됨!');
    
    // 새로운 데이터 매니저 및 Repository 초기화
    _dataManager = IncrementalDataManager();
    _watchlistRepo = WatchlistRepository();
    _holdingsRepo = HoldingsRepository();
    _chartRepo = ChartDataRepository();
    _currentPriceRepo = CurrentPriceRepository();
    _realtimeService = RealtimeUpdateService();
    _lifecycleManager = SmartLifecycleManager();
    _analysisEngine = RealtimeAnalysisEngine();
    _aiRecommendationService = AiRecommendationService();
    _monitoringService = IntegratedMonitoringService();
    _testSystem = IntegratedTestSystem();
    
    // 아이콘 바운스 애니메이션
    _iconBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _iconBounce = Tween<double>(begin: 0.0, end: -22.0).animate(
      CurvedAnimation(parent: _iconBounceController, curve: Curves.easeInOut),
    );
    _iconScale = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _iconBounceController, curve: Curves.easeInOut),
    );
    
    print('🚀 _initializeApp() 호출 전...');
    _initializeApp();
    print('🚀 _initializeApp() 호출 후...');
  }

  Future<void> _initializeApp() async {
    if (_isInitializing) {
      print('⚠️ 이미 초기화 중입니다. 중복 호출 무시.');
      return;
    }
    
    _isInitializing = true;
    
    try {
      print('🚀 스플래시 초기화 시작...');
      print('🚀 스플래시 화면이 실행되었습니다!');
      
      // 1) 기본 초기화
      print('🔍 1단계: 기본 초기화 시작...');
      await _animateTo(0.0, '앱을 시작하는 중...');
      await _animateTo(0.10, '기본 초기화 중...');
      await AppDataManager.instance.initialize();
      print('✅ 1단계: 기본 초기화 완료');
      
      // 2) 종목 데이터 확인 및 로드
      await _animateTo(0.20, '종목 데이터 확인 중...');
      int stockCount = await AppDataManager.instance.stockRepository.getStockCount();
      print('📊 데이터베이스 종목 개수: $stockCount개');
      
      // StockMasterParser 초기화
      print('🔍 2단계: StockMasterParser 초기화 시작...');
      await _animateTo(0.25, '종목 마스터 데이터 파싱 중...');
      
      try {
        await StockMasterParser().initialize();
        print('✅ StockMasterParser 초기화 완료');
        
        final nasdaqCount = StockMasterParser().getNasdaqStockCodes().length;
        print('📊 나스닥 종목 수: $nasdaqCount개');
      } catch (e) {
        print('❌ StockMasterParser 초기화 실패: $e');
        print('⚠️ 2단계: StockMasterParser 초기화 실패했지만 계속 진행');
      }
      
      // 종목 데이터 DB 저장 (세분화된 진행률)
      await _animateTo(0.30, '종목 데이터 확인 중...');
      
      // 이미 StockMasterParser가 초기화되었으므로 중복 초기화 방지
      stockCount = await AppDataManager.instance.stockRepository.getStockCount();
      print('📊 현재 데이터베이스 종목 개수: $stockCount개');
      
      if (stockCount == 0) {
        await _animateTo(0.32, '종목 마스터 데이터 저장 중...');
        await AppDataManager.instance.saveStockDataToDatabase();
        
        await _animateTo(0.35, '종목 데이터 저장 완료 확인 중...');
        stockCount = await AppDataManager.instance.stockRepository.getStockCount();
        print('✅ 종목 데이터 저장 완료: $stockCount개');
        
        if (stockCount == 0) {
          await _animateTo(0.37, '기본 종목 데이터 생성 중...');
          await AppDataManager.instance.createDefaultStockData();
          stockCount = await AppDataManager.instance.stockRepository.getStockCount();
          print('✅ 기본 종목 데이터 생성 완료: $stockCount개');
        }
      } else {
        await _animateTo(0.35, '기존 종목 데이터 사용');
        print('✅ 기존 종목 데이터 사용: $stockCount개');
      }
      
      // 3) 새로운 증분 데이터 매니저 초기화
      await _animateTo(0.40, '데이터 매니저 초기화 중...');
      print('🔍 3단계: 증분 데이터 매니저 초기화 시작...');
      
      try {
        await _dataManager.initialize();
        print('✅ 증분 데이터 매니저 초기화 완료');
      } catch (e) {
        print('❌ 증분 데이터 매니저 초기화 실패: $e');
        print('⚠️ 3단계: 증분 데이터 매니저 초기화 실패했지만 계속 진행');
      }
      
      // 4) API 키 설정 확인 (먼저 확인!)
      await _animateTo(0.40, 'API 설정 확인 중...');
      print('🔍 4단계: API 설정 확인 시작...');
      
      final config = ApiConfig.instance;
      await config.initialize(); // API 설정 초기화
      
      if (!config.isValid) {
        print('⚠️ API 키가 설정되지 않음 - API 키 설정 화면으로 이동');
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const ApiKeySetupScreen()),
          );
        }
        return;
      }
      print('✅ API 설정 확인 완료');

      // 🔍 KIS API 클라이언트 초기화 (보유종목 조회용)
      try {
        // ✅ API 키 설정은 필요 (데이터 조회가 아닌 설정)
        await KisUnifiedApiService().initialize(
          appKey: ApiConfig.instance.appKey!,
          appSecret: ApiConfig.instance.appSecret!,
          accountNumber: ApiConfig.instance.accountNo!,
        );
        print('✅ KIS API 클라이언트 초기화 완료 (보유종목 조회용)');
      } catch (e) {
        print('❌ KIS API 클라이언트 초기화 실패: $e');
      }

      // 5) 관심종목 및 보유종목 데이터 로딩 (API 설정 후)
      await _animateTo(0.60, '관심종목 데이터 로딩 중...');
      print('🔍 5단계: 관심종목 및 보유종목 데이터 로딩 시작...');
      
      // 메모리 부족 방지를 위해 필수 데이터만 로드
      await _loadEssentialWatchlistData();
      
      // 6) 자동매매 권한 확인 및 요청 (빠르게 처리)
      await _animateTo(0.90, '자동매매 권한 확인 중...');
      await _checkAndRequestPermissions();
      
      // 9) 실시간 업데이트 서비스 시작 (빠르게 처리)
      await _animateTo(0.95, '실시간 서비스 시작 중...');
      print('🔍 5단계: 실시간 업데이트 서비스 시작...');
      
      try {
        await _realtimeService.start();
        print('✅ 실시간 업데이트 서비스 시작 완료');
      } catch (e) {
        print('❌ 실시간 업데이트 서비스 시작 실패: $e');
        print('⚠️ 5단계: 실시간 업데이트 서비스 시작 실패했지만 계속 진행');
        // 실시간 업데이트 실패 시 백그라운드에서 재시도
        Future.delayed(const Duration(seconds: 60), () async {
          try {
            await _realtimeService.start();
            print('✅ 실시간 업데이트 서비스 재시작 성공');
          } catch (retryError) {
            print('❌ 실시간 업데이트 서비스 재시작 실패: $retryError');
          }
        });
      }
      
      // 8) 스마트 생명주기 관리 서비스 시작
      await _animateTo(0.93, '스마트 생명주기 관리 시작 중...');
      print('🔍 6단계: 스마트 생명주기 관리 시작...');
      
      try {
        await _lifecycleManager.start();
        print('✅ 스마트 생명주기 관리 시작 완료');
      } catch (e) {
        print('❌ 스마트 생명주기 관리 시작 실패: $e');
        print('⚠️ 6단계: 스마트 생명주기 관리 시작 실패했지만 계속 진행');
      }
      
      // 9) 실시간 분석 엔진 시작
      await _animateTo(0.94, '실시간 분석 엔진 시작 중...');
      print('🔍 7단계: 실시간 분석 엔진 시작...');
      
      try {
        await _analysisEngine.start();
        print('✅ 실시간 분석 엔진 시작 완료');
      } catch (e) {
        print('❌ 실시간 분석 엔진 시작 실패: $e');
        print('⚠️ 7단계: 실시간 분석 엔진 시작 실패했지만 계속 진행');
      }
      
      // 10) AI 추천 서비스는 스플래시/메인 자동 시작 없음
      await _animateTo(0.95, '추천 서비스는 전용 화면에서만 실행');
      print('ℹ️ 8단계: AI 추천 서비스 자동 시작 제거됨');
      
      // 11) 통합 모니터링 서비스 시작
      await _animateTo(0.97, '통합 모니터링 서비스 시작 중...');
      print('🔍 9단계: 통합 모니터링 서비스 시작...');
      
      try {
        await _monitoringService.start();
        print('✅ 통합 모니터링 서비스 시작 완료');
      } catch (e) {
        print('❌ 통합 모니터링 서비스 시작 실패: $e');
        print('⚠️ 9단계: 통합 모니터링 서비스 시작 실패했지만 계속 진행');
      }
      
      // 12) 자동매매 사이클 자동 시작
      await _animateTo(0.96, '자동매매 시스템 시작 중...');
      print('🔍 10단계: 자동매매 사이클 자동 시작...');
      
      try {
        final autoTradingCycle = AutoTradingCycle();
        await autoTradingCycle.autoStart();
        print('✅ 자동매매 사이클 자동 시작 완료');
      } catch (e) {
        print('❌ 자동매매 사이클 자동 시작 실패: $e');
        print('⚠️ 10단계: 자동매매 사이클 자동 시작 실패했지만 계속 진행');
      }
      
      // 13) 통합 테스트 시스템 시작
      await _animateTo(0.98, '통합 테스트 시스템 시작 중...');
      print('🔍 11단계: 통합 테스트 시스템 시작...');
      
      try {
        await _testSystem.start();
        print('✅ 통합 테스트 시스템 시작 완료');
      } catch (e) {
        print('❌ 통합 테스트 시스템 시작 실패: $e');
        print('⚠️ 11단계: 통합 테스트 시스템 시작 실패했지만 계속 진행');
      }
      
      // 14) 실시간 점수 서비스는 백그라운드에서 시작 (성능 최적화)
      await _animateTo(0.99, '백그라운드 서비스 준비 중...');
      print('🔍 12단계: 백그라운드 서비스 준비...');
      
      // 백그라운드에서 실시간 점수 서비스 시작 (메인 화면 진입 지연 방지)
      Future.microtask(() async {
        try {
          print('🔄 백그라운드에서 실시간 점수 서비스 시작...');
          final realtimeScoreService = AppDataManager.instance.realtimeScoreService;
          await realtimeScoreService.start();
          print('✅ 백그라운드 실시간 점수 서비스 시작 완료');
        } catch (e) {
          print('❌ 백그라운드 실시간 점수 서비스 시작 실패: $e');
        }
      });
      
      print('✅ 백그라운드 서비스 준비 완료');
      
      // 10) 완료
      await _animateTo(1.0, '앱 시작 완료!');
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const MainScreen()),
        );
        // 메인 진입 직후 추천 스캐너 시작
        Timer(const Duration(milliseconds: 100), () async {
          if (!mounted) return;
          try {
            await _aiRecommendationService.startResumableBackgroundScan();
            print('✅ 메인 진입 후 추천 스캐너 시작');
          } catch (e) {
            print('❌ 추천 스캐너 시작 실패: $e');
          }
        });
      }
    } catch (e) {
      print('❌ 스플래시 초기화 실패: $e');
      
      // API 키 설정 확인
      final config = ApiConfig.instance;
      if (!config.isValid) {
        print('⚠️ API 키가 설정되지 않음 - API 키 설정 화면으로 이동');
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const ApiKeySetupScreen()),
          );
        }
        return;
      }
      
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const MainScreen()),
        );
      }
    } finally {
      _isInitializing = false;
    }
  }
  
  Future<void> _updateProgress(double progress, String task) async {
    if (!mounted) return;
    setState(() {
      _progress = progress;
      _currentTask = task;
    });
    
    // 진행 상황을 부드럽게 표시하기 위한 짧은 대기
    await Future.delayed(const Duration(milliseconds: 100));
  }
  
  Future<void> _animateTo(double target, String task) async {
    if (target < _progress) {
      await _updateProgress(target, task);
      return;
    }
    final double step = 0.02; // 2%씩 증가
    double cur = _progress;
    while (cur + step < target) {
      cur += step;
      await _updateProgress(cur, task);
    }
    await _updateProgress(target, task);
  }
  
  /// 자동매매 권한 확인 및 요청
  Future<void> _checkAndRequestPermissions() async {
    try {
      print('🔐 자동매매 권한 확인 시작...');
      
      // 권한 상태 확인
      final permissions = await PermissionManager.checkAutoTradingPermissions();
      final missingPermissions = permissions.entries.where((e) => !(e.value ?? false)).toList();
      
      if (missingPermissions.isNotEmpty) {
        print('⚠️ 부족한 권한 발견: ${missingPermissions.map((e) => e.key).join(', ')}');
        
        // 권한 요청 다이얼로그 표시
        if (mounted) {
          final shouldRequest = await _showPermissionRequestDialog();
          if (shouldRequest) {
            await _requestAllPermissions();
          }
        }
      } else {
        print('✅ 모든 권한이 허용되어 있습니다.');
      }
      
    } catch (e) {
      print('❌ 권한 확인 실패: $e');
    }
  }
  
  /// 권한 요청 다이얼로그 표시
  Future<bool> _showPermissionRequestDialog() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('자동매매 권한 필요'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('백그라운드 자동매매가 제대로 작동하려면 다음 권한이 필요합니다:'),
            SizedBox(height: 16),
            Text('• 📱 알림 권한 (매매 시그널 알림)'),
            Text('• 🔋 배터리 최적화 제외 (앱이 종료되지 않도록)'),
            Text('• 🔧 다른 앱 위에 표시 (Foreground Service)'),
            SizedBox(height: 16),
            Text('권한을 허용하시겠습니까?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('나중에'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('허용'),
          ),
        ],
      ),
    ) ?? false;
  }
  
  /// 모든 권한 요청
  Future<void> _requestAllPermissions() async {
    try {
      print('🔐 모든 권한 요청 시작...');
      
      // 알림 권한 요청
      final notificationStatus = await Permission.notification.request();
      print('📱 알림 권한 요청 결과: $notificationStatus');
      
      // 배터리 최적화 무시 권한 요청
      final batteryStatus = await Permission.ignoreBatteryOptimizations.request();
      print('🔋 배터리 최적화 무시 권한 요청 결과: $batteryStatus');
      
      // 시스템 알림 권한 요청 ("다른 앱 위에 표시하기")
      final overlayStatus = await Permission.systemAlertWindow.request();
      print('🔧 시스템 알림 권한 요청 결과: $overlayStatus');
      
      // 최종 권한 상태 확인
      final finalPermissions = await PermissionManager.checkAutoTradingPermissions();
      final stillMissing = finalPermissions.entries.where((e) => !(e.value ?? false)).toList();
      
      if (stillMissing.isNotEmpty) {
        print('⚠️ 일부 권한이 여전히 거부됨: ${stillMissing.map((e) => e.key).join(', ')}');
        
        // 설정으로 이동 안내
        if (mounted) {
          await _showSettingsGuideDialog();
        }
      } else {
        print('✅ 모든 권한이 성공적으로 허용되었습니다.');
      }
      
    } catch (e) {
      print('❌ 권한 요청 실패: $e');
    }
  }
  
  /// 설정 안내 다이얼로그
  Future<void> _showSettingsGuideDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('권한 설정 필요'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('일부 권한이 거부되어 백그라운드 자동매매가 제대로 작동하지 않을 수 있습니다.'),
            SizedBox(height: 16),
            Text('설정에서 다음을 확인해주세요:'),
            SizedBox(height: 8),
            Text('• 설정 → 앱 → 거래앱 → 권한'),
            Text('• 설정 → 배터리 → 배터리 최적화'),
            SizedBox(height: 16),
            Text('앱 설정으로 이동하시겠습니까?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('나중에'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              PermissionManager.openAppSettings();
            },
            child: const Text('설정으로 이동'),
          ),
        ],
      ),
    );
  }
  
  void _showErrorDialog(String error) {
    if (!mounted) return;
    
    // 에러 로그만 출력하고 다이얼로그는 표시하지 않음
    print('❌ 스플래시 초기화 오류: $error');
    print('⚠️ 오류가 발생했지만 앱을 계속 진행합니다.');
    
    // 3초 후 자동으로 메인 화면으로 이동
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _navigateToMain();
          }
        });
      }
    });
  }

  /// 안전한 메인 화면 전환
  void _navigateToMain() {
    if (!mounted) return;
    
    print('🔄 메인 화면으로 이동 중...');
    
    // 즉시 MainScreen으로 이동
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      
      try {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const MainScreen()),
          (route) => false,
        );
        print('✅ 화면 전환 성공');
      } catch (e) {
        print('❌ Navigator 오류: $e');
        print('🔄 1초 후 재시도...');
        
        // 1초 후 재시도
        Timer(const Duration(seconds: 1), () {
          if (!mounted) return;
          
          try {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const MainScreen()),
              (route) => false,
            );
            print('✅ 재시도 성공');
          } catch (e2) {
            print('❌ 재시도 실패: $e2');
            print('🔄 앱 재시작...');
            SystemNavigator.pop();
          }
        });
      }
    });
  }

  /// 필수 관심종목 데이터만 로딩 (메모리 최적화)
  Future<void> _loadEssentialWatchlistData() async {
    try {
      print('📊 관심종목 및 보유종목 데이터 로딩 시작...');
      
      // 1. 관심종목 목록 조회
      await _animateTo(0.55, '관심종목 목록 조회 중...');
      final watchlist = await _watchlistRepo.getWatchlistWithStockInfo();
      print('📋 관심종목: ${watchlist.length}개');
      
      // 2. 보유종목 목록 조회
      await _animateTo(0.60, '보유종목 목록 조회 중...');
      final holdings = await _holdingsRepo.getAllHoldings();
      print('📊 보유종목: ${holdings.length}개');
      
      // 3. 중복 제거된 종목 목록 생성
      final allStocks = <String, Map<String, dynamic>>{};
      
      // 관심종목 추가 (시장/이름 보강)
      for (final item in watchlist) {
        final stockCode = item['stock_code']?.toString();
        if (stockCode == null || stockCode.isEmpty) continue;
        String stockName = item['stock_name']?.toString() ?? '';
        String market = item['market']?.toString() ?? 'UNKNOWN';
        if (stockName.isEmpty) {
          try { stockName = (StockMasterParser().getStockInfo(stockCode)?['name']?.toString() ?? ''); } catch (_) {}
        }
        if (market == 'UNKNOWN' || market.isEmpty) {
          try { market = (StockMasterParser().getStockInfo(stockCode)?['market']?.toString() ?? 'UNKNOWN'); } catch (_) {}
          if (market == 'UNKNOWN' || market.isEmpty) {
            market = MarketTimeValidator.instance.getMarketFromSymbol(stockCode);
          }
        }
        allStocks[stockCode] = {
          'stock_code': stockCode,
          'stock_name': stockName,
          'market': market,
          'type': 'watchlist',
        };
      }
      
      // 보유종목 추가 (중복 제거) - 키 보정 및 시장 보강
      for (final item in holdings) {
        final stockCode = (item['stockCode'] ?? item['pdno'])?.toString();
        if (stockCode == null || stockCode.isEmpty) continue;
        final name = (item['stockName'] ?? item['prdt_name'])?.toString() ?? '';
        // 시장 보강: 마스터/휴리스틱
        String market = 'UNKNOWN';
        try {
          final info = StockMasterParser().getStockInfo(stockCode);
          market = (info?['market']?.toString() ?? 'UNKNOWN');
        } catch (_) {}
        if (market == 'UNKNOWN') {
          market = MarketTimeValidator.instance.getMarketFromSymbol(stockCode);
        }
        if (!allStocks.containsKey(stockCode)) {
          allStocks[stockCode] = {
            'stock_code': stockCode,
            'stock_name': name,
            'market': market,
            'type': 'holdings',
          };
        } else {
          allStocks[stockCode]!['type'] = 'both';
          // 시장 정보가 더 정확하면 갱신
          if ((allStocks[stockCode]!['market'] ?? 'UNKNOWN') == 'UNKNOWN' && market != 'UNKNOWN') {
            allStocks[stockCode]!['market'] = market;
          }
        }
      }
      
      // 보유 종목 우선순위 높이기
      final uniqueStocks = allStocks.values.toList()
        ..sort((a, b) {
          final ta = (a['type'] ?? '').toString();
          final tb = (b['type'] ?? '').toString();
          if (ta == tb) return 0;
          // both > holdings > watchlist
          if (ta == 'both') return -1;
          if (tb == 'both') return 1;
          if (ta == 'holdings') return -1;
          if (tb == 'holdings') return 1;
          return 0;
        });
      print('📊 중복 제거된 종목: ${uniqueStocks.length}개');
      
      // 4. 필수 데이터만 로딩 (메모리 최적화)
      await _animateTo(0.65, '필수 데이터 로딩 중...');
      
      int loadedCount = 0;
      final totalCount = uniqueStocks.length;
      
      if (totalCount > 0) {
        // 모든 관심종목과 보유종목 최신화 (제한 없음)
        print('📊 모든 관심종목/보유종목 데이터 로딩: $totalCount개 종목');
        
        // 순차 처리로 메모리 사용량 제한
        for (int i = 0; i < uniqueStocks.length; i++) {
          final stock = uniqueStocks[i];
          final stockCode = stock['stock_code']?.toString() ?? '';
          final stockName = stock['stock_name']?.toString() ?? '';
          final market = stock['market']?.toString() ?? 'UNKNOWN';
          
          final progress = 0.65 + (0.15 * i / uniqueStocks.length);
          final typeLabel = (stock['type'] ?? '').toString();
          final label = typeLabel == 'holdings' || typeLabel == 'both' ? '보유종목' : '관심종목';
          await _animateTo(progress, '$label ${i + 1}/${uniqueStocks.length} 처리 중...');
          
          try {
            print('📊 $stockCode ($stockName) 현재가 데이터만 로딩...');
            
            // 1. 현재가 데이터만 로딩 (차트 데이터는 백그라운드에서 처리)
            await _dataManager.loadCurrentPriceData(stockCode, market);

            // 2. Firestore prices 채우기 보장: @api 현재가 호출(국내/해외 분기)
            await _fetchPriceWithRetry(stockCode: stockCode, market: market);

            // 3. 차트 컬렉션 생성(옵션): 로컬 DB 제거 대비 Firestore에 기본 ohlcv 업서트
            try {
              await _loadChartDataForStock(stockCode, market);
            } catch (e) {
              print('⚠️ 차트 업서트 시도 실패($stockCode): $e');
            }

            // 4. 거래량 데이터 강제 갱신 (해외주식 거래량 0 문제 해결)
            await _ensureVolumeData(stockCode, market);
            
            // 5. 분석 데이터 강제 생성 (관심종목 분석 데이터 없음 문제 해결)
            final uid = FirebaseAuth.instance.currentUser?.uid ?? 'debug-user';
            await _ensureAnalysisData(stockCode, uid);
            
            print('✅ $stockCode ($stockName) 현재가 데이터 로딩 완료');
            loadedCount++;
            
            // 메모리 정리를 위한 짧은 대기
            await Future.delayed(const Duration(milliseconds: 100));
            
          } catch (e) {
            print('❌ $stockCode ($stockName) 데이터 로딩 실패: $e');
          }
        }
      } else {
        await _animateTo(0.75, '로딩할 종목이 없습니다.');
        print('ℹ️ 로딩할 종목이 없습니다.');
      }
      
      print('✅ 관심종목 및 보유종목 데이터 로딩 완료: $loadedCount/$totalCount');
      
      // 5. 데이터베이스 최적화 (백그라운드에서 처리)
      await _animateTo(0.80, '데이터베이스 최적화 준비 중...');
      _optimizeDatabaseInBackground();
      
      // 6. 로딩된 데이터 통계 출력 (빠르게 처리)
      await _animateTo(0.85, '데이터 통계 확인 중...');
      await _printDataStatistics();
      
    } catch (e) {
      print('❌ 관심종목 및 보유종목 데이터 로딩 실패: $e');
    }
  }

  /// 백그라운드 처리 제거됨 - 모든 종목을 메인에서 처리

  /// 현재가 API 호출 보장 + 재시도(최대 2회). 국내/해외 자동 분기
  Future<void> _fetchPriceWithRetry({required String stockCode, required String market}) async {
    const int maxRetries = 2;
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? 'debug-user';
        
        // 1. 차트/현재가/분석 강제 최신화 (서버 보장) - 스플래시에서는 반드시 await
        print('🔄 [스플래시] $stockCode 서버 최신화 보장 시작');
        await RemoteKisService.instance.ensureChartAndAnalyze(uid: uid, symbol: stockCode);
        
        // 2. 현재가 데이터 강제 최신화 (통일된 서비스 사용)
        print('🔄 $stockCode 현재가 데이터 강제 최신화 시도...');
        // Firestore 구독으로 대체되므로 직접 API 호출 비활성화
        print('📊 [스플래시] 직접 API 호출 비활성화 - Firestore 구독 사용: $stockCode');
        final price = null;
        
        if (price != null && price['currentPrice'] != null) {
          print('✅ $stockCode 데이터 최신화 성공: ${price['currentPrice']}');
          break;
        }
        
        // 3. 서버 실패 시 Firestore에서 데이터 확인 (server source 강제)
        print('⚠️ $stockCode 서버 실패 → Firestore에서 데이터 확인...');
        try {
          // Firestore에서 직접 데이터 조회 (캐시 무시)
          final firestoreData = await FirebaseFirestore.instance
              .collection('stocks').doc(stockCode)
              .get(const GetOptions(source: Source.server))
              .then((d) => d.data());
          if (firestoreData != null && firestoreData['current'] != null) {
            final current = firestoreData['current'] as Map<String, dynamic>;
            final currentPrice = current['currentPrice'] as num?;
            if (currentPrice != null && currentPrice > 0) {
              print('✅ $stockCode Firestore에서 데이터 확인: $currentPrice');
              break;
            }
          }
        } catch (firestoreError) {
          print('❌ $stockCode Firestore 조회 실패: $firestoreError');
        }
        
        throw Exception('no price from server and client');
      } catch (e) {
        if (attempt == maxRetries) {
          print('❌ 현재가 서버 최종 실패($stockCode): $e');
        } else {
          final delayMs = 500 * (attempt + 1);
          print('⚠️ 현재가 서버 실패 재시도($stockCode) - ${attempt + 1}/$maxRetries (${delayMs}ms 후)');
          await Future.delayed(Duration(milliseconds: delayMs));
        }
      }
    }
  }

  /// 클라이언트에서 직접 현재가 조회 (서버 실패 시 백업) - UnifiedStockService 사용
  Future<Map<String, dynamic>?> _fetchPriceDirectly(String stockCode, String market) async {
    try {
      // 통일된 서비스 사용
      // Firestore 구독으로 대체되므로 직접 API 호출 비활성화
      print('📊 [스플래시] 직접 API 호출 비활성화 - Firestore 구독 사용: $stockCode');
      final result = null;
      if (result != null && result['currentPrice'] != null) {
        print('✅ 통일된 서비스 직접 호출 성공: $stockCode');
        return result;
      }
    } catch (e) {
      print('❌ 통일된 서비스 직접 호출 실패($stockCode): $e');
    }
    return null;
  }

  /// 거래량 데이터 강제 갱신 (해외주식 거래량 0 문제 해결)
  Future<void> _ensureVolumeData(String stockCode, String market) async {
    try {
      // 해외주식만 거래량 강제 갱신 (국내주식은 실시간 거래량 정상 제공)
      if (market != 'KOSPI' && market != 'KOSDAQ' && !RegExp(r'^[0-9]{5,6}$').hasMatch(stockCode)) {
        print('🔄 $stockCode 해외주식 거래량 강제 갱신 시도...');
        
        // 1. 서버에서 거래량 데이터 확인
        final uid = FirebaseAuth.instance.currentUser?.uid ?? 'debug-user';
        await RemoteKisService.instance.ensureChartAndAnalyze(uid: uid, symbol: stockCode);
        
        // 2. 클라이언트에서 직접 거래량 조회 (통일된 서비스 사용)
        // Firestore 구독으로 대체되므로 직접 API 호출 비활성화
      print('📊 [스플래시] 직접 API 호출 비활성화 - Firestore 구독 사용: $stockCode');
      final result = null;
        
        if (result != null && result['volume'] != null && result['volume'] > 0) {
          print('✅ $stockCode 거래량 갱신 성공: ${result['volume']}');
        } else {
          print('ℹ️ $stockCode 거래량 0은 정상 (정규장 시간 외)');
        }
      }
    } catch (e) {
      print('❌ $stockCode 거래량 갱신 실패: $e');
    }
  }

  /// 분석 데이터 강제 생성 (관심종목 분석 데이터 없음 문제 해결)
  Future<void> _ensureAnalysisData(String stockCode, String uid) async {
    try {
      print('🔄 $stockCode 분석 데이터 강제 생성 시도...');
      
      // 1. 서버에서 차트데이터 + 분석 데이터 강제 생성 (여러 번 시도)
      for (int attempt = 1; attempt <= 3; attempt++) {
        print('🔄 $stockCode 서버 데이터 생성 시도 $attempt/3...');
        final success = await RemoteKisService.instance.ensureChartAndAnalyze(uid: uid, symbol: stockCode);
        if (success) {
          print('✅ $stockCode 서버 데이터 생성 성공 (시도 $attempt)');
          break;
        } else {
          print('⚠️ $stockCode 서버 데이터 생성 실패 (시도 $attempt)');
          if (attempt < 3) {
            await Future.delayed(Duration(seconds: attempt * 2)); // 2초, 4초 대기
          }
        }
      }
      
      // 2. 분석 결과 확인 (AnalysisFunctionsService 사용)
      final analysisService = AnalysisFunctionsService();
      final analysisResult = await analysisService.analyzeStock(symbol: stockCode, days: 100);
      
      if (analysisResult != null && analysisResult.isNotEmpty) {
        print('✅ $stockCode 분석 데이터 생성 성공');
      } else {
        print('⚠️ $stockCode 분석 데이터 생성 실패 또는 빈 결과');
      }
    } catch (e) {
      print('❌ $stockCode 분석 데이터 생성 실패: $e');
    }
  }

  /// 데이터베이스 최적화 (백그라운드에서 처리)
  void _optimizeDatabaseInBackground() {
    // 백그라운드에서 처리하여 스플래시 화면 블로킹 방지
    Future.microtask(() async {
      try {
        print('⚡ 백그라운드 데이터베이스 최적화 시작...');
        
        // 1. 오래된 데이터 정리만 먼저 실행 (빠름)
        await AppDataManager.instance.databaseHelper.cleanupOldData();
        
        // 2. 메모리 정리
        PerformanceMonitor().forceMemoryCleanup();
        
        print('✅ 백그라운드 데이터베이스 최적화 1단계 완료');
        
        // 3. VACUUM, REINDEX, ANALYZE는 앱 사용 중에는 실행하지 않음 (데이터베이스 락 방지)
        // 대신 앱 종료 시나 사용자가 적극적으로 사용하지 않을 때만 실행
        print('⚠️ 데이터베이스 락 방지를 위해 VACUUM, REINDEX, ANALYZE는 생략합니다.');
        print('💡 필요시 앱 설정에서 수동으로 데이터베이스 최적화를 실행할 수 있습니다.');
        
      } catch (e) {
        print('❌ 백그라운드 데이터베이스 최적화 실패: $e');
      }
    });
  }

  /// 개별 종목의 차트 데이터 로딩
  Future<void> _loadChartDataForStock(String stockCode, String market) async {
    try {
      // 서버 캐시 차트 조회(100일)
      final chartData = await RemoteKisService.instance.getStockData(stockCode);
      print('✅ 서버 차트 수신: $stockCode (${chartData.length}일)');
    } catch (e) {
      print('❌ $stockCode 차트 데이터 로딩 실패(서버): $e');
    }
  }

  /// 상위 종목들의 차트 데이터 로딩 (AI 추천용)
  Future<void> _loadTopStocksData() async {
    try {
      print('📊 상위 종목 데이터 로딩 시작...');
      
      // TODO: 나스닥/코스닥/코스피 상위 50개씩 리스트는 나중에 제공받을 예정
      // 현재는 임시로 주요 종목들만 로딩
      final topStocks = [
        // 코스피 상위 종목들 (임시)
        {'code': '005930', 'name': '삼성전자', 'market': 'KOSPI'},
        {'code': '000660', 'name': 'SK하이닉스', 'market': 'KOSPI'},
        {'code': '035420', 'name': 'NAVER', 'market': 'KOSPI'},
        {'code': '051910', 'name': 'LG화학', 'market': 'KOSPI'},
        {'code': '006400', 'name': '삼성SDI', 'market': 'KOSPI'},
        
        // 코스닥 상위 종목들 (임시)
        {'code': '035720', 'name': '카카오', 'market': 'KOSDAQ'},
        {'code': '207940', 'name': '삼성바이오로직스', 'market': 'KOSDAQ'},
        {'code': '068270', 'name': '셀트리온', 'market': 'KOSDAQ'},
        {'code': '323410', 'name': '카카오뱅크', 'market': 'KOSDAQ'},
        {'code': '035760', 'name': 'CJ ENM', 'market': 'KOSDAQ'},
        
        // 나스닥 상위 종목들 (임시)
        {'code': 'AAPL', 'name': 'Apple Inc.', 'market': 'NASDAQ'},
        {'code': 'MSFT', 'name': 'Microsoft Corporation', 'market': 'NASDAQ'},
        {'code': 'GOOGL', 'name': 'Alphabet Inc.', 'market': 'NASDAQ'},
        {'code': 'AMZN', 'name': 'Amazon.com Inc.', 'market': 'NASDAQ'},
        {'code': 'TSLA', 'name': 'Tesla Inc.', 'market': 'NASDAQ'},
      ];
      
      int loadedCount = 0;
      final totalCount = topStocks.length;
      
      for (final stock in topStocks) {
        try {
          final stockCode = stock['code']?.toString() ?? '';
          final stockName = stock['name']?.toString() ?? '';
          final market = stock['market']?.toString() ?? 'UNKNOWN';
          
          print('📊 상위종목 $stockCode ($stockName) 데이터 로딩 중...');
          
          // 차트 데이터 로딩
          await _loadChartDataForStock(stockCode, market);
          
          loadedCount++;
          print('✅ 상위종목 $stockCode ($stockName) 데이터 로딩 완료 ($loadedCount/$totalCount)');
          
        } catch (e) {
          print('❌ 상위종목 데이터 로딩 실패: $e');
          loadedCount++; // 실패해도 카운트 증가
        }
      }
      
      print('✅ 상위 종목 데이터 로딩 완료: $loadedCount/$totalCount');
      
    } catch (e) {
      print('❌ 상위 종목 데이터 로딩 실패: $e');
    }
  }

  /// 로딩된 데이터 통계 출력
  Future<void> _printDataStatistics() async {
    try {
      print('📊 로딩된 데이터 통계:');
      
      // 차트 데이터 통계
      final chartStats = await _chartRepo.getChartDataStats();
      print('  📈 차트 데이터: ${chartStats['total_records'] ?? 0}개 레코드, ${chartStats['unique_stocks'] ?? 0}개 종목');
      
      // 현재가 데이터 통계
      final priceStats = await _currentPriceRepo.getCurrentPriceStats();
      print('  💰 현재가 데이터: ${priceStats['total_records'] ?? 0}개 레코드, ${priceStats['unique_stocks'] ?? 0}개 종목');
      
      // 관심종목 통계
      final watchlistCount = await _watchlistRepo.getWatchlistCount();
      print('  📋 관심종목: $watchlistCount개');
      
      // 보유종목 통계
      final holdings = await _holdingsRepo.getAllHoldings();
      print('  📊 보유종목: ${holdings.length}개');
      
    } catch (e) {
      print('❌ 데이터 통계 출력 실패: $e');
    }
  }



  @override
  Widget build(BuildContext context) {
    // 상태표시줄을 앱 테마색으로 연장하고 아이콘을 하얀색으로 설정
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent, // 상태표시줄 배경을 투명하게
        statusBarIconBrightness: Brightness.light, // 상태표시줄 아이콘을 하얀색으로
        statusBarBrightness: Brightness.dark, // iOS용 상태표시줄 스타일
        systemNavigationBarColor: Colors.transparent, // 네비게이션 바 배경을 투명하게
        systemNavigationBarIconBrightness: Brightness.light, // 네비게이션 바 아이콘을 하얀색으로
      ),
    );
    
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue[900]!,
              Colors.blue[800]!,
              Colors.blue[700]!,
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 앱 로고
              AnimatedBuilder(
                animation: _iconBounce,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        Colors.blue[400]!,
                        Colors.blue[600]!,
                        Colors.blue[800]!,
                      ],
                      stops: const [0.0, 0.7, 1.0],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue[400]!.withOpacity(0.6),
                        blurRadius: 30,
                        spreadRadius: 10,
                        offset: const Offset(0, 15),
                      ),
                      BoxShadow(
                        color: Colors.white.withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withOpacity(0.3),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.trending_up,
                      size: 60,
                      color: Colors.white,
                    ),
                  ),
                ),
                builder: (context, child) => Transform.translate(
                  offset: Offset(0, _iconBounce.value),
                  child: Transform.scale(
                    scale: _iconScale.value,
                    child: child,
                  ),
                ),
              ),

              const SizedBox(height: 24),
              const Text(
                'AI HELPER',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3.0,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      offset: Offset(0, 2),
                      blurRadius: 4,
                      color: Colors.black26,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              // 진행 상황 표시
              Container(
                width: 320,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.blue[700]!.withOpacity(0.9),
                      Colors.blue[800]!.withOpacity(0.8),
                      Colors.blue[900]!.withOpacity(0.7),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: Colors.blue[400]!.withOpacity(0.2),
                      blurRadius: 15,
                      spreadRadius: 2,
                      offset: const Offset(0, 0),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // 현재 작업 표시
                    Text(
                      _currentTask,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // 진행 바
                    Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: LinearProgressIndicator(
                          value: _progress,
                          backgroundColor: Colors.transparent,
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                          minHeight: 10,
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // 진행률 퍼센트
                    Text(
                      '${(_progress * 100).toInt()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 40),
              
              // 로딩 인디케이터
              if (_isLoading)
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (_iconBounceController.isAnimating) {
      _iconBounceController.stop();
    }
    _iconBounceController.dispose();
    super.dispose();
  }
}
