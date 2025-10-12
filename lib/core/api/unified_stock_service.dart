import 'package:ai_helper/core/api/kis_unified_api_service.dart';
import 'package:ai_helper/core/remote/remote_kis_service.dart';
import 'package:ai_helper/core/utils/stock_utils.dart';
import 'package:ai_helper/core/trading/market_time_validator.dart';
import 'package:ai_helper/core/data/firestore_stock_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// 통합 주식 서비스 - 해외/국내 통합 API 호출
class UnifiedStockService {
  UnifiedStockService._();
  static final UnifiedStockService instance = UnifiedStockService._();

  final KisUnifiedApiService _kisApi = KisUnifiedApiService();
  final RemoteKisService _remoteKis = RemoteKisService.instance;
  final StockUtils _stockUtils = StockUtils.instance;

  /// 통합 현재가 조회: 서버(Function) 보장 → Firestore 읽기(재시도)
  Future<Map<String, dynamic>?> getCurrentPrice(String symbol, {String? uid}) async {
    try {
      print('🔍 [UnifiedStockService] 통합 현재가 조회 시작: $symbol');
      // 1) 서버에 데이터 보장 요청
      final effectiveUid = uid ?? FirebaseAuth.instance.currentUser?.uid ?? 'debug-user';
      await _remoteKis.ensureChartAndAnalyze(uid: effectiveUid, symbol: symbol);

      // 2) Firestore에서 재시도 읽기 (500ms * 8)
      Map<String, dynamic>? current;
      for (int i = 0; i < 8; i++) {
        final doc = await FirestoreStockService.getStockData(symbol);
        current = (doc != null ? doc['current'] as Map<String, dynamic>? : null);
        final has = current != null && current.isNotEmpty && current['currentPrice'] != null;
        if (has) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (current != null && current.isNotEmpty) {
        print('✅ [UnifiedStockService] Firestore 현재가 수신: $symbol');
        return _normalizeServerData(current!, symbol);
      }

      print('❌ [UnifiedStockService] Firestore 현재가 없음: $symbol');
      return null;
      
    } catch (e) {
      print('❌ [UnifiedStockService] 통합 현재가 조회 실패 ($symbol): $e');
      return null;
    }
  }

  /// 통합 일별 차트 조회: 서버(Function) 보장 → Firestore 읽기(재시도)
  Future<List<Map<String, dynamic>>> getDailyChart(String symbol, {int days = 100, String? uid}) async {
    try {
      print('🔍 [UnifiedStockService] 통합 일별 차트 조회 시작: $symbol');
      // 1) 서버에 데이터 보장 요청
      final effectiveUid = uid ?? FirebaseAuth.instance.currentUser?.uid ?? 'debug-user';
      await _remoteKis.ensureChartAndAnalyze(uid: effectiveUid, symbol: symbol);

      // 2) Firestore에서 재시도 읽기 (500ms * 8)
      List<Map<String, dynamic>> chart = [];
      for (int i = 0; i < 8; i++) {
        final bars = await FirestoreStockService.getChartData(symbol);
        if (bars.isNotEmpty) {
          chart = bars;
          break;
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (chart.isNotEmpty) {
        print('✅ [UnifiedStockService] Firestore 차트 수신: $symbol (${chart.length}개)');
        return _normalizeChartData(chart, symbol);
      }

      print('❌ [UnifiedStockService] Firestore 차트 없음: $symbol');
      return [];
      
    } catch (e) {
      print('❌ [UnifiedStockService] 통합 일별 차트 조회 실패 ($symbol): $e');
      return [];
    }
  }

  /// 서버 데이터 정규화
  Map<String, dynamic> _normalizeServerData(Map<String, dynamic> data, String symbol) {
    String market;
    try {
      market = MarketTimeValidator.instance.getMarketFromSymbol(symbol);
    } catch (_) {
      market = _stockUtils.isOverseasStock(symbol) ? 'NASDAQ' : 'KOSPI';
    }
    final bool isOverseas = market.toUpperCase().contains('NAS');
    
    return {
      'currentPrice': data['currentPrice'] ?? data['current_price'] ?? 0.0,
      'openPrice': data['openPrice'] ?? data['open_price'] ?? 0.0,
      'prevClose': data['prevClose'] ?? data['prev_close'] ?? 0.0,
      'highPrice': data['highPrice'] ?? data['high_price'] ?? 0.0,
      'lowPrice': data['lowPrice'] ?? data['low_price'] ?? 0.0,
      'volume': data['volume'] ?? 0,
      'changeAmount': data['changeAmount'] ?? data['change_amount'] ?? 0.0,
      'changeRate': data['changeRate'] ?? data['change_rate'] ?? 0.0,
      'stockName': data['stockName'] ?? data['stock_name'] ?? symbol,
      'market': market,
      'timestamp': data['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
      'isOverseas': isOverseas,
    };
  }

  /// 클라이언트 데이터 정규화 (미사용 - 하위호환)
  Map<String, dynamic> _normalizeClientData(Map<String, dynamic> data, String symbol) {
    String market;
    try {
      market = MarketTimeValidator.instance.getMarketFromSymbol(symbol);
    } catch (_) {
      market = _stockUtils.isOverseasStock(symbol) ? 'NASDAQ' : 'KOSPI';
    }
    final bool isOverseas = market.toUpperCase().contains('NAS');
    
    return {
      'currentPrice': data['prpr'] ?? 0.0,
      'openPrice': data['open'] ?? 0.0,
      'prevClose': data['stck_prdy_clpr'] ?? 0.0,
      'highPrice': data['high'] ?? 0.0,
      'lowPrice': data['low'] ?? 0.0,
      'volume': data['acml_vol'] ?? 0,
      'changeAmount': data['diff'] ?? 0.0,
      'changeRate': data['rate'] ?? 0.0,
      'stockName': data['stockName'] ?? symbol,
      'market': market,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'isOverseas': isOverseas,
    };
  }

  /// 클라이언트 차트 데이터 조회 (기존 KIS API 구조 반영)
  Future<List<Map<String, dynamic>>> _getClientChartData(String symbol, int days) async {
    try {
      String market;
      try {
        market = MarketTimeValidator.instance.getMarketFromSymbol(symbol);
      } catch (_) {
        market = _stockUtils.isOverseasStock(symbol) ? 'NASDAQ' : 'KOSPI';
      }
      final bool isOverseas = market.toUpperCase().contains('NAS');
      
      if (isOverseas) {
        // 해외주식: exchangeCode 'NAS' (나스닥)
        return await _kisApi.getOverseasDailyChart(
          symbol: symbol,
          exchangeCode: 'NAS', // NAS: 나스닥, NYS: 뉴욕증권거래소, AMS: 아메리칸증권거래소
        );
      } else {
        // 국내주식: marketCode 'J' (KRX)
        return await _kisApi.getDomesticDailyChart(
          stockCode: symbol,
          marketCode: 'J', // J: KRX, NX: NXT, UN: 통합
        );
      }
    } catch (e) {
      print('❌ [UnifiedStockService] 클라이언트 차트 데이터 조회 실패 ($symbol): $e');
      return [];
    }
  }

  /// 차트 데이터 정규화
  List<Map<String, dynamic>> _normalizeChartData(List<Map<String, dynamic>> data, String symbol) {
    final bool isOverseas = _stockUtils.isOverseasStock(symbol);
    
    return data.map((item) {
      return {
        'date': item['date'] ?? item['stck_bsop_date'] ?? '',
        'open': item['open'] ?? item['stck_oprc'] ?? 0.0,
        'high': item['high'] ?? item['stck_hgpr'] ?? 0.0,
        'low': item['low'] ?? item['stck_lwpr'] ?? 0.0,
        'close': item['close'] ?? item['stck_clpr'] ?? 0.0,
        'volume': item['volume'] ?? item['acml_vol'] ?? 0,
        'isOverseas': isOverseas,
      };
    }).toList();
  }
}
