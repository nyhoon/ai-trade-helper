/// 계좌 화면의 ViewState (불변 상태)
/// MVI 패턴의 Model 역할을 담당
class AccountViewState {
  final bool isLoading;
  final bool isRefreshing;
  final Map<String, dynamic>? accountData;
  final String? errorMessage;
  final int errorCount;
  final DateTime? lastUpdated;

  const AccountViewState({
    this.isLoading = false,
    this.isRefreshing = false,
    this.accountData,
    this.errorMessage,
    this.errorCount = 0,
    this.lastUpdated,
  });

  /// 로딩 상태로 변경
  AccountViewState copyWithLoading(bool loading) {
    return AccountViewState(
      isLoading: loading,
      isRefreshing: isRefreshing,
      accountData: accountData,
      errorMessage: errorMessage,
      errorCount: errorCount,
      lastUpdated: lastUpdated,
    );
  }

  /// 새로고침 상태로 변경
  AccountViewState copyWithRefreshing(bool refreshing) {
    return AccountViewState(
      isLoading: isLoading,
      isRefreshing: refreshing,
      accountData: accountData,
      errorMessage: errorMessage,
      errorCount: errorCount,
      lastUpdated: lastUpdated,
    );
  }

  /// 계좌 데이터로 변경
  AccountViewState copyWithAccountData(Map<String, dynamic>? data) {
    return AccountViewState(
      isLoading: false,
      isRefreshing: false,
      accountData: data,
      errorMessage: null,
      errorCount: 0,
      lastUpdated: DateTime.now(),
    );
  }

  /// 에러 상태로 변경
  AccountViewState copyWithError(String error, {int? count}) {
    return AccountViewState(
      isLoading: false,
      isRefreshing: false,
      accountData: accountData,
      errorMessage: error,
      errorCount: count ?? errorCount + 1,
      lastUpdated: lastUpdated,
    );
  }

  /// 에러 카운트 리셋
  AccountViewState copyWithErrorReset() {
    return AccountViewState(
      isLoading: isLoading,
      isRefreshing: isRefreshing,
      accountData: accountData,
      errorMessage: null,
      errorCount: 0,
      lastUpdated: lastUpdated,
    );
  }

  /// 초기 상태
  static const AccountViewState initial = AccountViewState();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AccountViewState &&
        other.isLoading == isLoading &&
        other.isRefreshing == isRefreshing &&
        other.accountData == accountData &&
        other.errorMessage == errorMessage &&
        other.errorCount == errorCount &&
        other.lastUpdated == lastUpdated;
  }

  @override
  int get hashCode {
    return isLoading.hashCode ^
        isRefreshing.hashCode ^
        accountData.hashCode ^
        errorMessage.hashCode ^
        errorCount.hashCode ^
        lastUpdated.hashCode;
  }

  @override
  String toString() {
    return 'AccountViewState(isLoading: $isLoading, isRefreshing: $isRefreshing, '
        'hasData: ${accountData != null}, errorMessage: $errorMessage, '
        'errorCount: $errorCount, lastUpdated: $lastUpdated)';
  }
}
