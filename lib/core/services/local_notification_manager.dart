import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/formatters.dart';
import '../trading/investment_style_manager.dart';
import '../data/app_data_manager.dart';
import '../database/repositories/notification_history_repository.dart';
import '../api/kis_unified_api_service.dart';

class LocalNotificationManager {
  static final LocalNotificationManager _instance = LocalNotificationManager._internal();
  factory LocalNotificationManager() => _instance;
  LocalNotificationManager._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  
  // 중복 알림 방지를 위한 최근 알림 기록
  final Set<String> _recentNotifications = <String>{};
  
  // 초기화 상태 플래그
  bool _isInitialized = false;

  /// 초기화
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
      const InitializationSettings settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      // 플러그인 초기화
      await _flutterLocalNotificationsPlugin.initialize(settings);
      
      // 알림 권한 요청
      await _requestPermissions();
      
      _isInitialized = true;
      print('✅ 로컬 알림 매니저 초기화 완료');
    } catch (e) {
      print('❌ 로컬 알림 매니저 초기화 실패: $e');
    }
  }

  /// 알림 권한 요청
  Future<void> _requestPermissions() async {
    try {
      // 현재 권한 상태 확인
      final currentStatus = await Permission.notification.status;
      print('🔔 현재 알림 권한 상태: $currentStatus');
      
      // 권한이 없으면 요청
      if (currentStatus != PermissionStatus.granted) {
        final status = await Permission.notification.request();
        print('🔔 알림 권한 요청 결과: $status');
        
        if (status == PermissionStatus.denied) {
          print('⚠️ 알림 권한이 거부되었습니다. 설정에서 수동으로 활성화해주세요.');
        } else if (status == PermissionStatus.permanentlyDenied) {
          print('⚠️ 알림 권한이 영구적으로 거부되었습니다. 앱 설정에서 활성화해주세요.');
        }
      } else {
        print('✅ 알림 권한이 이미 허용되어 있습니다.');
      }
      
      // 안드로이드 알림 채널 생성 (Android 8.0+)
      await _createNotificationChannels();
      
    } catch (e) {
      print('❌ 알림 권한 요청 실패: $e');
    }
  }
  
  /// 알림 채널 생성 (Android)
  Future<void> _createNotificationChannels() async {
    try {
      // 거래 알림 채널
      const AndroidNotificationChannel tradingChannel = AndroidNotificationChannel(
        'trading_channel',
        '거래 알림',
        description: '매수/매도 거래 알림',
        importance: Importance.high,
        enableLights: true,
        enableVibration: true,
        playSound: true,
        showBadge: true,
      );
      
      // 자동매매 서비스 채널
      const AndroidNotificationChannel autoTradingChannel = AndroidNotificationChannel(
        'auto_trading_channel',
        '자동매매 서비스',
        description: 'AI 자동매매 서비스 상태 알림',
        importance: Importance.high,
        enableLights: true,
        enableVibration: false,
        playSound: false,
        showBadge: true,
      );
      
      // 테스트 알림 채널
      const AndroidNotificationChannel testChannel = AndroidNotificationChannel(
        'test_channel',
        '테스트 알림',
        description: '테스트용 알림',
        importance: Importance.defaultImportance,
        enableLights: true,
        enableVibration: true,
        playSound: true,
        showBadge: false,
      );
      
      // 채널 등록
      final plugin = _flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (plugin != null) {
        await plugin.createNotificationChannel(tradingChannel);
        await plugin.createNotificationChannel(autoTradingChannel);
        await plugin.createNotificationChannel(testChannel);
        print('✅ Android 알림 채널 생성 완료');
      }
      
    } catch (e) {
      print('❌ 알림 채널 생성 실패: $e');
    }
  }

  // 자동매매 알림 중복 방지를 위한 플래그
  bool _autoTradingNotificationShown = false;

  /// 자동매매 서비스 알림 표시 (한 번만)
  Future<void> showAutoTradingNotification() async {
    // 이미 알림이 표시되었는지 확인
    final prefs = await SharedPreferences.getInstance();
    final notificationShown = prefs.getBool('auto_trading_notification_shown') ?? false;
    
    if (notificationShown) {
      print('⚠️ 자동매매 서비스 알림이 이미 표시되었습니다. 중복 표시를 건너뜁니다.');
      return;
    }
    
    await showNotification(
      title: '🤖 AI 자동매매 서비스',
      body: 'AI 자동매매 하기위해 출근 했습니다.',
    );
    
    // 알림 표시 완료 표시
    await prefs.setBool('auto_trading_notification_shown', true);
    print('✅ 자동매매 서비스 알림 표시 완료 (한 번만)');
  }

  /// 자동매매 오류 알림 표시
  Future<void> showAutoTradingErrorNotification(int errorCount) async {
    await showNotification(
      title: '⚠️ 자동매매 오류 발생',
      body: '자동매매 실행 중 $errorCount개의 오류가 발생했습니다.\n앱을 확인해주세요.',
    );
  }

  /// 자동매매 서비스 알림 제거
  Future<void> hideAutoTradingNotification() async {
    if (!_isInitialized) await initialize();

    try {
      await _flutterLocalNotificationsPlugin.cancel(888);
      _autoTradingNotificationShown = false; // 플래그 리셋
      
      // SharedPreferences에서도 알림 표시 플래그 리셋
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auto_trading_notification_shown', false);
      
      print('✅ 자동매매 서비스 알림 제거됨 (플래그 리셋)');
    } catch (e) {
      print('❌ 자동매매 서비스 알림 제거 실패: $e');
    }
  }

  /// 일반 알림 표시
  Future<void> showNotification({
    required String title,
    required String body,
  }) async {
    if (!_isInitialized) await initialize();

    try {
      // 알림 권한 재확인
      final permissionStatus = await Permission.notification.status;
      if (permissionStatus != PermissionStatus.granted) {
        print('⚠️ 알림 권한이 없어 알림을 표시할 수 없습니다: $permissionStatus');
        return;
      }
      
      print('🔔 알림 표시 시도: $title - $body');
      
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'trading_channel',
        '거래 알림',
        channelDescription: '매수/매도 거래 알림',
        importance: Importance.high,
        priority: Priority.high,
        enableLights: true,
        enableVibration: true,
        playSound: true,
        showWhen: true,
        when: null,
        usesChronometer: false,
        chronometerCountDown: false,
        showProgress: false,
        maxProgress: 0,
        progress: 0,
        indeterminate: false,
        channelShowBadge: true,
        onlyAlertOnce: false,
        autoCancel: true,
        ongoing: false,
        color: null,
        colorized: false,
        category: AndroidNotificationCategory.message,
        fullScreenIntent: false,
        shortcutId: null,
        additionalFlags: null,
        subText: null,
        styleInformation: null,
        groupKey: null,
        setAsGroupSummary: false,
        groupAlertBehavior: GroupAlertBehavior.all,
        timeoutAfter: null,
        visibility: NotificationVisibility.public,
        ticker: '거래 알림',
        actions: null,
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      print('🔔 알림 ID: $notificationId');
      
      await _flutterLocalNotificationsPlugin.show(
        notificationId,
        title,
        body,
        details,
      );

      print('✅ 거래 알림 표시됨: $title - $body');
      
      // 알림 히스토리에 저장 (동기화)
      await _saveNotificationToHistory(title, body, notificationId);
      
      // 알림이 실제로 표시되었는지 확인
      final pendingNotifications = await _flutterLocalNotificationsPlugin.pendingNotificationRequests();
      print('📋 대기 중인 알림 수: ${pendingNotifications.length}');
      
      final activeNotifications = await _flutterLocalNotificationsPlugin.getActiveNotifications();
      print('📋 활성 알림 수: ${activeNotifications.length}');
      
    } catch (e) {
      print('❌ 거래 알림 표시 실패: $e');
      print('❌ 오류 상세: ${e.toString()}');
      print('❌ 오류 타입: ${e.runtimeType}');
    }
  }

  /// 테스트 알림 표시
  Future<void> showTestNotification({
    required String title,
    required String body,
  }) async {
    if (!_isInitialized) await initialize();

    try {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'test_channel',
        '테스트 알림',
        channelDescription: '테스트용 알림',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _flutterLocalNotificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000, // 고유 ID
        title,
        body,
        details,
      );

      print('✅ 테스트 알림 표시됨: $title - $body');
    } catch (e) {
      print('❌ 테스트 알림 표시 실패: $e');
    }
  }

  /// 알림 히스토리에 저장 (푸시알림과 동기화)
  Future<void> _saveNotificationToHistory(String title, String body, int notificationId) async {
    try {
      final stockCode = _extractStockCodeFromBody(body);
      final stockName = _extractStockNameFromBody(body);
      
      await NotificationHistoryRepository().addNotification(
        type: title,
        stockCode: stockCode,
        stockName: stockName,
        message: body,
        market: _inferMarketFromCode(stockCode), // 시장 정보 추가
      );
      print('💾 알림 히스토리 저장 완료: $title - $body (시장: ${_inferMarketFromCode(stockCode)})');
    } catch (e) {
      print('❌ 알림 히스토리 저장 실패: $e');
    }
  }
  
  /// 종목코드로 시장 추정
  String _inferMarketFromCode(String stockCode) {
    final upper = stockCode.toUpperCase();
    if (RegExp(r'^[A-Z]{1,6}$').hasMatch(upper)) {
      return 'NASDAQ';
    }
    if (upper.startsWith('0')) {
      return 'KOSPI';
    }
    return 'KOSDAQ';
  }

  /// 알림 본문에서 종목코드 추출
  String _extractStockCodeFromBody(String body) {
    try {
      // 패턴: "종목명(종목코드)" 형태에서 추출
      final regex = RegExp(r'\(([A-Z0-9]+)\)');
      final match = regex.firstMatch(body);
      return match?.group(1) ?? 'UNKNOWN';
    } catch (e) {
      return 'UNKNOWN';
    }
  }

  /// 알림 본문에서 종목명 추출
  String _extractStockNameFromBody(String body) {
    try {
      // 패턴: "종목명(종목코드)" 형태에서 추출
      final regex = RegExp(r'^([^(]+)\([A-Z0-9]+\)');
      final match = regex.firstMatch(body);
      return match?.group(1)?.trim() ?? 'Unknown';
    } catch (e) {
      return 'Unknown';
    }
  }

  /// 알림 설정 확인
  Future<bool> _isNotificationEnabled(String type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('${type}_enabled') ?? true;
    } catch (e) {
      print('❌ 알림 설정 확인 실패: $e');
      return true; // 기본값은 활성화
    }
  }

  /// 매수 시그널 알림 표시 (설정 확인)
  Future<void> showBuySignalNotification({
    required String stockCode,
    required String stockName,
    required String reason,
    required double price,
  }) async {
    if (!await _isNotificationEnabled('buy_signal')) {
      print('🔕 매수 시그널 알림이 비활성화되어 있습니다.');
      return;
    }

    // 사용자 투자스타일별 임계값 가져오기
    String thresholdInfo = '';
    try {
      final styleManager = InvestmentStyleManager();
      final currentStyle = await styleManager.getCurrentStyle();
      final styleParams = await styleManager.getStyleParameters(currentStyle);
      final buyThreshold = (styleParams['buyThreshold'] as num?)?.toDouble();
      if (buyThreshold == null) {
        print('⚠️ 매수 임계값이 설정되지 않았습니다.');
        return;
      }
      thresholdInfo = ' (임계값: ${buyThreshold.toStringAsFixed(2)})';
      print('📊 매수 알림 임계값: $buyThreshold');
    } catch (e) {
      print('⚠️ 사용자 매수 임계값 조회 실패: $e');
    }

    // 가격 보강: 전달된 price가 0이면 캐시/DB/API 순으로 조회
    final double displayPrice = price > 0 ? price : await _resolvePrice(stockCode);
    final title = '📈 매수 시그널: $stockName';
    final body = '$stockCode - ${_formatPrice(stockCode, displayPrice)}$thresholdInfo\n$reason';
    
    await showNotification(title: title, body: body);
  }

  /// 매도 시그널 알림 표시 (설정 확인)
  Future<void> showSellSignalNotification({
    required String stockCode,
    required String stockName,
    required String reason,
    required double price,
  }) async {
    if (!await _isNotificationEnabled('sell_signal')) {
      print('🔕 매도 시그널 알림이 비활성화되어 있습니다.');
      return;
    }

    // 사용자 투자스타일별 임계값 가져오기
    String thresholdInfo = '';
    try {
      final styleManager = InvestmentStyleManager();
      final currentStyle = await styleManager.getCurrentStyle();
      final styleParams = await styleManager.getStyleParameters(currentStyle);
      final sellThreshold = (styleParams['sellThreshold'] as num?)?.toDouble();
      if (sellThreshold == null) {
        print('⚠️ 매도 임계값이 설정되지 않았습니다.');
        return;
      }
      thresholdInfo = ' (임계값: ${sellThreshold.toStringAsFixed(2)})';
      print('📊 매도 알림 임계값: $sellThreshold');
    } catch (e) {
      print('⚠️ 사용자 매도 임계값 조회 실패: $e');
    }

    final double displayPrice = price > 0 ? price : await _resolvePrice(stockCode);
    final title = '📉 매도 시그널: $stockName';
    final body = '$stockCode - ${_formatPrice(stockCode, displayPrice)}$thresholdInfo\n$reason';
    
    await showNotification(title: title, body: body);
  }

  /// 매수 실패 알림 표시 (설정 확인)
  Future<void> showBuyFailureNotification({
    required String stockCode,
    required String stockName,
    required String reason,
    required double price,
  }) async {
    if (!await _isNotificationEnabled('buy_failure')) {
      print('🔕 매수 실패 알림이 비활성화되어 있습니다.');
      return;
    }

    final title = '❌ 매수 실패: $stockName';
    final body = '$stockCode - ${_formatPrice(stockCode, price)}\n실패 사유: $reason';
    
    await showNotification(title: title, body: body);
  }

  /// 매도 실패 알림 표시 (설정 확인)
  Future<void> showSellFailureNotification({
    required String stockCode,
    required String stockName,
    required String reason,
    required double price,
  }) async {
    if (!await _isNotificationEnabled('sell_failure')) {
      print('🔕 매도 실패 알림이 비활성화되어 있습니다.');
      return;
    }

    final title = '❌ 매도 실패: $stockName';
    final body = '$stockCode - ${_formatPrice(stockCode, price)}\n실패 사유: $reason';
    
    await showNotification(title: title, body: body);
  }

  /// 거래 실행 알림 표시 (설정 확인) - 매도 이유 포함
  Future<void> showTradeExecutionNotification({
    required String stockCode,
    required String stockName,
    required String orderType,
    required double price,
    required int quantity,
    String? reason, // 매도 이유 추가
  }) async {
    if (!await _isNotificationEnabled('trade_execution')) {
      print('🔕 거래 실행 알림이 비활성화되어 있습니다.');
      return;
    }

    // 중복 알림 방지: 최근 30초 내 동일한 종목의 동일한 주문 타입 알림 확인
    final now = DateTime.now();
    final recentKey = '${stockCode}_${orderType}_${now.millisecondsSinceEpoch ~/ 30000}'; // 30초 단위로 그룹화
    
    if (_recentNotifications.contains(recentKey)) {
      print('⚠️ 중복 알림 방지: $stockCode $orderType (최근 30초 내)');
      return;
    }
    
    // 최근 알림 기록에 추가 (최대 10개 유지)
    _recentNotifications.add(recentKey);
    if (_recentNotifications.length > 10) {
      _recentNotifications.remove(_recentNotifications.first);
    }

    String title = '✅ $orderType 완료: $stockName';
    String body = '$stockCode - ${_formatPrice(stockCode, price)} × ${quantity}주';
    
    // 매도인 경우 이유와 기준 퍼센트 추가
    if (orderType == '매도' && reason != null && reason.isNotEmpty) {
      String reasonText = '';
      
      // 매도 이유 분석 및 기준 퍼센트 조회
      if (reason.contains('부분익절') || reason.contains('전체익절') || reason.contains('손절')) {
        try {
          // 현재 투자 스타일 설정에서 기준 퍼센트 조회
          final styleManager = InvestmentStyleManager();
          final currentStyle = await styleManager.getCurrentStyle();
          final styleParams = await styleManager.getStyleParameters(currentStyle);
          
          if (reason.contains('손절')) {
            final stopLoss = (styleParams['stopLoss'] as num?)?.toDouble() ?? 0.0;
            reasonText = ' (손절 실행: ${stopLoss.abs().toStringAsFixed(1)}% 기준)';
          } else if (reason.contains('부분익절')) {
            final partialProfit = (styleParams['partialProfit'] as num?)?.toDouble() ?? 0.0;
            reasonText = ' (부분익절 실행: ${partialProfit.toStringAsFixed(1)}% 기준)';
          } else if (reason.contains('전체익절')) {
            final fullProfit = (styleParams['fullProfit'] as num?)?.toDouble() ?? 0.0;
            reasonText = ' (전체익절 실행: ${fullProfit.toStringAsFixed(1)}% 기준)';
          }
        } catch (e) {
          print('⚠️ 매도 기준 퍼센트 조회 실패: $e');
          // 기본 텍스트 사용
          if (reason.contains('손절')) {
            reasonText = ' (손절 실행)';
          } else if (reason.contains('부분익절')) {
            reasonText = ' (부분익절 실행)';
          } else if (reason.contains('전체익절')) {
            reasonText = ' (전체익절 실행)';
          }
        }
      } else if (reason.contains('기술적') || reason.contains('종합점수')) {
        reasonText = ' (기술적 매도)';
      } else {
        reasonText = ' ($reason)';
      }
      
      body += reasonText;
    }
    
    await showNotification(title: title, body: body);
  }

  /// 주문 대기 알림 표시 (설정 확인)
  Future<void> showPendingNotification({
    required String stockCode,
    required String stockName,
    required String orderType,
    required double price,
    required int quantity,
  }) async {
    if (!await _isNotificationEnabled('pending')) {
      print('🔕 주문 대기 알림이 비활성화되어 있습니다.');
      return;
    }
    final title = '⏳ 주문 접수 완료: $stockName';
    final body = '$stockCode - ${_formatPrice(stockCode, price)} × ${quantity}주\n$orderType 주문 접수, 체결 대기 중';
    await showNotification(title: title, body: body);
  }

  /// 기회 알림 표시 (설정 확인)
  Future<void> showOpportunityNotification({
    required String stockCode,
    required String stockName,
    required String summary,
    required double price,
  }) async {
    if (!await _isNotificationEnabled('opportunity')) {
      print('🔕 기회 알림이 비활성화되어 있습니다.');
      return;
    }
    final title = '💡 투자 기회 감지: $stockName';
    final body = '$stockCode - ${_formatPrice(stockCode, price)}\n$summary';
    await showNotification(title: title, body: body);
  }

  // 통화/소수점 포맷: 나스닥 티커는 달러 2자리, 그 외는 원화 포맷
  String _formatPrice(String stockCode, double price) {
    final isNasdaq = RegExp(r'^[A-Z]{1,5}$').hasMatch(stockCode);
    if (isNasdaq) {
      return '\$${price.toStringAsFixed(2)}';
    }
    return '${Formatters.formatPrice(price)}';
  }

  /// 가격 보강: 캐시 → DB → API 순서, 실패 시 0.0
  Future<double> _resolvePrice(String stockCode) async {
    try {
      final cached = AppDataManager.instance.getCachedStockData(stockCode);
      final nowP = (cached['currentPrice'] as num?)?.toDouble() ?? 0.0;
      final prev = (cached['prevClose'] as num?)?.toDouble() ?? 0.0;
      if (nowP > 0) return nowP;
      if (prev > 0) return prev;

      final db = await AppDataManager.instance.getRealtimeDataFromDatabase(stockCode);
      final dbNow = (db?['currentPrice'] as num?)?.toDouble() ?? 0.0;
      final dbPrev = (db?['prevClose'] as num?)?.toDouble() ?? 0.0;
      if (dbNow > 0) return dbNow;
      if (dbPrev > 0) return dbPrev;

      try {
        // ✅ API 직접 호출 비활성화 - Firestore 구독 사용
        print('🔍 [current 보호] LocalNotificationManager에서 API 직접 호출 비활성화');
        // final kis = KisUnifiedApiService();
        // final Map<String, dynamic>? api = await kis.getStockPrice(stockCode);
        final Map<String, dynamic>? api = null;
        if (api != null) {
          final apiNow = (api['currentPrice'] as num?)?.toDouble() ?? 0.0;
          final apiPrev = (api['prevClose'] as num?)?.toDouble() ?? 0.0;
          if (apiNow > 0) return apiNow;
          if (apiPrev > 0) return apiPrev;
        }
      } catch (_) {}
    } catch (_) {}
    return 0.0;
  }
}
