import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../trading/market_time_validator.dart';

/// 보유종목 Repository
class HoldingsRepository {
  CollectionReference<Map<String, dynamic>> _collection(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('holdings');

  String _resolveMarket(String stockCode) {
    return MarketTimeValidator.instance.getMarketFromSymbol(stockCode);
  }

  /// 로컬 테이블 생성/인덱스: 서버 이전으로 불필요 → 제거

  /// 보유종목 저장/업데이트
  Future<void> saveHoldings(List<Map<String, dynamic>> holdings) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final batch = FirebaseFirestore.instance.batch();
      // 기존 데이터 전체 삭제 후 재작성(간단화)
      final existing = await _collection(uid).get();
      for (final d in existing.docs) {
        batch.delete(d.reference);
      }
      for (final holding in holdings) {
        final String pdno = (holding['pdno'] ?? '').toString();
        if (pdno.isEmpty) continue;
        final String prdtName = holding['prdt_name'] ?? '';
        final int hldgQty = _parseInt(holding['hldg_qty']) ?? 0;
        final double pchsAvgPric = _parseDouble(holding['pchs_avg_pric']) ?? 0.0;
        final double prpr = _parseDouble(holding['prpr']) ?? 0.0;
        final double evluAmt = _parseDouble(holding['evlu_amt']) ?? 0.0;
        final double evluPflsAmt = _parseDouble(holding['evlu_pfls_amt']) ?? 0.0;
        final double evluPflsRt = _parseDouble(holding['evlu_pfls_rt']) ?? 0.0;
        final String resolvedMarket = _resolveMarket(pdno);
        batch.set(_collection(uid).doc(pdno), {
          'pdno': pdno,
          'prdt_name': prdtName,
          'market': resolvedMarket,
          'hldg_qty': hldgQty,
          'pchs_avg_pric': pchsAvgPric,
          'prpr': prpr,
          'evlu_amt': evluAmt,
          'evlu_pfls_amt': evluPflsAmt,
          'evlu_pfls_rt': evluPflsRt,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        }, SetOptions(merge: true));
      }
      await batch.commit();
      print('✅ 보유종목 저장 완료(Firestore): ${holdings.length}개');
    } catch (e) {
      print('❌ 보유종목 저장 실패: $e');
      rethrow;
    }
  }

  /// 보유종목 조회 (getAllHoldings와 동일)
  Future<List<Map<String, dynamic>>> getHoldings() async {
    return await getAllHoldings();
  }

  /// 모든 보유종목 조회
  Future<List<Map<String, dynamic>>> getAllHoldings() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return [];
      final snap = await _collection(uid).orderBy('updated_at', descending: true).get();
      final holdings = snap.docs.map((d) => d.data()).toList();
      print('✅ 보유종목 조회 완료(Firestore): ${holdings.length}개');
      return holdings;
    } catch (e) {
      print('❌ 보유종목 조회 실패: $e');
      return [];
    }
  }

  /// API 데이터와 로컬 DB 동기화
  Future<void> syncWithApi(List<Map<String, dynamic>> apiPositions) async {
    try {
      await saveHoldings(apiPositions);
      print('✅ API와 보유종목 동기화 완료(Firestore): ${apiPositions.length}개');
    } catch (e) {
      print('❌ API와 보유종목 동기화 실패: $e');
    }
  }

  /// 특정 종목 보유 정보 업데이트
  Future<void> updateHolding({
    required String stockCode,
    double? currentPrice, // prpr
    double? profitRate,   // evlu_pfls_rt
    double? currentValue, // evlu_amt
    DateTime? updatedAt,
  }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final updateData = <String, dynamic>{};
      if (currentPrice != null) updateData['prpr'] = currentPrice;
      if (profitRate != null) updateData['evlu_pfls_rt'] = profitRate;
      if (currentValue != null) updateData['evlu_amt'] = currentValue;
      updateData['updated_at'] = (updatedAt ?? DateTime.now()).millisecondsSinceEpoch;
      await _collection(uid).doc(stockCode).set(updateData, SetOptions(merge: true));
      
      print('✅ 보유종목 업데이트 완료: $stockCode');
    } catch (e) {
      print('❌ 보유종목 업데이트 실패: $e');
    }
  }

  /// 특정 종목 보유 정보 조회
  Future<Map<String, dynamic>?> getHolding(String stockCode) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return null;
      final doc = await _collection(uid).doc(stockCode).get();
      if (!doc.exists) return null;
      return doc.data();
    } catch (e) {
      print('❌ 특정 종목 보유 정보 조회 실패: $e');
      return null;
    }
  }

  /// 보유종목 개수 조회
  Future<int> getHoldingsCount() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return 0;
      final snap = await _collection(uid).count().get();
      return snap.count ?? 0;
    } catch (e) {
      print('❌ 보유종목 개수 조회 실패: $e');
      return 0;
    }
  }

  /// 보유종목 삭제
  Future<void> deleteHoldings() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final snap = await _collection(uid).get();
      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      print('✅ 보유종목 삭제 완료(Firestore)');
    } catch (e) {
      print('❌ 보유종목 삭제 실패: $e');
      rethrow;
    }
  }

  /// 특정 종목 보유 정보 삭제
  Future<void> deleteHolding(String stockCode) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await _collection(uid).doc(stockCode).delete();
      print('✅ 특정 종목 보유 정보 삭제 완료(Firestore): $stockCode');
    } catch (e) {
      print('❌ 특정 종목 보유 정보 삭제 실패: $e');
      rethrow;
    }
  }

  /// 오래된 보유종목 데이터 정리
  Future<void> cleanupOldHoldings({int daysToKeep = 7}) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final cutoffTime = DateTime.now().subtract(Duration(days: daysToKeep)).millisecondsSinceEpoch;
      final snap = await _collection(uid).where('updated_at', isLessThan: cutoffTime).get();
      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      print('✅ 오래된 보유종목 데이터 정리 완료(Firestore): ${snap.docs.length}개 삭제');
    } catch (e) {
      print('❌ 오래된 보유종목 데이터 정리 실패: $e');
    }
  }

  /// 보유종목 통계 조회
  Future<Map<String, dynamic>> getHoldingsStats() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        return {
          'totalCount': 0,
          'totalValue': 0.0,
          'totalProfitLoss': 0.0,
          'avgProfitRate': 0.0,
          'lastUpdated': 0,
        };
      }
      final snap = await _collection(uid).get();
      int totalCount = 0;
      double totalValue = 0.0;
      double totalProfitLoss = 0.0;
      double avgProfitRate = 0.0;
      int lastUpdated = 0;
      for (final d in snap.docs) {
        final data = d.data();
        totalCount += 1;
        totalValue += (data['evlu_amt'] as num?)?.toDouble() ?? 0.0;
        totalProfitLoss += (data['evlu_pfls_amt'] as num?)?.toDouble() ?? 0.0;
        avgProfitRate += (data['evlu_pfls_rt'] as num?)?.toDouble() ?? 0.0;
        lastUpdated = (data['updated_at'] as int?) ?? lastUpdated;
      }
      if (totalCount > 0) avgProfitRate = avgProfitRate / totalCount;
      return {
        'totalCount': totalCount,
        'totalValue': totalValue,
        'totalProfitLoss': totalProfitLoss,
        'avgProfitRate': avgProfitRate,
        'lastUpdated': lastUpdated,
      };
    } catch (e) {
      print('❌ 보유종목 통계 조회 실패: $e');
      return {
        'totalCount': 0,
        'totalValue': 0.0,
        'totalProfitLoss': 0.0,
        'avgProfitRate': 0.0,
        'lastUpdated': 0,
      };
    }
  }

  /// 문자열을 정수로 변환
  int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      return parsed;
    }
    return null;
  }

  /// 문자열을 실수로 변환
  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed;
    }
    return null;
  }
}
