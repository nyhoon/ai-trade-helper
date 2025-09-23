import 'package:flutter/material.dart';

/// 분석탭의 SideEffect (일회성 이벤트)
/// MVI 패턴의 SideEffect 역할을 담당
sealed class AnalysisSideEffect {
  const AnalysisSideEffect();
}

/// 에러 스낵바 표시
class ShowErrorSnackBarSideEffect extends AnalysisSideEffect {
  final String message;
  final VoidCallback? onRetry;
  const ShowErrorSnackBarSideEffect(this.message, {this.onRetry});
}

/// 성공 스낵바 표시
class ShowSuccessSnackBarSideEffect extends AnalysisSideEffect {
  final String message;
  const ShowSuccessSnackBarSideEffect(this.message);
}

/// 종목 상세 정보 다이얼로그 표시
class ShowStockDetailDialogSideEffect extends AnalysisSideEffect {
  final String symbol;
  final String name;
  const ShowStockDetailDialogSideEffect(this.symbol, this.name);
}

/// 추천종목 화면으로 네비게이션
class NavigateToRecommendedStocksScreenSideEffect extends AnalysisSideEffect {
  const NavigateToRecommendedStocksScreenSideEffect();
}

/// 설정 화면으로 네비게이션
class NavigateToSettingsScreenSideEffect extends AnalysisSideEffect {
  const NavigateToSettingsScreenSideEffect();
}

/// 도움말 화면으로 네비게이션
class NavigateToHelpScreenSideEffect extends AnalysisSideEffect {
  const NavigateToHelpScreenSideEffect();
}

/// 알림 표시
class ShowNotificationSideEffect extends AnalysisSideEffect {
  final String title;
  final String body;
  const ShowNotificationSideEffect(this.title, this.body);
}

/// 진동 피드백
class VibrateFeedbackSideEffect extends AnalysisSideEffect {
  const VibrateFeedbackSideEffect();
}

/// 데이터 테이블 표시
class ShowDataTableSideEffect extends AnalysisSideEffect {
  const ShowDataTableSideEffect();
}

/// 데이터 정리 완료 알림
class ShowDataCleanupCompletedSideEffect extends AnalysisSideEffect {
  const ShowDataCleanupCompletedSideEffect();
}
