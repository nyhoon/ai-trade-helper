import 'package:flutter/material.dart';

/// 전체 수익 요약 위젯
class TotalProfitSummaryWidget extends StatelessWidget {
  final List<Map<String, dynamic>> positions;

  const TotalProfitSummaryWidget({
    Key? key,
    required this.positions,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    
    double totalDomesticProfit = 0.0; // 국내주식 손익 (원화)
    double totalOverseasProfit = 0.0; // 해외주식 손익 (달러)
    int domesticCount = 0;
    int overseasCount = 0;
    
    for (final position in positions) {
      // API 필드명으로 손익 가져오기 (evlu_pfls_amt)
      final profit = _parseDouble(position['evlu_pfls_amt']) ?? 0.0;
      final stockCode = position['pdno'] ?? position['stockCode'] ?? position['stock_code'] ?? '';
      
      print('📊 [전체수익계산] 종목: $stockCode, 손익: $profit원');
      
      // 나스닥 종목인지 확인
      final isNasdaq = _isNasdaqStock(stockCode);
      
      if (isNasdaq) {
        totalOverseasProfit += profit;
        overseasCount++;
      } else {
        totalDomesticProfit += profit;
        domesticCount++;
      }
    }
    
    print('📊 [전체수익계산] 국내: $totalDomesticProfit원 (${domesticCount}개), 해외: \$${totalOverseasProfit} (${overseasCount}개)');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50], // 하늘색 배경으로 구분
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '전체 수익',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 국내주식 손익 (원화)
                  if (domesticCount > 0)
                    Text(
                      '${totalDomesticProfit >= 0 ? '+' : ''}${_formatNumber(totalDomesticProfit)}원',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: totalDomesticProfit >= 0 ? Colors.red : Colors.blue,
                      ),
                    ),
                  // 해외주식 손익 (달러)
                  if (overseasCount > 0)
                    Text(
                      '${totalOverseasProfit >= 0 ? '+' : ''}\$${totalOverseasProfit.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: totalOverseasProfit >= 0 ? Colors.red : Colors.blue,
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '보유 종목',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              Text(
                '${domesticCount > 0 ? '국내 ${domesticCount}개' : ''}${domesticCount > 0 && overseasCount > 0 ? ' / ' : ''}${overseasCount > 0 ? '해외 ${overseasCount}개' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 나스닥 종목인지 확인
  bool _isNasdaqStock(String stockCode) {
    // 나스닥 종목 코드 패턴 (예: AAPL, TSLA 등)
    return stockCode.length <= 5 && 
           stockCode == stockCode.toUpperCase() && 
           !RegExp(r'^\d+$').hasMatch(stockCode);
  }

  /// 숫자 파싱
  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  /// 숫자 포맷팅
  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final num = double.tryParse(value.toString()) ?? 0.0;
    return num.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }
}
