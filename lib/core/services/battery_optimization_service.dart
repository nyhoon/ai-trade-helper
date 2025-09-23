import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BatteryOptimizationService {
  static const MethodChannel _channel = MethodChannel('battery_optimization');
  
  /// 배터리 최적화 무시 권한 요청
  static Future<bool> requestIgnoreBatteryOptimization() async {
    try {
      print('🔋 배터리 최적화 무시 권한 요청...');
      
      final result = await _channel.invokeMethod('requestIgnoreBatteryOptimization');
      print('✅ 배터리 최적화 무시 권한 요청 결과: $result');
      
      // 권한 상태 저장
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('battery_optimization_ignored', result == true);
      
      return result == true;
    } catch (e) {
      print('❌ 배터리 최적화 무시 권한 요청 실패: $e');
      return false;
    }
  }
  
  /// 배터리 최적화 무시 상태 확인
  static Future<bool> isBatteryOptimizationIgnored() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('battery_optimization_ignored') ?? false;
    } catch (e) {
      print('❌ 배터리 최적화 상태 확인 실패: $e');
      return false;
    }
  }
  
  /// 배터리 최적화 설정 화면으로 이동
  static Future<void> openBatteryOptimizationSettings() async {
    try {
      print('🔋 배터리 최적화 설정 화면 열기...');
      
      await _channel.invokeMethod('openBatteryOptimizationSettings');
      print('✅ 배터리 최적화 설정 화면 열기 완료');
    } catch (e) {
      print('❌ 배터리 최적화 설정 화면 열기 실패: $e');
    }
  }
}
