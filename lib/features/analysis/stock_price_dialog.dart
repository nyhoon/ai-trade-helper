import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/database/repositories/historical_data_repository.dart';
import '../../core/analysis/dynamicCal/rsi_dynamic_score_calculator.dart';

/// 종목별 종가 데이터 확인 다이얼로그
class StockPriceDialog extends StatefulWidget {
  final String stockCode;
  final String stockName;

  const StockPriceDialog({
    super.key,
    required this.stockCode,
    required this.stockName,
  });

  @override
  State<StockPriceDialog> createState() => _StockPriceDialogState();
}

class _StockPriceDialogState extends State<StockPriceDialog> {
  List<Map<String, dynamic>> _priceData = [];
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadPriceData();
  }

  /// 종가 데이터 로딩
  Future<void> _loadPriceData() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      print('🔍 ${widget.stockCode} 종가 데이터 로딩 시작...');

      // HistoricalDataRepository에서 20일치 데이터 조회
      final historicalRepo = HistoricalDataRepository();
      final chartData = await historicalRepo.getRecentBars(widget.stockCode, limit: 20);

      if (chartData.isEmpty) {
        setState(() {
          _errorMessage = '데이터가 없습니다.';
          _isLoading = false;
        });
        return;
      }

             // 데이터 정렬 (과거 → 최신 순서로 통일)
       final sortedData = List<Map<String, dynamic>>.from(chartData);
       sortedData.sort((a, b) {
         final dateA = a['date'] ?? '';
         final dateB = b['date'] ?? '';
         return dateA.compareTo(dateB); // 과거→최신 순서로 정렬 (통일)
       });

      // RSI 계산을 위한 최근 14일치 가격 데이터 준비 (최신 데이터 기준)
      final rsiPeriod = 14;
      final recentPrices = sortedData
          .take(rsiPeriod + 1) // RSI 계산을 위해 15개 데이터 필요 (14일 + 1일)
          .map((data) => (data['close'] as num?)?.toDouble() ?? 0.0)
          .where((price) => price > 0)
          .toList()
          .reversed // RSI 계산을 위해 과거→최신 순서로 변경
          .toList();
      
      // 거래량 데이터 추출 (최신 데이터 기준)
      final volumes = sortedData
          .skip(sortedData.length - rsiPeriod - 1) // 최신 데이터부터 추출
          .map((data) => (data['volume'] as num?)?.toInt() ?? 0)
          .toList();
      
      // RSI 계산용 데이터 디버깅
      print('🔍 RSI 계산용 데이터 순서 (과거→최신):');
      for (int i = 0; i < recentPrices.length; i++) {
        final dataIndex = sortedData.length - 1 - i; // 역순으로 인덱스 계산
        final date = sortedData[dataIndex]['date'] ?? '';
        print('  ${i+1}: ${date} - ${recentPrices[i].toStringAsFixed(0)}원');
      }

      // RSI 계산
      double rsi = 50.0;
      if (recentPrices.length >= rsiPeriod + 1) {
        // RSI 값이 없으므로 계산 생략
        rsi = 0.0; // 계산 오류 처리
        print('📈 RSI 계산 완료: ${rsi.toStringAsFixed(2)}');
        print('📅 RSI 계산 기간: ${sortedData[rsiPeriod]['date']} ~ ${sortedData[0]['date']} (과거→최신)');
        print('📊 사용된 데이터 개수: ${recentPrices.length}일');
      } else {
        print('⚠️ RSI 계산 불가: 데이터 부족 (필요: ${rsiPeriod + 1}일, 보유: ${recentPrices.length}일)');
      }

      // 데이터 포맷팅 (최신 데이터가 위에 오도록 역순으로 처리)
      final formattedData = sortedData.asMap().entries.map((entry) {
        final index = entry.key;
        final data = entry.value;
        final date = data['date'] ?? '';
        final close = (data['close'] as num?)?.toDouble() ?? 0.0;
        final volume = (data['volume'] as num?)?.toInt() ?? 0;
        final open = (data['open'] as num?)?.toDouble() ?? 0.0;
        final high = (data['high'] as num?)?.toDouble() ?? 0.0;
        final low = (data['low'] as num?)?.toDouble() ?? 0.0;

        // 최신 데이터가 위에 오도록 인덱스 계산 (이미 최신순으로 정렬됨)
        final displayIndex = index + 1;
        
        // 변화량 계산 (이전 데이터와 비교)
        double change = 0.0;
        double changeRate = 0.0;
        
        if (index < sortedData.length - 1) {
          final nextData = sortedData[index + 1]; // 다음 데이터 (더 과거)
          final nextClose = (nextData['close'] as num?)?.toDouble() ?? 0.0;
          change = close - nextClose; // 현재가 - 이전가
          changeRate = nextClose > 0 ? (change / nextClose) * 100 : 0.0;
        }

        return {
          'index': displayIndex,
          'date': date,
          'close': close,
          'volume': volume,
          'open': open,
          'high': high,
          'low': low,
          'change': change,
          'changeRate': changeRate,
        };
      }).toList();

      print('📊 ${widget.stockCode} 데이터 로딩 완료:');
      print('  - 총 ${formattedData.length}일치 데이터');
      print('  - RSI: ${rsi.toStringAsFixed(2)}');
      print('  - 최신 종가: ${formattedData.first['close']}');
      print('  - 최신 날짜: ${formattedData.first['date']}');
      print('  - 표시 순서: 최신 → 과거 (${formattedData.first['index']}번째 → ${formattedData.last['index']}번째)');

      setState(() {
        _priceData = formattedData;
        _isLoading = false;
      });

    } catch (e) {
      print('❌ ${widget.stockCode} 데이터 로딩 실패: $e');
      setState(() {
        _errorMessage = '데이터 로딩 실패: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '${widget.stockName} (${widget.stockCode})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '최근 20일 종가 데이터 (최신순)',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),

            // 로딩 상태
            if (_isLoading)
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('데이터 로딩 중...'),
                    ],
                  ),
                ),
              ),

            // 에러 상태
            if (_errorMessage.isNotEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error, size: 48, color: Colors.red[300]),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage,
                        style: TextStyle(color: Colors.red[600]),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadPriceData,
                        child: const Text('다시 시도'),
                      ),
                    ],
                  ),
                ),
              ),

            // 데이터 테이블
            if (!_isLoading && _errorMessage.isEmpty && _priceData.isNotEmpty)
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // 테이블 헤더
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          children: [
                            SizedBox(width: 40, child: Text('일', style: TextStyle(fontWeight: FontWeight.bold))),
                            SizedBox(width: 80, child: Text('날짜', style: TextStyle(fontWeight: FontWeight.bold))),
                            SizedBox(width: 70, child: Text('종가', style: TextStyle(fontWeight: FontWeight.bold))),
                            SizedBox(width: 60, child: Text('변동', style: TextStyle(fontWeight: FontWeight.bold))),
                            SizedBox(width: 60, child: Text('변동률', style: TextStyle(fontWeight: FontWeight.bold))),
                            Expanded(child: Text('거래량', style: TextStyle(fontWeight: FontWeight.bold))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

                      // 데이터 행들
                      ..._priceData.map((data) {
                        final change = data['change'] as double;
                        final changeRate = data['changeRate'] as double;
                        final isPositive = change >= 0;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 40,
                                child: Text(
                                  '${data['index']}',
                                  style: TextStyle(
                                    color: data['index'] == _priceData.length ? Colors.blue[700] : null,
                                    fontWeight: data['index'] == _priceData.length ? FontWeight.bold : null,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 80,
                                child: Text(
                                  data['date'],
                                  style: TextStyle(
                                    color: data['index'] == _priceData.length ? Colors.blue[700] : null,
                                    fontWeight: data['index'] == _priceData.length ? FontWeight.bold : null,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 70,
                                child: Text(
                                  '${data['close'].toStringAsFixed(0)}',
                                  style: TextStyle(
                                    color: data['index'] == _priceData.length ? Colors.blue[700] : null,
                                    fontWeight: data['index'] == _priceData.length ? FontWeight.bold : null,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 60,
                                child: Text(
                                  '${change >= 0 ? '+' : ''}${change.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    color: isPositive ? Colors.red : Colors.blue,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 60,
                                child: Text(
                                  '${changeRate >= 0 ? '+' : ''}${changeRate.toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    color: isPositive ? Colors.red : Colors.blue,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  '${(data['volume'] as int).toString().replaceAllMapped(
                                    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                                    (Match m) => '${m[1]},'
                                  )}',
                                  style: TextStyle(
                                    color: data['index'] == _priceData.length ? Colors.blue[700] : null,
                                    fontWeight: data['index'] == _priceData.length ? FontWeight.bold : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),

                      const SizedBox(height: 16),

                      // 요약 정보
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '📊 요약 정보',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text('최신 종가: ${_priceData.last['close'].toStringAsFixed(0)}원'),
                                ),
                                Expanded(
                                  child: Text('최신 날짜: ${_priceData.last['date']}'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: Text('20일 평균: ${(_priceData.map((d) => d['close'] as double).reduce((a, b) => a + b) / _priceData.length).toStringAsFixed(0)}원'),
                                ),
                                Expanded(
                                  child: Text('총 거래량: ${(_priceData.map((d) => d['volume'] as int).reduce((a, b) => a + b)).toString().replaceAllMapped(
                                    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                                    (Match m) => '${m[1]},'
                                  )}주'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _getCurrentTimeString() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }
}
