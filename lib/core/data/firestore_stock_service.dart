import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore에서 직접 /stocks 컬렉션 데이터를 읽어오는 서비스
class FirestoreStockService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  /// 종목의 통합 데이터 조회 (차트 + 현재가 + 분석)
  static Future<Map<String, dynamic>?> getStockData(String symbol) async {
    try {
      print('📊 [FirestoreStockService] 종목 데이터 조회 시작: $symbol');
      
      final docRef = _firestore.collection('stocks').doc(symbol);
      final doc = await docRef.get();
      
      if (!doc.exists) {
        print('⚠️ [FirestoreStockService] 종목 데이터 없음: $symbol');
        return null;
      }
      
      final data = doc.data()!;
      print('✅ [FirestoreStockService] 종목 데이터 조회 성공: $symbol');
      print('  - 현재가: ${data['current']?['currentPrice'] ?? 'N/A'}');
      print('  - 분석 점수: ${data['analysis']?['comprehensiveScore'] ?? 'N/A'}');
      
      return data;
    } catch (e) {
      print('❌ [FirestoreStockService] 종목 데이터 조회 실패: $symbol - $e');
      return null;
    }
  }
  
  /// 종목의 현재가 데이터만 조회
  static Future<Map<String, dynamic>?> getCurrentPrice(String symbol) async {
    try {
      final docRef = _firestore.collection('stocks').doc(symbol);
      final doc = await docRef.get();
      
      if (!doc.exists) {
        return null;
      }
      
      final data = doc.data()!;
      return data['current'] as Map<String, dynamic>?;
    } catch (e) {
      print('❌ [FirestoreStockService] 현재가 조회 실패: $symbol - $e');
      return null;
    }
  }
  
  /// 종목의 차트 데이터 조회 (서브컬렉션에서 읽기)
  static Future<List<Map<String, dynamic>>> getChartData(String symbol) async {
    try {
      print('📈 [FirestoreStockService] 차트 데이터 조회 시작: $symbol');
      
      // 서브컬렉션에서 차트 데이터 읽기
      final chartRef = _firestore
        .collection('stocks')
        .doc(symbol)
        .collection('chart')
        .orderBy('date_ts', descending: false)
        .limit(100);
      
      final snapshot = await chartRef.get();
      
      if (snapshot.docs.isEmpty) {
        print('⚠️ [FirestoreStockService] 차트 데이터 없음: $symbol');
        return [];
      }
      
      final chartData = snapshot.docs
        .map((doc) => Map<String, dynamic>.from(doc.data()))
        .toList();
      
      // 디버깅: 차트 데이터 상세 정보 출력
      print('✅ [FirestoreStockService] 차트 데이터 조회 성공: $symbol (${chartData.length}개)');
      if (chartData.isNotEmpty) {
        print('📊 [FirestoreStockService] 차트 데이터 상세:');
        print('  - 첫 번째: ${chartData.first['date']} (${chartData.first['volume']}주)');
        print('  - 마지막: ${chartData.last['date']} (${chartData.last['volume']}주)');
        print('  - 최신 거래량: ${chartData.last['volume']}주');
      }
      
      return chartData;
    } catch (e) {
      print('❌ [FirestoreStockService] 차트 데이터 조회 실패: $symbol - $e');
      return [];
    }
  }
  
  /// 종목의 분석 데이터 조회
  static Future<Map<String, dynamic>?> getAnalysisData(String symbol) async {
    try {
      final docRef = _firestore.collection('stocks').doc(symbol);
      final doc = await docRef.get();
      
      if (!doc.exists) {
        return null;
      }
      
      final data = doc.data()!;
      return data['analysis'] as Map<String, dynamic>?;
    } catch (e) {
      print('❌ [FirestoreStockService] 분석 데이터 조회 실패: $symbol - $e');
      return null;
    }
  }
  
  /// 다중 종목 데이터 조회
  static Future<List<Map<String, dynamic>>> getMultipleStockData(List<String> symbols) async {
    try {
      print('📊 [FirestoreStockService] 다중 종목 데이터 조회 시작: ${symbols.length}개');
      
      final results = <Map<String, dynamic>>[];
      
      for (final symbol in symbols) {
        final data = await getStockData(symbol);
        if (data != null) {
          results.add({
            'symbol': symbol,
            'data': data,
          });
        }
      }
      
      print('✅ [FirestoreStockService] 다중 종목 데이터 조회 완료: ${results.length}개');
      return results;
    } catch (e) {
      print('❌ [FirestoreStockService] 다중 종목 데이터 조회 실패: $e');
      return [];
    }
  }
}
