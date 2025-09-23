// import '../../database/repositories/notification_history_repository.dart'; // AutoTradingCycle에서 처리하므로 주석 처리
// import '../../services/local_notification_manager.dart'; // AutoTradingCycle에서 처리하므로 주석 처리
// import '../investment_style_manager.dart'; // AutoTradingCycle에서 처리하므로 주석 처리

class PersistNotificationUseCase {
  // final NotificationHistoryRepository _repo = NotificationHistoryRepository(); // AutoTradingCycle에서 처리하므로 주석 처리
  // final LocalNotificationManager _notifier = LocalNotificationManager(); // AutoTradingCycle에서 처리하므로 주석 처리
  // final InvestmentStyleManager _styleManager = InvestmentStyleManager(); // AutoTradingCycle에서 처리하므로 주석 처리

  Future<void> execute(List<Map<String, dynamic>> signals) async {
    if (signals.isEmpty) {
      print('📱 알림할 시그널이 없습니다.');
      return;
    }

    print('📱 알림 처리 시작 - ${signals.length}개 시그널');
    // await _repo.createTable(); // AutoTradingCycle에서 처리하므로 주석 처리
    
    int notificationCount = 0;
    int skipCount = 0;

    // 알림 처리는 AutoTradingCycle에서 처리하므로 여기서는 건너뜀
    print('⚠️ 알림 처리는 AutoTradingCycle에서 처리됨: ${signals.length}개 시그널');
    
    print('📱 알림 처리 완료 - 발송: $notificationCount개, 건너뜀: $skipCount개');
  }

  // 푸시 알림 발송은 AutoTradingCycle에서 처리하므로 주석 처리
  // Future<void> _sendPushNotification(
  //   String code, 
  //   String name, 
  //   String signal, 
  //   double price, 
  //   double? rsi, 
  //   double? confidence
  // ) async {
  //   try {
  //     final styleName = _getStyleName(_styleManager.currentStyle);
  //     final rsiStr = rsi != null ? ' (RSI: ${rsi.toStringAsFixed(1)})' : '';
  //     final confidenceStr = confidence != null ? ' [${(confidence * 100).toStringAsFixed(0)}%]' : '';
  //     
  //     if (signal == '매수') {
  //       await _notifier.showBuySignalNotification(
  //         stockCode: code, 
  //         stockName: name, 
  //         reason: 'Auto_$styleName', 
  //         price: price
  //       );
  //     } else if (signal == '매도') {
  //       await _notifier.showSellSignalNotification(
  //         stockCode: code, 
  //         stockName: name, 
  //         reason: 'Auto_$styleName', 
  //         price: price
  //       );
  //     } else {
  //       final title = '$signal 시그널 [$styleName]';
  //       final body = '$name($code) $price$rsiStr$confidenceStr';
  //       await _notifier.showNotification(title: title, body: body);
  //     }
  //   } catch (e) {
  //     print('❌ 푸시 알림 발송 실패: $e');
  //   }
  // }

  // 투자 스타일 이름 변환은 AutoTradingCycle에서 처리하므로 주석 처리
  // String _getStyleName(dynamic style) {
  //   switch (style.toString()) {
  //     case 'InvestmentStyle.conservative':
  //       return '안정적';
  //     case 'InvestmentStyle.moderate':
  //       return '일반적';
  //     case 'InvestmentStyle.aggressive':
  //       return '공격적';
  //     default:
  //       return '일반적';
  //   }
  // }
}


