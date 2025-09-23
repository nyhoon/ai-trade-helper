import 'dart:math';

/// 기술적 지표 계산 클래스
class TechnicalIndicators {
  /// RSI (Relative Strength Index) 계산
  static double calculateRSI(List<double> prices, {int period = 14}) {
    if (prices.length < period + 1) return 50.0;
    
    List<double> gains = [];
    List<double> losses = [];
    
    for (int i = 1; i < prices.length; i++) {
      double change = prices[i] - prices[i - 1];
      gains.add(change > 0 ? change : 0);
      losses.add(change < 0 ? -change : 0);
    }
    
    if (gains.length < period) return 50.0;
    
    double avgGain = gains.take(period).reduce((a, b) => a + b) / period;
    double avgLoss = losses.take(period).reduce((a, b) => a + b) / period;
    
    for (int i = period; i < gains.length; i++) {
      avgGain = (avgGain * (period - 1) + gains[i]) / period;
      avgLoss = (avgLoss * (period - 1) + losses[i]) / period;
    }
    
    if (avgLoss == 0) return 100.0;
    
    double rs = avgGain / avgLoss;
    return 100 - (100 / (1 + rs));
  }
  
  /// MACD (Moving Average Convergence Divergence) 계산
  static Map<String, double> calculateMACD(List<double> prices, {
    int fastPeriod = 12,
    int slowPeriod = 26,
    int signalPeriod = 9,
  }) {
    if (prices.length < slowPeriod) {
      return {'macd': 0.0, 'signal': 0.0, 'histogram': 0.0};
    }
    
    List<double> emaFast = _calculateEMA(prices, fastPeriod);
    List<double> emaSlow = _calculateEMA(prices, slowPeriod);
    
    if (emaFast.isEmpty || emaSlow.isEmpty || emaFast.length < signalPeriod) {
      return {'macd': 0.0, 'signal': 0.0, 'histogram': 0.0};
    }
    
    List<double> macdLine = [];
    int minLength = emaFast.length < emaSlow.length ? emaFast.length : emaSlow.length;
    for (int i = 0; i < minLength; i++) {
      macdLine.add(emaFast[i] - emaSlow[i]);
    }
    
    List<double> signalLine = _calculateEMA(macdLine, signalPeriod);
    
    double macd = macdLine.isNotEmpty ? macdLine.last : 0.0;
    double signal = signalLine.isNotEmpty ? signalLine.last : 0.0;
    double histogram = macd - signal;
    
    return {
      'macd': macd,
      'signal': signal,
      'histogram': histogram,
    };
  }
  
  /// 볼린저 밴드 계산
  static Map<String, double> calculateBollingerBands(List<double> prices, {
    int period = 20,
    double stdDev = 2.0,
  }) {
    if (prices.length < period) {
      double price = prices.isNotEmpty ? prices.last : 0.0;
      return {'upper': price, 'middle': price, 'lower': price};
    }
    
    List<double> sma = _calculateSMA(prices, period);
    if (sma.isEmpty) {
      double price = prices.last;
      return {'upper': price, 'middle': price, 'lower': price};
    }
    
    double middle = sma.last;
    double sumSquaredDiff = 0.0;
    
    int startIndex = prices.length - period;
    if (startIndex < 0) startIndex = 0;
    
    for (int i = startIndex; i < prices.length; i++) {
      if (i >= 0 && i < prices.length) {
        double diff = prices[i] - middle;
        sumSquaredDiff += diff * diff;
      }
    }
    
    double standardDeviation = sqrt(sumSquaredDiff / period);
    double upper = middle + (stdDev * standardDeviation);
    double lower = middle - (stdDev * standardDeviation);
    
    return {
      'upper': upper,
      'middle': middle,
      'lower': lower,
    };
  }
  
  /// 단순 이동평균 (SMA) 계산
  static double calculateSMA(List<double> prices, int period) {
    if (prices.length < period) {
      return prices.isNotEmpty ? prices.last : 0.0;
    }
    
    double sum = 0.0;
    for (int i = prices.length - period; i < prices.length; i++) {
      sum += prices[i];
    }
    
    return sum / period;
  }
  
  /// 내부 SMA 계산 (리스트 반환)
  static List<double> _calculateSMA(List<double> prices, int period) {
    if (prices.length < period) {
      return prices.isNotEmpty ? [prices.last] : [0.0];
    }
    
    List<double> sma = [];
    for (int i = period - 1; i < prices.length; i++) {
      double sum = 0.0;
      for (int j = i - period + 1; j <= i; j++) {
        if (j >= 0 && j < prices.length) {
          sum += prices[j];
        }
      }
      sma.add(sum / period);
    }
    
    return sma;
  }
  
  /// 지수 이동평균 (EMA) 계산
  static List<double> _calculateEMA(List<double> prices, int period) {
    if (prices.isEmpty || prices.length < period) return [];
    
    List<double> ema = [];
    double multiplier = 2.0 / (period + 1);
    
    // 첫 번째 EMA는 SMA로 시작
    double sum = 0.0;
    for (int i = 0; i < period; i++) {
      sum += prices[i];
    }
    ema.add(sum / period);
    
    // 나머지는 EMA 공식 적용
    for (int i = period; i < prices.length; i++) {
      if (ema.isNotEmpty) {
        double currentEMA = (prices[i] * multiplier) + (ema.last * (1 - multiplier));
        ema.add(currentEMA);
      }
    }
    
    return ema;
  }
  
  /// VWAP (Volume Weighted Average Price) 계산
  static double calculateVWAP(
    List<double> prices,
    List<int> volumes, {
    List<double>? highs,
    List<double>? lows,
  }) {
    if (prices.isEmpty || volumes.isEmpty || prices.length != volumes.length) {
      return prices.isNotEmpty ? prices.last : 0.0;
    }
    
    // 고가, 저가가 제공된 경우 (HLC/3) 사용
    if (highs != null && lows != null && 
        highs.length == prices.length && lows.length == prices.length) {
      List<double> typicalPrices = [];
      for (int i = 0; i < prices.length; i++) {
        typicalPrices.add((highs[i] + lows[i] + prices[i]) / 3);
      }
      return _calculateVWAPInternal(typicalPrices, volumes);
    }
    
    // 일반 가격 사용
    return _calculateVWAPInternal(prices, volumes);
  }
  
  /// VWAP 내부 계산
  static double _calculateVWAPInternal(List<double> prices, List<int> volumes) {
    double totalVolumePrice = 0.0;
    int totalVolume = 0;
    
    for (int i = 0; i < prices.length; i++) {
      totalVolumePrice += prices[i] * volumes[i];
      totalVolume += volumes[i];
    }
    
    return totalVolume > 0 ? totalVolumePrice / totalVolume : 0.0;
  }
  
  /// ADX (Average Directional Index) 계산
  static double calculateADX(
    List<double> highs,
    List<double> lows,
    List<double> closes, {
    int period = 14,
  }) {
    if (highs.length < period + 1 ||
        lows.length < period + 1 ||
        closes.length < period + 1) {
      return 0.0;
    }

    // 1) +DM, -DM, TR 시퀀스 계산
    final List<double> plusDM = <double>[];
    final List<double> minusDM = <double>[];
    final List<double> trueRanges = <double>[];

    for (int i = 1; i < highs.length; i++) {
      final double highDiff = highs[i] - highs[i - 1];
      final double lowDiff = lows[i - 1] - lows[i];

      plusDM.add(highDiff > lowDiff && highDiff > 0 ? highDiff : 0.0);
      minusDM.add(lowDiff > highDiff && lowDiff > 0 ? lowDiff : 0.0);

      final double tr1 = highs[i] - lows[i];
      final double tr2 = (highs[i] - closes[i - 1]).abs();
      final double tr3 = (lows[i] - closes[i - 1]).abs();
      trueRanges.add([tr1, tr2, tr3].reduce((a, b) => a > b ? a : b));
    }

    if (plusDM.length < period) return 0.0;

    // 2) Wilder 방식의 초기 평균(+DM, -DM, TR)
    double avgPlusDM = plusDM.take(period).fold(0.0, (a, b) => a + b) / period;
    double avgMinusDM = minusDM.take(period).fold(0.0, (a, b) => a + b) / period;
    double avgTR = trueRanges.take(period).fold(0.0, (a, b) => a + b) / period;

    final List<double> dxSeries = <double>[];

    // 3) 이후 구간 지수형(=Wilder) 업데이트 및 DX 시퀀스 생성
    for (int i = period; i < plusDM.length; i++) {
      avgPlusDM = (avgPlusDM * (period - 1) + plusDM[i]) / period;
      avgMinusDM = (avgMinusDM * (period - 1) + minusDM[i]) / period;
      avgTR = (avgTR * (period - 1) + trueRanges[i]) / period;

      if (avgTR == 0) continue;

      final double plusDI = (avgPlusDM / avgTR) * 100.0;
      final double minusDI = (avgMinusDM / avgTR) * 100.0;
      final double denom = (plusDI + minusDI).abs();
      if (denom == 0) continue;
      final double dx = ((plusDI - minusDI).abs() / denom) * 100.0;
      if (!dx.isNaN && dx.isFinite) {
        dxSeries.add(dx);
      }
    }

    if (dxSeries.isEmpty) return 0.0;

    // 4) ADX = DX의 EMA(period). 초기값은 DX 평균으로 시드
    final double multiplier = 2.0 / (period + 1);
    double adx = dxSeries.take(period).fold(0.0, (a, b) => a + b) / period;
    for (int i = period; i < dxSeries.length; i++) {
      adx = (dxSeries[i] * multiplier) + (adx * (1 - multiplier));
    }

    return adx.isNaN || !adx.isFinite ? 0.0 : adx;
  }
  
  /// 스토캐스틱 계산
  static Map<String, double> calculateStochastic(
    List<double> highs,
    List<double> lows,
    List<double> closes, {
    int kPeriod = 14,
    int dPeriod = 3,
  }) {
    if (highs.length < kPeriod || 
        lows.length < kPeriod || 
        closes.length < kPeriod) {
      return {'k': 50.0, 'd': 50.0};
    }
    
    List<double> kValues = [];
    
    for (int i = kPeriod - 1; i < highs.length; i++) {
      double highestHigh = highs.sublist(i - kPeriod + 1, i + 1).reduce((a, b) => a > b ? a : b);
      double lowestLow = lows.sublist(i - kPeriod + 1, i + 1).reduce((a, b) => a < b ? a : b);
      
      if (highestHigh == lowestLow) {
        kValues.add(50.0);
      } else {
        double k = ((closes[i] - lowestLow) / (highestHigh - lowestLow)) * 100;
        kValues.add(k);
      }
    }
    
    double k = kValues.isNotEmpty ? kValues.last : 50.0;
    double d = 50.0;
    
    if (kValues.length >= dPeriod) {
      d = kValues.sublist(kValues.length - dPeriod).reduce((a, b) => a + b) / dPeriod;
    }
    
    return {'k': k, 'd': d};
  }
  
  /// CCI (Commodity Channel Index) 계산
  static double calculateCCI(
    List<double> highs,
    List<double> lows,
    List<double> closes, {
    int period = 20,
  }) {
    if (highs.length < period || 
        lows.length < period || 
        closes.length < period) {
      return 0.0;
    }
    
    List<double> typicalPrices = [];
    for (int i = 0; i < highs.length; i++) {
      typicalPrices.add((highs[i] + lows[i] + closes[i]) / 3);
    }
    
    if (typicalPrices.length < period) return 0.0;
    
    double sma = calculateSMA(typicalPrices, period);
    double meanDeviation = 0.0;
    
    for (int i = typicalPrices.length - period; i < typicalPrices.length; i++) {
      meanDeviation += (typicalPrices[i] - sma).abs();
    }
    meanDeviation /= period;
    
    if (meanDeviation == 0) return 0.0;
    
    double currentTP = typicalPrices.last;
    return (currentTP - sma) / (0.015 * meanDeviation);
  }
  
  /// Williams %R 계산
  static double calculateWilliamsR(
    List<double> highs,
    List<double> lows,
    List<double> closes, {
    int period = 14,
  }) {
    if (highs.length < period || 
        lows.length < period || 
        closes.length < period) {
      return -50.0;
    }
    
    double highestHigh = highs.sublist(highs.length - period).reduce((a, b) => a > b ? a : b);
    double lowestLow = lows.sublist(lows.length - period).reduce((a, b) => a < b ? a : b);
    double currentClose = closes.last;
    
    if (highestHigh == lowestLow) return -50.0;
    
    return ((highestHigh - currentClose) / (highestHigh - lowestLow)) * -100;
  }
}
