import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import 'stock_master_parser.dart';
import '../trading/market_time_validator.dart';

/// 로컬 SQLite → Firestore 일회성 마이그레이션 유틸
/// - stock_master → stock_master/{symbol}
/// - watchlist → users/{uid}/watchlist/{symbol}
/// - holdings → users/{uid}/holdings/{symbol}
/// - chart_data(요약) → charts/{symbol}
class FirebaseMigrationService {
  final FirebaseFirestore _db;
  final DatabaseHelper _local;

  FirebaseMigrationService({FirebaseFirestore? firestore, DatabaseHelper? local})
      : _db = firestore ?? FirebaseFirestore.instance,
        _local = local ?? DatabaseHelper();

  Future<void> migrateAll({required String uid}) async {
    final database = await _local.database;
    // 권한/프로젝트 연결 점검용 핑
    try {
      await _db.collection('debug').doc('ping').set({'ts': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      // ignore: avoid_print
      print('✅ Firestore write ping 성공');
    } catch (e) {
      // ignore: avoid_print
      print('❌ Firestore write ping 실패: $e');
    }

    final masterCount = await _migrateStockMaster(database);
    if (masterCount == 0) {
      final populated = await _populateStockMasterFromParser();
      // ignore: avoid_print
      print('ℹ️ StockMasterParser 기반 업로드: $populated건');
    }
    await _migrateWatchlist(database, uid);
    await _migrateHoldings(database, uid);
    await _migrateCurrentPrices(database);
    await _migrateChartData(database);
  }

  Future<int> _migrateStockMaster(Database db) async {
    List<Map<String, Object?>> rows = [];
    try {
      rows = await db.rawQuery('SELECT stock_code, stock_name, market, sector, is_active, created_at, updated_at FROM stock_master');
    } catch (e) {
      // ignore: avoid_print
      print('ℹ️ stock_master 테이블 없음 또는 조회 실패: $e');
      return 0;
    }
    // ignore: avoid_print
    print('📦 stock_master 마이그레이션 대상: ${rows.length}건');
    final batch = _db.batch();
    for (final r in rows) {
      final symbol = (r['stock_code'] ?? '').toString();
      if (symbol.isEmpty) continue;
      final ref = _db.collection('stock_master').doc(symbol);
      batch.set(ref, {
        'stock_name': r['stock_name'],
        'market': r['market'],
        'sector': r['sector'],
        'is_active': r['is_active'] ?? 1,
        'created_at': r['created_at'],
        'updated_at': r['updated_at'],
      }, SetOptions(merge: true));
    }
    await batch.commit();
    // ignore: avoid_print
    print('✅ stock_master 마이그레이션 완료 (${rows.length}건)');
    return rows.length;
  }

  Future<void> _migrateWatchlist(Database db, String uid) async {
    // master map으로 market/name 보정
    final Map<String, String> codeToMarket = {};
    final Map<String, String> codeToName = {};
    try {
      final masterRows = await db.rawQuery('SELECT stock_code, stock_name, market FROM stock_master');
      for (final r in masterRows) {
        final code = (r['stock_code'] ?? '').toString();
        if (code.isEmpty) continue;
        final name = (r['stock_name'] ?? '').toString();
        final market = (r['market'] ?? '').toString();
        if (name.isNotEmpty) codeToName[code] = name;
        if (market.isNotEmpty) codeToMarket[code] = market;
      }
    } catch (_) {}

    List<Map<String, Object?>> rows = [];
    try {
      rows = await db.rawQuery('SELECT stock_code, stock_name, market, added_at, memo, is_active FROM watchlist');
    } catch (e) {
      // ignore: avoid_print
      print('ℹ️ watchlist 테이블 없음 또는 조회 실패: $e');
      return;
    }
    // ignore: avoid_print
    print('📦 watchlist 마이그레이션 대상: ${rows.length}건');
    final batch = _db.batch();
    for (final r in rows) {
      final symbol = (r['stock_code'] ?? '').toString();
      if (symbol.isEmpty) continue;

      // denormalize: name/market 보정
      String stockName = (r['stock_name'] as String?)?.toString() ?? '';
      String market = (r['market'] as String?)?.toString() ?? '';
      if (stockName.isEmpty) {
        stockName = codeToName[symbol] ?? '';
        if (stockName.isEmpty) {
          try {
            final parser = StockMasterParser();
            final info = parser.getStockInfo(symbol);
            if (info != null) stockName = info['name']?.toString() ?? '';
          } catch (_) {}
        }
      }
      if (market.isEmpty || market == 'UNKNOWN') {
        market = _resolveMarketSymbol(symbol: symbol, currentMarket: market, masterMap: codeToMarket);
      }

      final ref = _db.collection('users').doc(uid).collection('watchlist').doc(symbol);
      batch.set(ref, {
        'stock_name': stockName,
        'market': market,
        'added_at': r['added_at'],
        'memo': r['memo'] ?? '',
        'is_active': r['is_active'] ?? 1,
      }, SetOptions(merge: true));
    }
    await batch.commit();
    // ignore: avoid_print
    print('✅ watchlist 마이그레이션 완료 (${rows.length}건)');
  }

  Future<void> _migrateHoldings(Database db, String uid) async {
    // 미리 stock_master에서 market 맵을 구성하여 UNKNOWN 보정
    final Map<String, String> stockCodeToMarket = {};
    try {
      final masterRows = await db.rawQuery('SELECT stock_code, market FROM stock_master');
      for (final r in masterRows) {
        final code = (r['stock_code'] ?? '').toString();
        final market = (r['market'] ?? '').toString();
        if (code.isNotEmpty && market.isNotEmpty) {
          stockCodeToMarket[code] = market;
        }
      }
      // ignore: avoid_print
      print('ℹ️ stock_master 로드 완료: ${stockCodeToMarket.length}건');
    } catch (_) {
      // ignore: avoid_print
      print('ℹ️ stock_master 로드 실패(보정 없이 진행)');
    }
    List<Map<String, Object?>> rows = [];
    try {
      rows = await db.rawQuery('SELECT pdno, prdt_name, market, hldg_qty, pchs_avg_pric, prpr, evlu_amt, evlu_pfls_amt, evlu_pfls_rt, updated_at FROM holdings');
    } catch (e) {
      // ignore: avoid_print
      print('ℹ️ holdings 테이블 없음 또는 조회 실패: $e');
      return;
    }
    // ignore: avoid_print
    print('📦 holdings 마이그레이션 대상: ${rows.length}건');
    final batch = _db.batch();
    for (final r in rows) {
      final symbol = (r['pdno'] ?? '').toString();
      if (symbol.isEmpty) continue;
      final String market = _resolveMarketSymbol(
        symbol: symbol,
        currentMarket: r['market'] as String?,
        masterMap: stockCodeToMarket,
      );
      final ref = _db.collection('users').doc(uid).collection('holdings').doc(symbol);
      batch.set(ref, {
        'prdt_name': r['prdt_name'],
        'market': market,
        'hldg_qty': r['hldg_qty'],
        'pchs_avg_pric': r['pchs_avg_pric'],
        'prpr': r['prpr'],
        'evlu_amt': r['evlu_amt'],
        'evlu_pfls_amt': r['evlu_pfls_amt'],
        'evlu_pfls_rt': r['evlu_pfls_rt'],
        'updated_at': r['updated_at'],
      }, SetOptions(merge: true));
    }
    await batch.commit();
    // ignore: avoid_print
    print('✅ holdings 마이그레이션 완료 (${rows.length}건)');
  }

  Future<void> _migrateChartData(Database db) async {
    try {
      final rows = await db.rawQuery('SELECT symbol, ohlcv_json, indicators_json, updated_at FROM chart_data');
      // ignore: avoid_print
      print('📦 chart_data 마이그레이션 대상: ${rows.length}건');
      final batch = _db.batch();
      for (final r in rows) {
        final symbol = (r['symbol'] ?? '').toString();
        if (symbol.isEmpty) continue;
        final ref = _db.collection('charts').doc(symbol);
        batch.set(ref, {
          'symbol': symbol,
          'ohlcv': r['ohlcv_json'],
          'indicators': r['indicators_json'],
          'updatedAt': r['updated_at'],
        }, SetOptions(merge: true));
      }
      await batch.commit();
      // ignore: avoid_print
      print('✅ chart_data 마이그레이션 완료 (${rows.length}건)');
    } catch (_) {
      // chart_data 테이블이 없을 수 있음 → 무시
      // ignore: avoid_print
      print('ℹ️ chart_data 테이블 없음 - 스킵');
    }
  }

  /// 현재가 테이블 → Firestore prices/{symbol}
  Future<void> _migrateCurrentPrices(Database db) async {
    List<Map<String, Object?>> rows = [];
    try {
      rows = await db.rawQuery('''
        SELECT stock_code, market, current_price, prev_close, change_amount, change_rate,
               volume, trade_amount, high_price, low_price, open_price, market_cap, per, pbr,
               timestamp
        FROM current_price
      ''');
    } catch (e) {
      // ignore: avoid_print
      print('ℹ️ current_price 테이블 없음 또는 조회 실패: $e');
      return;
    }
    // master 보정
    final Map<String, String> codeToName = {};
    final Map<String, String> codeToMarket = {};
    try {
      final masterRows = await db.rawQuery('SELECT stock_code, stock_name, market FROM stock_master');
      for (final r in masterRows) {
        final code = (r['stock_code'] ?? '').toString();
        if (code.isEmpty) continue;
        final name = (r['stock_name'] ?? '').toString();
        final market = (r['market'] ?? '').toString();
        if (name.isNotEmpty) codeToName[code] = name;
        if (market.isNotEmpty) codeToMarket[code] = market;
      }
    } catch (_) {}

    // ignore: avoid_print
    print('📦 current_price 마이그레이션 대상: ${rows.length}건');
    final batch = _db.batch();
    for (final r in rows) {
      final symbol = (r['stock_code'] ?? '').toString();
      if (symbol.isEmpty) continue;
      String market = (r['market'] as String?)?.toString() ?? '';
      if (market.isEmpty || market == 'UNKNOWN') {
        market = _resolveMarketSymbol(symbol: symbol, currentMarket: market, masterMap: codeToMarket);
      }
      String stockName = codeToName[symbol] ?? '';
      if (stockName.isEmpty) {
        try {
          final parser = StockMasterParser();
          final info = parser.getStockInfo(symbol);
          if (info != null) stockName = info['name']?.toString() ?? '';
        } catch (_) {}
      }
      final ref = _db.collection('prices').doc(symbol);
      batch.set(ref, {
        'stock_name': stockName,
        'market': market,
        'current_price': r['current_price'],
        'prev_close': r['prev_close'],
        'change_amount': r['change_amount'],
        'change_rate': r['change_rate'],
        'volume': r['volume'],
        'trade_amount': r['trade_amount'],
        'high_price': r['high_price'],
        'low_price': r['low_price'],
        'open_price': r['open_price'],
        'market_cap': r['market_cap'],
        'per': r['per'],
        'pbr': r['pbr'],
        'timestamp': r['timestamp'],
      }, SetOptions(merge: true));
    }
    await batch.commit();
    // ignore: avoid_print
    print('✅ current_price 마이그레이션 완료 (${rows.length}건)');
  }

  /// 종목코드로 시장 판별(정확도 높은 순으로 체인)
  String _resolveMarketSymbol({
    required String symbol,
    String? currentMarket,
    Map<String, String>? masterMap,
  }) {
    final String trimmed = symbol.trim().toUpperCase();
    final String? current = currentMarket?.toString();
    if (current != null && current.isNotEmpty && current != 'UNKNOWN') {
      return current;
    }
    // 1) 로컬 masterMap 우선
    final String? fromLocal = masterMap?[trimmed];
    if (fromLocal != null && fromLocal.isNotEmpty) {
      return fromLocal;
    }
    // 2) StockMasterParser (전역 마스터)
    try {
      final parser = StockMasterParser();
      if (parser.isInitialized) {
        if (parser.getKospiStockCodes().contains(trimmed)) return 'KOSPI';
        if (parser.getKosdaqStockCodes().contains(trimmed)) return 'KOSDAQ';
        if (RegExp(r'^[A-Z]{1,6}$').hasMatch(trimmed)) {
          if (parser.getNasdaqStockCodes().contains(trimmed)) return 'NASDAQ';
          if (parser.getNyseStockCodes().contains(trimmed)) return 'NYSE';
        }
      }
    } catch (_) {}
    // 3) MarketTimeValidator 휴리스틱
    try {
      final m = MarketTimeValidator.instance.getMarketFromSymbol(trimmed);
      if (m.isNotEmpty) return m;
    } catch (_) {}
    // 4) 간단 휴리스틱
    if (RegExp(r'^[A-Z]{1,5}$').hasMatch(trimmed)) return 'NASDAQ';
    if (trimmed.length == 6 && RegExp(r'^\d+$').hasMatch(trimmed)) {
      return trimmed.startsWith('0') ? 'KOSPI' : 'KOSDAQ';
    }
    return 'UNKNOWN';
  }

  /// StockMasterParser에서 모든 마스터를 읽어 Firestore에 업로드
  Future<int> _populateStockMasterFromParser() async {
    int count = 0;
    try {
      final parser = StockMasterParser();
      if (!parser.isInitialized) {
        // ignore: avoid_print
        print('ℹ️ StockMasterParser 미초기화 - 건너뜀');
        return 0;
      }

      final batch = _db.batch();

      void addCodes(Iterable<String> codes, String market) {
        for (final code in codes) {
          final info = parser.getStockInfo(code) ?? {};
          final name = (info['name']?.toString() ?? '').trim();
          final ref = _db.collection('stock_master').doc(code);
          batch.set(ref, {
            'stock_name': name.isNotEmpty ? name : code,
            'market': market,
            'sector': info['sector'],
            'is_active': 1,
            'created_at': DateTime.now().millisecondsSinceEpoch,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          }, SetOptions(merge: true));
          count++;
        }
      }

      addCodes(parser.getKospiStockCodes(), 'KOSPI');
      addCodes(parser.getKosdaqStockCodes(), 'KOSDAQ');
      addCodes(parser.getNasdaqStockCodes(), 'NASDAQ');
      addCodes(parser.getNyseStockCodes(), 'NYSE');

      await batch.commit();
      // ignore: avoid_print
      print('✅ StockMasterParser 기반 마스터 업로드 완료: $count건');
    } catch (e) {
      // ignore: avoid_print
      print('❌ StockMasterParser 업로드 실패: $e');
    }
    return count;
  }
}


