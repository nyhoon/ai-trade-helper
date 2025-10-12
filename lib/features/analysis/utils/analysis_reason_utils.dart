import 'package:flutter/material.dart';

typedef GetIndicatorKey = String Function(String indicatorName);
typedef GetKoreanIndicatorName = String Function(String indicatorName);
typedef FormatNumber = String Function(dynamic value);
typedef IsNasdaqStock = bool Function(String stockCode);

class AnalysisReasonUtils {
  static String generateDetailedReason({
    required String indicatorName,
    required double score,
    required String signal,
    required Map<String, dynamic> analysis,
    required GetIndicatorKey getIndicatorKey,
    required GetKoreanIndicatorName getKoreanIndicatorName,
    required FormatNumber formatNumber,
  }) {
    final detailedAnalysis = analysis['detailedAnalysis'] as Map<String, dynamic>? ?? {};
    final indicatorKey = getIndicatorKey(indicatorName);
    final indicatorAnalysis = detailedAnalysis[indicatorKey];
    if (indicatorAnalysis != null && indicatorAnalysis['analysis'] != null) {
      return indicatorAnalysis['analysis'] as String;
    }

    // ✅ current 필드에서 현재가 가져오기
    final current = analysis['current'] as Map<String, dynamic>?;
    final currentPrice = (current?['currentPrice'] as num?)?.toDouble() ?? 0.0;
    final prevClose = (current?['prevClose'] as num?)?.toDouble() ?? currentPrice;
    
    // 🔍 currentPrice 디버깅 로그
    print('🔍 [analysis_reason_utils] current: $current');
    print('🔍 [analysis_reason_utils] currentPrice: $currentPrice');
    print('🔍 [analysis_reason_utils] prevClose: $prevClose');
    final technicalData = analysis['technicalData'] as Map<String, dynamic>? ?? {};
    final priceChangePercent = prevClose > 0 ? ((currentPrice - prevClose) / prevClose) * 100 : 0.0;
    final koreanName = getKoreanIndicatorName(indicatorName);

    switch (indicatorName.toLowerCase()) {
      case 'rsi':
        final rsiValue = (technicalData['rsi'] as num?)?.toDouble();
        if (rsiValue == null || rsiValue == 0.0) {
          return 'RSI 데이터 부족 - 관망 권장';
        }
        if (signal == '매수') {
          if (rsiValue <= 30) return 'RSI ${rsiValue.toStringAsFixed(1)} (과매도 구간) - 반등 기대, 매수 기회';
          if (rsiValue <= 40) return 'RSI ${rsiValue.toStringAsFixed(1)} (매수 구간) - 매수 신호';
          if (rsiValue <= 50) return 'RSI ${rsiValue.toStringAsFixed(1)} (중립선 하회) - 매수 신호';
          return 'RSI ${rsiValue.toStringAsFixed(1)} (상승 추세) - 매수 신호';
        } else if (signal == '매도') {
          if (rsiValue >= 70) return 'RSI ${rsiValue.toStringAsFixed(1)} (과매수 구간) - 하락 예상, 매도 권장';
          if (rsiValue >= 60) return 'RSI ${rsiValue.toStringAsFixed(1)} (매도 구간) - 매도 신호';
          if (rsiValue >= 50) return 'RSI ${rsiValue.toStringAsFixed(1)} (중립선 상회) - 매도 신호';
          return 'RSI ${rsiValue.toStringAsFixed(1)} (하락 추세) - 매도 신호';
        } else {
          return 'RSI ${rsiValue.toStringAsFixed(1)} (중립 구간) - 관망';
        }

      case 'macd':
        final macdValue = (technicalData['macd'] as num?)?.toDouble();
        final signalValue = (technicalData['signal'] as num?)?.toDouble();
        if (macdValue == null || signalValue == null) return 'MACD 데이터 부족 - 관망 권장';
        final histogram = macdValue - signalValue;
        if (signal == '매수') {
          if (histogram > 0) return 'MACD가 신호선 위 (히스토그램 양수) - 상승 모멘텀 강화, 매수 신호';
          return 'MACD가 신호선에 근접 - 상승 전환 신호 대기';
        } else if (signal == '매도') {
          if (histogram < 0) return 'MACD가 신호선 아래 (히스토그램 음수) - 하락 모멘텀 강화, 매도 신호';
          return 'MACD가 신호선에 근접 - 하락 전환 신호 대기';
        } else {
          return 'MACD/신호선이 유사 - 관망';
        }

      case 'bollinger':
      case '볼린저밴드':
        final upper = (technicalData['bbUpper'] as num?)?.toDouble();
        final middle = (technicalData['bbMiddle'] as num?)?.toDouble();
        final lower = (technicalData['bbLower'] as num?)?.toDouble();
        if (upper == null || middle == null || lower == null) return '볼린저밴드 데이터 부족 - 관망 권장';
        final bandWidth = upper - lower;
        final position = bandWidth > 0 ? ((currentPrice - lower) / bandWidth) * 100 : 50.0;
        if (signal == '매수') {
          if (currentPrice <= lower) return '현재가 ${formatNumber(currentPrice)}이 하단 지지선 ${formatNumber(lower)}에 닿아 반등 기대 (상단: ${formatNumber(upper)}, 중단: ${formatNumber(middle)}, 하단: ${formatNumber(lower)}) - 매수 기회';
          if (position <= 30) return '현재가 ${formatNumber(currentPrice)}이 하단 근처 (${position.toStringAsFixed(0)}% 위치) (상단: ${formatNumber(upper)}, 중단: ${formatNumber(middle)}, 하단: ${formatNumber(lower)}) - 저점 매수 기회';
          if (currentPrice >= middle) return '현재가 ${formatNumber(currentPrice)}이 중간선 ${formatNumber(middle)} 위로 상승 중 (상단: ${formatNumber(upper)}, 중단: ${formatNumber(middle)}, 하단: ${formatNumber(lower)}) - 매수 신호';
        } else if (signal == '매도') {
          if (currentPrice >= upper) return '현재가 ${formatNumber(currentPrice)}이 상단 저항선 ${formatNumber(upper)}에 닿아 하락 예상 (상단: ${formatNumber(upper)}, 중단: ${formatNumber(middle)}, 하단: ${formatNumber(lower)}) - 매도 권장';
          if (position >= 70) return '현재가 ${formatNumber(currentPrice)}이 상단 근처 (${position.toStringAsFixed(0)}% 위치) (상단: ${formatNumber(upper)}, 중단: ${formatNumber(middle)}, 하단: ${formatNumber(lower)}) - 고점 매도 기회';
          if (currentPrice <= middle) return '현재가 ${formatNumber(currentPrice)}이 중간선 ${formatNumber(middle)} 아래로 하락 중 (상단: ${formatNumber(upper)}, 중단: ${formatNumber(middle)}, 하단: ${formatNumber(lower)}) - 매도 신호';
        }
        return '현재가 ${formatNumber(currentPrice)}이 중간선 ${formatNumber(middle)} 근처 (${position.toStringAsFixed(0)}% 위치) (상단: ${formatNumber(upper)}, 중단: ${formatNumber(middle)}, 하단: ${formatNumber(lower)}) - 관망';

      case 'movingaverage':
      case '이동평균선':
        final ma5 = (technicalData['ma5'] as num?)?.toDouble();
        final ma20 = (technicalData['ma20'] as num?)?.toDouble();
        final ma60 = (technicalData['ma60'] as num?)?.toDouble();
        if (ma5 == null || ma20 == null || ma60 == null) return '이동평균선 데이터 부족 - 관망 권장';
        if (signal == '매수') {
          if (currentPrice >= ma5 && currentPrice >= ma20 && currentPrice >= ma60) return '현재가 ${formatNumber(currentPrice)}이 모든 이동평균선 위 (MA5: ${formatNumber(ma5)}, MA20: ${formatNumber(ma20)}, MA60: ${formatNumber(ma60)}) - 강한 상승 추세, 매수 기회';
          if (currentPrice >= ma20) return '현재가 ${formatNumber(currentPrice)}이 20일 평균선 ${formatNumber(ma20)} 위로 돌파 - 상승 신호';
          if (ma5 >= ma20) return '단기 평균선 ${formatNumber(ma5)}이 장기 평균선 ${formatNumber(ma20)} 위로 상승 - 매수 신호';
        } else if (signal == '매도') {
          if (currentPrice <= ma5 && currentPrice <= ma20 && currentPrice <= ma60) return '현재가 ${formatNumber(currentPrice)}이 모든 이동평균선 아래 (MA5: ${formatNumber(ma5)}, MA20: ${formatNumber(ma20)}, MA60: ${formatNumber(ma60)}) - 강한 하락 추세, 매도 권장';
          if (currentPrice <= ma20) return '현재가 ${formatNumber(currentPrice)}이 20일 평균선 ${formatNumber(ma20)} 아래로 하락 - 매도 신호';
          if (ma5 <= ma20) return '단기 평균선 ${formatNumber(ma5)}이 장기 평균선 ${formatNumber(ma20)} 아래로 하락 - 매도 신호';
        }
        return '현재가 ${formatNumber(currentPrice)}이 20일 평균선 ${formatNumber(ma20)} 근처 - 관망';

      case 'volume':
      case '거래량':
        final currentVolume = (technicalData['currentVolume'] as num?)?.toDouble();
        final avgVolume = (technicalData['avgVolume'] as num?)?.toDouble();
        if (currentVolume == null || avgVolume == null || avgVolume == 0) return '거래량 데이터 부족 - 관망 권장';
        final volumeRatio = currentVolume / avgVolume;
        if (signal == '매수') {
          if (volumeRatio >= 2.0) return '거래량이 20일 평균 ${formatNumber(avgVolume)}주의 ${volumeRatio.toStringAsFixed(1)}배로 급증 (${formatNumber(currentVolume)}주) - 강한 매수 신호';
          if (volumeRatio >= 1.5) return '거래량이 20일 평균 ${formatNumber(avgVolume)}주의 ${volumeRatio.toStringAsFixed(1)}배로 증가 (${formatNumber(currentVolume)}주) - 매수 신호';
          if (volumeRatio >= 1.2 && priceChangePercent > 0) return '거래량 ${formatNumber(currentVolume)}주로 가격 상승 동반 (20일 평균 ${formatNumber(avgVolume)}주) - 매수 신호';
          if (priceChangePercent > 0) return '거래량 ${formatNumber(currentVolume)}주로 상승 추세 (20일 평균 ${formatNumber(avgVolume)}주) - 매수 고려';
        } else if (signal == '매도') {
          if (volumeRatio >= 2.0) return '거래량이 20일 평균 ${formatNumber(avgVolume)}주의 ${volumeRatio.toStringAsFixed(1)}배로 급증 (${formatNumber(currentVolume)}주) - 강한 매도 신호';
          if (volumeRatio >= 1.5) return '거래량이 20일 평균 ${formatNumber(avgVolume)}주의 ${volumeRatio.toStringAsFixed(1)}배로 증가 (${formatNumber(currentVolume)}주) - 매도 신호';
          if (volumeRatio >= 1.2 && priceChangePercent < 0) return '거래량 ${formatNumber(currentVolume)}주로 가격 하락 동반 (20일 평균 ${formatNumber(avgVolume)}주) - 매도 신호';
          if (priceChangePercent < 0) return '거래량 ${formatNumber(currentVolume)}주로 하락 추세 (20일 평균 ${formatNumber(avgVolume)}주) - 매도 고려';
        }
        return '거래량 ${formatNumber(currentVolume)}주 (20일 평균 ${formatNumber(avgVolume)}주의 ${volumeRatio.toStringAsFixed(1)}배) - 관망';

      case 'vwap':
        final vwapValue = (technicalData['vwap'] as num?)?.toDouble();
        if (vwapValue == null || vwapValue == 0) return 'VWAP 데이터 부족 - 관망 권장';
        
        // 🔍 VWAP 디버깅 로그
        print('🔍 [VWAP reason 디버그] currentPrice: $currentPrice');
        print('🔍 [VWAP reason 디버그] vwapValue: $vwapValue');
        
        // 현재가가 0이면 VWAP 분석 불가
        if (currentPrice == 0 || currentPrice == null) {
          return '현재가 데이터 부족 - VWAP 분석 불가 (VWAP: ${formatNumber(vwapValue)}) - 관망 권장';
        }
        
        final vwapDiff = ((currentPrice - vwapValue) / vwapValue) * 100;
        if (signal == '매수') {
          if (vwapDiff <= -2.0) return '현재가 ${formatNumber(currentPrice)}이 평균가격 ${formatNumber(vwapValue)}보다 ${vwapDiff.abs().toStringAsFixed(1)}% 낮음 - 저점 매수 기회';
          if (vwapDiff <= -1.0) return '현재가 ${formatNumber(currentPrice)}이 평균가격 ${formatNumber(vwapValue)}보다 ${vwapDiff.abs().toStringAsFixed(1)}% 낮음 - 반등 기대';
          if (vwapDiff >= 1.0) return '현재가 ${formatNumber(currentPrice)}이 평균가격 ${formatNumber(vwapValue)}보다 ${vwapDiff.toStringAsFixed(1)}% 높음 - 상승 추세';
        } else if (signal == '매도') {
          if (vwapDiff >= 2.0) return '현재가 ${formatNumber(currentPrice)}이 평균가격 ${formatNumber(vwapValue)}보다 ${vwapDiff.toStringAsFixed(1)}% 높음 - 고점 매도 기회';
          if (vwapDiff >= 1.0) return '현재가 ${formatNumber(currentPrice)}이 평균가격 ${formatNumber(vwapValue)}보다 ${vwapDiff.toStringAsFixed(1)}% 높음 - 하락 예상';
          if (vwapDiff <= -1.0) return '현재가 ${formatNumber(currentPrice)}이 평균가격 ${formatNumber(vwapValue)}과 비슷 (${vwapDiff.abs().toStringAsFixed(1)}% 차이) - 하락 추세';
        }
        return '현재가 ${formatNumber(currentPrice)}이 평균가격 ${formatNumber(vwapValue)}과 비슷 (${vwapDiff.abs().toStringAsFixed(1)}% 차이) - 관망';

      case 'adx':
        final adxValue = (technicalData['adx'] as num?)?.toDouble();
        if (adxValue == null || adxValue == 0.0) return 'ADX 데이터 부족 - 관망 권장';
        if (signal == '매수') return 'ADX ${adxValue.toStringAsFixed(1)} (추세 강함) - 상승 추세 강화';
        if (signal == '매도') return 'ADX ${adxValue.toStringAsFixed(1)} (추세 강함) - 하락 추세 강화';
        return 'ADX ${adxValue.toStringAsFixed(1)} (중립) - 관망';

      default:
        if (signal == '매수') return '$koreanName 상승 신호로 매수';
        if (signal == '매도') return '$koreanName 하락 신호로 매도';
        return '$koreanName 중립 구간으로 관망';
    }
  }

  static String generateComprehensiveAnalysisReason({
    required Map<String, dynamic> analysis,
    required String signal,
    required double aggregateScore,
    required Map<String, dynamic> individualScores,
    required GetKoreanIndicatorName getKoreanIndicatorName,
  }) {
    final currentPrice = (analysis['currentPrice'] as num?)?.toDouble() ?? 0.0;
    final openPrice = (analysis['openPrice'] as num?)?.toDouble() ?? currentPrice;
    final priceChangePercent = openPrice > 0 ? ((currentPrice - openPrice) / openPrice) * 100 : 0.0;
    final reasons = <String>[];

    if (priceChangePercent > 2.0) {
      reasons.add('현재가가 전일 대비 ${priceChangePercent.toStringAsFixed(1)}% 상승하여 강한 상승 모멘텀을 보입니다.');
    } else if (priceChangePercent < -2.0) {
      reasons.add('현재가가 전일 대비 ${priceChangePercent.toStringAsFixed(1)}% 하락하여 하락 압력이 있습니다.');
    } else {
      reasons.add('현재가가 전일 대비 ${priceChangePercent.toStringAsFixed(1)}% 변화로 안정적인 움직임을 보입니다.');
    }

    if (aggregateScore > 0.1) {
      reasons.add('🔥 종합 점수 ${aggregateScore.toStringAsFixed(3)}로 강한 매수 신호를 보입니다.');
    } else if (aggregateScore > 0.05) {
      reasons.add('📈 종합 점수 ${aggregateScore.toStringAsFixed(3)}로 매수 신호를 보입니다.');
    } else if (aggregateScore < -0.1) {
      reasons.add('⚠️ 종합 점수 ${aggregateScore.toStringAsFixed(3)}로 강한 매도 신호를 보입니다.');
    } else if (aggregateScore < -0.05) {
      reasons.add('📉 종합 점수 ${aggregateScore.toStringAsFixed(3)}로 매도 신호를 보입니다.');
    } else {
      reasons.add('⚖️ 종합 점수 ${aggregateScore.toStringAsFixed(3)}로 중립적인 상태입니다.');
    }

    final buyIndicators = <String>[];
    final sellIndicators = <String>[];
    individualScores.forEach((indicatorName, score) {
      final scoreValue = (score as num?)?.toDouble() ?? 0.0;
      if (scoreValue > 0.05) buyIndicators.add(getKoreanIndicatorName(indicatorName));
      if (scoreValue < -0.05) sellIndicators.add(getKoreanIndicatorName(indicatorName));
    });
    if (buyIndicators.isNotEmpty) {
      reasons.add('매수 신호 지표: ${buyIndicators.join(', ')}');
    }
    if (sellIndicators.isNotEmpty) {
      reasons.add('매도 신호 지표: ${sellIndicators.join(', ')}');
    }

    final volume = (analysis['volume'] as num?)?.toDouble() ?? 0.0;
    final avgVolume = (analysis['avgVolume'] as num?)?.toDouble() ?? volume;
    if (avgVolume > 0) {
      final volumeRatio = volume / avgVolume;
      if (volumeRatio > 1.5) {
        reasons.add('거래량이 평균 대비 ${volumeRatio.toStringAsFixed(1)}배로 급증하여 관심이 높습니다.');
      } else if (volumeRatio < 0.5) {
        reasons.add('거래량이 평균 대비 ${volumeRatio.toStringAsFixed(1)}배로 감소하여 관심이 낮습니다.');
      }
    }

    if (signal == '매수') {
      reasons.add('종합적으로 매수 시점으로 판단됩니다.');
    } else if (signal == '매도') {
      reasons.add('종합적으로 매도 시점으로 판단됩니다.');
    } else {
      reasons.add('종합적으로 관망이 적절한 시점입니다.');
    }

    return reasons.join(' ');
  }


  static String getActualValueText({
    required String indicatorName,
    required Map<String, dynamic> analysis,
    required FormatNumber formatNumber,
  }) {
    final technicalData = analysis['technicalData'] as Map<String, dynamic>? ?? {};
    final currentPrice = (analysis['currentPrice'] as num?)?.toDouble() ?? 0.0;

    switch (indicatorName.toLowerCase()) {
      case 'rsi':
        final value = (technicalData['rsi'] as num?)?.toDouble();
        if (value == null || value == 0.0) return 'RSI 데이터 없음';
        return 'RSI ${value.toStringAsFixed(1)}';
      case 'macd':
        final macdValue = (technicalData['macd'] as num?)?.toDouble();
        final signalValue = (technicalData['signal'] as num?)?.toDouble();
        if (macdValue == null || signalValue == null) return 'MACD 데이터 없음';
        return 'MACD ${macdValue.toStringAsFixed(4)} / 신호선 ${signalValue.toStringAsFixed(4)}';
      case 'bollinger':
        final upper = (technicalData['bbUpper'] as num?)?.toDouble();
        final middle = (technicalData['bbMiddle'] as num?)?.toDouble();
        final lower = (technicalData['bbLower'] as num?)?.toDouble();
        if (upper == null || middle == null || lower == null) return '볼린저밴드 데이터 없음';
        final bandWidth = upper - lower;
        final position = bandWidth > 0 ? ((currentPrice - lower) / bandWidth) * 100 : 50.0;
        return '현재가 ${formatNumber(currentPrice)} (${position.toStringAsFixed(1)}%)';
      case 'movingaverage':
        final ma5 = (technicalData['ma5'] as num?)?.toDouble();
        final ma20 = (technicalData['ma20'] as num?)?.toDouble();
        final ma60 = (technicalData['ma60'] as num?)?.toDouble();
        if (ma5 == null || ma20 == null || ma60 == null) return '이동평균선 데이터 없음';
        return '현재가 ${formatNumber(currentPrice)} / MA5 ${formatNumber(ma5)} / MA20 ${formatNumber(ma20)}';
      case 'volume':
        final current = (technicalData['currentVolume'] as num?)?.toDouble();
        final average = (technicalData['avgVolume'] as num?)?.toDouble();
        if (current == null || average == null || average == 0) return '거래량 데이터 없음';
        final ratio = current / average;
        return '거래량 ${formatNumber(current)} (평균의 ${ratio.toStringAsFixed(1)}배)';
      case 'vwap':
        final vwap = (technicalData['vwap'] as num?)?.toDouble();
        if (vwap == null || vwap == 0) return 'VWAP 데이터 없음';
        final difference = currentPrice > 0 ? ((currentPrice - vwap) / vwap) * 100 : 0.0;
        return '현재가 ${formatNumber(currentPrice)} / VWAP ${formatNumber(vwap)} (${difference.toStringAsFixed(1)}%)';
      case 'adx':
        final value = (technicalData['adx'] as num?)?.toDouble();
        if (value == null || value == 0.0) return 'ADX 데이터 없음';
        return 'ADX ${value.toStringAsFixed(1)}';
      default:
        return '';
    }
  }
}


