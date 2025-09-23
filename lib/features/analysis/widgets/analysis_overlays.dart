import 'package:flutter/material.dart';
import '../../../core/services/trade_status_tracker.dart' show TradeStatusTracker, TradeStatus;
import '../../../core/utils/formatters.dart';
import '../../../core/trading/market_time_validator.dart';

class TradeStatusOverlay extends StatelessWidget {
  final String stockCode;

  const TradeStatusOverlay({super.key, required this.stockCode});

  Color _getTradeStatusTextColor(TradeStatus status) {
    switch (status) {
      case TradeStatus.none:
        return Colors.black;
      case TradeStatus.bought:
        return Colors.red[700]!;
      case TradeStatus.sold:
        return Colors.blue[700]!;
      case TradeStatus.holding:
        return Colors.green[700]!;
      case TradeStatus.buyOrdered:
        return Colors.orange[700]!;
      case TradeStatus.sellOrdered:
        return Colors.purple[700]!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tradeStatus = TradeStatusTracker().getTradeStatus(stockCode);
    if (tradeStatus == TradeStatus.none) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: TradeStatusTracker.getStatusColor(tradeStatus),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  TradeStatusTracker.getStatusIcon(tradeStatus),
                  size: 16,
                  color: _getTradeStatusTextColor(tradeStatus),
                ),
                const SizedBox(width: 6),
                Text(
                  TradeStatusTracker.getStatusText(tradeStatus),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _getTradeStatusTextColor(tradeStatus),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AnalysisTimeInfo extends StatelessWidget {
  final Map<String, dynamic> analysis;

  const AnalysisTimeInfo({super.key, required this.analysis});

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.month.toString().padLeft(2, '0')}/${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  bool _isNasdaqStock(String symbol) {
    if (symbol.length == 6) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final analysisTime = analysis['analysisTime'] ?? '';
    final analysisPrice = analysis['analysisPrice'] ?? 0.0;
    if (analysisTime.isEmpty) return const SizedBox.shrink();
    final dateTime = DateTime.tryParse(analysisTime);
    if (dateTime == null) return const SizedBox.shrink();

    final stockCode = analysis['stockCode'] as String? ?? '';
    final isNasdaq = _isNasdaqStock(stockCode);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          const Icon(Icons.access_time, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text(
            '분석: ${_formatDateTime(dateTime)}',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class SignalTimeInfo extends StatelessWidget {
  final String stockCode;
  final Map<String, dynamic> analysis;
  final DateTime? signalTime;

  const SignalTimeInfo({super.key, required this.stockCode, required this.analysis, required this.signalTime});

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.month.toString().padLeft(2, '0')}/${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final signal = analysis['signal'] as String? ?? '관망';
    if (signal != '매수' && signal != '매도') {
      return const SizedBox.shrink();
    }
    if (signalTime == null) {
      return const SizedBox.shrink();
    }
    final signalColor = signal == '매수' ? Colors.green : Colors.red;
    final signalIcon = signal == '매수' ? Icons.trending_up : Icons.trending_down;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: signalColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: signalColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(signalIcon, size: 16, color: signalColor),
          const SizedBox(width: 8),
          Text(
            '$signal 시그널: ${_formatDateTime(signalTime!)}',
            style: TextStyle(
              fontSize: 12,
              color: signalColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: signalColor,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              '고정',
              style: TextStyle(
                fontSize: 10,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TradingTimeOverlay extends StatelessWidget {
  final String stockCode;

  const TradingTimeOverlay({super.key, required this.stockCode});

  bool _isTradingTime(String stockCode) {
    return MarketTimeValidator.instance.isTradingTimeForSymbol(stockCode);
  }

  @override
  Widget build(BuildContext context) {
    if (_isTradingTime(stockCode)) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(
                    Icons.schedule,
                    color: Colors.white,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    '정규장 시간 외',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


