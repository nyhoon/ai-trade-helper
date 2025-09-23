import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/kis_unified_api_service.dart';
import '../data/app_data_manager.dart';
import '../services/local_notification_manager.dart';
// import 'auto_trading_service.dart';
import 'investment_style.dart';
import 'usecases/sync_account_info_usecase.dart';
import 'usecases/sync_universe_usecase.dart';
import 'usecases/analyze_signals_usecase.dart';
import 'usecases/execute_orders_usecase.dart';
import 'usecases/persist_notification_usecase.dart';
import 'usecases/track_order_status_usecase.dart';
import 'usecases/advanced_risk_manager.dart';
import 'investment_style_manager.dart';

class BackgroundTradingService {
  static final BackgroundTradingService _instance = BackgroundTradingService._internal();
  factory BackgroundTradingService() => _instance;
  BackgroundTradingService._internal();

  bool _isInitialized = false;
  bool _isServiceRunning = false;
  Timer? _autoTradingTimer;
  Timer? _marketMonitoringTimer;
  bool _tickInProgress = false;
  DateTime? _lastTickAt;
  final InvestmentStyleManager _styleManager = InvestmentStyleManager();

  /// 서비스 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;

    // 투자스타일 매니저 초기화
    await _styleManager.initialize();
    
    _isInitialized = true;
    print('✅ 백그라운드 트레이딩 서비스 초기화 완료');
  }

  /// 백그라운드 서비스 시작
  Future<void> startBackgroundService() async {
    print('🚀 백그라운드 서비스 시작 요청...');
    
    if (!_isInitialized) {
      print('🔧 서비스 초기화 중...');
      await initialize();
    }

    if (_isServiceRunning) {
      print('⚠️ 백그라운드 서비스가 이미 실행 중입니다.');
      return;
    }

    try {
      print('📱 AppDataManager 초기화 중...');
      // AppDataManager 초기화
      await AppDataManager.instance.initialize();
      print('✅ AppDataManager 초기화 완료');
      
      // 자동매매 상태 확인
      final isAutoTradingEnabled = await AppDataManager.instance.getAutoTradingStatus();
      print('🔍 자동매매 활성화 상태: $isAutoTradingEnabled');
      
      if (!isAutoTradingEnabled) {
        print('⚠️ 자동매매가 비활성화되어 있어 서비스를 시작하지 않습니다.');
        return;
      }
      
      print('⏰ 자동매매 타이머 설정 중... (3분 간격)');
      // 자동매매 타이머 시작 (3분마다, 지터 적용)
      _autoTradingTimer = Timer.periodic(const Duration(minutes: 3), (timer) async {
        print('🔄 자동매매 타이머 트리거됨: ${DateTime.now().toString()}');
        // 지터 ±15초
        final jitterMs = (DateTime.now().millisecondsSinceEpoch % 30000) - 15000;
        final jitterDelay = Duration(milliseconds: jitterMs.abs());
        print('⏱️ 지터 지연: ${jitterDelay.inMilliseconds}ms');
        await Future.delayed(jitterDelay);
        await _executeAutoTrading();
      });
      
      print('📊 시장 모니터링 타이머 설정 중... (10분 간격)');
      // 시장 모니터링 타이머 시작 (10분마다)
      _marketMonitoringTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
        print('📊 시장 모니터링 타이머 트리거됨: ${DateTime.now().toString()}');
        _executeMarketMonitoring();
      });

      _isServiceRunning = true;
      print('💾 서비스 상태 저장 중...');
      await _saveServiceState(true);
      
      // 자동매매 서비스 알림 표시 (한 번만)
      print('🔔 자동매매 서비스 알림 표시 중...');
      await LocalNotificationManager().showAutoTradingNotification();
      
      print('✅ 백그라운드 서비스 시작됨 (Timer 기반)');
      print('📊 서비스 상태:');
      print('   - 실행 중: $_isServiceRunning');
      print('   - 자동매매 타이머: ${_autoTradingTimer != null ? "활성" : "비활성"}');
      print('   - 시장 모니터링 타이머: ${_marketMonitoringTimer != null ? "활성" : "비활성"}');
      print('   - 마지막 실행: ${_lastTickAt?.toString() ?? "없음"}');
      
    } catch (e) {
      print('❌ 백그라운드 서비스 시작 실패: $e');
      print('📊 오류 상세:');
      print('   - 오류 타입: ${e.runtimeType}');
      print('   - 오류 메시지: $e');
      rethrow;
    }
  }

  /// 백그라운드 서비스 중지
  Future<void> stopBackgroundService() async {
    if (!_isServiceRunning) {
      print('⚠️ 백그라운드 서비스가 실행 중이 아닙니다.');
      return;
    }

    try {
      // 타이머 정리
      _autoTradingTimer?.cancel();
      _marketMonitoringTimer?.cancel();
      _autoTradingTimer = null;
      _marketMonitoringTimer = null;

      // 실시간 가격 서비스 중지
      await AppDataManager.instance.realtimePriceService.stop();

      _isServiceRunning = false;
      await _saveServiceState(false);
      
      // 자동매매 서비스 알림 제거
      await LocalNotificationManager().hideAutoTradingNotification();
      
      print('✅ 백그라운드 서비스 중지됨');
    } catch (e) {
      print('❌ 백그라운드 서비스 중지 실패: $e');
      rethrow;
    }
  }

  /// 서비스 상태 확인
  Future<bool> isServiceRunning() async {
    if (!_isInitialized) {
      await initialize();
    }
    
    // SharedPreferences에서 상태 확인
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('background_service_running') ?? false;
  }

  /// 서비스 상태 저장
  Future<void> _saveServiceState(bool isRunning) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('background_service_running', isRunning);
  }

  /// 자동매매 실행
  Future<void> _executeAutoTrading() async {
    if (_tickInProgress) {
      print('⚠️ 이전 사이클이 아직 실행 중입니다. 건너뜁니다.');
      return;
    }

    // 자동매매 상태 재확인 (실행 중에 OFF된 경우 대응)
    final isAutoTradingEnabled = await AppDataManager.instance.getAutoTradingStatus();
    print('🔍 자동매매 상태 확인: $isAutoTradingEnabled');
    if (!isAutoTradingEnabled) {
      print('⚠️ 자동매매가 비활성화되어 있어 실행을 건너뜁니다.');
      return;
    }

    _tickInProgress = true;
    final startTime = DateTime.now();
    int errorCount = 0;
    
    try {
      print('🔄 자동매매 사이클 시작: ${startTime.toString()}');
      print('📊 현재 시간: ${DateTime.now().toString()}');
      
      // 네트워크 연결 상태 확인
      final connectivityResult = await _checkNetworkConnectivity();
      print('🌐 네트워크 연결 상태: $connectivityResult');
      if (!connectivityResult) {
        print('⚠️ 네트워크 연결 없음, 자동매매 건너뜀');
        return;
      }
      
      // 0. 실시간 가격 서비스 시작 (첫 사이클에서만)
      print('📡 실시간 가격 서비스 상태 확인: ${AppDataManager.instance.realtimePriceService.isConnected}');
      if (!AppDataManager.instance.realtimePriceService.isConnected) {
        try {
          print('📡 실시간 가격 서비스 시작 시도...');
          await AppDataManager.instance.realtimePriceService.start();
          print('✅ 실시간 가격 서비스 시작 완료');
        } catch (e) {
          print('❌ 실시간 가격 서비스 시작 실패: $e');
          errorCount++;
        }
      }
      
      // 0.5. 현재 투자스타일 설정 확인
      print('🎯 투자스타일 설정 로드 시작...');
      final currentStyle = _styleManager.currentStyle;
      print('📊 현재 투자스타일: ${_getStyleName(currentStyle)}');
      
      final styleParams = await _styleManager.getStyleParameters(currentStyle);
      print('📊 투자스타일 파라미터 로드 완료:');
      print('   - 매수 임계값: ${styleParams['buyThreshold']}');
      print('   - 매도 임계값: ${styleParams['sellThreshold']}');
      print('   - 투자 비율: ${(styleParams['positionSize'] * 100).toStringAsFixed(1)}%');
      print('   - 최대 종목 수: ${styleParams['maxStocks']}개');
      print('   - 부분익절: ${styleParams['partialProfit']}%');
      print('   - 전체익절: ${styleParams['fullProfit']}%');
      print('   - 손절: ${styleParams['stopLoss']}%');
      print('   - 일일 손실 한도: ${styleParams['dailyLossLimit']}%');
      
      // 0.6. 고급 리스크 관리 체크
      print('🛡️ 고급 리스크 관리 체크 시작...');
      final riskManager = AdvancedRiskManager();
      final riskStatus = await riskManager.checkRiskStatus();
      print('📊 리스크 상태:');
      print('   - 거래 가능: ${riskStatus['canTrade']}');
      print('   - 일일 손실: ${riskStatus['dailyLoss']}%');
      print('   - 최대 손실: ${riskStatus['maxDrawdown']}%');
      print('   - 포지션 수: ${riskStatus['positionCount']}/${riskStatus['maxPositions']}');
      
      if (!riskStatus['canTrade']) {
        print('⚠️ 리스크 한도 초과로 거래 중단');
        return;
      }
      
      // 1. 계좌 정보 동기화
      print('💰 계좌 정보 동기화 시작...');
      try {
        final syncAccountUseCase = SyncAccountInfoUseCase();
        await syncAccountUseCase.execute();
        print('✅ 계좌 정보 동기화 완료');
      } catch (e) {
        print('❌ 계좌 정보 동기화 실패: $e');
        errorCount++;
      }
      
      // 2. 관심종목 및 보유종목 동기화
      print('📋 관심종목 및 보유종목 동기화 시작...');
      try {
        final syncUniverseUseCase = SyncUniverseUseCase();
        await syncUniverseUseCase.execute();
        print('✅ 관심종목 및 보유종목 동기화 완료');
      } catch (e) {
        print('❌ 관심종목 및 보유종목 동기화 실패: $e');
        errorCount++;
      }
      
      // 3. 시그널 분석
      print('🎯 시그널 분석 시작...');
      try {
        final analyzeSignalsUseCase = AnalyzeSignalsUseCase();
        final watchlist = await AppDataManager.instance.getWatchlist();
        final signals = await analyzeSignalsUseCase.execute(watchlist);
        print('✅ 시그널 분석 완료:');
        print('   - 총 시그널 수: ${signals.length}개');
        
        if (signals.isNotEmpty) {
          print('📊 시그널 상세:');
          for (int i = 0; i < signals.length && i < 5; i++) {
            final signal = signals[i];
            print('   ${i+1}. ${signal['stockCode']} (${signal['stockName']}) - ${signal['signal']} - ${signal['analysis']?['reason'] ?? 'N/A'}');
          }
        } else {
          print('📊 매매 시그널 없음');
        }
      } catch (e) {
        print('❌ 시그널 분석 실패: $e');
        errorCount++;
      }
      
      // 4. 주문 실행
      print('💰 주문 실행 시작...');
      try {
        final executeOrdersUseCase = ExecuteOrdersUseCase();
        final watchlist = await AppDataManager.instance.getWatchlist();
        final signals = await AnalyzeSignalsUseCase().execute(watchlist);
        await executeOrdersUseCase.execute(signals);
        print('✅ 주문 실행 완료');
      } catch (e) {
        print('❌ 주문 실행 실패: $e');
        errorCount++;
      }
      
      // 5. 주문 상태 추적
      print('📊 주문 상태 추적 시작...');
      try {
        final trackOrderStatusUseCase = TrackOrderStatusUseCase();
        await trackOrderStatusUseCase.execute();
        print('✅ 주문 상태 추적 완료');
      } catch (e) {
        print('❌ 주문 상태 추적 실패: $e');
        errorCount++;
      }
      
      // 6. 알림 처리
      print('🔔 알림 처리 시작...');
      try {
        final persistNotificationUseCase = PersistNotificationUseCase();
        final watchlist = await AppDataManager.instance.getWatchlist();
        final signals = await AnalyzeSignalsUseCase().execute(watchlist);
        await persistNotificationUseCase.execute(signals);
        print('✅ 알림 처리 완료');
      } catch (e) {
        print('❌ 알림 처리 실패: $e');
        errorCount++;
      }
      
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);
      
      print('✅ 자동매매 사이클 완료:');
      print('   - 시작 시간: ${startTime.toString()}');
      print('   - 종료 시간: ${endTime.toString()}');
      print('   - 소요 시간: ${duration.inSeconds}초');
      print('   - 오류 수: $errorCount개');
      
      // 오류가 많으면 알림
      if (errorCount > 2) {
        print('⚠️ 자동매매 사이클에서 $errorCount개의 오류가 발생했습니다.');
        await LocalNotificationManager().showAutoTradingErrorNotification(errorCount);
      }
      
    } catch (e) {
      print('❌ 자동매매 사이클 실행 중 예외 발생: $e');
      await LocalNotificationManager().showAutoTradingErrorNotification(1);
    } finally {
      _tickInProgress = false;
      _lastTickAt = DateTime.now();
    }
  }

  /// 시장 모니터링 실행
  Future<void> _executeMarketMonitoring() async {
    try {
      print('🔄 백그라운드 시장 모니터링 실행...');
      
      // 네트워크 연결 상태 확인
      final connectivityResult = await _checkNetworkConnectivity();
      if (!connectivityResult) {
        print('⚠️ 네트워크 연결 없음, 시장 모니터링 건너뜀');
        return;
      }
      
      await AppDataManager.instance.refreshMarketData();
      
      print('✅ 백그라운드 시장 모니터링 완료');
    } catch (e) {
      print('❌ 백그라운드 시장 모니터링 실패: $e');
    }
  }

  /// 네트워크 연결 상태 확인
  Future<bool> _checkNetworkConnectivity() async {
    try {
      // 간단한 DNS 확인
      final result = await InternetAddress.lookup('openapi.koreainvestment.com');
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (e) {
      print('❌ 네트워크 연결 확인 실패: $e');
      return false;
    }
  }

  /// 서비스 정리
  void dispose() {
    _autoTradingTimer?.cancel();
    _marketMonitoringTimer?.cancel();
  }

  /// 투자스타일 이름 반환
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
}
