import 'package:flutter/material.dart';
import '../../../core/data/app_data_manager.dart';
import '../../../core/data/unified_stock_data_manager.dart';
import '../../../core/utils/formatters.dart';

/// 보유 종목 목록을 표시하는 위젯
class AccountHoldingsWidget extends StatefulWidget {
  final Map<String, dynamic>? accountData;

  const AccountHoldingsWidget({
    super.key,
    required this.accountData,
  });

  @override
  State<AccountHoldingsWidget> createState() => _AccountHoldingsWidgetState();
}

class _AccountHoldingsWidgetState extends State<AccountHoldingsWidget> {
  bool _isRefreshing = false;
  bool _hasInitialized = false;

  @override
  void initState() {
    super.initState();
    // 화면 진입 시 자동으로 캐시 무효화
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoRefreshOnFirstLoad();
    });
  }

  /// 첫 로드 시 자동 새로고침 (캐시 무효화)
  Future<void> _autoRefreshOnFirstLoad() async {
    if (_hasInitialized) return;
    
    try {
      print('🔄 보유종목 화면 첫 진입 - 캐시 무효화 시작...');
      
      // 캐시 무효화만 수행 (UI 업데이트는 하지 않음)
      AppDataManager.instance.invalidateCache();
      UnifiedStockDataManager.instance.clearCache();
      
      _hasInitialized = true;
      print('✅ 보유종목 화면 캐시 무효화 완료');
      
    } catch (e) {
      print('❌ 보유종목 화면 캐시 무효화 실패: $e');
    }
  }

  /// 보유종목 데이터 새로고침 (캐시 무효화)
  Future<void> _refreshHoldingsData() async {
    if (_isRefreshing) return;
    
    setState(() {
      _isRefreshing = true;
    });
    
    try {
      print('🔄 보유종목 데이터 새로고침 시작...');
      
      // 1. 모든 캐시 무효화
      AppDataManager.instance.invalidateCache();
      UnifiedStockDataManager.instance.clearCache();
      
      // 2. 보유종목 데이터 강제 새로고침
      await AppDataManager.instance.loadAllHoldings();
      
      // 3. UI 새로고침을 위해 부모 위젯에 알림
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('보유종목 데이터가 새로고침되었습니다'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }
      
      print('✅ 보유종목 데이터 새로고침 완료');
      
    } catch (e) {
      print('❌ 보유종목 데이터 새로고침 실패: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('새로고침 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final domesticHoldings = widget.accountData?['domesticHoldings'] as List<dynamic>? ?? [];
    final overseasHoldings = widget.accountData?['overseasHoldings'] as List<dynamic>? ?? [];
    final allHoldings = [...domesticHoldings, ...overseasHoldings];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '보유 종목',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      '${allHoldings.length}개',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: _isRefreshing 
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh, size: 20),
                      onPressed: _isRefreshing ? null : _refreshHoldingsData,
                      tooltip: '보유종목 데이터 새로고침',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (allHoldings.isEmpty)
              _buildEmptyHoldings()
            else
              ...allHoldings.map((holding) => _buildHoldingItem(holding as Map<String, dynamic>)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyHoldings() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32.0),
        child: Text(
          '보유 종목이 없습니다.',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget _buildHoldingItem(Map<String, dynamic> holding) {
    final stockCode = holding['stockCode'] as String? ?? '';
    final stockName = _getDisplayName(stockCode, holding);
    final quantity = (holding['quantity'] as num?)?.toInt() ?? 0;
    final avgPrice = (holding['avgPrice'] as num?)?.toDouble() ?? 0.0;
    final currentPrice = (holding['currentPrice'] as num?)?.toDouble() ?? 0.0;
    final profit = (holding['profit'] as num?)?.toDouble() ?? 0.0;
    final profitRate = (holding['profitRate'] as num?)?.toDouble() ?? 0.0;
    final totalValue = (holding['totalValue'] as num?)?.toDouble() ?? 0.0;
    
    // 나스닥 종목인지 확인
    final isNasdaq = _isNasdaqStock(stockCode);
    final currency = isNasdaq ? '\$' : '원';
    final formatPrice = isNasdaq ? _formatDollarPrice : _formatNumber;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stockName,
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${quantity}주',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${formatPrice(totalValue)}$currency',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildHoldingDetail(
                  '평균단가',
                  '${formatPrice(avgPrice)}$currency',
                ),
              ),
              Expanded(
                child: _buildHoldingDetail(
                  '현재가',
                  '${formatPrice(currentPrice)}$currency',
                ),
              ),
              Expanded(
                child: _buildHoldingDetail(
                  '손익',
                  '${profit >= 0 ? '+' : ''}${_formatProfitValue(profit, stockCode)}',
                  profit >= 0 ? Colors.green : Colors.red,
                ),
              ),
              Expanded(
                child: _buildHoldingDetail(
                  '수익률',
                  '${profitRate >= 0 ? '+' : ''}${profitRate.toStringAsFixed(2)}%',
                  profitRate >= 0 ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHoldingDetail(String label, String value, [Color? color]) {
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

  /// 나스닥 종목인지 확인
  bool _isNasdaqStock(String stockCode) {
    final marketUpper = stockCode.toUpperCase();
    final isUsMarket = marketUpper.startsWith('A') || 
                      marketUpper.startsWith('Q') || 
                      marketUpper.startsWith('T') || 
                      marketUpper.startsWith('N') ||
                      marketUpper.startsWith('PLTZ') ||
                      marketUpper.startsWith('TSLA') ||
                      marketUpper.startsWith('AAPL') ||
                      marketUpper.startsWith('GOOGL') ||
                      marketUpper.startsWith('MSFT') ||
                      marketUpper.startsWith('AMZN') ||
                      marketUpper.startsWith('META') ||
                      marketUpper.startsWith('NVDA') ||
                      marketUpper.startsWith('NFLX') ||
                      marketUpper.startsWith('AMD') ||
                      marketUpper.startsWith('INTC') ||
                      marketUpper.startsWith('CRM') ||
                      marketUpper.startsWith('ORCL') ||
                      marketUpper.startsWith('ADBE') ||
                      marketUpper.startsWith('PYPL') ||
                      marketUpper.startsWith('UBER') ||
                      marketUpper.startsWith('LYFT') ||
                      marketUpper.startsWith('SNAP') ||
                      marketUpper.startsWith('TWTR') ||
                      marketUpper.startsWith('SPOT') ||
                      marketUpper.startsWith('ZM') ||
                      marketUpper.startsWith('SQ') ||
                      marketUpper.startsWith('SHOP') ||
                      marketUpper.startsWith('ROKU') ||
                      marketUpper.startsWith('PINS') ||
                      marketUpper.startsWith('OKTA') ||
                      marketUpper.startsWith('NET') ||
                      marketUpper.startsWith('MELI') ||
                      marketUpper.startsWith('JD') ||
                      marketUpper.startsWith('BABA') ||
                      marketUpper.startsWith('PDD') ||
                      marketUpper.startsWith('NIO') ||
                      marketUpper.startsWith('XPEV') ||
                      marketUpper.startsWith('LI') ||
                      marketUpper.startsWith('BIDU') ||
                      marketUpper.startsWith('TCEHY') ||
                      marketUpper.startsWith('NTES') ||
                      marketUpper.startsWith('BILI') ||
                      marketUpper.startsWith('HUYA') ||
                      marketUpper.startsWith('DOYU') ||
                      marketUpper.startsWith('TME') ||
                      marketUpper.startsWith('DIDI') ||
                      marketUpper.startsWith('XNET') ||
                      marketUpper.startsWith('GDS') ||
                      marketUpper.startsWith('ZTO') ||
                      marketUpper.startsWith('YUMC') ||
                      marketUpper.startsWith('TCOM') ||
                      marketUpper.startsWith('CTRP') ||
                      marketUpper.startsWith('HTHT') ||
                      marketUpper.startsWith('WB') ||
                      marketUpper.startsWith('SINA') ||
                      marketUpper.startsWith('SOHU') ||
                      marketUpper.startsWith('NTES') ||
                      marketUpper.startsWith('EDU') ||
                      marketUpper.startsWith('TAL') ||
                      marketUpper.startsWith('DAO') ||
                      marketUpper.startsWith('FUTU') ||
                      marketUpper.startsWith('TIGR') ||
                      marketUpper.startsWith('XFIN') ||
                      marketUpper.startsWith('LIZI') ||
                      marketUpper.startsWith('GOTU') ||
                      marketUpper.startsWith('GSX') ||
                      marketUpper.startsWith('VIPS');
    
    final isLikelyUsTicker = stockCode.length >= 3 && 
                            stockCode.length <= 5 && 
                            stockCode == stockCode.toUpperCase() &&
                            RegExp(r'^[A-Z]+$').hasMatch(stockCode);
    
    return isUsMarket || isLikelyUsTicker;
  }

  /// 숫자를 천 단위 구분으로 포맷팅
  String _formatNumber(dynamic number) {
    return Formatters.formatNumber(number);
  }

  /// 달러 가격을 천 단위 구분으로 포맷팅
  String _formatDollarPrice(dynamic number) {
    final doubleValue = (number as num?)?.toDouble() ?? 0.0;
    return doubleValue.toStringAsFixed(2);
  }

  /// 손익 가치 포맷팅 (나스닥은 달러로 표시)
  String _formatProfitValue(double value, String stockCode) {
    final isNasdaq = _isNasdaqStock(stockCode);
    if (isNasdaq) {
      return '\$${_formatDollarPrice(value)}';
    } else {
      return '${_formatNumber(value)}원';
    }
  }

  String _getDisplayName(String stockCode, Map<String, dynamic> holding) {
    // AppDataManager에서 종목명 가져오기
    final masterName = AppDataManager.instance.getStockName(stockCode);
    if (masterName.isNotEmpty && masterName != stockCode) {
      return masterName;
    }
    
    // API 응답에서 종목명 확인
    final apiName = holding['stockName'] as String?;
    if (apiName != null && apiName.isNotEmpty && apiName != stockCode) {
      return apiName;
    }
    
    // 최후 수단으로 종목코드 반환
    return stockCode;
  }
}
