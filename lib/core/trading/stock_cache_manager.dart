import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 종목 정보 캐싱 매니저
class StockCacheManager {
  static const String _stockNamesKey = 'stock_names_cache';
  static const String _lastUpdateKey = 'stock_names_last_update';
  static const Duration _cacheExpiry = Duration(hours: 24); // 24시간 캐시

  /// 캐시된 종목 이름들을 가져오기
  static Future<Map<String, String>> getCachedStockNames() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(_stockNamesKey);
      final lastUpdateStr = prefs.getString(_lastUpdateKey);
      
      if (cachedData != null && lastUpdateStr != null) {
        final lastUpdate = DateTime.parse(lastUpdateStr);
        final now = DateTime.now();
        
        // 캐시가 유효한지 확인
        if (now.difference(lastUpdate) < _cacheExpiry) {
          final Map<String, dynamic> decoded = jsonDecode(cachedData);
          final Map<String, String> stockNames = Map<String, String>.from(decoded);
          print('✅ 캐시된 종목 이름 로드: ${stockNames.length}개');
          return stockNames;
        }
      }
      
      print('⚠️ 캐시가 없거나 만료됨');
      return {};
    } catch (e) {
      print('❌ 캐시 로드 실패: $e');
      return {};
    }
  }

  /// 종목 이름들을 캐시에 저장
  static Future<void> cacheStockNames(Map<String, String> stockNames) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encodedData = jsonEncode(stockNames);
      
      await prefs.setString(_stockNamesKey, encodedData);
      await prefs.setString(_lastUpdateKey, DateTime.now().toIso8601String());
      
      print('✅ 종목 이름 캐시 저장 완료: ${stockNames.length}개');
    } catch (e) {
      print('❌ 캐시 저장 실패: $e');
    }
  }

  /// 캐시 무효화
  static Future<void> invalidateCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_stockNamesKey);
      await prefs.remove(_lastUpdateKey);
      print('✅ 캐시 무효화 완료');
    } catch (e) {
      print('❌ 캐시 무효화 실패: $e');
    }
  }

  /// 캐시 상태 확인
  static Future<bool> isCacheValid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastUpdateStr = prefs.getString(_lastUpdateKey);
      
      if (lastUpdateStr != null) {
        final lastUpdate = DateTime.parse(lastUpdateStr);
        final now = DateTime.now();
        return now.difference(lastUpdate) < _cacheExpiry;
      }
      
      return false;
    } catch (e) {
      return false;
    }
  }
}
