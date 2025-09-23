import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/data/app_data_manager.dart';
import '../utils/account_utils.dart';

/// 계좌 자산 분포를 원형 차트로 표시하는 위젯
class AccountPieChartWidget extends StatelessWidget {
  final Map<String, dynamic>? accountData;

  const AccountPieChartWidget({
    super.key,
    required this.accountData,
  });

  // 원형 차트 색상 팔레트 (5개 기본 색상)
  static const List<Color> _chartColors = [
    Color(0xFF4A90E2), // 파란색
    Color(0xFF50C878), // 초록색
    Color(0xFFFFD700), // 노란색
    Color(0xFFFF6B6B), // 빨간색
    Color(0xFF9B59B6), // 보라색
  ];

  // 추가 색상들 (5개 이상일 때 사용)
  static const List<Color> _additionalColors = [
    Color(0xFFE67E22), // 주황색
    Color(0xFF1ABC9C), // 청록색
    Color(0xFF34495E), // 회색
    Color(0xFFE74C3C), // 진한 빨간색
    Color(0xFF2ECC71), // 진한 초록색
    Color(0xFFF39C12), // 주황색
    Color(0xFF8E44AD), // 진한 보라색
    Color(0xFF16A085), // 진한 청록색
    Color(0xFFD35400), // 진한 주황색
    Color(0xFFC0392B), // 진한 빨간색
  ];

  @override
  Widget build(BuildContext context) {
    if (accountData == null) return const SizedBox.shrink();
    
    final domesticHoldings = accountData!['domesticHoldings'] as List<dynamic>? ?? [];
    final overseasHoldings = accountData!['overseasHoldings'] as List<dynamic>? ?? [];
    final allHoldings = [...domesticHoldings, ...overseasHoldings];
    
    if (allHoldings.isEmpty) {
      return _buildEmptyChart();
    }
    
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
                  '자산 분포',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            Text(
              '${allHoldings.length}개 종목',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
              ],
            ),
            const SizedBox(height: 16),
            // 원형 차트와 범례를 포함하는 컨테이너
            Container(
              height: 160,
              child: Row(
                children: [
                  // 원형 차트
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: SizedBox(
                      width: 120,
                      height: 120,
                      child: PieChart(
                        PieChartData(
                          sections: _generatePieChartData(chartSize: 120),
                          centerSpaceRadius: 30,
                          sectionsSpace: 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 32),
                  // 범례
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12, right: 8),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _generateLegendItems(),
                        ),
                      ),
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

  Widget _buildEmptyChart() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.pie_chart_outline,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                '보유 종목이 없습니다.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 원형 차트 데이터 생성
  List<PieChartSectionData> _generatePieChartData({double? chartSize}) {
    if (accountData == null) return [];
    
    final domesticHoldings = accountData!['domesticHoldings'] as List<dynamic>? ?? [];
    final overseasHoldings = accountData!['overseasHoldings'] as List<dynamic>? ?? [];
    final allHoldings = [...domesticHoldings, ...overseasHoldings];
    if (allHoldings.isEmpty) return [];
    
    // 총 자산 계산 (나스닥 종목은 원화로 변환)
    double totalAssets = 0;
    for (final holding in allHoldings) {
      final holdingMap = holding as Map<String, dynamic>;
      final stockCode = holdingMap['stockCode'] as String? ?? '';
      final totalValue = (holdingMap['totalValue'] as num?)?.toDouble() ?? 0.0;
      
      // 나스닥 종목은 원화로 변환
      if (AccountUtils.isNasdaqStock(stockCode)) {
        totalAssets += totalValue * 1400; // 달러를 원화로 변환
      } else {
        totalAssets += totalValue;
      }
    }
    
    // 보유 종목별 데이터 생성
    final List<PieChartSectionData> sections = [];
    final List<Color> allColors = [..._chartColors, ..._additionalColors];
    
    // 동적 radius 계산
    final radius = chartSize != null ? (chartSize * 0.4) : 50.0;
    final fontSize = chartSize != null ? (chartSize * 0.06).clamp(8.0, 14.0) : 11.0;
    
    for (int i = 0; i < allHoldings.length; i++) {
      final holding = allHoldings[i] as Map<String, dynamic>;
      final stockCode = holding['stockCode'] as String? ?? '';
      final totalValue = (holding['totalValue'] as num?)?.toDouble() ?? 0.0;
      
      // 나스닥 종목은 원화로 변환하여 비율 계산
      double convertedValue = totalValue;
      if (_isNasdaqStock(stockCode)) {
        convertedValue = totalValue * 1400; // 달러를 원화로 변환
      }
      
      final percentage = totalAssets > 0 ? (convertedValue / totalAssets) * 100 : 0;
      final stockName = _getDisplayName(stockCode, holding);
      
      // 색상 선택
      final color = allColors[i % allColors.length];
      
      sections.add(
        PieChartSectionData(
          color: color,
          value: convertedValue,
          title: '${percentage.toStringAsFixed(1)}%',
          radius: radius,
          titleStyle: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      );
    }
    
    return sections;
  }

  /// 원형 차트 범례 데이터 생성
  List<Widget> _generateLegendItems() {
    if (accountData == null) return [];
    
    final domesticHoldings = accountData!['domesticHoldings'] as List<dynamic>? ?? [];
    final overseasHoldings = accountData!['overseasHoldings'] as List<dynamic>? ?? [];
    final allHoldings = [...domesticHoldings, ...overseasHoldings];
    if (allHoldings.isEmpty) return [];
    
    final List<Widget> legendItems = [];
    final List<Color> allColors = [..._chartColors, ..._additionalColors];
    
    for (int i = 0; i < allHoldings.length; i++) {
      final holding = allHoldings[i] as Map<String, dynamic>;
      final stockCode = holding['stockCode'] as String? ?? '';
      final stockName = _getDisplayName(stockCode, holding);
      final totalValue = (holding['totalValue'] as num?)?.toDouble() ?? 0.0;
      final profitRate = (holding['profitRate'] as num?)?.toDouble() ?? 0.0;
      final color = allColors[i % allColors.length];
      
      // 총 자산 대비 비율 계산 (나스닥 종목은 원화로 변환)
      double totalAssets = 0;
      for (final h in allHoldings) {
        final hMap = h as Map<String, dynamic>;
        final hStockCode = hMap['stockCode'] as String? ?? '';
        final hTotalValue = (hMap['totalValue'] as num?)?.toDouble() ?? 0.0;
        
        if (_isNasdaqStock(hStockCode)) {
          totalAssets += hTotalValue * 1400;
        } else {
          totalAssets += hTotalValue;
        }
      }
      
      // 현재 종목의 변환된 가치 계산
      double convertedValue = totalValue;
      if (_isNasdaqStock(stockCode)) {
        convertedValue = totalValue * 1400;
      }
      
      final percentage = totalAssets > 0 ? (convertedValue / totalAssets) * 100 : 0;
      
      legendItems.add(
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stockName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '${percentage.toStringAsFixed(1)}% • ${_formatAssetValue(totalValue, stockCode)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${profitRate >= 0 ? '+' : ''}${profitRate.toStringAsFixed(2)}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: profitRate >= 0 ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    return legendItems;
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

  /// 자산 가치 포맷팅 (달러는 원화로 변환)
  String _formatAssetValue(double value, String stockCode) {
    final isNasdaq = _isNasdaqStock(stockCode);
    if (isNasdaq) {
      final krwValue = value * 1400;
      return '${_formatNumber(krwValue)}원';
    } else {
      return '${_formatNumber(value)}원';
    }
  }

  /// 숫자를 천 단위 구분으로 포맷팅
  String _formatNumber(dynamic number) {
    return Formatters.formatNumber(number);
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
