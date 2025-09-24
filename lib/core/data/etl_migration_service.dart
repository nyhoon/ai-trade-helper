import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../database/repositories/watchlist_repository.dart';
import '../database/repositories/holdings_repository.dart';
import '../database/repositories/historical_data_repository.dart';
import '../database/repositories/current_price_repository.dart';

/// 일회성 ETL: 로컬 DB → Firestore 동기화 및 로컬 정리
class EtlMigrationService {
  EtlMigrationService._();
  static final EtlMigrationService instance = EtlMigrationService._();

  final WatchlistRepository _watchlistRepo = WatchlistRepository();
  final HoldingsRepository _holdingsRepo = HoldingsRepository();
  final HistoricalDataRepository _historicalRepo = HistoricalDataRepository();
  final CurrentPriceRepository _priceRepo = CurrentPriceRepository();

  Future<void> runEtlIfNeeded({bool force = false}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (kDebugMode) print('ETL skipped: user not authenticated');
      return;
    }
    // 간단 방어: 강제 실행 외에는 앱 레벨에서 1회만 호출하도록 관리(별도 플래그 저장은 생략)
    await _migrateWatchlist();
    await _migrateHoldings();
    await _migrateCurrentPrices();
    await _migrateCharts(keepDays: 100);
    await _cleanupLocalDb();
    if (kDebugMode) print('✅ ETL completed');
  }

  Future<void> _migrateWatchlist() async {
    try {
      final Database db = await DatabaseHelper.instance.database;
      final rows = await db.query('watchlist');
      if (rows.isEmpty) return;
      final List<Map<String, String>> stocks = rows.map((r) => <String, String>{
            'stock_code': (r['stock_code'] ?? '').toString(),
            'stock_name': (r['stock_name'] ?? '').toString(),
            'memo': (r['memo'] ?? '').toString(),
          }).where((m) => (m['stock_code'] ?? '').isNotEmpty).toList();
      if (stocks.isNotEmpty) {
        await _watchlistRepo.addMultipleToWatchlist(stocks);
        if (kDebugMode) print('📤 ETL watchlist → Firestore: ${stocks.length}개');
      }
    } catch (e) {
      if (kDebugMode) print('❌ ETL watchlist failed: $e');
    }
  }

  Future<void> _migrateHoldings() async {
    try {
      final Database db = await DatabaseHelper.instance.database;
      final rows = await db.query('holdings');
      if (rows.isEmpty) return;
      final payload = rows.map((r) => <String, dynamic>{
            'pdno': (r['pdno'] ?? '').toString(),
            'prdt_name': r['prdt_name'],
            'hldg_qty': r['hldg_qty'],
            'pchs_avg_pric': r['pchs_avg_pric'],
            'prpr': r['prpr'],
            'evlu_amt': r['evlu_amt'],
            'evlu_pfls_amt': r['evlu_pfls_amt'],
            'evlu_pfls_rt': r['evlu_pfls_rt'],
          }).where((m) => (m['pdno'] as String).isNotEmpty).toList();
      if (payload.isNotEmpty) {
        await _holdingsRepo.saveHoldings(payload);
        if (kDebugMode) print('📤 ETL holdings → Firestore: ${payload.length}개');
      }
    } catch (e) {
      if (kDebugMode) print('❌ ETL holdings failed: $e');
    }
  }

  Future<void> _migrateCurrentPrices() async {
    try {
      final Database db = await DatabaseHelper.instance.database;
      final rows = await db.query('current_price');
      if (rows.isEmpty) return;
      final list = rows.map((r) => <String, dynamic>{
            'stock_code': (r['stock_code'] ?? '').toString(),
            'market': r['market'],
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
          }).where((m) => (m['stock_code'] as String).isNotEmpty).toList();
      if (list.isNotEmpty) {
        await _priceRepo.insertMultipleCurrentPrice(list);
        if (kDebugMode) print('📤 ETL prices → Firestore: ${list.length}개');
      }
    } catch (e) {
      if (kDebugMode) print('❌ ETL prices failed: $e');
    }
  }

  Future<void> _migrateCharts({int keepDays = 100}) async {
    try {
      final Database db = await DatabaseHelper.instance.database;
      // chart_data 테이블이 없을 가능성 고려
      final exists = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='chart_data'");
      if (exists.isEmpty) return;
      final rows = await db.query('chart_data');
      if (rows.isEmpty) return;
      // 심볼별 그룹핑
      final Map<String, List<Map<String, dynamic>>> bySymbol = {};
      for (final r in rows) {
        final symbol = (r['stock_code'] ?? r['symbol'] ?? '').toString();
        if (symbol.isEmpty) continue;
        final date = (r['date'] ?? r['dt'] ?? '').toString();
        num _n(dynamic v) => (v is num) ? v : num.tryParse(v?.toString() ?? '0') ?? 0;
        final bar = <String, dynamic>{
          'date': date,
          'open': _n(r['open'] ?? r['o'] ?? 0).toDouble(),
          'high': _n(r['high'] ?? r['h'] ?? 0).toDouble(),
          'low': _n(r['low'] ?? r['l'] ?? 0).toDouble(),
          'close': _n(r['close'] ?? r['c'] ?? 0).toDouble(),
          'volume': _n(r['volume'] ?? r['v'] ?? 0).toInt(),
          'trade_amount': (r['trade_amount'] ?? r['t']) != null ? _n(r['trade_amount'] ?? r['t']).toDouble() : null,
        };
        bySymbol.putIfAbsent(symbol, () => <Map<String, dynamic>>[]).add(bar);
      }
      for (final entry in bySymbol.entries) {
        await _historicalRepo.upsertDailyBars(
          stockCode: entry.key,
          market: '',
          bars: entry.value,
          keepDays: keepDays,
        );
      }
      if (kDebugMode) print('📤 ETL charts → Firestore: ${bySymbol.length}개 심볼');
    } catch (e) {
      if (kDebugMode) print('❌ ETL charts failed: $e');
    }
  }

  Future<void> _cleanupLocalDb() async {
    try {
      final Database db = await DatabaseHelper.instance.database;
      // 존재하는 경우에만 삭제 시도
      for (final table in ['top_stocks', 'current_price', 'holdings']) {
        try { await db.delete(table); } catch (_) {}
      }
      if (kDebugMode) print('🧹 Local DB cleanup done');
    } catch (e) {
      if (kDebugMode) print('❌ Local DB cleanup failed: $e');
    }
  }
}


