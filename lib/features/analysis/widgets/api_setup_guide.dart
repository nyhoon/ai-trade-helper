import 'package:flutter/material.dart';

class ApiSetupGuide extends StatelessWidget {
  const ApiSetupGuide({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.warning_amber, color: Colors.orange[700], size: 24),
            const SizedBox(width: 12),
            Expanded(child: Text('API 설정이 필요합니다', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange[700]))),
          ]),
          const SizedBox(height: 12),
          Text('실시간 분석과 보유종목 확인을 위해 KIS API 설정이 필요합니다.', style: TextStyle(fontSize: 14, color: Colors.orange[600])),
          const SizedBox(height: 8),
          Text('• 설정 화면에서 API 키 등록\n• 계좌번호 및 앱키 설정\n• 실시간 데이터 조회 가능', style: TextStyle(fontSize: 12, color: Colors.orange[600], height: 1.4)),
        ],
      ),
    );
  }
}


