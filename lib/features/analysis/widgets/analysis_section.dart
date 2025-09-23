import 'package:flutter/material.dart';
import '../../../core/utils/formatters.dart';

typedef BuildColoredSignalSummary = Widget Function(Map<String, dynamic> analysis);
typedef IsNasdaqStock = bool Function(String stockCode);

class AnalysisSectionView extends StatelessWidget {
  final Map<String, dynamic> item;
  final Map<String, dynamic> analysis;
  final IsNasdaqStock isNasdaqStock;
  final BuildColoredSignalSummary buildColoredSignalSummary;

  const AnalysisSectionView({
    super.key,
    required this.item,
    required this.analysis,
    required this.isNasdaqStock,
    required this.buildColoredSignalSummary,
  });

  @override
  Widget build(BuildContext context) {
    final confidence = analysis['confidence'] ?? 0.0;
    final targetPrice = analysis['targetPrice'] ?? 0.0;
    final individualScores = analysis['individualScores'] as Map<String, dynamic>? ?? {};
    final comprehensiveScore = (analysis['comprehensiveScore'] as num?)?.toDouble() ?? 0.0;
    final buyThreshold = (analysis['buyThreshold'] as num?)?.toDouble();
    final sellThreshold = (analysis['sellThreshold'] as num?)?.toDouble();

    if (buyThreshold == null || sellThreshold == null) {
      return const SizedBox.shrink();
    }

    String finalSignal = '관망';
    if (comprehensiveScore >= buyThreshold) {
      finalSignal = '매수';
    } else if (comprehensiveScore <= sellThreshold) {
      finalSignal = '매도';
    }

    final List<Map<String, dynamic>> generatedSignals = [];
    individualScores.forEach((indicatorName, score) {
      final scoreValue = (score as num?)?.toDouble() ?? 0.0;
      String indicatorSignal = '관망';
      if (scoreValue > buyThreshold) {
        indicatorSignal = '매수';
      } else if (scoreValue <= sellThreshold) {
        indicatorSignal = '매도';
      }
      generatedSignals.add({'name': indicatorName, 'signal': indicatorSignal, 'score': scoreValue});
    });

    final stockCode = item['stock_code'] as String? ?? item['stockCode'] as String? ?? '';
    final isNasdaq = isNasdaqStock(stockCode);

    final String targetPriceText = isNasdaq
        ? '\$${(targetPrice as num).toStringAsFixed(2)}'
        : Formatters.formatPrice(targetPrice);

    Color signalColor;
    switch (finalSignal) {
      case '매수':
        signalColor = Colors.red;
        break;
      case '매도':
        signalColor = Colors.blue;
        break;
      default:
        signalColor = Colors.grey;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '일봉 분석 결과',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: signalColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                finalSignal,
                style: TextStyle(
                  fontSize: 12,
                  color: signalColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: signalColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: signalColor.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(
                finalSignal == '매수'
                    ? Icons.trending_up
                    : (finalSignal == '매도' ? Icons.trending_down : Icons.remove),
                color: signalColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(child: buildColoredSignalSummary(analysis)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.track_changes, color: Colors.green, size: 16),
                      const SizedBox(width: 4),
                      const Text(
                        '목표가',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    (targetPrice as num) > 0 ? targetPriceText : 'N/A',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: (targetPrice as num) > 0 ? Colors.green : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}


