import 'package:flutter/material.dart';

class WatchlistTab extends StatelessWidget {
  final bool isLoading;
  final bool isFirstLoading;
  final List<Map<String, dynamic>> watchlistItems;
  final String Function(dynamic style) getStyleName;
  final Future<void> Function() onRefresh;
  final Widget Function() buildEmptyApiGuide;
  final Widget Function(List<dynamic> items) buildAnalysisList;

  const WatchlistTab({
    super.key,
    required this.isLoading,
    required this.isFirstLoading,
    required this.watchlistItems,
    required this.getStyleName,
    required this.onRefresh,
    required this.buildEmptyApiGuide,
    required this.buildAnalysisList,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading || isFirstLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('관심 종목을 분석중입니다...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (watchlistItems.isEmpty) {
      final isNarrow = MediaQuery.of(context).size.width < 600;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_border, size: isNarrow ? 48 : 64, color: Colors.grey),
            SizedBox(height: isNarrow ? 12 : 16),
            Text('조건에 맞는 관심종목이 없습니다', style: TextStyle(fontSize: isNarrow ? 16 : 18, color: Colors.grey)),
            SizedBox(height: isNarrow ? 6 : 8),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isNarrow ? 16 : 24),
              child: Text(
                '${getStyleName.call(null)} 투자 스타일에 맞는 종목만 표시됩니다',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: isNarrow ? 12 : 14, color: Colors.grey),
              ),
            ),
            SizedBox(height: isNarrow ? 6 : 8),
            const Text('우측 상단 새로고침을 눌러 재분석할 수 있어요', style: TextStyle(color: Colors.grey)),
            SizedBox(height: isNarrow ? 12 : 16),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: isNarrow ? 24 : 32),
              child: ElevatedButton.icon(
                onPressed: () async => onRefresh(),
                icon: const Icon(Icons.refresh),
                label: const Text('새로고침'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: isNarrow ? 24 : 32, vertical: isNarrow ? 12 : 16),
                  minimumSize: Size(double.infinity, isNarrow ? 40 : 48),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: buildAnalysisList(watchlistItems),
    );
  }
}


