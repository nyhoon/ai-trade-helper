import 'package:flutter/material.dart';

class HoldingsTab extends StatelessWidget {
  final bool isLoading;
  final bool isFirstLoading;
  final bool hasApiConfig;
  final List<Map<String, dynamic>> holdingsItems;
  final Future<void> Function() onApiReconnect;
  final Future<void> Function() onRefresh;
  final Widget Function(List<dynamic> items) buildAnalysisList;

  const HoldingsTab({
    super.key,
    required this.isLoading,
    required this.isFirstLoading,
    required this.hasApiConfig,
    required this.holdingsItems,
    required this.onApiReconnect,
    required this.onRefresh,
    required this.buildAnalysisList,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading || isFirstLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!hasApiConfig) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_wallet_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('API 설정이 필요합니다', style: TextStyle(fontSize: 18, color: Colors.grey)),
            const SizedBox(height: 8),
            const Text('설정 화면에서 API 키를 등록하면\n보유종목을 확인할 수 있습니다.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: ElevatedButton.icon(
                onPressed: () async => onApiReconnect(),
                icon: const Icon(Icons.refresh),
                label: const Text('API 재연결'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0), minimumSize: const Size(double.infinity, 48.0)),
              ),
            ),
          ],
        ),
      );
    }

    if (holdingsItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_wallet_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('조건에 맞는 보유종목이 없습니다', style: TextStyle(fontSize: 18, color: Colors.grey)),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: ElevatedButton.icon(
                onPressed: () async => onRefresh(),
                icon: const Icon(Icons.refresh),
                label: const Text('새로고침'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0), minimumSize: const Size(double.infinity, 48.0)),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(onRefresh: onRefresh, child: buildAnalysisList(holdingsItems));
  }
}


