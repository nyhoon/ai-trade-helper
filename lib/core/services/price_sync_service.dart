import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/stock_master_parser.dart';
import '../trading/market_time_validator.dart';

/// 현재가 응답(국내/해외 혼합)을 정규화하여 Firestore `prices/{symbol}`에 업서트하는 서비스
class PriceSyncService {
  PriceSyncService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<void> upsertPrice({
    required String symbol,
    required Map<String, dynamic> raw, // KIS 등 원본 응답(Map)
    String? market,
    String? stockName,
    int? timestampMs,
  }) async {
    final normalized = _normalize(symbol: symbol, raw: raw, market: market, stockName: stockName, timestampMs: timestampMs);
    final ref = _db.collection('prices').doc(symbol);
    await ref.set(normalized, SetOptions(merge: true));
  }

  Map<String, dynamic> _normalize({
    required String symbol,
    required Map<String, dynamic> raw,
    String? market,
    String? stockName,
    int? timestampMs,
  }) {
    final String resolvedMarket = (market?.trim().isNotEmpty == true)
        ? market!.trim()
        : MarketTimeValidator.instance.getMarketFromSymbol(symbol);

    String resolvedName = (stockName?.trim().isNotEmpty == true) ? stockName!.trim() : '';
    if (resolvedName.isEmpty) {
      try {
        final info = StockMasterParser().getStockInfo(symbol);
        resolvedName = (info?['name']?.toString() ?? '').trim();
      } catch (_) {}
    }

    // 국내 KIS 키
    final domestic = _Domestic(raw);
    // 해외(미국) 일반 키
    final overseas = _Overseas(raw);

    double? currentPrice = domestic.stckPrpr ?? overseas.last;
    double? prevClose = domestic.stckPrdyClpr ?? overseas.prevClose;
    double? changeAmount = domestic.prdyVrss ?? overseas.change;
    double? changeRate = domestic.prdyCtrt ?? overseas.changeRate;
    double? high = domestic.stckHgpr ?? overseas.high;
    double? low = domestic.stckLwpr ?? overseas.low;
    double? open = domestic.stckOprc ?? overseas.open;
    int? volume = domestic.acmlVol ?? overseas.volume;
    double? tradeAmount = domestic.tradeAmount ?? overseas.tradeAmount;
    double? marketCap = domestic.marketCap ?? overseas.marketCap;
    double? per = domestic.per ?? overseas.per;
    double? pbr = domestic.pbr ?? overseas.pbr;
    final int ts = timestampMs ?? _parseInt(raw['timestamp']) ?? DateTime.now().millisecondsSinceEpoch;

    return {
      'stock_name': resolvedName,
      'market': resolvedMarket,
      'current_price': currentPrice ?? 0,
      'prev_close': prevClose ?? 0,
      'change_amount': changeAmount ?? ((currentPrice != null && prevClose != null) ? currentPrice - prevClose : 0),
      'change_rate': changeRate ?? ((currentPrice != null && prevClose != null && prevClose != 0) ? ((currentPrice - prevClose) / prevClose) * 100 : 0),
      'volume': volume ?? 0,
      'trade_amount': tradeAmount ?? 0,
      'high_price': high ?? 0,
      'low_price': low ?? 0,
      'open_price': open ?? 0,
      'market_cap': marketCap,
      'per': per,
      'pbr': pbr,
      'timestamp': ts,
    };
  }

  static double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString().trim();
    if (s.isEmpty || s == '-' || s.toUpperCase() == 'NULL') return null;
    return double.tryParse(s);
  }

  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    final s = v.toString().trim();
    if (s.isEmpty || s == '-' || s.toUpperCase() == 'NULL') return null;
    return int.tryParse(s);
  }
}

class _Domestic {
  _Domestic(this.raw);
  final Map<String, dynamic> raw;

  double? get stckPrpr => PriceSyncService._parseDouble(raw['stck_prpr']);
  double? get stckPrdyClpr => PriceSyncService._parseDouble(raw['stck_prdy_clpr']);
  double? get prdyVrss => PriceSyncService._parseDouble(raw['prdy_vrss']);
  double? get prdyCtrt => PriceSyncService._parseDouble(raw['prdy_ctrt']);
  double? get stckHgpr => PriceSyncService._parseDouble(raw['stck_hgpr']);
  double? get stckLwpr => PriceSyncService._parseDouble(raw['stck_lwpr']);
  double? get stckOprc => PriceSyncService._parseDouble(raw['stck_oprc']);
  int? get acmlVol => PriceSyncService._parseInt(raw['acml_vol']);
  double? get tradeAmount => PriceSyncService._parseDouble(raw['acc_trdval'] ?? raw['acc_trdvol_value']);
  double? get marketCap => PriceSyncService._parseDouble(raw['list_trdval'] ?? raw['market_cap']);
  double? get per => PriceSyncService._parseDouble(raw['per']);
  double? get pbr => PriceSyncService._parseDouble(raw['pbr']);
}

class _Overseas {
  _Overseas(this.raw);
  final Map<String, dynamic> raw;

  double? get last => PriceSyncService._parseDouble(raw['last'] ?? raw['current_price'] ?? raw['close']);
  double? get prevClose => PriceSyncService._parseDouble(raw['previousClose'] ?? raw['prevClose'] ?? raw['prdy_close']);
  double? get change => PriceSyncService._parseDouble(raw['change'] ?? raw['chng']);
  double? get changeRate => PriceSyncService._parseDouble(raw['changeRate'] ?? raw['pctChange']);
  double? get high => PriceSyncService._parseDouble(raw['high']);
  double? get low => PriceSyncService._parseDouble(raw['low']);
  double? get open => PriceSyncService._parseDouble(raw['open']);
  int? get volume => PriceSyncService._parseInt(raw['volume']);
  double? get tradeAmount => PriceSyncService._parseDouble(raw['totalValue'] ?? raw['tradeAmount']);
  double? get marketCap => PriceSyncService._parseDouble(raw['marketCap']);
  double? get per => PriceSyncService._parseDouble(raw['pe'] ?? raw['per']);
  double? get pbr => PriceSyncService._parseDouble(raw['pb'] ?? raw['pbr']);
}


