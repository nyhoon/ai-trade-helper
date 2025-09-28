import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CredentialsService {
  CredentialsService._();
  static final CredentialsService instance = CredentialsService._();

  FirebaseFunctions _functionsForRegion(String region) => FirebaseFunctions.instanceFor(app: Firebase.app(), region: region);
  List<String> get _orderedRegions => ['asia-northeast3']; // us-central1 제거

  /// Firebase Auth 상태 확인 및 재로그인
  Future<void> _ensureAuthenticated() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('⚠️ [CredentialsService] 사용자 인증 정보 없음, 익명 로그인 시도...');
        await FirebaseAuth.instance.signInAnonymously();
        print('✅ [CredentialsService] 익명 로그인 완료');
      } else {
        print('✅ [CredentialsService] 사용자 인증 상태 확인: ${user.uid}');
      }
    } catch (e) {
      print('❌ [CredentialsService] 인증 확인 실패: $e');
      // 인증 실패해도 Functions 호출은 시도 (일부 Functions는 인증 불필요)
    }
  }

  Future<bool> saveApiCredentials({
    required String uid,
    required String appKey,
    required String appSecret,
    required String accountNo,
  }) async {
    try {
      // Firebase Auth 상태 확인
      await _ensureAuthenticated();
      
      Exception? lastErr;
      for (final region in _orderedRegions) {
        final f = _functionsForRegion(region);
        // 지역별 지수 백오프 재시도 (INTERNAL/UNAVAILABLE 등 일시 장애 대응)
        const int maxRetries = 5; // 3 → 5로 증가
        Duration delay = const Duration(seconds: 2); // 400ms → 2초로 증가
        for (int attempt = 1; attempt <= maxRetries; attempt++) {
          try {
            print('🔄 [CredentialsService] API 자격증명 저장 시도: $region (시도 $attempt/$maxRetries)');
            final callable = f.httpsCallable('saveApiCredentials');
            final resp = await callable.call(<String, dynamic>{
              'uid': uid,
              'appKey': appKey,
              'appSecret': appSecret,
              'accountNo': accountNo,
            });
            final data = (resp.data as Map?) ?? const {};
            final ok = data['ok'] == true;
            print('🔐 saveApiCredentials('+region+' try#'+attempt.toString()+') -> '+data.toString());
            print('🔍 [CredentialsService] API 자격증명 저장 결과:');
            print('  - Region: $region');
            print('  - Attempt: $attempt');
            print('  - Success: $ok');
            print('  - Response: $data');
            if (ok) {
              print('✅ [CredentialsService] API 자격증명 저장 성공!');
              return true;
            }
          } catch (e) {
            lastErr = e is Exception ? e : Exception(e.toString());
            print('⚠️ saveApiCredentials call failed on '+region+' try#'+attempt.toString()+': '+e.toString());
            if (attempt < maxRetries) {
              print('⏳ [CredentialsService] ${delay.inSeconds}초 후 재시도...');
              await Future.delayed(delay);
              // 지수 백오프 (2초 → 4초 → 8초 → 16초 → 32초)
              delay = Duration(seconds: (delay.inSeconds * 2).clamp(2, 32));
              continue;
            }
          }
          break;
        }
      }
      if (lastErr != null) print('❌ saveApiCredentials failed: '+lastErr.toString());
      return false;
    } catch (e) {
      print('❌ saveApiCredentials fatal: '+e.toString());
      return false;
    }
  }
}


