import 'analysis_view_state.dart';
import 'analysis_change.dart';

/// 분석탭의 Reducer (Change를 ViewState로 변환)
/// MVI 패턴의 Reducer 역할을 담당
class AnalysisReducer {
  /// Change를 ViewState로 변환
  static AnalysisViewState reduce(AnalysisViewState currentState, AnalysisChange change) {
    return switch (change) {
      LoadingStartedChange() => currentState.copyWithLoading(true),
      RefreshingStartedChange() => currentState.copyWithRefreshing(true),
      InitialDataLoadedChange(
        :final watchlistItems,
        :final holdingsItems,
        :final recommendedStocks,
        :final analysisResults,
      ) => currentState.copyWithInitialDataLoaded(
        watchlistItems: watchlistItems,
        holdingsItems: holdingsItems,
        recommendedStocks: recommendedStocks,
        analysisResults: analysisResults,
      ),
      WatchlistDataLoadedChange(:final items) => currentState.copyWithWatchlistData(items),
      HoldingsDataLoadedChange(:final items) => currentState.copyWithHoldingsData(items),
      RecommendedStocksDataLoadedChange(:final items) => currentState.copyWithRecommendedStocksData(items),
      CurrentPricesUpdatedChange(:final prices) => currentState.copyWithCurrentPrices(prices),
      AnalysisResultsUpdatedChange(:final results) => currentState.copyWithAnalysisResults(results),
      TabChangedChange(:final tabIndex) => currentState.copyWithTabChanged(tabIndex),
      SelectionModeChangedChange(:final isSelectionMode) => currentState.copyWithSelectionMode(isSelectionMode),
      ItemSelectionChangedChange(:final selectedItems) => currentState.copyWithItemSelection(selectedItems),
      InvestmentStyleChangedChange(:final style) => currentState.copyWithInvestmentStyle(style),
      AutoTradingStatusChangedChange(:final enabled) => currentState.copyWithAutoTradingStatus(enabled),
      RealtimeAnalysisStatusChangedChange(:final isRunning) => currentState.copyWithRealtimeAnalysisStatus(isRunning),
      RecommendedStocksAnalysisStatusChangedChange(
        :final isAnalyzing,
        :final currentProgress,
        :final totalProgress,
        :final currentSymbol,
        :final currentName,
      ) => currentState.copyWithRecommendedStocksAnalysisStatus(
        isAnalyzing: isAnalyzing,
        currentProgress: currentProgress,
        totalProgress: totalProgress,
        currentSymbol: currentSymbol,
        currentName: currentName,
      ),
      DataCleanupCompletedChange() => currentState,
      AnalysisErrorChange(:final error, :final errorCount) => currentState.copyWithError(error, count: errorCount),
      ErrorResetChange() => currentState.copyWithErrorReset(),
      NoChange() => currentState,
    };
  }
}
