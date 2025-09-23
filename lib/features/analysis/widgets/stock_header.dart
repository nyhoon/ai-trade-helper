import 'package:flutter/material.dart';
import '../../../core/utils/formatters.dart';

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

    final double currentPrice = (currentPriceData?['currentPrice'] ?? analysis?['currentPrice'] ?? 0.0).toDouble();
    final double openPrice = (currentPriceData?['openPrice'] ?? analysis?['openPrice'] ?? currentPrice).toDouble();
    
    // 🔧 디버깅: openPrice 값 확인
    print('🔍 [StockHeader] openPrice 디버깅:');
    print('  - currentPriceData?[\'openPrice\']: ${currentPriceData?['openPrice']}');
    print('  - analysis?[\'openPrice\']: ${analysis?['openPrice']}');
    print('  - 최종 openPrice: $openPrice');
    
    // 🔧 디버깅: 데이터 확인
    print('🔍 [StockHeader] 데이터 확인:');
    print('  - currentPriceData: $currentPriceData');
    print('  - analysis: $analysis');
    print('  - currentPrice: $currentPrice');
    print('  - openPrice: $openPrice');

    final double priceChange = currentPrice - openPrice;
    final double priceChangePercent = openPrice > 0 ? (priceChange / openPrice) * 100 : 0.0;

    final bool nasdaq = isNasdaqStock(stockCode);

    final String currentPriceText = nasdaq
        ? '\$${currentPrice.toStringAsFixed(2)}'
        : Formatters.formatPrice(currentPrice);
    final String openPriceText = nasdaq
        ? '\$${openPrice.toStringAsFixed(2)}'
        : Formatters.formatPrice(openPrice);
    final String changeText = nasdaq
        ? '${priceChange >= 0 ? '+' : ''}\$${priceChange.toStringAsFixed(2)} (${priceChangePercent >= 0 ? '+' : ''}${priceChangePercent.toStringAsFixed(2)}%)'
        : '${priceChange >= 0 ? '+' : ''}${Formatters.formatPrice(priceChange)} (${priceChangePercent >= 0 ? '+' : ''}${priceChangePercent.toStringAsFixed(2)}%)';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    stockName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
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
            // 현재가 + 등락률을 한 줄에 표시
            Text(
              currentPrice > 0 ? '$currentPriceText (${priceChangePercent >= 0 ? '+' : ''}${priceChangePercent.toStringAsFixed(2)}%)' : 'N/A',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: currentPrice > 0
                    ? (currentPrice >= openPrice ? Colors.red : Colors.blue)
                    : Colors.grey,
              ),
            ),
            // 시가 + 등락금액을 한 줄에 표시
            Text(
              openPrice > 0 ? '시가: $openPriceText (${priceChange >= 0 ? '+' : ''}${nasdaq ? '\$${priceChange.toStringAsFixed(2)}' : Formatters.formatPrice(priceChange)})' : '',
              style: TextStyle(
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


