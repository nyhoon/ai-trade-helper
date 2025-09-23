import 'dart:math';

/// 변동성 계산기
/// ATR(Average True Range) 계산과 변동성 분석 기능
class VolatilityCalculator {
  
  /// ATR(Average True Range) 계산
  /// 
  /// [highs] 고가 리스트
  /// [lows] 저가 리스트
  /// [closes] 종가 리스트
  /// [period] 계산 기간 (기본값: 14)
  /// 
  /// Returns: ATR 값
  static double calculateATR({
    required List<double> highs,
    required List<double> lows,
    required List<double> closes,
    int period = 14,
  }) {
    try {
      print('📊 ATR 계산 시작: 고가=${highs.length}개, 저가=${lows.length}개, 종가=${closes.length}개, 기간=$period');
      
      // 데이터 부족 시 적응적 기간 조정
      int adjustedPeriod = period;
      if (closes.length < period + 1) {
        adjustedPeriod = (closes.length - 1).clamp(5, period); // 최소 5일, 최대 원래 기간
        print('⚠️ 데이터 부족으로 기간 조정: ${period}일 → ${adjustedPeriod}일');
      }
      
      // 실제로 필요한 데이터가 충분한지 확인
      if (highs.length < adjustedPeriod + 1 || lows.length < adjustedPeriod + 1 || closes.length < adjustedPeriod + 1) {
        print('⚠️ ATR 계산을 위한 데이터 부족: 최소 ${adjustedPeriod + 1}개 필요, 현재 ${closes.length}개');
        // 데이터가 부족한 경우 간단한 변동성 계산으로 대체
        if (closes.length >= 2) {
          final simpleVolatility = (highs.last - lows.last) / closes.last * 100;
          print('📊 간단한 변동성 계산으로 대체: ${simpleVolatility.toStringAsFixed(2)}%');
          return simpleVolatility;
        }
        return 0.0;
      }
      
      // True Range 계산
      final List<double> trueRanges = [];
      
      for (int i = 1; i < highs.length; i++) {
        final double high = highs[i];
        final double low = lows[i];
        final double prevClose = closes[i - 1];
        
        // True Range = max(high - low, |high - prevClose|, |low - prevClose|)
        final double tr1 = high - low;
        final double tr2 = (high - prevClose).abs();
        final double tr3 = (low - prevClose).abs();
        
        final double trueRange = [tr1, tr2, tr3].reduce(max);
        trueRanges.add(trueRange);
      }
      
      if (trueRanges.length < adjustedPeriod) {
        print('⚠️ True Range 데이터 부족');
        return 0.0;
      }
      
      // ATR 계산 (단순이동평균 사용)
      double atr = 0.0;
      for (int i = 0; i < adjustedPeriod; i++) {
        atr += trueRanges[trueRanges.length - adjustedPeriod + i];
      }
      atr /= adjustedPeriod;
      
      print('📊 ATR 계산 결과: ${atr.toStringAsFixed(2)} (기간: ${adjustedPeriod}일)');
      
      return atr;
      
    } catch (e) {
      print('⚠️ ATR 계산 실패: $e');
      return 0.0;
    }
  }

  /// 평균 ATR 계산 (과거 데이터 기반)
  /// 
  /// [highs] 고가 리스트
  /// [lows] 저가 리스트
  /// [closes] 종가 리스트
  /// [period] ATR 계산 기간 (기본값: 14)
  /// [lookbackPeriod] 평균 계산 기간 (기본값: 20)
  /// 
  /// Returns: 평균 ATR 값
  static double calculateAverageATR({
    required List<double> highs,
    required List<double> lows,
    required List<double> closes,
    int period = 14,
    int lookbackPeriod = 20,
  }) {
    try {
      print('📊 평균 ATR 계산 시작: 고가=${highs.length}개, 저가=${lows.length}개, 종가=${closes.length}개, 기간=$period, 룩백=$lookbackPeriod');
      
      // 데이터 부족 시 적응적 조정
      int adjustedLookback = lookbackPeriod;
      if (closes.length < period + lookbackPeriod) {
        adjustedLookback = (closes.length - period).clamp(5, lookbackPeriod); // 최소 5일, 최대 원래 기간
        print('⚠️ 데이터 부족으로 룩백 기간 조정: ${lookbackPeriod}일 → ${adjustedLookback}일');
      }
      
      if (highs.length < period + adjustedLookback || 
          lows.length < period + adjustedLookback || 
          closes.length < period + adjustedLookback) {
        print('⚠️ 평균 ATR 계산을 위한 데이터 부족: 최소 ${period + adjustedLookback}개 필요, 현재 ${closes.length}개');
        // 데이터가 부족한 경우 현재 ATR 값으로 대체
        final currentATR = calculateATR(highs: highs, lows: lows, closes: closes, period: period);
        print('📊 현재 ATR 값으로 대체: ${currentATR.toStringAsFixed(2)}');
        return currentATR;
      }
      
      final List<double> atrValues = [];
      
      // 과거 데이터에서 ATR 값들을 계산
      for (int i = 0; i < adjustedLookback; i++) {
        final int startIndex = highs.length - adjustedLookback - period + i;
        final int endIndex = highs.length - adjustedLookback + i;
        
        if (startIndex >= 0 && endIndex <= highs.length) {
          final List<double> highSlice = highs.sublist(startIndex, endIndex);
          final List<double> lowSlice = lows.sublist(startIndex, endIndex);
          final List<double> closeSlice = closes.sublist(startIndex, endIndex);
          
          final double atr = calculateATR(
            highs: highSlice,
            lows: lowSlice,
            closes: closeSlice,
            period: period,
          );
          
          if (atr > 0) {
            atrValues.add(atr);
          }
        }
      }
      
      if (atrValues.isEmpty) {
        print('⚠️ 유효한 ATR 값이 없음');
        return 0.0;
      }
      
      // 평균 ATR 계산
      final double averageATR = atrValues.reduce((a, b) => a + b) / atrValues.length;
      
      print('📊 평균 ATR 계산 결과: ${averageATR.toStringAsFixed(2)} (${atrValues.length}개 데이터)');
      
      return averageATR;
      
    } catch (e) {
      print('⚠️ 평균 ATR 계산 실패: $e');
      return 0.0;
    }
  }

  /// 변동성 데이터 계산 (ATR + 평균 ATR)
  /// 
  /// [highs] 고가 리스트
  /// [lows] 저가 리스트
  /// [closes] 종가 리스트
  /// 
  /// Returns: 변동성 데이터
  static Map<String, dynamic> calculateVolatilityData({
    required List<double> highs,
    required List<double> lows,
    required List<double> closes,
  }) {
    try {
      final double currentATR = calculateATR(
        highs: highs,
        lows: lows,
        closes: closes,
      );
      
      final double averageATR = calculateAverageATR(
        highs: highs,
        lows: lows,
        closes: closes,
      );
      
      return {
        'currentATR': currentATR,
        'averageATR': averageATR,
      };
    } catch (e) {
      print('⚠️ 변동성 데이터 계산 실패: $e');
      return {
        'currentATR': 0.0,
        'averageATR': 0.0,
      };
    }
  }

  /// 변동성 수준 분석
  /// 
  /// [currentATR] 현재 ATR 값
  /// [averageATR] 평균 ATR 값
  /// 
  /// Returns: 변동성 수준 분석 결과
  static Map<String, dynamic> analyzeVolatilityLevel({
    required double currentATR,
    required double averageATR,
  }) {
    try {
      if (averageATR <= 0) {
        return {
          'level': '알 수 없음',
          'ratio': 0.0,
          'description': '평균 ATR이 0 이하입니다.',
          'signal': '중립',
        };
      }
      
      final double ratio = currentATR / averageATR;
      String level;
      String description;
      String signal;
      
      if (ratio >= 2.0) {
        level = '매우 높은 변동성';
        description = '현재 변동성이 평균의 2배 이상으로 매우 높습니다. 박스권 시장일 가능성이 높습니다.';
        signal = '매도 신호 강화 (볼린저밴드, RSI)';
      } else if (ratio >= 1.5) {
        level = '높은 변동성';
        description = '현재 변동성이 평균의 1.5배 이상으로 높습니다. 변동성이 큰 시장입니다.';
        signal = '매도 신호 (볼린저밴드, RSI)';
      } else if (ratio >= 1.2) {
        level = '약간 높은 변동성';
        description = '현재 변동성이 평균보다 약간 높습니다.';
        signal = '중립';
      } else if (ratio >= 0.8) {
        level = '보통 변동성';
        description = '현재 변동성이 평균 수준입니다. 정상적인 시장입니다.';
        signal = '중립';
      } else if (ratio >= 0.5) {
        level = '낮은 변동성';
        description = '현재 변동성이 평균보다 낮습니다. 트렌드 시장일 가능성이 높습니다.';
        signal = '매수 신호 (이동평균선, MACD)';
      } else {
        level = '매우 낮은 변동성';
        description = '현재 변동성이 평균의 절반 이하로 매우 낮습니다. 강한 트렌드 시장입니다.';
        signal = '매수 신호 강화 (이동평균선, MACD)';
      }
      
      return {
        'level': level,
        'ratio': ratio,
        'description': description,
        'signal': signal,
        'currentATR': currentATR,
        'averageATR': averageATR,
      };
      
    } catch (e) {
      print('⚠️ 변동성 수준 분석 실패: $e');
      return {
        'level': '분석 실패',
        'ratio': 0.0,
        'description': '분석 중 오류가 발생했습니다.',
        'signal': '중립',
        'error': e.toString(),
      };
    }
  }

  /// 변동성 기반 지표 조정
  /// 
  /// [baseScore] 기본 점수
  /// [currentATR] 현재 ATR 값
  /// [averageATR] 평균 ATR 값
  /// [indicatorType] 지표 유형 ('rsi', 'bollinger', 'macd', 'movingAverage', 'vwap', 'adx')
  /// 
  /// Returns: 조정된 점수
  static double adjustScoreByVolatility({
    required double baseScore,
    required double currentATR,
    required double averageATR,
    required String indicatorType,
  }) {
    try {
      if (averageATR <= 0) return baseScore;
      
      final double ratio = currentATR / averageATR;
      double adjustment = 0.0;
      
      switch (indicatorType) {
        case 'rsi':
          // RSI: 높은 변동성에서 신호 강화
          if (ratio >= 2.0) adjustment = 0.2;
          else if (ratio >= 1.5) adjustment = 0.1;
          else if (ratio >= 1.2) adjustment = 0.1;
          else if (ratio < 0.8) adjustment = -0.1;
          break;
          
        case 'bollinger':
          // 볼린저밴드: 높은 변동성에서 신호 강화
          if (ratio >= 2.0) adjustment = 0.2;
          else if (ratio >= 1.5) adjustment = 0.1;
          else if (ratio >= 1.2) adjustment = 0.1;
          else if (ratio < 0.8) adjustment = -0.1;
          break;
          
        case 'macd':
          // MACD: 낮은 변동성에서 신호 강화
          if (ratio >= 2.0) adjustment = -0.1;
          else if (ratio >= 1.5) adjustment = -0.1;
          else if (ratio < 0.8) adjustment = 0.2;
          else if (ratio < 0.5) adjustment = 0.3;
          break;
          
        case 'movingAverage':
          // 이동평균선: 낮은 변동성에서 신호 강화
          if (ratio >= 2.0) adjustment = -0.1;
          else if (ratio >= 1.5) adjustment = -0.1;
          else if (ratio < 0.8) adjustment = 0.2;
          else if (ratio < 0.5) adjustment = 0.3;
          break;
          
        case 'vwap':
          // VWAP: 높은 변동성에서 신호 강화
          if (ratio >= 2.0) adjustment = 0.2;
          else if (ratio >= 1.5) adjustment = 0.1;
          else if (ratio >= 1.2) adjustment = 0.1;
          else if (ratio < 0.8) adjustment = -0.1;
          break;
          
        case 'adx':
          // ADX: 낮은 변동성에서 신호 강화
          if (ratio >= 2.0) adjustment = -0.2;
          else if (ratio >= 1.5) adjustment = -0.1;
          else if (ratio < 0.8) adjustment = 0.2;
          else if (ratio < 0.5) adjustment = 0.3;
          break;
          
        default:
          adjustment = 0.0;
      }
      
      final double adjustedScore = baseScore + adjustment;
      
      print('📊 변동성 기반 점수 조정 ($indicatorType):');
      print('  - 기본점수: ${baseScore.toStringAsFixed(3)}');
      print('  - 변동성비율: ${ratio.toStringAsFixed(2)}');
      print('  - 조정값: ${adjustment.toStringAsFixed(3)}');
      print('  - 조정된점수: ${adjustedScore.toStringAsFixed(3)}');
      
      return adjustedScore.clamp(-1.0, 1.0);
      
    } catch (e) {
      print('⚠️ 변동성 기반 점수 조정 실패: $e');
      return baseScore;
    }
  }

  /// 변동성 데이터 분석 (디버깅용)
  static Map<String, dynamic> analyzeVolatilityData({
    required List<double> highs,
    required List<double> lows,
    required List<double> closes,
    int period = 14,
    int lookbackPeriod = 20,
  }) {
    try {
      final double currentATR = calculateATR(
        highs: highs,
        lows: lows,
        closes: closes,
        period: period,
      );
      
      final double averageATR = calculateAverageATR(
        highs: highs,
        lows: lows,
        closes: closes,
        period: period,
        lookbackPeriod: lookbackPeriod,
      );
      
      final Map<String, dynamic> volatilityAnalysis = analyzeVolatilityLevel(
        currentATR: currentATR,
        averageATR: averageATR,
      );
      
      return {
        'currentATR': currentATR,
        'averageATR': averageATR,
        'volatilityAnalysis': volatilityAnalysis,
        'dataPoints': {
          'highs': highs.length,
          'lows': lows.length,
          'closes': closes.length,
        },
        'parameters': {
          'period': period,
          'lookbackPeriod': lookbackPeriod,
        },
      };
      
    } catch (e) {
      print('⚠️ 변동성 데이터 분석 실패: $e');
      return {
        'error': e.toString(),
        'currentATR': 0.0,
        'averageATR': 0.0,
        'volatilityAnalysis': {
          'level': '분석 실패',
          'ratio': 0.0,
          'description': '분석 중 오류가 발생했습니다.',
          'signal': '중립',
        },
      };
    }
  }
}
