import '../../../core/api/kis_unified_api_service.dart';

/// 현재가 데이터 업데이트 UseCase
/// Domain 계층의 비즈니스 로직을 담당
class UpdateCurrentPricesUseCase {
  final KisUnifiedApiService _apiService;

  UpdateCurrentPricesUseCase(this._apiService);

  /// 현재가 데이터 업데이트 실행
  Future<Map<String, Map<String, dynamic>>> execute(List<String> symbols) async {
    try {
      if (symbols.isEmpty) {
        return {};
      }

      // 현재가 데이터 조회
      final Map<String, Map<String, dynamic>> currentPrices = {};
      for (final symbol in symbols) {
        if (symbol.isNotEmpty) {
          // ✅ API 직접 호출 비활성화 - Firestore 구독 사용
          print('🔍 [current 보호] UpdateCurrentPricesUseCase에서 API 직접 호출 비활성화');
          // final priceData = await _apiService.getStockPrice(symbol);
          final priceData = null;
          if (priceData != null) {
            currentPrices[symbol] = priceData;
          }
        }
      }
      
      // 데이터 포맷팅
      final Map<String, Map<String, dynamic>> result = {};
      
      for (final symbol in symbols) {
        final priceData = currentPrices[symbol];
        
        if (priceData != null) {
          result[symbol] = {
            'currentPrice': priceData['prpr'],
            'change': priceData['diff'],
            'changeRate': priceData['rate'],
            'volume': priceData['acml_vol'],
            'lastUpdated': DateTime.now().toIso8601String(),
          };
        }
      }
      
      return result;
    } catch (e) {
      throw Exception('현재가 데이터 업데이트 실패: $e');
    }
  }
}
