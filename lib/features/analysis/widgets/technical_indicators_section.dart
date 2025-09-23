import 'package:flutter/material.dart';

typedef GetKoreanIndicatorName = String Function(String indicatorName);
typedef GenerateDetailedReason = String Function(String indicatorName, double score, String signal, Map<String, dynamic> analysis);
typedef GetIndicatorScore = double Function(String indicatorName, Map<String, dynamic> analysis);
typedef LoadThresholds = Future<Map<String, double>> Function();

class TechnicalIndicatorsSection extends StatelessWidget {
  final Map<String, dynamic> analysis;
  final GetKoreanIndicatorName getKoreanIndicatorName;
  final GenerateDetailedReason generateDetailedReason;
  final GetIndicatorScore getIndicatorScore;
  final LoadThresholds loadThresholds;

  const TechnicalIndicatorsSection({
    super.key,
    required this.analysis,
    required this.getKoreanIndicatorName,
    required this.generateDetailedReason,
    required this.getIndicatorScore,
    required this.loadThresholds,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, double>>(
      future: loadThresholds(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final buyThreshold = snapshot.data!['buyThreshold'] ?? 0.0;
        final sellThreshold = snapshot.data!['sellThreshold'] ?? 0.0;

        final individualScores = analysis['individualScores'] as Map<String, dynamic>? ?? {};
        final aggregateScore = (analysis['comprehensiveScore'] as num?)?.toDouble() ?? 0.0;

        final allIndicators = const [
          {'name': 'RSI'},
          {'name': 'MACD'},
          {'name': '볼린저밴드'},
          {'name': '이동평균선'},
          {'name': '거래량'},
          {'name': 'VWAP'},
          {'name': 'ADX'},
        ];

        final signalMap = <String, Map<String, dynamic>>{};
        individualScores.forEach((indicatorName, score) {
          final value = (score as num?)?.toDouble() ?? 0.0;
          final signal = value > buyThreshold ? '매수' : (value < sellThreshold ? '매도' : '관망');
          final koreanName = getKoreanIndicatorName(indicatorName);
          signalMap[koreanName] = {
            'name': koreanName,
            'score': value,
            'signal': signal,
            'reason': generateDetailedReason(indicatorName, value, signal, analysis),
          };
        });

        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.green[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '기술적 지표 조건',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green[700]),
              ),
              const SizedBox(height: 6),
              Builder(builder: (_) {
                final scoreText = aggregateScore >= 0 ? '+${aggregateScore.toStringAsFixed(3)}' : aggregateScore.toStringAsFixed(3);
                return Row(children: [
                  const Icon(Icons.assessment, size: 16, color: Colors.black54),
                  const SizedBox(width: 6),
                  Text('지표 종합점수: $scoreText', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
                ]);
              }),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: allIndicators.take(4).map((indicator) {
                  final map = signalMap[indicator['name'] as String];
                  final hasSignal = map != null;
                  Color checkColor = Colors.grey;
                  String checkSymbol = '○';
                  if (hasSignal) {
                    final score = (map?['score'] as num?)?.toDouble() ?? 0.0;
                    if (score > 0.05) {
                      checkColor = Colors.red;
                      checkSymbol = '✓';
                    } else if (score < -0.05) {
                      checkColor = Colors.blue;
                      checkSymbol = '✓';
                    } else {
                      checkColor = Colors.green;
                      checkSymbol = '✓';
                    }
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      SizedBox(width: 20, child: Text(checkSymbol, style: TextStyle(color: checkColor, fontWeight: FontWeight.bold, fontSize: 12))),
                      Expanded(child: Text('${indicator['name']}${hasSignal ? ' (${getIndicatorScore(indicator['name'] as String, analysis).toStringAsFixed(3)})' : ''}',
                        style: TextStyle(fontSize: 11, color: hasSignal ? checkColor : Colors.grey[600], fontWeight: hasSignal ? FontWeight.w500 : FontWeight.normal),
                      )),
                    ]),
                  );
                }).toList())),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: allIndicators.skip(4).map((indicator) {
                  final map = signalMap[indicator['name'] as String];
                  final hasSignal = map != null;
                  Color checkColor = Colors.grey;
                  String checkSymbol = '○';
                  if (hasSignal) {
                    final score = (map?['score'] as num?)?.toDouble() ?? 0.0;
                    if (score > 0.05) {
                      checkColor = Colors.red;
                      checkSymbol = '✓';
                    } else if (score < -0.05) {
                      checkColor = Colors.blue;
                      checkSymbol = '✓';
                    } else {
                      checkColor = Colors.green;
                      checkSymbol = '✓';
                    }
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      SizedBox(width: 20, child: Text(checkSymbol, style: TextStyle(color: checkColor, fontWeight: FontWeight.bold, fontSize: 12))),
                      Expanded(child: Text('${indicator['name']}${hasSignal ? ' (${getIndicatorScore(indicator['name'] as String, analysis).toStringAsFixed(3)})' : ''}',
                        style: TextStyle(fontSize: 11, color: hasSignal ? checkColor : Colors.grey[600], fontWeight: hasSignal ? FontWeight.w500 : FontWeight.normal),
                      )),
                    ]),
                  );
                }).toList())),
              ]),
            ],
          ),
        );
      },
    );
  }
}


