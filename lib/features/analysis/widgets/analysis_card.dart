import 'package:flutter/material.dart';
import '../../../core/api/kis_unified_api_service.dart';

typedef BuildStockHeader = Widget Function(dynamic item, Map<String, dynamic>? currentPriceData);
typedef BuildHoldingsInfo = Widget Function(Map<String, dynamic> holding, Map<String, dynamic>? analysis);
typedef BuildInvestmentStyleInfo = Widget Function(Map<String, dynamic> analysis);
typedef BuildIntegratedAnalysisSection = Future<Widget> Function(dynamic item, Map<String, dynamic> analysis);
typedef BuildLoadingSection = Widget Function();
typedef BuildNoApiMessage = Widget Function();
typedef BuildAnalysisTimeInfo = Widget Function(Map<String, dynamic> analysis);
typedef BuildSignalTimeInfo = Widget Function(String stockCode, Map<String, dynamic> analysis);
typedef BuildTradeStatusOverlay = Widget Function(String stockCode);
typedef BuildTradingTimeOverlay = Widget Function(String stockCode);

class AnalysisCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final Map<String, dynamic>? currentPriceData;
  final Map<String, dynamic>? analysisData;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback? onSelectionChanged;

  final BuildStockHeader buildStockHeader;
  final BuildHoldingsInfo buildHoldingsInfo;
  final BuildInvestmentStyleInfo buildInvestmentStyleInfo;
  final BuildIntegratedAnalysisSection buildIntegratedAnalysisSection;
  final BuildLoadingSection buildLoadingSection;
  final BuildNoApiMessage buildNoApiMessage;
  final BuildAnalysisTimeInfo buildAnalysisTimeInfo;
  final BuildSignalTimeInfo buildSignalTimeInfo;
  final BuildTradeStatusOverlay buildTradeStatusOverlay;
  final BuildTradingTimeOverlay buildTradingTimeOverlay;

  const AnalysisCard({
    super.key,
    required this.item,
    required this.currentPriceData,
    required this.analysisData,
    required this.isSelected,
    this.isSelectionMode = false,
    this.onSelectionChanged,
    required this.buildStockHeader,
    required this.buildHoldingsInfo,
    required this.buildInvestmentStyleInfo,
    required this.buildIntegratedAnalysisSection,
    required this.buildLoadingSection,
    required this.buildNoApiMessage,
    required this.buildAnalysisTimeInfo,
    required this.buildSignalTimeInfo,
    required this.buildTradeStatusOverlay,
    required this.buildTradingTimeOverlay,
  });

  @override
  Widget build(BuildContext context) {
    final hasApiConfig = KisUnifiedApiService().apiConfig['isValid'] as bool? ?? false;
    final stockCode = item['stock_code'] as String? ?? item['stockCode'] as String? ?? '';
    final hasQuantity = item.containsKey('quantity') || item.containsKey('avgPrice');
    final isHolding = hasQuantity && (item['quantity'] ?? 0) > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected ? const BorderSide(color: Colors.lightBlue, width: 2) : BorderSide.none,
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildStockHeader(item, currentPriceData),
                const SizedBox(height: 12),

                if (isHolding || _isNasdaqStock(stockCode)) buildHoldingsInfo(item, analysisData),
                if (isHolding || _isNasdaqStock(stockCode)) const SizedBox(height: 8),

                if (analysisData != null)
                  FutureBuilder<Widget>(
                    future: buildIntegratedAnalysisSection(item, analysisData!),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) return snapshot.data!;
                      return const SizedBox.shrink();
                    },
                  ),

                if (analysisData != null && (analysisData!['isLoading'] == true || analysisData!['signal'] == '분석 중...'))
                  buildLoadingSection(),
                const SizedBox(height: 8),

                if (!hasApiConfig) buildNoApiMessage(),
              ],
            ),
          ),
          if (isSelected)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.lightBlue.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          buildTradeStatusOverlay(stockCode),
          buildTradingTimeOverlay(stockCode),
          // 체크박스 (선택 모드일 때만 표시)
          if (isSelectionMode)
            Positioned.fill(
              child: Center(
                child: Transform.scale(
                  scale: 1.8,
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (value) {
                      if (onSelectionChanged != null) {
                        onSelectionChanged!();
                      }
                    },
                    activeColor: const Color(0xFF3B5BA9),
                    shape: const CircleBorder(),
                    side: const BorderSide(color: Colors.grey, width: 1.5),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _isNasdaqStock(String symbol) {
    if (symbol.length == 6 && int.tryParse(symbol) != null) {
      return false;
    }
    return true;
  }

}


