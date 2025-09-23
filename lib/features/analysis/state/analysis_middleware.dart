import 'dart:async';
import 'analysis_action.dart';
import 'analysis_change.dart';
import 'analysis_side_effect.dart';
import '../usecases/load_watchlist_data_usecase.dart';
import '../usecases/load_holdings_data_usecase.dart';
import '../usecases/load_recommended_stocks_usecase.dart';
import '../usecases/update_current_prices_usecase.dart';
import '../../../core/api/kis_unified_api_service.dart';
import '../../../core/database/repositories/watchlist_repository.dart';
import '../../../core/data/unified_stock_data_manager.dart';
import '../../../core/services/recommended_stocks_service.dart';
import '../../../core/analysis/unified_analysis_service.dart';

/// 분석탭의 Middleware (Action을 해석하여 Change 또는 SideEffect 생성)
/// MVI 패턴의 Middleware 역할을 담당
class AnalysisMiddleware {
  final LoadWatchlistDataUseCase _loadWatchlistDataUseCase;
  final LoadHoldingsDataUseCase _loadHoldingsDataUseCase;
  final LoadRecommendedStocksUseCase _loadRecommendedStocksUseCase;
  final UpdateCurrentPricesUseCase _updateCurrentPricesUseCase;
  final UnifiedAnalysisService _unifiedAnalysis;
  
  Timer? _analysisTimer;
  Timer? _quickUpdateTimer;
  Timer? _cleanupTimer;
  
  static const Duration _analysisInterval = Duration(minutes: 1);
  static const Duration _quickUpdateInterval = Duration(seconds: 5);
  static const Duration _cleanupInterval = Duration(hours: 1);

  AnalysisMiddleware()
      : _loadWatchlistDataUseCase = LoadWatchlistDataUseCase(
          KisUnifiedApiService(),
          WatchlistRepository(),
          UnifiedStockDataManager.instance,
        ),
        _loadHoldingsDataUseCase = LoadHoldingsDataUseCase(
          KisUnifiedApiService(),
          UnifiedStockDataManager.instance,
        ),
        _loadRecommendedStocksUseCase = LoadRecommendedStocksUseCase(
          RecommendedStocksService(),
        ),
        _updateCurrentPricesUseCase = UpdateCurrentPricesUseCase(
          KisUnifiedApiService(),
        ),
        _unifiedAnalysis = UnifiedAnalysisService.instance;

  /// Action을 해석하여 Change 또는 SideEffect 생성
  Future<AnalysisChange?> processAction(AnalysisAction action) async {
    print('🔄 [Middleware] Action 처리: ${action.runtimeType}');
    return switch (action) {
      LoadInitialDataAction(:final silent) => await _handleLoadInitialData(silent),
      RefreshDataAction() => await _handleRefreshData(),
      ChangeTabAction(:final tabIndex) => TabChangedChange(tabIndex),
      LoadWatchlistDataAction(:final silent) => await _handleLoadWatchlistData(silent),
      LoadHoldingsDataAction(:final silent) => await _handleLoadHoldingsData(silent),
      LoadRecommendedStocksAction(:final silent) => await _handleLoadRecommendedStocks(silent),
      UpdateCurrentPricesAction(:final symbols) => await _handleUpdateCurrentPrices(symbols),
      UpdateAnalysisResultsAction(:final results) => AnalysisResultsUpdatedChange(results),
      ToggleSelectionModeAction() => await _handleToggleSelectionMode(),
      ToggleItemSelectionAction(:final symbol) => await _handleToggleItemSelection(symbol),
      ToggleAllSelectionAction() => await _handleToggleAllSelection(),
      ChangeInvestmentStyleAction(:final style) => InvestmentStyleChangedChange(style),
      ToggleAutoTradingAction(:final enabled) => AutoTradingStatusChangedChange(enabled),
      ResetErrorAction() => const ErrorResetChange(),
      StartRealtimeAnalysisAction() => await _handleStartRealtimeAnalysis(),
      StopRealtimeAnalysisAction() => await _handleStopRealtimeAnalysis(),
      CleanupDataAction() => await _handleCleanupData(),
      ShowStockDetailAction(:final symbol, :final name) => await _handleShowStockDetail(symbol, name),
      StartRecommendedStocksAnalysisAction() => await _handleStartRecommendedStocksAnalysis(),
      StopRecommendedStocksAnalysisAction() => await _handleStopRecommendedStocksAnalysis(),
      RefreshAnalysisDataAction() => await _handleRefreshAnalysisData(),
      NavigateToSettingsAction() => await _handleNavigateToSettings(),
      NavigateToHelpAction() => await _handleNavigateToHelp(),
      UpdateRealtimeAnalysisStatusAction(
        :final isRunning,
        :final currentProgress,
        :final totalProgress,
        :final currentAnalyzingSymbol,
        :final currentAnalyzingName,
      ) => RecommendedStocksAnalysisStatusChangedChange(
        isAnalyzing: isRunning,
        currentProgress: currentProgress,
        totalProgress: totalProgress,
        currentSymbol: currentAnalyzingSymbol,
        currentName: currentAnalyzingName,
      ),
    };
  }

  /// 초기 데이터 로드 처리
  Future<AnalysisChange> _handleLoadInitialData(bool silent) async {
    try {
      print('🔄 [Middleware] 초기 데이터 로드 시작 (silent: $silent)');
      
      if (!silent) {
        // 로딩 시작 상태 반환
        return const LoadingStartedChange();
      }
      
      // 실제 데이터 로드
      final results = await Future.wait([
        _loadWatchlistDataUseCase.execute(),
        _loadHoldingsDataUseCase.execute(),
        _loadRecommendedStocksUseCase.execute(),
      ]);
      
      print('✅ [Middleware] 초기 데이터 로드 완료:');
      print('   - 관심종목: ${results[0].length}개');
      print('   - 보유종목: ${results[1].length}개');
      print('   - 추천종목: ${results[2].length}개');
      
      return InitialDataLoadedChange(
        watchlistItems: results[0],
        holdingsItems: results[1],
        recommendedStocks: results[2],
      );
    } catch (e) {
      print('❌ [Middleware] 초기 데이터 로드 실패: $e');
      return AnalysisErrorChange('초기 데이터 로드 실패: $e', 1);
    }
  }

  /// 데이터 새로고침 처리
  Future<AnalysisChange> _handleRefreshData() async {
    return const RefreshingStartedChange();
  }

  /// 관심종목 데이터 로드 처리
  Future<AnalysisChange> _handleLoadWatchlistData(bool silent) async {
    try {
      final items = await _loadWatchlistDataUseCase.execute();
      return WatchlistDataLoadedChange(items);
    } catch (e) {
      return AnalysisErrorChange('관심종목 데이터 로드 실패: $e', 1);
    }
  }

  /// 보유종목 데이터 로드 처리
  Future<AnalysisChange> _handleLoadHoldingsData(bool silent) async {
    try {
      final items = await _loadHoldingsDataUseCase.execute();
      return HoldingsDataLoadedChange(items);
    } catch (e) {
      return AnalysisErrorChange('보유종목 데이터 로드 실패: $e', 1);
    }
  }

  /// 추천종목 데이터 로드 처리
  Future<AnalysisChange> _handleLoadRecommendedStocks(bool silent) async {
    try {
      print('🔄 [Middleware] 추천종목 데이터 로드 시작 (silent: $silent)');
      final items = await _loadRecommendedStocksUseCase.execute();
      print('✅ [Middleware] 추천종목 데이터 로드 완료: ${items.length}개');
      
      return RecommendedStocksDataLoadedChange(items);
    } catch (e) {
      print('❌ [Middleware] 추천종목 데이터 로드 실패: $e');
      return AnalysisErrorChange('추천종목 데이터 로드 실패: $e', 1);
    }
  }

  /// 현재가 데이터 업데이트 처리
  Future<AnalysisChange> _handleUpdateCurrentPrices(List<String> symbols) async {
    try {
      final prices = await _updateCurrentPricesUseCase.execute(symbols);
      return CurrentPricesUpdatedChange(prices);
    } catch (e) {
      return AnalysisErrorChange('현재가 데이터 업데이트 실패: $e', 1);
    }
  }

  /// 선택 모드 토글 처리
  Future<AnalysisChange> _handleToggleSelectionMode() async {
    // 이 로직은 ViewModel에서 현재 상태를 기반으로 처리
    return const SelectionModeChangedChange(false); // 임시값, 실제로는 ViewModel에서 처리
  }

  /// 종목 선택 토글 처리
  Future<AnalysisChange> _handleToggleItemSelection(String symbol) async {
    // 이 로직은 ViewModel에서 현재 상태를 기반으로 처리
    return const ItemSelectionChangedChange({}); // 임시값, 실제로는 ViewModel에서 처리
  }

  /// 전체 선택 토글 처리
  Future<AnalysisChange> _handleToggleAllSelection() async {
    // 이 로직은 ViewModel에서 현재 상태를 기반으로 처리
    return const ItemSelectionChangedChange({}); // 임시값, 실제로는 ViewModel에서 처리
  }

  /// 실시간 분석 시작 처리
  Future<AnalysisChange> _handleStartRealtimeAnalysis() async {
    _analysisTimer?.cancel();
    _analysisTimer = Timer.periodic(_analysisInterval, (timer) {
      // 실시간 분석 로직
      print('🔄 [Middleware] 실시간 분석 실행...');
    });
    
    _quickUpdateTimer?.cancel();
    _quickUpdateTimer = Timer.periodic(_quickUpdateInterval, (timer) {
      // 빠른 업데이트 로직
      print('🔄 [Middleware] 빠른 업데이트 실행...');
    });
    
    return const RealtimeAnalysisStatusChangedChange(true);
  }

  /// 실시간 분석 중지 처리
  Future<AnalysisChange> _handleStopRealtimeAnalysis() async {
    _analysisTimer?.cancel();
    _quickUpdateTimer?.cancel();
    return const RealtimeAnalysisStatusChangedChange(false);
  }

  /// 데이터 정리 처리
  Future<AnalysisChange> _handleCleanupData() async {
    try {
      // 데이터 정리 로직 (임시로 빈 구현)
      // await _unifiedAnalysis.cleanupOldData();
      return const DataCleanupCompletedChange();
    } catch (e) {
      return AnalysisErrorChange('데이터 정리 실패: $e', 1);
    }
  }

  /// 종목 상세 정보 표시 처리
  Future<AnalysisChange?> _handleShowStockDetail(String symbol, String name) async {
    // SideEffect로 처리되므로 null 반환
    return null;
  }

  /// 추천종목 분석 시작 처리
  Future<AnalysisChange> _handleStartRecommendedStocksAnalysis() async {
    return const RecommendedStocksAnalysisStatusChangedChange(
      isAnalyzing: true,
      currentProgress: 0,
      totalProgress: 0,
      currentSymbol: '',
      currentName: '',
    );
  }

  /// 추천종목 분석 중지 처리
  Future<AnalysisChange> _handleStopRecommendedStocksAnalysis() async {
    return const RecommendedStocksAnalysisStatusChangedChange(
      isAnalyzing: false,
      currentProgress: 0,
      totalProgress: 0,
      currentSymbol: '',
      currentName: '',
    );
  }

  /// UseCase 실행 (별도 처리)
  Future<AnalysisChange> executeUseCase(AnalysisAction action) async {
    return switch (action) {
      LoadInitialDataAction() => await _handleLoadInitialDataUseCase(),
      LoadWatchlistDataAction() => await _handleLoadWatchlistDataUseCase(),
      LoadHoldingsDataAction() => await _handleLoadHoldingsDataUseCase(),
      LoadRecommendedStocksAction() => await _handleLoadRecommendedStocksUseCase(),
      UpdateCurrentPricesAction(:final symbols) => await _handleUpdateCurrentPricesUseCase(symbols),
      _ => throw UnimplementedError('UseCase not implemented for ${action.runtimeType}'),
    };
  }

  /// 초기 데이터 로드 UseCase 실행
  Future<AnalysisChange> _handleLoadInitialDataUseCase() async {
    try {
      print('🔄 [Middleware] 초기 데이터 로드 UseCase 시작');
      
      // 모든 데이터를 병렬로 로드
      final results = await Future.wait([
        _loadWatchlistDataUseCase.execute(),
        _loadHoldingsDataUseCase.execute(),
        _loadRecommendedStocksUseCase.execute(),
      ]);
      
      print('✅ [Middleware] 초기 데이터 로드 완료:');
      print('   - 관심종목: ${results[0].length}개');
      print('   - 보유종목: ${results[1].length}개');
      print('   - 추천종목: ${results[2].length}개');
      
      // 분석 결과 생성 (동시성 제한: 최대 8, 배치 크기 16)
      final Map<String, Map<String, dynamic>> analysisResults = {};

      Future<void> analyzeItems(List<Map<String, dynamic>> items) async {
        const int maxConcurrency = 8; // 동시성 세마포어
        const int batchSize = 16; // 배치 크기

        int index = 0;
        while (index < items.length) {
          final batch = items.skip(index).take(batchSize).toList();
          index += batch.length;

          int inFlight = 0;
          int cursor = 0;
          final List<Future<void>> runners = [];

          Future<void> scheduleNext() async {
            if (cursor >= batch.length) return;
            final item = batch[cursor++];
            final originalSymbol = item['stock_code'] as String?;
            final symbol = _normalizeSymbol(originalSymbol);
            if (symbol == null || symbol.isEmpty || analysisResults.containsKey(symbol)) {
              return scheduleNext();
            }
            inFlight++;
            try {
              final analysis = await _unifiedAnalysis.analyzeStock(
                symbol,
                currentPrice: (item['currentPrice'] as num?)?.toDouble(),
                volume: (item['volume'] as num?)?.toDouble(),
              );
              if (analysis != null) {
                analysisResults[symbol] = analysis;
              }
            } catch (e) {
              print('❌ [Middleware] $symbol 분석 실패: $e');
            } finally {
              inFlight--;
              // 다음 작업 스케줄
              await scheduleNext();
            }
          }

          // 초기 파이프라인 채우기
          for (int i = 0; i < maxConcurrency && i < batch.length; i++) {
            runners.add(scheduleNext());
          }
          await Future.wait(runners);
        }
      }

      await analyzeItems(results[0]);
      await analyzeItems(results[1]);
      
      print('✅ [Middleware] 분석 완료: ${analysisResults.length}개 종목');
      
      return InitialDataLoadedChange(
        watchlistItems: results[0],
        holdingsItems: results[1],
        recommendedStocks: results[2],
        analysisResults: analysisResults,
      );
    } catch (e) {
      print('❌ [Middleware] 초기 데이터 로드 실패: $e');
      return AnalysisErrorChange('초기 데이터 로드 실패: $e', 1);
    }
  }

  /// 관심종목 데이터 로드 UseCase 실행
  Future<AnalysisChange> _handleLoadWatchlistDataUseCase() async {
    try {
      final items = await _loadWatchlistDataUseCase.execute();
      return WatchlistDataLoadedChange(items);
    } catch (e) {
      return AnalysisErrorChange('관심종목 데이터 로드 실패: $e', 1);
    }
  }

  /// 보유종목 데이터 로드 UseCase 실행
  Future<AnalysisChange> _handleLoadHoldingsDataUseCase() async {
    try {
      final items = await _loadHoldingsDataUseCase.execute();
      return HoldingsDataLoadedChange(items);
    } catch (e) {
      return AnalysisErrorChange('보유종목 데이터 로드 실패: $e', 1);
    }
  }

  /// 추천종목 데이터 로드 UseCase 실행
  Future<AnalysisChange> _handleLoadRecommendedStocksUseCase() async {
    try {
      final items = await _loadRecommendedStocksUseCase.execute();
      return RecommendedStocksDataLoadedChange(items);
    } catch (e) {
      return AnalysisErrorChange('추천종목 데이터 로드 실패: $e', 1);
    }
  }

  /// 현재가 데이터 업데이트 UseCase 실행
  Future<AnalysisChange> _handleUpdateCurrentPricesUseCase(List<String> symbols) async {
    try {
      final prices = await _updateCurrentPricesUseCase.execute(symbols);
      return CurrentPricesUpdatedChange(prices);
    } catch (e) {
      return AnalysisErrorChange('현재가 데이터 업데이트 실패: $e', 1);
    }
  }

  /// 분석 데이터 새로고침 처리
  Future<AnalysisChange> _handleRefreshAnalysisData() async {
    try {
      // 모든 데이터를 새로고침
      final watchlistItems = await _loadWatchlistDataUseCase.execute();
      final holdingsItems = await _loadHoldingsDataUseCase.execute();
      final recommendedStocks = await _loadRecommendedStocksUseCase.execute();
      
      return InitialDataLoadedChange(
        watchlistItems: watchlistItems,
        holdingsItems: holdingsItems,
        recommendedStocks: recommendedStocks,
      );
    } catch (e) {
      return AnalysisErrorChange('분석 데이터 새로고침 실패: $e', 1);
    }
  }

  /// 설정 화면으로 이동 처리
  Future<AnalysisChange> _handleNavigateToSettings() async {
    // SideEffect는 ViewModel에서 처리
    return const NoChange();
  }

  /// 도움말 화면으로 이동 처리
  Future<AnalysisChange> _handleNavigateToHelp() async {
    // SideEffect는 ViewModel에서 처리
    return const NoChange();
  }

  /// 심볼 정규화: 해외는 영문 심볼, 국내는 6자리 숫자
  String? _normalizeSymbol(dynamic symbol) {
    if (symbol == null) return null;
    
    final symbolStr = symbol.toString().trim();
    if (symbolStr.isEmpty) return null;
    
    // 국내 6자리 숫자 코드는 그대로 유지
    if (RegExp(r'^\d{6}$').hasMatch(symbolStr)) {
      return symbolStr;
    }
    
    // 해외 종목: NASDAQ: 접두사 제거하고 영문 심볼만 추출
    if (symbolStr.startsWith('NASDAQ:')) {
      return symbolStr.substring(7).toUpperCase();
    }
    
    // 이미 영문 심볼인 경우 대문자로 변환
    if (RegExp(r'^[A-Za-z]{1,5}$').hasMatch(symbolStr)) {
      return symbolStr.toUpperCase();
    }
    
    // 기타 포맷은 스킵
    return null;
  }

  /// 리소스 정리
  void dispose() {
    _analysisTimer?.cancel();
    _quickUpdateTimer?.cancel();
    _cleanupTimer?.cancel();
  }
}
