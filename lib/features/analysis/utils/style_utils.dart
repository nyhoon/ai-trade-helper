import '../../../core/trading/investment_style.dart';

class StyleUtils {
  static String getStyleDescription(InvestmentStyle style) {
    switch (style) {
      case InvestmentStyle.conservative:
        return '안전한 투자로 리스크를 최소화하는 전략. RSI 30 이하에서 매수, 70 이상에서 매도.';
      case InvestmentStyle.moderate:
        return '균형잡힌 투자로 안정성과 수익성을 모두 고려하는 전략. RSI 35 이하에서 매수, 65 이상에서 매도.';
      case InvestmentStyle.aggressive:
        return '적극적인 투자로 높은 수익을 추구하는 전략. RSI 40 이하에서 매수, 60 이상에서 매도.';
    }
  }
}


