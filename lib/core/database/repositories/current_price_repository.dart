import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// 현재가 데이터 Repository - 실시간 현재가 관리
class CurrentPriceRepository {
  DocumentReference<Map<String, dynamic>> _doc(String stockCode) =>
      FirebaseFirestore.instance.collection('prices').doc(stockCode);
  CollectionReference<Map<String, dynamic>> _userCol(String uid, String name) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection(name);

  /// 현재가 데이터 삽입 또는 업데이트 (Firestore 직접 쓰기 비활성화)
  Future<void> insertOrUpdateCurrentPrice({
    required String stockCode,
    required String market,
    required double currentPrice,
    required double prevClose,
    required double changeAmount,
    required double changeRate,
    required int volume,
    required double tradeAmount,
    required double highPrice,
    required double lowPrice,
    required double openPrice,
    double? marketCap,
    double? per,
    double? pbr,
  }) async {
    // Firestore 직접 쓰기 비활성화 - 서버 Functions를 통해서만 데이터 저장
    print('📊 $stockCode: 현재가 데이터는 서버 Functions를 통해 저장됩니다');
    print('⚠️ 클라이언트에서 Firestore 직접 쓰기 비활성화됨 (권한 문제 방지)');
  }

  /// 여러 종목의 현재가 데이터 일괄 삽입 (최적화)
  Future<void> insertMultipleCurrentPrice(List<Map<String, dynamic>> priceDataList) async {
    if (priceDataList.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = FirebaseFirestore.instance.batch();
    for (final data in priceDataList) {
      final code = data['stock_code'] as String;
      batch.set(_doc(code), {
        'stock_code': code,
        'market': data['market'],
        'current_price': data['current_price'],
        'prev_close': data['prev_close'],
        'change_amount': data['change_amount'],
        'change_rate': data['change_rate'],
        'volume': data['volume'],
        'trade_amount': data['trade_amount'],
        'high_price': data['high_price'],
        'low_price': data['low_price'],
        'open_price': data['open_price'],
        'market_cap': data['market_cap'],
        'per': data['per'],
        'pbr': data['pbr'],
        'timestamp': now,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
    print('📊 현재가 데이터 일괄 삽입 완료(Firestore): ${priceDataList.length}개');
  }

  /// 특정 종목의 현재가 조회
  Future<Map<String, dynamic>?> getCurrentPrice(String stockCode) async {
    final doc = await _doc(stockCode).get();
    if (doc.exists) return doc.data();
    return null;
  }

  /// 여러 종목의 현재가 조회
  Future<Map<String, Map<String, dynamic>>> getMultipleCurrentPrice(List<String> stockCodes) async {
    final result = <String, Map<String, dynamic>>{};
    if (stockCodes.isEmpty) return result;
    final futures = stockCodes.map((c) => _doc(c).get()).toList();
    final snaps = await Future.wait(futures);
    for (final s in snaps) {
      if (s.exists) {
        final data = s.data()!;
        result[data['stock_code'] as String] = data;
      }
    }
    return result;
  }

  /// 관심종목과 보유종목의 현재가 조회
  Future<Map<String, Map<String, dynamic>>> getActiveCurrentPrice() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return {};
    final watch = await _userCol(uid, 'watchlist').get();
    final hold = await _userCol(uid, 'holdings').get();
    final stockCodes = <String>{
      ...watch.docs.map((d) => (d.data()['stock_code'] ?? d.id) as String),
      ...hold.docs.map((d) => (d.data()['pdno'] ?? d.id) as String),
    }.toList();
    if (stockCodes.isEmpty) return {};
    return await getMultipleCurrentPrice(stockCodes);
  }

  /// 특정 시장의 현재가 조회
  Future<List<Map<String, dynamic>>> getCurrentPriceByMarket(String market) async {
    final snap = await FirebaseFirestore.instance
        .collection('prices')
        .where('market', isEqualTo: market)
        .get();
    return snap.docs.map((d) => d.data()).toList();
  }

  /// 상승률 기준 정렬된 현재가 조회
  Future<List<Map<String, dynamic>>> getCurrentPriceByChangeRate({
    String? market,
    int limit = 50,
    bool ascending = false, // false: 상승률 높은 순, true: 하락률 높은 순
  }) async {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection('prices');
    if (market != null) q = q.where('market', isEqualTo: market);
    q = q.orderBy('change_rate', descending: !ascending).limit(limit);
    final snap = await q.get();
    return snap.docs.map((d) => d.data()).toList();
  }

  /// 거래량 기준 정렬된 현재가 조회
  Future<List<Map<String, dynamic>>> getCurrentPriceByVolume({
    String? market,
    int limit = 50,
    bool ascending = false, // false: 거래량 많은 순, true: 거래량 적은 순
  }) async {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection('prices');
    if (market != null) q = q.where('market', isEqualTo: market);
    q = q.orderBy('volume', descending: !ascending).limit(limit);
    final snap = await q.get();
    return snap.docs.map((d) => d.data()).toList();
  }

  /// 현재가 데이터 존재 여부 확인
  Future<bool> hasCurrentPrice(String stockCode) async {
    final d = await _doc(stockCode).get();
    return d.exists;
  }

  /// 현재가 데이터 삭제 (특정 종목)
  Future<int> deleteCurrentPrice(String stockCode) async {
    await _doc(stockCode).delete();
    return 1;
  }

  /// 현재가 데이터 삭제 (특정 시장)
  Future<int> deleteCurrentPriceByMarket(String market) async {
    final snap = await FirebaseFirestore.instance.collection('prices').where('market', isEqualTo: market).get();
    final batch = FirebaseFirestore.instance.batch();
    for (final d in snap.docs) batch.delete(d.reference);
    await batch.commit();
    return snap.docs.length;
  }

  /// 오래된 현재가 데이터 정리 (1시간 이상)
  Future<int> cleanupOldCurrentPrice() async {
    final oneHourAgo = DateTime.now().millisecondsSinceEpoch - (60 * 60 * 1000);
    final snap = await FirebaseFirestore.instance
        .collection('prices')
        .where('timestamp', isLessThan: oneHourAgo)
        .get();
    final batch = FirebaseFirestore.instance.batch();
    for (final d in snap.docs) batch.delete(d.reference);
    await batch.commit();
    return snap.docs.length;
  }

  /// 비활성 종목의 현재가 데이터 정리
  Future<Map<String, dynamic>> cleanupInactiveStocks(List<String> activeStocks) async {
    try {
      if (activeStocks.isEmpty) {
        return {'deleted_records': 0, 'active_stocks_count': 0};
      }
      final snap = await FirebaseFirestore.instance.collection('prices').get();
      final toDelete = snap.docs.where((d) => !activeStocks.contains(d.id)).toList();
      final batch = FirebaseFirestore.instance.batch();
      for (final d in toDelete) batch.delete(d.reference);
      await batch.commit();
      return {'deleted_records': toDelete.length, 'active_stocks_count': activeStocks.length};
    } catch (e) {
      print('❌ 비활성 종목 현재가 데이터 정리 실패: $e');
      return {'deleted_records': 0, 'active_stocks_count': activeStocks.length, 'error': e.toString()};
    }
  }

  /// 오래된 현재가 데이터 정리 (1시간 이상) - Map 반환
  Future<Map<String, dynamic>> cleanupOldCurrentPriceData() async {
    try {
      final oneHourAgo = DateTime.now().millisecondsSinceEpoch - (60 * 60 * 1000);
      final snap = await FirebaseFirestore.instance
          .collection('prices')
          .where('timestamp', isLessThan: oneHourAgo)
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs) batch.delete(d.reference);
      await batch.commit();
      return {'deleted_records': snap.docs.length, 'cutoff_timestamp': oneHourAgo};
    } catch (e) {
      print('❌ 오래된 현재가 데이터 정리 실패: $e');
      return {'deleted_records': 0, 'cutoff_timestamp': 0, 'error': e.toString()};
    }
  }

  /// 현재가 데이터 통계 조회 (Firestore)
  Future<Map<String, dynamic>> getCurrentPriceStats() async {
    final snap = await FirebaseFirestore.instance.collection('prices').get();
    return {
      'total_records': snap.docs.length,
      'unique_stocks': snap.docs.length,
    };
  }

  /// 모든 현재가 데이터 조회 (Firestore)
  Future<List<Map<String, dynamic>>> getAllCurrentPrices() async {
    final snap = await FirebaseFirestore.instance.collection('prices').get();
    return snap.docs.map((d) => d.data()).toList();
  }

  /// 특정 종목의 현재가 통계 (Firestore)
  Future<Map<String, dynamic>> getStockCurrentPriceStats(String stockCode) async {
    final doc = await _doc(stockCode).get();
    if (!doc.exists) {
      return {'stock_code': stockCode, 'has_data': false};
    }
    final data = doc.data()!;
    return {
      'stock_code': stockCode,
      'has_data': true,
      'current_price': data['current_price'],
      'change_rate': data['change_rate'],
      'volume': data['volume'],
      'timestamp': data['timestamp'],
    };
  }

  /// 현재가 데이터 백업/복원/검증 (Firestore)
  Future<Map<String, dynamic>> exportCurrentPrice({ List<String>? stockCodes, String? market }) async {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection('prices');
    if (stockCodes != null && stockCodes.isNotEmpty) {
      final list = <Map<String, dynamic>>[];
      for (final code in stockCodes) {
        final d = await _doc(code).get();
        if (d.exists) list.add(d.data()!);
      }
      return {'export_date': DateTime.now().toIso8601String(), 'data_count': list.length, 'current_price_data': list};
    }
    if (market != null) q = q.where('market', isEqualTo: market);
    final snap = await q.get();
    return {
      'export_date': DateTime.now().toIso8601String(),
      'data_count': snap.docs.length,
      'current_price_data': snap.docs.map((d) => d.data()).toList(),
    };
  }

  Future<void> importCurrentPrice(Map<String, dynamic> exportData) async {
    final list = (exportData['current_price_data'] as List?) ?? [];
    if (list.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final e in list) {
      final m = Map<String, dynamic>.from(e as Map);
      final code = (m['stock_code'] ?? '').toString();
      if (code.isEmpty) continue;
      batch.set(_doc(code), m, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<List<String>> validateCurrentPriceData() async {
    final errors = <String>[];
    final snap = await FirebaseFirestore.instance.collection('prices').get();
    for (final d in snap.docs) {
      final m = d.data();
      if (m['current_price'] == null || m['prev_close'] == null || m['volume'] == null) {
        errors.add('${d.id}: 필수 필드 누락');
      }
    }
    return errors;
  }

  /// 활성 종목 현재가 조회(Firestore). whereIn 제약으로 10개씩 청크 처리
  Future<List<Map<String, dynamic>>> getActiveStocksCurrentPrices({int limit = 500}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];
    final watch = await _userCol(uid, 'watchlist').get();
    final hold = await _userCol(uid, 'holdings').get();
    final codes = <String>{
      ...watch.docs.map((d) => (d.data()['stock_code'] ?? d.id) as String),
      ...hold.docs.map((d) => (d.data()['pdno'] ?? d.id) as String),
    }.toList();
    if (codes.isEmpty) return [];

    final results = <Map<String, dynamic>>[];
    for (int i = 0; i < codes.length; i += 10) {
      final chunk = codes.sublist(i, i + 10 > codes.length ? codes.length : i + 10);
      final snap = await FirebaseFirestore.instance
          .collection('prices')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      results.addAll(snap.docs.map((d) => d.data()));
      if (results.length >= limit) break;
    }

    results.sort((a, b) => ((b['timestamp'] ?? 0) as int).compareTo((a['timestamp'] ?? 0) as int));
    if (results.length > limit) {
      return results.sublist(0, limit);
    }
    return results;
  }

  /// 통계 정보(Firestore) - 간단 집계
  Future<Map<String, dynamic>> getStats() async {
    final snap = await FirebaseFirestore.instance.collection('prices').get();
    if (snap.docs.isEmpty) {
      return {
        'total_records': 0,
        'unique_stocks': 0,
        'latest_timestamp': 0,
        'oldest_timestamp': 0,
        'avg_price': '0.00',
        'avg_records_per_stock': '0',
      };
    }
    int latest = 0;
    int oldest = 1 << 62;
    double sumPrice = 0.0;
    int countPrice = 0;
    for (final d in snap.docs) {
      final m = d.data();
      final ts = (m['timestamp'] as int?) ?? 0;
      if (ts > latest) latest = ts;
      if (ts < oldest) oldest = ts;
      final cp = (m['current_price'] as num?)?.toDouble();
      if (cp != null && cp > 0) {
        sumPrice += cp;
        countPrice += 1;
      }
    }
    final total = snap.docs.length;
    final unique = total; // 종목당 1 문서 가정
    final avg = countPrice > 0 ? (sumPrice / countPrice) : 0.0;
    return {
      'total_records': total,
      'unique_stocks': unique,
      'latest_timestamp': latest,
      'oldest_timestamp': oldest == (1 << 62) ? 0 : oldest,
      'avg_price': avg.toStringAsFixed(2),
      'avg_records_per_stock': unique > 0 ? (total / unique).toStringAsFixed(2) : '0',
    };
  }
}
