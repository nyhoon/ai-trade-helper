import 'dart:async';
import 'package:flutter/foundation.dart';
import 'analysis_action.dart';
import 'analysis_change.dart';
import 'analysis_side_effect.dart';
import 'analysis_view_state.dart';
import 'analysis_reducer.dart';
import 'analysis_middleware.dart';

/// 분석탭의 ViewModel
/// MVI 패턴의 Presentation 계층 중심 역할을 담당
class AnalysisViewModel extends ChangeNotifier {
  final AnalysisMiddleware _middleware;
  final StreamController<AnalysisSideEffect> _sideEffectController;
  
  AnalysisViewState _state = AnalysisViewState.initial;
  AnalysisViewState get state => _state;
  
  Stream<AnalysisSideEffect> get sideEffectStream => _sideEffectController.stream;
  
  AnalysisViewModel() 
      : _middleware = AnalysisMiddleware(),
        _sideEffectController = StreamController<AnalysisSideEffect>.broadcast();
  
  /// Action 처리
  Future<void> dispatch(AnalysisAction action) async {
    try {
      print('🔄 [ViewModel] Action 처리 시작: ${action.runtimeType}');
      
      // Middleware에서 Change 생성
      final change = await _middleware.processAction(action);
      
      if (change != null) {
        // Reducer에서 ViewState 변환
        _state = AnalysisReducer.reduce(_state, change);
        notifyListeners();
        print('✅ [ViewModel] State 업데이트 완료: ${_state.toString()}');
      }
      
      // UseCase 실행이 필요한 경우
      if (action is LoadInitialDataAction ||
          action is LoadWatchlistDataAction ||
          action is LoadHoldingsDataAction ||
          action is LoadRecommendedStocksAction ||
          action is UpdateCurrentPricesAction) {
        final useCaseChange = await _middleware.executeUseCase(action);
        _state = AnalysisReducer.reduce(_state, useCaseChange);
        notifyListeners();
        print('✅ [ViewModel] UseCase 실행 완료: ${_state.toString()}');
        
        // 추천종목 데이터 로드 완료 시 분석 상태 업데이트
        if (action is LoadRecommendedStocksAction && useCaseChange is RecommendedStocksDataLoadedChange) {
          final analysisStatusChange = RecommendedStocksAnalysisStatusChangedChange(
            isAnalyzing: false,
            currentProgress: useCaseChange.items.length,
            totalProgress: useCaseChange.items.length,
            currentSymbol: '',
            currentName: '로딩 완료',
          );
          _state = AnalysisReducer.reduce(_state, analysisStatusChange);
          notifyListeners();
          print('✅ [ViewModel] 추천종목 분석 상태 업데이트 완료');
        }
        
        // 에러 발생 시 SideEffect 발행
        if (useCaseChange is AnalysisErrorChange) {
          final isSilent = switch (action) {
            LoadInitialDataAction(:final silent) => silent,
            LoadWatchlistDataAction(:final silent) => silent,
            LoadHoldingsDataAction(:final silent) => silent,
            LoadRecommendedStocksAction(:final silent) => silent,
            _ => false,
          };
          
          if (!isSilent) {
            _sideEffectController.add(
              ShowErrorSnackBarSideEffect(
                useCaseChange.error,
                onRetry: () => dispatch(const LoadInitialDataAction()),
              ),
            );
          }
        }
      }
      
      // SideEffect가 필요한 경우
      if (action is ShowStockDetailAction) {
        _sideEffectController.add(
          ShowStockDetailDialogSideEffect(action.symbol, action.name),
        );
      } else if (action is NavigateToSettingsAction) {
        _sideEffectController.add(
          const NavigateToSettingsScreenSideEffect(),
        );
      } else if (action is NavigateToHelpAction) {
        _sideEffectController.add(
          const NavigateToHelpScreenSideEffect(),
        );
      }
      
    } catch (e) {
      print('❌ [ViewModel] Action 처리 실패: $e');
      _state = _state.copyWithError('처리 중 오류가 발생했습니다: $e');
      notifyListeners();
      
      _sideEffectController.add(
        ShowErrorSnackBarSideEffect(
          '처리 중 오류가 발생했습니다: $e',
          onRetry: () => dispatch(const LoadInitialDataAction()),
        ),
      );
    }
  }
  
  /// 초기 데이터 로드
  Future<void> loadInitialData({bool silent = false}) async {
    print('🔄 [ViewModel] 초기 데이터 로드 시작 (silent: $silent)');
    
    // 먼저 로딩 상태 표시
    await dispatch(LoadInitialDataAction(silent: false));
    
    // 그 다음 실제 데이터 로드
    await dispatch(LoadInitialDataAction(silent: true));
  }
  
  /// 데이터 새로고침
  Future<void> refreshData() async {
    await dispatch(const RefreshDataAction());
  }
  
  /// 탭 변경
  Future<void> changeTab(int tabIndex) async {
    await dispatch(ChangeTabAction(tabIndex));
  }
  
  /// 관심종목 데이터 로드
  Future<void> loadWatchlistData({bool silent = false}) async {
    await dispatch(LoadWatchlistDataAction(silent: silent));
  }
  
  /// 보유종목 데이터 로드
  Future<void> loadHoldingsData({bool silent = false}) async {
    await dispatch(LoadHoldingsDataAction(silent: silent));
  }
  
  /// 추천종목 데이터 로드
  Future<void> loadRecommendedStocks({bool silent = false}) async {
    await dispatch(LoadRecommendedStocksAction(silent: silent));
  }
  
  /// 현재가 데이터 업데이트
  Future<void> updateCurrentPrices(List<String> symbols) async {
    await dispatch(UpdateCurrentPricesAction(symbols));
  }
  
  /// 분석 결과 업데이트
  Future<void> updateAnalysisResults(Map<String, Map<String, dynamic>> results) async {
    await dispatch(UpdateAnalysisResultsAction(results));
  }
  
  /// 선택 모드 토글
  Future<void> toggleSelectionMode() async {
    final newSelectionMode = !_state.isSelectionMode;
    _state = _state.copyWithSelectionMode(newSelectionMode);
    notifyListeners();
  }
  
  /// 종목 선택/해제
  Future<void> toggleItemSelection(String symbol) async {
    final newSelectedItems = Set<String>.from(_state.selectedItems);
    if (newSelectedItems.contains(symbol)) {
      newSelectedItems.remove(symbol);
    } else {
      newSelectedItems.add(symbol);
    }
    _state = _state.copyWithItemSelection(newSelectedItems);
    notifyListeners();
  }
  
  /// 전체 선택/해제
  Future<void> toggleAllSelection() async {
    final currentItems = _getCurrentTabItems();
    final allSelected = currentItems.every((item) => 
        _state.selectedItems.contains(item['symbol'] as String));
    
    final newSelectedItems = allSelected 
        ? <String>{}
        : currentItems.map((item) => item['symbol'] as String).toSet();
    
    _state = _state.copyWithItemSelection(newSelectedItems);
    notifyListeners();
  }
  
  /// 투자 스타일 변경
  Future<void> changeInvestmentStyle(String style) async {
    await dispatch(ChangeInvestmentStyleAction(style));
  }
  
  /// 자동매매 상태 변경
  Future<void> toggleAutoTrading(bool enabled) async {
    await dispatch(ToggleAutoTradingAction(enabled));
  }
  
  /// 에러 리셋
  void resetError() {
    _state = _state.copyWithErrorReset();
    notifyListeners();
  }
  
  /// 실시간 분석 시작
  Future<void> startRealtimeAnalysis() async {
    await dispatch(const StartRealtimeAnalysisAction());
  }
  
  /// 실시간 분석 중지
  Future<void> stopRealtimeAnalysis() async {
    await dispatch(const StopRealtimeAnalysisAction());
  }
  
  /// 데이터 정리
  Future<void> cleanupData() async {
    await dispatch(const CleanupDataAction());
  }
  
  /// 종목 상세 정보 표시
  Future<void> showStockDetail(String symbol, String name) async {
    await dispatch(ShowStockDetailAction(symbol, name));
  }
  
  /// 추천종목 분석 시작
  Future<void> startRecommendedStocksAnalysis() async {
    await dispatch(const StartRecommendedStocksAnalysisAction());
  }
  
  /// 추천종목 분석 중지
  Future<void> stopRecommendedStocksAnalysis() async {
    await dispatch(const StopRecommendedStocksAnalysisAction());
  }
  
  /// 현재 탭의 아이템 목록 반환
  List<Map<String, dynamic>> _getCurrentTabItems() {
    return switch (_state.currentTabIndex) {
      0 => _state.watchlistItems,
      1 => _state.holdingsItems,
      2 => _state.recommendedStocks,
      _ => [],
    };
  }
  
  @override
  void dispose() {
    _middleware.dispose();
    _sideEffectController.close();
    super.dispose();
  }
}
