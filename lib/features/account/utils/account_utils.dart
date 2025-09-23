import '../../../core/data/app_data_manager.dart';

/// 계좌 관련 유틸리티 클래스
class AccountUtils {
  /// 나스닥 종목인지 확인 (미국 시장)
  /// API에서 사용하는 것과 동일한 로직 사용
  static bool isNasdaqStock(String stockCode) {
    // API에서 사용하는 정확히 같은 로직
    return RegExp(r'^[A-Z]{1,5}$').hasMatch(stockCode);
  }

  /// 종목 표시명 가져오기
  static String getDisplayName(String stockCode, Map<String, dynamic> holding) {
    // AppDataManager에서 종목명 가져오기
    final masterName = AppDataManager.instance.getStockName(stockCode);
    if (masterName.isNotEmpty && masterName != stockCode) {
      return masterName;
    }
    
    // API 응답에서 종목명 확인
    final apiName = holding['stockName'] as String?;
    if (apiName != null && apiName.isNotEmpty && apiName != stockCode) {
      return apiName;
    }
    
    // 최후 수단으로 종목코드 반환
    return stockCode;
  }

  /// 해외계좌 총 자산 계산 (달러)
  static double calculateOverseasTotalAssets(List<dynamic> holdings) {
    double totalAssets = 0.0;
    
    for (final holding in holdings) {
      final holdingMap = holding as Map<String, dynamic>;
      final stockCode = holdingMap['stockCode'] as String? ?? '';
      final totalValue = (holdingMap['totalValue'] as num?)?.toDouble() ?? 0.0;
      
      if (isNasdaqStock(stockCode)) {
        totalAssets += totalValue;
      }
    }
    
    return totalAssets;
  }

  /// 해외계좌 총 손익 계산 (달러)
  static double calculateOverseasTotalProfit(List<dynamic> holdings) {
    double totalProfit = 0.0;
    
    for (final holding in holdings) {
      final holdingMap = holding as Map<String, dynamic>;
      final stockCode = holdingMap['stockCode'] as String? ?? '';
      final profit = (holdingMap['profit'] as num?)?.toDouble() ?? 0.0;
      
      if (isNasdaqStock(stockCode)) {
        totalProfit += profit;
      }
    }
    
    return totalProfit;
  }

  /// 해외계좌 수익률 계산
  static double calculateOverseasProfitRate(List<dynamic> holdings) {
    final totalAssets = calculateOverseasTotalAssets(holdings);
    final totalProfit = calculateOverseasTotalProfit(holdings);
    
    if (totalAssets <= 0) return 0.0;
    
    return (totalProfit / totalAssets) * 100;
  }
}
