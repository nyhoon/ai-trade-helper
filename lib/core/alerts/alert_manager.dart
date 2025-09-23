import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../database/repositories/watchlist_repository.dart';

enum AlertType {
  buySignal,
  sellSignal,
  priceAlert,
  volumeAlert,
}

class AlertSetting {
  final String id;
  final String stockCode;
  final String stockName;
  final AlertType alertType;
  final Map<String, dynamic> conditions;
  final bool isEnabled;
  final DateTime createdAt;
  final DateTime? lastTriggered;

  AlertSetting({
    required this.id,
    required this.stockCode,
    required this.stockName,
    required this.alertType,
    required this.conditions,
    required this.isEnabled,
    required this.createdAt,
    this.lastTriggered,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'stockCode': stockCode,
      'stockName': stockName,
      'alertType': alertType.name,
      'conditions': conditions,
      'isEnabled': isEnabled,
      'createdAt': createdAt.toIso8601String(),
      'lastTriggered': lastTriggered?.toIso8601String(),
    };
  }

  factory AlertSetting.fromJson(Map<String, dynamic> json) {
    return AlertSetting(
      id: json['id'],
      stockCode: json['stockCode'],
      stockName: json['stockName'],
      alertType: AlertType.values.firstWhere(
        (e) => e.name == json['alertType'],
        orElse: () => AlertType.buySignal,
      ),
      conditions: Map<String, dynamic>.from(json['conditions']),
      isEnabled: json['isEnabled'] ?? true,
      createdAt: DateTime.parse(json['createdAt']),
      lastTriggered: json['lastTriggered'] != null 
          ? DateTime.parse(json['lastTriggered']) 
          : null,
    );
  }

  AlertSetting copyWith({
    String? id,
    String? stockCode,
    String? stockName,
    AlertType? alertType,
    Map<String, dynamic>? conditions,
    bool? isEnabled,
    DateTime? createdAt,
    DateTime? lastTriggered,
  }) {
    return AlertSetting(
      id: id ?? this.id,
      stockCode: stockCode ?? this.stockCode,
      stockName: stockName ?? this.stockName,
      alertType: alertType ?? this.alertType,
      conditions: conditions ?? this.conditions,
      isEnabled: isEnabled ?? this.isEnabled,
      createdAt: createdAt ?? this.createdAt,
      lastTriggered: lastTriggered ?? this.lastTriggered,
    );
  }
}

class AlertManager {
  static const String _alertsKey = 'alert_settings';
  
  /// 알림 설정 목록 조회
  static Future<List<AlertSetting>> getAlerts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alertsJson = prefs.getStringList(_alertsKey) ?? [];
      
      return alertsJson.map((alert) {
        final json = jsonDecode(alert);
        return AlertSetting.fromJson(json);
      }).toList();
    } catch (e) {
      print('Failed to get alerts: $e');
      return [];
    }
  }
  
  /// 알림 설정 추가
  static Future<bool> addAlert(AlertSetting alert) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alerts = await getAlerts();
      
      // 중복 확인
      if (alerts.any((a) => a.id == alert.id)) {
        return false;
      }
      
      alerts.add(alert);
      
      final alertsJson = alerts.map((a) => jsonEncode(a.toJson())).toList();
      await prefs.setStringList(_alertsKey, alertsJson);
      
      print('알림 설정 추가: ${alert.stockName} (${alert.alertType.name})');
      return true;
    } catch (e) {
      print('Failed to add alert: $e');
      return false;
    }
  }
  
  /// 알림 설정 업데이트
  static Future<bool> updateAlert(AlertSetting alert) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alerts = await getAlerts();
      
      final index = alerts.indexWhere((a) => a.id == alert.id);
      if (index == -1) return false;
      
      alerts[index] = alert;
      
      final alertsJson = alerts.map((a) => jsonEncode(a.toJson())).toList();
      await prefs.setStringList(_alertsKey, alertsJson);
      
      print('알림 설정 업데이트: ${alert.stockName}');
      return true;
    } catch (e) {
      print('Failed to update alert: $e');
      return false;
    }
  }
  
  /// 알림 설정 삭제
  static Future<bool> deleteAlert(String alertId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alerts = await getAlerts();
      
      final filteredAlerts = alerts.where((a) => a.id != alertId).toList();
      
      final alertsJson = filteredAlerts.map((a) => jsonEncode(a.toJson())).toList();
      await prefs.setStringList(_alertsKey, alertsJson);
      
      print('알림 설정 삭제: $alertId');
      return true;
    } catch (e) {
      print('Failed to delete alert: $e');
      return false;
    }
  }
  
  /// 특정 종목의 알림 설정 조회
  static Future<List<AlertSetting>> getAlertsForStock(String stockCode) async {
    final alerts = await getAlerts();
    return alerts.where((alert) => alert.stockCode == stockCode).toList();
  }
  
  /// 활성화된 알림 설정 조회
  static Future<List<AlertSetting>> getEnabledAlerts() async {
    final alerts = await getAlerts();
    return alerts.where((alert) => alert.isEnabled).toList();
  }
  
  /// 알림 설정 초기화
  static Future<void> clearAlerts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_alertsKey);
      print('알림 설정이 초기화되었습니다.');
    } catch (e) {
      print('Failed to clear alerts: $e');
    }
  }
  
  /// 관심종목 시그널 알림 자동 생성
  static Future<void> createWatchlistSignalAlerts() async {
    try {
      final alerts = await getAlerts();
      final watchlistCodes = await _getWatchlistCodes();
      
      // 기존 관심종목 시그널 알림 제거
      final nonSignalAlerts = alerts.where((a) => 
        a.alertType != AlertType.buySignal && a.alertType != AlertType.sellSignal
      ).toList();
      
      // 새로운 관심종목 시그널 알림 생성
      final newAlerts = <AlertSetting>[];
      
      for (final stockCode in watchlistCodes) {
        final stockName = await _getStockName(stockCode);
        
        // 매수 시그널 알림
        newAlerts.add(AlertSetting(
          id: '${stockCode}_buy_signal',
          stockCode: stockCode,
          stockName: stockName,
          alertType: AlertType.buySignal,
          conditions: {'auto': true},
          isEnabled: true,
          createdAt: DateTime.now(),
        ));
        
        // 매도 시그널 알림
        newAlerts.add(AlertSetting(
          id: '${stockCode}_sell_signal',
          stockCode: stockCode,
          stockName: stockName,
          alertType: AlertType.sellSignal,
          conditions: {'auto': true},
          isEnabled: true,
          createdAt: DateTime.now(),
        ));
      }
      
      // 모든 알림 저장
      final allAlerts = [...nonSignalAlerts, ...newAlerts];
      final prefs = await SharedPreferences.getInstance();
      final alertsJson = allAlerts.map((a) => jsonEncode(a.toJson())).toList();
      await prefs.setStringList(_alertsKey, alertsJson);
      
      print('관심종목 시그널 알림 생성 완료: ${newAlerts.length}개');
    } catch (e) {
      print('Failed to create watchlist signal alerts: $e');
    }
  }
  
  // 새로운 SQLite 시스템 사용
  static Future<List<String>> _getWatchlistCodes() async {
    final watchlistRepository = WatchlistRepository();
    final watchlist = await watchlistRepository.getWatchlist();
    return watchlist.map((item) => item['stock_code'] as String).toList();
  }
  
  static Future<String> _getStockName(String stockCode) async {
    final watchlistRepository = WatchlistRepository();
    final watchlist = await watchlistRepository.getWatchlist();
    final item = watchlist.firstWhere(
      (item) => item['stock_code'] == stockCode,
      orElse: () => {'stock_code': stockCode, 'stock_name': '알 수 없는 종목'},
    );
    return item['stock_name'] as String;
  }
}
