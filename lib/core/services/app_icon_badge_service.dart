import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppIconBadgeService {
  static const MethodChannel _channel = MethodChannel('app_icon_badge');
  
  /// 앱 아이콘에 자동매매 상태 배지 표시
  static Future<bool> showAutoTradingBadge() async {
    try {
      print('🔴 앱 아이콘에 자동매매 배지 표시...');
      
      final result = await _channel.invokeMethod('showAutoTradingBadge');
      print('✅ 앱 아이콘 배지 표시 결과: $result');
      
      // 배지 상태 저장
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('app_icon_badge_shown', result == true);
      
      return result == true;
    } catch (e) {
      print('❌ 앱 아이콘 배지 표시 실패: $e');
      return false;
    }
  }
  
  /// 앱 아이콘 배지 제거
  static Future<bool> hideAutoTradingBadge() async {
    try {
      print('⚪ 앱 아이콘 배지 제거...');
      
      final result = await _channel.invokeMethod('hideAutoTradingBadge');
      print('✅ 앱 아이콘 배지 제거 결과: $result');
      
      // 배지 상태 저장
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('app_icon_badge_shown', false);
      
      return result == true;
    } catch (e) {
      print('❌ 앱 아이콘 배지 제거 실패: $e');
      return false;
    }
  }
  
  /// 앱 아이콘 배지 상태 확인
  static Future<bool> isBadgeShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('app_icon_badge_shown') ?? false;
    } catch (e) {
      print('❌ 앱 아이콘 배지 상태 확인 실패: $e');
      return false;
    }
  }
  
  /// 자동매매 상태에 따라 배지 업데이트
  static Future<void> updateBadgeForAutoTrading(bool isAutoTradingEnabled) async {
    try {
      if (isAutoTradingEnabled) {
        await showAutoTradingBadge();
      } else {
        await hideAutoTradingBadge();
      }
    } catch (e) {
      print('❌ 앱 아이콘 배지 업데이트 실패: $e');
    }
  }
}
