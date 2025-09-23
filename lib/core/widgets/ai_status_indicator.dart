import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/app_data_manager.dart';

class AiStatusIndicator extends StatefulWidget {
  const AiStatusIndicator({super.key});

  @override
  State<AiStatusIndicator> createState() => _AiStatusIndicatorState();
}

class _AiStatusIndicatorState extends State<AiStatusIndicator> {
  bool _isAiRunning = false;

  @override
  void initState() {
    super.initState();
    _checkAiStatus();
    // 주기적으로 상태 확인
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _checkAiStatus();
      } else {
        timer.cancel();
      }
    });
  }

  void _checkAiStatus() async {
    try {
      final newStatus = await AppDataManager.instance.getAutoTradingStatus();
      if (newStatus != _isAiRunning) {
        if (mounted) {
          setState(() {
            _isAiRunning = newStatus;
          });
        }
      }
    } catch (e) {
      print('❌ AI 상태 확인 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAiRunning) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.psychology,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 4),
          const Text(
            'AI가 출근했어요.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
