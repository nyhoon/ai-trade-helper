import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

typedef IsNasdaqStock = bool Function(String stockCode);
typedef GetIndicatorScore = double Function(String indicatorName, Map<String, dynamic> analysis);
typedef GetKoreanIndicatorName = String Function(String indicatorName);
typedef GetIndicatorKey = String Function(String indicatorName);
typedef FormatNumber = String Function(num value);
typedef GenerateDetailedReason = String Function(String indicatorName, double score, String signal, Map<String, dynamic> analysis);
typedef GenerateComprehensiveAnalysisReason = String Function(Map<String, dynamic> analysis, String signal, double aggregateScore, Map<String, dynamic> individualScores);
typedef LoadStyleParams = Future<Map<String, dynamic>> Function();

class IntegratedAnalysisSection extends StatelessWidget {
  final Map<String, dynamic> item;
  final Map<String, dynamic> analysis;
  final IsNasdaqStock isNasdaqStock;
  final GetIndicatorScore getIndicatorScore;
  final GetKoreanIndicatorName getKoreanIndicatorName;
  final GetIndicatorKey getIndicatorKey;
  final FormatNumber formatNumber;
  final GenerateDetailedReason generateDetailedReason;
  final GenerateComprehensiveAnalysisReason generateComprehensiveAnalysisReason;
  final LoadStyleParams loadStyleParams;

  const IntegratedAnalysisSection({
    super.key,
    required this.item,
    required this.analysis,
    required this.isNasdaqStock,
    required this.getIndicatorScore,
    required this.getKoreanIndicatorName,
    required this.getIndicatorKey,
    required this.formatNumber,
    required this.generateDetailedReason,
    required this.generateComprehensiveAnalysisReason,
    required this.loadStyleParams,
  });

  @override
  Widget build(BuildContext context) {
    final double confidence = (analysis['confidence'] as num?)?.toDouble() ?? 0.0;
    final double targetPrice = (analysis['targetPrice'] as num?)?.toDouble() ?? 0.0;
    final Map<String, dynamic> individualScores = analysis['individualScores'] as Map<String, dynamic>? ?? {};
    final double comprehensiveScore = (analysis['comprehensiveScore'] as num?)?.toDouble() ?? 0.0;
    final String reason = (analysis['reason'] as String?) ?? '';

    return FutureBuilder<Map<String, dynamic>>(
      future: loadStyleParams(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final styleParams = snapshot.data!;
        final double buyThreshold = (styleParams['buyThreshold'] as num?)?.toDouble() ?? 0.0;
        final double sellThreshold = (styleParams['sellThreshold'] as num?)?.toDouble() ?? 0.0;

        String finalSignal = '관망';
        if (comprehensiveScore >= buyThreshold) {
          finalSignal = '매수';
        } else if (comprehensiveScore <= sellThreshold) {
          finalSignal = '매도';
        }

        Color signalColor;
        Color backgroundColor;
        Color borderColor;
        if (finalSignal == '매수') {
          signalColor = Colors.red;
          backgroundColor = Colors.red[50]!;
          borderColor = Colors.red[200]!;
        } else if (finalSignal == '매도') {
          signalColor = Colors.blue;
          backgroundColor = Colors.blue[50]!;
          borderColor = Colors.blue[200]!;
        } else {
          signalColor = Colors.green;
          backgroundColor = Colors.green[50]!;
          borderColor = Colors.green[200]!;
        }

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.5),
            boxShadow: [
              BoxShadow(color: signalColor.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: signalColor.withOpacity(0.1),
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: signalColor, borderRadius: BorderRadius.circular(20)),
                      child: Text(finalSignal, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '종합점수: ${comprehensiveScore >= 0 ? '+' : ''}${comprehensiveScore.toStringAsFixed(3)}',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: signalColor),
                          ),
                        ],
                      ),
                    ),
                    if (targetPrice > 0)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            isNasdaqStock(analysis['stockCode'] as String? ?? '')
                                ? '목표가: \$${targetPrice.toStringAsFixed(2)}'
                                : '목표가: ${NumberFormat('#,###').format(targetPrice)}원',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: signalColor),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [Icon(Icons.lightbulb_outline, size: 16, color: signalColor), const SizedBox(width: 6), Text('분석 이유', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: signalColor))]),
                    const SizedBox(height: 8),
                    Text(
                      reason.isNotEmpty
                          ? reason
                          : generateComprehensiveAnalysisReason(analysis, finalSignal, comprehensiveScore, individualScores),
                      style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.4),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [Icon(Icons.analytics, size: 16, color: signalColor), const SizedBox(width: 6), Text('기술적 지표 분석', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: signalColor))]),
                    const SizedBox(height: 6),
                    ...individualScores.keys.map((indicatorName) {
                      final double score = getIndicatorScore(indicatorName, analysis);
                      String signal = _getIndicatorSignal(indicatorName, score);
                      Color indicatorColor = signal == '매수' ? Colors.red : signal == '매도' ? Colors.blue : Colors.green;
                      final detailedReason = generateDetailedReason(indicatorName, score, signal, analysis);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: indicatorColor.withOpacity(0.3))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(color: indicatorColor, shape: BoxShape.circle)),
                            const SizedBox(width: 12),
                            Expanded(child: Row(children: [
                              Text(getKoreanIndicatorName(indicatorName), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: indicatorColor)),
                              const SizedBox(width: 8),
                              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: indicatorColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)), child: Text('${score >= 0 ? '+' : ''}${score.toStringAsFixed(3)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: indicatorColor))),
                              const Spacer(),
                              Text(signal, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: indicatorColor)),
                            ])),
                          ]),
                          if (detailedReason.isNotEmpty) ...[const SizedBox(height: 6), Text(detailedReason, style: TextStyle(fontSize: 11, color: Colors.grey[600], height: 1.3))],
                        ]),
                      );
                    }).toList(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.month.toString().padLeft(2, '0')}/${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _getIndicatorSignal(String indicatorName, double score) {
    switch (indicatorName) {
      case 'volume':
        // 거래량: 양수면 매수, 음수면 매도
        return score > 0.1 ? '매수' : (score < -0.1 ? '매도' : '관망');
      
      case 'rsi':
        // RSI: 0.1 이상이면 매수, -0.1 이하면 매도
        return score > 0.1 ? '매수' : (score < -0.1 ? '매도' : '관망');
      
      case 'macd':
        // MACD: 0.1 이상이면 매수, -0.1 이하면 매도
        return score > 0.1 ? '매수' : (score < -0.1 ? '매도' : '관망');
      
      case 'bollinger':
        // 볼린저밴드: 0.1 이상이면 매수, -0.1 이하면 매도
        return score > 0.1 ? '매수' : (score < -0.1 ? '매도' : '관망');
      
      case 'movingAverage':
        // 이동평균선: 0.1 이상이면 매수, -0.1 이하면 매도
        return score > 0.1 ? '매수' : (score < -0.1 ? '매도' : '관망');
      
      case 'vwap':
        // VWAP: 0.1 이상이면 매수, -0.1 이하면 매도
        return score > 0.1 ? '매수' : (score < -0.1 ? '매도' : '관망');
      
      case 'adx':
        // ADX: 0.1 이상이면 매수, -0.1 이하면 매도
        return score > 0.1 ? '매수' : (score < -0.1 ? '매도' : '관망');
      
      default:
        return '관망';
    }
  }
}
