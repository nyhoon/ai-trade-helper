import 'account_view_state.dart';
import 'account_change.dart';

/// 계좌 화면의 Reducer (Change를 ViewState로 변환)
/// MVI 패턴의 Reducer 역할을 담당
class AccountReducer {
  /// Change를 ViewState로 변환
  static AccountViewState reduce(AccountViewState currentState, AccountChange change) {
    return switch (change) {
      LoadingStartedChange() => currentState.copyWithLoading(true),
      RefreshingStartedChange() => currentState.copyWithRefreshing(true),
      AccountDataLoadedChange(:final accountData) => currentState.copyWithAccountData(accountData),
      AccountDataLoadFailedChange(:final error, :final errorCount) => 
        currentState.copyWithError(error, count: errorCount),
      ErrorResetChange() => currentState.copyWithErrorReset(),
    };
  }
}
