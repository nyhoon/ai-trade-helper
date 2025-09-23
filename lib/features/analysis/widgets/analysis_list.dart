import 'package:flutter/material.dart';

typedef BuildAnalysisCard = Widget Function(dynamic item, Map<String, dynamic>? currentPriceData, Map<String, dynamic>? analysisData, bool isSelected);

class AnalysisListView extends StatelessWidget {
  final List<dynamic> items;
  final ScrollController watchlistScrollController;
  final ScrollController holdingsScrollController;
  final int currentTabIndex;
  final Map<String, dynamic> currentPrices;
  final Map<String, dynamic> analysisResults;
  final Set<String> selectedItems;
  final BuildAnalysisCard buildAnalysisCard;

  const AnalysisListView({
    super.key,
    required this.items,
    required this.watchlistScrollController,
    required this.holdingsScrollController,
    required this.currentTabIndex,
    required this.currentPrices,
    required this.analysisResults,
    required this.selectedItems,
    required this.buildAnalysisCard,
  });

  @override
  Widget build(BuildContext context) {
    final scrollController = currentTabIndex == 0 ? watchlistScrollController : holdingsScrollController;

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final stockCode = item['stock_code'] as String? ?? item['stockCode'] as String? ?? '';
        if (stockCode.isEmpty) return const SizedBox.shrink();

        final currentPriceData = currentPrices[stockCode];
        final analysis = analysisResults[stockCode];
        final isSelected = selectedItems.contains(stockCode);
        // diff 안정성 강화를 위해 stockCode로 고정 키 사용
        final stableKey = stockCode;

        return Container(
          key: ValueKey(stableKey),
          child: buildAnalysisCard(item, currentPriceData, analysis, isSelected),
        );
      },
    );
  }
}


