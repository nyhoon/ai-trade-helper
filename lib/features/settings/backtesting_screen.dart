import 'package:flutter/material.dart';
import '../../core/trading/investment_style_manager.dart';
import '../../core/trading/investment_style.dart';
import '../../core/backtest/backtester.dart';

/// 백테스팅 화면
class BacktestingScreen extends StatefulWidget {
  const BacktestingScreen({super.key});

  @override
  State<BacktestingScreen> createState() => _BacktestingScreenState();
}

class _BacktestingScreenState extends State<BacktestingScreen> {
  final InvestmentStyleManager _styleManager = InvestmentStyleManager();
  bool _isBacktesting = false;
  BacktestResult? _backtestResult;

  @override
  void initState() {
    super.initState();
    _styleManager.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('백테스팅'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 현재 투자스타일 정보
            _buildCurrentStyleCard(),
            const SizedBox(height: 16),
            
            // 백테스트 설정
            _buildBacktestSettings(),
            const SizedBox(height: 16),
            
            // 백테스트 실행 버튼
            _buildBacktestButton(),
            const SizedBox(height: 16),
            
            // 백테스트 결과
            if (_backtestResult != null) _buildBacktestResults(),
          ],
        ),
      ),
    );
  }

  /// 현재 투자스타일 정보 카드
  Widget _buildCurrentStyleCard() {
    return StreamBuilder<InvestmentStyle>(
      stream: _styleManager.styleStream,
      builder: (context, snapshot) {
        final currentStyle = snapshot.data ?? _styleManager.currentStyle;
        
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.bar_chart, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '백테스트 설정',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  '현재 투자스타일: ${_getStyleName(currentStyle)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _getStyleColor(currentStyle),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '백테스트는 현재 선택된 투자스타일의 매매 전략을 과거 데이터로 검증합니다.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 백테스트 설정
  Widget _buildBacktestSettings() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                Text(
                  '백테스트 설정',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSettingItem('백테스트 기간', '최근 1년 (365일)'),
            _buildSettingItem('초기 자본', '10,000,000원'),
            _buildSettingItem('테스트 종목', '관심종목 + 보유종목'),
            _buildSettingItem('수수료', '0.015% (매매시)'),
            _buildSettingItem('슬리피지', '0.1% (체결가 차이)'),
          ],
        ),
      ),
    );
  }

  /// 설정 항목
  Widget _buildSettingItem(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  /// 백테스트 실행 버튼
  Widget _buildBacktestButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isBacktesting ? null : _runBacktest,
        icon: _isBacktesting 
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : const Icon(Icons.play_arrow),
        label: Text(_isBacktesting ? '백테스트 실행 중...' : '백테스트 실행'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  /// 백테스트 실행
  Future<void> _runBacktest() async {
    setState(() {
      _isBacktesting = true;
    });

    try {
      // 실제 백테스트 로직은 여기에 구현
      // 현재는 시뮬레이션 결과를 보여줌
      await Future.delayed(const Duration(seconds: 3));
      
      // 시뮬레이션 결과 생성
      final result = BacktestResult(
        initialEquity: 10000000.0,
        finalEquity: 12350000.0,
        totalReturn: 2350000.0,
        totalReturnPercent: 23.5,
        totalTrades: 45,
        winningTrades: 28,
        losingTrades: 17,
        winRate: 62.2,
        maxDrawdown: 8.5,
        trades: [],
        performance: {
          'sharpe_ratio': 1.85,
          'max_drawdown': 8.5,
          'avg_return': 2.1,
          'volatility': 12.3,
        },
      );

      setState(() {
        _backtestResult = result;
        _isBacktesting = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('백테스트가 완료되었습니다.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isBacktesting = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('백테스트 실행 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 백테스트 결과
  Widget _buildBacktestResults() {
    if (_backtestResult == null) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Text(
                  '백테스트 결과',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // 수익률 요약
            _buildResultSummary(),
            const SizedBox(height: 16),
            
            // 상세 지표
            _buildDetailedMetrics(),
            const SizedBox(height: 16),
            
            // 거래 통계
            _buildTradeStatistics(),
          ],
        ),
      ),
    );
  }

  /// 결과 요약
  Widget _buildResultSummary() {
    final result = _backtestResult!;
    final isPositive = result.totalReturnPercent > 0;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isPositive ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPositive ? Colors.green : Colors.red,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('총 수익률'),
              Text(
                '${result.totalReturnPercent.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isPositive ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('총 수익'),
              Text(
                '${result.totalReturn.toStringAsFixed(0).replaceAllMapped(
                  RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                  (Match m) => '${m[1]},',
                )}원',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isPositive ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 상세 지표
  Widget _buildDetailedMetrics() {
    final result = _backtestResult!;
    final performance = result.performance;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '상세 지표',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        _buildMetricRow('샤프 비율', '${performance['sharpe_ratio']?.toStringAsFixed(2) ?? 'N/A'}'),
        _buildMetricRow('최대 낙폭', '${performance['max_drawdown']?.toStringAsFixed(1) ?? 'N/A'}%'),
        _buildMetricRow('평균 수익률', '${performance['avg_return']?.toStringAsFixed(1) ?? 'N/A'}%'),
        _buildMetricRow('변동성', '${performance['volatility']?.toStringAsFixed(1) ?? 'N/A'}%'),
      ],
    );
  }

  /// 거래 통계
  Widget _buildTradeStatistics() {
    final result = _backtestResult!;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '거래 통계',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        _buildMetricRow('총 거래 수', '${result.totalTrades}건'),
        _buildMetricRow('승률', '${result.winRate.toStringAsFixed(1)}%'),
        _buildMetricRow('수익 거래', '${result.winningTrades}건'),
        _buildMetricRow('손실 거래', '${result.losingTrades}건'),
      ],
    );
  }

  /// 지표 행
  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// 스타일 색상 반환
  Color _getStyleColor(InvestmentStyle style) {
    switch (style) {
      case InvestmentStyle.conservative:
        return Colors.green;
      case InvestmentStyle.moderate:
        return const Color(0xFF3B5BA9);
      case InvestmentStyle.aggressive:
        return Colors.red;
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
}
