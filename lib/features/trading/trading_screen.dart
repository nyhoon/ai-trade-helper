import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/state/trading_bloc.dart';
import '../../core/data/app_data_manager.dart';
import '../../core/widgets/gradient_app_bar.dart';
import '../../core/trading/watchlist_manager.dart';
import '../../core/trading/investment_style_manager.dart';
import '../../core/trading/investment_style.dart';
import 'dart:async';
import 'watchlist_dialog.dart';
import 'stock_selection_dialog.dart';
import '../settings/investment_style_settings_screen.dart';
import '../settings/backtesting_screen.dart';

// 리팩토링된 위젯들 import
import 'widgets/stock_info_header_widget.dart';
import 'widgets/ai_trading_section_widget.dart';
import 'widgets/position_item_widget.dart';
import 'widgets/total_profit_summary_widget.dart';

class TradingScreen extends StatelessWidget {
  final Stream<void>? onTabFocusedStream;
  const TradingScreen({super.key, this.onTabFocusedStream});

  @override
  Widget build(BuildContext context) {
    return TradingScreenView(onTabFocusedStream: onTabFocusedStream);
  }
}

class TradingScreenView extends StatefulWidget {
  final Stream<void>? onTabFocusedStream;
  const TradingScreenView({super.key, this.onTabFocusedStream});

  @override
  State<TradingScreenView> createState() => _TradingScreenViewState();
}

class _TradingScreenViewState extends State<TradingScreenView> {
  String _selectedStockCode = '005930';
  String _selectedStockName = '삼성전자';
  Map<String, dynamic>? _aiAnalysis;
  List<WatchlistItem> _watchlist = [];

  // 데이터 매니저 인스턴스
  final AppDataManager _appDataManager = AppDataManager.instance;
  
  // 투자 스타일 매니저
  final InvestmentStyleManager _styleManager = InvestmentStyleManager();
  InvestmentStyle _currentStyle = InvestmentStyle.moderate;

  // 자동매매 상태
  bool _isAutoTradingLoading = false;
  bool _isAutoTradingEnabled = false;

  // 타이머
  Timer? _refreshTimer;
  bool _isRefreshing = false;

  String get _selectedStock => _selectedStockCode;

  /// 현재 투자 스타일 로드
  void _loadCurrentStyle() async {
    try {
      final currentStyle = await _styleManager.getCurrentStyle();
      if (mounted) {
        setState(() {
          _currentStyle = currentStyle;
        });
      }
    } catch (e) {
      print('❌ 투자 스타일 로드 실패: $e');
    }
  }

  /// 스타일 이름 반환
  String _getStyleName(InvestmentStyle style) {
    switch (style) {
      case InvestmentStyle.conservative:
        return '안정적 투자';
      case InvestmentStyle.moderate:
        return '일반적 투자';
      case InvestmentStyle.aggressive:
        return '공격적 투자';
    }
  }

  /// 스타일별 그라디언트 색상 반환
  List<Color> _getStyleGradientColors(InvestmentStyle style) {
    switch (style) {
      case InvestmentStyle.conservative:
        return [
          const Color(0xFF4CAF50), // 밝은 초록색
          const Color(0xFF388E3C), // 중간 초록색
          const Color(0xFF2E7D32), // 진한 초록색
        ];
      case InvestmentStyle.moderate:
        return [
          const Color(0xFF4A90E2), // 밝은 파란색
          const Color(0xFF357ABD), // 중간 파란색
          const Color(0xFF2E5A8A), // 진한 파란색
        ];
      case InvestmentStyle.aggressive:
        return [
          const Color(0xFFE53935), // 밝은 빨간색
          const Color(0xFFD32F2F), // 중간 빨간색
          const Color(0xFFC62828), // 진한 빨간색
        ];
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

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _startAutoRefresh();
    _initializeAutoTradingStatus();
    _loadCurrentStyle();
    // 거래 탭 포커스 시 강제 동기화
    widget.onTabFocusedStream?.listen((_) {
      if (mounted) {
        _initializeAutoTradingStatus();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// 초기 데이터 로드
  Future<void> _loadInitialData() async {
    try {
      await _appDataManager.loadTradingData();
      await _appDataManager.loadAllHoldings();
      await _loadWatchlist();

      if (mounted) {
        context.read<TradingBloc>().add(LoadStockData(_selectedStock));
      }
    } catch (e) {
      print('❌ 초기 데이터 로드 실패: $e');
    }
  }

  /// 관심종목 로드
  Future<void> _loadWatchlist() async {
    try {
      // SQL 조인으로 최신 점수/가격 포함 조회
      final watchlistData = await _appDataManager.getWatchlistWithScores();
      _watchlist = watchlistData.map((item) => WatchlistItem(
        stockCode: item['stock_code'] ?? item['stockCode'] ?? '',
        stockName: item['stock_name'] ?? item['stockName'] ?? '',
        addedAt: DateTime.fromMillisecondsSinceEpoch(
          item['added_at'] ?? item['addedAt'] ?? DateTime.now().millisecondsSinceEpoch
        ),
      )).toList();
      setState(() {});
    } catch (e) {
      print('❌ 관심종목 로드 실패: $e');
    }
  }

  /// 자동매매 상태 초기화
  Future<void> _initializeAutoTradingStatus() async {
    try {
      final stored = await _appDataManager.getAutoTradingStatus();
      _isAutoTradingEnabled = stored;
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('❌ AI 자동매매 상태 초기화 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('자동매매 상태 로드 실패'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 자동 새로고침 시작 (데이터베이스 락 방지를 위해 간격 증가)
  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      if (!_isRefreshing && mounted) {
        _isRefreshing = true;
        try {
          // 데이터베이스 락 방지를 위해 캐시 우선 새로고침
          await _appDataManager.refreshMarketData();
        } catch (e) {
          print('❌ 자동 새로고침 실패: $e');
        } finally {
          _isRefreshing = false;
        }
      }
    });
  }

  /// 자동매매 토글
  Future<void> _toggleAutoTrading(bool value) async {
    final previous = _isAutoTradingEnabled;
    setState(() {
      _isAutoTradingLoading = true;
      _isAutoTradingEnabled = value; // 낙관적 업데이트
    });

    try {
      await _appDataManager.setAutoTradingStatus(value);
      // 저장 직후 재조회하여 일치 여부 확인
      final reloaded = await _appDataManager.getAutoTradingStatus();
      if (reloaded != value) {
        // 롤백 및 알림
        _isAutoTradingEnabled = previous;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('자동매매 설정이 저장되지 않아 이전 상태로 복원했습니다.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      // 실패 시 롤백 및 에러 알림
      _isAutoTradingEnabled = previous;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('자동매매 설정 변경 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAutoTradingLoading = false;
        });
      }
    }
  }

  /// 관심종목 토글
  Future<void> _toggleWatchlist(String stockCode) async {
    try {
      final isInWatchlist = _appDataManager.isInWatchlist(stockCode);
      if (isInWatchlist) {
        await _appDataManager.removeFromWatchlist(stockCode);
      } else {
        final stockName = _appDataManager.getStockName(stockCode);
        await _appDataManager.addToWatchlist(stockCode, stockName);
      }
      await _loadWatchlist();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('관심종목 설정 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 종목 선택 다이얼로그 표시
  void _showStockSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => StockSelectionDialog(
        onStockSelected: (stockCode, stockName) {
          setState(() {
            _selectedStockCode = stockCode;
            _selectedStockName = stockName;
          });
          context.read<TradingBloc>().add(LoadStockData(stockCode));
        },
      ),
    );
  }

  /// 관심종목 다이얼로그 표시
  void _showWatchlistDialog() {
    showDialog(
      context: context,
      builder: (context) => WatchlistDialog(
        watchlist: _watchlist,
        onRemove: (stockCode) async {
          await _appDataManager.removeFromWatchlist(stockCode);
          await _loadWatchlist();
        },
        onClear: () async {
          for (final item in _watchlist) {
            await _appDataManager.removeFromWatchlist(item.stockCode);
          }
          await _loadWatchlist();
        },
        onStockSelected: (stockCode, stockName) {
          setState(() {
            _selectedStockCode = stockCode;
            _selectedStockName = stockName;
          });
          context.read<TradingBloc>().add(LoadStockData(stockCode));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '거래',
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
        colors: _getStyleGradientColors(_currentStyle),
        actions: [
          _buildDropdownMenu(),
        ],
      ),
      body: BlocBuilder<TradingBloc, TradingState>(
        builder: (context, state) {
          if (state is TradingLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          } else if (state is TradingError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '오류가 발생했습니다',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.message,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      context.read<TradingBloc>().add(LoadStockData(_selectedStock));
                    },
                    child: const Text('다시 시도'),
                  ),
                ],
              ),
            );
          } else if (state is TradingLoaded) {
            return _buildTradingView(state);
          }

          return const Center(
            child: CircularProgressIndicator(),
          );
        },
      ),
    );
  }

  Widget _buildTradingView(TradingLoaded state) {
    final stockData = state.stockData;
    final positions = state.positions;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(
        top: 16.0,
        left: 16.0,
        right: 16.0,
        bottom: 16.0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 주식 정보 헤더
          StockInfoHeaderWidget(
            stockCode: _selectedStock,
            stockName: _selectedStockName,
            stockData: stockData,
            onFavoriteTap: () => _toggleWatchlist(_selectedStock),
            onSearchTap: _showStockSelectionDialog,
            onListTap: _showWatchlistDialog,
          ),
          const SizedBox(height: 16),

          // AI 자동매매 섹션
          AiTradingSectionWidget(
            isAutoTradingEnabled: _isAutoTradingEnabled,
            onAutoTradingChanged: _toggleAutoTrading,
          ),
          const SizedBox(height: 16),

          // 보유종목 섹션 (보유종목이 있을 때만 표시)
          if (positions.isNotEmpty) _buildHoldingsSection(positions),
        ],
      ),
    );
  }

  /// 보유종목 섹션 빌드 (보유종목이 있을 때만 표시)
  Widget _buildHoldingsSection(List<Map<String, dynamic>> positions) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '보유 종목',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${positions.length}개 종목',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // 보유종목 목록
          ...positions.asMap().entries.map((entry) {
            final index = entry.key;
            final position = entry.value;
            return Column(
              children: [
                PositionItemWidget(
                  position: position,
                  onTap: () {
                    // 보유종목 상세 화면으로 이동
                    print('보유종목 상세: ${position['pdno']}');
                  },
                ),
                if (index < positions.length - 1)
                  Divider(
                    height: 1,
                    color: Colors.grey[200],
                    indent: 0,
                    endIndent: 0,
                  ),
              ],
            );
          }),
          
          // 전체 수익 요약 (보유종목 카드 안에 포함)
          if (positions.isNotEmpty) ...[
            const SizedBox(height: 16),
            TotalProfitSummaryWidget(positions: positions),
          ],
        ],
      ),
    );
  }

  /// 숫자 포맷팅 헬퍼
  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final num = double.tryParse(value.toString()) ?? 0.0;
    return num.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  /// 드롭다운 메뉴 빌드
  Widget _buildDropdownMenu() {
    return Container(
      margin: const EdgeInsets.only(right: 16),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          items: [
            DropdownMenuItem<String>(
              value: 'investment_style',
              child: Row(
                children: [
                  Icon(Icons.settings, color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  const Text('투자 스타일 설정'),
                ],
              ),
            ),
            DropdownMenuItem<String>(
              value: 'backtest_results',
              child: Row(
                children: [
                  Icon(Icons.bar_chart, color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  const Text('백테스팅'),
                ],
              ),
            ),
          ],
          onChanged: (String? value) {
            if (value != null) {
              switch (value) {
                case 'investment_style':
                  _navigateToInvestmentStyleSettings();
                  break;
                case 'backtest_results':
                  _navigateToBacktestResults();
                  break;
              }
            }
          },
        ),
      ),
    );
  }

  /// 투자 스타일 설정 화면으로 이동
  void _navigateToInvestmentStyleSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const InvestmentStyleSettingsScreen(),
      ),
    );
    // 설정 화면에서 돌아올 때 스타일 다시 로드
    _loadCurrentStyle();
  }

  /// 백테스트 결과 화면으로 이동
  void _navigateToBacktestResults() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const BacktestingScreen(),
      ),
    );
  }
}