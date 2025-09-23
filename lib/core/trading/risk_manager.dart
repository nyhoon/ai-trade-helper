import 'dart:math';

class RiskDecision {
  final int quantity;
  final double stopLoss;
  final double takeProfit;
  const RiskDecision({required this.quantity, required this.stopLoss, required this.takeProfit});
}

class RiskManager {
  final double accountEquity;
  final double maxDailyLossRate; // e.g., 0.03
  final double riskPerTradeRate; // e.g., 0.005

  const RiskManager({
    required this.accountEquity,
    this.maxDailyLossRate = 0.03,
    this.riskPerTradeRate = 0.005,
  });

  bool isTradingAllowed({required double dayLossRate}) {
    return dayLossRate.abs() < maxDailyLossRate;
  }

  RiskDecision sizePosition({
    required double entryPrice,
    required double atr,
    double atrMultiplierSL = 1.5,
    double atrMultiplierTP = 3.0,
  }) {
    final riskAmount = accountEquity * riskPerTradeRate;
    final sl = (entryPrice - atr * atrMultiplierSL).clamp(0, double.infinity);
    final tp = entryPrice + atr * atrMultiplierTP;
    final perShareRisk = (entryPrice - sl).abs();
    final qty = perShareRisk > 0 ? (riskAmount / perShareRisk).floor() : 0;
    return RiskDecision(quantity: qty, stopLoss: sl.toDouble(), takeProfit: tp.toDouble());
  }
}
