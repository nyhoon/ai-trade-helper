import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ForegroundServiceManager {
  static const MethodChannel _channel = MethodChannel('auto_trading_service');
  
  /// Foreground Service 시작
  static Future<bool> startForegroundService() async {
    try {
      print('🔧 Foreground Service 시작 요청...');
      
      // 서비스 상태 저장
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('foreground_service_running', true);
      await prefs.setString('service_start_time', DateTime.now().toIso8601String());
      
      // MethodChannel 호출 전에 잠시 대기
      await Future.delayed(const Duration(milliseconds: 200));
      
      final result = await _channel.invokeMethod('startForegroundService');
      print('✅ Foreground Service 시작됨: $result');
      
      if (result == true) {
        // 성공 시 추가 정보 저장
        await prefs.setBool('service_started_successfully', true);
        print('📱 백그라운드 자동매매가 활성화되었습니다.');
      }
      
      return result == true;
    } catch (e) {
      print('❌ Foreground Service 시작 실패: $e');
      
      // 실패 시 상태 정리
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('foreground_service_running', false);
      await prefs.setBool('service_started_successfully', false);
      
      return false;
    }
  }
  
  /// Foreground Service 중지
  static Future<bool> stopForegroundService() async {
    try {
      print('🔧 Foreground Service 중지 요청...');
      
      // 서비스 상태 저장
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('foreground_service_running', false);
      await prefs.setBool('service_started_successfully', false);
      
      // MethodChannel 호출 전에 잠시 대기
      await Future.delayed(const Duration(milliseconds: 200));
      
      final result = await _channel.invokeMethod('stopForegroundService');
      print('🛑 Foreground Service 중지됨: $result');
      return result == true;
    } catch (e) {
      print('❌ Foreground Service 중지 실패: $e');
      return false;
    }
  }
  
  /// Foreground Service 상태 확인
  static Future<bool> isForegroundServiceRunning() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('foreground_service_running') ?? false;
    } catch (e) {
      print('❌ Foreground Service 상태 확인 실패: $e');
      return false;
    }
  }
  
  /// 서비스 재시작 (앱 재시작 시)
  static Future<bool> restartForegroundService() async {
    try {
      print('🔄 Foreground Service 재시작 요청...');
      
      // 기존 서비스 중지
      await stopForegroundService();
      await Future.delayed(const Duration(seconds: 2));
      
      // 새 서비스 시작
      return await startForegroundService();
    } catch (e) {
      print('❌ Foreground Service 재시작 실패: $e');
      return false;
    }
  }
}
