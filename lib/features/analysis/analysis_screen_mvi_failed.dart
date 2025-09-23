import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import '../../core/widgets/gradient_app_bar.dart';
import '../../core/trading/investment_style_manager.dart';
import '../../core/trading/investment_style.dart';
import '../../core/config/api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'state/analysis_viewmodel.dart';
import 'state/analysis_action.dart';
import 'state/analysis_side_effect.dart';
import 'state/analysis_view_state.dart';
import 'stock_price_dialog.dart';
import '../trading/recommended_stocks_screen.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> with TickerProviderStateMixin {
  final InvestmentStyleManager _styleManager = InvestmentStyleManager();
  final AnalysisViewModel _viewModel = AnalysisViewModel();
  late TabController _tabController;
  
  StreamSubscription? _styleSubscription;
  StreamSubscription? _sideEffectSubscription;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    
    // ViewModel 초기화
    _initializeViewModel();
    
    // 전달받은 탭 인덱스가 있으면 해당 탭으로 이동
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null && args['initialTab'] != null) {
        final initialTab = args['initialTab'] as int;
        if (initialTab >= 0 && initialTab < 4) {
          _tabController.animateTo(initialTab);
        }
      }
    });
  }
  
  void _initializeViewModel() {
    // SideEffect 리스너 등록
    _sideEffectSubscription = _viewModel.sideEffectStream.listen(_handleSideEffect);
    
    // 초기 데이터 로드
    _viewModel.loadInitialData();
    _viewModel.loadAutoTradingStatus();
    
    // 투자 스타일 변경 리스너
    _styleSubscription = _styleManager.styleStream.listen((style) {
      _viewModel.onInvestmentStyleChanged(style.name);
    });
  }
  
  void _handleSideEffect(AnalysisSideEffect sideEffect) {
    switch (sideEffect.runtimeType) {
      case ShowErrorSnackBarSideEffect:
        final e = sideEffect as ShowErrorSnackBarSideEffect;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red,
          ),
        );
        break;
        
      case ShowSuccessSnackBarSideEffect:
        final s = sideEffect as ShowSuccessSnackBarSideEffect;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.message),
            backgroundColor: Colors.green,
          ),
        );
        break;
        
      case ShowStockPriceDialogSideEffect:
        final d = sideEffect as ShowStockPriceDialogSideEffect;
        _showStockPriceDialog(d.stockCode, d.stockName);
        break;
        
      case NavigateToRecommendedStocksSideEffect:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const RecommendedStocksScreen(),
          ),
        );
        break;
    }
  }
  
  void _showStockPriceDialog(String stockCode, String stockName) {
    showDialog(
      context: context,
      builder: (context) => StockPriceDialog(
        stockCode: stockCode,
        stockName: stockName,
      ),
    );
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    _styleSubscription?.cancel();
    _sideEffectSubscription?.cancel();
    _viewModel.dispose();
    super.dispose();
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
              '분석',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              _getStyleIcon(_styleManager.currentStyle),
              color: Colors.white,
              size: 24,
            ),
            if (_viewModel.state.isAutoTradingEnabled) ...[
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
          // 새로고침 아이콘
          IconButton(
            onPressed: _viewModel.refreshAnalysisData,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
          // 데이터 테이블 아이콘
          IconButton(
            onPressed: () {
              // 데이터 테이블 표시 로직
            },
            icon: const Icon(Icons.table_chart, color: Colors.white),
          ),
          // 정리 아이콘
          IconButton(
            onPressed: () {
              // 데이터 정리 로직
            },
            icon: const Icon(Icons.cleaning_services, color: Colors.white),
          ),
          // 더보기 아이콘
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              switch (value) {
                case 'settings':
                  // 설정 화면으로 이동
                  break;
                case 'help':
                  // 도움말 화면으로 이동
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'settings',
                child: Text('설정'),
              ),
              const PopupMenuItem(
                value: 'help',
                child: Text('도움말'),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          onTap: (index) => _viewModel.changeTab(index),
          tabs: const [
            Tab(text: '관심종목'),
            Tab(text: '보유종목'),
            Tab(text: '추천종목'),
            Tab(text: '투자스타일 & 백테스트'),
          ],
        ),
      ),
      body: AnimatedBuilder(
        animation: _viewModel,
        builder: (context, child) {
          final state = _viewModel.state;
          
          if (state.isFirstLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }
          
          return TabBarView(
            controller: _tabController,
            children: [
              // 관심종목 탭
              _buildWatchlistTab(state),
              // 보유종목 탭
              _buildHoldingsTab(state),
              // 추천종목 탭
              _buildRecommendedStocksTab(state),
              // 투자스타일 & 백테스트 탭
              _buildInvestmentStyleAndBacktestTab(state),
            ],
          );
        },
      ),
    );
  }
  
  Widget _buildWatchlistTab(AnalysisViewState state) {
    return RefreshIndicator(
      onRefresh: _viewModel.loadWatchlistData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: state.watchlistItems.length,
        itemBuilder: (context, index) {
          final item = state.watchlistItems[index];
          final stockCode = item['stock_code'] as String;
          final stockName = item['stock_name'] as String;
          final currentPrice = state.currentPrices[stockCode];
          
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(stockName),
              subtitle: Text(stockCode),
              trailing: currentPrice != null
                  ? Text(
                      '${currentPrice['current_price'] ?? 'N/A'}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    )
                  : const Text('N/A'),
              onTap: () => _viewModel.showStockPriceDialog(stockCode, stockName),
              onLongPress: () => _viewModel.toggleStockSelection(stockCode),
              selected: state.selectedItems.contains(stockCode),
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildHoldingsTab(AnalysisViewState state) {
    return RefreshIndicator(
      onRefresh: _viewModel.loadHoldingsData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: state.holdingsItems.length,
        itemBuilder: (context, index) {
          final item = state.holdingsItems[index];
          final stockCode = item['stock_code'] as String;
          final stockName = item['stock_name'] as String;
          final currentPrice = state.currentPrices[stockCode];
          
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(stockName),
              subtitle: Text(stockCode),
              trailing: currentPrice != null
                  ? Text(
                      '${currentPrice['current_price'] ?? 'N/A'}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    )
                  : const Text('N/A'),
              onTap: () => _viewModel.showStockPriceDialog(stockCode, stockName),
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildRecommendedStocksTab(AnalysisViewState state) {
    return RefreshIndicator(
      onRefresh: _viewModel.loadRecommendedStocks,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: state.recommendedStocks.length,
        itemBuilder: (context, index) {
          final item = state.recommendedStocks[index];
          final stockCode = item['stock_code'] as String;
          final stockName = item['stock_name'] as String;
          final currentPrice = state.currentPrices[stockCode];
          final analysis = state.analysisResults[stockCode];
          
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(stockName),
              subtitle: Text(stockCode),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (currentPrice != null)
                    Text(
                      '${currentPrice['current_price'] ?? 'N/A'}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  if (analysis != null)
                    Text(
                      '점수: ${analysis['score'] ?? 'N/A'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                ],
              ),
              onTap: () => _viewModel.showStockPriceDialog(stockCode, stockName),
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildInvestmentStyleAndBacktestTab(AnalysisViewState state) {
    return const Center(
      child: Text(
        '투자스타일 & 백테스트 탭\n(이 탭은 별도로 처리하지 않음)',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16),
      ),
    );
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
