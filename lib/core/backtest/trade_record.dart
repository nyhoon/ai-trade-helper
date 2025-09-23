class TradeRecord {
  final String stockCode;
  final DateTime entryTime;
  final double entryPrice;
  final int quantity;
  final String side; // 'buy' or 'sell'
  final DateTime? exitTime;
  final double? exitPrice;
  final double pnl;
  final String status; // 'open' or 'closed'

  TradeRecord({
    required this.stockCode,
    required this.entryTime,
    required this.entryPrice,
    required this.quantity,
    required this.side,
    this.exitTime,
    this.exitPrice,
    required this.pnl,
    required this.status,
  });

  Map<String, dynamic> toJson() {
    return {
      'stockCode': stockCode,
      'entryTime': entryTime.toIso8601String(),
      'entryPrice': entryPrice,
      'quantity': quantity,
      'side': side,
      'exitTime': exitTime?.toIso8601String(),
      'exitPrice': exitPrice,
      'pnl': pnl,
      'status': status,
    };
  }

  factory TradeRecord.fromJson(Map<String, dynamic> json) {
    return TradeRecord(
      stockCode: json['stockCode'],
      entryTime: DateTime.parse(json['entryTime']),
      entryPrice: json['entryPrice'].toDouble(),
      quantity: json['quantity'],
      side: json['side'],
      exitTime: json['exitTime'] != null ? DateTime.parse(json['exitTime']) : null,
      exitPrice: json['exitPrice']?.toDouble(),
      pnl: json['pnl'].toDouble(),
      status: json['status'],
    );
  }

  TradeRecord copyWith({
    String? stockCode,
    DateTime? entryTime,
    double? entryPrice,
    int? quantity,
    String? side,
    DateTime? exitTime,
    double? exitPrice,
    double? pnl,
    String? status,
  }) {
    return TradeRecord(
      stockCode: stockCode ?? this.stockCode,
      entryTime: entryTime ?? this.entryTime,
      entryPrice: entryPrice ?? this.entryPrice,
      quantity: quantity ?? this.quantity,
      side: side ?? this.side,
      exitTime: exitTime ?? this.exitTime,
      exitPrice: exitPrice ?? this.exitPrice,
      pnl: pnl ?? this.pnl,
      status: status ?? this.status,
    );
  }

  @override
  String toString() {
    return 'TradeRecord(stockCode: $stockCode, entryTime: $entryTime, entryPrice: $entryPrice, quantity: $quantity, side: $side, exitTime: $exitTime, exitPrice: $exitPrice, pnl: $pnl, status: $status)';
  }
}
