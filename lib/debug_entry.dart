import 'package:flutter/material.dart';
import 'core/data/app_data_manager.dart';
// import 'core/trading/ai_auto_trading_service.dart';
import 'core/services/local_notification_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 초기화
  await AppDataManager.instance.initialize();
  await LocalNotificationManager().initialize();

  // 실거래 기준: ApiConfig가 실거래로 설정되어 있어야 함
  // AutoTradingCycle 기반으로 이동 (디버그 진입점 미사용)

  const symbol = '073240'; // 금호타이어
  const qty = 1;

  try {
    final res = await service.debugPlaceBuy(symbol, quantity: qty);
    final ok = res['success'] == true;
    final msg = res['message']?.toString() ?? (ok ? '주문 성공' : '주문 실패');
    // 콘솔 로그 + 알림
    // ignore: avoid_print
    print('DEBUG_ORDER result=$res');
    await LocalNotificationManager().showNotification(
      title: ok ? '주문 성공' : '주문 실패',
      body: '$symbol $qty주 - $msg',
    );
  } catch (e) {
    // ignore: avoid_print
    print('DEBUG_ORDER error=$e');
    await LocalNotificationManager().showNotification(
      title: '주문 실패',
      body: '$symbol $qty주 - $e',
    );
  }

  runApp(const _DebugApp());
}

class _DebugApp extends StatelessWidget {
  const _DebugApp();
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Debug Order Runner')),
        body: const Center(
          child: Text('주문 테스트가 실행되었습니다. 알림/내역을 확인하세요.'),
        ),
      ),
    );
  }
}


