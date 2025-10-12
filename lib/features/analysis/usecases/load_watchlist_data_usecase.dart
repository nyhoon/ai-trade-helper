import '../../../core/api/kis_unified_api_service.dart';
import '../../../core/database/repositories/watchlist_repository.dart';
import '../../../core/data/unified_stock_data_manager.dart';

/// 관심종목 데이터 로드 UseCase
/// Domain 계층의 비즈니스 로직을 담당
class LoadWatchlistDataUseCase {
  final KisUnifiedApiService _apiService;
  final WatchlistRepository _watchlistRepository;
  final UnifiedStockDataManager _dataManager;

  LoadWatchlistDataUseCase(
    this._apiService,
    this._watchlistRepository,
    this._dataManager,
  );

  /// 관심종목 데이터 로드 실행
  Future<List<Map<String, dynamic>>> execute() async {
    try {
      // 1. 관심종목 목록 조회
      final watchlistItems = await _watchlistRepository.getWatchlist();
      
      if (watchlistItems.isEmpty) {
        return [];
      }

      // 2. 종목 심볼 추출 및 정규화
      final symbols = watchlistItems
          .map((item) => _normalizeSymbol(item['stock_code'] ?? item['stockCode'] ?? item['pdno']))
          .where((symbol) => symbol != null && symbol!.isNotEmpty)
          .cast<String>()
          .toList();
      
      // 3. 현재가 데이터 조회
      final Map<String, Map<String, dynamic>> currentPrices = {};
      for (final symbol in symbols) {
        // ✅ API 직접 호출 비활성화 - Firestore 구독 사용
        print('🔍 [current 보호] LoadWatchlistDataUseCase에서 API 직접 호출 비활성화');
        // final priceData = await _apiService.getStockPrice(symbol);
        final priceData = null;
        if (priceData != null) {
          currentPrices[symbol] = priceData;
        }
      }
      
      // 4. 데이터 통합
      final List<Map<String, dynamic>> result = [];
      
      for (final item in watchlistItems) {
        final originalSymbol = (item['stock_code'] ?? item['stockCode'] ?? item['pdno']) as String?;
        final symbol = _normalizeSymbol(originalSymbol);
        final name = (item['stock_name'] ?? item['stockName'] ?? item['prdt_name']) as String?;
        if (symbol == null || symbol.isEmpty) {
          continue;
        }
        final priceData = currentPrices[symbol];
        // 나스닥 종목인지 확인
        final isNasdaq = RegExp(r'^[A-Z]{1,5}$').hasMatch(symbol) && !RegExp(r'^\d{6}$').hasMatch(symbol);
        
        result.add({
          'stock_code': symbol,
          'stock_name': (priceData?['stockName'] as String?) ?? name ?? '',
          'currentPrice': priceData?['prpr'],
          'change': priceData?['diff'],
          'changeRate': priceData?['rate'],
          'volume': priceData?['acml_vol'],
          'isNasdaq': isNasdaq,
          'lastUpdated': DateTime.now().toIso8601String(),
        });
      }
      
      return result;
    } catch (e) {
      throw Exception('관심종목 데이터 로드 실패: $e');
    }
  }

  /// 심볼 정규화: 해외는 영문 심볼, 국내는 6자리 숫자
  String? _normalizeSymbol(dynamic symbol) {
    if (symbol == null) return null;
    
    final symbolStr = symbol.toString().trim();
    if (symbolStr.isEmpty) return null;
    
    // 국내 6자리 숫자 코드는 그대로 유지
    if (RegExp(r'^\d{6}$').hasMatch(symbolStr)) {
      return symbolStr;
    }
    
    // 해외 종목: NASDAQ: 접두사 제거하고 영문 심볼만 추출
    if (symbolStr.startsWith('NASDAQ:')) {
      return symbolStr.substring(7).toUpperCase();
    }
    
    // 이미 영문 심볼인 경우 대문자로 변환
    if (RegExp(r'^[A-Za-z]{1,5}$').hasMatch(symbolStr)) {
      return symbolStr.toUpperCase();
    }
    
    // 기타 포맷은 스킵
    return null;
  }
}
