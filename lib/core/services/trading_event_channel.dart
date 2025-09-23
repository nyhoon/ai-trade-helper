import 'dart:async';
import 'package:flutter/services.dart';
// import '../trading/auto_trading_service.dart';
import '../trading/auto_trading_cycle.dart';
import '../data/app_data_manager.dart';

class TradingEventChannel {
  static const EventChannel _channel = EventChannel('auto_trading_events');
  static StreamSubscription? _subscription;
  static bool _isListening = false;

  /// 자동매매 이벤트 리스너 시작
  static void startListening() {
    if (_isListening) return;
    
    try {
      print('🎧 자동매매 이벤트 리스너 시작...');
      
      _subscription = _channel.receiveBroadcastStream().listen(
        (event) {
          _handleTradingEvent(event);
        },
        onError: (error) {
          print('❌ 자동매매 이벤트 수신 오류: $error');
        },
        onDone: () {
          print('✅ 자동매매 이벤트 리스너 종료');
          _isListening = false;
        },
      );
      
      _isListening = true;
      print('✅ 자동매매 이벤트 리스너 시작됨');
    } catch (e) {
      print('❌ 자동매매 이벤트 리스너 시작 실패: $e');
    }
  }

  /// 자동매매 이벤트 리스너 중지
  static void stopListening() {
    try {
      _subscription?.cancel();
      _subscription = null;
      _isListening = false;
      print('🛑 자동매매 이벤트 리스너 중지됨');
    } catch (e) {
      print('❌ 자동매매 이벤트 리스너 중지 실패: $e');
    }
  }

  /// 자동매매 이벤트 처리
  static Future<void> _handleTradingEvent(dynamic event) async {
    try {
      print('📨 자동매매 이벤트 수신: $event');
      
      if (event is Map) {
        final action = event['action'] as String?;
        final checkCount = event['checkCount'] as int?;
        
        switch (action) {
          case 'execute_trading':
            await _executeTradingLogic(checkCount);
            break;
          case 'update_status':
            await _updateTradingStatus(event);
            break;
          default:
            print('⚠️ 알 수 없는 자동매매 이벤트: $action');
        }
      }
    } catch (e) {
      print('❌ 자동매매 이벤트 처리 실패: $e');
    }
  }

  /// 실제 자동매매 로직 실행
  static Future<void> _executeTradingLogic(int? checkCount) async {
    try {
      print('🤖 자동매매 실행 시작 (체크 횟수: $checkCount)');
      
      // AppDataManager 초기화
      await AppDataManager.instance.initialize();
      
      // 자동매매 활성화 상태 확인
      final isAutoTradingEnabled = await AppDataManager.instance.getAutoTradingStatus();
      if (!isAutoTradingEnabled) {
        print('⚠️ 자동매매가 비활성화되어 있습니다.');
        return;
      }
      
      // AutoTradingCycle을 단일 실행원으로 사용
      final cycle = AutoTradingCycle();
      if (!cycle.isRunning) {
        await cycle.startCycle();
      }
      
      print('✅ 자동매매 실행 완료 (체크 횟수: $checkCount)');
    } catch (e) {
      print('❌ 자동매매 실행 실패: $e');
    }
  }

  /// 자동매매 상태 업데이트
  static Future<void> _updateTradingStatus(Map event) async {
    try {
      final status = event['status'] as String?;
      final message = event['message'] as String?;
      
      print('📊 자동매매 상태 업데이트: $status - $message');
      
      // 여기서 UI 업데이트나 알림을 처리할 수 있습니다
      // 예: LocalNotificationManager().showNotification(...)
    } catch (e) {
      print('❌ 자동매매 상태 업데이트 실패: $e');
    }
  }

  /// 리스너 상태 확인
  static bool get isListening => _isListening;
}
