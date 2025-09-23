import 'volume_dynamic_score_calculator.dart';
import 'rsi_dynamic_score_calculator.dart';
import 'macd_dynamic_score_calculator.dart';
import 'bollinger_dynamic_score_calculator.dart';
import 'moving_average_dynamic_score_calculator.dart';
import 'vwap_dynamic_score_calculator.dart';
import 'adx_dynamic_score_calculator.dart';

/// 종합 지표 점수 계산기
/// 7개 지표의 점수를 종합하여 최종 점수를 계산하고, 매매 실행 기준을 판단
class ComprehensiveIndicatorCalculator {
  
  /// 지표별 가중치 정의
  static const Map<String, double> _indicatorWeights = {
    'volume': 0.20,    // 거래량 (20%)
    'rsi': 0.20,       // RSI (20%)
    'macd': 0.20,      // MACD (20%)
    'bollinger': 0.15, // 볼린저밴드 (15%)
    'movingAverage': 0.15, // 이동평균선 (15%)
    'vwap': 0.05,      // VWAP (5%)
    'adx': 0.05,       // ADX (5%)
  };

  /// 종목별 최신 정상장 거래량 점수 캐시 (비거래시간 유지용)
  static final Map<String, double> _latestTradingVolumeScore = {};

  /// 종합 지표 점수 계산
  /// 
  /// [indicatorData] 각 지표의 계산에 필요한 데이터
  /// [currentTime] 현재 시간 (HH:mm 형식)
  /// [buyThreshold] 사용자 지정 매수 임계값 (SQL에서 불러온 값)
  /// [sellThreshold] 사용자 지정 매도 임계값 (SQL에서 불러온 값)
  /// 
  /// Returns: 종합 점수와 분석 결과
  static Map<String, dynamic> calculateComprehensiveScore({
    required Map<String, dynamic> indicatorData,
    required String currentTime,
    double? buyThreshold,
    double? sellThreshold,
  }) {
    try {
      print('🎯 종합 지표 점수 계산 시작');
      print('📊 입력 데이터: $indicatorData');
      
      // 1. 각 지표별 점수 계산
      final Map<String, double> individualScores = _calculateIndividualScores(
        indicatorData: indicatorData,
        currentTime: currentTime,
      );
      
      // 2. 가중 평균으로 종합 점수 계산
      final double comprehensiveScore = _calculateWeightedAverage(individualScores);
      
      // 3. 매매 실행 기준 판단 (사용자 지정 임계값 사용)
      final String tradingDecision = _determineTradingDecision(
        comprehensiveScore, 
        buyThreshold, 
        sellThreshold
      );
      
      // 4. 신호 강도 분석
      final String signalStrength = _analyzeSignalStrength(comprehensiveScore);
      
      // 5. 상세 분석 결과 생성
      final Map<String, dynamic> analysisResult = _generateAnalysisResult(
        individualScores: individualScores,
        comprehensiveScore: comprehensiveScore,
        tradingDecision: tradingDecision,
        signalStrength: signalStrength,
        indicatorData: indicatorData,
      );
      
      print('✅ 종합 지표 점수 계산 완료');
      print('📊 최종 점수: ${comprehensiveScore.toStringAsFixed(3)}');
      print('📊 매매 결정: $tradingDecision');
      print('📊 신호 강도: $signalStrength');
      
      return analysisResult;
      
    } catch (e) {
      print('⚠️ 종합 지표 점수 계산 실패: $e');
      return {
        'comprehensiveScore': null,
        'tradingDecision': '계산 오류',
        'signalStrength': '계산 오류',
        'individualScores': {},
        'analysis': {},
        'error': e.toString(),
      };
    }
  }

  /// 각 지표별 점수 계산
  static Map<String, double> _calculateIndividualScores({
    required Map<String, dynamic> indicatorData,
    required String currentTime,
  }) {
    final Map<String, double> scores = {};
    
    try {
      // 종목코드 및 거래시간 여부(없으면 true)
      final String symbol = (indicatorData['stockCode'] ?? indicatorData['symbol'] ?? 'unknown').toString();
      final bool isTrading = (indicatorData['isTrading'] as bool?) ?? true;

      // 1. 거래량 점수 계산
      if (isTrading) {
        final volScore = VolumeDynamicScoreCalculator.calculateVolumeScore(
          currentVolume: (indicatorData['currentVolume'] ?? 0).toInt(),
          averageVolume: (indicatorData['averageVolume'] ?? 0).toInt(),
          currentPrice: indicatorData['currentPrice'] ?? 0.0,
          previousPrice: indicatorData['previousPrice'] ?? 0.0,
          openPrice: indicatorData['openPrice'] ?? indicatorData['currentPrice'] ?? 0.0,
          currentTime: currentTime,
        );
        scores['volume'] = volScore;
        // 정상장 값 캐시
        _latestTradingVolumeScore[symbol] = volScore;
      } else {
        // 비거래시간: 마지막 정상장 값 유지, 없으면 중립(0)
        final cached = _latestTradingVolumeScore[symbol];
        scores['volume'] = cached ?? 0.0;
      }
      
      // 2. RSI 점수 계산 (ATR 사용)
      final rsiValue = indicatorData['rsiValue'] as double?;
      if (rsiValue != null) {
        scores['rsi'] = RSIDynamicScoreCalculator.calculateRSIScore(
          rsiValue: rsiValue,
          currentVolume: (indicatorData['currentVolume'] ?? 0).toInt(),
          averageVolume: (indicatorData['averageVolume'] ?? 0).toInt(),
          currentATR: indicatorData['currentATR'] ?? 0.0,
          averageATR: indicatorData['averageATR'] ?? 0.0,
          currentTime: currentTime,
        );
      } else {
        print('⚠️ RSI 값이 없어서 계산 생략');
      }
      
      // 3. MACD 점수 계산 (ATR 사용 안함)
      final macdValue = indicatorData['macdValue'] as double?;
      final signalValue = indicatorData['signalValue'] as double?;
      if (macdValue != null && signalValue != null) {
        scores['macd'] = MACDDynamicScoreCalculator.calculateMACDScore(
          macdValue: macdValue,
          signalValue: signalValue,
          adxValue: indicatorData['adxValue'] ?? 0.0,
          currentVolume: (indicatorData['currentVolume'] ?? 0).toInt(),
          averageVolume: (indicatorData['averageVolume'] ?? 0).toInt(),
          currentTime: currentTime,
        );
      } else {
        print('⚠️ MACD 값이 없어서 계산 생략');
      }
      
      // 4. 볼린저밴드 점수 계산 (ATR 사용)
      final upperBand = indicatorData['upperBand'] as double?;
      final middleBand = indicatorData['middleBand'] as double?;
      final lowerBand = indicatorData['lowerBand'] as double?;
      if (upperBand != null && middleBand != null && lowerBand != null) {
        scores['bollinger'] = BollingerDynamicScoreCalculator.calculateBollingerScore(
          currentPrice: indicatorData['currentPrice'] ?? 0.0,
          upperBand: upperBand,
          middleBand: middleBand,
          lowerBand: lowerBand,
          currentATR: indicatorData['currentATR'] ?? 0.0,
          averageATR: indicatorData['averageATR'] ?? 0.0,
          currentVolume: (indicatorData['currentVolume'] ?? 0).toInt(),
          averageVolume: (indicatorData['averageVolume'] ?? 0).toInt(),
          currentTime: currentTime,
        );
      } else {
        print('⚠️ 볼린저밴드 값이 없어서 계산 생략');
      }
      
      // 5. 이동평균선 점수 계산 (ATR 사용 안함)
      final ma5 = indicatorData['ma5'] as double?;
      final ma20 = indicatorData['ma20'] as double?;
      final ma60 = indicatorData['ma60'] as double?;
      if (ma5 != null && ma20 != null && ma60 != null) {
        scores['movingAverage'] = MovingAverageDynamicScoreCalculator.calculateMovingAverageScore(
          ma5: ma5,
          ma20: ma20,
          ma60: ma60,
          adxValue: indicatorData['adxValue'] ?? 0.0,
          currentVolume: (indicatorData['currentVolume'] ?? 0).toInt(),
          averageVolume: (indicatorData['averageVolume'] ?? 0).toInt(),
          currentTime: currentTime,
        );
      } else {
        print('⚠️ 이동평균선 값이 없어서 계산 생략');
      }
      
      // 6. VWAP 점수 계산 (ATR 사용)
      final vwapValue = indicatorData['vwapValue'] as double?;
      if (vwapValue != null) {
        scores['vwap'] = VWAPDynamicScoreCalculator.calculateVWAPScore(
          currentPrice: indicatorData['currentPrice'] ?? 0.0,
          vwapValue: vwapValue,
          currentVolume: (indicatorData['currentVolume'] ?? 0).toInt(),
          averageVolume: (indicatorData['averageVolume'] ?? 0).toInt(),
          currentATR: indicatorData['currentATR'] ?? 0.0,
          averageATR: indicatorData['averageATR'] ?? 0.0,
          currentTime: currentTime,
        );
      } else {
        print('⚠️ VWAP 값이 없어서 계산 생략');
      }
      
      // 7. ADX 점수 계산 (ATR 사용)
      final adxValue = indicatorData['adxValue'] as double?;
      if (adxValue != null) {
        scores['adx'] = ADXDynamicScoreCalculator.calculateADXScore(
          adxValue: adxValue,
          currentVolume: (indicatorData['currentVolume'] ?? 0).toInt(),
          averageVolume: (indicatorData['averageVolume'] ?? 0).toInt(),
          currentATR: indicatorData['currentATR'] ?? 0.0,
          averageATR: indicatorData['averageATR'] ?? 0.0,
          currentTime: currentTime,
        );
      } else {
        print('⚠️ ADX 값이 없어서 계산 생략');
      }

      return scores;
    } catch (e) {
      print('⚠️ 개별 지표 점수 계산 실패: $e');
      return scores;
    }
  }

  /// 가중 평균 계산 (제공된 지표 구성에 맞게 수정)
  /// 각 지표는 이미 -1.0 ~ 1.0 범위로 정규화되어 있으므로
  /// 가중 평균 후에도 -1.0 ~ 1.0 범위를 유지해야 함
  static double _calculateWeightedAverage(Map<String, double> individualScores) {
    double weightedSum = 0.0;
    
    print('📊 가중 평균 계산 시작:');
    
    individualScores.forEach((indicator, score) {
      final weight = _indicatorWeights[indicator] ?? 0.0;
      final contribution = score * weight;
      weightedSum += contribution;
      
      print('  - $indicator: 점수=${score.toStringAsFixed(3)}, 가중치=${weight.toStringAsFixed(2)}, 기여도=${contribution.toStringAsFixed(3)}');
    });
    
    print('📊 총 가중합: ${weightedSum.toStringAsFixed(3)}');
    
    // 가중치 합계는 1.0이므로 나누지 않음 (이미 정규화됨)
    // 각 지표의 점수(-1.0~1.0) × 가중치(총합 1.0) = 최종 점수(-1.0~1.0)
    final finalScore = weightedSum.clamp(-1.0, 1.0);
    
    print('📊 최종 점수: ${finalScore.toStringAsFixed(3)}');
    
    return finalScore;
  }

  /// 매매 실행 기준 판단 (사용자 지정 임계값 사용)
  static String _determineTradingDecision(
    double comprehensiveScore, 
    double? buyThreshold, 
    double? sellThreshold
  ) {
    // 사용자 지정 임계값이 있으면 사용, 없으면 기본값 사용
    final double immediateBuyThreshold = buyThreshold ?? 0.6;
    final double buyInterestThreshold = buyThreshold != null ? buyThreshold * 0.67 : 0.4;
    final double immediateSellThreshold = sellThreshold ?? -0.6;
    final double sellInterestThreshold = sellThreshold != null ? sellThreshold * 0.67 : -0.4;
    
    if (comprehensiveScore >= immediateBuyThreshold) {
      return '즉시 매수';
    } else if (comprehensiveScore >= buyInterestThreshold) {
      return '관심 지켜보기 (매수)';
    } else if (comprehensiveScore <= immediateSellThreshold) {
      return '즉시 매도';
    } else if (comprehensiveScore <= sellInterestThreshold) {
      return '관심 지켜보기 (매도)';
    } else {
      return '관망';
    }
  }

  /// 신호 강도 분석
  static String _analyzeSignalStrength(double comprehensiveScore) {
    final absScore = comprehensiveScore.abs();
    
    if (absScore >= 0.8) {
      return '매우 강한 신호';
    } else if (absScore >= 0.6) {
      return '강한 신호';
    } else if (absScore >= 0.4) {
      return '보통 신호';
    } else if (absScore >= 0.2) {
      return '약한 신호';
    } else {
      return '매우 약한 신호';
    }
  }

  /// 상세 분석 결과 생성
  static Map<String, dynamic> _generateAnalysisResult({
    required Map<String, double> individualScores,
    required double comprehensiveScore,
    required String tradingDecision,
    required String signalStrength,
    required Map<String, dynamic> indicatorData,
  }) {
    // 지표별 기여도 계산
    final Map<String, double> contributions = {};
    individualScores.forEach((indicator, score) {
      final weight = _indicatorWeights[indicator] ?? 0.0;
      contributions[indicator] = score * weight;
    });
    
    // 상위 기여 지표 찾기
    final sortedContributions = contributions.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    
    final topContributors = sortedContributions.take(3).map((e) => {
      'indicator': e.key,
      'contribution': e.value,
      'weight': _indicatorWeights[e.key] ?? 0.0,
    }).toList();
    
    // 각 지표별 상세 분석 생성
    final Map<String, dynamic> detailedAnalysis = _generateDetailedAnalysis(
      individualScores: individualScores,
      contributions: contributions,
      indicatorData: indicatorData,
    );
    
    return {
      'comprehensiveScore': comprehensiveScore,
      'tradingDecision': tradingDecision,
      'signalStrength': signalStrength,
      'individualScores': individualScores,
      'contributions': contributions,
      'topContributors': topContributors,
      'detailedAnalysis': detailedAnalysis,
      'analysis': {
        'scoreRange': _getScoreRange(comprehensiveScore),
        'confidence': _getConfidence(comprehensiveScore),
        'recommendation': _getRecommendation(comprehensiveScore),
        'riskLevel': _getRiskLevel(comprehensiveScore),
      },
      'timestamp': DateTime.now().toIso8601String(),
      'currentTime': indicatorData['currentTime'] ?? '',
    };
  }

  /// 점수 범위 분석
  static String _getScoreRange(double score) {
    if (score >= 0.8) return '매우 강한 매수 구간';
    if (score >= 0.6) return '강한 매수 구간';
    if (score >= 0.4) return '약한 매수 구간';
    if (score >= 0.2) return '매우 약한 매수 구간';
    if (score >= -0.2) return '중립 구간';
    if (score >= -0.4) return '매우 약한 매도 구간';
    if (score >= -0.6) return '약한 매도 구간';
    if (score >= -0.8) return '강한 매도 구간';
    return '매우 강한 매도 구간';
  }

  /// 신뢰도 분석
  static String _getConfidence(double score) {
    final absScore = score.abs();
    if (absScore >= 0.8) return '매우 높음 (90%+)';
    if (absScore >= 0.6) return '높음 (80-90%)';
    if (absScore >= 0.4) return '보통 (60-80%)';
    if (absScore >= 0.2) return '낮음 (40-60%)';
    return '매우 낮음 (40% 미만)';
  }

  /// 추천 사항
  static String _getRecommendation(double score) {
    if (score >= 0.6) return '즉시 매수 실행 권장';
    if (score >= 0.4) return '매수 관심, 추가 신호 대기';
    if (score <= -0.6) return '즉시 매도 실행 권장';
    if (score <= -0.4) return '매도 관심, 추가 신호 대기';
    return '관망, 명확한 신호 대기';
  }

  /// 위험도 분석
  static String _getRiskLevel(double score) {
    final absScore = score.abs();
    if (absScore >= 0.8) return '낮음 (강한 신호)';
    if (absScore >= 0.6) return '보통 (확실한 신호)';
    if (absScore >= 0.4) return '보통 (약한 신호)';
    if (absScore >= 0.2) return '높음 (불확실한 신호)';
    return '매우 높음 (신호 없음)';
  }

  /// 각 지표별 상세 분석 생성
  static Map<String, dynamic> _generateDetailedAnalysis({
    required Map<String, double> individualScores,
    required Map<String, double> contributions,
    required Map<String, dynamic> indicatorData,
  }) {
    final Map<String, dynamic> analysis = {};
    
    // RSI 분석
    final rsiValue = indicatorData['rsiValue'] ?? 50.0;
    final rsiScore = individualScores['rsi'] ?? 0.0;
    final rsiContribution = contributions['rsi'] ?? 0.0;
    
    String rsiAnalysis = '';
    if (rsiValue >= 70) {
      rsiAnalysis = 'RSI ${rsiValue.toStringAsFixed(1)} (과매수 구간) - 매도 신호';
    } else if (rsiValue >= 60) {
      rsiAnalysis = 'RSI ${rsiValue.toStringAsFixed(1)} (과매수 구간) - 매도 신호';
    } else if (rsiValue <= 30) {
      rsiAnalysis = 'RSI ${rsiValue.toStringAsFixed(1)} (과매도 구간) - 매수 신호';
    } else if (rsiValue <= 40) {
      rsiAnalysis = 'RSI ${rsiValue.toStringAsFixed(1)} (과매도 구간) - 매수 신호';
    } else {
      rsiAnalysis = 'RSI ${rsiValue.toStringAsFixed(1)} (중립 구간) - 관망';
    }
    
    // MACD 분석
    final macdValue = indicatorData['macdValue'] ?? 0.0;
    final signalValue = indicatorData['signalValue'] ?? 0.0;
    final macdScore = individualScores['macd'] ?? 0.0;
    final macdContribution = contributions['macd'] ?? 0.0;
    
    String macdAnalysis = '';
    if (macdValue > signalValue && macdValue > 0) {
      macdAnalysis = 'MACD ${macdValue.toStringAsFixed(4)} > 신호선 ${signalValue.toStringAsFixed(4)} (골든크로스, 상승 전환) - 매수 신호';
    } else if (macdValue < signalValue && macdValue < 0) {
      macdAnalysis = 'MACD ${macdValue.toStringAsFixed(4)} < 신호선 ${signalValue.toStringAsFixed(4)} (데드크로스, 하락 전환) - 매도 신호';
    } else if (macdValue > signalValue) {
      macdAnalysis = 'MACD ${macdValue.toStringAsFixed(4)} > 신호선 ${signalValue.toStringAsFixed(4)} (상승 추세) - 매수 신호';
    } else {
      macdAnalysis = 'MACD ${macdValue.toStringAsFixed(4)} < 신호선 ${signalValue.toStringAsFixed(4)} (하락 추세) - 매도 신호';
    }
    
    // 볼린저밴드 분석
    final currentPrice = indicatorData['currentPrice'] ?? 0.0;
    final upperBand = indicatorData['upperBand'] ?? currentPrice;
    final middleBand = indicatorData['middleBand'] ?? currentPrice;
    final lowerBand = indicatorData['lowerBand'] ?? currentPrice;
    final bbScore = individualScores['bollinger'] ?? 0.0;
    final bbContribution = contributions['bollinger'] ?? 0.0;
    
    final bbPosition = ((currentPrice - lowerBand) / (upperBand - lowerBand) * 100).clamp(0.0, 100.0);
    String bbAnalysis = '';
    if (currentPrice > upperBand) {
      bbAnalysis = '현재가 ${currentPrice.toStringAsFixed(0)} > 상단밴드 ${upperBand.toStringAsFixed(0)} (과매수, ${bbPosition.toStringAsFixed(1)}%) - 매도 신호';
    } else if (currentPrice < lowerBand) {
      bbAnalysis = '현재가 ${currentPrice.toStringAsFixed(0)} < 하단밴드 ${lowerBand.toStringAsFixed(0)} (과매도, ${bbPosition.toStringAsFixed(1)}%) - 매수 신호';
    } else if (currentPrice > middleBand) {
      bbAnalysis = '현재가 ${currentPrice.toStringAsFixed(0)} > 중간밴드 ${middleBand.toStringAsFixed(0)} (상승 구간, ${bbPosition.toStringAsFixed(1)}%) - 매수 신호';
    } else {
      bbAnalysis = '현재가 ${currentPrice.toStringAsFixed(0)} < 중간밴드 ${middleBand.toStringAsFixed(0)} (하락 구간, ${bbPosition.toStringAsFixed(1)}%) - 매도 신호';
    }
    
    // 이동평균선 분석
    final ma5 = indicatorData['ma5'] ?? currentPrice;
    final ma20 = indicatorData['ma20'] ?? currentPrice;
    final ma60 = indicatorData['ma60'] ?? currentPrice;
    final maScore = individualScores['movingAverage'] ?? 0.0;
    final maContribution = contributions['movingAverage'] ?? 0.0;
    
    String maAnalysis = '';
    if (currentPrice > ma5 && ma5 > ma20 && ma20 > ma60) {
      maAnalysis = '이동평균선 정배열 (${currentPrice.toStringAsFixed(0)} > ${ma5.toStringAsFixed(0)} > ${ma20.toStringAsFixed(0)} > ${ma60.toStringAsFixed(0)}) - 강한 매수 신호';
    } else if (currentPrice < ma5 && ma5 < ma20 && ma20 < ma60) {
      maAnalysis = '이동평균선 역배열 (${currentPrice.toStringAsFixed(0)} < ${ma5.toStringAsFixed(0)} < ${ma20.toStringAsFixed(0)} < ${ma60.toStringAsFixed(0)}) - 강한 매도 신호';
    } else if (currentPrice > ma5 && ma5 > ma20) {
      maAnalysis = '단기 상승 추세 (${currentPrice.toStringAsFixed(0)} > ${ma5.toStringAsFixed(0)} > ${ma20.toStringAsFixed(0)}) - 매수 신호';
    } else if (currentPrice < ma5 && ma5 < ma20) {
      maAnalysis = '단기 하락 추세 (${currentPrice.toStringAsFixed(0)} < ${ma5.toStringAsFixed(0)} < ${ma20.toStringAsFixed(0)}) - 매도 신호';
    } else {
      maAnalysis = '이동평균선 혼재 (${currentPrice.toStringAsFixed(0)} vs ${ma5.toStringAsFixed(0)} vs ${ma20.toStringAsFixed(0)} vs ${ma60.toStringAsFixed(0)}) - 관망';
    }
    
    // 거래량 분석
    final currentVolume = indicatorData['currentVolume'] ?? 0;
    final averageVolume = indicatorData['averageVolume'] ?? 1;
    final volumeScore = individualScores['volume'] ?? 0.0;
    final volumeContribution = contributions['volume'] ?? 0.0;
    
    final volumeRatio = averageVolume > 0 ? currentVolume / averageVolume : 1.0;
    String volumeAnalysis = '';
    if (volumeRatio >= 2.0) {
      volumeAnalysis = '거래량 ${currentVolume.toStringAsFixed(0)} (평균의 ${volumeRatio.toStringAsFixed(1)}배) - 급증으로 매수 신호 강화';
    } else if (volumeRatio >= 1.5) {
      volumeAnalysis = '거래량 ${currentVolume.toStringAsFixed(0)} (평균의 ${volumeRatio.toStringAsFixed(1)}배) - 증가로 매수 신호';
    } else if (volumeRatio <= 0.5) {
      volumeAnalysis = '거래량 ${currentVolume.toStringAsFixed(0)} (평균의 ${volumeRatio.toStringAsFixed(1)}배) - 부족으로 매도 신호';
    } else {
      volumeAnalysis = '거래량 ${currentVolume.toStringAsFixed(0)} (평균의 ${volumeRatio.toStringAsFixed(1)}배) - 보통 수준';
    }
    
    // VWAP 분석
    final vwapValue = indicatorData['vwapValue'] ?? currentPrice;
    final vwapScore = individualScores['vwap'] ?? 0.0;
    final vwapContribution = contributions['vwap'] ?? 0.0;
    
    final vwapDiff = ((currentPrice - vwapValue) / vwapValue * 100).clamp(-100.0, 100.0);
    String vwapAnalysis = '';
    if (currentPrice > vwapValue && vwapDiff > 1.0) {
      vwapAnalysis = '현재가 ${currentPrice.toStringAsFixed(0)} > VWAP ${vwapValue.toStringAsFixed(0)} (${vwapDiff.toStringAsFixed(1)}% 높음, 상승 추세) - 매수 신호';
    } else if (currentPrice < vwapValue && vwapDiff < -1.0) {
      vwapAnalysis = '현재가 ${currentPrice.toStringAsFixed(0)} < VWAP ${vwapValue.toStringAsFixed(0)} (${vwapDiff.abs().toStringAsFixed(1)}% 낮음, 하락 추세) - 매도 신호';
    } else if (currentPrice > vwapValue) {
      vwapAnalysis = '현재가 ${currentPrice.toStringAsFixed(0)} > VWAP ${vwapValue.toStringAsFixed(0)} (${vwapDiff.toStringAsFixed(1)}% 높음) - 약한 매수 신호';
    } else {
      vwapAnalysis = '현재가 ${currentPrice.toStringAsFixed(0)} < VWAP ${vwapValue.toStringAsFixed(0)} (${vwapDiff.abs().toStringAsFixed(1)}% 낮음) - 약한 매도 신호';
    }
    
    // ADX 분석
    final adxValue = indicatorData['adxValue'] ?? 25.0;
    final adxScore = individualScores['adx'] ?? 0.0;
    final adxContribution = contributions['adx'] ?? 0.0;
    
    String adxAnalysis = '';
    if (adxValue >= 25.0) {
      adxAnalysis = 'ADX ${adxValue.toStringAsFixed(1)} (강한 추세) - 신호 신뢰도 높음';
    } else if (adxValue >= 20.0) {
      adxAnalysis = 'ADX ${adxValue.toStringAsFixed(1)} (보통 추세) - 신호 신뢰도 보통';
    } else {
      adxAnalysis = 'ADX ${adxValue.toStringAsFixed(1)} (약한 추세) - 신호 신뢰도 낮음';
    }
    
    analysis['rsi'] = {
      'value': rsiValue,
      'score': rsiScore,
      'contribution': rsiContribution,
      'analysis': rsiAnalysis,
    };
    
    analysis['macd'] = {
      'value': macdValue,
      'signal': signalValue,
      'score': macdScore,
      'contribution': macdContribution,
      'analysis': macdAnalysis,
    };
    
    analysis['bollinger'] = {
      'currentPrice': currentPrice,
      'upper': upperBand,
      'middle': middleBand,
      'lower': lowerBand,
      'position': bbPosition,
      'score': bbScore,
      'contribution': bbContribution,
      'analysis': bbAnalysis,
    };
    
    analysis['movingAverage'] = {
      'currentPrice': currentPrice,
      'ma5': ma5,
      'ma20': ma20,
      'ma60': ma60,
      'score': maScore,
      'contribution': maContribution,
      'analysis': maAnalysis,
    };
    
    analysis['volume'] = {
      'current': currentVolume,
      'average': averageVolume,
      'ratio': volumeRatio,
      'score': volumeScore,
      'contribution': volumeContribution,
      'analysis': volumeAnalysis,
    };
    
    analysis['vwap'] = {
      'currentPrice': currentPrice,
      'vwap': vwapValue,
      'difference': vwapDiff,
      'score': vwapScore,
      'contribution': vwapContribution,
      'analysis': vwapAnalysis,
    };
    
    analysis['adx'] = {
      'value': adxValue,
      'score': adxScore,
      'contribution': adxContribution,
      'analysis': adxAnalysis,
    };
    
    return analysis;
  }
}
