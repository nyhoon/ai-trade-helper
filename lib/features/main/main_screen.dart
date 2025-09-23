import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../trading/trading_screen.dart';
import '../analysis/analysis_screen.dart';
import '../alerts/alerts_screen.dart';
import '../history/history_screen.dart';
import '../account/account_screen.dart';

import 'dart:async';
import '../../core/data/app_data_manager.dart';
// import '../../core/trading/auto_trading_service.dart';
import '../../core/trading/auto_trading_cycle.dart';
import '../../core/trading/investment_style_manager.dart';
import '../../core/trading/investment_style.dart';
import '../../core/state/auto_trading_bloc.dart';
import '../../core/services/foreground_service_manager.dart';
import '../../core/services/permission_manager.dart';
import '../../core/ai/ai_recommendation_service.dart';


class MainScreen extends StatefulWidget {
  final int? initialTabIndex;
  
  const MainScreen({super.key, this.initialTabIndex});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  AutoTradingCycle? _autoTradingCycle;
  int _currentIndex = 0;
  final PageController _pageController = PageController();
  final InvestmentStyleManager _styleManager = InvestmentStyleManager();
  StreamSubscription<InvestmentStyle>? _styleSubscription;
  final StreamController<void> _tradingTabFocusController = StreamController<void>.broadcast();

  late final List<Widget> _screens = [
    TradingScreen(onTabFocusedStream: _tradingTabFocusController.stream),
    const AnalysisScreen(),
    const AccountScreen(),
    const HistoryScreen(),
    const AlertsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // 위젯이 완전히 빌드된 후에 초기화 작업 수행
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeStyleManager();
        _initializeAutoTrading();
        _checkInitialization();
        // 메인 진입 시 추천 서비스는 자동 시작하지 않음
        // 추천 탭에서 사용자가 진입/요청할 때만 실행되도록 유지
        if (widget.initialTabIndex != null) {
          navigateToTab(widget.initialTabIndex!);
        }
      }
    });
  }

  Future<void> _initializeStyleManager() async {
    await _styleManager.initialize();
    
    // 스타일 변경 리스너 등록
    _styleSubscription = _styleManager.styleStream.listen((style) {
      if (mounted) {
        setState(() {}); // UI 업데이트
      }
    });
    
    setState(() {}); // UI 업데이트
  }

  Future<void> _initializeAutoTrading() async {
    try {
      _autoTradingCycle = AutoTradingCycle();
      
      // 자동매매 사이클 시작
      await _autoTradingCycle!.startCycle();
      
      // Foreground Service 상태 확인 및 복구
      await _checkAndRestoreForegroundService();
      
      print('🚀 자동매매 서비스 및 사이클 초기화 완료');
    } catch (e) {
      print('❌ 자동매매 서비스 초기화 실패: $e');
    }
  }
  
  /// Foreground Service 상태 확인 및 복구
  Future<void> _checkAndRestoreForegroundService() async {
    try {
      // Foreground Service 상태 확인
      final isRunning = await ForegroundServiceManager.isForegroundServiceRunning();
      
      if (!isRunning) {
        print('⚠️ Foreground Service가 실행되지 않았습니다. 재시작을 시도합니다...');
        
        // 자동매매가 활성화되어 있다면 Foreground Service 재시작
        final isAutoTradingEnabled = await AppDataManager.instance.getAutoTradingStatus();
        if (isAutoTradingEnabled) {
          final success = await ForegroundServiceManager.restartForegroundService();
          
          if (success) {
            print('✅ Foreground Service 복구 성공');
            _showServiceRestoredSnackBar();
          } else {
            print('❌ Foreground Service 복구 실패');
            _showServiceRestoreFailedSnackBar();
          }
        }
      } else {
        print('✅ Foreground Service가 정상 실행 중입니다.');
      }
    } catch (e) {
      print('❌ Foreground Service 상태 확인 실패: $e');
    }
  }
  
  void _showServiceRestoredSnackBar() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ 백그라운드 자동매매가 복구되었습니다.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.fixed, // 고정 위치
        ),
      );
    }
  }
  
  void _showServiceRestoreFailedSnackBar() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ 백그라운드 자동매매 복구에 실패했습니다. 앱을 다시 시작해주세요.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 5),
          behavior: SnackBarBehavior.fixed, // 고정 위치
        ),
      );
    }
  }



  Future<void> _checkInitialization() async {
    // AppDataManager가 초기화되지 않은 경우에도 MainScreen에서 처리할 수 있도록
    // 스플래시로 돌아가지 않고 현재 화면에서 초기화를 시도합니다.
    if (!AppDataManager.instance.isInitialized) {
      print('⚠️ AppDataManager가 초기화되지 않았습니다. 현재 화면에서 초기화를 시도합니다.');
      // 여기서는 스플래시로 돌아가지 않고, 필요한 경우 현재 화면에서 초기화 로직을 실행
      // 또는 사용자에게 초기화가 필요하다는 메시지를 표시할 수 있습니다.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoTradingCycle?.stopCycle();
    _pageController.dispose();
    _styleSubscription?.cancel();
    _tradingTabFocusController.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        // 앱이 포그라운드로 돌아왔을 때
        print('🔄 앱이 포그라운드로 돌아왔습니다');
        _checkAutoTradingStatus();
        break;
      case AppLifecycleState.inactive:
        // 앱이 비활성화되었을 때 (다른 앱으로 전환 중)
        print('⏸️ 앱이 비활성화되었습니다');
        break;
      case AppLifecycleState.paused:
        // 앱이 백그라운드로 갔을 때
        print('⏸️ 앱이 백그라운드로 갔습니다');
        _ensureForegroundServiceRunning();
        break;
      case AppLifecycleState.detached:
        // 앱이 완전히 종료되었을 때
        print('🔄 앱이 종료되었습니다');
        break;
      case AppLifecycleState.hidden:
        // 앱이 숨겨졌을 때
        print('👁️ 앱이 숨겨졌습니다');
        break;
    }
  }
  
  /// 자동매매 상태 확인
  Future<void> _checkAutoTradingStatus() async {
    try {
      final isAutoTradingEnabled = await AppDataManager.instance.getAutoTradingStatus();
      if (isAutoTradingEnabled) {
        print('🤖 자동매매가 활성화되어 있습니다.');
        
        // Foreground Service 상태 확인
        final isServiceRunning = await ForegroundServiceManager.isForegroundServiceRunning();
        if (!isServiceRunning) {
          print('⚠️ Foreground Service가 중단되었습니다. 재시작합니다...');
          await ForegroundServiceManager.restartForegroundService();
        }
      } else {
        print('🤖 자동매매가 비활성화되어 있습니다.');
      }
    } catch (e) {
      print('❌ 자동매매 상태 확인 실패: $e');
    }
  }
  
  /// Foreground Service 실행 보장
  Future<void> _ensureForegroundServiceRunning() async {
    try {
      final isAutoTradingEnabled = await AppDataManager.instance.getAutoTradingStatus();
      if (isAutoTradingEnabled) {
        final isServiceRunning = await ForegroundServiceManager.isForegroundServiceRunning();
        if (!isServiceRunning) {
          print('🔄 백그라운드 전환 시 Foreground Service 재시작...');
          await ForegroundServiceManager.startForegroundService();
        }
      }
    } catch (e) {
      print('❌ Foreground Service 실행 보장 실패: $e');
    }
  }

  void navigateToTab(int index) {
    setState(() {
      _currentIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          if (mounted) {
            setState(() {
              _currentIndex = index;
            });
            if (index == 0) {
              // 거래 탭 포커스 시 강제 동기화 트리거
              _tradingTabFocusController.add(null);
            }
          }
        },
        children: _screens.map((screen) => screen).toList(),
      ),

      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: navigateToTab,
        selectedItemColor: _getSelectedColor(),
        unselectedItemColor: Colors.grey,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.trending_up),
            label: '거래',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.analytics),
            label: '분석',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.account_balance),
            label: '계좌',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.history),
            label: '내역',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.notifications),
            label: '알림',
          ),
        ],
      ),
    );
  }

  Color _getSelectedColor() {
    switch (_currentIndex) {
      case 0:
        return Colors.blue;
      case 1:
        return Colors.red;
      case 2:
        return Colors.green;
      case 3:
        return Colors.orange;
      case 4:
        return Colors.purple;
      default:
        return Colors.blue;
    }
  }
}
