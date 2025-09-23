/// 분석탭의 Action (사용자 입력 또는 라이프사이클 이벤트)
/// MVI 패턴의 Intent 역할을 담당
sealed class AnalysisAction {
  const AnalysisAction();
}

/// 초기 데이터 로드
class LoadInitialDataAction extends AnalysisAction {
  final bool silent;
  const LoadInitialDataAction({this.silent = false});
}

/// 데이터 새로고침
class RefreshDataAction extends AnalysisAction {
  const RefreshDataAction();
}

/// 탭 변경
class ChangeTabAction extends AnalysisAction {
  final int tabIndex;
  const ChangeTabAction(this.tabIndex);
}

/// 관심종목 데이터 로드
class LoadWatchlistDataAction extends AnalysisAction {
  final bool silent;
  const LoadWatchlistDataAction({this.silent = false});
}

/// 보유종목 데이터 로드
class LoadHoldingsDataAction extends AnalysisAction {
  final bool silent;
  const LoadHoldingsDataAction({this.silent = false});
}

/// 추천종목 데이터 로드
class LoadRecommendedStocksAction extends AnalysisAction {
  final bool silent;
  const LoadRecommendedStocksAction({this.silent = false});
}

/// 현재가 데이터 업데이트
class UpdateCurrentPricesAction extends AnalysisAction {
  final List<String> symbols;
  const UpdateCurrentPricesAction(this.symbols);
}

/// 분석 결과 업데이트
class UpdateAnalysisResultsAction extends AnalysisAction {
  final Map<String, Map<String, dynamic>> results;
  const UpdateAnalysisResultsAction(this.results);
}

/// 선택 모드 토글
class ToggleSelectionModeAction extends AnalysisAction {
  const ToggleSelectionModeAction();
}

/// 종목 선택/해제
class ToggleItemSelectionAction extends AnalysisAction {
  final String symbol;
  const ToggleItemSelectionAction(this.symbol);
}

/// 전체 선택/해제
class ToggleAllSelectionAction extends AnalysisAction {
  const ToggleAllSelectionAction();
}

/// 투자 스타일 변경
class ChangeInvestmentStyleAction extends AnalysisAction {
  final String style;
  const ChangeInvestmentStyleAction(this.style);
}

/// 자동매매 상태 변경
class ToggleAutoTradingAction extends AnalysisAction {
  final bool enabled;
  const ToggleAutoTradingAction(this.enabled);
}

/// 에러 리셋
class ResetErrorAction extends AnalysisAction {
  const ResetErrorAction();
}

/// 실시간 분석 시작
class StartRealtimeAnalysisAction extends AnalysisAction {
  const StartRealtimeAnalysisAction();
}

/// 실시간 분석 중지
class StopRealtimeAnalysisAction extends AnalysisAction {
  const StopRealtimeAnalysisAction();
}

/// 데이터 정리
class CleanupDataAction extends AnalysisAction {
  const CleanupDataAction();
}

/// 종목 상세 정보 표시
class ShowStockDetailAction extends AnalysisAction {
  final String symbol;
  final String name;
  const ShowStockDetailAction(this.symbol, this.name);
}

/// 추천종목 분석 시작
class StartRecommendedStocksAnalysisAction extends AnalysisAction {
  const StartRecommendedStocksAnalysisAction();
}

/// 추천종목 분석 중지
class StopRecommendedStocksAnalysisAction extends AnalysisAction {
  const StopRecommendedStocksAnalysisAction();
}

/// 분석 데이터 새로고침
class RefreshAnalysisDataAction extends AnalysisAction {
  const RefreshAnalysisDataAction();
}

/// 설정 화면으로 이동
class NavigateToSettingsAction extends AnalysisAction {
  const NavigateToSettingsAction();
}

/// 도움말 화면으로 이동
class NavigateToHelpAction extends AnalysisAction {
  const NavigateToHelpAction();
}

/// 실시간 분석 상태 업데이트
class UpdateRealtimeAnalysisStatusAction extends AnalysisAction {
  final bool isRunning;
  final int currentProgress;
  final int totalProgress;
  final String currentAnalyzingSymbol;
  final String currentAnalyzingName;
  
  const UpdateRealtimeAnalysisStatusAction({
    required this.isRunning,
    required this.currentProgress,
    required this.totalProgress,
    required this.currentAnalyzingSymbol,
    required this.currentAnalyzingName,
  });
}