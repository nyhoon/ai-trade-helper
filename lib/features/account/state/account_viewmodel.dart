import 'dart:async';
import 'package:flutter/foundation.dart';
import 'account_action.dart';
import 'account_change.dart';
import 'account_side_effect.dart';
import 'account_view_state.dart';
import 'account_reducer.dart';
import 'account_middleware.dart';

/// 계좌 화면의 ViewModel
/// MVI 패턴의 Presentation 계층 중심 역할을 담당
class AccountViewModel extends ChangeNotifier {
  final AccountMiddleware _middleware;
  final StreamController<AccountSideEffect> _sideEffectController;
  
  AccountViewState _state = AccountViewState.initial;
  AccountViewState get state => _state;
  
  Stream<AccountSideEffect> get sideEffectStream => _sideEffectController.stream;
  
  AccountViewModel() 
      : _middleware = AccountMiddleware(),
        _sideEffectController = StreamController<AccountSideEffect>.broadcast();
  
  /// Action 처리
  Future<void> dispatch(AccountAction action) async {
    try {
      print('🔄 [ViewModel] Action 처리 시작: ${action.runtimeType}');
      
      // Middleware에서 Change 생성
      final change = await _middleware.processAction(action);
      
      if (change != null) {
        // Reducer에서 ViewState 변환
        _state = AccountReducer.reduce(_state, change);
        notifyListeners();
        print('✅ [ViewModel] State 업데이트 완료: $_state');
      }
      
      // UseCase 실행이 필요한 경우
      if (action is LoadAccountDataAction) {
        final useCaseChange = await _middleware.executeUseCase(action);
        _state = AccountReducer.reduce(_state, useCaseChange);
        notifyListeners();
        print('✅ [ViewModel] UseCase 실행 완료: $_state');
        
        // 에러 발생 시 SideEffect 발행
        if (useCaseChange is AccountDataLoadFailedChange && !action.silent) {
          _sideEffectController.add(
            ShowErrorSnackBarSideEffect(
              useCaseChange.error,
              onRetry: () => dispatch(const LoadAccountDataAction()),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ [ViewModel] Action 처리 실패: $e');
      _state = _state.copyWithError('처리 중 오류가 발생했습니다: $e');
      notifyListeners();
      
      _sideEffectController.add(
        ShowErrorSnackBarSideEffect(
          '처리 중 오류가 발생했습니다: $e',
          onRetry: () => dispatch(const LoadAccountDataAction()),
        ),
      );
    }
  }
  
  /// 계좌 데이터 로드
  Future<void> loadAccountData({bool silent = false}) async {
    await dispatch(LoadAccountDataAction(silent: silent));
  }
  
  /// 계좌 데이터 새로고침
  Future<void> refreshAccountData() async {
    await dispatch(const RefreshAccountDataAction());
  }
  
  /// 에러 리셋
  void resetError() {
    dispatch(const ResetErrorAction());
  }
  
  /// API 설정 변경
  Future<void> onApiSettingsChanged() async {
    await dispatch(const ApiSettingsChangedAction());
  }
  
  /// 자동 새로고침 시작
  void startAutoRefresh() {
    dispatch(const StartAutoRefreshAction());
  }
  
  /// 자동 새로고침 중지
  void stopAutoRefresh() {
    dispatch(const StopAutoRefreshAction());
  }
  
  @override
  void dispose() {
    _middleware.dispose();
    _sideEffectController.close();
    super.dispose();
  }
}
