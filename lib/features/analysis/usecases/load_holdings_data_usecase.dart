import '../../../core/api/kis_unified_api_service.dart';
import '../../../core/data/unified_stock_data_manager.dart';
import '../../../core/database/repositories/holdings_repository.dart';
import '../../../core/remote/remote_kis_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// 보유종목 데이터 로드 UseCase
/// Domain 계층의 비즈니스 로직을 담당
class LoadHoldingsDataUseCase {
  final KisUnifiedApiService _apiService;
  final UnifiedStockDataManager _dataManager;
  final HoldingsRepository _holdingsRepo = HoldingsRepository();

  LoadHoldingsDataUseCase(
    this._apiService,
    this._dataManager,
  );

  /// 보유종목 데이터 로드 실행 (서버 주도: Firestore → Functions)
  Future<List<Map<String, dynamic>>> execute() async {
    try {
      // 1) Firestore에서 보유종목 조회 (서버 주도)
      final holdings = await _holdingsRepo.getAllHoldings();
      
      print('🔍 [LoadHoldingsUseCase] API에서 받은 보유종목 개수: ${holdings.length}');
      for (int i = 0; i < holdings.length; i++) {
        final holding = holdings[i];
        final symbol = holding['stockCode'] ?? holding['pdno'];
        final name = holding['stockName'] ?? holding['prdt_name'];
        final qty = holding['hldg_qty'];
        print('  [$i] $symbol - $name (수량: $qty)');
      }
      
      if (holdings.isEmpty) {
        return [];
      }

      // 2) 종목 심볼 추출 및 정규화 (stockCode 또는 pdno 지원)
      final symbols = holdings
          .map((item) => _normalizeSymbol(item['stockCode'] ?? item['pdno']))
          .where((symbol) => symbol != null && symbol!.isNotEmpty)
          .cast<String>()
          .toList();
      
      // 3) 현재가 데이터 조회 (서버 Functions 경유)
      final Map<String, Map<String, dynamic>> currentPrices = {};
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'debug-user';
      for (final symbol in symbols) {
        await RemoteKisService.instance.ensureChartAndAnalyze(uid: uid, symbol: symbol);
        // Firestore 구독으로 대체되므로 직접 API 호출 비활성화
        print('📊 [LoadHoldingsData] 현재가 API 호출 비활성화 - Firestore 구독 사용: $symbol');
        final price = null;
        if (price != null && price.isNotEmpty) {
          // 표준화
          currentPrices[symbol] = {
            'prpr': RemoteKisService.asDouble(price['currentPrice']),
            'stck_prdy_clpr': RemoteKisService.asDouble(price['prevClose']),
            'acml_vol': RemoteKisService.asInt(price['volume']),
            'open': RemoteKisService.asDouble(price['open'] ?? price['openPrice']),
            'high': RemoteKisService.asDouble(price['high'] ?? price['highPrice']),
            'low': RemoteKisService.asDouble(price['low'] ?? price['lowPrice']),
            'stockName': (price['stockName'] ?? '').toString(),
          };
        }
      }
      
      // 4) 데이터 통합
      final List<Map<String, dynamic>> result = [];
      
      for (final holding in holdings) {
        final originalSymbol = (holding['stockCode'] ?? holding['pdno']) as String?;
        final symbol = _normalizeSymbol(originalSymbol);
        final name = (holding['stockName'] ?? holding['prdt_name']) as String?;
        
        // null 값이나 빈 값은 건너뛰기
        if (symbol == null || symbol.isEmpty) {
          continue;
        }
        
        final priceData = currentPrices[symbol];
        final resolvedName = (priceData != null ? (priceData['stockName'] as String?) : null) ?? name ?? '';
        
        // 나스닥 종목인지 확인
        final isNasdaq = RegExp(r'^[A-Z]{1,5}$').hasMatch(symbol) && !RegExp(r'^\d{6}$').hasMatch(symbol);
        
        final resultItem = {
          // UI 및 다른 파이프라인과 키 일치
          'symbol': symbol,
          'name': resolvedName,
          'currentPrice': (priceData?['prpr'] as num?)?.toDouble(),
          'volume': priceData?['acml_vol'],
          'quantity': holding['hldg_qty'],
          'avgPrice': holding['pchs_avg_pric'],
          'isNasdaq': isNasdaq,
          'lastUpdated': DateTime.now().toIso8601String(),
        };
        
        print('✅ [LoadHoldingsUseCase] 결과 추가: $symbol (quantity: ${holding['hldg_qty']}, isNasdaq: $isNasdaq)');
        result.add(resultItem);
      }
      
      print('🔍 [LoadHoldingsUseCase] 최종 결과 개수: ${result.length}');
      return result;
    } catch (e) {
      throw Exception('보유종목 데이터 로드 실패: $e');
    }
  }

  /// 심볼 정규화: 해외는 영문 심볼, 국내는 6자리 숫자
  String? _normalizeSymbol(dynamic symbol) {
    if (symbol == null) return null;
    
    final symbolStr = symbol.toString().trim();
    if (symbolStr.isEmpty) return null;
    
    // 국내 코드: 왼쪽 0패딩 포함 6자리 유지, KRX/KOSPI 접두사 제거
    final cleaned = symbolStr
        .replaceFirst(RegExp(r'^(KRX:|KOSPI:|KOSDAQ:)', caseSensitive: false), '')
        .trim();
    if (RegExp(r'^\d{1,6}$').hasMatch(cleaned)) {
      return cleaned.padLeft(6, '0');
    }
    
    // 해외 종목: NASDAQ: 접두사 제거하고 영문 심볼만 추출
    if (cleaned.toUpperCase().startsWith('NASDAQ:')) {
      return cleaned.substring(7).toUpperCase();
    }
    
    // 이미 영문 심볼인 경우 대문자로 변환
    if (RegExp(r'^[A-Za-z]{1,5}$').hasMatch(cleaned)) {
      return cleaned.toUpperCase();
    }
    
    // 기타 포맷은 스킵
    return null;
  }
}
