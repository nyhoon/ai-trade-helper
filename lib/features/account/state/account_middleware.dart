import 'dart:async';
import 'account_action.dart';
import 'account_change.dart';
import 'account_side_effect.dart';
import '../usecases/load_account_data_usecase.dart';
import '../../../core/api/kis_unified_api_service.dart';

/// 계좌 화면의 Middleware (Action을 해석하여 Change 또는 SideEffect 생성)
/// MVI 패턴의 Middleware 역할을 담당
class AccountMiddleware {
  final LoadAccountDataUseCase _loadAccountDataUseCase;
  Timer? _refreshTimer;
  
  AccountMiddleware() : _loadAccountDataUseCase = LoadAccountDataUseCase(KisUnifiedApiService());
  
  /// Action을 해석하여 Change 또는 SideEffect 생성
  Future<AccountChange?> processAction(AccountAction action) async {
    return switch (action) {
      LoadAccountDataAction(:final silent) => await _handleLoadAccountData(silent),
      RefreshAccountDataAction() => await _handleRefreshAccountData(),
      ResetErrorAction() => const ErrorResetChange(),
      ApiSettingsChangedAction() => await _handleLoadAccountData(false),
      StartAutoRefreshAction() => await _handleStartAutoRefresh(),
      StopAutoRefreshAction() => await _handleStopAutoRefresh(),
    };
  }
  
  /// 계좌 데이터 로드 처리
  Future<AccountChange> _handleLoadAccountData(bool silent) async {
    if (!silent) {
      return const LoadingStartedChange();
    } else {
      return const RefreshingStartedChange();
    }
  }
  
  /// 계좌 데이터 새로고침 처리
  Future<AccountChange> _handleRefreshAccountData() async {
    return const RefreshingStartedChange();
  }
  
  /// 자동 새로고침 시작 처리
  Future<AccountChange?> _handleStartAutoRefresh() async {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      // 사일런트 리프레시는 별도 처리
      print('🔄 [Middleware] 자동 새로고침 실행...(사일런트)');
    });
    return null; // SideEffect 없음
  }
  
  /// 자동 새로고침 중지 처리
  Future<AccountChange?> _handleStopAutoRefresh() async {
    _refreshTimer?.cancel();
    return null; // SideEffect 없음
  }
  
  /// UseCase 실행
  Future<AccountChange> executeUseCase(LoadAccountDataAction action) async {
    return await _loadAccountDataUseCase.execute(silent: action.silent);
  }
  
  /// 리소스 정리
  void dispose() {
    _refreshTimer?.cancel();
  }
}
