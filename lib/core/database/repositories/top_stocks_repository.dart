import 'package:cloud_firestore/cloud_firestore.dart';
import '../../trading/market_time_validator.dart';

/// 상위 점수 종목 전용 Repository
/// 실시간 점수 계산 결과를 DB에 저장하고 상위 종목을 빠르게 조회
class TopStocksRepository {
  CollectionReference<Map<String, dynamic>> _col() => FirebaseFirestore.instance.collection('top_stocks');

  /// 상위 점수 종목 테이블 생성
  Future<void> createTopStocksTable() async {
    // Firestore 사용: 테이블 생성 불필요
    print('✅ 상위 점수 종목 저장은 Firestore 컬렉션(top_stocks)을 사용합니다');
  }

  /// 상위 점수 종목 저장/업데이트
  Future<int> saveTopStock({
    required String stockCode,
    required String stockName,
    required String market,
    required double score,
    required double currentPrice,
    double priceChange = 0,
    double priceChangeRate = 0,
    int volume = 0,
    double volumeRatio = 1.0,
    required int rank,
    double? tradingAmount,
    String? tradingCurrency,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _col().doc(stockCode).set({
      'stock_code': stockCode,
      'stock_name': stockName,
      'market': MarketTimeValidator.instance.getMarketFromSymbol(stockCode),
      'score': score,
      'current_price': currentPrice,
      'price_change': priceChange,
      'price_change_rate': priceChangeRate,
      'volume': volume,
      'volume_ratio': volumeRatio,
      'trading_amount': tradingAmount ?? 0,
      'trading_currency': tradingCurrency ?? (market == 'KOSPI' || market == 'KOSDAQ' ? 'KRW' : 'USD'),
      'rank': rank,
      'last_updated': now,
      'created_at': now,
      'updated_at': now,
    }, SetOptions(merge: true));
    return 1;
  }

  /// 여러 상위 점수 종목 일괄 저장/업데이트
  Future<void> saveManyTopStocks(List<Map<String, dynamic>> stocks) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = FirebaseFirestore.instance.batch();
    for (final stock in stocks) {
      final String code = stock['stockCode'];
      batch.set(_col().doc(code), {
        'stock_code': code,
        'stock_name': stock['stockName'],
        'market': MarketTimeValidator.instance.getMarketFromSymbol(code),
        'score': stock['score'],
        'current_price': stock['currentPrice'],
        'price_change': stock['priceChange'] ?? 0,
        'price_change_rate': stock['priceChangeRate'] ?? 0,
        'volume': stock['volume'] ?? 0,
        'volume_ratio': stock['volumeRatio'] ?? 1.0,
        'trading_amount': stock['tradingAmount'] ?? 0,
        'trading_currency': stock['tradingCurrency'] ?? 'KRW',
        'rank': stock['rank'],
        'last_updated': now,
        'created_at': now,
        'updated_at': now,
      }, SetOptions(merge: true));
    }
    await batch.commit();
    print('📊 상위 점수 종목 ${stocks.length}개 저장 완료(Firestore)');
  }

  /// 저장된 market 필드 일괄 정규화 (코드 기반 재판별)
  Future<int> normalizeStoredMarkets() async {
    // Firestore 전환으로 불필요. 필요 시 별도 배치 구현.
    return 0;
  }

  /// 상위 점수 종목 조회 (점수 기준 정렬)
  Future<List<Map<String, dynamic>>> getTopStocks({
    int limit = 50,
    double minScore = 0.0,
    String? market,
    int? maxAgeMinutes,
    double? minTradingAmountKrw,
    double? minTradingAmountUsd,
  }) async {
    Query<Map<String, dynamic>> q = _col().where('score', isGreaterThanOrEqualTo: minScore);
    if (market != null) q = q.where('market', isEqualTo: market);
    // 거래대금 필터는 시장별 통화 차이를 고려해 클라이언트 필터 또는 서버에서 계산된 결과 사용 권장
    if (maxAgeMinutes != null) {
      final cutoff = DateTime.now().millisecondsSinceEpoch - maxAgeMinutes * 60 * 1000;
      q = q.where('last_updated', isGreaterThanOrEqualTo: cutoff);
    }
    q = q.orderBy('score', descending: true).orderBy('rank').limit(limit);
    final snap = await q.get();
    return snap.docs.map((d) {
      final row = d.data();
      return {
        'stockCode': row['stock_code'],
        'stockName': row['stock_name'],
        'market': row['market'],
        'score': (row['score'] as num?)?.toDouble() ?? 0.0,
        'currentPrice': (row['current_price'] as num?)?.toDouble() ?? 0.0,
        'priceChange': (row['price_change'] as num?)?.toDouble() ?? 0.0,
        'priceChangeRate': (row['price_change_rate'] as num?)?.toDouble() ?? 0.0,
        'volume': row['volume'] ?? 0,
        'volumeRatio': (row['volume_ratio'] as num?)?.toDouble() ?? 1.0,
        'tradingAmount': (row['trading_amount'] as num?)?.toDouble() ?? 0.0,
        'tradingCurrency': row['trading_currency'],
        'rank': row['rank'] ?? 0,
        'lastUpdated': DateTime.fromMillisecondsSinceEpoch((row['last_updated'] as int?) ?? 0),
      };
    }).toList();
  }

  /// 특정 종목의 점수 조회
  Future<Map<String, dynamic>?> getStockScore(String stockCode) async {
    final doc = await _col().doc(stockCode).get();
    if (!doc.exists) return null;
    final row = doc.data()!;
    return {
      'stockCode': row['stock_code'],
      'stockName': row['stock_name'],
      'market': row['market'],
      'score': row['score'],
      'currentPrice': row['current_price'],
      'priceChange': row['price_change'],
      'priceChangeRate': row['price_change_rate'],
      'volume': row['volume'],
      'volumeRatio': row['volume_ratio'],
      'rank': row['rank'],
      'lastUpdated': DateTime.fromMillisecondsSinceEpoch((row['last_updated'] as int?) ?? 0),
    };
  }

  /// 시장별 상위 점수 종목 조회
  Future<List<Map<String, dynamic>>> getTopStocksByMarket({
    required String market,
    int limit = 50,
    double minScore = 0.0,
    double? minTradingAmountKrw,
    double? minTradingAmountUsd,
  }) async {
    return await getTopStocks(
      limit: limit,
      minScore: minScore,
      market: market,
      minTradingAmountKrw: minTradingAmountKrw,
      minTradingAmountUsd: minTradingAmountUsd,
    );
  }

  /// 점수 범위별 종목 조회
  Future<List<Map<String, dynamic>>> getStocksByScoreRange({
    required double minScore,
    required double maxScore,
    int limit = 100,
    String? market,
  }) async {
    Query<Map<String, dynamic>> q = _col()
        .where('score', isGreaterThanOrEqualTo: minScore)
        .where('score', isLessThanOrEqualTo: maxScore);
    if (market != null) q = q.where('market', isEqualTo: market);
    q = q.orderBy('score', descending: true).limit(limit);
    final snap = await q.get();
    return snap.docs.map((d) {
      final row = d.data();
      return {
        'stockCode': row['stock_code'],
        'stockName': row['stock_name'],
        'market': row['market'],
        'score': row['score'],
        'currentPrice': row['current_price'],
        'priceChange': row['price_change'],
        'priceChangeRate': row['price_change_rate'],
        'volume': row['volume'],
        'volumeRatio': row['volume_ratio'],
        'rank': row['rank'],
        'lastUpdated': DateTime.fromMillisecondsSinceEpoch((row['last_updated'] as int?) ?? 0),
      };
    }).toList();
  }

  /// 상위 점수 종목 통계 조회
  Future<Map<String, dynamic>> getTopStocksStatistics() async {
    // 서버 집계 권장. 여기서는 최소 통계만 제공
    final snap = await _col().get();
    final totalCount = snap.docs.length;
    double maxScore = 0;
    double minScore = 1e9;
    double sumScore = 0;
    for (final d in snap.docs) {
      final s = (d.data()['score'] as num?)?.toDouble() ?? 0.0;
      sumScore += s;
      if (s > maxScore) maxScore = s;
      if (s < minScore) minScore = s;
    }
    final avgScore = totalCount > 0 ? sumScore / totalCount : 0.0;
    return {
      'total': {
        'count': totalCount,
        'avgScore': avgScore,
        'maxScore': maxScore,
        'minScore': totalCount > 0 ? minScore : 0.0,
        'lastUpdateTime': null,
      },
      'byMarket': [],
      'distribution': [],
    };
  }

  /// 오래된 데이터 정리 (30일 이상)
  Future<int> cleanupOldData({int daysOld = 30}) async {
    final cutoff = DateTime.now().millisecondsSinceEpoch - daysOld * 24 * 60 * 60 * 1000;
    final snap = await _col().where('last_updated', isLessThan: cutoff).get();
    final batch = FirebaseFirestore.instance.batch();
    for (final d in snap.docs) batch.delete(d.reference);
    await batch.commit();
    print('🧹 오래된 상위 점수 데이터 ${snap.docs.length}개 정리 완료(Firestore)');
    return snap.docs.length;
  }

  /// 모든 상위 점수 종목 삭제
  Future<int> deleteAllTopStocks() async {
    final snap = await _col().get();
    final batch = FirebaseFirestore.instance.batch();
    for (final d in snap.docs) batch.delete(d.reference);
    await batch.commit();
    print('🗑️ 모든 상위 점수 종목 삭제 완료(Firestore)');
    return snap.docs.length;
  }

  /// 특정 종목 삭제
  Future<int> deleteTopStock(String stockCode) async {
    await _col().doc(stockCode).delete();
    return 1;
  }

  /// 테이블 존재 여부 확인
  Future<bool> tableExists() async {
    // Firestore 사용 시 테이블 존재 개념 불필요
    return true;
  }
}
