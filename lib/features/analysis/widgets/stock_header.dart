import 'package:flutter/material.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/stock_utils.dart';

typedef GetAnalysisForCode = Map<String, dynamic>? Function(String stockCode);
typedef IsNasdaqStock = bool Function(String stockCode);
typedef GetDisplayName = String Function(Map<String, dynamic> item);

class StockHeader extends StatelessWidget {
  final Map<String, dynamic> item;
  final Map<String, dynamic>? currentPriceData;
  final GetAnalysisForCode getAnalysisForCode;
  final IsNasdaqStock isNasdaqStock;
  final GetDisplayName getDisplayName;

  const StockHeader({
    super.key,
    required this.item,
    required this.currentPriceData,
    required this.getAnalysisForCode,
    required this.isNasdaqStock,
    required this.getDisplayName,
  });

  @override
  Widget build(BuildContext context) {
    final String stockCode = item['stock_code'] as String? ?? item['stockCode'] as String? ?? '';
    final String stockName = getDisplayName(item);

    final analysis = getAnalysisForCode(stockCode);

    double _toDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    // 🔍 current 필드 우선 읽기 (Functions에서 저장하는 구조)
    final Map<String, dynamic> currentData = (item['current'] as Map<String, dynamic>?) ?? {};
    print('🔍 [StockHeader] currentData: $currentData');
    
    // 현재가 소스 우선순위: current 필드 → item.currentPriceData → 전달된 currentPriceData → analysis.currentPriceData → analysis.priceData → analysis.technicalData → {}
    final Map<String, dynamic> priceMap = Map<String, dynamic>.from(
      currentData.isNotEmpty ? currentData :
      (item['currentPriceData'] as Map?) ??
      (currentPriceData as Map?) ??
      (analysis?['currentPriceData'] as Map?) ??
      (analysis?['priceData'] as Map?) ??
      (analysis?['technicalData'] as Map?) ??
      const {}
    );

    double currentPrice = _toDouble(
      priceMap['currentPrice'] ?? priceMap['current_price'] ?? priceMap['prpr']
    );
    double openPrice = _toDouble(
      priceMap['open'] ?? priceMap['openPrice'] ?? priceMap['open_price']
    );
    double prevClose = _toDouble(
      priceMap['prevClose'] ?? priceMap['prev_close'] ?? priceMap['previous_close'] ?? priceMap['stck_prdy_clpr']
    );

    // 추가 폴백: 서버/분석 루트 및 아이템 루트 키에서 보강
    if (currentPrice <= 0.0) {
      currentPrice = _toDouble(
        (analysis?['currentPrice']) ??
        (analysis?['priceData']?['currentPrice']) ??
        (analysis?['technicalData']?['currentPrice']) ??
        (item['currentPrice']) ?? (item['prpr']) ??
        (currentPriceData?['currentPrice'])
      );
    }
    if (openPrice <= 0.0) {
      openPrice = _toDouble(
        (analysis?['openPrice']) ??
        (analysis?['priceData']?['openPrice']) ??
        (analysis?['technicalData']?['openPrice']) ??
        (item['open']) ?? (item['openPrice']) ??
        (currentPriceData?['openPrice'])
      );
    }
    // 추가 폴백: 분석 블록에서 전일가 추출
    if (prevClose == 0.0) {
      prevClose = _toDouble(
        (analysis?['prevClose']) ?? (analysis?['previousPrice']) ??
        (analysis?['priceData']?['prevClose']) ??
        (analysis?['technicalData']?['previousPrice']) ??
        (item['prevClose']) ?? (item['stck_prdy_clpr']) ??
        (currentPriceData?['prevClose'])
      );
    }

    // 최후 폴백: priceHistory 마지막 종가 사용
    if (currentPrice <= 0.0) {
      final List<dynamic>? prices = (analysis?['technicalData']?['priceHistory'] as List?) ??
          (analysis?['priceHistory'] as List?);
      if (prices != null && prices.isNotEmpty) {
        currentPrice = _toDouble(prices.last);
      }
    }

    // 등락 기준: 전일 종가 기준 (올바른 계산)
    final double baseline = prevClose > 0 ? prevClose : (openPrice > 0 ? openPrice : currentPrice);
    final double priceChangeFromBaseline = currentPrice - baseline;
    final double priceChangePercent = baseline > 0 ? (priceChangeFromBaseline / baseline) * 100 : 0.0;
    
    // 디버그 로깅 추가
    print('🔍 [StockHeader] 가격 계산: $stockCode');
    print('  - 현재가: $currentPrice');
    print('  - 전일가: $prevClose');
    print('  - 시가: $openPrice');
    print('  - 기준가: $baseline');
    print('  - 변동액: $priceChangeFromBaseline');
    print('  - 변동률: $priceChangePercent%');

    final bool nasdaq = isNasdaqStock(stockCode);

    // 통합 가격 포맷팅 사용
    final String currentPriceText = StockUtils.instance.formatPrice(currentPrice, stockCode);
    final String openPriceText = StockUtils.instance.formatPrice(openPrice, stockCode);
    final String changeText = '${StockUtils.instance.formatChangeAmount(priceChangeFromBaseline, stockCode)} (${StockUtils.instance.formatChangeRate(priceChangePercent)})';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      stockName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
              Text(
                stockCode,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 현재가 + 등락금액 + 등락률(전일 대비) 한 줄 표시
            Text(
              currentPrice > 0
                  ? '$currentPriceText ($changeText)'
                  : 'N/A',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: currentPrice > 0
                    ? (priceChangeFromBaseline >= 0 ? Colors.red : Colors.blue)
                    : Colors.grey,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            // 시가 + (시가 대비 등락금액) 표시
            Text(
              () {
                if (openPrice <= 0) return '';
                final double changeFromOpen = currentPrice - openPrice;
                return '시가: $openPriceText (${StockUtils.instance.formatChangeAmount(changeFromOpen, stockCode)})';
              }(),
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            // 전일가 별도 표시
            Text(
              prevClose > 0
                  ? '전일: ${StockUtils.instance.formatPrice(prevClose, stockCode)}'
                  : '',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ],
    );
  }
}


