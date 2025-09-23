import 'dart:async';
import 'dart:ui';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../trading/investment_style_manager.dart';

/// 신호 알림 시스템
/// 매매 신호를 감지하고 사용자에게 알림을 보내는 시스템
class SignalNotificationSystem {
  static final SignalNotificationSystem _instance = SignalNotificationSystem._internal();
  factory SignalNotificationSystem() => _instance;
  SignalNotificationSystem._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  final StreamController<Map<String, dynamic>> _signalController = StreamController<Map<String, dynamic>>.broadcast();
  
  bool _isInitialized = false;
  bool _isEnabled = true;
  
  /// 알림 시스템 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Android 설정
      const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      
      // iOS 설정
      const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      
      // 초기화 설정
      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      
      // 알림 플러그인 초기화
      await _notifications.initialize(initSettings);
      
      _isInitialized = true;
      print('✅ 신호 알림 시스템 초기화 완료');
      
    } catch (e) {
      print('⚠️ 신호 알림 시스템 초기화 실패: $e');
    }
  }

  /// 알림 시스템 활성화/비활성화
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    print('📱 신호 알림 시스템 ${enabled ? "활성화" : "비활성화"}');
  }

  /// 알림 시스템 상태 확인
  bool get isEnabled => _isEnabled;
  bool get isInitialized => _isInitialized;

  /// 매매 신호 알림 전송
  Future<void> sendSignalNotification({
    required String stockCode,
    required String stockName,
    required double currentPrice,
    required String executionDecision,
    required String signalStrength,
    required double comprehensiveScore,
    required String currentTime,
    int priority = 1,
  }) async {
    print('📱 매매 신호 알림 전송 시작...');
    print('📊 알림 정보:');
    print('   - 종목코드: $stockCode');
    print('   - 종목명: $stockName');
    print('   - 현재가: $currentPrice');
    print('   - 매매결정: $executionDecision');
    print('   - 신호강도: $signalStrength');
    print('   - 종합점수: $comprehensiveScore');
    print('   - 시간: $currentTime');
    print('   - 우선순위: $priority');
    
    if (!_isEnabled || !_isInitialized) {
      print('⚠️ 알림 시스템이 비활성화되어 있습니다.');
      print('   - 시스템 활성화: $_isEnabled');
      print('   - 시스템 초기화: $_isInitialized');
      return;
    }

    try {
      // 알림 ID 생성
      final int notificationId = DateTime.now().millisecondsSinceEpoch % 100000;
      print('📱 알림 ID 생성: $notificationId');
      
      // 알림 제목 생성
      final String title = _generateNotificationTitle(executionDecision, signalStrength);
      print('📱 알림 제목: $title');
      
      // 알림 내용 생성
      print('📱 알림 내용 생성 중...');
      final String body = await _generateNotificationBody(
        stockCode: stockCode,
        stockName: stockName,
        currentPrice: currentPrice,
        executionDecision: executionDecision,
        signalStrength: signalStrength,
        comprehensiveScore: comprehensiveScore,
        currentTime: currentTime,
      );
      print('📱 알림 내용: $body');
      
      // Android 알림 설정
      print('📱 Android 알림 설정 중...');
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'trading_signals',
        '매매 신호',
        channelDescription: '매매 신호 알림',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        enableLights: true,
        color: const Color(0xFF2196F3), // 파란색
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        styleInformation: BigTextStyleInformation(''),
      );
      
      // iOS 알림 설정
      print('📱 iOS 알림 설정 중...');
      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
      );
      
      // 알림 상세 설정
      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      
      // 알림 전송
      print('📱 알림 전송 중...');
      await _notifications.show(notificationId, title, body, details);
      
      // 신호 데이터를 스트림으로 전송
      print('📱 신호 데이터 스트림 전송 중...');
      final Map<String, dynamic> signalData = {
        'notificationId': notificationId,
        'stockCode': stockCode,
        'stockName': stockName,
        'currentPrice': currentPrice,
        'executionDecision': executionDecision,
        'signalStrength': signalStrength,
        'comprehensiveScore': comprehensiveScore,
        'currentTime': currentTime,
        'priority': priority,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      _signalController.add(signalData);
      
      print('✅ 매매 신호 알림 전송 완료');
      print('📱 알림 ID: $notificationId');
      print('📱 제목: $title');
      print('📱 내용: $body');
      
    } catch (e) {
      print('⚠️ 매매 신호 알림 전송 실패: $e');
      print('📊 오류 상세:');
      print('   - 오류 타입: ${e.runtimeType}');
      print('   - 오류 메시지: $e');
    }
  }

  /// 긴급 매매 신호 알림 전송
  Future<void> sendUrgentSignalNotification({
    required String stockCode,
    required String stockName,
    required double currentPrice,
    required String executionDecision,
    required String signalStrength,
    required double comprehensiveScore,
    required String currentTime,
  }) async {
    await sendSignalNotification(
      stockCode: stockCode,
      stockName: stockName,
      currentPrice: currentPrice,
      executionDecision: executionDecision,
      signalStrength: signalStrength,
      comprehensiveScore: comprehensiveScore,
      currentTime: currentTime,
      priority: 1, // 최고 우선순위
    );
  }

  /// 알림 제목 생성
  String _generateNotificationTitle(String executionDecision, String signalStrength) {
    final String action = executionDecision.contains('매수') ? '매수' : 
                         executionDecision.contains('매도') ? '매도' : '관망';
    
    final String urgency = signalStrength.contains('강한') ? '🚨 긴급' : 
                          signalStrength.contains('보통') ? '📊 일반' : '📈 참고';
    
    return '$urgency $action 신호';
  }

  /// 알림 내용 생성
  Future<String> _generateNotificationBody({
    required String stockCode,
    required String stockName,
    required double currentPrice,
    required String executionDecision,
    required String signalStrength,
    required double comprehensiveScore,
    required String currentTime,
  }) async {
    final String action = executionDecision.contains('매수') ? '매수' : 
                         executionDecision.contains('매도') ? '매도' : '관망';
    
    // 사용자 투자스타일별 임계값 가져오기
    String thresholdInfo = '';
    try {
      final styleManager = InvestmentStyleManager();
      final currentStyle = await styleManager.getCurrentStyle();
      final styleParams = await styleManager.getStyleParameters(currentStyle);
      
      if (action == '매수') {
        final buyThreshold = (styleParams['buyThreshold'] as num?)?.toDouble();
        if (buyThreshold == null) {
          print('⚠️ 매수 임계값이 설정되지 않았습니다.');
          return '';
        }
        thresholdInfo = ' (임계값: ${buyThreshold.toStringAsFixed(1)})';
      } else if (action == '매도') {
        final sellThreshold = (styleParams['sellThreshold'] as num?)?.toDouble();
        if (sellThreshold == null) {
          print('⚠️ 매도 임계값이 설정되지 않았습니다.');
          return '';
        }
        thresholdInfo = ' (임계값: ${sellThreshold.toStringAsFixed(1)})';
      }
    } catch (e) {
      print('⚠️ 사용자 임계값 조회 실패: $e');
    }
    
    return '''
$stockName ($stockCode)
현재가: ${currentPrice.toStringAsFixed(0)}원
종합점수: ${comprehensiveScore.toStringAsFixed(3)}$thresholdInfo
매매결정: $executionDecision
신호강도: $signalStrength
시간: $currentTime

$action 신호가 감지되었습니다.
앱을 열어 상세 분석을 확인하세요.
    '''.trim();
  }

  /// 신호 스트림 구독
  Stream<Map<String, dynamic>> get signalStream => _signalController.stream;

  /// 특정 종목의 신호만 필터링
  Stream<Map<String, dynamic>> getSignalsForStock(String stockCode) {
    return _signalController.stream.where((signal) => signal['stockCode'] == stockCode);
  }

  /// 매수 신호만 필터링
  Stream<Map<String, dynamic>> get buySignals {
    return _signalController.stream.where((signal) => 
      signal['executionDecision'].toString().contains('매수'));
  }

  /// 매도 신호만 필터링
  Stream<Map<String, dynamic>> get sellSignals {
    return _signalController.stream.where((signal) => 
      signal['executionDecision'].toString().contains('매도'));
  }

  /// 긴급 신호만 필터링
  Stream<Map<String, dynamic>> get urgentSignals {
    return _signalController.stream.where((signal) => 
      signal['signalStrength'].toString().contains('강한'));
  }

  /// 알림 권한 요청
  Future<bool> requestPermissions() async {
    try {
      final bool? result = await _notifications.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      
      return result ?? false;
    } catch (e) {
      print('⚠️ 알림 권한 요청 실패: $e');
      return false;
    }
  }

  /// 알림 권한 상태 확인
  Future<bool> checkPermissions() async {
    try {
      final bool? result = await _notifications.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      
      return result ?? false;
    } catch (e) {
      print('⚠️ 알림 권한 확인 실패: $e');
      return false;
    }
  }

  /// 모든 알림 삭제
  Future<void> cancelAllNotifications() async {
    try {
      await _notifications.cancelAll();
      print('✅ 모든 알림 삭제 완료');
    } catch (e) {
      print('⚠️ 알림 삭제 실패: $e');
    }
  }

  /// 특정 알림 삭제
  Future<void> cancelNotification(int notificationId) async {
    try {
      await _notifications.cancel(notificationId);
      print('✅ 알림 삭제 완료 (ID: $notificationId)');
    } catch (e) {
      print('⚠️ 알림 삭제 실패: $e');
    }
  }

  /// 알림 채널 생성 (Android)
  Future<void> createNotificationChannel() async {
    try {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'trading_signals',
        '매매 신호',
        description: '매매 신호 알림 채널',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        enableLights: true,
      );
      
      await _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
      
      print('✅ 알림 채널 생성 완료');
    } catch (e) {
      print('⚠️ 알림 채널 생성 실패: $e');
    }
  }

  /// 알림 설정 가져오기
  Map<String, dynamic> getNotificationSettings() {
    return {
      'isEnabled': _isEnabled,
      'isInitialized': _isInitialized,
      'hasPermissions': checkPermissions(),
    };
  }

  /// 알림 통계 가져오기
  Map<String, dynamic> getNotificationStats() {
    return {
      'totalSignals': 0, // TODO: 실제 통계 구현
      'buySignals': 0,
      'sellSignals': 0,
      'urgentSignals': 0,
      'lastSignalTime': null,
    };
  }

  /// 리소스 해제
  void dispose() {
    _signalController.close();
    print('✅ 신호 알림 시스템 리소스 해제 완료');
  }
}
