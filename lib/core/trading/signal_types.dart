/// 자동매매 시그널 타입 정의
enum SignalType {
  // 자동매매 ON/OFF 관련
  autoTradingOn,      // AI가 출근했습니다
  
  // 매수 관련 시그널
  buySignal,          // 매수 시그널
  buySuccess,         // 매수 성공
  buyFailed,          // 매수 실패
  buyPending,         // 매수 대기
  buyCancelled,       // 매수 취소
  
  // 매도 관련 시그널
  sellSignal,         // 매도 시그널
  sellSuccess,        // 매도 성공
  sellFailed,         // 매도 실패
  sellPending,        // 매도 대기
  sellCancelled,      // 매도 취소
  
  // 정보 시그널 (자동매매 OFF 상태)
  buyOpportunity,     // 매수 기회
  sellOpportunity,    // 매도 기회
}

/// 시그널 분류
enum SignalCategory {
  autoTrading,    // 자동매매 상태
  buy,           // 매수 관련
  sell,          // 매도 관련
  info,          // 정보 시그널
}

/// 시그널 타입 확장 메서드
extension SignalTypeExtension on SignalType {
  /// 시그널 카테고리 반환
  SignalCategory get category {
    switch (this) {
      case SignalType.autoTradingOn:
        return SignalCategory.autoTrading;
      case SignalType.buySignal:
      case SignalType.buySuccess:
      case SignalType.buyFailed:
      case SignalType.buyPending:
      case SignalType.buyCancelled:
        return SignalCategory.buy;
      case SignalType.sellSignal:
      case SignalType.sellSuccess:
      case SignalType.sellFailed:
      case SignalType.sellPending:
      case SignalType.sellCancelled:
        return SignalCategory.sell;
      case SignalType.buyOpportunity:
      case SignalType.sellOpportunity:
        return SignalCategory.info;
    }
  }
  
  /// 시그널 이름 반환
  String get displayName {
    switch (this) {
      case SignalType.autoTradingOn:
        return 'AI 출근';
      case SignalType.buySignal:
        return '매수 시그널';
      case SignalType.buySuccess:
        return '매수 성공';
      case SignalType.buyFailed:
        return '매수 실패';
      case SignalType.buyPending:
        return '매수 대기';
      case SignalType.buyCancelled:
        return '매수 취소';
      case SignalType.sellSignal:
        return '매도 시그널';
      case SignalType.sellSuccess:
        return '매도 성공';
      case SignalType.sellFailed:
        return '매도 실패';
      case SignalType.sellPending:
        return '매도 대기';
      case SignalType.sellCancelled:
        return '매도 취소';
      case SignalType.buyOpportunity:
        return '매수 기회';
      case SignalType.sellOpportunity:
        return '매도 기회';
    }
  }
  
  /// 푸시 알림 메시지 반환
  String get notificationMessage {
    switch (this) {
      case SignalType.autoTradingOn:
        return 'AI가 출근했습니다.';
      case SignalType.buySignal:
        return '자동매매 실행';
      case SignalType.buySuccess:
        return '매수 체결 완료';
      case SignalType.buyFailed:
        return '매수 주문 실패';
      case SignalType.buyPending:
        return '매수 주문 대기';
      case SignalType.buyCancelled:
        return '매수 주문 취소';
      case SignalType.sellSignal:
        return '자동매매 실행';
      case SignalType.sellSuccess:
        return '매도 체결 완료';
      case SignalType.sellFailed:
        return '매도 주문 실패';
      case SignalType.sellPending:
        return '매도 주문 대기';
      case SignalType.sellCancelled:
        return '매도 주문 취소';
      case SignalType.buyOpportunity:
        return '매수 기회 발견';
      case SignalType.sellOpportunity:
        return '매도 기회 발견';
    }
  }
  
  /// 액션 필요 여부
  bool get requiresAction {
    switch (this) {
      case SignalType.autoTradingOn:
      case SignalType.buySuccess:
      case SignalType.buyFailed:
      case SignalType.buyCancelled:
      case SignalType.sellSuccess:
      case SignalType.sellFailed:
      case SignalType.sellCancelled:
      case SignalType.buyOpportunity:
      case SignalType.sellOpportunity:
        return false;
      case SignalType.buySignal:
      case SignalType.buyPending:
      case SignalType.sellSignal:
      case SignalType.sellPending:
        return true;
    }
  }
  
  /// 주문 상태 반환
  String? get orderStatus {
    switch (this) {
      case SignalType.buySignal:
      case SignalType.sellSignal:
        return '주문 대기';
      case SignalType.buySuccess:
      case SignalType.sellSuccess:
        return '체결 완료';
      case SignalType.buyFailed:
      case SignalType.sellFailed:
        return '주문 실패';
      case SignalType.buyPending:
      case SignalType.sellPending:
        return '체결 대기';
      case SignalType.buyCancelled:
      case SignalType.sellCancelled:
        return '주문 취소';
      default:
        return null;
    }
  }
  
  /// 적용 시장 반환
  List<String> get applicableMarkets {
    switch (this) {
      case SignalType.autoTradingOn:
        return [];
      default:
        return ['나스닥', '코스닥', '코스피'];
    }
  }
}

/// 시그널 데이터 모델
class SignalData {
  final SignalType type;
  final String stockCode;
  final String stockName;
  final double price;
  final int? quantity;
  final double? totalAmount;
  final String? reason;
  final DateTime timestamp;
  final Map<String, dynamic>? analysis;
  final String? orderId;
  final String? orderStatus;
  final bool isAutoTrade;
  final String? market;

  SignalData({
    required this.type,
    required this.stockCode,
    required this.stockName,
    required this.price,
    this.quantity,
    this.totalAmount,
    this.reason,
    required this.timestamp,
    this.analysis,
    this.orderId,
    this.orderStatus,
    this.isAutoTrade = true,
    this.market,
  });

  /// JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'stockCode': stockCode,
      'stockName': stockName,
      'price': price,
      'quantity': quantity,
      'totalAmount': totalAmount,
      'reason': reason,
      'timestamp': timestamp.toIso8601String(),
      'analysis': analysis,
      'orderId': orderId,
      'orderStatus': orderStatus,
      'isAutoTrade': isAutoTrade,
      'market': market,
    };
  }

  /// Map으로 변환 (기존 시스템과 호환)
  Map<String, dynamic> toMap() {
    String inferredSignal;
    switch (type) {
      case SignalType.buySignal:
        inferredSignal = '매수';
        break;
      case SignalType.sellSignal:
        inferredSignal = '매도';
        break;
      default:
        inferredSignal = '관망';
    }

    // 분석 데이터에서 종합점수 추출 (없으면 0.0)
    final double extractedScore = (analysis != null)
        ? ((analysis!['comprehensiveScore'] as num?)?.toDouble() ??
            (analysis!['aggregateScore'] as num?)?.toDouble() ?? 0.0)
        : 0.0;

    return {
      'type': type.displayName,
      'signal': inferredSignal,
      'stockCode': stockCode,
      'stockName': stockName,
      'price': price,
      'quantity': quantity,
      'totalAmount': totalAmount,
      'reason': reason,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'analysis': analysis,
      'orderId': orderId,
      'orderStatus': orderStatus,
      'isAutoTrade': isAutoTrade,
      'market': market,
      'score': extractedScore,
    };
  }

  /// JSON에서 생성
  factory SignalData.fromJson(Map<String, dynamic> json) {
    return SignalData(
      type: SignalType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => SignalType.buySignal,
      ),
      stockCode: json['stockCode'] ?? '',
      stockName: json['stockName'] ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      quantity: json['quantity'] as int?,
      totalAmount: (json['totalAmount'] as num?)?.toDouble(),
      reason: json['reason'] as String?,
      timestamp: DateTime.parse(json['timestamp']),
      analysis: json['analysis'] as Map<String, dynamic>?,
      orderId: json['orderId'] as String?,
      orderStatus: json['orderStatus'] as String?,
      isAutoTrade: json['isAutoTrade'] as bool? ?? true,
      market: json['market'] as String?,
    );
  }
}
