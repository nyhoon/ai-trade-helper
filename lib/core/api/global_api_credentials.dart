import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ai_helper/core/remote/credentials_service.dart';

/// 전역 API 자격증명 관리 싱글톤
/// - 앱키, 앱시크릿, 계좌번호, 토큰을 전역에서 관리
/// - 서버와 클라이언트 모두에서 사용 가능
class GlobalApiCredentials {
  GlobalApiCredentials._();
  static final GlobalApiCredentials instance = GlobalApiCredentials._();

  // API 자격증명
  String? _appKey;
  String? _appSecret;
  String? _accountNo;
  String? _accessToken;
  DateTime? _tokenExpiry;
  
  // 초기화 상태
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  
  // API 자격증명 Getter
  String? get appKey => _appKey;
  String? get appSecret => _appSecret;
  String? get accountNo => _accountNo;
  String? get accessToken => _accessToken;
  
  // 유효한 토큰 여부
  bool get hasValidToken {
    if (_accessToken == null || _tokenExpiry == null) return false;
    return DateTime.now().isBefore(_tokenExpiry!);
  }
  
  // 모든 자격증명이 있는지 확인
  bool get hasAllCredentials {
    return _appKey != null && 
           _appSecret != null && 
           _accountNo != null && 
           _accessToken != null;
  }

  /// 앱 시작 시 API 자격증명 초기화
  Future<bool> initialize() async {
    try {
      print('🔐 [GlobalApiCredentials] API 자격증명 초기화 시작...');
      
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('⚠️ [GlobalApiCredentials] 사용자 인증 정보 없음');
        return false;
      }
      
      final uid = user.uid;
      
      // 1. Firestore에서 API 자격증명 조회
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('api')
          .get();
      
      if (doc.exists) {
        final data = doc.data()!;
        _appKey = data['appKey'] as String?;
        _appSecret = data['appSecret'] as String?;
        _accountNo = data['accountNo'] as String?;
        _accessToken = data['accessToken'] as String?;
        
        // 토큰 만료 시간 설정 (24시간)
        if (_accessToken != null) {
          _tokenExpiry = DateTime.now().add(const Duration(hours: 24));
        }
        
        print('✅ [GlobalApiCredentials] Firestore에서 자격증명 로드 완료');
        print('  - AppKey: ${_appKey?.substring(0, 10)}...');
        print('  - AccountNo: ${_accountNo}');
        print('  - AccessToken: ${_accessToken?.substring(0, 20)}...');
        
        _isInitialized = true;
        return true;
      } else {
        print('⚠️ [GlobalApiCredentials] Firestore에 API 자격증명 없음');
        return false;
      }
    } catch (e) {
      print('❌ [GlobalApiCredentials] 초기화 실패: $e');
      return false;
    }
  }

  /// API 자격증명 설정 및 서버 저장
  Future<bool> setCredentials({
    required String appKey,
    required String appSecret,
    required String accountNo,
  }) async {
    try {
      print('🔐 [GlobalApiCredentials] API 자격증명 설정 시작...');
      
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('⚠️ [GlobalApiCredentials] 사용자 인증 정보 없음');
        return false;
      }
      
      final uid = user.uid;
      
      // 1. 로컬에 저장
      _appKey = appKey;
      _appSecret = appSecret;
      _accountNo = accountNo;
      _accessToken = null; // 새로 발급받아야 함
      _tokenExpiry = null;
      
      // 2. 서버에 저장
      final success = await CredentialsService.instance.saveApiCredentials(
        uid: uid,
        appKey: appKey,
        appSecret: appSecret,
        accountNo: accountNo,
      );
      
      if (success) {
        print('✅ [GlobalApiCredentials] API 자격증명 설정 완료');
        _isInitialized = true;
        return true;
      } else {
        print('❌ [GlobalApiCredentials] 서버 저장 실패');
        return false;
      }
    } catch (e) {
      print('❌ [GlobalApiCredentials] 자격증명 설정 실패: $e');
      return false;
    }
  }

  /// 액세스 토큰 설정
  void setAccessToken(String token) {
    _accessToken = token;
    _tokenExpiry = DateTime.now().add(const Duration(hours: 24));
    print('🔐 [GlobalApiCredentials] 액세스 토큰 설정 완료');
  }

  /// 토큰 갱신
  Future<String?> refreshToken() async {
    try {
      if (!hasAllCredentials) {
        print('⚠️ [GlobalApiCredentials] 자격증명이 불완전함');
        return null;
      }
      
      // KIS API 토큰 발급 로직 (실제 구현 필요)
      // 여기서는 예시로 기존 토큰 반환
      print('🔄 [GlobalApiCredentials] 토큰 갱신 시도...');
      
      // 실제로는 KIS API를 호출하여 새 토큰 발급
      // final newToken = await _getKisToken();
      // setAccessToken(newToken);
      
      return _accessToken;
    } catch (e) {
      print('❌ [GlobalApiCredentials] 토큰 갱신 실패: $e');
      return null;
    }
  }

  /// 자격증명 초기화
  void clear() {
    _appKey = null;
    _appSecret = null;
    _accountNo = null;
    _accessToken = null;
    _tokenExpiry = null;
    _isInitialized = false;
    print('🧹 [GlobalApiCredentials] 자격증명 초기화 완료');
  }

  /// 디버그 정보 출력
  void printDebugInfo() {
    print('🔍 [GlobalApiCredentials] 디버그 정보:');
    print('  - 초기화됨: $_isInitialized');
    print('  - AppKey: ${_appKey?.substring(0, 10)}...');
    print('  - AppSecret: ${_appSecret?.substring(0, 10)}...');
    print('  - AccountNo: $_accountNo');
    print('  - AccessToken: ${_accessToken?.substring(0, 20)}...');
    print('  - 토큰 유효: $hasValidToken');
    print('  - 모든 자격증명: $hasAllCredentials');
  }
}
