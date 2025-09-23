/// 상위 점수 종목 상태 관리 (MVI 패턴)
/// 불변 상태 객체로 UI 상태를 관리

/// 상위 점수 종목 ViewState
class TopStocksViewState {
  final List<TopStockItem> topStocks;
  final bool isLoading;
  final bool isRefreshing;
  final String? error;
  final DateTime? lastUpdated;
  final Map<String, dynamic> statistics;
  final String selectedMarket;
  final double minScoreThreshold;
  final int displayLimit;

  const TopStocksViewState({
    this.topStocks = const [],
    this.isLoading = false,
    this.isRefreshing = false,
    this.error,
    this.lastUpdated,
    this.statistics = const {},
    this.selectedMarket = 'ALL',
    this.minScoreThreshold = 0.3,
    this.displayLimit = 50,
  });

  /// 상태 복사 (불변성 유지)
  TopStocksViewState copyWith({
    List<TopStockItem>? topStocks,
    bool? isLoading,
    bool? isRefreshing,
    String? error,
    DateTime? lastUpdated,
    Map<String, dynamic>? statistics,
    String? selectedMarket,
    double? minScoreThreshold,
    int? displayLimit,
  }) {
    return TopStocksViewState(
      topStocks: topStocks ?? this.topStocks,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      error: error ?? this.error,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      statistics: statistics ?? this.statistics,
      selectedMarket: selectedMarket ?? this.selectedMarket,
      minScoreThreshold: minScoreThreshold ?? this.minScoreThreshold,
      displayLimit: displayLimit ?? this.displayLimit,
    );
  }

  /// 에러 상태인지 확인
  bool get hasError => error != null;

  /// 로딩 중인지 확인
  bool get isBusy => isLoading || isRefreshing;

  /// 데이터가 있는지 확인
  bool get hasData => topStocks.isNotEmpty;

  /// 시장별 필터링된 종목
  List<TopStockItem> get filteredStocks {
    if (selectedMarket == 'ALL') {
      return topStocks;
    }
    return topStocks.where((stock) => stock.market == selectedMarket).toList();
  }

  /// 점수 임계값 이상 종목
  List<TopStockItem> get thresholdStocks {
    return filteredStocks
        .where((stock) => stock.score >= minScoreThreshold)
        .toList();
  }

  /// 표시할 종목 (제한 적용)
  List<TopStockItem> get displayStocks {
    return thresholdStocks.take(displayLimit).toList();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TopStocksViewState &&
        other.topStocks == topStocks &&
        other.isLoading == isLoading &&
        other.isRefreshing == isRefreshing &&
        other.error == error &&
        other.lastUpdated == lastUpdated &&
        other.statistics == statistics &&
        other.selectedMarket == selectedMarket &&
        other.minScoreThreshold == minScoreThreshold &&
        other.displayLimit == displayLimit;
  }

  @override
  int get hashCode {
    return Object.hash(
      topStocks,
      isLoading,
      isRefreshing,
      error,
      lastUpdated,
      statistics,
      selectedMarket,
      minScoreThreshold,
      displayLimit,
    );
  }

  @override
  String toString() {
    return 'TopStocksViewState('
        'topStocks: ${topStocks.length}, '
        'isLoading: $isLoading, '
        'isRefreshing: $isRefreshing, '
        'error: $error, '
        'lastUpdated: $lastUpdated, '
        'selectedMarket: $selectedMarket, '
        'minScoreThreshold: $minScoreThreshold, '
        'displayLimit: $displayLimit'
        ')';
  }
}

/// 상위 점수 종목 아이템
class TopStockItem {
  final String stockCode;
  final String stockName;
  final String market;
  final double score;
  final double currentPrice;
  final double priceChange;
  final double priceChangeRate;
  final int volume;
  final double volumeRatio;
  final int rank;
  final DateTime lastUpdated;

  const TopStockItem({
    required this.stockCode,
    required this.stockName,
    required this.market,
    required this.score,
    required this.currentPrice,
    this.priceChange = 0,
    this.priceChangeRate = 0,
    this.volume = 0,
    this.volumeRatio = 1.0,
    this.rank = 0,
    required this.lastUpdated,
  });

  /// Map에서 생성
  factory TopStockItem.fromMap(Map<String, dynamic> map) {
    return TopStockItem(
      stockCode: map['stockCode'] as String,
      stockName: map['stockName'] as String,
      market: map['market'] as String,
      score: (map['score'] as num).toDouble(),
      currentPrice: (map['currentPrice'] as num).toDouble(),
      priceChange: (map['priceChange'] as num?)?.toDouble() ?? 0,
      priceChangeRate: (map['priceChangeRate'] as num?)?.toDouble() ?? 0,
      volume: map['volume'] as int? ?? 0,
      volumeRatio: (map['volumeRatio'] as num?)?.toDouble() ?? 1.0,
      rank: map['rank'] as int? ?? 0,
      lastUpdated: map['lastUpdated'] is DateTime 
          ? map['lastUpdated'] as DateTime
          : DateTime.parse(map['lastUpdated'] as String),
    );
  }

  /// Map으로 변환
  Map<String, dynamic> toMap() {
    return {
      'stockCode': stockCode,
      'stockName': stockName,
      'market': market,
      'score': score,
      'currentPrice': currentPrice,
      'priceChange': priceChange,
      'priceChangeRate': priceChangeRate,
      'volume': volume,
      'volumeRatio': volumeRatio,
      'rank': rank,
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }

  /// 점수 등급
  String get scoreGrade {
    if (score >= 0.8) return 'A+';
    if (score >= 0.7) return 'A';
    if (score >= 0.6) return 'B+';
    if (score >= 0.5) return 'B';
    if (score >= 0.4) return 'C+';
    if (score >= 0.3) return 'C';
    return 'D';
  }

  /// 점수 색상
  String get scoreColor {
    if (score >= 0.7) return 'green';
    if (score >= 0.5) return 'orange';
    return 'red';
  }

  /// 가격 변동 색상
  String get priceChangeColor {
    if (priceChangeRate > 0) return 'red';
    if (priceChangeRate < 0) return 'blue';
    return 'gray';
  }

  /// 거래량 비율 텍스트
  String get volumeRatioText {
    if (volumeRatio >= 3.0) return '${volumeRatio.toStringAsFixed(1)}x (폭증)';
    if (volumeRatio >= 2.0) return '${volumeRatio.toStringAsFixed(1)}x (급증)';
    if (volumeRatio >= 1.5) return '${volumeRatio.toStringAsFixed(1)}x (증가)';
    if (volumeRatio <= 0.5) return '${volumeRatio.toStringAsFixed(1)}x (감소)';
    return '${volumeRatio.toStringAsFixed(1)}x';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TopStockItem &&
        other.stockCode == stockCode &&
        other.stockName == stockName &&
        other.market == market &&
        other.score == score &&
        other.currentPrice == currentPrice &&
        other.priceChange == priceChange &&
        other.priceChangeRate == priceChangeRate &&
        other.volume == volume &&
        other.volumeRatio == volumeRatio &&
        other.rank == rank &&
        other.lastUpdated == lastUpdated;
  }

  @override
  int get hashCode {
    return Object.hash(
      stockCode,
      stockName,
      market,
      score,
      currentPrice,
      priceChange,
      priceChangeRate,
      volume,
      volumeRatio,
      rank,
      lastUpdated,
    );
  }

  @override
  String toString() {
    return 'TopStockItem('
        'stockCode: $stockCode, '
        'stockName: $stockName, '
        'market: $market, '
        'score: $score, '
        'currentPrice: $currentPrice, '
        'rank: $rank'
        ')';
  }
}

/// 상위 점수 종목 Action (Intent)
abstract class TopStocksAction {}

/// 상위 점수 종목 로드
class LoadTopStocksAction extends TopStocksAction {
  final int limit;
  final double minScore;
  final String? market;
  final bool useCache;

  LoadTopStocksAction({
    this.limit = 50,
    this.minScore = 0.3,
    this.market,
    this.useCache = true,
  });
}

/// 상위 점수 종목 새로고침
class RefreshTopStocksAction extends TopStocksAction {
  final int limit;
  final double minScore;
  final String? market;

  RefreshTopStocksAction({
    this.limit = 50,
    this.minScore = 0.3,
    this.market,
  });
}

/// 시장 필터 변경
class ChangeMarketFilterAction extends TopStocksAction {
  final String market;

  ChangeMarketFilterAction(this.market);
}

/// 점수 임계값 변경
class ChangeScoreThresholdAction extends TopStocksAction {
  final double threshold;

  ChangeScoreThresholdAction(this.threshold);
}

/// 표시 제한 변경
class ChangeDisplayLimitAction extends TopStocksAction {
  final int limit;

  ChangeDisplayLimitAction(this.limit);
}

/// 실시간 점수 스트림 구독
class SubscribeToScoreStreamAction extends TopStocksAction {}

/// 실시간 점수 스트림 구독 해제
class UnsubscribeFromScoreStreamAction extends TopStocksAction {}

/// 상위 점수 종목 Change (중간 데이터)
abstract class TopStocksChange {}

/// 상위 점수 종목 로딩 시작
class TopStocksLoadingChange extends TopStocksChange {}

/// 상위 점수 종목 로딩 완료
class TopStocksLoadedChange extends TopStocksChange {
  final List<TopStockItem> topStocks;
  final DateTime lastUpdated;

  TopStocksLoadedChange({
    required this.topStocks,
    required this.lastUpdated,
  });
}

/// 상위 점수 종목 로딩 실패
class TopStocksErrorChange extends TopStocksChange {
  final String error;

  TopStocksErrorChange(this.error);
}

/// 상위 점수 종목 새로고침 시작
class TopStocksRefreshingChange extends TopStocksChange {}

/// 상위 점수 종목 새로고침 완료
class TopStocksRefreshedChange extends TopStocksChange {
  final List<TopStockItem> topStocks;
  final DateTime lastUpdated;

  TopStocksRefreshedChange({
    required this.topStocks,
    required this.lastUpdated,
  });
}

/// 시장 필터 변경
class MarketFilterChangedChange extends TopStocksChange {
  final String market;

  MarketFilterChangedChange(this.market);
}

/// 점수 임계값 변경
class ScoreThresholdChangedChange extends TopStocksChange {
  final double threshold;

  ScoreThresholdChangedChange(this.threshold);
}

/// 표시 제한 변경
class DisplayLimitChangedChange extends TopStocksChange {
  final int limit;

  DisplayLimitChangedChange(this.limit);
}

/// 실시간 점수 업데이트
class RealtimeScoreUpdateChange extends TopStocksChange {
  final TopStockItem updatedStock;

  RealtimeScoreUpdateChange(this.updatedStock);
}

/// 상위 점수 종목 SideEffect (일회성 이벤트)
abstract class TopStocksSideEffect {}

/// 에러 토스트 표시
class ShowErrorToastSideEffect extends TopStocksSideEffect {
  final String message;

  ShowErrorToastSideEffect(this.message);
}

/// 성공 토스트 표시
class ShowSuccessToastSideEffect extends TopStocksSideEffect {
  final String message;

  ShowSuccessToastSideEffect(this.message);
}

/// 종목 상세 화면으로 네비게이션
class NavigateToStockDetailSideEffect extends TopStocksSideEffect {
  final String stockCode;
  final String stockName;

  NavigateToStockDetailSideEffect({
    required this.stockCode,
    required this.stockName,
  });
}
