import 'package:flutter/material.dart';

typedef IsNasdaqStock = bool Function(String stockCode);

class ColoredSignalSummary extends StatelessWidget {
  final Map<String, dynamic> analysis;
  final IsNasdaqStock isNasdaqStock;
  final String Function(String indicatorName) getIndicatorKey;
  final String Function(String indicatorName, double scoreValue, String signal, Map<String, dynamic> analysis) generateDetailedReason;
  final String Function(String indicatorName) getKoreanIndicatorName;
  final String Function(String indicatorName, Map<String, dynamic> analysis) getActualValueText;

  const ColoredSignalSummary({
    super.key,
    required this.analysis,
    required this.isNasdaqStock,
    required this.getIndicatorKey,
    required this.generateDetailedReason,
    required this.getKoreanIndicatorName,
    required this.getActualValueText,
  });

  @override
  Widget build(BuildContext context) {
    final detailedAnalysis = analysis['detailedAnalysis'] as Map<String, dynamic>? ?? {};
    final individualScores = analysis['individualScores'] as Map<String, dynamic>? ?? {};
    final targetPrice = (analysis['targetPrice'] as num?)?.toDouble() ?? 0.0;
    final analysisPrice = (analysis['analysisPrice'] as num?)?.toDouble() ?? 0.0;
    final stockCode = analysis['stockCode'] as String? ?? '';
    final buyThreshold = (analysis['buyThreshold'] as num?)?.toDouble();
    final sellThreshold = (analysis['sellThreshold'] as num?)?.toDouble();

    if (buyThreshold == null || sellThreshold == null) {
      return const SizedBox.shrink();
    }

    final List<Map<String, dynamic>> signals = [];
    individualScores.forEach((indicatorName, score) {
      final scoreValue = (score as num?)?.toDouble() ?? 0.0;
      String signal = '관망';
      if (scoreValue > buyThreshold) {
        signal = '매수';
      } else if (scoreValue < sellThreshold) {
        signal = '매도';
      }

      final indicatorKey = getIndicatorKey(indicatorName);
      final indicatorAnalysis = detailedAnalysis[indicatorKey];

      String detailedReason = '';
      String actualValue = '';

      if (indicatorAnalysis != null) {
        detailedReason = indicatorAnalysis['analysis'] as String? ?? '';
      }

      actualValue = getActualValueText(indicatorName, analysis);

      if (detailedReason.isEmpty) {
        detailedReason = generateDetailedReason(indicatorName, scoreValue, signal, analysis);
      }

      signals.add({
        'name': getKoreanIndicatorName(indicatorName),
        'signal': signal,
        'score': scoreValue,
        'actualValue': actualValue,
        'reason': detailedReason,
      });
    });

    if (signals.isEmpty) {
      return const Text(
        '시그널 없음',
        style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
      );
    }

    final buySignals = signals.where((s) => s['signal'] == '매수').toList();
    final sellSignals = signals.where((s) => s['signal'] == '매도').toList();
    final neutralSignals = signals.where((s) => s['signal'] == '관망').toList();

    Color colorForSignal(String signal) {
      if (signal == '매수') return Colors.red[600]!;
      if (signal == '매도') return Colors.blue[600]!;
      return Colors.grey[600]!;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildChip('매수', buySignals.length, Colors.red[50]!, Colors.red[600]!),
            _buildChip('매도', sellSignals.length, Colors.blue[50]!, Colors.blue[600]!),
            _buildChip('관망', neutralSignals.length, Colors.grey[100]!, Colors.grey[600]!),
          ],
        ),
        const SizedBox(height: 8),
        ...signals.map((s) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorForSignal(s['signal'] as String).withOpacity(0.05),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colorForSignal(s['signal'] as String).withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    (s['signal'] == '매수')
                        ? Icons.arrow_upward
                        : (s['signal'] == '매도')
                            ? Icons.arrow_downward
                            : Icons.remove,
                    color: colorForSignal(s['signal'] as String),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${s['name']} · ${(s['score'] as num).toStringAsFixed(3)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: colorForSignal(s['signal'] as String),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s['reason'] as String,
                          style: const TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                        if ((s['actualValue'] as String).isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            s['actualValue'] as String,
                            style: const TextStyle(fontSize: 11, color: Colors.black54),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildChip(String label, int count, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: fg.withOpacity(0.3))),
      child: Text('$label: $count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg)),
    );
  }
}


