import 'package:flutter/material.dart';

class LoadingSection extends StatelessWidget {
  const LoadingSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Row(children: [
        SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[600]!)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('데이터 수집 및 분석 중...', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.blue[700])),
            const SizedBox(height: 4),
            Text('실시간 데이터를 수집하고 AI 분석을 수행하고 있습니다.', style: TextStyle(fontSize: 12, color: Colors.blue[600])),
          ]),
        ),
      ]),
    );
  }
}


