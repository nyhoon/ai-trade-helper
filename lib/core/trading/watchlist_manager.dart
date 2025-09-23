import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class WatchlistItem {
  final String stockCode;
  final String stockName;
  final DateTime addedAt;

  WatchlistItem({
    required this.stockCode,
    required this.stockName,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'stockCode': stockCode,
      'stockName': stockName,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  factory WatchlistItem.fromJson(Map<String, dynamic> json) {
    return WatchlistItem(
      stockCode: json['stockCode'],
      stockName: json['stockName'],
      addedAt: DateTime.parse(json['addedAt']),
    );
  }
}

// WatchlistManager 클래스는 SQLite 시스템으로 대체되었습니다.
// 새로운 시스템에서는 WatchlistRepository를 사용하세요.
