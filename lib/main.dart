import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'core/state/trading_bloc.dart';
import 'core/state/auto_trading_bloc.dart';
import 'core/trading/background_trading_service.dart';
import 'core/services/local_notification_manager.dart';
import 'core/services/permission_manager.dart';
import 'core/services/foreground_service_manager.dart';
import 'core/services/trading_event_channel.dart';

import 'core/services/app_icon_badge_service.dart';
import 'core/services/signal_tracker.dart';
import 'core/data/app_data_manager.dart';
import 'core/config/api_config.dart';
import 'core/api/kis_unified_api_service.dart';
import 'core/analysis/signal_notification_system.dart';
import 'core/services/realtime_score_service.dart';
import 'features/splash/splash_screen.dart';
import 'features/main/main_screen.dart';
import 'features/onboarding/api_key_setup_screen.dart';

Future<void> pingFirestoreOnce() async {
  final docRef = FirebaseFirestore.instance.collection('app_health').doc('ping');
  await docRef.set({'ts': DateTime.now().toIso8601String()}, SetOptions(merge: true));
  await docRef.get();
}

void main() async {
  // Flutter 바인딩 초기화
  WidgetsFlutterBinding.ensureInitialized();
  
  // 웹 환경에서 데이터베이스 초기화
  if (kIsWeb) {
    print('🌐 웹 환경 감지 - 데이터베이스 초기화');
    try {
      // 웹 전용 데이터베이스 팩토리 초기화
      databaseFactory = databaseFactoryFfiWeb;
      print('✅ 웹용 데이터베이스 팩토리 초기화 완료');
    } catch (e) {
      print('❌ 웹용 데이터베이스 초기화 실패: $e');
    }
  }
  
  // 먼저 앱을 실행해서 즉시 스플래시가 렌더링되도록 함
  runApp(const MyApp());

  // 나머지 초기화는 스플래시에서 진행되므로 여기서는 최소화
  try {
    print('🚀 main() 경량 초기화 시작');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('✅ Firebase initialize 완료');
    await pingFirestoreOnce();
    print('✅ Firestore ping 완료');
    await ApiConfig.instance.initialize();
    await AppDataManager.instance.initialize();
    await BackgroundTradingService().initialize();
    await LocalNotificationManager().initialize();
    await SignalNotificationSystem().initialize();
    
    // 실시간 점수 서비스는 스플래시 화면에서 초기화 완료 후 시작
    // 여기서는 시작하지 않음 (데이터베이스 락 방지)
    
    // 자동매매 이벤트 리스너 시작
    TradingEventChannel.startListening();
    
    // 권한 상태 확인 (앱 시작 시)
    try {
      final permissionStatus = await PermissionManager.getPermissionStatus();
      print('🔐 권한 상태: $permissionStatus');
      
      if (!permissionStatus['allGranted']!) {
        print('⚠️ 일부 권한이 부족합니다. 사용자가 자동매매 시작 시 권한을 요청할 수 있습니다.');
      }
    } catch (e) {
      print('❌ 권한 상태 확인 실패: $e');
    }
    
    // 백그라운드 서비스 복구 (Native Service 기반)
    final isAutoTradingEnabled = await AppDataManager.instance.getAutoTradingStatus();
    if (isAutoTradingEnabled) {
      // Native Foreground Service 시작
      await ForegroundServiceManager.startForegroundService();
      
      // 앱 아이콘 배지 복구
      await AppIconBadgeService.showAutoTradingBadge();
    }

    
    print('✅ main() 경량 초기화 완료');
  } catch (e, stackTrace) {
    print('❌ main() 경량 초기화 실패: $e');
    print('스택 트레이스: $stackTrace');
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.detached:
        // 앱이 완전히 종료될 때 자동매매 OFF
        _disableAutoTradingOnAppExit();
        break;
      case AppLifecycleState.paused:
        // 앱이 백그라운드로 갈 때도 자동매매 OFF (선택사항)
        // _disableAutoTradingOnAppExit();
        break;
      case AppLifecycleState.resumed:
        // 앱이 포그라운드로 돌아올 때는 아무것도 하지 않음
        break;
      case AppLifecycleState.inactive:
        // 앱이 비활성화될 때는 아무것도 하지 않음
        break;
      case AppLifecycleState.hidden:
        // 앱이 숨겨질 때는 아무것도 하지 않음
        break;
    }
  }

  /// 앱 종료 시 자동매매 비활성화
  Future<void> _disableAutoTradingOnAppExit() async {
    try {
      print('🛑 앱 종료 감지 - 자동매매 비활성화 중...');
      
      // 현재 자동매매 상태 확인
      final isCurrentlyEnabled = await AppDataManager.instance.getAutoTradingStatus();
      
      if (isCurrentlyEnabled) {
        // 자동매매 OFF로 설정
        await AppDataManager.instance.setAutoTradingStatus(false);
        print('✅ 앱 종료 시 자동매매 비활성화 완료');
        
        // 사용자에게 알림 (선택사항)
        await LocalNotificationManager().showNotification(
          title: '🛑 자동매매 중지',
          body: '앱이 종료되어 자동매매가 중지되었습니다.',
        );
      } else {
        print('ℹ️ 자동매매가 이미 비활성화되어 있음');
      }
    } catch (e) {
      print('❌ 앱 종료 시 자동매매 비활성화 실패: $e');
    }
  }

  /// 초기 화면 결정
  Widget _getInitialScreen() {
    return FutureBuilder<bool>(
      future: _checkApiConfigFromPrefs(),
      builder: (context, snapshot) {
        try {
          print('🔍 _getInitialScreen() 호출됨...');
          
          // 로딩 중일 때는 로딩 화면 표시
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }
          
          // API 설정이 유효한지 확인
          final isValid = snapshot.data ?? false;
          print('🔍 SharedPreferences API 설정 확인 결과: $isValid');
          
          if (isValid) {
            print('✅ SplashScreen으로 이동 (API 설정 완료)');
            return const SplashScreen();
          } else {
            print('⚠️ ApiKeySetupScreen으로 이동 (API 설정 필요)');
            return const ApiKeySetupScreen();
          }
        } catch (e) {
          print('❌ 초기 화면 결정 실패: $e');
          return const ApiKeySetupScreen(); // 기본값으로 API 키 설정 화면
        }
      },
    );
  }

  /// SharedPreferences에서 API 설정 직접 확인
  Future<bool> _checkApiConfigFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appKey = prefs.getString('api_app_key');
      final appSecret = prefs.getString('api_app_secret');
      final accountNo = prefs.getString('api_account_no');
      
      final isValid = appKey != null && 
                     appSecret != null && 
                     accountNo != null &&
                     appKey.isNotEmpty &&
                     appSecret.isNotEmpty &&
                     accountNo.isNotEmpty;
      
      print('🔍 SharedPreferences API 설정:');
      print('   - AppKey: ${appKey?.substring(0, appKey.length > 10 ? 10 : appKey.length)}...');
      print('   - AppSecret: ${appSecret?.substring(0, appSecret.length > 10 ? 10 : appSecret.length)}...');
      print('   - AccountNo: $accountNo');
      print('   - IsValid: $isValid');
      
      return isValid;
    } catch (e) {
      print('❌ SharedPreferences API 설정 확인 실패: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<TradingBloc>(
          create: (context) {
            try {
              return TradingBloc(
                appDataManager: AppDataManager.instance,
                unifiedApiService: KisUnifiedApiService(),
              );
            } catch (e) {
              print('⚠️ TradingBloc 생성 실패: $e');
              // 기본 API 서비스로 생성
              return TradingBloc(
                appDataManager: AppDataManager.instance,
                unifiedApiService: KisUnifiedApiService(),
              );
            }
          },
        ),
        BlocProvider<AutoTradingBloc>(
          create: (context) => AutoTradingBloc(),
        ),
      ],
      child: MaterialApp(
        title: 'Trading App',
        debugShowCheckedModeBanner: false, // 디버그 배너 제거
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF3B5BA9),
            brightness: Brightness.light,
          ),
          // 전역 텍스트 크기 +2 적용
          textTheme: Typography.material2021().englishLike.copyWith(
            displayLarge: Typography.material2021().englishLike.displayLarge?.copyWith(
              fontSize: 98,
              color: Colors.black87,
            ),
            displayMedium: Typography.material2021().englishLike.displayMedium?.copyWith(
              fontSize: 62,
              color: Colors.black87,
            ),
            displaySmall: Typography.material2021().englishLike.displaySmall?.copyWith(
              fontSize: 50,
              color: Colors.black87,
            ),
            headlineLarge: Typography.material2021().englishLike.headlineLarge?.copyWith(
              fontSize: 42,
              color: Colors.black87,
            ),
            headlineMedium: Typography.material2021().englishLike.headlineMedium?.copyWith(
              fontSize: 36,
              color: Colors.black87,
            ),
            headlineSmall: Typography.material2021().englishLike.headlineSmall?.copyWith(
              fontSize: 26,
              color: Colors.black87,
            ),
            titleLarge: Typography.material2021().englishLike.titleLarge?.copyWith(
              fontSize: 22,
              color: Colors.black87,
            ),
            titleMedium: Typography.material2021().englishLike.titleMedium?.copyWith(
              fontSize: 18,
              color: Colors.black87,
            ),
            titleSmall: Typography.material2021().englishLike.titleSmall?.copyWith(
              fontSize: 16,
              color: Colors.black87,
            ),
            bodyLarge: Typography.material2021().englishLike.bodyLarge?.copyWith(
              fontSize: 18,
              color: Colors.black87,
            ),
            bodyMedium: Typography.material2021().englishLike.bodyMedium?.copyWith(
              fontSize: 16,
              color: Colors.black87,
            ),
            bodySmall: Typography.material2021().englishLike.bodySmall?.copyWith(
              fontSize: 14,
              color: Colors.black87,
            ),
            labelLarge: Typography.material2021().englishLike.labelLarge?.copyWith(
              fontSize: 16,
              color: Colors.black87,
            ),
            labelMedium: Typography.material2021().englishLike.labelMedium?.copyWith(
              fontSize: 13,
              color: Colors.black87,
            ),
            labelSmall: Typography.material2021().englishLike.labelSmall?.copyWith(
              fontSize: 12,
              color: Colors.black87,
            ),
          ),
          scaffoldBackgroundColor: const Color(0xFFE9ECF1),
          cardTheme: CardThemeData(
            color: const Color(0xFFFFFBF5),
            surfaceTintColor: Colors.transparent,
            elevation: 2,
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.black.withOpacity(0.06)),
            ),
            shadowColor: Colors.black.withOpacity(0.08),
          ),
          appBarTheme: AppBarTheme(
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: const Color(0xFF3B5BA9),
            surfaceTintColor: Colors.transparent,
            foregroundColor: Colors.white,
            centerTitle: false,
            shadowColor: Colors.black.withOpacity(0.12),

          ),
          bottomNavigationBarTheme: BottomNavigationBarThemeData(
            backgroundColor: Colors.white.withOpacity(0.95),
            elevation: 12,
            selectedItemColor: const Color(0xFF3B5BA9),
            unselectedItemColor: Colors.grey,
            type: BottomNavigationBarType.fixed,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B5BA9),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            backgroundColor: Colors.black87,
            contentTextStyle: const TextStyle(color: Colors.white),
          ),
          dividerTheme: DividerThemeData(color: Colors.grey.shade300),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(color: Color(0xFF3B5BA9), width: 1.5),
            ),
          ),
        ),
        home: _getInitialScreen(),
        routes: {
          '/splash': (context) => const SplashScreen(),
          '/main': (context) {
            final args = ModalRoute.of(context)?.settings.arguments;
            final tabIndex = args is int ? args : null;
            return MainScreen(initialTabIndex: tabIndex);
          },
          '/api-setup': (context) => const ApiKeySetupScreen(),
        },
        // Navigator 상태 초기화를 위한 설정
        navigatorKey: GlobalKey<NavigatorState>(),
      ),
    );
  }
}
