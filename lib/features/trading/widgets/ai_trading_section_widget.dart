import 'package:flutter/material.dart';
import '../../../core/trading/investment_style_manager.dart';
import '../../../core/trading/investment_style.dart';

/// AI 자동매매 섹션 위젯
class AiTradingSectionWidget extends StatefulWidget {
  final bool isAutoTradingEnabled;
  final Function(bool) onAutoTradingChanged;

  const AiTradingSectionWidget({
    Key? key,
    required this.isAutoTradingEnabled,
    required this.onAutoTradingChanged,
  }) : super(key: key);

  @override
  State<AiTradingSectionWidget> createState() => _AiTradingSectionWidgetState();
}

class _AiTradingSectionWidgetState extends State<AiTradingSectionWidget> {
  bool _isLoading = false;
  final InvestmentStyleManager _styleManager = InvestmentStyleManager();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, // 기존 UI와 동일한 흰색 배경
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI 자동매매 헤더 (로봇 아이콘 추가)
          Row(
            children: [
              Icon(
                Icons.smart_toy, // 로봇 아이콘
                color: _getStyleColor(_styleManager.currentStyle),
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'AI 자동매매',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Switch(
                value: widget.isAutoTradingEnabled,
                onChanged: _isLoading ? null : _handleAutoTradingToggle,
                activeColor: _getStyleColor(_styleManager.currentStyle),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // 상태 메시지 (기존 UI와 동일한 스타일)
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.isAutoTradingEnabled
                      ? 'AI가 자동으로 매매를 수행하고 있습니다'
                      : 'AI 자동매매가 비활성화되어 있습니다',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // 백그라운드 서비스 상태
          Row(
            children: [
              Icon(
                Icons.refresh,
                size: 16,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 8),
              Text(
                '백그라운드 서비스 실행 중 (앱을 닫아도 계속 작동)',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
          
          // 로딩 인디케이터
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleAutoTradingToggle(bool value) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await widget.onAutoTradingChanged(value);
    } catch (e) {
      // 에러 처리
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('자동매매 설정 변경 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 스타일별 색상 반환
  Color _getStyleColor(InvestmentStyle style) {
    switch (style) {
      case InvestmentStyle.conservative:
        return Colors.green[600]!; // 안정적 투자 - 녹색
      case InvestmentStyle.moderate:
        return Colors.blue[600]!; // 일반적 투자 - 파란색
      case InvestmentStyle.aggressive:
        return Colors.red[600]!; // 공격적 투자 - 빨간색
    }
  }
}
