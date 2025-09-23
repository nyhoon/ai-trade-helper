import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/widgets/gradient_app_bar.dart';
import '../../core/trading/investment_style_manager.dart';
import '../../core/trading/investment_style.dart';
import '../../core/config/api_config.dart';
import 'widgets/account_summary_widget.dart';
import 'widgets/account_pie_chart_widget.dart';
import 'widgets/account_holdings_widget.dart';
import 'widgets/account_api_settings_dialog.dart';
import 'state/account_viewmodel.dart';
import 'state/account_side_effect.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final InvestmentStyleManager _styleManager = InvestmentStyleManager();
  final AccountViewModel _viewModel = AccountViewModel();
  StreamSubscription<InvestmentStyle>? _styleSubscription;
  StreamSubscription<AccountSideEffect>? _sideEffectSubscription;
  InvestmentStyle _currentStyle = InvestmentStyle.moderate;
  bool _isAutoTradingEnabled = false;

  @override
  void initState() {
    super.initState();
    print('🔄 AccountScreen initState 시작');
    _initializeStyleManager();
    _initializeViewModel();
    _loadAutoTradingStatus();
    _viewModel.loadAccountData();
    _viewModel.startAutoRefresh();
    print('✅ AccountScreen initState 완료');
  }

  @override
  void dispose() {
    _styleSubscription?.cancel();
    _sideEffectSubscription?.cancel();
    _viewModel.dispose();
    super.dispose();
  }

  /// 스타일 매니저 초기화
  Future<void> _initializeStyleManager() async {
    await _styleManager.initialize();
    _loadCurrentStyle();
    
    // 스타일 변경 리스너 등록
    _styleSubscription = _styleManager.styleStream.listen((style) {
      if (mounted) {
        setState(() {}); // UI 업데이트
      }
    });
  }

  /// ViewModel 초기화
  void _initializeViewModel() {
    // SideEffect 리스너 등록
    _sideEffectSubscription = _viewModel.sideEffectStream.listen((sideEffect) {
      if (!mounted) return;
      
      switch (sideEffect) {
        case ShowErrorSnackBarSideEffect(:final message, :final onRetry):
          _showErrorSnackBar(message, onRetry);
        case ShowApiSettingsDialogSideEffect():
          _showApiSettingsDialog();
        case ShowSuccessToastSideEffect(:final message):
          _showSuccessToast(message);
        case ShowLoadingIndicatorSideEffect():
          // 로딩 인디케이터는 UI에서 처리
          break;
        case HideLoadingIndicatorSideEffect():
          // 로딩 인디케이터는 UI에서 처리
          break;
      }
    });
  }

  /// 에러 스낵바 표시
  void _showErrorSnackBar(String message, VoidCallback? onRetry) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
        action: onRetry != null ? SnackBarAction(
          label: '다시 시도',
          onPressed: onRetry,
        ) : null,
      ),
    );
  }

  /// 성공 토스트 표시
  void _showSuccessToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// API 설정 다이얼로그 표시
  void _showApiSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AccountApiSettingsDialog(
        onSettingsChanged: () {
          _viewModel.onApiSettingsChanged();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 상태표시줄을 투명하게 설정하여 앱바와 연속되도록 함
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );
    
    return Scaffold(
      appBar: GradientAppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '계좌',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              _getStyleIcon(_currentStyle),
              color: Colors.white,
              size: 24,
            ),
            if (_isAutoTradingEnabled) ...[
              const SizedBox(width: 8),
              const Text(
                'AI 자동매매중',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ],
        ),
        colors: _styleManager.getGradientColors(),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _viewModel.refreshAccountData(),
            tooltip: '새로고침',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showApiSettingsDialog(),
            tooltip: 'KIS API 설정',
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, child) {
          final state = _viewModel.state;
          
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          } else if (state.accountData == null && state.errorMessage != null) {
            return _buildErrorState(state.errorMessage!);
          } else if (state.accountData == null) {
            return _buildErrorState('계좌 정보를 불러올 수 없습니다.');
          } else {
            return _buildAccountContent(state.accountData!);
          }
        },
      ),
    );
  }

  /// 에러 상태 UI
  Widget _buildErrorState(String errorMessage) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.grey,
          ),
          const SizedBox(height: 16),
          Text(
            errorMessage,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _viewModel.loadAccountData(),
            child: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }

  /// 계좌 콘텐츠 UI
  Widget _buildAccountContent(Map<String, dynamic> accountData) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(
              top: 16.0,
              left: 16.0,
              right: 16.0,
              bottom: 16.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 계좌 요약
                AccountSummaryWidget(
                  accountData: accountData,
                ),
                const SizedBox(height: 16),
                
                // 원형 차트
                AccountPieChartWidget(
                  accountData: accountData,
                ),
                const SizedBox(height: 16),
                
                // 보유 종목
                AccountHoldingsWidget(
                  accountData: accountData,
                ),
                const SizedBox(height: 16), // 하단 여백 추가
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 현재 스타일 로드
  Future<void> _loadCurrentStyle() async {
    final style = await _styleManager.getCurrentStyle();
    if (mounted) {
      setState(() {
        _currentStyle = style;
      });
    }
  }

  /// 자동매매 상태 로드
  Future<void> _loadAutoTradingStatus() async {
    try {
      // ApiConfig를 통해 정확한 자동매매 상태 로드
      final isEnabled = await ApiConfig.instance.getAutoTradingEnabled();
      if (mounted) {
        setState(() {
          _isAutoTradingEnabled = isEnabled;
        });
      }
    } catch (e) {
      print('❌ 자동매매 상태 로드 실패: $e');
      // 실패 시 SharedPreferences에서 로드
      final prefs = await SharedPreferences.getInstance();
      final isEnabled = prefs.getBool('auto_trading_enabled') ?? false;
      if (mounted) {
        setState(() {
          _isAutoTradingEnabled = isEnabled;
        });
      }
    }
  }

  /// 스타일별 아이콘 반환
  IconData _getStyleIcon(InvestmentStyle style) {
    switch (style) {
      case InvestmentStyle.conservative:
        return Icons.security; // 방패 아이콘
      case InvestmentStyle.moderate:
        return Icons.balance; // 저울 아이콘
      case InvestmentStyle.aggressive:
        return Icons.trending_up; // 상승 그래프 아이콘
    }
  }
}
