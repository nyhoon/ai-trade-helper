import 'dart:math';

/// 단순 지표 계산기
/// - 입력은 최근 가격 리스트(오래된 값 → 최신 값 순)
class IndicatorCalculator {
  final List<double> _prices;

  IndicatorCalculator(List<double> prices) : _prices = List<double>.from(prices);

  bool get hasEnoughData => _prices.length >= 2;

  double sma(int period) {
    if (_prices.length < period || period <= 0) return 0;
    final start = _prices.length - period;
    final window = _prices.sublist(start);
    final sum = window.fold<double>(0, (a, b) => a + b);
    return sum / period;
  }

  double ema(int period) {
    if (_prices.length < period || period <= 0) return 0;
    final k = 2 / (period + 1);
    double emaValue = sma(period);
    for (int i = _prices.length - period + 1; i < _prices.length; i++) {
      emaValue = _prices[i] * k + emaValue * (1 - k);
    }
    return emaValue;
  }

  double rsi({int period = 14}) {
    if (_prices.length < period + 1) return 50;
    double gain = 0;
    double loss = 0;
    for (int i = _prices.length - period; i < _prices.length; i++) {
      final change = _prices[i] - _prices[i - 1];
      if (change > 0) {
        gain += change.abs();
      } else {
        loss += change.abs();
      }
    }
    final avgGain = gain / period;
    final avgLoss = loss / period;
    if (avgLoss == 0) return 100;
    final rs = avgGain / avgLoss;
    return 100 - (100 / (1 + rs));
  }

  ({double macd, double signal, double histogram}) macd({int fast = 12, int slow = 26, int signal = 9}) {
    if (_prices.length < slow + signal) {
      return (macd: 0, signal: 0, histogram: 0);
    }
    final macdLine = ema(fast) - ema(slow);
    // 간략화: 직전 macd들을 충분히 계산하지 못하므로 현재 macd 기준으로 시그널 추정
    final signalLine = macdLine * (2 / (signal + 1)) + macdLine * (1 - (2 / (signal + 1)));
    return (macd: macdLine, signal: signalLine, histogram: macdLine - signalLine);
  }

  ({double upper, double middle, double lower}) bollinger({int period = 20, double k = 2}) {
    if (_prices.length < period) {
      final last = _prices.isNotEmpty ? _prices.last : 0.0;
      return (upper: last.toDouble(), middle: last.toDouble(), lower: last.toDouble());
    }
    final m = sma(period);
    final start = _prices.length - period;
    final window = _prices.sublist(start);
    final varSum = window.fold<double>(0.0, (a, p) => a + pow(p - m, 2).toDouble());
    final std = sqrt(varSum / period);
    return (upper: m + k * std, middle: m, lower: m - k * std);
  }
}
