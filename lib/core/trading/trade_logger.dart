import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class TradeSignal {
  final String stockCode;
  final String stockName;
  final String signalType; // 'buy' or 'sell'
  final DateTime timestamp;
  final Map<String, dynamic> indicators;
  final String reason;
  final double currentPrice;
  final double? targetPrice;
  final String? stopLoss;
  final String? takeProfit;

  TradeSignal({
    required this.stockCode,
    required this.stockName,
    required this.signalType,
    required this.timestamp,
    required this.indicators,
    required this.reason,
    required this.currentPrice,
    this.targetPrice,
    this.stopLoss,
    this.takeProfit,
  });

  Map<String, dynamic> toJson() {
    return {
      'stockCode': stockCode,
      'stockName': stockName,
      'signalType': signalType,
      'timestamp': timestamp.toIso8601String(),
      'indicators': indicators,
      'reason': reason,
      'currentPrice': currentPrice,
      'targetPrice': targetPrice,
      'stopLoss': stopLoss,
      'takeProfit': takeProfit,
    };
  }

  factory TradeSignal.fromJson(Map<String, dynamic> json) {
    return TradeSignal(
      stockCode: json['stockCode'],
      stockName: json['stockName'],
      signalType: json['signalType'],
      timestamp: DateTime.parse(json['timestamp']),
      indicators: Map<String, dynamic>.from(json['indicators']),
      reason: json['reason'],
      currentPrice: json['currentPrice'].toDouble(),
      targetPrice: json['targetPrice']?.toDouble(),
      stopLoss: json['stopLoss'],
      takeProfit: json['takeProfit'],
    );
  }
}

class TradeLogger {
  static const String _logKey = 'trade_signals';
  
  /// 매수/매도 시그널 로그 저장
  static Future<void> logSignal(TradeSignal signal) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingLogs = prefs.getStringList(_logKey) ?? [];
      
      // 새로운 시그널을 JSON으로 변환
      final signalJson = jsonEncode(signal.toJson());
      existingLogs.add(signalJson);
      
      // 최대 100개까지만 저장 (오래된 것부터 삭제)
      if (existingLogs.length > 100) {
        existingLogs.removeRange(0, existingLogs.length - 100);
      }
      
      await prefs.setStringList(_logKey, existingLogs);
      
      print('🤖 [시그널 로그] ${signal.signalType.toUpperCase()} 시그널 포착');
      print('📈 종목: ${signal.stockName} (${signal.stockCode})');
      print('💰 현재가: ${signal.currentPrice}원');
      print('📊 지표: ${signal.indicators}');
      print('📝 사유: ${signal.reason}');
      print('⏰ 시간: ${signal.timestamp}');
    } catch (e) {
      print('Failed to log signal: $e');
    }
  }
  
  /// 저장된 시그널 로그 조회
  static Future<List<TradeSignal>> getSignals() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final logs = prefs.getStringList(_logKey) ?? [];
      
      return logs.map((log) {
        final json = jsonDecode(log);
        return TradeSignal.fromJson(json);
      }).toList();
    } catch (e) {
      print('Failed to get signals: $e');
      return [];
    }
  }
  
  /// 특정 종목의 시그널 로그 조회
  static Future<List<TradeSignal>> getSignalsForStock(String stockCode) async {
    final allSignals = await getSignals();
    return allSignals.where((signal) => signal.stockCode == stockCode).toList();
  }
  
  /// 최근 N개의 시그널 로그 조회
  static Future<List<TradeSignal>> getRecentSignals(int count) async {
    final allSignals = await getSignals();
    allSignals.sort((a, b) => b.timestamp.compareTo(a.timestamp)); // 최신순 정렬
    return allSignals.take(count).toList();
  }
  
  /// 로그 초기화
  static Future<void> clearLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_logKey);
      print('Trade logs cleared');
    } catch (e) {
      print('Failed to clear logs: $e');
    }
  }
}
