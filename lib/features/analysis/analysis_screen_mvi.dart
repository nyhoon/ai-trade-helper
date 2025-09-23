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

/// MVI 패턴으로 리팩토링된 분석탭 화면
/// UI 구조는 기존과 동일하게 유지
class AnalysisScreenMVI extends StatefulWidget {
  const AnalysisScreenMVI({super.key});

  @override
  State<AnalysisScreenMVI> createState() => _AnalysisScreenMVIState();
}

class _AnalysisScreenMVIState extends State<AnalysisScreenMVI> with TickerProviderStateMixin {
  final InvestmentStyleManager _styleManager = InvestmentStyleManager();
  final AnalysisViewModel _viewModel = AnalysisViewModel();
  late TabController _tabController;
  
  StreamSubscription? _styleSubscription;
  StreamSubscription? _sideEffectSubscription;
  
  // 스크롤 위치 유지를 위한 컨트롤러들
  final ScrollController _watchlistScrollController = ScrollController();
  final ScrollController _holdingsScrollController = ScrollController();
  final ScrollController _recommendedScrollController = ScrollController();
  
  // 스크롤 위치 저장
  double _watchlistScrollOffset = 0.0;
  double _holdingsScrollOffset = 0.0;
  double _recommendedScrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this); // 투자스타일 & 백테스트 탭 제거
    
    // ViewModel 초기화
    _initializeViewModel();
    
    // 전달받은 탭 인덱스가 있으면 해당 탭으로 이동
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null && args['initialTab'] != null) {
        final initialTab = args['initialTab'] as int;
        if (initialTab >= 0 && initialTab < 3) { // 3개 탭으로 변경
          _tabController.animateTo(initialTab);
        }
      }
    });
    
    // 탭 변경 리스너 추가
    _tabController.addListener(() {
      _viewModel.changeTab(_tabController.index);
    });
    
    // 투자 스타일 변경 스트림 구독
    _styleSubscription = _styleManager.styleStream.listen((newStyle) {
      print('🔄 투자 스타일 변경 감지: ${_getStyleName(newStyle)}');
      _viewModel.changeInvestmentStyle(_getStyleName(newStyle));
    });
  }
  
  void _initializeViewModel() {
    // SideEffect 리스너 등록
    _sideEffectSubscription = _viewModel.sideEffectStream.listen((sideEffect) {
      _handleSideEffect(sideEffect);
    });
    
    // 초기 데이터 로드
    _viewModel.loadInitialData();
  }
  
  void _handleSideEffect(AnalysisSideEffect sideEffect) {
    if (!mounted) return;
    
    switch (sideEffect) {
      case ShowErrorSnackBarSideEffect(:final message, :final onRetry):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            action: onRetry != null 
                ? SnackBarAction(
                    label: '재시도',
                    onPressed: onRetry,
                  )
                : null,
          ),
        );
        break;
      case ShowSuccessSnackBarSideEffect(:final message):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
        break;
      case ShowStockDetailDialogSideEffect(:final symbol, :final name):
        _showStockDetailDialog(symbol, name);
        break;
      case NavigateToRecommendedStocksScreenSideEffect():
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const RecommendedStocksScreen(),
          ),
        );
        break;
      case ShowNotificationSideEffect(:final title, :final body):
        // 알림 표시 로직
        break;
      case VibrateFeedbackSideEffect():
        HapticFeedback.lightImpact();
        break;
      case ShowDataTableSideEffect():
        // 데이터 테이블 표시 로직
        break;
      case ShowDataCleanupCompletedSideEffect():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('데이터 정리가 완료되었습니다.')),
        );
        break;
    }
  }
  
  void _showStockDetailDialog(String symbol, String name) {
    showDialog(
      context: context,
      builder: (context) => StockPriceDialog(
        symbol: symbol,
        name: name,
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _styleSubscription?.cancel();
    _sideEffectSubscription?.cancel();
    _watchlistScrollController.dispose();
    _holdingsScrollController.dispose();
    _recommendedScrollController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(
        title: '분석',
        colors: _styleManager.getGradientColors(),
        actions: [
          // 새로고침 아이콘
          IconButton(
            onPressed: () => _viewModel.refreshData(),
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
          // 데이터 테이블 아이콘
          IconButton(
            onPressed: () => _viewModel.cleanupData(),
            icon: const Icon(Icons.table_chart, color: Colors.white),
          ),
          // 정리 아이콘
          IconButton(
            onPressed: () => _viewModel.cleanupData(),
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
            // 투자스타일 & 백테스트 탭 제거
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
            ],
          );
        },
      ),
    );
  }
  
  Widget _buildWatchlistTab(AnalysisViewState state) {
    if (state.watchlistItems.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.star_border, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              '관심종목이 없습니다',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              '종목을 추가해보세요',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: () => _viewModel.loadWatchlistData(),
      child: ListView.builder(
        controller: _watchlistScrollController,
        itemCount: state.watchlistItems.length,
        itemBuilder: (context, index) {
          final item = state.watchlistItems[index];
          return _buildStockItem(item, state);
        },
      ),
    );
  }
  
  Widget _buildHoldingsTab(AnalysisViewState state) {
    if (state.holdingsItems.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_wallet, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              '보유종목이 없습니다',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              '종목을 매수해보세요',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: () => _viewModel.loadHoldingsData(),
      child: ListView.builder(
        controller: _holdingsScrollController,
        itemCount: state.holdingsItems.length,
        itemBuilder: (context, index) {
          final item = state.holdingsItems[index];
          return _buildStockItem(item, state);
        },
      ),
    );
  }
  
  Widget _buildRecommendedStocksTab(AnalysisViewState state) {
    if (state.recommendedStocks.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.recommend, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              '추천종목이 없습니다',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              '추천종목을 분석해보세요',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: () => _viewModel.loadRecommendedStocks(),
      child: ListView.builder(
        controller: _recommendedScrollController,
        itemCount: state.recommendedStocks.length,
        itemBuilder: (context, index) {
          final item = state.recommendedStocks[index];
          return _buildStockItem(item, state);
        },
      ),
    );
  }
  
  Widget _buildStockItem(Map<String, dynamic> item, AnalysisViewState state) {
    final symbol = item['symbol'] as String? ?? '';
    final name = item['name'] as String? ?? '';
    final currentPrice = _toDouble(item['currentPrice']);
    final change = _toDouble(item['change']);
    final changeRate = _toDouble(item['changeRate']);
    final volume = _toInt(item['volume']);
    
    final isPositive = change >= 0;
    final priceColor = isPositive ? Colors.red : Colors.blue;
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(symbol),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${currentPrice.toStringAsFixed(0)}원',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: priceColor,
              ),
            ),
            Text(
              '${isPositive ? '+' : ''}${change.toStringAsFixed(0)} (${isPositive ? '+' : ''}${changeRate.toStringAsFixed(2)}%)',
              style: TextStyle(
                fontSize: 12,
                color: priceColor,
              ),
            ),
            Text(
              '거래량: ${_formatVolume(volume)}',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
        onTap: () => _viewModel.showStockDetail(symbol, name),
        onLongPress: () {
          HapticFeedback.lightImpact();
          _viewModel.toggleSelectionMode();
        },
      ),
    );
  }
  
  // 유틸리티 메서드들
  double _toDouble(dynamic value, [double defaultValue = 0.0]) {
    if (value == null) return defaultValue;
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value.trim());
      return parsed ?? defaultValue;
    }
    return defaultValue;
  }
  
  int _toInt(dynamic value, [int defaultValue = 0]) {
    if (value == null) return defaultValue;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      return parsed ?? defaultValue;
    }
    return defaultValue;
  }
  
  String _formatVolume(int volume) {
    if (volume >= 1000000) {
      return '${(volume / 1000000).toStringAsFixed(1)}M';
    } else if (volume >= 1000) {
      return '${(volume / 1000).toStringAsFixed(1)}K';
    } else {
      return volume.toString();
    }
  }
  
  String _getStyleName(InvestmentStyle style) {
    return switch (style) {
      InvestmentStyle.conservative => 'conservative',
      InvestmentStyle.moderate => 'moderate',
      InvestmentStyle.aggressive => 'aggressive',
    };
  }
}
