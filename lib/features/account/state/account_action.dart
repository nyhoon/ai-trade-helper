/// 계좌 화면의 Action (사용자 액션 및 시스템 이벤트)
/// MVI 패턴의 Intent 역할을 담당
sealed class AccountAction {
  const AccountAction();
}

/// 계좌 데이터 로드 액션
class LoadAccountDataAction extends AccountAction {
  final bool silent;
  
  const LoadAccountDataAction({this.silent = false});
}

/// 계좌 데이터 새로고침 액션
class RefreshAccountDataAction extends AccountAction {
  const RefreshAccountDataAction();
}

/// 에러 리셋 액션
class ResetErrorAction extends AccountAction {
  const ResetErrorAction();
}

/// API 설정 변경 액션
class ApiSettingsChangedAction extends AccountAction {
  const ApiSettingsChangedAction();
}

/// 자동 새로고침 시작 액션
class StartAutoRefreshAction extends AccountAction {
  const StartAutoRefreshAction();
}

/// 자동 새로고침 중지 액션
class StopAutoRefreshAction extends AccountAction {
  const StopAutoRefreshAction();
}
