import 'package:flutter/material.dart';
import '../../../core/trading/investment_style.dart';
import '../../../core/utils/formatters.dart';

typedef GetStyleName = String Function(InvestmentStyle style);
typedef GetStyleIcon = IconData Function(InvestmentStyle style);
typedef GetStyleColor = Color Function(InvestmentStyle style);
typedef IsNasdaqStock = bool Function(String stockCode);
typedef GetDisplayName = String Function(Map<String, dynamic> item);
typedef FormatPriceWithChange = String Function(double currentPrice, double previousPrice, bool isNasdaq);
typedef FormatPriceForDisplay = String Function(num price, bool isNasdaq, {bool showSign});
typedef FormatIndicatorValue = String Function(dynamic value, String type);

class AnalysisDataTableTab extends StatelessWidget {
  final bool isLoading;
  final ScrollController analysisScrollController;
  final List<dynamic> watchlistItems;
  final List<dynamic> holdingsItems;
  final Map<String, dynamic> analysisResults;
  final InvestmentStyle currentStyle;
  final GetStyleName getStyleName;
  final GetStyleIcon getStyleIcon;
  final GetStyleColor getStyleColor;
  final IsNasdaqStock isNasdaqStock;
  final GetDisplayName getDisplayName;
  final FormatPriceWithChange formatPriceWithChange;
  final FormatPriceForDisplay formatPriceForDisplay;
  final FormatIndicatorValue formatIndicatorValue;

  const AnalysisDataTableTab({
    super.key,
    required this.isLoading,
    required this.analysisScrollController,
    required this.watchlistItems,
    required this.holdingsItems,
    required this.analysisResults,
    required this.currentStyle,
    required this.getStyleName,
    required this.getStyleIcon,
    required this.getStyleColor,
    required this.isNasdaqStock,
    required this.getDisplayName,
    required this.formatPriceWithChange,
    required this.formatPriceForDisplay,
    required this.formatIndicatorValue,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      controller: analysisScrollController,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInvestmentStyleInfoCard(),
          const SizedBox(height: 16),
          _buildAnalysisFlowDiagram(),
          const SizedBox(height: 24),
          _buildWatchlistDataTable(),
          const SizedBox(height: 24),
          _buildHoldingsDataTable(),
          const SizedBox(height: 24),
          _buildTechnicalIndicatorsFormulas(),
          const SizedBox(height: 24),
          _buildInvestmentStyleConditions(),
        ],
      ),
    );
  }

  Widget _buildAnalysisFlowDiagram() {
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
                Icon(Icons.account_tree, color: Colors.indigo, size: 20),
                const SizedBox(width: 8),
                Text(
                  '분석 프로세스 흐름도',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                children: [
                  _buildFlowStepWithArrow(
                    '1. 데이터 수집',
                    'KIS API에서 일봉 데이터 조회\n• 종가, 고가, 저가, 거래량\n• 최소 14일 이상의 데이터',
                    Icons.cloud_download,
                    Colors.blue,
                    hasArrow: true,
                  ),
                  _buildFlowStepWithArrow(
                    '2. 기술적 지표 계산',
                    'RSI, MACD, 볼린저밴드, 이동평균\n• 각 지표별 표준 공식 적용\n• 투자스타일별 임계값 설정',
                    Icons.functions,
                    Colors.green,
                    hasArrow: true,
                  ),
                  _buildFlowStepWithArrow(
                    '3. 투자스타일 적용',
                    '${getStyleName(currentStyle)}\n• RSI 매수/매도 기준 적용\n• 신뢰도 및 목표가 계산',
                    getStyleIcon(currentStyle),
                    getStyleColor(currentStyle),
                    hasArrow: true,
                  ),
                  _buildFlowStepWithArrow(
                    '4. 시그널 생성',
                    '매수/매도/관망 판단\n• 조건 만족 개수 확인\n• 최종 신뢰도 계산',
                    Icons.trending_up,
                    Colors.orange,
                    hasArrow: true,
                  ),
                  _buildFlowStepWithArrow(
                    '5. 결과 표시',
                    'UI에 분석 결과 표시\n• 실시간 업데이트 (30초)\n• 데이터 테이블 정리',
                    Icons.table_chart,
                    Colors.purple,
                    hasArrow: false,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: getStyleColor(currentStyle).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: getStyleColor(currentStyle).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(getStyleIcon(currentStyle), color: getStyleColor(currentStyle), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '현재 적용 중: ${getStyleName(currentStyle)}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: getStyleColor(currentStyle),
                          ),
                        ),
                        Text(
                          _getStyleDescription(currentStyle),
                          style: TextStyle(
                            fontSize: 12,
                            color: getStyleColor(currentStyle).withOpacity(0.8),
                          ),
                        ),
                      ],
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

  Widget _buildFlowStepWithArrow(String title, String description, IconData icon, Color color, {required bool hasArrow}) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (hasArrow) ...[
          const SizedBox(height: 8),
          Icon(Icons.keyboard_arrow_down, color: Colors.grey, size: 24),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildInvestmentStyleInfoCard() {
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
                Icon(getStyleIcon(currentStyle), color: getStyleColor(currentStyle), size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '현재 투자스타일 - ${getStyleName(currentStyle)}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: getStyleColor(currentStyle),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _getStyleDescription(currentStyle),
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  String _getStyleDescription(InvestmentStyle style) {
    switch (style) {
      case InvestmentStyle.conservative:
        return '안전한 투자로 리스크를 최소화하는 전략. RSI 30 이하에서 매수, 70 이상에서 매도.';
      case InvestmentStyle.moderate:
        return '균형잡힌 투자로 안정성과 수익성을 모두 고려하는 전략. RSI 35 이하에서 매수, 65 이상에서 매도.';
      case InvestmentStyle.aggressive:
        return '적극적인 투자로 높은 수익을 추구하는 전략. RSI 40 이하에서 매수, 60 이상에서 매도.';
    }
  }

  Widget _buildWatchlistDataTable() {
    if (watchlistItems.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('관심종목이 없습니다.', style: TextStyle(fontSize: 16)),
        ),
      );
    }

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
                Icon(Icons.favorite, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Text(
                  '관심종목 데이터 테이블',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 20,
                columns: const [
                  DataColumn(label: Text('종목명', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('종목코드', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('현재가', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('전일가', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('RSI', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('MACD', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('볼린저(중간)', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('SMA20', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('거래량(배)', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('VWAP', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('ADX', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('시그널', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('신뢰도', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('목표가', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: watchlistItems.map((item) {
                  final stockCode = item['stock_code'] as String? ?? '';
                  final analysis = analysisResults[stockCode] as Map<String, dynamic>?;
                  final technicalRaw = analysis?['technicalData'];
                  final technical = technicalRaw is Map ? technicalRaw as Map : <String, dynamic>{};
                  final indicators = <String, dynamic>{
                    'rsi': technical['rsi'],
                    'macd': technical['macd'],
                    'bollinger': technical['bbMiddle'],
                    'sma20': technical['ma20'],
                    'volume': (() {
                      final cv = (technical['currentVolume'] ?? 0).toDouble();
                      final av = (technical['avgVolume'] ?? 1).toDouble();
                      if (av == 0) return 0.0;
                      return cv / av;
                    })(),
                    'vwap': technical['vwap'],
                    'adx': technical['adx'],
                  };
                  final isNasdaq = isNasdaqStock(stockCode);

                  return DataRow(
                    cells: [
                      DataCell(Text(getDisplayName(item))),
                      DataCell(Text(stockCode)),
                      DataCell(Text(formatPriceWithChange((analysis?['currentPrice'] ?? 0.0).toDouble(), (analysis?['openPrice'] ?? 0.0).toDouble(), isNasdaq))),
                      DataCell(Text(formatPriceForDisplay((technical['previousPrice'] ?? 0.0).toDouble(), isNasdaq))),
                      DataCell(Text('${_formatIndicatorValue(indicators['rsi'], 'RSI')}')),
                      DataCell(Text('${_formatMACDValue(indicators['macd'])}')),
                      DataCell(Text('${_formatBollingerValue(indicators['bollinger'])}')),
                      DataCell(Text('${_formatIndicatorValue(indicators['sma20'], '이동평균선')}')),
                      DataCell(Text('${_formatIndicatorValue(indicators['volume'], '거래량')}')),
                      DataCell(Text('${_formatIndicatorValue(indicators['vwap'], 'VWAP')}')),
                      DataCell(Text('${_formatIndicatorValue(indicators['adx'], 'ADX')}')),
                      DataCell(Text(analysis?['signal'] ?? '관망')),
                      DataCell(Text('${(((analysis?['confidence'] ?? 0.0) <= 1.0 ? (analysis?['confidence'] ?? 0.0) * 100 : (analysis?['confidence'] ?? 0.0)) as num).toStringAsFixed(0)}%')),
                      DataCell(Text(isNasdaq ? '\$${((analysis?['targetPrice'] ?? 0.0) as num).toStringAsFixed(2)}' : Formatters.formatPrice(analysis?['targetPrice'] ?? 0.0))),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHoldingsDataTable() {
    if (holdingsItems.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('보유종목이 없습니다.', style: TextStyle(fontSize: 16)),
        ),
      );
    }

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
                Icon(Icons.account_balance_wallet, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Text(
                  '보유종목 데이터 테이블',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 20,
                columns: const [
                  DataColumn(label: Text('종목명', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('종목코드', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('현재가(등락률)', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('평균단가', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('보유수량', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('손익', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('손익률', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('RSI', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('MACD', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('볼린저(중간)', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('SMA20', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('거래량(배)', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('VWAP', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('ADX', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('시그널', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('신뢰도', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('목표가', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: holdingsItems.map((item) {
                  final stockCode = (item['stockCode'] as String?) ?? '';
                  final analysis = analysisResults[stockCode] as Map<String, dynamic>?;
                  final technicalRaw = analysis?['technicalData'];
                  final technical = technicalRaw is Map ? technicalRaw as Map : <String, dynamic>{};
                  final indicators = <String, dynamic>{
                    'rsi': technical['rsi'],
                    'macd': technical['macd'],
                    'bollinger': technical['bbMiddle'],
                    'sma20': technical['ma20'],
                    'volume': (() {
                      final cv = (technical['currentVolume'] ?? 0).toDouble();
                      final av = (technical['avgVolume'] ?? 1).toDouble();
                      if (av == 0) return 0.0;
                      return cv / av;
                    })(),
                    'vwap': technical['vwap'],
                    'adx': technical['adx'],
                  };
                  final profit = (item['profit'] ?? 0.0).toDouble();
                  final profitRate = (item['profitRate'] ?? 0.0).toDouble();
                  final isNasdaq = isNasdaqStock(stockCode);

                  return DataRow(
                    cells: [
                      DataCell(Text(getDisplayName(item.cast<String, dynamic>()))),
                      DataCell(Text(stockCode)),
                      DataCell(Text(formatPriceWithChange((analysis?['currentPrice'] ?? 0.0).toDouble(), (analysis?['openPrice'] ?? 0.0).toDouble(), isNasdaq))),
                      DataCell(Text(formatPriceForDisplay((technical['previousPrice'] ?? 0.0).toDouble(), isNasdaq))),
                      DataCell(Text('${item['quantity'] ?? 0}')),
                      DataCell(Text(
                        formatPriceForDisplay(profit, isNasdaq, showSign: true),
                        style: TextStyle(color: profit >= 0 ? Colors.red : Colors.blue),
                      )),
                      DataCell(Text(
                        '${profitRate >= 0 ? '+' : ''}${profitRate.toStringAsFixed(2)}%',
                        style: TextStyle(color: profitRate >= 0 ? Colors.red : Colors.blue),
                      )),
                      DataCell(Text('${_formatIndicatorValue(indicators['rsi'], 'RSI')}')),
                      DataCell(Text('${_formatMACDValue(indicators['macd'])}')),
                      DataCell(Text('${_formatBollingerValue(indicators['bollinger'])}')),
                      DataCell(Text('${_formatIndicatorValue(indicators['sma20'], '이동평균선')}')),
                      DataCell(Text('${_formatIndicatorValue(indicators['volume'], '거래량')}')),
                      DataCell(Text('${_formatIndicatorValue(indicators['vwap'], 'VWAP')}')),
                      DataCell(Text('${_formatIndicatorValue(indicators['adx'], 'ADX')}')),
                      DataCell(Text(analysis?['signal'] ?? '관망')),
                      DataCell(Text('${(((analysis?['confidence'] ?? 0.0) <= 1.0 ? (analysis?['confidence'] ?? 0.0) * 100 : (analysis?['confidence'] ?? 0.0)) as num).toStringAsFixed(0)}%')),
                      DataCell(Text(formatPriceForDisplay(analysis?['targetPrice'] ?? 0.0, isNasdaq))),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTechnicalIndicatorsFormulas() {
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
                Icon(Icons.functions, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Text(
                  '기술적 지표 계산 공식',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildIndicatorFormula(
              'RSI (Relative Strength Index)',
              'RSI = 100 - (100 / (1 + RS))\nRS = 평균 상승폭 / 평균 하락폭\n• Wilder\'s smoothing 사용\n• 기간: 14일\n• 과매도: 30 이하, 과매수: 70 이상',
              Colors.orange,
            ),
            const SizedBox(height: 12),
            _buildIndicatorFormula(
              'MACD (Moving Average Convergence Divergence)',
              'MACD = EMA(12) - EMA(26)\nSignal = EMA(MACD, 9)\nHistogram = MACD - Signal\n• 매수: MACD > Signal\n• 매도: MACD < Signal',
              Colors.blue,
            ),
            const SizedBox(height: 12),
            _buildIndicatorFormula(
              '볼린저 밴드 (Bollinger Bands)',
              '중간선 = SMA(20)\n상단선 = 중간선 + (2 × 표준편차)\n하단선 = 중간선 - (2 × 표준편차)\n• 기간: 20일, 표준편차: 2',
              Colors.purple,
            ),
            const SizedBox(height: 12),
            _buildIndicatorFormula(
              '이동평균 (Simple Moving Average)',
              'SMA = (P1 + P2 + ... + Pn) / n\n• 단순이동평균 사용\n• 기간: 20일',
              Colors.green,
            ),
            const SizedBox(height: 12),
            _buildIndicatorFormula(
              '거래량 지표 (시간대별 동적 임계값)',
              '거래량 비율 = 현재 거래량 / 20일 평균 거래량\n• KOSPI/KOSDAQ: 09:00-15:30\n• NASDAQ: 22:30-05:00\n• 시간대별 동적 임계값 적용\n• 거래 시간 외: 0% 신뢰도',
              Colors.red,
            ),
            const SizedBox(height: 12),
            _buildIndicatorFormula(
              'VWAP (Volume Weighted Average Price)',
              'VWAP = Σ(가격 × 거래량) / Σ(거래량)\n• 거래량 가중 평균가격\n• 현재가 대비 위치로 매매 신호 판단\n• 상단 돌파: 매도 신호\n• 하단 터치: 매수 신호',
              Colors.teal,
            ),
            const SizedBox(height: 12),
            _buildIndicatorFormula(
              'ADX (Average Directional Index)',
              'ADX = 평균 방향성 지수\n• 추세 강도 측정\n• ADX ≥ 25: 강한 추세\n• ADX < 25: 약한 추세\n• 추세 방향에 따른 매매 신호',
              Colors.indigo,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIndicatorFormula(String title, String formula, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            formula,
            style: const TextStyle(
              fontSize: 14,
              fontFamily: 'monospace',
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvestmentStyleConditions() {
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
                  '투자스타일별 상세 조건',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildStyleConditionCard(
              InvestmentStyle.conservative,
              '안정적 투자',
              '리스크를 최소화하는 보수적 전략',
              Colors.green,
              const {
                'RSI 매수': '30 이하',
                'RSI 매도': '70 이상',
                'MACD 매수': 'MACD > Signal',
                'MACD 매도': 'MACD < Signal',
                '볼린저밴드 매수': '하단선 근처',
                '볼린저밴드 매도': '상단선 근처',
                '거래량 조건': '1.2배 이상',
                '모멘텀 조건': '양수',
                '신뢰도 기준': '70% 이상',
              },
            ),
            const SizedBox(height: 12),
            _buildStyleConditionCard(
              InvestmentStyle.moderate,
              '일반적 투자',
              '안정성과 수익성을 균형있게 고려',
              Color(0xFF3B5BA9),
              const {
                'RSI 매수': '35 이하',
                'RSI 매도': '65 이상',
                'MACD 매수': 'MACD > Signal',
                'MACD 매도': 'MACD < Signal',
                '볼린저밴드 매수': '하단선 근처',
                '볼린저밴드 매도': '상단선 근처',
                '거래량 조건': '1.0배 이상',
                '모멘텀 조건': '양수',
                '신뢰도 기준': '60% 이상',
              },
            ),
            const SizedBox(height: 12),
            _buildStyleConditionCard(
              InvestmentStyle.aggressive,
              '공격적 투자',
              '높은 수익을 추구하는 적극적 전략',
              Colors.red,
              const {
                'RSI 매수': '40 이하',
                'RSI 매도': '60 이상',
                'MACD 매수': 'MACD > Signal',
                'MACD 매도': 'MACD < Signal',
                '볼린저밴드 매수': '중간선 근처',
                '볼린저밴드 매도': '상단선 근처',
                '거래량 조건': '0.8배 이상',
                '모멘텀 조건': '양수 또는 음수',
                '신뢰도 기준': '50% 이상',
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStyleConditionCard(
    InvestmentStyle style,
    String title,
    String description,
    Color color,
    Map<String, String> conditions,
  ) {
    final isCurrentStyle = style == currentStyle;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCurrentStyle ? color.withOpacity(0.2) : color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCurrentStyle ? color : color.withOpacity(0.3),
          width: isCurrentStyle ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(getStyleIcon(style), color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              if (isCurrentStyle) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '현재',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          ...conditions.entries.map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Text(
                      '• ${entry.key}:',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      entry.value,
                      style: TextStyle(
                        fontSize: 12,
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  String _formatMACDValue(dynamic macdValue) {
    if (macdValue == null) return 'N/A';
    if (macdValue is Map<String, dynamic>) {
      final macd = macdValue['macd'] ?? 0.0;
      if (macd is num) return macd.toStringAsFixed(2);
      return 'N/A';
    } else if (macdValue is num) {
      return macdValue.toStringAsFixed(2);
    }
    return 'N/A';
  }

  String _formatBollingerValue(dynamic bollingerValue) {
    if (bollingerValue == null) return 'N/A';
    if (bollingerValue is Map<String, dynamic>) {
      final middle = bollingerValue['middle'] ?? bollingerValue['bbMiddle'] ?? 0.0;
      if (middle is num) return middle.toStringAsFixed(0);
      return 'N/A';
    } else if (bollingerValue is num) {
      return bollingerValue.toStringAsFixed(0);
    }
    return 'N/A';
  }

  String _formatIndicatorValue(dynamic value, String type) {
    return formatIndicatorValue(value, type);
  }
}


