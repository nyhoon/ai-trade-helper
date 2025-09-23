/// 통합 신선도 관리 시스템
/// 모든 캐시와 데이터의 신선도를 일관되게 관리

/// 신선도 상태 열거형
enum FreshnessStatus {
  FRESH,    // 최신 (TTL 내)
  STALE,    // 약간 오래됨 (TTL × 2 내)
  EXPIRED,  // 오래됨 (TTL × 2 초과)
  NO_DATA,  // 데이터 없음
}

/// 신선도 색상 정보
class FreshnessColor {
  final int background;
  final int text;
  final int icon;
  
  const FreshnessColor({
    required this.background,
    required this.text,
    required this.icon,
  });
}

/// 신선도 요약 정보
class FreshnessSummary {
  final FreshnessStatus overallStatus;
  final DateTime? oldestTime;
  final Map<String, bool> freshnessChecks;
  final String text;
  final FreshnessColor color;
  final String icon;
  
  const FreshnessSummary({
    required this.overallStatus,
    required this.oldestTime,
    required this.freshnessChecks,
    required this.text,
    required this.color,
    required this.icon,
  });
  
  /// 모든 데이터가 신선한지 확인
  bool get isAllFresh => freshnessChecks.values.every((isFresh) => isFresh);
  
  /// 일부 데이터가 오래되었는지 확인
  bool get hasStaleData => freshnessChecks.values.any((isFresh) => !isFresh);
  
  /// 오래된 데이터 개수
  int get staleDataCount => freshnessChecks.values.where((isFresh) => !isFresh).length;
}

/// 통합 신선도 관리 시스템
class DataFreshnessManager {
  // 통일된 신선도 기준 (분 단위)
  static const Duration STOCK_DATA_TTL = Duration(minutes: 3);      // 주식 데이터
  static const Duration CHART_DATA_TTL = Duration(minutes: 30);     // 차트 데이터
  static const Duration ANALYSIS_TTL = Duration(minutes: 5);        // 분석 결과
  static const Duration PRICE_DATA_TTL = Duration(minutes: 3);      // 가격 데이터
  static const Duration VOLUME_DATA_TTL = Duration(minutes: 3);     // 거래량 데이터
  
  /// 주식 데이터 신선도 검사
  static bool isStockDataFresh(DateTime? timestamp) {
    if (timestamp == null) return false;
    return DateTime.now().difference(timestamp) < STOCK_DATA_TTL;
  }
  
  /// 차트 데이터 신선도 검사
  static bool isChartDataFresh(DateTime? timestamp) {
    if (timestamp == null) return false;
    return DateTime.now().difference(timestamp) < CHART_DATA_TTL;
  }
  
  /// 분석 결과 신선도 검사
  static bool isAnalysisFresh(DateTime? timestamp) {
    if (timestamp == null) return false;
    return DateTime.now().difference(timestamp) < ANALYSIS_TTL;
  }
  
  /// 가격 데이터 신선도 검사
  static bool isPriceDataFresh(DateTime? timestamp) {
    if (timestamp == null) return false;
    return DateTime.now().difference(timestamp) < PRICE_DATA_TTL;
  }
  
  /// 거래량 데이터 신선도 검사
  static bool isVolumeDataFresh(DateTime? timestamp) {
    if (timestamp == null) return false;
    return DateTime.now().difference(timestamp) < VOLUME_DATA_TTL;
  }
  
  /// 신선도 상태 판단
  static FreshnessStatus getFreshnessStatus(DateTime? timestamp, {Duration? customTTL}) {
    if (timestamp == null) return FreshnessStatus.NO_DATA;
    
    final ttl = customTTL ?? STOCK_DATA_TTL;
    final minutes = DateTime.now().difference(timestamp).inMinutes;
    
    if (minutes < ttl.inMinutes) return FreshnessStatus.FRESH;
    if (minutes < ttl.inMinutes * 2) return FreshnessStatus.STALE;
    return FreshnessStatus.EXPIRED;
  }
  
  /// 신선도 텍스트 생성
  static String getFreshnessText(DateTime? timestamp) {
    if (timestamp == null) return '데이터 없음';
    
    final minutes = DateTime.now().difference(timestamp).inMinutes;
    if (minutes < 1) return '방금 전';
    if (minutes < 60) return '$minutes분 전';
    
    final hours = minutes ~/ 60;
    if (hours < 24) return '${hours}시간 전';
    
    final days = hours ~/ 24;
    return '${days}일 전';
  }
  
  /// 신선도 색상 반환
  static FreshnessColor getFreshnessColor(FreshnessStatus status) {
    switch (status) {
      case FreshnessStatus.FRESH:
        return const FreshnessColor(
          background: 0xFFE8F5E8,  // 연한 녹색
          text: 0xFF2E7D32,        // 진한 녹색
          icon: 0xFF4CAF50,        // 중간 녹색
        );
      case FreshnessStatus.STALE:
        return const FreshnessColor(
          background: 0xFFFFF3E0,  // 연한 주황색
          text: 0xFFE65100,        // 진한 주황색
          icon: 0xFFFF9800,        // 중간 주황색
        );
      case FreshnessStatus.EXPIRED:
        return const FreshnessColor(
          background: 0xFFFFEBEE,  // 연한 빨간색
          text: 0xFFC62828,        // 진한 빨간색
          icon: 0xFFF44336,        // 중간 빨간색
        );
      case FreshnessStatus.NO_DATA:
        return const FreshnessColor(
          background: 0xFFF5F5F5,  // 연한 회색
          text: 0xFF616161,        // 진한 회색
          icon: 0xFF9E9E9E,        // 중간 회색
        );
    }
  }
  
  /// 신선도 아이콘 반환
  static String getFreshnessIcon(FreshnessStatus status) {
    switch (status) {
      case FreshnessStatus.FRESH:
        return '🟢';  // 녹색 원
      case FreshnessStatus.STALE:
        return '🟡';  // 노란색 원
      case FreshnessStatus.EXPIRED:
        return '🔴';  // 빨간색 원
      case FreshnessStatus.NO_DATA:
        return '⚪';  // 흰색 원
    }
  }
  
  /// 통합 신선도 검사 (모든 데이터 타입)
  static Map<String, bool> checkAllDataFreshness({
    DateTime? stockDataTime,
    DateTime? chartDataTime,
    DateTime? analysisTime,
    DateTime? priceDataTime,
    DateTime? volumeDataTime,
  }) {
    return {
      'stockData': isStockDataFresh(stockDataTime),
      'chartData': isChartDataFresh(chartDataTime),
      'analysis': isAnalysisFresh(analysisTime),
      'priceData': isPriceDataFresh(priceDataTime),
      'volumeData': isVolumeDataFresh(volumeDataTime),
    };
  }
  
  /// 가장 오래된 데이터 시간 반환
  static DateTime? getOldestDataTime(List<DateTime?> timestamps) {
    final validTimestamps = timestamps.where((t) => t != null).cast<DateTime>().toList();
    if (validTimestamps.isEmpty) return null;
    
    return validTimestamps.reduce((a, b) => a.isBefore(b) ? a : b);
  }
  
  /// 신선도 요약 정보 생성
  static FreshnessSummary getFreshnessSummary({
    DateTime? stockDataTime,
    DateTime? chartDataTime,
    DateTime? analysisTime,
    DateTime? priceDataTime,
    DateTime? volumeDataTime,
  }) {
    final allTimes = [stockDataTime, chartDataTime, analysisTime, priceDataTime, volumeDataTime];
    final oldestTime = getOldestDataTime(allTimes);
    final overallStatus = getFreshnessStatus(oldestTime);
    
    final freshnessChecks = checkAllDataFreshness(
      stockDataTime: stockDataTime,
      chartDataTime: chartDataTime,
      analysisTime: analysisTime,
      priceDataTime: priceDataTime,
      volumeDataTime: volumeDataTime,
    );
    
    return FreshnessSummary(
      overallStatus: overallStatus,
      oldestTime: oldestTime,
      freshnessChecks: freshnessChecks,
      text: getFreshnessText(oldestTime),
      color: getFreshnessColor(overallStatus),
      icon: getFreshnessIcon(overallStatus),
    );
  }
}
