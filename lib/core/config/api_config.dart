import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../database/database_helper.dart';

/// API 설정 관리 클래스
class ApiConfig {
  static ApiConfig? _instance;
  static ApiConfig get instance => _instance ??= ApiConfig._();
  
  ApiConfig._();

  // API 설정
  String? _appKey;
  String? _appSecret;
  String? _accountNo;
  bool _isReal = true;
  bool _autoTradingEnabled = false;

  // Getters
  String? get appKey => _appKey;
  String? get appSecret => _appSecret;
  String? get accountNo => _accountNo;
  bool get isReal => _isReal;

  /// API 설정 초기화
  Future<void> initialize() async {
    try {
      print('🔍 API 설정 초기화 시작...');
      
      // 1) Firestore에서 로드 시도 (최우선)
      await _loadFromFirestore();
      
      // 2) Firestore에서 로드 실패 시 SQLite에서 로드
      if (_appKey == null || _appSecret == null || _accountNo == null) {
        print('⚠️ Firestore에서 API 설정 로드 실패 - SQLite에서 로드 시도...');
        final db = await DatabaseHelper.instance.database;
        final rows = await db.query('api_config', limit: 1);
        if (rows.isNotEmpty) {
          final row = rows.first;
          _appKey = row['app_key'] as String?;
          _appSecret = row['app_secret'] as String?;
          _accountNo = row['account_no'] as String?;
          _isReal = (row['is_real'] as int? ?? 1) == 1;
          _autoTradingEnabled = (row['auto_trading_enabled'] as int? ?? 0) == 1;
        }
      }
      
      // 3) 이전 버전 SharedPreferences → SQLite 마이그레이션
      if (_appKey == null || _appSecret == null || _accountNo == null) {
        await _loadFromSharedPreferences();
        if (_appKey != null && _appSecret != null && _accountNo != null &&
            _appKey!.isNotEmpty && _appSecret!.isNotEmpty && _accountNo!.isNotEmpty) {
          // SQLite에 업서트
          final db = await DatabaseHelper.instance.database;
          final now = DateTime.now().millisecondsSinceEpoch;
          await db.insert(
            'api_config',
            {
              'id': 1,
              'app_key': _appKey,
              'app_secret': _appSecret,
              'account_no': _accountNo,
              'is_real': _isReal ? 1 : 0,
              'auto_trading_enabled': _autoTradingEnabled ? 1 : 0,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          print('🔄 SharedPreferences → SQLite 마이그레이션 완료');
        }
      }
      
      // 3) 여전히 비어있으면 기본 설정 로드 (개발용)
      if (_appKey == null || _appSecret == null || _accountNo == null) {
        print('⚠️ 저장된 API 설정 없음 - 기본 설정 로드 시도...');
        await _loadDefaultConfig();
      }
      
      // 4) 자동매매 상태도 SharedPreferences에서 마이그레이션
      if (!_autoTradingEnabled) {
        final prefs = await SharedPreferences.getInstance();
        final isEnabled = prefs.getBool('auto_trading_enabled') ?? false;
        if (isEnabled) {
          _autoTradingEnabled = true;
          await setAutoTradingEnabled(true);
          print('🔄 자동매매 상태 마이그레이션 완료: enabled=true');
        }
      }
      
      print('✅ API 설정 초기화 완료');
      if (_appKey != null) {
        final keyLength = _appKey!.length;
        print('🔑 AppKey: ${_appKey!.substring(0, keyLength > 10 ? 10 : keyLength)}...');
      } else {
        print('🔑 AppKey: null');
      }
      print('📝 AccountNo: $_accountNo');
      print('🌐 IsReal: $_isReal');
      
    } catch (e) {
      print('❌ API 설정 초기화 실패: $e');
      // 오류 발생 시 기본값 사용
      await _loadDefaultConfig();
    }
  }

  /// Firestore에서 API 설정 로드
  Future<void> _loadFromFirestore() async {
    try {
      print('🔍 Firestore에서 API 설정 로드 시작...');
      
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        print('⚠️ 사용자 인증되지 않음 - Firestore 로드 건너뜀');
        return;
      }
      
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
        
        if (_appKey != null && _appSecret != null && _accountNo != null) {
          print('✅ Firestore에서 API 설정 로드 완료');
          print('🔑 AppKey: ${_appKey!.substring(0, _appKey!.length > 10 ? 10 : _appKey!.length)}...');
          print('📝 AccountNo: $_accountNo');
          
          // SQLite에도 동기화 저장
          await _saveToSQLite();
        } else {
          print('⚠️ Firestore API 설정 불완전: appKey=$_appKey, accountNo=$_accountNo');
        }
      } else {
        print('⚠️ Firestore API 설정 문서 없음');
      }
    } catch (e) {
      print('❌ Firestore에서 API 설정 로드 실패: $e');
    }
  }

  /// SQLite에 API 설정 저장
  Future<void> _saveToSQLite() async {
    try {
      if (_appKey != null && _appSecret != null && _accountNo != null) {
        final db = await DatabaseHelper.instance.database;
        await db.insert(
          'api_config',
          {
            'id': 1,
            'app_key': _appKey,
            'app_secret': _appSecret,
            'account_no': _accountNo,
            'is_real': _isReal ? 1 : 0,
            'auto_trading_enabled': _autoTradingEnabled ? 1 : 0,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        print('✅ SQLite에 API 설정 동기화 저장 완료');
      }
    } catch (e) {
      print('❌ SQLite API 설정 저장 실패: $e');
    }
  }

  /// SharedPreferences에서 설정 로드
  Future<void> _loadFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      _appKey = prefs.getString('api_app_key');
      _appSecret = prefs.getString('api_app_secret');
      _accountNo = prefs.getString('api_account_no');
      _isReal = prefs.getBool('api_is_real') ?? true;
      
      if (_appKey != null && _appSecret != null && _accountNo != null) {
        print('✅ SharedPreferences에서 API 설정 로드 완료');
      }
    } catch (e) {
      print('❌ SharedPreferences에서 API 설정 로드 실패: $e');
    }
  }

  /// 기본 설정 로드 (개발용) - 주석/공백 안전 파싱
  Future<void> _loadDefaultConfig() async {
    try {
      // assets/config/api_config.json에서 로드 시도
      final raw = await rootBundle.loadString('assets/config/api_config.json');
      final cleaned = _stripJsonComments(raw);
      if (cleaned.isEmpty) {
        // 빈 파일이면 기본값 유지(서버 저장 경로 사용)
        _appKey = null;
        _appSecret = null;
        _accountNo = null;
        _isReal = true;
        print('ℹ️ 기본 설정 파일이 비어있음: 서버 저장 경로 사용 예정');
        return;
      }
      final config = json.decode(cleaned) as Map<String, dynamic>;
      
      _appKey = config['app_key'];
      _appSecret = config['app_secret'];
      _accountNo = config['account_no'];
      _isReal = config['is_real'] ?? true;
      
      print('✅ 기본 설정 파일에서 API 설정 로드 완료');
    } catch (e) {
      print('❌ 기본 설정 파일 로드 실패: $e');
      // API 키가 설정되지 않음 - 사용자가 직접 입력해야 함
      _appKey = null;
      _appSecret = null;
      _accountNo = null;
      _isReal = true;
      
      print('⚠️ API 키가 설정되지 않음 - 사용자 입력 필요');
    }
  }

  /// JSON 문자열에서 라인/블록 주석 제거 및 BOM/공백 정리
  String _stripJsonComments(String input) {
    // 제거: UTF-8 BOM
    var s = input.replaceFirst(RegExp(r'^\uFEFF'), '');
    // 제거: \r
    s = s.replaceAll('\r', '');
    // 제거: /* ... */ 블록 주석 (멀티라인)
    s = s.replaceAll(RegExp(r"/\*[\s\S]*?\*/"), '');
    // 제거: // ... 라인 주석
    s = s.replaceAllMapped(RegExp(r"(^|\n)\s*//.*"), (m) => m.group(1) ?? '');
    // 앞뒤 공백 정리
    s = s.trim();
    return s;
  }

  /// API 설정 저장
  Future<void> saveConfig({
    required String appKey,
    required String appSecret,
    required String accountNo,
    bool isReal = true,
  }) async {
    try {
      // 메모리 업데이트
      _appKey = appKey;
      _appSecret = appSecret;
      _accountNo = accountNo;
      _isReal = isReal;
      
      // SQLite 업서트
      final db = await DatabaseHelper.instance.database;
      await db.insert(
        'api_config',
        {
          'id': 1,
          'app_key': appKey,
          'app_secret': appSecret,
          'account_no': accountNo,
          'is_real': isReal ? 1 : 0,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      // 이전 버전 SharedPreferences도 동기 저장(호환): 실패해도 무시
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('api_app_key', appKey);
        await prefs.setString('api_app_secret', appSecret);
        await prefs.setString('api_account_no', accountNo);
        await prefs.setBool('api_is_real', isReal);
      } catch (_) {}
      
      print('✅ API 설정 저장 완료 (SQLite)');
    } catch (e) {
      print('❌ API 설정 저장 실패: $e');
    }
  }

  /// 자동매매 상태 설정
  Future<void> setAutoTradingEnabled(bool enabled) async {
    try {
      // 메모리 업데이트
      _autoTradingEnabled = enabled;
      
      // SQLite 업데이트
      final db = await DatabaseHelper.instance.database;
      await db.update(
        'api_config',
        {
          'auto_trading_enabled': enabled ? 1 : 0,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = 1',
      );
      
      // 이전 버전 SharedPreferences도 동기 저장(호환): 실패해도 무시
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('auto_trading_enabled', enabled);
      } catch (_) {}
      
      print('✅ 자동매매 상태 저장 완료: enabled=$enabled');
    } catch (e) {
      print('❌ 자동매매 상태 저장 실패: $e');
    }
  }

  /// 자동매매 상태 조회
  Future<bool> getAutoTradingEnabled() async {
    try {
      // SQLite에서 조회
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query('api_config', limit: 1);
      if (rows.isNotEmpty) {
        final isEnabled = (rows.first['auto_trading_enabled'] as int? ?? 0) == 1;
        _autoTradingEnabled = isEnabled;
        return isEnabled;
      }
      
      // SQLite에 없으면 SharedPreferences에서 마이그레이션 시도
      final prefs = await SharedPreferences.getInstance();
      final isEnabled = prefs.getBool('auto_trading_enabled') ?? false;
      _autoTradingEnabled = isEnabled;
      
      // SQLite에 저장
      await setAutoTradingEnabled(isEnabled);
      
      return isEnabled;
    } catch (e) {
      print('❌ 자동매매 상태 조회 실패: $e');
      return false;
    }
  }

  /// API 설정 삭제
  Future<void> clearConfig() async {
    try {
      // SQLite 삭제
      final db = await DatabaseHelper.instance.database;
      await db.delete('api_config', where: 'id = 1');
      await db.insert('api_config', {
        'id': 1,
        'app_key': null,
        'app_secret': null,
        'account_no': null,
        'is_real': 1,
        'auto_trading_enabled': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
      
      // 구버전 SharedPreferences도 정리(호환)
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('api_app_key');
        await prefs.remove('api_app_secret');
        await prefs.remove('api_account_no');
        await prefs.remove('api_is_real');
      } catch (_) {}
      
      // 메모리 클리어
      _appKey = null;
      _appSecret = null;
      _accountNo = null;
      _isReal = true;
      _autoTradingEnabled = false;
      
      print('✅ API 설정 삭제 완료');
    } catch (e) {
      print('❌ API 설정 삭제 실패: $e');
    }
  }

  /// 설정 유효성 검사
  bool get isValid {
    return _appKey != null && 
           _appSecret != null && 
           _accountNo != null &&
           _appKey!.isNotEmpty &&
           _appSecret!.isNotEmpty &&
           _accountNo!.isNotEmpty;
  }

  /// 데모 모드 확인
  Future<bool> get isDemoMode async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('demo_mode') ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 설정 정보 반환 (디버그용)
  Map<String, dynamic> get configInfo {
    return {
      'appKey': _appKey != null ? '${_appKey!.substring(0, 10)}...' : null,
      'appSecret': _appSecret != null ? '${_appSecret!.substring(0, 10)}...' : null,
      'accountNo': _accountNo,
      'isReal': _isReal,
      'isValid': isValid,
    };
  }
}
