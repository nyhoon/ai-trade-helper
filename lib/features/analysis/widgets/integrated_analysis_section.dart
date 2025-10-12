import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/stock_utils.dart';

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
    final Map<String, dynamic> individualScores = Map<String, dynamic>.from((analysis['individualScores'] as Map?) ?? const {});
    final Map<String, dynamic> analysisBlock = Map<String, dynamic>.from((analysis['analysis'] as Map?) ?? const {});
    final double comprehensiveScore = (analysis['comprehensiveScore'] as num?)?.toDouble() ?? 0.0;
    final String reason = (analysis['reason'] as String?) ?? '';
    final Map<String, dynamic> technicalData = Map<String, dynamic>.from((analysis['technicalData'] as Map?) ?? const {});
    final String stockCode = (analysis['stockCode'] as String?) ?? '';
    final bool overseas = isNasdaqStock(stockCode);

    // 최신 현재가 데이터(아이템에 동봉된 서버 값 우선)
    double _toDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    final Map<String, dynamic> currentMap = Map<String, dynamic>.from((item['currentPriceData'] as Map?)
      ?? (analysis['currentPriceData'] as Map?)
      ?? (analysis['priceData'] as Map?)
      ?? const {});
    final double currentPriceLatest = _toDouble(
      currentMap['currentPrice'] ?? currentMap['current_price'] ?? currentMap['prpr']
    );
    final double openPriceLatest = _toDouble(
      currentMap['open'] ?? currentMap['openPrice'] ?? currentMap['open_price']
    );
    final double prevCloseLatest = _toDouble(
      currentMap['prevClose'] ?? currentMap['prev_close'] ?? currentMap['previous_close'] ?? currentMap['stck_prdy_clpr']
    );
    final int volumeLatest = ((
      currentMap['volume']
        ?? currentMap['trade_volume']
        ?? currentMap['acc_trade_volume']
        ?? currentMap['tvol']
        ?? currentMap['Volume']
    ) as num?)?.toInt() ?? 0;

    // 가격/거래량 값 (서버 값 우선, 기술 데이터 폴백)
    final double currentPrice = currentPriceLatest > 0
        ? currentPriceLatest
        : ((analysis['currentPrice'] as num?)?.toDouble() ?? (technicalData['currentPrice'] as num?)?.toDouble() ?? 0.0);
    final double openPrice = openPriceLatest > 0
        ? openPriceLatest
        : ((analysis['openPrice'] as num?)?.toDouble() ?? (technicalData['open'] as num?)?.toDouble() ?? 0.0);
    final double prevClose = prevCloseLatest > 0
        ? prevCloseLatest
        : ((analysis['prevClose'] as num?)?.toDouble() ?? (technicalData['previousPrice'] as num?)?.toDouble() ?? 0.0);
    final int currentVolume = volumeLatest > 0
        ? volumeLatest
        : ((technicalData['currentVolume'] as num?)?.toInt() ?? (analysis['volume'] as num?)?.toInt() ?? 0);
    final int avgVolume = (technicalData['avgVolume'] as num?)?.toInt() ?? 0;

    // 지표 값들
    final double? rsi = (technicalData['rsi'] as num?)?.toDouble();
    final double? macd = (technicalData['macd'] as num?)?.toDouble();
    final double? macdSignal = (technicalData['signal'] as num?)?.toDouble();
    final double? bbUpper = (technicalData['bbUpper'] as num?)?.toDouble();
    final double? bbMiddle = (technicalData['bbMiddle'] as num?)?.toDouble();
    final double? bbLower = (technicalData['bbLower'] as num?)?.toDouble();
    final double? ma5 = (technicalData['ma5'] as num?)?.toDouble();
    final double? ma20 = (technicalData['ma20'] as num?)?.toDouble();
    final double? ma60 = (technicalData['ma60'] as num?)?.toDouble();
    final double? vwap = (technicalData['vwap'] as num?)?.toDouble();
    final double? adx = (technicalData['adx'] as num?)?.toDouble();

    // 통합 가격 포맷팅 사용
    String fmtPrice(num v) => StockUtils.instance.formatPrice(v.toDouble(), stockCode);
    String fmtPricePlain(num v) => StockUtils.instance.formatPricePlain(v.toDouble(), stockCode);
    String fmtVol(num v) => StockUtils.instance.formatVolume(v.toInt());

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
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                    // 우측 요약 제거: 상단 헤더(StockHeader)에서만 현재가/등락률/시가 표기
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
                      _buildAnalysisReasonWithPriceChange(reason, analysis, finalSignal, comprehensiveScore, individualScores),
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
                    // 7개 지표 강제 표시 (individualScores가 비어있어도 표시)
                    ..._getAllIndicators().map((indicatorName) {
                      final double score = getIndicatorScore(indicatorName, analysis);
                      // 실제 값 텍스트(technicalData 기반)가 있다면 우측 설명에 표기되므로, 서버 미제공 시 폴백은 별도 유틸에서 처리됨
                      String signal = _getIndicatorSignal(indicatorName, score);
                      Color indicatorColor = signal == '매수' ? Colors.red : signal == '매도' ? Colors.blue : Colors.green;
                      final detailedReason = generateDetailedReason(indicatorName, score, signal, analysis);
                      String valueLine = '';
                      switch (indicatorName) {
                        case 'volume':
                          if (currentVolume > 0) {
                            final ratio = (avgVolume > 0) ? (currentVolume / (avgVolume == 0 ? 1 : avgVolume)) : 1.0;
                            valueLine = '거래량 ${fmtVol(currentVolume)}주 (20일 평균 ${fmtVol(avgVolume)}주의 ${ratio.toStringAsFixed(1)}배)';
                          }
                          break;
                        case 'rsi':
                          if (rsi != null) valueLine = 'RSI ${rsi.toStringAsFixed(1)}';
                          break;
                        case 'macd':
                          if (macd != null && macdSignal != null) {
                            valueLine = 'MACD ${macd.toStringAsFixed(4)} · 신호선 ${macdSignal.toStringAsFixed(4)}';
                          }
                          break;
                        case 'bollinger':
                          if (bbUpper != null && bbMiddle != null && bbLower != null) {
                            valueLine = '상단 ${fmtPricePlain(bbUpper)}${overseas ? '' : '원'} · 중단 ${fmtPricePlain(bbMiddle)}${overseas ? '' : '원'} · 하단 ${fmtPricePlain(bbLower)}${overseas ? '' : '원'}';
                          } else if (bbMiddle != null) {
                            valueLine = '중간밴드 ${fmtPricePlain(bbMiddle)}${overseas ? '' : '원'}';
                          }
                          break;
                        case 'movingAverage':
                          if (ma5 != null && ma20 != null && ma60 != null) {
                            valueLine = 'MA5 ${fmtPricePlain(ma5)}${overseas ? '' : '원'} · MA20 ${fmtPricePlain(ma20)}${overseas ? '' : '원'} · MA60 ${fmtPricePlain(ma60)}${overseas ? '' : '원'}';
                          } else if (ma5 != null && ma20 != null) {
                            valueLine = 'MA5 ${fmtPricePlain(ma5)}${overseas ? '' : '원'} · MA20 ${fmtPricePlain(ma20)}${overseas ? '' : '원'}';
                          }
                          break;
                        case 'vwap':
                          if (vwap != null) {
                            // ✅ current 필드에서 현재가 직접 가져오기
                            final current = analysis['current'] as Map<String, dynamic>?;
                            final currentPrice = current?['currentPrice'] as num?;
                            
                            // 🔍 VWAP 디버깅 로그
                            print('🔍 [VWAP 디버그] analysis keys: ${analysis.keys.toList()}');
                            print('🔍 [VWAP 디버그] current: $current');
                            print('🔍 [VWAP 디버그] currentPrice: $currentPrice');
                            print('🔍 [VWAP 디버그] vwap: $vwap');
                            
                            if (currentPrice != null && currentPrice > 0) {
                              final diff = ((currentPrice.toDouble() - vwap) / vwap) * 100;
                              valueLine = 'VWAP ${fmtPricePlain(vwap)}${overseas ? '' : '원'} (현재가 ${fmtPricePlain(currentPrice)}${overseas ? '' : '원'}, ${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}%)';
                            } else {
                              valueLine = 'VWAP ${fmtPricePlain(vwap)}${overseas ? '' : '원'} (현재가 데이터 부족)';
                            }
                          }
                          break;
                        case 'adx':
                          if (adx != null) {
                            final double disp = adx <= 1.0 ? adx * 100.0 : adx; // 0~1 스케일 들어올 경우 보정
                            valueLine = 'ADX ${disp.toStringAsFixed(1)}';
                          }
                          break;
                      }
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
                          if (valueLine.isNotEmpty) ...[const SizedBox(height: 6), Text(valueLine, style: TextStyle(fontSize: 11, color: Colors.grey[700]))],
                          if (detailedReason.isNotEmpty) ...[const SizedBox(height: 6), Text(detailedReason, style: TextStyle(fontSize: 11, color: Colors.grey[600], height: 1.3))],
                          ...[const SizedBox(height: 4), Text(_getCalculationMethod(indicatorName), style: TextStyle(fontSize: 10, color: Colors.grey[500], fontStyle: FontStyle.italic))],
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

  /// 7개 지표 목록 반환 (강제 표시용)
  List<String> _getAllIndicators() {
    return [
      'volume',
      'adx', 
      'macd',
      'vwap',
      'rsi',
      'bollinger',
      'movingAverage',
    ];
  }

  /// 전일대비 등락률을 포함한 분석 이유 생성
  String _buildAnalysisReasonWithPriceChange(String reason, Map<String, dynamic> analysis, String finalSignal, double comprehensiveScore, Map<String, dynamic> individualScores) {
    final technicalData = analysis['technicalData'] as Map<String, dynamic>?;
    if (technicalData == null) {
      return reason.isNotEmpty ? reason : generateComprehensiveAnalysisReason(analysis, finalSignal, comprehensiveScore, individualScores);
    }

    final currentPrice = (technicalData['currentPrice'] as num?)?.toDouble();
    final prevClose = (technicalData['prevClose'] as num?)?.toDouble();
    
    String priceChangeInfo = '';
    if (currentPrice != null && prevClose != null && prevClose > 0) {
      final changeRate = ((currentPrice - prevClose) / prevClose) * 100;
      final changeAmount = currentPrice - prevClose;
      final changeSign = changeAmount >= 0 ? '+' : '';
      priceChangeInfo = '전일 대비 ${changeSign}${changeRate.toStringAsFixed(2)}% (${changeSign}${changeAmount.toStringAsFixed(0)}원)\n\n';
    }

    final baseReason = reason.isNotEmpty ? reason : generateComprehensiveAnalysisReason(analysis, finalSignal, comprehensiveScore, individualScores);
    return priceChangeInfo + baseReason;
  }

  /// 지표별 계산 방법 요약 반환
  String _getCalculationMethod(String indicatorName) {
    switch (indicatorName) {
      case 'volume':
        return '거래량: 현재 거래량 vs 평균 거래량 비교';
      case 'rsi':
        return 'RSI: 14기간 RSI (Gain/Loss EMA 기반)';
      case 'macd':
        return 'MACD: EMA(12) - EMA(26), Signal=EMA(9)';
      case 'bollinger':
        return '볼린저: MA(20) ± 2σ (표준편차)';
      case 'movingAverage':
        return '이동평균: MA(5), MA(20), MA(60)';
      case 'vwap':
        return 'VWAP: ∑(Price×Volume)/∑Volume (일중)';
      case 'adx':
        return 'ADX: 14기간 ADX (DMI 기반)';
      default:
        return '계산식: 데이터 기반 분석';
    }
  }
}
