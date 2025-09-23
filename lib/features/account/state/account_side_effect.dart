/// 계좌 화면의 SideEffect (일회성 이벤트)
/// MVI 패턴의 SideEffect 역할을 담당
sealed class AccountSideEffect {
  const AccountSideEffect();
}

/// 에러 스낵바 표시 SideEffect
class ShowErrorSnackBarSideEffect extends AccountSideEffect {
  final String message;
  final VoidCallback? onRetry;
  
  const ShowErrorSnackBarSideEffect(this.message, {this.onRetry});
}

/// API 설정 다이얼로그 표시 SideEffect
class ShowApiSettingsDialogSideEffect extends AccountSideEffect {
  const ShowApiSettingsDialogSideEffect();
}

/// 성공 토스트 표시 SideEffect
class ShowSuccessToastSideEffect extends AccountSideEffect {
  final String message;
  
  const ShowSuccessToastSideEffect(this.message);
}

/// 로딩 인디케이터 표시 SideEffect
class ShowLoadingIndicatorSideEffect extends AccountSideEffect {
  const ShowLoadingIndicatorSideEffect();
}

/// 로딩 인디케이터 숨기기 SideEffect
class HideLoadingIndicatorSideEffect extends AccountSideEffect {
  const HideLoadingIndicatorSideEffect();
}

/// VoidCallback 타입 정의
typedef VoidCallback = void Function();
