import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/data/app_data_manager.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/gradient_app_bar.dart';
import '../../core/trading/investment_style_manager.dart';
import '../../core/trading/investment_style.dart';
import '../../core/config/api_config.dart';
import '../../core/database/repositories/trade_history_repository.dart';
import '../../core/database/repositories/signal_history_repository.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with TickerProviderStateMixin {
  final InvestmentStyleManager _styleManager = InvestmentStyleManager();
  final TradeHistoryRepository _tradeHistoryRepository = TradeHistoryRepository();
  final SignalHistoryRepository _signalHistoryRepository = SignalHistoryRepository();
  StreamSubscription<InvestmentStyle>? _styleSubscription;
  InvestmentStyle _currentStyle = InvestmentStyle.moderate;
  bool _isAutoTradingEnabled = false;
  
  List<Map<String, dynamic>> _tradeHistory = [];
  List<Map<String, dynamic>> _signalHistory = [];
  Map<String, dynamic>? _statistics;
  bool _isLoading = false;
  
  // 필터 제거 - 자동매매만 표시

  @override
  void initState() {
    super.initState();
    _initializeStyleManager();
    _loadAutoTradingStatus();
    _loadHistory();
  }

  @override
  void dispose() {
    _styleSubscription?.cancel();
    _isLoading = false; // dispose 후 setState 방지
    super.dispose();
  }

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

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 1. 거래 내역 로드
      await _tradeHistoryRepository.createTable();
      final tradeHistory = await _tradeHistoryRepository.getAutoTradeHistory();

      // 2. 시그널 히스토리 로드
      final signalHistory = await _signalHistoryRepository.getRecentSignals(limit: 100);

      // 3. 종목명 보강 (코스피/코스닥/나스닥 모두)
      final List<Map<String, dynamic>> enrichedTradeHistory = [];
      for (final t in tradeHistory) {
        final stockCode = (t['stockCode'] ?? '').toString();
        String stockName = (t['stockName'] ?? '').toString();
        if (stockName.isEmpty || stockName == stockCode) {
          try {
            stockName = await AppDataManager.instance.getStockNameAsync(stockCode);
          } catch (_) {}
        }
        enrichedTradeHistory.add({...t, 'stockName': stockName, 'type': 'trade'});
      }

      final List<Map<String, dynamic>> enrichedSignalHistory = [];
      for (final s in signalHistory) {
        final stockCode = (s['stock_code'] ?? '').toString();
        String stockName = (s['stock_name'] ?? '').toString();
        if (stockName.isEmpty || stockName == stockCode) {
          try {
            stockName = await AppDataManager.instance.getStockNameAsync(stockCode);
          } catch (_) {}
        }
        enrichedSignalHistory.add({...s, 'stockName': stockName, 'type': 'signal'});
      }

      setState(() {
        _tradeHistory = enrichedTradeHistory;
        _signalHistory = enrichedSignalHistory;
        _isLoading = false;
      });
      
      // 내역 로드 후 통계 계산
      await _loadStatistics();
    } catch (e) {
      print('❌ 내역 로드 실패: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadStatistics() async {
    try {
      // 거래 내역 통계
      int totalTrades = _tradeHistory.length;
      int buyTrades = 0;
      int sellTrades = 0;

      // 총 손익을 원화로 환산
      double totalProfitLossWon = 0.0;
      const double exchangeRate = 1400.0; // 1달러 = 1400원 (간단 환산)
      
      for (final trade in _tradeHistory) {
        final orderType = (trade['orderType'] ?? '').toString();
        if (orderType == '매수') buyTrades++;
        if (orderType == '매도') sellTrades++;

        final stockCode = (trade['stockCode'] ?? '').toString();
        final isNasdaq = _isNasdaqStock(stockCode);
        final profitLoss = (trade['profitLoss'] as num?)?.toDouble() ?? 0.0;
        totalProfitLossWon += isNasdaq ? profitLoss * exchangeRate : profitLoss;
      }

      // 시그널 히스토리 통계
      int totalSignals = _signalHistory.length;
      int buySignals = 0;
      int sellSignals = 0;
      
      for (final signal in _signalHistory) {
        final signalType = (signal['signal_type'] ?? '').toString();
        if (signalType == '매수') buySignals++;
        if (signalType == '매도') sellSignals++;
      }

      if (mounted) {
        setState(() {
          _statistics = {
            'totalTrades': totalTrades,
            'buyTrades': buyTrades,
            'sellTrades': sellTrades,
            'totalProfitLossWon': totalProfitLossWon,
            'totalSignals': totalSignals,
            'buySignals': buySignals,
            'sellSignals': sellSignals,
          };
        });
      }
    } catch (e) {
      print('❌ 내역 통계 로드 실패: $e');
    }
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
              '내역',
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
            onPressed: () {
              _loadHistory();
            },
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            // 통계 카드
            if (_statistics != null) _buildStatisticsCard(),
            
            // 거래 내역 목록
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _tradeHistory.isEmpty && _signalHistory.isEmpty
                      ? _buildEmptyState()
                      : _buildHistoryList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsCard() {
    final stats = _statistics!;
    
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '거래 통계',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    '총 거래',
                    '${stats['totalTrades']}건',
                    Colors.blue,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    '매수',
                    '${stats['buyTrades']}건',
                    Colors.red,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    '매도',
                    '${stats['sellTrades']}건',
                    Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    '총 손익',
                    '${_formatNumber(stats['totalProfitLossWon'] ?? 0)}원',
                    (stats['totalProfitLossWon'] ?? 0) >= 0 ? Colors.green : Colors.red,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    '총 시그널',
                    '${stats['totalSignals']}건',
                    Colors.orange,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    '시그널 매수',
                    '${stats['buySignals']}건',
                    Colors.red,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            '자동매매 거래 내역이 없습니다',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'AI 자동매매가 활성화되면 여기에 거래 내역이 표시됩니다',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    return ListView.builder(
      itemCount: _tradeHistory.length + _signalHistory.length,
      itemBuilder: (context, index) {
        if (index < _tradeHistory.length) {
          final trade = _tradeHistory[index];
          return _buildHistoryItem(trade);
        } else {
          final signal = _signalHistory[index - _tradeHistory.length];
          return _buildHistoryItem(signal);
        }
      },
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> item) {
    final itemType = item['type'] as String? ?? 'trade';
    
    if (itemType == 'signal') {
      return _buildSignalHistoryItem(item);
    } else {
      return _buildTradeHistoryItem(item);
    }
  }

  Widget _buildTradeHistoryItem(Map<String, dynamic> item) {
    final orderType = item['orderType'] as String;
    final orderTypeColor = orderType == '매수' ? Colors.red : Colors.blue;
    final isAutoTrade = item['isAutoTrade'] as bool;
    final profitLoss = item['profitLoss'] as double? ?? 0.0;
    final profitRate = item['profitRate'] as double? ?? 0.0;
    
    // 나스닥 종목 여부 확인
    final stockCode = item['stockCode'] as String? ?? '';
    final isNasdaq = _isNasdaqStock(stockCode);
    final currency = isNasdaq ? '\$' : '원';
    final exchangeRate = 1400.0; // 1달러 = 1400원
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Row(
              children: [
                // 거래 타입 아이콘
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: orderTypeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    orderType == '매수' ? Icons.trending_up : Icons.trending_down,
                    color: orderTypeColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                
                // 종목 정보
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['stockName'] ?? item['stockCode'],
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        item['stockCode'],
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // 거래 타입 및 자동 매매/매수/매도 표시
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      orderType,
                      style: TextStyle(
                        color: orderTypeColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    if (isAutoTrade)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          orderType == '매수' ? '자동매수' : '자동매도',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // 거래 상세 정보
            Row(
              children: [
                Expanded(
                  child: _buildTradeDetail(
                    '수량',
                    '${_formatNumber(item['quantity'])}주',
                  ),
                ),
                Expanded(
                  child: _buildTradeDetail(
                    '가격',
                    '${_formatNumber(item['price'], isNasdaq: isNasdaq)}$currency',
                  ),
                ),
                Expanded(
                  child: _buildTradeDetail(
                    '총액',
                    '${_formatNumber(item['totalAmount'], isNasdaq: isNasdaq)}$currency',
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // 손익 정보 (매도인 경우)
            if (orderType == '매도' && (profitLoss != 0 || profitRate != 0))
              Row(
                children: [
                  Expanded(
                    child: _buildTradeDetail(
                      '손익',
                      '${profitLoss >= 0 ? '+' : ''}${_formatNumber(profitLoss, isNasdaq: isNasdaq)}$currency',
                      profitLoss >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                  Expanded(
                    child: _buildTradeDetail(
                      '수익률',
                      '${profitRate >= 0 ? '+' : ''}${profitRate.toStringAsFixed(2)}%',
                      profitRate >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                  const Expanded(child: SizedBox()),
                ],
              ),
            
            const SizedBox(height: 8),
            
            // 거래 이유 및 투자 스타일
            if (item['tradeReason'] != null || item['investmentStyle'] != null)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item['tradeReason'] != null) ...[
                      Text(
                        '거래 이유: ${item['tradeReason']}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (item['investmentStyle'] != null)
                      Text(
                        '투자 스타일: ${item['investmentStyle']}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    if (item['metConditions'] != null && item['totalConditions'] != null)
                      Text(
                        '조건 만족: ${item['metConditions']}/${item['totalConditions']}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              ),
            
            const SizedBox(height: 8),
            
            // 거래 시간
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${item['orderDate']} ${item['orderTime']}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
                if (isAutoTrade)
                  Text(
                    '자동매매',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTradeDetail(String label, String value, [Color? color]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  /// 숫자를 천 단위 구분으로 포맷팅
  String _formatNumber(dynamic number, {bool isNasdaq = false}) {
    if (isNasdaq) {
      // 나스닥 종목은 double로 처리 (소수점 2자리)
      final doubleValue = (number as num).toDouble();
      return doubleValue.toStringAsFixed(2);
    } else {
      // 국내 종목은 기존 방식 (정수)
      return Formatters.formatNumber(number);
    }
  }
  
  Widget _buildSignalHistoryItem(Map<String, dynamic> signal) {
    final signalType = signal['signal_type'] as String? ?? '';
    final signalTypeColor = signalType == '매수' ? Colors.red : Colors.blue;
    final stockCode = signal['stock_code'] as String? ?? '';
    final stockName = signal['stock_name'] as String? ?? '';
    final price = (signal['price'] as num?)?.toDouble() ?? 0.0;
    final signalStrength = (signal['signal_strength'] as num?)?.toDouble() ?? 0.0;
    final confidence = (signal['confidence'] as num?)?.toDouble() ?? 0.0;
    final memo = signal['memo'] as String? ?? '';
    final triggeredAt = signal['triggered_at'] as int? ?? 0;
    
    // 나스닥 종목 여부 확인
    final isNasdaq = _isNasdaqStock(stockCode);
    final currency = isNasdaq ? '\$' : '원';
    
    // 시간 포맷팅
    final dateTime = DateTime.fromMillisecondsSinceEpoch(triggeredAt);
    final dateStr = '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    final timeStr = '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Row(
              children: [
                // 시그널 타입 아이콘
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: signalTypeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    signalType == '매수' ? Icons.trending_up : Icons.trending_down,
                    color: signalTypeColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                
                // 종목 정보
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stockName.isNotEmpty ? stockName : stockCode,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        stockCode,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // 시그널 타입 및 자동매매 표시
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$signalType 시그널',
                      style: TextStyle(
                        color: signalTypeColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    if (memo.contains('AutoTrading_'))
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '자동매매',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // 시그널 상세 정보
            Row(
              children: [
                Expanded(
                  child: _buildTradeDetail(
                    '가격',
                    '${_formatNumber(price, isNasdaq: isNasdaq)}$currency',
                  ),
                ),
                Expanded(
                  child: _buildTradeDetail(
                    '시그널 강도',
                    signalStrength.toStringAsFixed(3),
                  ),
                ),
                Expanded(
                  child: _buildTradeDetail(
                    '신뢰도',
                    confidence.toStringAsFixed(3),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // 메모 정보
            if (memo.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '메모: $memo',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            
            const SizedBox(height: 8),
            
            // 시그널 발생 시간
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$dateStr $timeStr',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
                Text(
                  '시그널',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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

  /// 나스닥 종목 여부 확인
  bool _isNasdaqStock(String stockCode) {
    return stockCode.length >= 4 && RegExp(r'^[A-Z]+$').hasMatch(stockCode);
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
