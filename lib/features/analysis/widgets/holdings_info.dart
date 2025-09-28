import 'package:flutter/material.dart';

typedef GetCurrentPrices = Map<String, Map<String, dynamic>> Function();
typedef IsNasdaqStock = bool Function(String stockCode);

class HoldingsInfo extends StatelessWidget {
  final Map<String, dynamic> holding;
  final Map<String, dynamic>? analysis;
  final GetCurrentPrices getCurrentPrices;
  final IsNasdaqStock isNasdaqStock;

  const HoldingsInfo({
    super.key,
    required this.holding,
    required this.analysis,
    required this.getCurrentPrices,
    required this.isNasdaqStock,
  });

  @override
  Widget build(BuildContext context) {
    final quantity = (holding['quantity'] ?? holding['qty'] ?? holding['quantity'] ?? 0).toInt();
    final avgPrice = (holding['avgPrice'] ?? holding['avg_price'] ?? holding['avgPrice'] ?? 0.0).toDouble();
    final stockCode = holding['stockCode'] as String? ?? holding['stock_code'] as String? ?? '';

    // 보유수량이 0이면 보유정보 표시하지 않음
    if (quantity <= 0) {
      return const SizedBox.shrink();
    }

    final currentPrices = getCurrentPrices();
    final currentPriceData = currentPrices[stockCode];

    double currentPrice = currentPriceData?['currentPrice'] ??
        currentPriceData?['prpr'] ??
        (holding['currentPrice'] ?? holding['current_price'] ?? 0.0).toDouble();

    final totalValue = currentPrice * quantity;
    final totalCost = avgPrice * quantity;
    final profit = totalValue - totalCost;
    final profitRate = totalCost > 0 ? (profit / totalCost) * 100 : 0.0;

    final isUs = isNasdaqStock(stockCode);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Icon(Icons.account_balance_wallet, color: Colors.blue[700], size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '보유수량: $quantity주, 평균단가: ${isUs ? '\$${avgPrice.toStringAsFixed(2)}' : '${avgPrice.toStringAsFixed(0)}원'}',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  '평가손익: ${isUs ? '\$${profit.toStringAsFixed(2)}' : '${profit.toStringAsFixed(0)}원'} (${profitRate >= 0 ? '+' : ''}${profitRate.toStringAsFixed(2)}%)',
                  style: TextStyle(
                    fontSize: 12,
                    color: profit >= 0 ? Colors.red : Colors.blue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


