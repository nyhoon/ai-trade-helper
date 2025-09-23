import 'package:flutter/material.dart';
import '../../trading/recommended_stocks_screen.dart';

class RecommendedTab extends StatelessWidget {
  final bool isLoading;
  final bool isFirstLoading;

  const RecommendedTab({super.key, required this.isLoading, required this.isFirstLoading});

  @override
  Widget build(BuildContext context) {
    if (isLoading || isFirstLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('추천종목을 분석중입니다...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return const RecommendedStocksScreen();
  }
}


