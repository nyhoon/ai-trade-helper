import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:ai_helper/core/api/kis_unified_api_service.dart';
import 'package:ai_helper/core/api/global_api_credentials.dart';
import 'package:dio/dio.dart';

/// 서버 Functions에 위임하는 KIS 프록시 래퍼
class RemoteKisService {
  RemoteKisService._();
  static final RemoteKisService instance = RemoteKisService._();

  // 한국 사용자를 위한 asia-northeast3 리전만 사용
  static const String _region = 'asia-northeast3';
  FirebaseFunctions get _functions => FirebaseFunctions.instanceFor(app: Firebase.app(), region: _region);
  
  // HTTP 요청용 Dio 인스턴스
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  /// Firebase Auth 상태 확인 및 재로그인
  Future<void> _ensureAuthenticated() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('⚠️ [RemoteKisService] 사용자 인증 정보 없음, 익명 로그인 시도...');
        await FirebaseAuth.instance.signInAnonymously();
        print('✅ [RemoteKisService] 익명 로그인 완료');
      } else {
        print('✅ [RemoteKisService] 사용자 인증 상태 확인: ${user.uid}');
      }
    } catch (e) {
      print('❌ [RemoteKisService] 인증 확인 실패: $e');
      // 인증 실패해도 Functions 호출은 시도 (일부 Functions는 인증 불필요)
    }
  }

  Future<List<Map<String, dynamic>>> getDailyChart(String symbol, {int days = 100, String? uid}) async {
    try {
      // 서버 흐름 강제: 먼저 보장
      final effectiveUid = (uid != null && uid.isNotEmpty)
          ? uid
          : (FirebaseAuth.instance.currentUser?.uid ?? 'debug-user');
      await ensureChartAndAnalyze(uid: effectiveUid, symbol: symbol);
      
      print('🔍 [RemoteKisService] getDailyChart 시작: $symbol');
      print('🔍 [RemoteKisService] 리전: $_region');
      
      final callable = _functions.httpsCallable('getStockData');
      final resp = await callable.call(<String, dynamic>{'symbol': symbol, 'uid': effectiveUid});
      final data = (resp.data as Map?) ?? const {};
      final chartData = (data['data']?['chart'] as List?) ?? const [];
      
      print('✅ [RemoteKisService] getDailyChart 성공: $symbol (${chartData.length}개 데이터)');
      return chartData.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      print('❌ [RemoteKisService] getDailyChart 실패: $e');
      return <Map<String, dynamic>>[];
    }
  }

  Future<Map<String, dynamic>?> getCurrentPrice(String symbol, {String? uid}) async {
    try {
      print('🔍 [RemoteKisService] 현재가 조회 시작: $symbol');
      
      // Firebase Auth 상태 확인
      await _ensureAuthenticated();
      
      final effectiveUid = (uid != null && uid.isNotEmpty)
          ? uid
          : (FirebaseAuth.instance.currentUser?.uid ?? 'debug-user');
      
      print('🔍 [RemoteKisService] UID: $effectiveUid');
      print('🔍 [RemoteKisService] 리전: $_region');
      
      // 1) getCurrentPrice 함수 직접 호출
      try {
        final callable = _functions.httpsCallable('getCurrentPrice');
        final resp = await callable.call(<String, dynamic>{'symbol': symbol, 'uid': effectiveUid});
        final data = (resp.data as Map?) ?? const {};
        
        print('🔍 [RemoteKisService] 서버 응답: ${data}');
        
        if (data['hasData'] == true) {
          final serverData = Map<String, dynamic>.from(data['data'] as Map);
          
          final result = {
            'currentPrice': asDouble(serverData['current_price'] ?? serverData['currentPrice']),
            'openPrice': asDouble(serverData['open_price'] ?? serverData['openPrice']),
            'prevClose': asDouble(serverData['prev_close'] ?? serverData['prevClose']),
            'highPrice': asDouble(serverData['high_price'] ?? serverData['highPrice']),
            'lowPrice': asDouble(serverData['low_price'] ?? serverData['lowPrice']),
            'volume': asInt(serverData['volume']),
            'changeAmount': asDouble(serverData['change_amount'] ?? serverData['changeAmount']),
            'changeRate': asDouble(serverData['change_rate'] ?? serverData['changeRate']),
            'stockName': serverData['stock_name'] ?? serverData['stockName'],
            'market': serverData['market'],
            'timestamp': serverData['timestamp'],
          };
          
          print('✅ [RemoteKisService] 현재가 조회 성공: $symbol');
          return result;
        }
      } catch (e) {
        print('❌ [RemoteKisService] getCurrentPrice 실패: $e');
      }
      
      // 2) 폴백: 클라이언트 KIS API 직접 호출
      print('🔄 [RemoteKisService] 서버 실패 → 클라이언트 KIS API 직접 호출: $symbol');
      try {
        final kisApi = KisUnifiedApiService();
        final priceData = await kisApi.getStockPriceAuto(symbol);
        
        if (priceData != null) {
          print('✅ [RemoteKisService] 클라이언트 KIS API 성공: $symbol');
          return priceData;
        }
      } catch (e) {
        print('❌ [RemoteKisService] 클라이언트 KIS API 실패 ($symbol): $e');
      }
      
      print('❌ [RemoteKisService] 현재가 데이터 없음: $symbol');
      return null;
    } catch (e) {
      print('❌ [RemoteKisService] 현재가 조회 실패 ($symbol): $e');
      return null;
    }
  }

  Future<bool> ensureChartAndAnalyze({required String uid, required String symbol}) async {
    try {
      print('🔍 [RemoteKisService] ensureChartAndAnalyze 시작: $symbol (uid: $uid)');
      print('🔍 [RemoteKisService] 리전: $_region');
      
      // Firebase Auth 상태 확인
      await _ensureAuthenticated();
      
      // Firebase Functions 호출
      final callable = _functions.httpsCallable('ensureChartAndAnalyze');
      print('🔍 [RemoteKisService] 함수 호출 준비 완료: ensureChartAndAnalyze');
      
      final requestData = <String, dynamic>{
        'symbol': symbol,
        'uid': uid,
        'market': 'NASDAQ', // 해외주식 기본값
      };
      
      print('🔍 [RemoteKisService] 전달할 데이터: $requestData');
      print('🔍 [RemoteKisService] symbol 값: "$symbol" (길이: ${symbol.length})');
      print('🔍 [RemoteKisService] uid 값: "$uid" (길이: ${uid.length})');
      print('🔍 [RemoteKisService] requestData 타입: ${requestData.runtimeType}');
      print('🔍 [RemoteKisService] requestData 키들: ${requestData.keys.toList()}');
      
      final resp = await callable.call(requestData);
      
      print('🔍 [RemoteKisService] 서버 응답 받음: ${resp.data}');
      
      final data = (resp.data as Map?) ?? const {};
      final success = (data['success'] == true);
      
      if (success) {
        print('✅ [RemoteKisService] ensureChartAndAnalyze 성공: $symbol');
        return true;
      } else {
        print('⚠️ [RemoteKisService] ensureChartAndAnalyze 실패: ${data['error']}');
        print('⚠️ [RemoteKisService] 전체 응답 데이터: $data');
        return false;
      }
    } catch (e) {
      print('❌ [RemoteKisService] ensureChartAndAnalyze 오류: $e');
      print('❌ [RemoteKisService] 오류 타입: ${e.runtimeType}');
      print('❌ [RemoteKisService] 스택 트레이스: ${e.toString()}');
      
      // Firebase Functions 오류 상세 분석
      if (e.toString().contains('firebase_functions')) {
        print('🔍 [RemoteKisService] Firebase Functions 오류 감지');
        if (e.toString().contains('unauthenticated')) {
          print('🔍 [RemoteKisService] 인증 오류 - 재로그인 시도');
          try {
            await FirebaseAuth.instance.signInAnonymously();
            print('✅ [RemoteKisService] 재로그인 성공');
          } catch (authError) {
            print('❌ [RemoteKisService] 재로그인 실패: $authError');
          }
        }
      }
      
      return false;
    }
  }

  /// 통합 종목 데이터 조회 (차트 + 현재가 + 분석)
  Future<List<Map<String, dynamic>>> getStockData(String symbol, {String? uid}) async {
    try {
      print('🔍 [RemoteKisService] 통합 종목 데이터 조회 시작: $symbol');
      
      final effectiveUid = (uid != null && uid.isNotEmpty)
          ? uid
          : (FirebaseAuth.instance.currentUser?.uid ?? 'debug-user');
      
      print('🔍 [RemoteKisService] UID: $effectiveUid');
      print('🔍 [RemoteKisService] 리전: $_region');
      
      // Firebase Functions 호출
      final callable = _functions.httpsCallable('getStockData');
      print('🔍 [RemoteKisService] 함수 호출 준비 완료: getStockData');
      
      final resp = await callable.call(<String, dynamic>{'symbol': symbol, 'uid': effectiveUid});
      print('🔍 [RemoteKisService] 서버 응답 받음: ${resp.data}');
      
      final data = (resp.data as Map?) ?? const {};
      
      if (data['success'] == true) {
        final stockData = Map<String, dynamic>.from(data['data'] as Map);
        final chartData = (stockData['chart'] as List?) ?? const [];
        print('✅ [RemoteKisService] getStockData 성공: $symbol (${chartData.length}개 데이터)');
        return chartData.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } else {
        print('⚠️ [RemoteKisService] getStockData 실패: ${data['error']}');
        return <Map<String, dynamic>>[];
      }
    } catch (e) {
      print('❌ [RemoteKisService] getStockData 오류: $e');
      print('❌ [RemoteKisService] 오류 타입: ${e.runtimeType}');
      return <Map<String, dynamic>>[];
    }
  }

  // 숫자 캐스팅 통일 헬퍼
  static double asDouble(dynamic v, {double def = 0.0}) {
    if (v == null) return def;
    if (v is num) return v.toDouble();
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return def;
      return double.tryParse(s) ?? def;
    }
    return def;
  }

  static int asInt(dynamic v, {int def = 0}) {
    if (v == null) return def;
    if (v is num) return v.toInt();
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return def;
      final d = double.tryParse(s);
      return d?.toInt() ?? def;
    }
    return def;
  }
}