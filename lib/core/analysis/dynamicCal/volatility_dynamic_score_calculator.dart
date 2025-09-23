import 'dart:math';
import 'package:ai_helper/core/analysis/technical_indicators.dart';

/// 변동성 동적 점수 계산기
class VolatilityDynamicScoreCalculator {
  /// 변동성 동적 점수 계산
  static double calculateVolatilityScore(Map<String, dynamic> indicatorData) {
    try {
      final List<double> prices = (indicatorData['prices'] as List<dynamic>?)
          ?.map((e) => (e as num).toDouble())
          .toList() ?? [];
      
      final List<double> highs = (indicatorData['highs'] as List<dynamic>?)
          ?.map((e) => (e as num).toDouble())
          .toList() ?? [];
      
      final List<double> lows = (indicatorData['lows'] as List<dynamic>?)
          ?.map((e) => (e as num).toDouble())
          .toList() ?? [];
      
      final List<int> volumes = (indicatorData['volumes'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt())
          .toList() ?? [];
      
      if (prices.length < 20) {
        return 50.0; // 기본 중립 점수
      }
      
      // 1. 볼린저 밴드 변동성 분석
      final bbScore = _calculateBollingerBandVolatility(prices);
      
      // 2. ATR (Average True Range) 기반 변동성
      final atrScore = _calculateATRVolatility(highs, lows, prices);
      
      // 3. 가격 변동성 (표준편차)
      final priceVolatilityScore = _calculatePriceVolatility(prices);
      
      // 4. 거래량 변동성
      final volumeVolatilityScore = _calculateVolumeVolatility(volumes);
      
      // 5. VIX 스타일 변동성 (단기 vs 장기 변동성)
      final vixStyleScore = _calculateVIXStyleVolatility(prices);
      
      // 가중 평균으로 최종 점수 계산
      final double finalScore = (
        bbScore * 0.25 +
        atrScore * 0.25 +
        priceVolatilityScore * 0.20 +
        volumeVolatilityScore * 0.15 +
        vixStyleScore * 0.15
      );
      
      return finalScore.clamp(0.0, 100.0);
      
    } catch (e) {
      print('❌ 변동성 점수 계산 오류: $e');
      return 50.0;
    }
  }
  
  /// 볼린저 밴드 기반 변동성 점수
  static double _calculateBollingerBandVolatility(List<double> prices) {
    try {
      final bb = TechnicalIndicators.calculateBollingerBands(prices, period: 20, stdDev: 2.0);
      final currentPrice = prices.last;
      final upperBand = bb['upper']!;
      final lowerBand = bb['lower']!;
      final middleBand = bb['middle']!;
      
      // 볼린저 밴드 폭 계산
      final bandWidth = (upperBand - lowerBand) / middleBand;
      
      // 현재 가격이 볼린저 밴드 내에서의 위치
      final pricePosition = (currentPrice - lowerBand) / (upperBand - lowerBand);
      
      // 변동성이 클수록 높은 점수 (0-100)
      double volatilityScore = (bandWidth * 1000).clamp(0.0, 100.0);
      
      // 가격이 극단에 위치할 때 추가 점수
      if (pricePosition < 0.1 || pricePosition > 0.9) {
        volatilityScore += 10.0;
      }
      
      return volatilityScore.clamp(0.0, 100.0);
      
    } catch (e) {
      print('❌ 볼린저 밴드 변동성 계산 오류: $e');
      return 50.0;
    }
  }
  
  /// ATR 기반 변동성 점수
  static double _calculateATRVolatility(
    List<double> highs,
    List<double> lows,
    List<double> closes,
  ) {
    try {
      if (highs.length < 14 || lows.length < 14 || closes.length < 14) {
        return 50.0;
      }
      
      List<double> trueRanges = [];
      
      for (int i = 1; i < highs.length; i++) {
        double tr1 = highs[i] - lows[i];
        double tr2 = (highs[i] - closes[i - 1]).abs();
        double tr3 = (lows[i] - closes[i - 1]).abs();
        trueRanges.add([tr1, tr2, tr3].reduce((a, b) => a > b ? a : b));
      }
      
      if (trueRanges.length < 14) return 50.0;
      
      // 14일 ATR 계산
      double atr = trueRanges.take(14).reduce((a, b) => a + b) / 14;
      
      // 현재 가격 대비 ATR 비율
      double currentPrice = closes.last;
      double atrRatio = atr / currentPrice;
      
      // 변동성이 클수록 높은 점수
      double volatilityScore = (atrRatio * 10000).clamp(0.0, 100.0);
      
      return volatilityScore;
      
    } catch (e) {
      print('❌ ATR 변동성 계산 오류: $e');
      return 50.0;
    }
  }
  
  /// 가격 변동성 점수 (표준편차 기반)
  static double _calculatePriceVolatility(List<double> prices) {
    try {
      if (prices.length < 20) return 50.0;
      
      // 최근 20일 가격 데이터
      final recentPrices = prices.sublist(prices.length - 20);
      
      // 평균 계산
      double mean = recentPrices.reduce((a, b) => a + b) / recentPrices.length;
      
      // 분산 계산
      double variance = 0.0;
      for (double price in recentPrices) {
        variance += (price - mean) * (price - mean);
      }
      variance /= recentPrices.length;
      
      // 표준편차
      double standardDeviation = sqrt(variance);
      
      // 변동성 계수 (CV)
      double coefficientOfVariation = standardDeviation / mean;
      
      // 변동성이 클수록 높은 점수
      double volatilityScore = (coefficientOfVariation * 1000).clamp(0.0, 100.0);
      
      return volatilityScore;
      
    } catch (e) {
      print('❌ 가격 변동성 계산 오류: $e');
      return 50.0;
    }
  }
  
  /// 거래량 변동성 점수
  static double _calculateVolumeVolatility(List<int> volumes) {
    try {
      if (volumes.length < 20) return 50.0;
      
      // 최근 20일 거래량 데이터
      final recentVolumes = volumes.sublist(volumes.length - 20);
      
      // 평균 거래량
      double meanVolume = recentVolumes.reduce((a, b) => a + b) / recentVolumes.length;
      
      // 분산 계산
      double variance = 0.0;
      for (int volume in recentVolumes) {
        variance += (volume - meanVolume) * (volume - meanVolume);
      }
      variance /= recentVolumes.length;
      
      // 표준편차
      double standardDeviation = sqrt(variance);
      
      // 거래량 변동성 계수
      double volumeVolatility = standardDeviation / meanVolume;
      
      // 거래량 변동성이 클수록 높은 점수
      double volatilityScore = (volumeVolatility * 100).clamp(0.0, 100.0);
      
      return volatilityScore;
      
    } catch (e) {
      print('❌ 거래량 변동성 계산 오류: $e');
      return 50.0;
    }
  }
  
  /// VIX 스타일 변동성 점수 (단기 vs 장기 변동성)
  static double _calculateVIXStyleVolatility(List<double> prices) {
    try {
      if (prices.length < 30) return 50.0;
      
      // 단기 변동성 (5일)
      final shortTermPrices = prices.sublist(prices.length - 5);
      double shortTermVolatility = _calculatePriceVolatility(shortTermPrices);
      
      // 장기 변동성 (20일)
      final longTermPrices = prices.sublist(prices.length - 20);
      double longTermVolatility = _calculatePriceVolatility(longTermPrices);
      
      // 변동성 비율 (단기/장기)
      double volatilityRatio = longTermVolatility > 0 
          ? shortTermVolatility / longTermVolatility 
          : 1.0;
      
      // 단기 변동성이 장기 변동성보다 클 때 높은 점수
      double vixScore = 50.0;
      if (volatilityRatio > 1.2) {
        vixScore = 80.0; // 높은 변동성
      } else if (volatilityRatio > 1.0) {
        vixScore = 60.0; // 중간 변동성
      } else if (volatilityRatio < 0.8) {
        vixScore = 30.0; // 낮은 변동성
      }
      
      return vixScore;
      
    } catch (e) {
      print('❌ VIX 스타일 변동성 계산 오류: $e');
      return 50.0;
    }
  }
  
  /// 변동성 점수 해석
  static String interpretVolatilityScore(double score) {
    if (score >= 80) {
      return '매우 높은 변동성';
    } else if (score >= 60) {
      return '높은 변동성';
    } else if (score >= 40) {
      return '보통 변동성';
    } else if (score >= 20) {
      return '낮은 변동성';
    } else {
      return '매우 낮은 변동성';
    }
  }
  
  /// 변동성 기반 매매 신호 생성
  static Map<String, dynamic> generateVolatilitySignal(double score) {
    String signal = 'HOLD';
    String reason = '';
    double confidence = 0.0;
    
    if (score >= 80) {
      signal = 'SELL';
      reason = '매우 높은 변동성으로 인한 리스크 증가';
      confidence = 0.8;
    } else if (score >= 60) {
      signal = 'CAUTION';
      reason = '높은 변동성으로 인한 주의 필요';
      confidence = 0.6;
    } else if (score <= 20) {
      signal = 'BUY';
      reason = '낮은 변동성으로 인한 안정성 확보';
      confidence = 0.7;
    } else {
      signal = 'HOLD';
      reason = '보통 수준의 변동성';
      confidence = 0.5;
    }
    
    return {
      'signal': signal,
      'reason': reason,
      'confidence': confidence,
      'score': score,
      'interpretation': interpretVolatilityScore(score),
    };
  }
}
