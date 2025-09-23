import 'package:flutter/material.dart';
import '../../../core/services/trade_status_tracker.dart';

class TradeStatusActions {
  static Future<void> handle(BuildContext context, TradeStatusTracker tracker, String action) async {
    switch (action) {
      case 'sync':
        await tracker.syncTradeStatusesFromHistory();
        _snack(context, '거래 상태가 동기화되었습니다.', Colors.green);
        break;
      case 'rebuild':
        await tracker.rebuildTradeStatuses();
        _snack(context, '거래 상태가 재구성되었습니다.', Colors.blue);
        break;
      case 'detect':
        await tracker.autoDetectHoldings();
        _snack(context, '보유종목이 자동 감지되었습니다.', Colors.orange);
        break;
      case 'clear':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('거래 상태 초기화'),
            content: const Text('모든 거래 상태를 초기화하시겠습니까?\n이 작업은 되돌릴 수 없습니다.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('취소')),
              TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('초기화')),
            ],
          ),
        );
        if (confirmed == true) {
          await tracker.clearAllTradeStatuses();
          _snack(context, '거래 상태가 초기화되었습니다.', Colors.red);
        }
        break;
    }
  }

  static void _snack(BuildContext context, String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, duration: const Duration(seconds: 2)),
    );
  }
}


