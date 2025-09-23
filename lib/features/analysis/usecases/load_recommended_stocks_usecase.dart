import '../../../core/services/recommended_stocks_service.dart';
import '../../../core/data/app_data_manager.dart';
import '../../../core/data/recommended_stocks_data.dart';
import '../../../core/data/stock_master_parser.dart';

/// 추천종목 데이터 로드 UseCase
/// Domain 계층의 비즈니스 로직을 담당
class LoadRecommendedStocksUseCase {
  final RecommendedStocksService _recommendedStocksService;

  LoadRecommendedStocksUseCase(this._recommendedStocksService);

  /// 추천종목 데이터 로드 실행
  Future<List<Map<String, dynamic>>> execute() async {
    try {
      print('🔄 [UseCase] 추천종목 데이터 로드 시작...');
      
      // 추천종목 서비스에서 데이터 조회 (code->name)
      final recommendedStocksMap = await _recommendedStocksService.getAllRecommendedStocks();
      print('📊 [UseCase] 추천종목 맵 조회 완료: ${recommendedStocksMap.length}개');

      final appData = AppDataManager.instance;

      final List<Map<String, dynamic>> result = [];
      int processedCount = 0;
      final totalCount = recommendedStocksMap.length;
      
      for (final entry in recommendedStocksMap.entries) {
        final originalCode = (entry.key).toString().trim();
        final code = _normalizeSymbol(originalCode);
        
        if (code == null || code.isEmpty) {
          continue;
        }

        // 마스터/캐시에서 종목명 우선
        String name = appData.getStockName(code);
        if (name.isEmpty) {
          name = entry.value?.toString() ?? '';
        }
        if (name.isEmpty) continue; // 이름도 없으면 스킵

        result.add({
          'stock_code': code,
          'stock_name': name,
          'currentPrice': 0,
          'change': 0,
          'changeRate': 0,
          'volume': 0,
          'recommendation': 'HOLD',
          'confidence': 0.0,
          'lastUpdated': DateTime.now().toIso8601String(),
        });
        
        processedCount++;
        
        // 진행률 로그 (100개마다)
        if (processedCount % 100 == 0 || processedCount == totalCount) {
          final progress = (processedCount / totalCount * 100).toStringAsFixed(1);
          print('📊 [UseCase] 진행률: $processedCount/$totalCount ($progress%) - $code ($name)');
        }
      }

      // 점수/가격 기반 상위 10개씩 추리기 (NASDAQ / KOSPI / KOSDAQ)
      final recommendedData = RecommendedStocksData();
      final scored = await recommendedData.getAllStocksWithScores();

      // 시장 판별을 위해 마스터 파서 활용
      final parser = StockMasterParser();
      final isParserReady = parser.isInitialized;

      String _resolveMarketDetailed(String code) {
        if (code.length == 6 && int.tryParse(code) != null) {
          if (isParserReady) {
            if (parser.getKosdaqStockCodes().contains(code)) return 'KOSDAQ';
            if (parser.getKospiStockCodes().contains(code)) return 'KOSPI';
          }
          return 'KOREA';
        }
        return 'NASDAQ';
      }

      List<Map<String, dynamic>> toItemList(Iterable<MapEntry<String, Map<String, dynamic>>> entries) {
        return entries.map((e) => {
          'stock_code': e.key,
          'stock_name': e.value['name'] ?? appData.getStockName(e.key),
          'currentPrice': (e.value['price'] as num?)?.toDouble() ?? 0.0,
          'comprehensiveScore': (e.value['score'] as num?)?.toDouble() ?? 0.0,
          'market': _resolveMarketDetailed(e.key),
        }).toList();
      }

      // 엔트리 가공 및 정렬
      final entries = scored.entries;
      final usEntries = entries.where((e) => _resolveMarketDetailed(e.key) == 'NASDAQ').toList()
        ..sort((a, b) => ((b.value['score'] ?? 0.0) as num).compareTo((a.value['score'] ?? 0.0) as num));
      final kospiEntries = entries.where((e) => _resolveMarketDetailed(e.key) == 'KOSPI').toList()
        ..sort((a, b) => ((b.value['score'] ?? 0.0) as num).compareTo((a.value['score'] ?? 0.0) as num));
      final kosdaqEntries = entries.where((e) => _resolveMarketDetailed(e.key) == 'KOSDAQ').toList()
        ..sort((a, b) => ((b.value['score'] ?? 0.0) as num).compareTo((a.value['score'] ?? 0.0) as num));

      final topUs = toItemList(usEntries.take(10));
      final topKospi = toItemList(kospiEntries.take(10));
      final topKosdaq = toItemList(kosdaqEntries.take(10));

      final combined = <Map<String, dynamic>>[...topUs, ...topKospi, ...topKosdaq];

      print('✅ [UseCase] 시장별 상위 종목 준비 완료: US=${topUs.length}, KOSPI=${topKospi.length}, KOSDAQ=${topKosdaq.length}');
      return combined.isNotEmpty ? combined : result;
    } catch (e) {
      print('❌ [UseCase] 추천종목 데이터 로드 실패: $e');
      throw Exception('추천종목 데이터 로드 실패: $e');
    }
  }

  /// 심볼 정규화: 해외는 영문 심볼, 국내는 6자리 숫자
  String? _normalizeSymbol(String symbol) {
    if (symbol.isEmpty) return null;
    
    // 국내 6자리 숫자 코드는 그대로 유지
    if (RegExp(r'^\d{6}$').hasMatch(symbol)) {
      return symbol;
    }
    
    // 해외 종목: NASDAQ: 접두사 제거하고 영문 심볼만 추출
    if (symbol.startsWith('NASDAQ:')) {
      return symbol.substring(7).toUpperCase();
    }
    
    // 이미 영문 심볼인 경우 대문자로 변환
    if (RegExp(r'^[A-Za-z]{1,5}$').hasMatch(symbol)) {
      return symbol.toUpperCase();
    }
    
    // 기타 포맷은 스킵
    return null;
  }
}
