/// 분석탭의 ViewState (불변 상태)
/// MVI 패턴의 Model 역할을 담당
class AnalysisViewState {
  // 로딩 상태
  final bool isLoading;
  final bool isRefreshing;
  final bool isFirstLoading;
  
  // 탭 상태
  final int currentTabIndex;
  
  // 데이터 상태
  final List<Map<String, dynamic>> watchlistItems;
  final List<Map<String, dynamic>> holdingsItems;
  final List<Map<String, dynamic>> recommendedStocks;
  final Map<String, Map<String, dynamic>> currentPrices;
  final Map<String, Map<String, dynamic>> analysisResults;
  
  // 캐시된 실시간 데이터
  final Map<String, Map<String, dynamic>> watchlistDataCache;
  final Map<String, Map<String, dynamic>> holdingsDataCache;
  final Map<String, Map<String, dynamic>> recommendedStocksCache;
  
  // UI 상태
  final bool isSelectionMode;
  final Set<String> selectedItems;
  final bool needsRefresh;
  
  // 분석 상태
  final bool isAnalyzingRecommendedStocks;
  final int currentProgress;
  final int totalProgress;
  final String currentAnalyzingSymbol;
  final String currentAnalyzingName;
  
  // 설정 상태
  final String currentInvestmentStyle;
  final bool isAutoTradingEnabled;
  final bool isRealtimeAnalysisRunning;
  
  // 에러 상태
  final String? errorMessage;
  final int errorCount;
  
  // 마지막 업데이트 시간
  final DateTime? lastUpdated;

  const AnalysisViewState({
    this.isLoading = false,
    this.isRefreshing = false,
    this.isFirstLoading = true,
    this.currentTabIndex = 0,
    this.watchlistItems = const [],
    this.holdingsItems = const [],
    this.recommendedStocks = const [],
    this.currentPrices = const {},
    this.analysisResults = const {},
    this.watchlistDataCache = const {},
    this.holdingsDataCache = const {},
    this.recommendedStocksCache = const {},
    this.isSelectionMode = false,
    this.selectedItems = const {},
    this.needsRefresh = false,
    this.isAnalyzingRecommendedStocks = false,
    this.currentProgress = 0,
    this.totalProgress = 0,
    this.currentAnalyzingSymbol = '',
    this.currentAnalyzingName = '',
    this.currentInvestmentStyle = 'moderate',
    this.isAutoTradingEnabled = true,
    this.isRealtimeAnalysisRunning = false,
    this.errorMessage,
    this.errorCount = 0,
    this.lastUpdated,
  });

  /// 초기 상태
  static const AnalysisViewState initial = AnalysisViewState();

  /// 로딩 상태로 변경
  AnalysisViewState copyWithLoading(bool loading) {
    return AnalysisViewState(
      isLoading: loading,
      isRefreshing: isRefreshing,
      isFirstLoading: isFirstLoading,
      currentTabIndex: currentTabIndex,
      watchlistItems: watchlistItems,
      holdingsItems: holdingsItems,
      recommendedStocks: recommendedStocks,
      currentPrices: currentPrices,
      analysisResults: analysisResults,
      watchlistDataCache: watchlistDataCache,
      holdingsDataCache: holdingsDataCache,
      recommendedStocksCache: recommendedStocksCache,
      isSelectionMode: isSelectionMode,
      selectedItems: selectedItems,
      needsRefresh: needsRefresh,
      isAnalyzingRecommendedStocks: isAnalyzingRecommendedStocks,
      currentProgress: currentProgress,
      totalProgress: totalProgress,
      currentAnalyzingSymbol: currentAnalyzingSymbol,
      currentAnalyzingName: currentAnalyzingName,
      currentInvestmentStyle: currentInvestmentStyle,
      isAutoTradingEnabled: isAutoTradingEnabled,
      isRealtimeAnalysisRunning: isRealtimeAnalysisRunning,
      errorMessage: errorMessage,
      errorCount: errorCount,
      lastUpdated: lastUpdated,
    );
  }

  /// 새로고침 상태로 변경
  AnalysisViewState copyWithRefreshing(bool refreshing) {
    return AnalysisViewState(
      isLoading: isLoading,
      isRefreshing: refreshing,
      isFirstLoading: isFirstLoading,
      currentTabIndex: currentTabIndex,
      watchlistItems: watchlistItems,
      holdingsItems: holdingsItems,
      recommendedStocks: recommendedStocks,
      currentPrices: currentPrices,
      analysisResults: analysisResults,
      watchlistDataCache: watchlistDataCache,
      holdingsDataCache: holdingsDataCache,
      recommendedStocksCache: recommendedStocksCache,
      isSelectionMode: isSelectionMode,
      selectedItems: selectedItems,
      needsRefresh: needsRefresh,
      isAnalyzingRecommendedStocks: isAnalyzingRecommendedStocks,
      currentProgress: currentProgress,
      totalProgress: totalProgress,
      currentAnalyzingSymbol: currentAnalyzingSymbol,
      currentAnalyzingName: currentAnalyzingName,
      currentInvestmentStyle: currentInvestmentStyle,
      isAutoTradingEnabled: isAutoTradingEnabled,
      isRealtimeAnalysisRunning: isRealtimeAnalysisRunning,
      errorMessage: errorMessage,
      errorCount: errorCount,
      lastUpdated: lastUpdated,
    );
  }

  /// 첫 로딩 완료
  AnalysisViewState copyWithFirstLoadingCompleted() {
    return AnalysisViewState(
      isLoading: false,
      isRefreshing: false,
      isFirstLoading: false,
      currentTabIndex: currentTabIndex,
      watchlistItems: watchlistItems,
      holdingsItems: holdingsItems,
      recommendedStocks: recommendedStocks,
      currentPrices: currentPrices,
      analysisResults: analysisResults,
      watchlistDataCache: watchlistDataCache,
      holdingsDataCache: holdingsDataCache,
      recommendedStocksCache: recommendedStocksCache,
      isSelectionMode: isSelectionMode,
      selectedItems: selectedItems,
      needsRefresh: needsRefresh,
      isAnalyzingRecommendedStocks: isAnalyzingRecommendedStocks,
      currentProgress: currentProgress,
      totalProgress: totalProgress,
      currentAnalyzingSymbol: currentAnalyzingSymbol,
      currentAnalyzingName: currentAnalyzingName,
      currentInvestmentStyle: currentInvestmentStyle,
      isAutoTradingEnabled: isAutoTradingEnabled,
      isRealtimeAnalysisRunning: isRealtimeAnalysisRunning,
      errorMessage: errorMessage,
      errorCount: errorCount,
      lastUpdated: DateTime.now(),
    );
  }

  /// 초기 데이터 로드 완료
  AnalysisViewState copyWithInitialDataLoaded({
    required List<Map<String, dynamic>> watchlistItems,
    required List<Map<String, dynamic>> holdingsItems,
    required List<Map<String, dynamic>> recommendedStocks,
    Map<String, Map<String, dynamic>>? analysisResults,
  }) {
    return AnalysisViewState(
      isLoading: false,
      isRefreshing: false,
      isFirstLoading: false,
      currentTabIndex: currentTabIndex,
      watchlistItems: watchlistItems,
      holdingsItems: holdingsItems,
      recommendedStocks: recommendedStocks,
      currentPrices: currentPrices,
      analysisResults: analysisResults ?? this.analysisResults,
      watchlistDataCache: watchlistDataCache,
      holdingsDataCache: holdingsDataCache,
      recommendedStocksCache: recommendedStocksCache,
      isSelectionMode: isSelectionMode,
      selectedItems: selectedItems,
      needsRefresh: false,
      isAnalyzingRecommendedStocks: isAnalyzingRecommendedStocks,
      currentProgress: currentProgress,
      totalProgress: totalProgress,
      currentAnalyzingSymbol: currentAnalyzingSymbol,
      currentAnalyzingName: currentAnalyzingName,
      currentInvestmentStyle: currentInvestmentStyle,
      isAutoTradingEnabled: isAutoTradingEnabled,
      isRealtimeAnalysisRunning: isRealtimeAnalysisRunning,
      errorMessage: null,
      errorCount: 0,
      lastUpdated: DateTime.now(),
    );
  }

  /// 탭 변경
  AnalysisViewState copyWithTabChanged(int tabIndex) {
    return AnalysisViewState(
      isLoading: isLoading,
      isRefreshing: isRefreshing,
      isFirstLoading: isFirstLoading,
      currentTabIndex: tabIndex,
      watchlistItems: watchlistItems,
      holdingsItems: holdingsItems,
      recommendedStocks: recommendedStocks,
      currentPrices: currentPrices,
      analysisResults: analysisResults,
      watchlistDataCache: watchlistDataCache,
      holdingsDataCache: holdingsDataCache,
      recommendedStocksCache: recommendedStocksCache,
      isSelectionMode: false, // 탭 변경 시 선택 모드 초기화
      selectedItems: const {}, // 탭 변경 시 선택 항목 초기화
      needsRefresh: needsRefresh,
      isAnalyzingRecommendedStocks: isAnalyzingRecommendedStocks,
      currentProgress: currentProgress,
      totalProgress: totalProgress,
      currentAnalyzingSymbol: currentAnalyzingSymbol,
      currentAnalyzingName: currentAnalyzingName,
      currentInvestmentStyle: currentInvestmentStyle,
      isAutoTradingEnabled: isAutoTradingEnabled,
      isRealtimeAnalysisRunning: isRealtimeAnalysisRunning,
      errorMessage: errorMessage,
      errorCount: errorCount,
      lastUpdated: lastUpdated,
    );
  }

  /// 관심종목 데이터 업데이트
  AnalysisViewState copyWithWatchlistData(List<Map<String, dynamic>> items) {
    return AnalysisViewState(
      isLoading: false,
      isRefreshing: false,
      isFirstLoading: isFirstLoading,
      currentTabIndex: currentTabIndex,
      watchlistItems: items,
      holdingsItems: holdingsItems,
      recommendedStocks: recommendedStocks,
      currentPrices: currentPrices,
      analysisResults: analysisResults,
      watchlistDataCache: watchlistDataCache,
      holdingsDataCache: holdingsDataCache,
      recommendedStocksCache: recommendedStocksCache,
      isSelectionMode: isSelectionMode,
      selectedItems: selectedItems,
      needsRefresh: needsRefresh,
      isAnalyzingRecommendedStocks: isAnalyzingRecommendedStocks,
      currentProgress: currentProgress,
      totalProgress: totalProgress,
      currentAnalyzingSymbol: currentAnalyzingSymbol,
      currentAnalyzingName: currentAnalyzingName,
      currentInvestmentStyle: currentInvestmentStyle,
      isAutoTradingEnabled: isAutoTradingEnabled,
      isRealtimeAnalysisRunning: isRealtimeAnalysisRunning,
      errorMessage: null,
      errorCount: 0,
      lastUpdated: DateTime.now(),
    );
  }

  /// 보유종목 데이터 업데이트
  AnalysisViewState copyWithHoldingsData(List<Map<String, dynamic>> items) {
    return AnalysisViewState(
      isLoading: false,
      isRefreshing: false,
      isFirstLoading: isFirstLoading,
      currentTabIndex: currentTabIndex,
      watchlistItems: watchlistItems,
      holdingsItems: items,
      recommendedStocks: recommendedStocks,
      currentPrices: currentPrices,
      analysisResults: analysisResults,
      watchlistDataCache: watchlistDataCache,
      holdingsDataCache: holdingsDataCache,
      recommendedStocksCache: recommendedStocksCache,
      isSelectionMode: isSelectionMode,
      selectedItems: selectedItems,
      needsRefresh: needsRefresh,
      isAnalyzingRecommendedStocks: isAnalyzingRecommendedStocks,
      currentProgress: currentProgress,
      totalProgress: totalProgress,
      currentAnalyzingSymbol: currentAnalyzingSymbol,
      currentAnalyzingName: currentAnalyzingName,
      currentInvestmentStyle: currentInvestmentStyle,
      isAutoTradingEnabled: isAutoTradingEnabled,
      isRealtimeAnalysisRunning: isRealtimeAnalysisRunning,
      errorMessage: null,
      errorCount: 0,
      lastUpdated: DateTime.now(),
    );
  }

  /// 추천종목 데이터 업데이트
  AnalysisViewState copyWithRecommendedStocksData(List<Map<String, dynamic>> items) {
    return AnalysisViewState(
      isLoading: false,
      isRefreshing: false,
      isFirstLoading: isFirstLoading,
      currentTabIndex: currentTabIndex,
      watchlistItems: watchlistItems,
      holdingsItems: holdingsItems,
      recommendedStocks: items,
      currentPrices: currentPrices,
      analysisResults: analysisResults,
      watchlistDataCache: watchlistDataCache,
      holdingsDataCache: holdingsDataCache,
      recommendedStocksCache: recommendedStocksCache,
      isSelectionMode: isSelectionMode,
      selectedItems: selectedItems,
      needsRefresh: needsRefresh,
      isAnalyzingRecommendedStocks: isAnalyzingRecommendedStocks,
      currentProgress: currentProgress,
      totalProgress: totalProgress,
      currentAnalyzingSymbol: currentAnalyzingSymbol,
      currentAnalyzingName: currentAnalyzingName,
      currentInvestmentStyle: currentInvestmentStyle,
      isAutoTradingEnabled: isAutoTradingEnabled,
      isRealtimeAnalysisRunning: isRealtimeAnalysisRunning,
      errorMessage: null,
      errorCount: 0,
      lastUpdated: DateTime.now(),
    );
  }

  /// 현재가 데이터 업데이트
  AnalysisViewState copyWithCurrentPrices(Map<String, Map<String, dynamic>> prices) {
    return AnalysisViewState(
      isLoading: isLoading,
      isRefreshing: isRefreshing,
      isFirstLoading: isFirstLoading,
      currentTabIndex: currentTabIndex,
      watchlistItems: watchlistItems,
      holdingsItems: holdingsItems,
      recommendedStocks: recommendedStocks,
      currentPrices: prices,
      analysisResults: analysisResults,
      watchlistDataCache: watchlistDataCache,
      holdingsDataCache: holdingsDataCache,
      recommendedStocksCache: recommendedStocksCache,
      isSelectionMode: isSelectionMode,
      selectedItems: selectedItems,
      needsRefresh: needsRefresh,
      isAnalyzingRecommendedStocks: isAnalyzingRecommendedStocks,
      currentProgress: currentProgress,
      totalProgress: totalProgress,
      currentAnalyzingSymbol: currentAnalyzingSymbol,
      currentAnalyzingName: currentAnalyzingName,
      currentInvestmentStyle: currentInvestmentStyle,
      isAutoTradingEnabled: isAutoTradingEnabled,
      isRealtimeAnalysisRunning: isRealtimeAnalysisRunning,
      errorMessage: errorMessage,
      errorCount: errorCount,
      lastUpdated: DateTime.now(),
    );
  }

  /// 분석 결과 업데이트
  AnalysisViewState copyWithAnalysisResults(Map<String, Map<String, dynamic>> results) {
    return AnalysisViewState(
      isLoading: isLoading,
      isRefreshing: isRefreshing,
      isFirstLoading: isFirstLoading,
      currentTabIndex: currentTabIndex,
      watchlistItems: watchlistItems,
      holdingsItems: holdingsItems,
      recommendedStocks: recommendedStocks,
      currentPrices: currentPrices,
      analysisResults: results,
      watchlistDataCache: watchlistDataCache,
      holdingsDataCache: holdingsDataCache,
      recommendedStocksCache: recommendedStocksCache,
      isSelectionMode: isSelectionMode,
      selectedItems: selectedItems,
      needsRefresh: needsRefresh,
      isAnalyzingRecommendedStocks: isAnalyzingRecommendedStocks,
      currentProgress: currentProgress,
      totalProgress: totalProgress,
      currentAnalyzingSymbol: currentAnalyzingSymbol,
      currentAnalyzingName: currentAnalyzingName,
      currentInvestmentStyle: currentInvestmentStyle,
      isAutoTradingEnabled: isAutoTradingEnabled,
      isRealtimeAnalysisRunning: isRealtimeAnalysisRunning,
      errorMessage: errorMessage,
      errorCount: errorCount,
      lastUpdated: DateTime.now(),
    );
  }

  /// 선택 모드 변경
  AnalysisViewState copyWithSelectionMode(bool isSelectionMode) {
    return AnalysisViewState(
      isLoading: isLoading,
      isRefreshing: isRefreshing,
      isFirstLoading: isFirstLoading,
      currentTabIndex: currentTabIndex,
      watchlistItems: watchlistItems,
      holdingsItems: holdingsItems,
      recommendedStocks: recommendedStocks,
      currentPrices: currentPrices,
      analysisResults: analysisResults,
      watchlistDataCache: watchlistDataCache,
      holdingsDataCache: holdingsDataCache,
      recommendedStocksCache: recommendedStocksCache,
      isSelectionMode: isSelectionMode,
      selectedItems: isSelectionMode ? selectedItems : const {}, // 선택 모드 해제 시 선택 항목 초기화
      needsRefresh: needsRefresh,
      isAnalyzingRecommendedStocks: isAnalyzingRecommendedStocks,
      currentProgress: currentProgress,
      totalProgress: totalProgress,
      currentAnalyzingSymbol: currentAnalyzingSymbol,
      currentAnalyzingName: currentAnalyzingName,
      currentInvestmentStyle: currentInvestmentStyle,
      isAutoTradingEnabled: isAutoTradingEnabled,
      isRealtimeAnalysisRunning: isRealtimeAnalysisRunning,
      errorMessage: errorMessage,
      errorCount: errorCount,
      lastUpdated: lastUpdated,
    );
  }

  /// 종목 선택 상태 변경
  AnalysisViewState copyWithItemSelection(Set<String> selectedItems) {
    return AnalysisViewState(
      isLoading: isLoading,
      isRefreshing: isRefreshing,
      isFirstLoading: isFirstLoading,
      currentTabIndex: currentTabIndex,
      watchlistItems: watchlistItems,
      holdingsItems: holdingsItems,
      recommendedStocks: recommendedStocks,
      currentPrices: currentPrices,
      analysisResults: analysisResults,
      watchlistDataCache: watchlistDataCache,
      holdingsDataCache: holdingsDataCache,
      recommendedStocksCache: recommendedStocksCache,
      isSelectionMode: isSelectionMode,
      selectedItems: selectedItems,
      needsRefresh: needsRefresh,
      isAnalyzingRecommendedStocks: isAnalyzingRecommendedStocks,
      currentProgress: currentProgress,
      totalProgress: totalProgress,
      currentAnalyzingSymbol: currentAnalyzingSymbol,
      currentAnalyzingName: currentAnalyzingName,
      currentInvestmentStyle: currentInvestmentStyle,
      isAutoTradingEnabled: isAutoTradingEnabled,
      isRealtimeAnalysisRunning: isRealtimeAnalysisRunning,
      errorMessage: errorMessage,
      errorCount: errorCount,
      lastUpdated: lastUpdated,
    );
  }

  /// 투자 스타일 변경
  AnalysisViewState copyWithInvestmentStyle(String style) {
    return AnalysisViewState(
      isLoading: isLoading,
      isRefreshing: isRefreshing,
      isFirstLoading: isFirstLoading,
      currentTabIndex: currentTabIndex,
      watchlistItems: watchlistItems,
      holdingsItems: holdingsItems,
      recommendedStocks: recommendedStocks,
      currentPrices: currentPrices,
      analysisResults: analysisResults,
      watchlistDataCache: watchlistDataCache,
      holdingsDataCache: holdingsDataCache,
      recommendedStocksCache: recommendedStocksCache,
      isSelectionMode: isSelectionMode,
      selectedItems: selectedItems,
      needsRefresh: needsRefresh,
      isAnalyzingRecommendedStocks: isAnalyzingRecommendedStocks,
      currentProgress: currentProgress,
      totalProgress: totalProgress,
      currentAnalyzingSymbol: currentAnalyzingSymbol,
      currentAnalyzingName: currentAnalyzingName,
      currentInvestmentStyle: style,
      isAutoTradingEnabled: isAutoTradingEnabled,
      isRealtimeAnalysisRunning: isRealtimeAnalysisRunning,
      errorMessage: errorMessage,
      errorCount: errorCount,
      lastUpdated: lastUpdated,
    );
  }

  /// 자동매매 상태 변경
  AnalysisViewState copyWithAutoTradingStatus(bool enabled) {
    return AnalysisViewState(
      isLoading: isLoading,
      isRefreshing: isRefreshing,
      isFirstLoading: isFirstLoading,
      currentTabIndex: currentTabIndex,
      watchlistItems: watchlistItems,
      holdingsItems: holdingsItems,
      recommendedStocks: recommendedStocks,
      currentPrices: currentPrices,
      analysisResults: analysisResults,
      watchlistDataCache: watchlistDataCache,
      holdingsDataCache: holdingsDataCache,
      recommendedStocksCache: recommendedStocksCache,
      isSelectionMode: isSelectionMode,
      selectedItems: selectedItems,
      needsRefresh: needsRefresh,
      isAnalyzingRecommendedStocks: isAnalyzingRecommendedStocks,
      currentProgress: currentProgress,
      totalProgress: totalProgress,
      currentAnalyzingSymbol: currentAnalyzingSymbol,
      currentAnalyzingName: currentAnalyzingName,
      currentInvestmentStyle: currentInvestmentStyle,
      isAutoTradingEnabled: enabled,
      isRealtimeAnalysisRunning: isRealtimeAnalysisRunning,
      errorMessage: errorMessage,
      errorCount: errorCount,
      lastUpdated: lastUpdated,
    );
  }

  /// 실시간 분석 상태 변경
  AnalysisViewState copyWithRealtimeAnalysisStatus(bool isRunning) {
    return AnalysisViewState(
      isLoading: isLoading,
      isRefreshing: isRefreshing,
      isFirstLoading: isFirstLoading,
      currentTabIndex: currentTabIndex,
      watchlistItems: watchlistItems,
      holdingsItems: holdingsItems,
      recommendedStocks: recommendedStocks,
      currentPrices: currentPrices,
      analysisResults: analysisResults,
      watchlistDataCache: watchlistDataCache,
      holdingsDataCache: holdingsDataCache,
      recommendedStocksCache: recommendedStocksCache,
      isSelectionMode: isSelectionMode,
      selectedItems: selectedItems,
      needsRefresh: needsRefresh,
      isAnalyzingRecommendedStocks: isAnalyzingRecommendedStocks,
      currentProgress: currentProgress,
      totalProgress: totalProgress,
      currentAnalyzingSymbol: currentAnalyzingSymbol,
      currentAnalyzingName: currentAnalyzingName,
      currentInvestmentStyle: currentInvestmentStyle,
      isAutoTradingEnabled: isAutoTradingEnabled,
      isRealtimeAnalysisRunning: isRunning,
      errorMessage: errorMessage,
      errorCount: errorCount,
      lastUpdated: lastUpdated,
    );
  }

  /// 추천종목 분석 상태 변경
  AnalysisViewState copyWithRecommendedStocksAnalysisStatus({
    required bool isAnalyzing,
    required int currentProgress,
    required int totalProgress,
    required String currentSymbol,
    required String currentName,
  }) {
    return AnalysisViewState(
      isLoading: isLoading,
      isRefreshing: isRefreshing,
      isFirstLoading: isFirstLoading,
      currentTabIndex: currentTabIndex,
      watchlistItems: watchlistItems,
      holdingsItems: holdingsItems,
      recommendedStocks: recommendedStocks,
      currentPrices: currentPrices,
      analysisResults: analysisResults,
      watchlistDataCache: watchlistDataCache,
      holdingsDataCache: holdingsDataCache,
      recommendedStocksCache: recommendedStocksCache,
      isSelectionMode: isSelectionMode,
      selectedItems: selectedItems,
      needsRefresh: needsRefresh,
      isAnalyzingRecommendedStocks: isAnalyzing,
      currentProgress: currentProgress,
      totalProgress: totalProgress,
      currentAnalyzingSymbol: currentSymbol,
      currentAnalyzingName: currentName,
      currentInvestmentStyle: currentInvestmentStyle,
      isAutoTradingEnabled: isAutoTradingEnabled,
      isRealtimeAnalysisRunning: isRealtimeAnalysisRunning,
      errorMessage: errorMessage,
      errorCount: errorCount,
      lastUpdated: lastUpdated,
    );
  }

  /// 에러 상태로 변경
  AnalysisViewState copyWithError(String error, {int? count}) {
    return AnalysisViewState(
      isLoading: false,
      isRefreshing: false,
      isFirstLoading: isFirstLoading,
      currentTabIndex: currentTabIndex,
      watchlistItems: watchlistItems,
      holdingsItems: holdingsItems,
      recommendedStocks: recommendedStocks,
      currentPrices: currentPrices,
      analysisResults: analysisResults,
      watchlistDataCache: watchlistDataCache,
      holdingsDataCache: holdingsDataCache,
      recommendedStocksCache: recommendedStocksCache,
      isSelectionMode: isSelectionMode,
      selectedItems: selectedItems,
      needsRefresh: needsRefresh,
      isAnalyzingRecommendedStocks: isAnalyzingRecommendedStocks,
      currentProgress: currentProgress,
      totalProgress: totalProgress,
      currentAnalyzingSymbol: currentAnalyzingSymbol,
      currentAnalyzingName: currentAnalyzingName,
      currentInvestmentStyle: currentInvestmentStyle,
      isAutoTradingEnabled: isAutoTradingEnabled,
      isRealtimeAnalysisRunning: isRealtimeAnalysisRunning,
      errorMessage: error,
      errorCount: count ?? errorCount + 1,
      lastUpdated: lastUpdated,
    );
  }

  /// 에러 리셋
  AnalysisViewState copyWithErrorReset() {
    return AnalysisViewState(
      isLoading: isLoading,
      isRefreshing: isRefreshing,
      isFirstLoading: isFirstLoading,
      currentTabIndex: currentTabIndex,
      watchlistItems: watchlistItems,
      holdingsItems: holdingsItems,
      recommendedStocks: recommendedStocks,
      currentPrices: currentPrices,
      analysisResults: analysisResults,
      watchlistDataCache: watchlistDataCache,
      holdingsDataCache: holdingsDataCache,
      recommendedStocksCache: recommendedStocksCache,
      isSelectionMode: isSelectionMode,
      selectedItems: selectedItems,
      needsRefresh: needsRefresh,
      isAnalyzingRecommendedStocks: isAnalyzingRecommendedStocks,
      currentProgress: currentProgress,
      totalProgress: totalProgress,
      currentAnalyzingSymbol: currentAnalyzingSymbol,
      currentAnalyzingName: currentAnalyzingName,
      currentInvestmentStyle: currentInvestmentStyle,
      isAutoTradingEnabled: isAutoTradingEnabled,
      isRealtimeAnalysisRunning: isRealtimeAnalysisRunning,
      errorMessage: null,
      errorCount: 0,
      lastUpdated: lastUpdated,
    );
  }

  @override
  String toString() {
    return 'AnalysisViewState('
        'isLoading: $isLoading, '
        'isRefreshing: $isRefreshing, '
        'isFirstLoading: $isFirstLoading, '
        'currentTabIndex: $currentTabIndex, '
        'watchlistItems: ${watchlistItems.length}, '
        'holdingsItems: ${holdingsItems.length}, '
        'recommendedStocks: ${recommendedStocks.length}, '
        'currentPrices: ${currentPrices.length}, '
        'analysisResults: ${analysisResults.length}, '
        'isSelectionMode: $isSelectionMode, '
        'selectedItems: ${selectedItems.length}, '
        'isAnalyzingRecommendedStocks: $isAnalyzingRecommendedStocks, '
        'currentInvestmentStyle: $currentInvestmentStyle, '
        'isAutoTradingEnabled: $isAutoTradingEnabled, '
        'isRealtimeAnalysisRunning: $isRealtimeAnalysisRunning, '
        'errorMessage: $errorMessage, '
        'errorCount: $errorCount, '
        'lastUpdated: $lastUpdated'
        ')';
  }
}
