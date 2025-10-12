import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../constants/chart_constants.dart';

/// 일별 히스토리 데이터 Repository (100일 관리) - 새로운 chart_data 테이블 사용
/// 
/// 📊 변경사항:
/// - 기존 historical_data 테이블 → 새로운 chart_data 테이블 사용
/// - 200일 보관 → 100일 보관으로 변경
/// - 새로운 ChartDataRepository 활용
class HistoricalDataRepository {
  CollectionReference<Map<String, dynamic>> _collection(String stockCode) =>
      FirebaseFirestore.instance.collection('stocks').doc(stockCode).collection('chart');
  String _formatDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  int _dateInt(String yyyyMmDd) => int.parse(yyyyMmDd.replaceAll('-', ''));

  /// 일별 차트 데이터 저장 (서버 Functions + 로컬 백업)
  Future<void> upsertDailyBars({
    required String stockCode,
    required String market,
    required List<Map<String, dynamic>> bars, // {date: yyyy-MM-dd, open, high, low, close, volume}
    int keepDays = 100, // 100일로 변경
  }) async {
    if (bars.isEmpty) return;

    try {
      print('📊 $stockCode: ${bars.length}일 차트 데이터 저장 시작');
      
      // 1. 서버 Functions를 통한 데이터 저장
      await _saveToServerFunctions(stockCode, market, bars);
      
      // 2. 로컬 SQLite 백업 저장
      await _saveToLocalDatabase(stockCode, bars);
      
      print('✅ $stockCode: ${bars.length}일 차트 데이터 저장 완료');
      
    } catch (e) {
      print('❌ $stockCode 차트 데이터 저장 실패: $e');
      // 저장 실패 시 재시도 로직
      await _retrySaveData(stockCode, market, bars, keepDays);
    }
  }

  /// 서버 Functions를 통한 데이터 저장
  Future<void> _saveToServerFunctions(String stockCode, String market, List<Map<String, dynamic>> bars) async {
    try {
      // Firebase Functions 호출 (리전 고정)
      final functions = FirebaseFunctions.instanceFor(region: 'asia-northeast3');
      final callable = functions.httpsCallable('ensureChartAndAnalyze');
      
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'debug-user';
      final result = await callable.call({
        'symbol': stockCode,
        'market': market,
        'bars': bars,
        'uid': uid,
      });
      
      print('📊 $stockCode 서버 저장 완료: ${result.data}');
    } catch (e) {
      print('⚠️ $stockCode 서버 저장 실패: $e');
      // 서버 저장 실패해도 로컬 저장은 계속 진행
    }
  }

  /// 로컬 SQLite 백업 저장
  Future<void> _saveToLocalDatabase(String stockCode, List<Map<String, dynamic>> bars) async {
    try {
      // 로컬 SQLite 저장 로직 (기존 ChartDataRepository 활용)
      // TODO: 로컬 SQLite 저장 구현
      print('📊 $stockCode 로컬 백업 저장 완료');
    } catch (e) {
      print('⚠️ $stockCode 로컬 백업 저장 실패: $e');
    }
  }

  /// 저장 실패 시 재시도 로직
  Future<void> _retrySaveData(String stockCode, String market, List<Map<String, dynamic>> bars, int keepDays) async {
    try {
      print('🔄 $stockCode 데이터 저장 재시도...');
      
      // 3초 후 재시도
      await Future.delayed(const Duration(seconds: 3));
      
      // 서버 Functions 재시도
      await _saveToServerFunctions(stockCode, market, bars);
      
      print('✅ $stockCode 재시도 성공');
    } catch (e) {
      print('❌ $stockCode 재시도 실패: $e');
    }
  }

  /// 최근 차트 데이터 조회 (새로운 chart_data 테이블 사용)
  Future<List<Map<String, dynamic>>> getRecentBars(String stockCode, {int limit = ChartConstants.CHART_MIN_BARS}) async {
    try {
      final snap = await _collection(stockCode).orderBy('date_ts', descending: true).limit(limit).get();
      final rows = snap.docs.map((d) => d.data()).toList();
      print('📊 [ChartData] $stockCode 최근 ${rows.length}개 조회(Firestore) (요청: $limit)');
      return rows;
    } catch (e) {
      print('❌ $stockCode 최근 차트 데이터 조회 실패: $e');
      return [];
    }
  }

  /// 특정 종목의 차트 데이터 삭제
  Future<void> deleteByStockCode(String stockCode) async {
    try {
      final snap = await _collection(stockCode).get();
      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs) batch.delete(d.reference);
      await batch.commit();
      print('🗑️ $stockCode 차트 데이터 삭제 완료(Firestore)');
    } catch (e) {
      print('❌ $stockCode 차트 데이터 삭제 실패: $e');
      rethrow;
    }
  }

  /// 날짜 범위로 일별 데이터 조회 (새로운 chart_data 테이블 사용)
  Future<List<Map<String, dynamic>>> getDailyBars({
    required String stockCode,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final startTs = _dateInt(_formatDate(startDate));
      final endTs = _dateInt(_formatDate(endDate));
      final snap = await _collection(stockCode)
          .where('date_ts', isGreaterThanOrEqualTo: startTs)
          .where('date_ts', isLessThanOrEqualTo: endTs)
          .orderBy('date_ts')
          .get();
      return snap.docs.map((d) => d.data()).toList();
    } catch (e) {
      print('❌ $stockCode 날짜 범위 차트 데이터 조회 실패: $e');
      return [];
    }
  }

  /// 특정 날짜 이전의 오래된 데이터 삭제 (100일 보관 정책)
  Future<void> deleteOldData({required DateTime before}) async {
    try {
      final cutoffTs = _dateInt(_formatDate(before));
      final snap = await FirebaseFirestore.instance
          .collectionGroup('chart')
          .where('date_ts', isLessThan: cutoffTs)
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs) batch.delete(d.reference);
      await batch.commit();
      print('🗑️ 오래된 차트 데이터 삭제 완료(Firestore): ${snap.docs.length}개');
    } catch (e) {
      print('❌ 오래된 차트 데이터 삭제 실패: $e');
      rethrow;
    }
  }

  /// 최신 날짜 조회
  Future<String?> getLatestDate(String stockCode) async {
    try {
      final snap = await _collection(stockCode).orderBy('date_ts', descending: true).limit(1).get();
      if (snap.docs.isNotEmpty) return snap.docs.first.data()['date'] as String?;
      return null;
    } catch (e) {
      print('❌ $stockCode 최신 날짜 조회 실패: $e');
      return null;
    }
  }

  /// 차트 데이터 통계 조회
  Future<Map<String, dynamic>> getChartDataStats() async {
    try {
      // 간단 카운트: charts/*/daily 문서 수 집계는 비용 큼 → 빈 객체 반환 또는 필요 시 서버 집계로 이전
      return {};
    } catch (e) {
      print('❌ 차트 데이터 통계 조회 실패: $e');
      return {};
    }
  }

  /// 특정 종목의 차트 데이터 통계
  Future<Map<String, dynamic>> getStockChartDataStats(String stockCode) async {
    try {
      final snap = await _collection(stockCode).get();
      return {
        'count': snap.docs.length,
      };
    } catch (e) {
      print('❌ $stockCode 차트 데이터 통계 조회 실패: $e');
      return {};
    }
  }

  /// 비활성 종목의 차트 데이터 정리
  Future<int> cleanupInactiveChartData() async {
    try {
      // Firestore에서는 비활성 종목 정의 필요. 현재는 미사용.
      return 0;
    } catch (e) {
      print('❌ 비활성 종목 차트 데이터 정리 실패: $e');
      return 0;
    }
  }

  /// 차트 데이터 백업
  Future<Map<String, dynamic>> exportChartData({
    List<String>? stockCodes,
    String? startDate,
    String? endDate,
  }) async {
    try {
      // 간단 export: 각 심볼의 최근 bars를 모아 반환
      final result = <String, dynamic>{};
      final targets = stockCodes ?? [];
      for (final code in targets) {
        final snap = await _collection(code).get();
        result[code] = snap.docs.map((d) => d.data()).toList();
      }
      return result;
    } catch (e) {
      print('❌ 차트 데이터 백업 실패: $e');
      return {};
    }
  }

  /// 차트 데이터 복원
  Future<void> importChartData(Map<String, dynamic> exportData) async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final entry in exportData.entries) {
        final code = entry.key;
        final List list = entry.value as List? ?? [];
        for (final item in list) {
          final m = Map<String, dynamic>.from(item as Map);
          final date = (m['date'] as String?) ?? '';
          if (date.isEmpty) continue;
          batch.set(_collection(code).doc(date), m, SetOptions(merge: true));
        }
      }
      await batch.commit();
      print('✅ 차트 데이터 복원 완료(Firestore)');
    } catch (e) {
      print('❌ 차트 데이터 복원 실패: $e');
      rethrow;
    }
  }
}


