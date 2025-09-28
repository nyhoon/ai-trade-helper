import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Firebase Functions 호출 래퍼 (onCall)
/// - analyzeStock
/// - analyzeMultipleStocks
/// - analyzeWatchlist
/// - analyzeHoldings
/// - getTopRecommendations
class AnalysisFunctionsService {
  AnalysisFunctionsService({FirebaseFunctions? functions})
      : _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  final FirebaseFunctions _functions;

  /// Firebase Auth 상태 확인 및 재로그인
  Future<void> _ensureAuthenticated() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('⚠️ [AnalysisFunctionsService] 사용자 인증 정보 없음, 익명 로그인 시도...');
        await FirebaseAuth.instance.signInAnonymously();
        print('✅ [AnalysisFunctionsService] 익명 로그인 완료');
      } else {
        print('✅ [AnalysisFunctionsService] 사용자 인증 상태 확인: ${user.uid}');
      }
    } catch (e) {
      print('❌ [AnalysisFunctionsService] 인증 확인 실패: $e');
      // 인증 실패해도 Functions 호출은 시도 (일부 Functions는 인증 불필요)
    }
  }

  /// 단일 종목 분석 호출
  /// - symbol: 종목 코드
  /// - days: 조회 일수(기본 100)
  /// - buyThreshold/sellThreshold: 임계값(선택)
  Future<Map<String, dynamic>> analyzeStock({
    required String symbol,
    int days = 100,
    double? buyThreshold,
    double? sellThreshold,
  }) async {
    // Firebase Auth 상태 확인
    await _ensureAuthenticated();
    
    final callable = _functions.httpsCallable('analyzeStock');
    final result = await callable.call(<String, dynamic>{
      'symbol': symbol,
      'days': days,
      if (buyThreshold != null) 'buyThreshold': buyThreshold,
      if (sellThreshold != null) 'sellThreshold': sellThreshold,
    });
    final data = result.data;
    if (data is Map<String, dynamic>) {
      return data;
    }
    return <String, dynamic>{};
  }

  /// 다중 종목 분석 호출
  Future<List<Map<String, dynamic>>> analyzeMultipleStocks({
    required List<String> symbols,
    int days = 100,
  }) async {
    if (symbols.isEmpty) return <Map<String, dynamic>>[];
    
    // Firebase Auth 상태 확인
    await _ensureAuthenticated();
    
    final callable = _functions.httpsCallable('analyzeMultipleStocks');
    final result = await callable.call(<String, dynamic>{
      'symbols': symbols,
      'days': days,
    });
    final data = result.data;
    if (data is Map && data['results'] is List) {
      final list = (data['results'] as List)
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
      return list;
    }
    return <Map<String, dynamic>>[];
  }

  /// 관심종목 일괄 분석
  Future<List<Map<String, dynamic>>> analyzeWatchlist({
    required String uid,
    int days = 100,
  }) async {
    // Firebase Auth 상태 확인
    await _ensureAuthenticated();
    
    final callable = _functions.httpsCallable('analyzeWatchlist');
    final result = await callable.call(<String, dynamic>{
      'uid': uid,
      'days': days,
    });
    final data = result.data;
    if (data is Map && data['results'] is List) {
      return (data['results'] as List)
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  /// 보유종목 일괄 분석
  Future<List<Map<String, dynamic>>> analyzeHoldings({
    required String uid,
    int days = 100,
  }) async {
    // Firebase Auth 상태 확인
    await _ensureAuthenticated();
    
    final callable = _functions.httpsCallable('analyzeHoldings');
    final result = await callable.call(<String, dynamic>{
      'uid': uid,
      'days': days,
    });
    final data = result.data;
    if (data is Map && data['results'] is List) {
      return (data['results'] as List)
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  /// 추천 상위 N개 가져오기(서버가 저장 후 반환)
  Future<List<Map<String, dynamic>>> getTopRecommendations({
    required String uid,
    int limit = 10,
  }) async {
    // Firebase Auth 상태 확인
    await _ensureAuthenticated();
    
    final callable = _functions.httpsCallable('getTopRecommendations');
    final result = await callable.call(<String, dynamic>{
      'uid': uid,
      'limit': limit,
    });
    final data = result.data;
    if (data is Map && data['items'] is List) {
      return (data['items'] as List)
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    }
    return <Map<String, dynamic>>[];
  }
}


