import 'package:cloud_functions/cloud_functions.dart';

/// 서버 Functions에 위임하는 KIS 프록시 래퍼
class RemoteKisService {
  RemoteKisService._();
  static final RemoteKisService instance = RemoteKisService._();

  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<List<Map<String, dynamic>>> getDailyChart(String symbol, {int days = 100}) async {
    try {
      final callable = _functions.httpsCallable('getDailyChart');
      final resp = await callable.call(<String, dynamic>{'symbol': symbol, 'days': days});
      final data = (resp.data as Map?) ?? const {};
      final items = (data['items'] as List?) ?? const [];
      return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      // 서버 실패 시 빈 목록 반환(클라이언트에서 폴백 선택)
      return <Map<String, dynamic>>[];
    }
  }

  Future<Map<String, dynamic>?> getCurrentPrice(String symbol) async {
    try {
      final callable = _functions.httpsCallable('getCurrentPrice');
      final resp = await callable.call(<String, dynamic>{'symbol': symbol});
      final data = (resp.data as Map?) ?? const {};
      if (data['hasData'] == true) {
        return Map<String, dynamic>.from(data['data'] as Map);
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}


