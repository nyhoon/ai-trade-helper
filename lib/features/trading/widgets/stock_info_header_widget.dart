import 'package:flutter/material.dart';
import '../../../core/data/app_data_manager.dart';
import '../../../core/trading/investment_style_manager.dart';

/// 주식 정보 헤더 위젯
class StockInfoHeaderWidget extends StatelessWidget {
  final String stockCode;
  final String stockName;
  final Map<String, dynamic> stockData;
  final VoidCallback? onFavoriteTap;
  final VoidCallback? onSearchTap;
  final VoidCallback? onListTap;

  const StockInfoHeaderWidget({
    Key? key,
    required this.stockCode,
    required this.stockName,
    required this.stockData,
    this.onFavoriteTap,
    this.onSearchTap,
    this.onListTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 디버그 로깅 추가
    print('🔍 [StockInfoHeader] stockData: $stockData');
    
    final currentPrice = _toDouble(stockData['prpr']) ?? 0.0;
    final change = _toDouble(stockData['diff']) ?? 0.0;
    final changeRate = _toDouble(stockData['rate']) ?? 0.0;
    final openPrice = _toDouble(stockData['open']) ?? 0.0;
    final highPrice = _toDouble(stockData['high']) ?? 0.0;
    final lowPrice = _toDouble(stockData['low']) ?? 0.0;
    // 거래량: 다중 소스 폴백 (API→캐시→차트)
    double volume = _toDouble(stockData['acml_vol']) ?? 0.0;
    if (volume <= 0) {
      final cachedData = AppDataManager.instance.getCachedStockData(stockCode);
      final cachedVol = _toDouble(cachedData['acml_vol'])
          + _toDouble(cachedData['volume']);
      if (cachedVol > 0) {
        volume = cachedVol;
        print('🔍 [StockInfoHeader] 거래량 캐시 폴백 사용: $volume');
      } else {
        try {
          final cachedChart = AppDataManager.instance.getCachedChartData(stockCode);
          if (cachedChart.isNotEmpty) {
            final last = cachedChart.last;
            final chartVol = _toDouble(last['volume']);
            if (chartVol > 0) {
              volume = chartVol;
              print('🔍 [StockInfoHeader] 거래량 차트 폴백 사용: $volume');
            }
          }
        } catch (_) {}
      }
    }
    final market = (stockData['market']?.toString().toUpperCase() ?? '');
    final exchange = (stockData['exchange']?.toString().toUpperCase() ?? '');
    final bool isNasdaq = _isNasdaqStock(stockCode) || market == 'NASDAQ' || exchange == 'NAS';
    
    // 가격이 0인 경우 캐시에서 확인
    double finalCurrentPrice = currentPrice;
    if (finalCurrentPrice <= 0) {
      final cachedData = AppDataManager.instance.getCachedPrice(stockCode);
      if (cachedData != null) {
        final cachedPrice = _toDouble(cachedData['prpr']);
        if (cachedPrice > 0) {
          finalCurrentPrice = cachedPrice;
          print('🔍 [StockInfoHeader] 캐시에서 가격 복구: $finalCurrentPrice');
        }
      }
    }
    
    print('🔍 [StockInfoHeader] 최종 현재가: $finalCurrentPrice');

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
          // 종목명과 액션 버튼들
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 종목명 (전체 표시)
                    Text(
                      stockName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 4),
                    // 종목 코드만 표시
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getMarketColor(stockCode).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _getMarketColor(stockCode).withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        stockCode,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _getMarketColor(stockCode),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onFavoriteTap,
                icon: Icon(
                  AppDataManager.instance.isInWatchlist(stockCode)
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: AppDataManager.instance.isInWatchlist(stockCode)
                      ? Colors.red
                      : Colors.grey,
                ),
              ),
              IconButton(
                onPressed: onSearchTap,
                icon: const Icon(Icons.search),
              ),
              IconButton(
                onPressed: onListTap,
                icon: const Icon(Icons.list),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // 현재가와 변동률
          Row(
            children: [
              Expanded(
                child: Text(
                  isNasdaq ? '\$${_formatNumber(finalCurrentPrice, decimals: 2)}' : '${_formatNumber(finalCurrentPrice)}원',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: change >= 0 ? Colors.red.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${change >= 0 ? '+' : ''}${isNasdaq ? _formatNumber(change, decimals: 2) : _formatNumber(change)} (${changeRate >= 0 ? '+' : ''}${changeRate.toStringAsFixed(2)}%)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: change >= 0 ? Colors.red : Colors.blue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // 전일 종가
          Text(
            isNasdaq
                ? '전일: \$${_formatNumber(_toDouble(stockData['stck_prdy_clpr']), decimals: 2)}'
                : '전일: ${_formatNumber(_toDouble(stockData['stck_prdy_clpr']))}원',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),
          
          // 시가, 고가, 저가, 거래량
          Row(
            children: [
              Expanded(
                child: _buildInfoItem('시가', isNasdaq ? '\$${_formatNumber(openPrice, decimals: 2)}' : '${_formatNumber(openPrice)}원'),
              ),
              Expanded(
                child: _buildInfoItem('고가', isNasdaq ? '\$${_formatNumber(highPrice, decimals: 2)}' : '${_formatNumber(highPrice)}원', Colors.red),
              ),
              Expanded(
                child: _buildInfoItem('저가', isNasdaq ? '\$${_formatNumber(lowPrice, decimals: 2)}' : '${_formatNumber(lowPrice)}원', Colors.blue),
              ),
              Expanded(
                child: _buildInfoItem('거래량', _formatNumber(volume)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, [Color? valueColor]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
            fontWeight: FontWeight.w500,
            color: valueColor ?? Colors.black,
          ),
        ),
      ],
    );
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  String _formatNumber(dynamic value, {int decimals = 0}) {
    if (value == null) return decimals > 0 ? '0.${'0' * decimals}' : '0';
    final num = double.tryParse(value.toString()) ?? 0.0;
    final fixed = num.toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    if (decimals == 0) return intPart;
    final frac = parts.length > 1 ? parts[1] : ''.padRight(decimals, '0');
    return '$intPart.$frac';
  }

  bool _isNasdaqStock(String stockCode) {
    return stockCode.length <= 5 &&
           stockCode == stockCode.toUpperCase() &&
           !RegExp(r'^\d+$').hasMatch(stockCode);
  }

  Color _getMarketColor(String stockCode) {
    if (_isNasdaqStock(stockCode)) {
      return Colors.green; // 해외주식 (나스닥)
    } else if (stockCode.startsWith('0') || stockCode.startsWith('1')) {
      return Colors.orange; // 코스닥
    } else {
      return Colors.blue; // 코스피
    }
  }

  String _getInvestmentStyleText() {
    try {
      final styleManager = InvestmentStyleManager();
      final style = styleManager.currentStyle;
      switch (style.toString()) {
        case 'InvestmentStyle.conservative':
          return '안정적';
        case 'InvestmentStyle.moderate':
          return '일반적';
        case 'InvestmentStyle.aggressive':
          return '공격적';
        default:
          return '일반적';
      }
    } catch (e) {
      return '일반적';
    }
  }

  Color _getInvestmentStyleColor() {
    try {
      final styleManager = InvestmentStyleManager();
      final style = styleManager.currentStyle;
      switch (style.toString()) {
        case 'InvestmentStyle.conservative':
          return Colors.blue; // 안정적 - 파란색
        case 'InvestmentStyle.moderate':
          return Colors.green; // 일반적 - 초록색
        case 'InvestmentStyle.aggressive':
          return Colors.red; // 공격적 - 빨간색
        default:
          return Colors.green;
      }
    } catch (e) {
      return Colors.green;
    }
  }
}
