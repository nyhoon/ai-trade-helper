/// 분석탭의 Change (ViewState로 변환되기 전 중간 데이터)
/// MVI 패턴의 Change 역할을 담당
sealed class AnalysisChange {
  const AnalysisChange();
}

/// 로딩 시작
class LoadingStartedChange extends AnalysisChange {
  const LoadingStartedChange();
}

/// 새로고침 시작
class RefreshingStartedChange extends AnalysisChange {
  const RefreshingStartedChange();
}

/// 초기 데이터 로드 완료
class InitialDataLoadedChange extends AnalysisChange {
  final List<Map<String, dynamic>> watchlistItems;
  final List<Map<String, dynamic>> holdingsItems;
  final List<Map<String, dynamic>> recommendedStocks;
  final Map<String, Map<String, dynamic>> analysisResults;
  const InitialDataLoadedChange({
    required this.watchlistItems,
    required this.holdingsItems,
    required this.recommendedStocks,
    this.analysisResults = const {},
  });
}

/// 관심종목 데이터 로드 완료
class WatchlistDataLoadedChange extends AnalysisChange {
  final List<Map<String, dynamic>> items;
  const WatchlistDataLoadedChange(this.items);
}

/// 보유종목 데이터 로드 완료
class HoldingsDataLoadedChange extends AnalysisChange {
  final List<Map<String, dynamic>> items;
  const HoldingsDataLoadedChange(this.items);
}

/// 추천종목 데이터 로드 완료
class RecommendedStocksDataLoadedChange extends AnalysisChange {
  final List<Map<String, dynamic>> items;
  const RecommendedStocksDataLoadedChange(this.items);
}

/// 현재가 데이터 업데이트 완료
class CurrentPricesUpdatedChange extends AnalysisChange {
  final Map<String, Map<String, dynamic>> prices;
  const CurrentPricesUpdatedChange(this.prices);
}

/// 분석 결과 업데이트 완료
class AnalysisResultsUpdatedChange extends AnalysisChange {
  final Map<String, Map<String, dynamic>> results;
  const AnalysisResultsUpdatedChange(this.results);
}

/// 탭 변경 완료
class TabChangedChange extends AnalysisChange {
  final int tabIndex;
  const TabChangedChange(this.tabIndex);
}

/// 선택 모드 변경 완료
class SelectionModeChangedChange extends AnalysisChange {
  final bool isSelectionMode;
  const SelectionModeChangedChange(this.isSelectionMode);
}

/// 종목 선택 상태 변경 완료
class ItemSelectionChangedChange extends AnalysisChange {
  final Set<String> selectedItems;
  const ItemSelectionChangedChange(this.selectedItems);
}

/// 투자 스타일 변경 완료
class InvestmentStyleChangedChange extends AnalysisChange {
  final String style;
  const InvestmentStyleChangedChange(this.style);
}

/// 자동매매 상태 변경 완료
class AutoTradingStatusChangedChange extends AnalysisChange {
  final bool enabled;
  const AutoTradingStatusChangedChange(this.enabled);
}

/// 실시간 분석 상태 변경 완료
class RealtimeAnalysisStatusChangedChange extends AnalysisChange {
  final bool isRunning;
  const RealtimeAnalysisStatusChangedChange(this.isRunning);
}

/// 추천종목 분석 상태 변경 완료
class RecommendedStocksAnalysisStatusChangedChange extends AnalysisChange {
  final bool isAnalyzing;
  final int currentProgress;
  final int totalProgress;
  final String currentSymbol;
  final String currentName;
  const RecommendedStocksAnalysisStatusChangedChange({
    required this.isAnalyzing,
    required this.currentProgress,
    required this.totalProgress,
    required this.currentSymbol,
    required this.currentName,
  });
}

/// 데이터 정리 완료
class DataCleanupCompletedChange extends AnalysisChange {
  const DataCleanupCompletedChange();
}

/// 에러 발생
class AnalysisErrorChange extends AnalysisChange {
  final String error;
  final int errorCount;
  const AnalysisErrorChange(this.error, this.errorCount);
}

/// 에러 리셋
class ErrorResetChange extends AnalysisChange {
  const ErrorResetChange();
}

/// 변경 없음
class NoChange extends AnalysisChange {
  const NoChange();
}
