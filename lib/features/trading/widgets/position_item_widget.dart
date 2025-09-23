import 'package:flutter/material.dart';
import '../../../core/data/app_data_manager.dart';

/// 보유종목 개별 아이템 위젯
class PositionItemWidget extends StatelessWidget {
  final Map<String, dynamic> position;
  final VoidCallback? onTap;

  const PositionItemWidget({
    Key? key,
    required this.position,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // API 필드명으로 데이터 추출
    final stockCode = position['pdno'] ?? position['stockCode'] ?? position['stock_code'] ?? '';
    final stockName = _resolveDisplayName(stockCode, position);
    final quantity = _parseInt(position['hldg_qty']) ?? 
                    _parseInt(position['quantity']) ?? 0;
    final avgPrice = _parseDouble(position['pchs_avg_pric']) ?? 
                    _parseDouble(position['avgPrice']) ?? 0.0;
    final currentPrice = _parseDouble(position['prpr']) ?? 0.0;
    final profit = _parseDouble(position['evlu_pfls_amt']) ?? 0.0;
    final profitRate = _parseDouble(position['evlu_pfls_rt']) ?? 0.0;

    // 현재가 우선순위: position 데이터 → AppDataManager 캐시 → 실시간 조회
    double finalCurrentPrice = currentPrice;
    try {
      if (finalCurrentPrice <= 0) {
        final cachedPriceData = AppDataManager.instance.getCachedPrice(stockCode);
        if (cachedPriceData != null) {
          final cachedPrice = _parseDouble(cachedPriceData['prpr']);
          if (cachedPrice != null && cachedPrice > 0) {
            finalCurrentPrice = cachedPrice;
          }
        }
      }
      
      // 디버깅: 티로보틱스 가격 확인
      if (stockCode.contains('티로보틱스') || stockCode.contains('TROBOTICS') || stockCode.contains('trobotics')) {
        print('🔍 티로보틱스 가격 디버깅:');
        print('  - stockCode: $stockCode');
        print('  - position currentPrice: $currentPrice');
        print('  - finalCurrentPrice: $finalCurrentPrice');
        print('  - position keys: ${position.keys.toList()}');
      }
    } catch (e) {
      print('⚠️ 현재가 조회 실패 ($stockCode): $e');
      finalCurrentPrice = _parseDouble(position['currentPrice']) ?? 0.0;
    }

    final isNasdaq = _isNasdaqStock(stockCode);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 0),
        child: Row(
          children: [
            // 종목 정보
            Expanded(
              flex: 3,
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
                  const SizedBox(height: 4),
                  Text(
                    '${quantity}주',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            // 가격 정보
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    isNasdaq ? '\$${_formatNumber(finalCurrentPrice, decimals: 2)}' : '${_formatNumber(finalCurrentPrice)}원',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '평균 ${isNasdaq ? '\$${_formatNumber(avgPrice, decimals: 2)}' : '${_formatNumber(avgPrice)}원'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            // 손익 정보
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${profit >= 0 ? '+' : ''}${isNasdaq ? '\$${_formatNumber(profit, decimals: 2)}' : '${_formatNumber(profit)}원'}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: profit >= 0 ? Colors.red : Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${profitRate >= 0 ? '+' : ''}${profitRate.toStringAsFixed(2)}%',
                    style: TextStyle(
                      fontSize: 12,
                      color: profit >= 0 ? Colors.red : Colors.blue,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 종목명 해결
  String _resolveDisplayName(String stockCode, Map<String, dynamic> stockData) {
    // 1. stockData에서 종목명 확인 (API 필드명 우선 사용)
    String stockName = stockData['prdt_name'] as String? ?? 
                      stockData['stockName'] as String? ?? '';
    
    // 2. stockData에 종목명이 없으면 AppDataManager에서 조회
    if (stockName.isEmpty) {
      stockName = AppDataManager.instance.getStockName(stockCode);
    }
    
    final market = stockData['market'] as String? ?? '';
    
    // 3. 종목명이 있으면 종목명(종목코드) 형태로 표시
    if (stockName.isNotEmpty && stockName != stockCode) {
      if (_isNasdaqStock(stockCode) || market == 'NASDAQ') {
        return '$stockName ($stockCode)';
      } else if (market == 'KOSPI') {
        return '$stockName ($stockCode)';
      } else if (market == 'KOSDAQ') {
        return '$stockName ($stockCode)';
      }
      return '$stockName ($stockCode)';
    }
    
    // 4. 종목명이 없는 경우 종목코드와 시장 정보만 표시
    if (_isNasdaqStock(stockCode)) {
      return '$stockCode (NASDAQ)';
    } else if (market == 'KOSPI') {
      return '$stockCode (KOSPI)';
    } else if (market == 'KOSDAQ') {
      return '$stockCode (KOSDAQ)';
    }
    
    return stockCode;
  }

  /// 나스닥 종목인지 확인
  bool _isNasdaqStock(String stockCode) {
    // 나스닥 종목 코드 패턴 (예: AAPL, TSLA 등)
    return stockCode.length <= 5 && 
           stockCode == stockCode.toUpperCase() && 
           !RegExp(r'^\d+$').hasMatch(stockCode);
  }

  /// 정수 파싱
  int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  /// 실수 파싱
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
}
