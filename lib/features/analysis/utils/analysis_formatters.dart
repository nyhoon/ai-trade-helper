import 'package:intl/intl.dart';

class AnalysisFormatters {
  static String formatNumber(num value) {
    return NumberFormat('#,###').format(value);
  }

  static String formatPriceForDisplay(double price, bool isNasdaq, {bool showSign = false}) {
    if (price == 0) return 'N/A';
    String prefix = '';
    if (showSign && price > 0) prefix = '+';
    if (showSign && price < 0) prefix = '';
    if (isNasdaq) {
      return '$prefix\$${price.toStringAsFixed(2)}';
    } else {
      return '$prefix${NumberFormat('#,###').format(price)}';
    }
  }

  static String formatPriceWithChange(double currentPrice, double openPrice, bool isNasdaq) {
    if (currentPrice == 0 || openPrice == 0) return 'N/A';
    final change = currentPrice - openPrice;
    final changeRate = (change / openPrice) * 100;
    final priceStr = isNasdaq ? '\$${currentPrice.toStringAsFixed(2)}' : NumberFormat('#,###').format(currentPrice);
    final changeStr = changeRate > 0 ? '+${changeRate.toStringAsFixed(1)}%' : '${changeRate.toStringAsFixed(1)}%';
    return '$priceStr\n($changeStr)';
  }

  static String formatIndicatorValue(dynamic value, String indicatorName) {
    if (value == null) return 'N/A';
    if (value is Map<String, dynamic>) {
      final extractedValue = value['value'] ?? value[indicatorName.toLowerCase()] ?? 0.0;
      return formatIndicatorValue(extractedValue, indicatorName);
    }
    if (value is double || value is int) {
      switch (indicatorName) {
        case 'RSI':
          final rsiValue = value.toStringAsFixed(1);
          if (value < 30) return '$rsiValue (과매도)';
          if (value > 70) return '$rsiValue (과매수)';
          return '$rsiValue (중립)';
        case 'MACD':
          return value.toStringAsFixed(2);
        case '볼린저밴드':
        case '이동평균선':
        case 'VWAP':
          return '${formatNumber(value)}원';
        case '거래량':
          return '${formatNumber(value)}배';
        case 'ADX':
          return value.toStringAsFixed(1);
        case '모멘텀':
          return value.toStringAsFixed(1);
        default:
          return value.toStringAsFixed(2);
      }
    }
    return 'N/A';
  }
}


