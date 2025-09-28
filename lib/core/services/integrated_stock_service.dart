import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// 통합 종목 데이터 서비스
/// 종목 하나에 대한 모든 정보를 한 번에 조회
class IntegratedStockService {
  
  /// 통합 종목 데이터 조회
  /// 종목의 차트, 현재가, 분석 데이터를 모두 한 번에 조회
  static Future<Map<String, dynamic>?> getStockData(String symbol) async {
    try {
      print('📊 통합 종목 데이터 조회 시작: $symbol');
      
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('getStockData');
      
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'debug-user';
      
      final result = await callable.call({
        'symbol': symbol,
        'uid': uid,
      });
      
      if (result.data['success'] == true) {
        final data = result.data['data'];
        print('✅ 통합 종목 데이터 조회 성공: $symbol');
        print('  - 차트 데이터: ${data['chartData']?.length ?? 0}개');
        print('  - 현재가: ${data['currentPrice']?['currentPrice'] ?? 'N/A'}');
        print('  - 분석 점수: ${data['analysis']?['comprehensiveScore'] ?? 'N/A'}');
        return data;
      } else {
        print('❌ 통합 종목 데이터 조회 실패: $symbol - ${result.data['error']}');
        return null;
      }
    } catch (e) {
      print('❌ 통합 종목 데이터 조회 실패: $symbol - $e');
      return null;
    }
  }
  
  /// 다중 종목 데이터 조회
  /// 여러 종목의 데이터를 한 번에 조회
  static Future<List<Map<String, dynamic>>> getMultipleStockData(List<String> symbols) async {
    try {
      print('📊 다중 종목 데이터 조회 시작: ${symbols.length}개 종목');
      
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('getMultipleStockData');
      
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'debug-user';
      
      final result = await callable.call({
        'symbols': symbols,
        'uid': uid,
      });
      
      if (result.data['success'] == true) {
        final results = result.data['results'] as List;
        print('✅ 다중 종목 데이터 조회 성공: ${results.length}개 결과');
        return results.cast<Map<String, dynamic>>();
      } else {
        print('❌ 다중 종목 데이터 조회 실패: ${result.data['error']}');
        return [];
      }
    } catch (e) {
      print('❌ 다중 종목 데이터 조회 실패: $e');
      return [];
    }
  }
  
  /// 종목 데이터 새로고침
  /// 기존 데이터를 무시하고 최신 데이터로 강제 업데이트
  static Future<Map<String, dynamic>?> refreshStockData(String symbol) async {
    try {
      print('🔄 종목 데이터 새로고침 시작: $symbol');
      
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('refreshStockData');
      
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'debug-user';
      
      final result = await callable.call({
        'symbol': symbol,
        'uid': uid,
      });
      
      if (result.data['success'] == true) {
        final data = result.data['data'];
        print('✅ 종목 데이터 새로고침 성공: $symbol');
        return data;
      } else {
        print('❌ 종목 데이터 새로고침 실패: $symbol - ${result.data['error']}');
        return null;
      }
    } catch (e) {
      print('❌ 종목 데이터 새로고침 실패: $symbol - $e');
      return null;
    }
  }
  
  /// 종목 데이터 상태 확인
  /// 특정 종목의 데이터 상태를 확인
  static Future<Map<String, dynamic>?> getStockDataStatus(String symbol) async {
    try {
      print('📊 종목 데이터 상태 확인: $symbol');
      
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('getStockDataStatus');
      
      final result = await callable.call({
        'symbol': symbol,
      });
      
      if (result.data['success'] == true) {
        final data = result.data['data'];
        print('✅ 종목 데이터 상태 확인 성공: $symbol');
        print('  - 상태: ${data['status']}');
        print('  - 마지막 업데이트: ${data['lastUpdated']}');
        print('  - 데이터 개수: ${data['dataCount']}');
        return data;
      } else {
        print('❌ 종목 데이터 상태 확인 실패: $symbol - ${result.data['error']}');
        return null;
      }
    } catch (e) {
      print('❌ 종목 데이터 상태 확인 실패: $symbol - $e');
      return null;
    }
  }
  
  /// 통합 데이터에서 현재가 정보 추출
  static Map<String, dynamic>? extractCurrentPrice(Map<String, dynamic>? stockData) {
    if (stockData == null) return null;
    return stockData['currentPrice'] as Map<String, dynamic>?;
  }
  
  /// 통합 데이터에서 차트 데이터 추출
  static List<Map<String, dynamic>> extractChartData(Map<String, dynamic>? stockData) {
    if (stockData == null) return [];
    final chartData = stockData['chartData'] as List?;
    return chartData?.cast<Map<String, dynamic>>() ?? [];
  }
  
  /// 통합 데이터에서 분석 데이터 추출
  static Map<String, dynamic>? extractAnalysis(Map<String, dynamic>? stockData) {
    if (stockData == null) return null;
    return stockData['analysis'] as Map<String, dynamic>?;
  }
  
  /// 통합 데이터에서 종목 정보 추출
  static Map<String, dynamic>? extractStockInfo(Map<String, dynamic>? stockData) {
    if (stockData == null) return null;
    return stockData['stockInfo'] as Map<String, dynamic>?;
  }
  
  /// 통합 데이터에서 최신 거래량 추출
  static double extractLatestVolume(Map<String, dynamic>? stockData) {
    final chartData = extractChartData(stockData);
    if (chartData.isEmpty) return 0.0;
    
    final latestData = chartData.first;
    return (latestData['volume'] as num?)?.toDouble() ?? 0.0;
  }
  
  /// 통합 데이터에서 최신 거래일 추출
  static String extractLatestDate(Map<String, dynamic>? stockData) {
    final chartData = extractChartData(stockData);
    if (chartData.isEmpty) return '';
    
    final latestData = chartData.first;
    return latestData['date']?.toString() ?? '';
  }
}
