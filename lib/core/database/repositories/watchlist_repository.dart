import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../trading/market_time_validator.dart';

/// 관심종목 Repository
class WatchlistRepository {
  CollectionReference<Map<String, dynamic>> _collection(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('watchlist');

  String _resolveMarket(String stockCode) {
    return MarketTimeValidator.instance.getMarketFromSymbol(stockCode);
  }

  /// 관심종목 추가 (차트 데이터 자동 수집)
  Future<int> addToWatchlist({
    required String stockCode,
    required String stockName,
    String? memo,
  }) async {
    try {
      print('🔍 관심종목 추가 시작: $stockCode ($stockName)');
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        throw Exception('No authenticated user');
      }
      final now = DateTime.now().millisecondsSinceEpoch;

      final doc = _collection(uid).doc(stockCode);
      final snapshot = await doc.get();
      if (snapshot.exists) {
        print('⚠️ 이미 관심종목에 존재: $stockCode');
        return 1;
      }

      final resolvedMarket = _resolveMarket(stockCode);
      await doc.set({
        'stock_code': stockCode,
        'stock_name': stockName,
        'market': resolvedMarket,
        'added_at': now,
        'memo': memo,
        'is_active': 1,
      }, SetOptions(merge: true));

      print('✅ 관심종목 추가 완료: $stockName ($stockCode)');
      return 1;
    } catch (e) {
      print('❌ 관심종목 추가 실패: $e');
      rethrow;
    }
  }

  // 서버 이전: 차트 데이터 로컬 수집 제거

  /// 관심종목 제거 (하드 삭제 + 데이터 정리)
  Future<void> removeFromWatchlist(String stockCode) async {
    try {
      print('🗑️ 관심종목 제거 시작: $stockCode');
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        throw Exception('No authenticated user');
      }
      await _collection(uid).doc(stockCode).delete();
      print('✅ 관심종목 완전 제거: $stockCode');
      
    } catch (e) {
      print('❌ 관심종목 제거 실패: $e');
      rethrow;
    }
  }

  // 로컬 차트 데이터 정리는 사용하지 않음

  /// 관심종목 목록 조회
  Future<List<Map<String, dynamic>>> getWatchlist() async {
    try {
      print('🔍 관심종목 목록 조회 시작...');
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return [];
      final snap = await _collection(uid).orderBy('added_at', descending: true).get();
      final list = snap.docs.map((d) => d.data()).toList();
      print('✅ 관심종목 목록 조회 완료: ${list.length}개');
      return list;
    } catch (e) {
      print('❌ 관심종목 목록 조회 실패: $e');
      return [];
    }
  }

  /// 관심종목 상세 정보 조회 (종목 정보와 JOIN)
  Future<List<Map<String, dynamic>>> getWatchlistWithStockInfo() async {
    // Firestore 단일 소스: 섹터 정보는 별도 마스터에서 합치는 형태로 확장 가능
    return await getWatchlist();
  }

  /// 관심종목 여부 확인
  Future<bool> isInWatchlist(String stockCode) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final doc = await _collection(uid).doc(stockCode).get();
    return doc.exists;
  }

  /// 관심종목 메모 업데이트
  Future<void> updateMemo(String stockCode, String memo) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _collection(uid).doc(stockCode).set({'memo': memo}, SetOptions(merge: true));
  }

  /// 관심종목 개수 조회
  Future<int> getWatchlistCount() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return 0;
    final snap = await _collection(uid).where('is_active', isEqualTo: 1).count().get();
    return snap.count ?? 0;
  }

  /// 관심종목 일괄 추가
  Future<void> addMultipleToWatchlist(List<Map<String, String>> stocks) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = FirebaseFirestore.instance.batch();
    for (final stock in stocks) {
      final code = stock['stock_code']!;
      final name = stock['stock_name']!;
      final memo = stock['memo'];
      final doc = _collection(uid).doc(code);
      batch.set(doc, {
        'stock_code': code,
        'stock_name': name,
        'market': _resolveMarket(code),
        'added_at': now,
        'memo': memo,
        'is_active': 1,
      }, SetOptions(merge: true));
    }
    await batch.commit();
    print('✅ 관심종목 일괄 추가: ${stocks.length}개');
  }

  /// 관심종목 정렬 순서 변경
  Future<void> reorderWatchlist(List<String> stockCodes) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = FirebaseFirestore.instance.batch();
    for (int i = 0; i < stockCodes.length; i++) {
      final code = stockCodes[i];
      final doc = _collection(uid).doc(code);
      batch.set(doc, {
        'added_at': now + i,
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }
}
