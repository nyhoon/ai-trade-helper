class IndicatorUtils {
  static String getKoreanIndicatorName(String indicatorName) {
    switch (indicatorName.toLowerCase()) {
      case 'volume':
        return '거래량';
      case 'bollinger':
      case 'bollingerbands':
        return '볼린저밴드';
      case 'movingaverage':
      case 'moving_average':
        return '이동평균선';
      case 'rsi':
        return 'RSI';
      case 'macd':
        return 'MACD';
      case 'vwap':
        return 'VWAP';
      case 'adx':
        return 'ADX';
      default:
        return indicatorName;
    }
  }

  static String getIndicatorKey(String indicatorName) {
    switch (indicatorName.toLowerCase()) {
      case 'volume':
        return 'volume';
      case 'rsi':
        return 'rsi';
      case 'macd':
        return 'macd';
      case 'bollinger':
      case 'bollingerbands':
        return 'bollinger';
      case 'movingaverage':
      case 'moving_average':
        return 'movingAverage';
      case 'vwap':
        return 'vwap';
      case 'adx':
        return 'adx';
      default:
        return indicatorName.toLowerCase();
    }
  }
}


