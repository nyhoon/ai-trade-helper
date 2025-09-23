/// 계좌 화면의 Change (ViewState로 변환되기 전 중간 데이터)
/// MVI 패턴의 Change 역할을 담당
sealed class AccountChange {
  const AccountChange();
}

/// 로딩 시작 Change
class LoadingStartedChange extends AccountChange {
  const LoadingStartedChange();
}

/// 새로고침 시작 Change
class RefreshingStartedChange extends AccountChange {
  const RefreshingStartedChange();
}

/// 계좌 데이터 로드 성공 Change
class AccountDataLoadedChange extends AccountChange {
  final Map<String, dynamic> accountData;
  
  const AccountDataLoadedChange(this.accountData);
}

/// 계좌 데이터 로드 실패 Change
class AccountDataLoadFailedChange extends AccountChange {
  final String error;
  final int errorCount;
  
  const AccountDataLoadFailedChange(this.error, this.errorCount);
}

/// 에러 리셋 Change
class ErrorResetChange extends AccountChange {
  const ErrorResetChange();
}
