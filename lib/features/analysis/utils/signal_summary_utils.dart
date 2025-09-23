class SignalSummaryUtils {
  static String buildSummary(Map<String, dynamic> analysis) {
    final signalsRaw = analysis['signals'];
    List<Map<String, dynamic>> signals = [];
    if (signalsRaw != null && signalsRaw is List) {
      signals = signalsRaw.map((item) => item is Map<String, dynamic> ? item : Map<String, dynamic>.from(item as Map)).toList();
    }
    if (signals.isEmpty) return '시그널 없음';

    final buySignals = signals.where((s) => s['type'] == '매수').toList();
    final sellSignals = signals.where((s) => s['type'] == '매도').toList();

    final parts = <String>[];
    if (buySignals.isNotEmpty) {
      final buyReasons = buySignals.map((s) => s['reason'] as String).toList();
      parts.add('${buySignals.length}개 매수 시그널: ${buyReasons.join(' + ')}');
    }
    if (sellSignals.isNotEmpty) {
      final sellReasons = sellSignals.map((s) => s['reason'] as String).toList();
      parts.add('${sellSignals.length}개 매도 시그널: ${sellReasons.join(' + ')}');
    }
    return parts.join(' + ');
  }
}


