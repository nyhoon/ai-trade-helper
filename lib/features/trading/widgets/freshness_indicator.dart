import 'package:flutter/material.dart';
import '../../../core/data/freshness_manager.dart';

/// 신선도 표시 위젯
/// 데이터의 신선도를 시각적으로 표시
class FreshnessIndicator extends StatelessWidget {
  final DateTime? lastUpdated;
  final FreshnessStatus? status;
  final Duration? customTTL;
  final bool showIcon;
  final bool showText;
  final double? fontSize;
  final EdgeInsets? padding;
  final BorderRadius? borderRadius;
  
  const FreshnessIndicator({
    super.key,
    required this.lastUpdated,
    this.status,
    this.customTTL,
    this.showIcon = true,
    this.showText = true,
    this.fontSize,
    this.padding,
    this.borderRadius,
  });
  
  @override
  Widget build(BuildContext context) {
    // 신선도 상태 계산
    final freshnessStatus = status ?? DataFreshnessManager.getFreshnessStatus(
      lastUpdated, 
      customTTL: customTTL,
    );
    
    // 신선도 정보 가져오기
    final freshnessText = DataFreshnessManager.getFreshnessText(lastUpdated);
    final freshnessColor = DataFreshnessManager.getFreshnessColor(freshnessStatus);
    final freshnessIcon = DataFreshnessManager.getFreshnessIcon(freshnessStatus);
    
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Color(freshnessColor.background),
        borderRadius: borderRadius ?? BorderRadius.circular(4),
        border: Border.all(
          color: Color(freshnessColor.icon).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Text(
              freshnessIcon,
              style: TextStyle(
                fontSize: fontSize ?? 10,
                color: Color(freshnessColor.icon),
              ),
            ),
            if (showText) const SizedBox(width: 4),
          ],
          if (showText)
            Text(
              freshnessText,
              style: TextStyle(
                fontSize: fontSize ?? 10,
                color: Color(freshnessColor.text),
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }
}

/// 신선도 요약 표시 위젯
/// 여러 데이터의 신선도를 종합하여 표시
class FreshnessSummaryIndicator extends StatelessWidget {
  final FreshnessSummary summary;
  final bool showDetails;
  final double? fontSize;
  final EdgeInsets? padding;
  final BorderRadius? borderRadius;
  
  const FreshnessSummaryIndicator({
    super.key,
    required this.summary,
    this.showDetails = false,
    this.fontSize,
    this.padding,
    this.borderRadius,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Color(summary.color.background),
        borderRadius: borderRadius ?? BorderRadius.circular(6),
        border: Border.all(
          color: Color(summary.color.icon).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 전체 신선도 상태
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                summary.icon,
                style: TextStyle(
                  fontSize: fontSize ?? 12,
                  color: Color(summary.color.icon),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                summary.text,
                style: TextStyle(
                  fontSize: fontSize ?? 12,
                  color: Color(summary.color.text),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          
          // 상세 정보 (옵션)
          if (showDetails) ...[
            const SizedBox(height: 2),
            ...summary.freshnessChecks.entries.map((entry) {
              final isFresh = entry.value;
              final statusIcon = isFresh ? '✅' : '❌';
              final statusColor = isFresh ? Colors.green : Colors.red;
              
              return Padding(
                padding: const EdgeInsets.only(left: 8, top: 1),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      statusIcon,
                      style: TextStyle(fontSize: (fontSize ?? 12) - 2),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _getDataTypeName(entry.key),
                      style: TextStyle(
                        fontSize: (fontSize ?? 12) - 2,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ],
      ),
    );
  }
  
  String _getDataTypeName(String key) {
    switch (key) {
      case 'stockData': return '주식데이터';
      case 'chartData': return '차트데이터';
      case 'analysis': return '분석결과';
      case 'priceData': return '가격데이터';
      case 'volumeData': return '거래량데이터';
      default: return key;
    }
  }
}

/// 신선도 상태별 배지 위젯
class FreshnessBadge extends StatelessWidget {
  final FreshnessStatus status;
  final String? customText;
  final double? size;
  final bool showIcon;
  
  const FreshnessBadge({
    super.key,
    required this.status,
    this.customText,
    this.size,
    this.showIcon = true,
  });
  
  @override
  Widget build(BuildContext context) {
    final color = DataFreshnessManager.getFreshnessColor(status);
    final icon = DataFreshnessManager.getFreshnessIcon(status);
    final text = customText ?? _getStatusText(status);
    
    return Container(
      width: size ?? 24,
      height: size ?? 24,
      decoration: BoxDecoration(
        color: Color(color.background),
        shape: BoxShape.circle,
        border: Border.all(
          color: Color(color.icon),
          width: 1.5,
        ),
      ),
      child: Center(
        child: showIcon 
          ? Text(
              icon,
              style: TextStyle(
                fontSize: (size ?? 24) * 0.6,
                color: Color(color.icon),
              ),
            )
          : Text(
              text,
              style: TextStyle(
                fontSize: (size ?? 24) * 0.4,
                color: Color(color.text),
                fontWeight: FontWeight.bold,
              ),
            ),
      ),
    );
  }
  
  String _getStatusText(FreshnessStatus status) {
    switch (status) {
      case FreshnessStatus.FRESH:
        return 'F';
      case FreshnessStatus.STALE:
        return 'S';
      case FreshnessStatus.EXPIRED:
        return 'E';
      case FreshnessStatus.NO_DATA:
        return 'N';
    }
  }
}
