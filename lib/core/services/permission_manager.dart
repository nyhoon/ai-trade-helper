import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';

class PermissionManager {
  static final PermissionManager _instance = PermissionManager._internal();
  factory PermissionManager() => _instance;
  PermissionManager._internal();

  static const MethodChannel _channel = MethodChannel('auto_trading_service');
  
  /// 백그라운드 서비스 실행에 필요한 모든 권한 요청
  Future<bool> requestBackgroundPermissions() async {
    try {
      print('🔐 백그라운드 권한 요청 시작');
      
      // 알림 권한 요청 (가장 중요)
      final notificationStatus = await Permission.notification.request();
      if (notificationStatus.isDenied) {
        print('⚠️ 알림 권한이 거부되었습니다. 자동매매 알림이 작동하지 않을 수 있습니다.');
        // 알림 권한이 없어도 자동매매는 작동하지만 알림은 안됨
      }
      
      // 배터리 최적화 무시 권한 요청 (매우 중요)
      final batteryOptimizationStatus = await Permission.ignoreBatteryOptimizations.request();
      if (batteryOptimizationStatus.isDenied) {
        print('⚠️ 배터리 최적화 무시 권한이 거부되었습니다. 시스템이 앱을 종료할 수 있습니다.');
        // 이 권한이 없으면 자동매매가 중단될 수 있음
      }
      
      // 시스템 알림 권한 요청 (Android 13+)
      if (await Permission.systemAlertWindow.isDenied) {
        final systemAlertStatus = await Permission.systemAlertWindow.request();
        if (systemAlertStatus.isDenied) {
          print('⚠️ 시스템 알림 권한이 거부되었습니다.');
          // 이 권한은 필수가 아니므로 계속 진행
        }
      }
      
      // "다른 앱 위에 표시하기" 권한 확인
      final overlayStatus = await Permission.systemAlertWindow.status;
      if (overlayStatus.isDenied) {
        print('⚠️ "다른 앱 위에 표시하기" 권한이 없습니다. Foreground Service가 제대로 작동하지 않을 수 있습니다.');
      }
      
      print('✅ 백그라운드 권한 요청 완료');
      return true;
    } catch (e) {
      print('❌ 백그라운드 권한 요청 실패: $e');
      return false;
    }
  }
  
  /// 필요한 모든 권한 요청
  static Future<bool> requestAllPermissions() async {
    try {
      print('🔐 모든 권한 요청 시작...');
      
      // 알림 권한 요청 (Android 13+)
      final notificationStatus = await Permission.notification.request();
      print('📱 알림 권한 상태: $notificationStatus');
      
      // 배터리 최적화 무시 권한 요청
      final batteryResult = await _channel.invokeMethod('requestIgnoreBatteryOptimization');
      print('🔋 배터리 최적화 무시 권한: $batteryResult');
      
      // Foreground Service 권한 확인
      final foregroundServiceStatus = await _checkForegroundServicePermission();
      print('🔧 Foreground Service 권한: $foregroundServiceStatus');
      
      return notificationStatus.isGranted && batteryResult == true && foregroundServiceStatus;
    } catch (e) {
      print('❌ 권한 요청 실패: $e');
      return false;
    }
  }
  
  /// Foreground Service 권한 확인
  static Future<bool> _checkForegroundServicePermission() async {
    try {
      // Android 14에서는 Foreground Service 권한이 자동으로 부여됨
      // 하지만 알림 권한은 별도로 요청해야 함
      return true;
    } catch (e) {
      print('❌ Foreground Service 권한 확인 실패: $e');
      return false;
    }
  }
  
  /// 알림 권한 상태 확인
  static Future<bool> isNotificationPermissionGranted() async {
    final status = await Permission.notification.status;
    return status.isGranted;
  }
  
  /// 배터리 최적화 설정 열기
  static Future<void> openBatteryOptimizationSettings() async {
    try {
      await _channel.invokeMethod('openBatteryOptimizationSettings');
    } catch (e) {
      print('❌ 배터리 최적화 설정 열기 실패: $e');
    }
  }
  
  /// 자동매매 권한 상태 확인 및 안내
  static Future<Map<String, bool>> checkAutoTradingPermissions() async {
    final Map<String, bool> permissions = {};
    
    try {
      // 알림 권한 확인
      final notificationStatus = await Permission.notification.status;
      permissions['notification'] = notificationStatus.isGranted;
      
      // 배터리 최적화 무시 권한 확인
      final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
      permissions['battery_optimization'] = batteryStatus.isGranted;
      
      // 시스템 알림 권한 확인 ("다른 앱 위에 표시하기")
      final overlayStatus = await Permission.systemAlertWindow.status;
      permissions['overlay'] = overlayStatus.isGranted;
      
             print('🔐 자동매매 권한 상태:');
       print('  📱 알림 권한: ${permissions['notification'] ?? false ? '✅' : '❌'}');
       print('  🔋 배터리 최적화 제외: ${permissions['battery_optimization'] ?? false ? '✅' : '❌'}');
       print('  🔧 다른 앱 위에 표시: ${permissions['overlay'] ?? false ? '✅' : '❌'}');
      
      return permissions;
    } catch (e) {
      print('❌ 권한 상태 확인 실패: $e');
      return permissions;
    }
  }
  
  /// 권한 부족 시 설정 안내 다이얼로그 표시
  static Future<void> showPermissionGuideDialog(BuildContext context) async {
         final permissions = await checkAutoTradingPermissions();
     final missingPermissions = permissions.entries.where((e) => !(e.value ?? false)).toList();
    
    if (missingPermissions.isNotEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('자동매매 권한 설정 필요'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('백그라운드 자동매매가 제대로 작동하려면 다음 권한이 필요합니다:'),
              const SizedBox(height: 16),
                             if (!(permissions['notification'] ?? false)) 
                 const Text('• 📱 알림 권한 (매매 시그널 알림)'),
               if (!(permissions['battery_optimization'] ?? false)) 
                 const Text('• 🔋 배터리 최적화 제외 (앱이 종료되지 않도록)'),
               if (!(permissions['overlay'] ?? false)) 
                 const Text('• 🔧 다른 앱 위에 표시 (Foreground Service)'),
              const SizedBox(height: 16),
              const Text('설정에서 권한을 활성화해주세요.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('나중에'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                openBatteryOptimizationSettings();
              },
              child: const Text('설정으로 이동'),
            ),
          ],
        ),
      );
    }
  }
  
  /// 권한 상태 요약
  static Future<Map<String, bool>> getPermissionStatus() async {
    final notificationGranted = await isNotificationPermissionGranted();
    final foregroundServiceGranted = await _checkForegroundServicePermission();
    
    return {
      'notification': notificationGranted,
      'foregroundService': foregroundServiceGranted,
      'allGranted': notificationGranted && foregroundServiceGranted,
    };
  }

  /// 권한이 거부된 경우 설정 화면으로 이동
  static Future<void> openAppSettings() async {
    try {
      await AppSettings.openAppSettings();
    } catch (e) {
      print('❌ 앱 설정 열기 실패: $e');
    }
  }

  /// 권한 상태에 따른 안내 메시지 생성
  static String getPermissionStatusMessage(Map<Permission, PermissionStatus> statuses) {
    final deniedPermissions = <String>[];
    
    if (statuses[Permission.notification]?.isDenied == true) {
      deniedPermissions.add('알림');
    }
    
    if (statuses[Permission.ignoreBatteryOptimizations]?.isDenied == true) {
      deniedPermissions.add('배터리 최적화 무시');
    }
    
    if (deniedPermissions.isEmpty) {
      return '모든 권한이 허용되었습니다.';
    } else {
      return '다음 권한이 거부되었습니다: ${deniedPermissions.join(', ')}';
    }
  }

  /// 권한 요청 다이얼로그 표시
  static Future<bool> showPermissionDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('권한 필요'),
        content: const Text(
          '백그라운드 자동매매를 위해서는 다음 권한들이 필요합니다:\n\n'
          '• 알림 권한\n'
          '• 배터리 최적화 무시 권한\n\n'
          '권한을 허용하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('허용'),
          ),
        ],
      ),
    );
    
    return result ?? false;
  }

  /// 권한 설정 안내 다이얼로그 표시
  static Future<void> showSettingsDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('권한 설정 필요'),
        content: const Text(
          '일부 권한이 거부되어 백그라운드 서비스가 제대로 작동하지 않을 수 있습니다.\n\n'
          '앱 설정에서 권한을 수동으로 허용해주세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('나중에'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('설정으로 이동'),
          ),
        ],
      ),
    );
    
    if (result == true) {
      await openAppSettings();
    }
  }
}
