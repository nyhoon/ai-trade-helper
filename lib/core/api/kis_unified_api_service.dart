/// KIS 공식 가이드라인 준수 통일 API 서비스
/// 
/// 모든 모듈(분석탭, 추천종목, 자동매매)이 동일한 API 호출 방식을 사용하도록 통일
/// 공식 가이드라인의 고정 URL, TR ID, 파라미터명, 응답 필드를 정확히 준수
/// 
/// @author AI Assistant
/// @version 1.0.0
/// @since 2024-01-01

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../data/stock_master_parser.dart';
import 'global_api_credentials.dart';
import '../remote/remote_kis_service.dart';

// 확장 기능 import
import 'kis_unified_api_service_account.dart';
import 'kis_unified_api_service_orders.dart';
import 'kis_unified_api_service_charts.dart';
import 'kis_unified_api_service_market.dart';
import 'kis_unified_api_service_websocket.dart';
import 'kis_unified_api_service_extensions.dart';
import '../constants/chart_constants.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../trading/market_time_validator.dart';
import '../data/stock_master_parser.dart';

/// KIS 공식 가이드라인 준수 통일 API 서비스
class KisUnifiedApiService {
  static final KisUnifiedApiService _instance = KisUnifiedApiService._internal();
  factory KisUnifiedApiService() => _instance;
  KisUnifiedApiService._internal();

  late Dio _dio;
  String? _accessToken;
  String? _appKey;
  String? _appSecret;
  String? _accountNumber;
  Future<String>? _tokenFuture; // 토큰 발급 중복 방지용

  // 간단한 서킷 브레이커: endpoint+symbol 기준으로 오류 반복 차단
  final Map<String, int> _cbFailCount = {};
  final Map<String, DateTime> _cbBlockedUntil = {};
  bool _isBlocked(String key) {
    // 나스닥 데이터는 필수이므로 Circuit Breaker 적용 안함
    if (key.startsWith('ovrs_')) {
      return false;
    }
    
    final until = _cbBlockedUntil[key];
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _cbBlockedUntil.remove(key);
      _cbFailCount.remove(key);
      return false;
    }
    return true;
  }
  void _onCallFailure(String key, {int threshold = 2, Duration block = const Duration(minutes: 5)}) {
    // 나스닥 데이터는 필수이므로 Circuit Breaker 실패 처리 안함
    if (key.startsWith('ovrs_')) {
      return;
    }
    
    final n = (_cbFailCount[key] ?? 0) + 1;
    _cbFailCount[key] = n;
    if (n >= threshold) {
      _cbBlockedUntil[key] = DateTime.now().add(block);
      print('⛔ CB OPEN $key for ${block.inMinutes}m (fail=$n)');
    }
  }
  void _onCallSuccess(String key) {
    // 나스닥 데이터는 필수이므로 Circuit Breaker 성공 처리 안함
    if (key.startsWith('ovrs_')) {
      return;
    }
    
    _cbFailCount.remove(key);
    _cbBlockedUntil.remove(key);
  }

  // ===== 차트 캐시/인플라이트 관리 =====
  final Map<String, List<Map<String, dynamic>>> _chartCache = {};
  final Map<String, DateTime> _chartCacheAt = {};
  final Map<String, Future<List<Map<String, dynamic>>>> _inflightChart = {};
  static const Duration _chartTtl = Duration(minutes: 30);
  String _chartKey(String stockCode, String periodCode, int count) => 'chart:$stockCode:$periodCode:$count';
  bool _isFresh(DateTime? ts) => ts != null && DateTime.now().difference(ts) < _chartTtl;

  /// 초기화 (GlobalApiCredentials 사용)
  Future<void> initialize({
    String? appKey,
    String? appSecret,
    String? accountNumber,
  }) async {
    // GlobalApiCredentials에서 자격증명 가져오기
    if (GlobalApiCredentials.instance.isInitialized && GlobalApiCredentials.instance.hasAllCredentials) {
      _appKey = GlobalApiCredentials.instance.appKey;
      _appSecret = GlobalApiCredentials.instance.appSecret;
      _accountNumber = GlobalApiCredentials.instance.accountNo;
      print('✅ [KisUnifiedApiService] GlobalApiCredentials에서 자격증명 로드');
    } else {
      // 폴백: 파라미터에서 가져오기
      _appKey = appKey;
      _appSecret = appSecret;
      _accountNumber = accountNumber;
      print('⚠️ [KisUnifiedApiService] GlobalApiCredentials 미사용, 파라미터 사용');
    }

    _dio = Dio(BaseOptions(
      baseUrl: 'https://openapi.koreainvestment.com:9443',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
      },
    ));

    // 토큰 로드 시도
    await _loadToken();
  }

  /// 토큰 로드
  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString('kis_access_token');
    
    if (_accessToken != null) {
      print('✅ 기존 토큰 로드: ${_accessToken!.substring(0, 20)}...');
    }
  }

  /// 토큰 저장
  Future<void> _saveToken(String token) async {
    _accessToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('kis_access_token', token);
    print('✅ 토큰 저장 완료');
  }

  /// 인증 토큰 발급
  Future<String> _getAccessToken() async {
    // 기존 토큰이 있으면 먼저 사용
    if (_accessToken != null) {
      return _accessToken!;
    }

    // 이미 토큰 발급 중이면 기다림
    if (_tokenFuture != null) {
      print('⏳ 토큰 발급 대기 중...');
      return await _tokenFuture!;
    }

    // 새 토큰 발급 시작
    _tokenFuture = _requestNewToken();
    try {
      final token = await _tokenFuture!;
      return token;
    } finally {
      _tokenFuture = null; // 완료 후 초기화
    }
  }

  /// 실제 토큰 발급 요청
  Future<String> _requestNewToken() async {
    print('🔐 인증 토큰 발급 시작...');
    
    final response = await _dio.post(
      '/oauth2/tokenP',
      data: {
        'grant_type': 'client_credentials',
        'appkey': _appKey,
        'appsecret': _appSecret,
      },
    );

    if (response.statusCode == 200) {
      final data = response.data;
      final token = data['access_token'];
      if (token != null) {
        await _saveToken(token);
        return token;
      }
    }
    
    throw Exception('토큰 발급 실패: ${response.data}');
  }

  /// 토큰 만료 시 새 토큰 발급
  Future<String> _refreshToken() async {
    print('🔄 토큰 만료 감지, 새 토큰 발급 중...');
    _accessToken = null; // 기존 토큰 삭제
    _tokenFuture = null; // 기존 토큰 발급 요청도 초기화
    return await _getAccessToken();
  }

  /// 인증된 GET 요청
  Future<Response> authedGet(
    String path,
    Map<String, dynamic> params, {
    required String trId,
  }) async {
    String token = await _getAccessToken();
    
    // 디버그 로그 추가
    print('🔍 [API] 요청 정보:');
    print('  - Path: $path');
    print('  - TR_ID: $trId');
    print('  - Params: $params');
    print('  - Token: ${token.length > 20 ? '${token.substring(0, 20)}...' : token}');
    print('  - AppKey: ${_appKey != null && _appKey!.length > 10 ? '${_appKey!.substring(0, 10)}...' : _appKey ?? 'null'}');
    
    try {
      final response = await _dio.get(
        path,
        queryParameters: params,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'appkey': _appKey,
            'appsecret': _appSecret,
            'tr_id': trId,
            'custtype': 'P',
          },
        ),
      );
      
      // 토큰 만료 체크
      if (response.data != null && response.data['msg_cd'] == 'EGW00123') {
        print('🔄 토큰 만료 감지, 새 토큰으로 재시도...');
        token = await _refreshToken();
        
        // 새 토큰으로 재시도
        return await _dio.get(
          path,
          queryParameters: params,
          options: Options(
            headers: {
              'Authorization': 'Bearer $token',
              'appkey': _appKey,
              'appsecret': _appSecret,
              'tr_id': trId,
              'custtype': 'P',
            },
          ),
        );
      }
      
      return response;
    } catch (e) {
      // DioException에서 토큰 만료 체크
      if (e is DioException && e.response?.data != null) {
        final responseData = e.response!.data;
        if (responseData['msg_cd'] == 'EGW00123') {
          print('🔄 토큰 만료 감지, 새 토큰으로 재시도...');
          token = await _refreshToken();
          
          // 새 토큰으로 재시도
          return await _dio.get(
            path,
            queryParameters: params,
            options: Options(
              headers: {
                'Authorization': 'Bearer $token',
                'appkey': _appKey,
                'appsecret': _appSecret,
                'tr_id': trId,
                'custtype': 'P',
              },
            ),
          );
        }
        
        // 토큰 발급 제한 오류는 재시도하지 않음
        if (responseData['error_code'] == 'EGW00133') {
          print('❌ [통일API] 토큰 발급 제한 오류 - 재시도하지 않음');
          rethrow;
        }
      }
      rethrow;
    }
  }

  /// 인증된 POST 요청
  Future<Response> authedPost(
    String path,
    Map<String, dynamic> data, {
    required String trId,
  }) async {
    final token = await _getAccessToken();
    
    return await _dio.post(
      path,
      data: data,
      options: Options(
        headers: {
          'Authorization': 'Bearer $token',
          'appkey': _appKey,
          'appsecret': _appSecret,
          'tr_id': trId,
          'custtype': 'P',
        },
      ),
    );
  }

  /// ========================================
  /// 1. 국내주식 현재가 API (공식 가이드라인)
  /// ========================================
  
  /// 국내주식 현재가 조회
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/domestic-stock/v1/quotations/inquire-price
  /// - TR ID: FHKST01010100 (실전/모의 동일)
  /// - 필수 파라미터: env_dv, fid_cond_mrkt_div_code, fid_input_iscd
  /// - 응답 필드: stck_prpr, stck_prdy_clpr, acml_vol, stck_hgpr, stck_lwpr, stck_oprc, prdy_vrss, prdy_ctrt
  Future<Map<String, dynamic>?> getDomesticStockPrice({
    required String stockCode,
    String marketCode = 'J', // J: KRX, NX: NXT, UN: 통합
  }) async {
    const maxRetries = 3;
    const retryDelay = Duration(seconds: 2);
    
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('📊 [통일API] 국내주식 현재가 조회: $stockCode (시장: $marketCode) - 시도 $attempt/$maxRetries');
        
        final response = await authedGet(
          '/uapi/domestic-stock/v1/quotations/inquire-price',
          {
            'FID_COND_MRKT_DIV_CODE': marketCode,
            'FID_INPUT_ISCD': stockCode,
          },
          trId: 'FHKST01010100',
        );

        if (response.statusCode == 200 && response.data['rt_cd'] == '0') {
          final output = response.data['output'];
          if (output != null) {
            print('✅ [통일API] 국내주식 현재가 조회 성공: $stockCode');
            final parsed = _parseDomesticStockPriceResponse(output);
            // 클라이언트 Firestore 쓰기 금지: 서버 전용으로 이전됨
            return parsed;
          }
        }
        
        // 500 오류인 경우 재시도
        if (response.statusCode == 500 && attempt < maxRetries) {
          print('⚠️ [통일API] 500 오류 발생, ${retryDelay.inSeconds}초 후 재시도...');
          await Future.delayed(retryDelay);
          continue;
        }
        
        // 에러 응답 상세 로깅
        print('❌ [통일API] 국내주식 현재가 조회 실패:');
        print('  - Status Code: ${response.statusCode}');
        print('  - Response Data: ${response.data}');
        print('  - Headers: ${response.headers}');
        
        return null;
      } catch (e) {
        print('❌ [통일API] 국내주식 현재가 조회 오류 (시도 $attempt/$maxRetries): $e');
        
        // 500 오류인 경우 재시도
        if (e.toString().contains('500') && attempt < maxRetries) {
          print('⚠️ [통일API] 500 오류 발생, ${retryDelay.inSeconds}초 후 재시도...');
          await Future.delayed(retryDelay);
          continue;
        }
        
        if (attempt == maxRetries) {
          return null;
        }
      }
    }
    
    return null;
  }

  /// 국내주식 현재가 응답 파싱 (원본 필드명 사용)
  Map<String, dynamic> _parseDomesticStockPriceResponse(Map<String, dynamic> output) {
    final currentPrice = parseDouble(output['stck_prpr']);
    final change = parseDouble(output['prdy_vrss']);
    final prevCloseFromApi = parseDouble(output['stck_prdy_clpr']);
    
    // 전일 종가가 0이면 현재가에서 전일대비를 빼서 계산
    final prevClose = prevCloseFromApi > 0 ? prevCloseFromApi : (currentPrice - change);
    
    return {
      'prpr': currentPrice, // 현재가
      'stck_prdy_clpr': prevClose, // 전일가 (계산된 값 사용)
      'acml_vol': parseInt(output['acml_vol']), // 거래량
      'high': parseDouble(output['stck_hgpr']), // 고가
      'low': parseDouble(output['stck_lwpr']), // 저가
      'open': parseDouble(output['stck_oprc']), // 시가
      'diff': change, // 전일대비
      'rate': parseDouble(output['prdy_ctrt']), // 전일대비율
      'stockCode': output['fid_input_iscd'] ?? '',
      'stockName': output['hts_kor_isnm'] ?? '',
    };
  }

  /// ========================================
  /// 2. 해외주식 현재가 API (공식 가이드라인)
  /// ========================================
  

  /// 해외주식 현재가 조회 (1호가)
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/overseas-price/v1/quotations/inquire-asking-price
  /// - TR ID: HHDFS76200100 (실전/모의 동일)
  /// - 필수 파라미터: auth, excd, symb
  /// - 응답 필드: output1, output2, output3
  Future<Map<String, dynamic>?> getOverseasStockPrice({
    required String symbol,
    required String exchangeCode, // NAS: 나스닥, NYS: 뉴욕, HKS: 홍콩
  }) async {
    try {
      print('🌍 [통일API] 해외주식 현재가 조회: $symbol (거래소: $exchangeCode)');
      
      final response = await authedGet(
        '/uapi/overseas-price/v1/quotations/inquire-asking-price',
        {
          'AUTH': '',
          'EXCD': exchangeCode,
          'SYMB': symbol,
        },
        trId: 'HHDFS76200100', // 해외주식 현재가 1호가
      );

      print('🔍 [API] 응답 상태: ${response.statusCode}');
      print('🔍 [API] 응답 데이터: ${response.data}');
      
      if (response.statusCode == 200) {
        print('🔍 [API] HTTP 200 응답 확인');
        if (response.data['rt_cd'] == '0') {
          print('✅ [API] KIS API 성공 응답');
        } else {
          print('❌ [API] KIS API 오류: ${response.data['rt_cd']} - ${response.data['msg1']}');
          return null;
        }
      } else {
        print('❌ [API] HTTP 오류: ${response.statusCode}');
        return null;
      }
      
      if (response.statusCode == 200 && response.data['rt_cd'] == '0') {
        final output1 = response.data['output1'];
        if (output1 != null) {
          print('✅ [API] 해외주식 현재가 조회 성공: $symbol (거래소: $exchangeCode)');
          print('🔍 [API] output1 데이터: $output1');
          
          // 1차: 1호가 응답 파싱
          final parsed = await _parseOverseasStockPriceResponse(output1, exchangeCode);
          print('🔍 [API] 파싱된 데이터: $parsed');

          // Firestore prices 업서트(denormalize)
          try {
            final nowMs = DateTime.now().millisecondsSinceEpoch;
            final market = MarketTimeValidator.instance.getMarketFromSymbol(symbol);
            // 해외 종목명 보강: 응답 후보키 → 마스터 → 티커
            String name = '';
            final candidates = [
              parsed['stockName'],
              parsed['name'],
              parsed['shortName'],
              parsed['hts_kor_isnm'],
            ];
            for (final c in candidates) {
              final s = (c ?? '').toString();
              if (s.trim().isNotEmpty) { name = s; break; }
            }
            if (name.isEmpty) {
              name = (StockMasterParser().getStockInfo(symbol)?['name']?.toString() ?? '').trim();
            }
            if (name.isEmpty) name = symbol; // 최후 폴백

            // Firestore 직접 쓰기 비활성화 - 서버 Functions를 통해서만 데이터 저장
            print('📊 $symbol: 현재가 데이터는 서버 Functions를 통해 저장됩니다');
            print('⚠️ 클라이언트에서 Firestore 직접 쓰기 비활성화됨 (권한 문제 방지)');
          } catch (e) {
            print('⚠️ Firestore prices 업서트 실패(overseas): $e');
          }

          // 보조: 시가/고가/저가가 없으면 price API로 보강
          final hasOhl = (parsed['open'] ?? 0.0) != 0.0 ||
                        (parsed['high'] ?? 0.0) != 0.0 ||
                        (parsed['low'] ?? 0.0) != 0.0;
          if (!hasOhl) {
            try {
              final priceResp = await authedGet(
                '/uapi/overseas-price/v1/quotations/price',
                {
                  'auth': '',
                  'excd': exchangeCode,
                  'symb': symbol,
                  'env_dv': 'real',
                },
                trId: 'HHDFS00000300',
              );
              if (priceResp.statusCode == 200 && priceResp.data['rt_cd'] == '0') {
                final priceOut = priceResp.data['output'];
                if (priceOut != null) {
                  final open = parseDouble(priceOut['open']);
                  final high = parseDouble(priceOut['high']);
                  final low = parseDouble(priceOut['low']);
                  final prevClose2 = parseDouble(priceOut['previousClose'] ?? priceOut['prevClose']);
                  final volume2 = parseInt(priceOut['tvol'] ?? priceOut['acml_vol'] ?? priceOut['volume']);
                  final totalValue2 = parseDouble(priceOut['totalValue'] ?? priceOut['tradeAmount']);
                  double? changeAmt2 = parseDouble(priceOut['change']);
                  double? changeRt2 = parseDouble(priceOut['changeRate'] ?? priceOut['pctChange']);
                  // 보정 계산
                  final lastNow = parseDouble(priceOut['last']) ?? parsed['last'];
                  if ((changeAmt2 == null || changeAmt2 == 0) && lastNow != null && prevClose2 != null) {
                    changeAmt2 = lastNow - prevClose2;
                  }
                  if ((changeRt2 == null || changeRt2 == 0) && lastNow != null && prevClose2 != null && prevClose2 != 0) {
                    changeRt2 = ((lastNow - prevClose2) / prevClose2) * 100;
                  }
                  // Firestore 직접 쓰기 비활성화 - 서버 Functions를 통해서만 데이터 저장
                  print('📊 $symbol: 보조 현재가 데이터는 서버 Functions를 통해 저장됩니다');
                }
              }
            } catch (_) {}
          }

          // 최종 Fallback: 여전히 주요 값이 0이면 일봉 2개로 보정
          try {
            final chart = await getDailyChart(symbol, count: 2);
            if (chart.isNotEmpty) {
              final last = chart.first;
              final prev = chart.length > 1 ? chart[1] : null;
              final closeNow = parseDouble(last['close'] ?? last['prpr'] ?? last['last']);
              final volNow = parseInt(last['volume']);
              final prevClose = prev != null ? parseDouble(prev['close']) : null;
              double? diff2;
              double? rate2;
              if (closeNow != null && prevClose != null) {
                diff2 = closeNow - prevClose;
                if (prevClose != 0) rate2 = (diff2 / prevClose) * 100;
              }
              await FirebaseFirestore.instance.collection('prices').doc(symbol).set({
                'current_price': closeNow ?? parsed['last'] ?? 0,
                'prev_close': prevClose ?? parsed['prevClose'] ?? 0,
                'volume': volNow ?? parsed['volume'] ?? 0,
                'change_amount': diff2 ?? (parsed['last'] != null && parsed['prevClose'] != null ? (parsed['last'] - parsed['prevClose']) : 0),
                'change_rate': rate2 ?? ((parsed['last'] != null && parsed['prevClose'] != null && parsed['prevClose'] != 0) ? ((parsed['last'] - parsed['prevClose']) / parsed['prevClose']) * 100 : 0),
              }, SetOptions(merge: true));
            }
          } catch (e) {
            print('⚠️ overseas chart fallback 실패: $e');
          }

          return parsed;
        }
      }
      
      print('❌ [API] 해외주식 현재가 조회 실패:');
      print('  - Status Code: ${response.statusCode}');
      print('  - Response Data: ${response.data}');
      return null;
    } catch (e) {
      print('❌ [API] 해외주식 현재가 조회 오류: $e');
      return null;
    }
  }

  /// 해외주식 현재가 응답 파싱 (기존 성공하는 API 구조 참고)
  Future<Map<String, dynamic>> _parseOverseasStockPriceResponse(Map<String, dynamic> output, String exchangeCode) async {
    // 기존 성공하는 API 구조 참고: output 필드에서 직접 추출
    final currentPrice = parseDouble(output['last'] ?? output['prpr'] ?? 0);
    final openPrice = parseDouble(output['open'] ?? 0);
    final highPrice = parseDouble(output['high'] ?? 0);
    final lowPrice = parseDouble(output['low'] ?? 0);
    final prevClose = parseDouble(output['base'] ?? output['stck_prdy_clpr'] ?? 0);
    
    // 등락과 등락률 계산
    final diff = currentPrice - prevClose;
    final rate = prevClose > 0 ? ((diff / prevClose) * 100) : 0.0;
    
    // 디버깅: 해외주식 필드 매핑 로깅
    final symbol = output['code'] ?? output['symb'] ?? '';
    print('🔍 [해외주식 필드 매핑] API 응답 원본:');
    print('  - symbol: $symbol');
    
    // NVD 특별 로깅
    if (symbol.toUpperCase() == 'NVD') {
      print('🔍 [NVD 현재가 API 응답] 상세 분석:');
      print('  - output keys: ${output.keys.toList()}');
      print('  - output values: $output');
      print('  - 거래량 관련 필드들:');
      print('    - tvol: ${output['tvol']}');
      print('    - pvol: ${output['pvol']}');
      print('    - acml_vol: ${output['acml_vol']}');
      print('    - volume: ${output['volume']}');
      print('    - bvol: ${output['bvol']}');
      print('    - avol: ${output['avol']}');
      print('    - bdvl: ${output['bdvl']}');
      print('    - advl: ${output['advl']}');
    }
    
    // PLTZ 특별 로깅
    if (symbol.toUpperCase() == 'PLTZ') {
      print('🔍 [PLTZ 현재가 API 응답] 상세 분석:');
      print('  - output keys: ${output.keys.toList()}');
      print('  - output values: $output');
      print('  - 거래량 관련 필드들:');
      print('    - tvol: ${output['tvol']}');
      print('    - pvol: ${output['pvol']}');
      print('    - acml_vol: ${output['acml_vol']}');
      print('    - volume: ${output['volume']}');
      print('    - bvol: ${output['bvol']}');
      print('    - avol: ${output['avol']}');
      print('    - bdvl: ${output['bdvl']}');
      print('    - advl: ${output['advl']}');
    }
    
    // 거래량: inquire-asking-price API 특성 반영
    // 해외주식 API는 실시간 거래량을 제공하지 않음 (정규장 시간 외)
    // API 응답에서 사용 가능한 거래량 필드들 확인
    int volume = parseInt(output['tvol'] ?? output['pvol'] ?? output['acml_vol'] ?? output['volume'] ?? output['bvol'] ?? output['avol'] ?? output['bdvl'] ?? output['advl'] ?? 0);
    
    // 해외주식 거래량이 0이면 전일거래량 사용 (마지막 거래량 표시)
    if (volume == 0) {
      // 전일거래량이나 마지막 거래량 데이터가 있다면 사용
      final prevVolume = parseInt(output['pvol'] ?? output['prev_vol'] ?? 0);
      if (prevVolume > 0) {
        volume = prevVolume;
        print('ℹ️ [해외주식] 당일거래량 0 → 전일거래량 사용: $symbol (거래량: $volume)');
      } else {
        // 정규장 시간 외에는 거래량 0이 정상
        print('ℹ️ [해외주식] 거래량 0은 정상 (정규장 시간 외)');
      }
    }
    
    // 해외주식 공통 처리: 차트 데이터에서 최신 거래량 가져오기 (항상 실행)
    try {
      print('🔍 [해외주식] 차트 데이터에서 최신 거래량 조회 시도: $symbol');
      final chartData = await getOverseasDailyChart(symbol: symbol, exchangeCode: exchangeCode, count: 100);
      if (chartData.isNotEmpty) {
        // 차트 데이터에서 최신 데이터(마지막 데이터) 사용
        final latestChartData = chartData.last;
        final chartTvol = parseInt(latestChartData['tvol'] ?? 0);
        final chartVolume = parseInt(latestChartData['volume'] ?? 0);
        final chartAcmlVol = parseInt(latestChartData['acml_vol'] ?? 0);
        
        print('🔍 [해외주식] 차트 데이터 거래량 필드들:');
        print('  - 차트 데이터 개수: ${chartData.length}');
        print('  - 최신 데이터: ${latestChartData}');
        print('  - tvol: $chartTvol');
        print('  - volume: $chartVolume');
        print('  - acml_vol: $chartAcmlVol');
        
        // tvol이 있으면 우선 사용, 없으면 volume, 마지막으로 acml_vol
        final latestVolume = chartTvol > 0 ? chartTvol : (chartVolume > 0 ? chartVolume : chartAcmlVol);
        
        if (latestVolume > 0) {
          volume = latestVolume;
          print('✅ [해외주식] 차트에서 거래량 조회 성공: $symbol (거래량: $volume)');
        }
      }
      
      // 해외주식 차트 데이터 서버 저장 (RemoteKisService를 통한 호출)
      if (chartData.isNotEmpty) {
        print('🔍 [해외주식] 차트 데이터 서버 저장 시도: $symbol');
        try {
          // RemoteKisService를 통한 차트 데이터 저장
          final uid = FirebaseAuth.instance.currentUser?.uid ?? 'debug-user';
          final success = await RemoteKisService.instance.ensureChartAndAnalyze(
            uid: uid,
            symbol: symbol,
          );
          if (success) {
            print('✅ [해외주식] 차트 데이터 서버 저장 성공: $symbol');
          } else {
            print('❌ [해외주식] 차트 데이터 서버 저장 실패: $symbol');
          }
        } catch (e) {
          print('❌ [해외주식] 차트 데이터 서버 저장 실패: $symbol - $e');
          print('ℹ️ [해외주식] 서버 Functions 없음 - 로컬 차트 데이터만 사용');
        }
      }
    } catch (e) {
      print('⚠️ [해외주식] 차트 거래량 조회 실패: $symbol - $e');
    }
    print('  - output keys: ${output.keys.toList()}');
    print('  - last: ${output['last']}');
    print('  - prpr: ${output['prpr']}');
    print('  - base: ${output['base']}');
    print('  - acml_vol: ${output['acml_vol']}');
    print('  - volume: ${output['volume']}');
    print('🔍 [해외주식 필드 매핑] 파싱 결과:');
    print('  - 현재가: $currentPrice');
    print('  - 전일가: $prevClose');
    print('  - 거래량: $volume');
    print('  - 등락: $diff');
    print('  - 등락률: ${rate.toStringAsFixed(2)}%');
    
    return {
      'prpr': currentPrice, // 현재가
      'stck_prdy_clpr': prevClose, // 전일가
      'acml_vol': volume, // 거래량 (기존 성공하는 API 구조 참고)
      'tvol': parseInt(output['tvol'] ?? 0), // 총 거래량 (우선 사용)
      'open': openPrice, // 시가
      'high': highPrice, // 고가
      'low': lowPrice, // 저가
      'diff': diff, // 전일대비 (계산)
      'rate': rate, // 등락률 (계산)
      'tradeAmount': parseDouble(output['tamt'] ?? output['tradeAmount']), // 거래대금
      'stockCode': symbol,
      'stockName': (output['name'] ?? output['hts_kor_isnm'] ?? symbol).toString(),
    };
  }

  /// ========================================
  /// 3. 국내주식 일별 차트 API (공식 가이드라인)
  /// ========================================
  
  /// 국내주식 일별 차트 조회
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/domestic-stock/v1/quotations/inquire-daily-itemchartprice
  /// - TR ID: FHKST03010100 (실전/모의 동일)
  /// - 필수 파라미터: fid_cond_mrkt_div_code, fid_input_iscd, fid_input_date_1, fid_input_date_2, fid_period_div_code, fid_org_adj_prc
  /// - 응답 필드: output1, output2
  Future<List<Map<String, dynamic>>> getDomesticDailyChart({
    required String stockCode,
    String marketCode = 'J', // J: KRX
    String periodCode = 'D', // D: 일, W: 주, M: 월
    String adjustedPrice = '1', // 0: 수정주가미반영, 1: 수정주가반영
    int count = ChartConstants.CHART_MIN_BARS,
  }) async {
    try {
      print('📈 [통일API] 국내주식 일별 차트 조회: $stockCode (기간: $periodCode, 개수: $count)');
      
      // 날짜 설정 개선 - 거래일 기준으로 조정
      final now = DateTime.now();
      
      // 주말인 경우 금요일로 조정
      DateTime endDate;
      if (now.weekday == DateTime.saturday) {
        endDate = now.subtract(const Duration(days: 1)); // 금요일
      } else if (now.weekday == DateTime.sunday) {
        endDate = now.subtract(const Duration(days: 2)); // 금요일
      } else {
        endDate = now;
      }
      
      final endDateStr = '${endDate.year}${endDate.month.toString().padLeft(2, '0')}${endDate.day.toString().padLeft(2, '0')}';
      final startDateStr = endDate.subtract(Duration(days: count + 10)).toString().replaceAll('-', '').substring(0, 8); // 버퍼 추가
      
      print('📅 [API] 날짜 범위: $startDateStr ~ $endDateStr (요청: $count일)');
      
      final response = await authedGet(
        '/uapi/domestic-stock/v1/quotations/inquire-daily-itemchartprice',
        {
          'FID_COND_MRKT_DIV_CODE': marketCode,
          'FID_INPUT_ISCD': stockCode,
          'FID_INPUT_DATE_1': startDateStr,
          'FID_INPUT_DATE_2': endDateStr,
          'FID_PERIOD_DIV_CODE': periodCode,
          'FID_ORG_ADJ_PRC': adjustedPrice,
        },
        trId: 'FHKST03010100',
      );

      if (response.statusCode == 200 && response.data['rt_cd'] == '0') {
        final output2 = response.data['output2'];
        if (output2 != null && output2 is List) {
          // API 응답을 과거→최신 순서로 정렬
          final sortedOutput = List.from(output2);
          sortedOutput.sort((a, b) {
            final dateA = a['stck_bsop_date'] ?? a['date'] ?? '';
            final dateB = b['stck_bsop_date'] ?? b['date'] ?? '';
            return dateA.compareTo(dateB); // 과거→최신 순서
          });
          
          print('🔍 [국내주식 정렬 후] 첫 번째 데이터: ${sortedOutput.first}');
          print('🔍 [국내주식 정렬 후] 마지막 데이터: ${sortedOutput.last}');
          
          final chartData = sortedOutput.take(count).map((item) => _parseDomesticChartItem(item)).toList();
          print('✅ [통일API] 국내주식 일별 차트 조회 성공: ${chartData.length}개');
          return chartData;
        }
      }
      
      print('❌ [통일API] 국내주식 일별 차트 조회 실패: ${response.data}');
      return [];
    } catch (e) {
      print('❌ [통일API] 국내주식 일별 차트 조회 오류: $e');
      return [];
    }
  }

  /// 국내주식 차트 아이템 파싱 (공식 필드명 사용)
  Map<String, dynamic> _parseDomesticChartItem(Map<String, dynamic> item) {
    return {
      'date': item['stck_bsop_date'] ?? '', // 날짜
      'open': parseDouble(item['stck_oprc']), // 시가
      'high': parseDouble(item['stck_hgpr']), // 고가
      'low': parseDouble(item['stck_lwpr']), // 저가
      'close': parseDouble(item['stck_clpr']), // 종가
      'volume': parseInt(item['acml_vol']), // 거래량
    };
  }

  /// ========================================
  /// 4. 해외주식 일별시세 API (공식 가이드라인)
  /// ========================================
  
  /// 해외주식 일별시세 조회
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/overseas-price/v1/quotations/dailyprice
  /// - TR ID: HHDFS76240000 (실전/모의 동일)
  /// - 필수 파라미터: EXCD, SYMB, GUBN, BYMD, MODP
  /// - 응답 필드: output
  Future<List<Map<String, dynamic>>> getOverseasDailyChart({
    required String symbol,
    required String exchangeCode, // NAS: 나스닥
    String periodCode = 'D', // D: 일, W: 주, M: 월, Y: 년
    int count = ChartConstants.CHART_MIN_BARS,
  }) async {
    try {
      print('📈 [통일API] 해외주식 일별시세 조회: $symbol (거래소: $exchangeCode, 기간: $periodCode)');

      final cbKey = 'ovrs_chart:$symbol:$periodCode';
      if (_isBlocked(cbKey)) {
        print('⛔ CB BLOCKED $cbKey - skip call');
        return [];
      }

      // 날짜 설정 (오늘 기준) - 더 정확한 계산
      final now = DateTime.now();
      final endDate = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      
      // 더 넉넉하게 날짜 범위 설정 (주말/공휴일 고려)
      final startDateTime = now.subtract(Duration(days: count + 30));
      final startDate = '${startDateTime.year}${startDateTime.month.toString().padLeft(2, '0')}${startDateTime.day.toString().padLeft(2, '0')}';

        // 해외주식 일별 차트 API - 올바른 파라미터 사용
        print('🔍 [API] 요청 정보:');
        print('  - Path: /uapi/overseas-price/v1/quotations/inquire-daily-chartprice');
        print('  - TR_ID: FHKST03030100');
        print('  - Params: {FID_COND_MRKT_DIV_CODE: N, FID_INPUT_ISCD: $symbol, FID_INPUT_DATE_1: $startDate, FID_INPUT_DATE_2: $endDate, FID_PERIOD_DIV_CODE: $periodCode}');
        print('  - 실제 날짜 범위: $startDate ~ $endDate (${count + 30}일 범위)');
        
        // 거래소별 시장구분코드 시도 (API 문서에 따라 다를 수 있음)
        Response? response;
        
        // 1. 해외 ETF 종목인지 확인 (PLTZ = DEFIANCE PLTR DAILY -2X)
        // 해외 ETF는 일반 해외주식 API를 사용하되, 특별한 처리가 필요할 수 있음
        final isOverseasETF = symbol.length <= 5 && 
                             (symbol.toUpperCase().endsWith('Z') || 
                              symbol.toUpperCase().contains('X') ||
                              ['PLTZ', 'NVDQ', 'NVD'].contains(symbol.toUpperCase()));
        
        // 2. 해외 ETF는 일반 해외주식과 동일하게 거래소 코드 사용
        final marketCode = exchangeCode; // 해외 ETF도 'N' 또는 거래소 코드 사용
        
        print('🔍 [API] 해외 ETF 여부: $isOverseasETF, 시장코드: $marketCode');
        
        response = await authedGet(
          '/uapi/overseas-price/v1/quotations/dailyprice',
          {
            'EXCD': exchangeCode, // 거래소코드 (NAS, NYS, AMS)
            'SYMB': symbol, // 종목코드
            'GUBN': '0', // 0: 일별, 1: 주별, 2: 월별
            'BYMD': '', // 조회기준일자 (공백시 최신)
            'MODP': '1', // 0: 수정전, 1: 수정후
          },
          trId: 'HHDFS76240000', // 해외주식 일별시세 TR ID
        );
        
        // 2. 첫 번째 시도가 실패하면 다른 거래소로 재시도
        if (response?.data['rt_cd'] != '0' || (response?.data['output'] as List?)?.isEmpty == true) {
          print('🔄 [API] $exchangeCode 실패, NYS로 재시도');
          response = await authedGet(
            '/uapi/overseas-price/v1/quotations/dailyprice',
            {
              'EXCD': 'NYS', // 뉴욕거래소로 재시도
              'SYMB': symbol, // 종목코드
              'GUBN': '0', // 0: 일별
              'BYMD': '', // 조회기준일자 (공백시 최신)
              'MODP': '1', // 1: 수정후
            },
            trId: 'HHDFS76240000', // 해외주식 일별시세 TR ID
          );
        }
        
        // 3. dailyprice API는 최신 데이터를 기본 제공하므로 추가 재시도 불필요
        
        // 4. ETF 종목인지 확인하고 경고 표시
        if (response?.data['rt_cd'] == '0' && (response?.data['output2'] as List?)?.isEmpty == true) {
          if (symbol.contains('ETF') || symbol.endsWith('Z') || symbol.endsWith('X')) {
            print('⚠️ [API] ETF 종목 ($symbol) - 차트 데이터가 제한적일 수 있습니다');
          } else {
            print('❌ [API] 일반 종목 ($symbol) - 데이터 조회 실패');
          }
        }

        print('🔍 [API] 응답 상태: ${response.statusCode}');
        print('🔍 [API] 응답 데이터: ${response.data}');
        
        // 상세 응답 분석
        if (response.data != null) {
          print('🔍 [API] 응답 분석:');
          print('  - rt_cd: ${response.data['rt_cd']}');
          print('  - msg_cd: ${response.data['msg_cd']}');
          print('  - msg1: ${response.data['msg1']}');
          print('  - output1: ${response.data['output1']}');
          print('  - output2: ${response.data['output2']}');
        }
        
        if (response.statusCode == 200 && (response.data['rt_cd'] == '0' || response.data['rt_cd'] == 0)) {
          // 디버깅: 실제 API 응답 확인
        print('🔍 [디버깅] 해외주식 일별시세 API 응답 구조:');
        print('🔍 response.data 키들: ${response.data.keys.toList()}');
          
          // output2 배열에서 일별시세 데이터 추출 (dailyprice API)
          final output = response.data['output2'];
          print('🔍 [디버깅] output2 타입: ${output.runtimeType}');
          print('🔍 [디버깅] output2 값: $output');
          
          if (output != null && output is List && output.isNotEmpty) {
            print('🔍 [디버깅] 해외주식 일별시세 API 응답 구조 (output):');
            print('🔍 output 길이: ${output.length}');
            print('🔍 첫 번째 아이템 키들: ${output.first.keys.toList()}');
            print('🔍 첫 번째 아이템 값들: ${output.first}');
            
            // NVD 특별 로깅
            if (symbol.toUpperCase() == 'NVD') {
              print('🔍 [NVD 차트 API 응답] 상세 분석:');
              for (int i = 0; i < output.length && i < 3; i++) {
                final item = output[i];
                print('  - Item $i:');
                print('    - date: ${item['xymd']}');
                print('    - close: ${item['clos']}');
                print('    - tvol: ${item['tvol']}');
                print('    - volume: ${item['volume']}');
                print('    - acml_vol: ${item['acml_vol']}');
                print('    - all keys: ${item.keys.toList()}');
              }
            }
            
            // PLTZ 특별 로깅
            if (symbol.toUpperCase() == 'PLTZ') {
              print('🔍 [PLTZ 차트 API 응답] 상세 분석:');
              for (int i = 0; i < output.length && i < 3; i++) {
                final item = output[i];
                print('  - Item $i:');
                print('    - date: ${item['xymd']}');
                print('    - close: ${item['clos']}');
                print('    - tvol: ${item['tvol']}');
                print('    - volume: ${item['volume']}');
                print('    - acml_vol: ${item['acml_vol']}');
                print('    - all keys: ${item.keys.toList()}');
              }
            }
            
            // API 응답을 과거→최신 순서로 정렬
            final sortedOutput = List.from(output);
            sortedOutput.sort((a, b) {
              final dateA = a['xymd'] ?? a['date'] ?? '';
              final dateB = b['xymd'] ?? b['date'] ?? '';
              return dateA.compareTo(dateB); // 과거→최신 순서
            });
            
            print('🔍 [정렬 후] 첫 번째 데이터: ${sortedOutput.first}');
            print('🔍 [정렬 후] 마지막 데이터: ${sortedOutput.last}');
            
            final chartData = sortedOutput.take(count).map((item) => _parseOverseasDailyPriceItem(item)).toList();
            print('✅ [통일API] 해외주식 일별시세 조회 성공: ${chartData.length}개');
            _onCallSuccess(cbKey);
            return chartData;
          }
          
          print('⚠️ [디버깅] output2가 비어있거나 null');
        } else {
          print('❌ [API] 응답 실패: rt_cd=${response.data['rt_cd']}, msg1=${response.data['msg1']}');
        }
      
      _onCallFailure(cbKey);
      print('❌ [통일API] 해외주식 일별시세 조회 실패: ${response?.data}');
      return [];
    } catch (e) {
      _onCallFailure('ovrs_chart:$symbol:$periodCode');
      print('❌ [통일API] 해외주식 일별시세 조회 오류: $e');
      return [];
    }
  }

  String _normalizeExchange(String code) {
    switch (code) {
      case 'NASD':
        return 'NAS';
      case 'NYSE':
        return 'NYS';
      default:
        return code;
    }
  }

  /// 해외 심볼 교정 (마스터 데이터 기반): exact 매칭 실패 시 startsWith 후보 사용
  String? _resolveUsSymbol(String symbol) {
    try {
      final parser = StockMasterParser();
      if (!parser.isInitialized) {
        // 초기화 시 비용이 크므로 실패 시 원심볼 유지
        return symbol;
      }
      final nasList = parser.getNasdaqStockCodes();
      if (nasList.contains(symbol)) return symbol;
      // startsWith로 근접 탐색 (예: NVD -> NVDA)
      final candidate = nasList.firstWhere(
        (c) => c.startsWith(symbol),
        orElse: () => '',
      );
      return candidate.isNotEmpty ? candidate : symbol;
    } catch (_) {
      return symbol;
    }
  }

  /// 해외주식 차트 아이템 파싱 (공식 가이드라인 필드명 사용)
  Map<String, dynamic> _parseOverseasChartItem(Map<String, dynamic> item) {
    // 디버깅: NVDL 거래량 특별 로깅
    final symbol = item['symb'] ?? '';
    if (symbol.toUpperCase() == 'NVDL') {
      print('🔍 [NVDL 차트 디버깅] 차트 아이템 필드들: ${item.keys.toList()}');
      print('🔍 [NVDL 차트 디버깅] 차트 아이템 값들: $item');
      print('🔍 [NVDL 차트 디버깅] 거래량 필드들:');
      print('  - acml_vol: ${item['acml_vol']}');
      print('  - tvol: ${item['tvol']}');
      print('  - volume: ${item['volume']}');
    }
    
    // KIS API 해외주식 차트의 공식 가이드라인 필드명들 사용
    return {
      'date': item['stck_bsop_date'] ?? item['xymd'] ?? item['date'] ?? DateTime.now().toString().substring(0, 10), // 영업일자
      'open': parseDouble(item['ovrs_nmix_oprc'] ?? item['ovrs_prod_oprc'] ?? item['open'] ?? item['stck_oprc']), // 시가
      'high': parseDouble(item['ovrs_nmix_hgpr'] ?? item['ovrs_prod_hgpr'] ?? item['high'] ?? item['stck_hgpr']), // 고가
      'low': parseDouble(item['ovrs_nmix_lwpr'] ?? item['ovrs_prod_lwpr'] ?? item['low'] ?? item['stck_lwpr']), // 저가
      'close': parseDouble(item['ovrs_nmix_prpr'] ?? item['ovrs_prod_clpr'] ?? item['close'] ?? item['stck_clpr']), // 종가
      'volume': parseInt(item['acml_vol'] ?? item['tvol'] ?? item['volume']), // 거래량
    };
  }

  /// 해외주식 일별시세 아이템 파싱 (dailyprice API 필드명 사용)
  Map<String, dynamic> _parseOverseasDailyPriceItem(Map<String, dynamic> item) {
    // 디버깅: NVD 거래량 특별 로깅
    final symbol = item['code'] ?? item['symb'] ?? '';
    if (symbol.toUpperCase() == 'NVD') {
      print('🔍 [NVD 일별시세 디버깅] 일별시세 아이템 필드들: ${item.keys.toList()}');
      print('🔍 [NVD 일별시세 디버깅] 일별시세 아이템 값들: $item');
      print('🔍 [NVD 일별시세 디버깅] 거래량 필드들:');
      print('  - tvol: ${item['tvol']}');
      print('  - volume: ${item['volume']}');
      print('  - acml_vol: ${item['acml_vol']}');
      print('  - pvol: ${item['pvol']}');
      print('  - bvol: ${item['bvol']}');
      print('  - avol: ${item['avol']}');
    }
    
    // 디버깅: PLTZ 거래량 특별 로깅
    if (symbol.toUpperCase() == 'PLTZ') {
      print('🔍 [PLTZ 일별시세 디버깅] 일별시세 아이템 필드들: ${item.keys.toList()}');
      print('🔍 [PLTZ 일별시세 디버깅] 일별시세 아이템 값들: $item');
      print('🔍 [PLTZ 일별시세 디버깅] 거래량 필드들:');
      print('  - tvol: ${item['tvol']}');
      print('  - volume: ${item['volume']}');
      print('  - acml_vol: ${item['acml_vol']}');
      print('  - pvol: ${item['pvol']}');
      print('  - bvol: ${item['bvol']}');
      print('  - avol: ${item['avol']}');
    }
    
    // KIS API 해외주식 일별시세의 공식 필드명들 사용
    // 거래량 필드 우선순위: tvol > volume > acml_vol > pvol > bvol > avol
    final volume = parseInt(item['tvol'] ?? item['volume'] ?? item['acml_vol'] ?? item['pvol'] ?? item['bvol'] ?? item['avol'] ?? 0);
    
    if (symbol.toUpperCase() == 'NVD') {
      print('🔍 [NVD 일별시세 디버깅] 최종 거래량: $volume');
    }
    
    if (symbol.toUpperCase() == 'PLTZ') {
      print('🔍 [PLTZ 일별시세 디버깅] 최종 거래량: $volume');
    }
    
    return {
      'date': item['xymd'] ?? item['date'] ?? DateTime.now().toString().substring(0, 10), // 일자
      'open': parseDouble(item['open'] ?? 0), // 시가
      'high': parseDouble(item['high'] ?? 0), // 고가
      'low': parseDouble(item['low'] ?? 0), // 저가
      'close': parseDouble(item['clos'] ?? item['close'] ?? 0), // 종가
      'volume': volume, // 거래량 (우선순위 적용)
      'tvol': parseInt(item['tvol'] ?? 0), // 총 거래량 (우선 사용)
      'acml_vol': parseInt(item['acml_vol'] ?? 0), // 누적 거래량
    };
  }

  /// 해외주식 차트 데이터 서버 저장 (서버 Functions 실패 대비)
  Future<void> _saveOverseasChartDataToServer(String symbol, List<Map<String, dynamic>> chartData) async {
    try {
      print('🔍 [해외주식 차트 저장] 서버 저장 시도: $symbol (${chartData.length}개)');
      
      // Firestore에 직접 저장
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      
      for (final data in chartData) {
        final date = data['date']?.toString() ?? '';
        if (date.isEmpty) continue;
        
        final docRef = db.collection('charts').doc(symbol).collection('daily').doc(date);
        batch.set(docRef, {
          'stock_code': symbol,
          'market': 'NASDAQ',
          'date': date,
          'date_ts': int.tryParse(date.replaceAll('-', '')) ?? 0,
          'open': (data['open'] ?? 0.0).toDouble(),
          'high': (data['high'] ?? 0.0).toDouble(),
          'low': (data['low'] ?? 0.0).toDouble(),
          'close': (data['close'] ?? 0.0).toDouble(),
          'volume': (data['volume'] ?? 0).toInt(),
          'trade_amount': data['trade_amount'],
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      
      await batch.commit();
      print('✅ [해외주식 차트 저장] 서버 저장 완료: $symbol');
      
    } catch (e) {
      print('❌ [해외주식 차트 저장] 서버 저장 실패: $symbol - $e');
    }
  }

  /// ========================================
  /// 5. 통합 API 메서드 (기존 호환성 유지)
  /// ========================================
  
  /// 종목 코드로 자동 판별하여 현재가 조회
  Future<Map<String, dynamic>?> getStockPrice(String stockCode) async {
    // 서버 전환: 클라이언트에서 통일API 호출 금지
    return null;
  }

  /// 종목 코드로 자동 판별하여 일별 차트 조회
  Future<List<Map<String, dynamic>>> getDailyChart(String stockCode, {int count = ChartConstants.CHART_MIN_BARS}) async {
    // 서버 전환: 클라이언트에서 통일API 호출 금지
    return const [];
  }

  /// ========================================
  /// 5. 계좌 관련 API는 확장 파일에서 제공됨
  /// ========================================

  /// ========================================
  /// 7. 해외 매수가능금액 조회 API (공식 가이드라인)
  /// ========================================
  
  /// 해외 매수가능금액 조회
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/overseas-stock/v1/trading/inquire-psamount
  /// - TR ID: TTTS3007R (실전), VTTS3007R (모의)
  /// - 필수 파라미터: cano, acnt_prdt_cd, ovrs_excg_cd, ovrs_ord_unpr, item_cd
  Future<double> getOverseasBuyableAmount({
    required String cano,
    required String acntPrdtCd,
    required String stockCode,
    required double price,
    String ovrsExcCd = 'NASD',
  }) async {
    try {
      print('💰 [통일API] 해외 매수가능금액 조회 시작');
      
      final response = await authedGet(
        '/uapi/overseas-stock/v1/trading/inquire-psamount',
        {
          'CANO': cano,
          'ACNT_PRDT_CD': acntPrdtCd,
          'OVRS_EXCG_CD': ovrsExcCd,
          'OVRS_ORD_UNPR': price.toStringAsFixed(2),
          'ITEM_CD': stockCode,
        },
        trId: 'TTTS3007R',
      );

      if (response.statusCode == 200 && response.data['rt_cd'] == '0') {
        final output = response.data['output'];
        if (output != null) {
          final buyableAmount = parseDouble(output['nrcvb_buy_amt']);
          print('✅ [통일API] 해외 매수가능금액: \$${buyableAmount.toStringAsFixed(2)}');
          return buyableAmount;
        }
      }
      
      print('❌ [통일API] 해외 매수가능금액 조회 실패: ${response.data}');
      return 0.0;
    } catch (e) {
      print('❌ [통일API] 해외 매수가능금액 조회 오류: $e');
      return 0.0;
    }
  }

  /// ========================================
  /// 8. 계좌 관련 API들
  /// ========================================
  
  /// 국내 계좌 잔고 조회
  Future<Map<String, dynamic>?> getDomesticAccountBalance({
    required String cano,
    required String acntPrdtCd,
    String afhrFlprYn = 'N',
    String inqrDvsn = '01', // 01: 대출일별 조회 (공식 예제 기준)
    String unprDvsn = '01',
    String fundSttlIcldYn = 'N',
    String fncgAmtAutoRdptYn = 'N',
    String prcsDvsn = '00',
  }) async {
    const maxRetries = 3;
    const retryDelay = Duration(seconds: 2);
    
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('💰 [통일API] 국내주식 잔고 조회 시작 - 시도 $attempt/$maxRetries');
        final response = await authedGet(
          '/uapi/domestic-stock/v1/trading/inquire-balance',
          {
            'CANO': cano,
            'ACNT_PRDT_CD': acntPrdtCd,
            'AFHR_FLPR_YN': afhrFlprYn,
            'OFL_YN': '',
            'INQR_DVSN': inqrDvsn,
            'UNPR_DVSN': unprDvsn,
            'FUND_STTL_ICLD_YN': fundSttlIcldYn,
            'FNCG_AMT_AUTO_RDPT_YN': fncgAmtAutoRdptYn,
            'PRCS_DVSN': prcsDvsn,
            'CTX_AREA_FK100': '',
            'CTX_AREA_NK100': '',
          },
          trId: 'TTTC8434R',
        );
        
        if (response.statusCode == 200 && response.data['rt_cd'] == '0') {
          final output1 = response.data['output1'] ?? [];
          final output2 = response.data['output2'] ?? [];
          print('✅ [통일API] 국내주식 잔고 조회 성공');
          return {
            'holdings': output1 is List ? output1 : [output1],
            'accountInfo': output2 is List ? output2 : [output2],
          };
        }
        
        // 500 오류인 경우 재시도
        if (response.statusCode == 500 && attempt < maxRetries) {
          print('⚠️ [통일API] 500 오류 발생, ${retryDelay.inSeconds}초 후 재시도...');
          print('📋 [통일API] 응답 데이터: ${response.data}');
          await Future.delayed(retryDelay);
          continue;
        }
        
        print('❌ [통일API] 국내주식 잔고 조회 실패: ${response.statusCode} - ${response.data}');
        return null;
      } catch (e) {
        print('❌ [통일API] 국내주식 잔고 조회 오류 (시도 $attempt/$maxRetries): $e');
        
        // DioException인 경우 응답 데이터 확인
        if (e is DioException && e.response != null) {
          print('📋 [통일API] 응답 상태코드: ${e.response!.statusCode}');
          print('📋 [통일API] 응답 데이터: ${e.response!.data}');
          
          // 토큰 만료 오류는 재시도하지 않음 (authedGet에서 이미 처리됨)
          if (e.response!.data['msg_cd'] == 'EGW00123') {
            print('❌ [통일API] 토큰 만료 오류 - 재시도하지 않음');
            return null;
          }
          
          // 토큰 발급 제한 오류는 재시도하지 않음
          if (e.response!.data['error_code'] == 'EGW00133') {
            print('❌ [통일API] 토큰 발급 제한 오류 - 재시도하지 않음');
            return null;
          }
        }
        
        // 500 오류인 경우 재시도 (토큰 만료 제외)
        if (e.toString().contains('500') && attempt < maxRetries) {
          print('⚠️ [통일API] 500 오류 발생, ${retryDelay.inSeconds}초 후 재시도...');
          await Future.delayed(retryDelay);
          continue;
        }
        
        if (attempt == maxRetries) {
          return null;
        }
      }
    }
    
    return null;
  }
  
  /// 해외 계좌 잔고 조회
  Future<Map<String, dynamic>?> getOverseasAccountBalance({
    required String cano,
    required String acntPrdtCd,
    String ovrsExcCd = 'NASD',
    String trCrcyCd = 'USD',
  }) async {
    const maxRetries = 3;
    const retryDelay = Duration(seconds: 2);

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('🌍 [통일API] 해외주식 잔고 조회 시작 (시도 $attempt/$maxRetries)');
        final response = await authedGet(
          '/uapi/overseas-stock/v1/trading/inquire-balance',
          {
            'CANO': cano,
            'ACNT_PRDT_CD': acntPrdtCd,
            'OVRS_EXCG_CD': ovrsExcCd,
            'TR_CRCY_CD': trCrcyCd,
            'CTX_AREA_FK200': '',
            'CTX_AREA_NK200': '',
          },
          trId: 'TTTS3012R',
        );
        
        if (response.statusCode == 200 && response.data['rt_cd'] == '0') {
          final output1 = response.data['output1'] ?? [];
          final output2 = response.data['output2'] ?? [];
          print('✅ [통일API] 해외주식 잔고 조회 성공 OVRS_EXCG_CD=$ovrsExcCd');
          print('   - output1(holdings) len: ${output1 is List ? output1.length : 1}');
          print('   - output2(cash) len: ${output2 is List ? output2.length : 1}');
          return {
            'holdings': output1 is List ? output1 : [output1],
            'cashBalance': output2 is List ? output2 : [output2],
          };
        }
        
        // 500 오류인 경우 재시도
        if (response.statusCode == 500 && attempt < maxRetries) {
          print('⚠️ [통일API] 500 오류 발생, ${retryDelay.inSeconds}초 후 재시도...');
          print('📋 [통일API] 응답 데이터: ${response.data}');
          await Future.delayed(retryDelay);
          continue;
        }
        
        print('❌ [통일API] 해외주식 잔고 조회 실패: ${response.statusCode} - ${response.data}');
        return null;
      } catch (e) {
        print('❌ [통일API] 해외주식 잔고 조회 오류 (시도 $attempt/$maxRetries): $e');
        
        // DioException인 경우 응답 데이터 확인
        if (e is DioException && e.response != null) {
          print('📋 [통일API] 응답 상태코드: ${e.response!.statusCode}');
          print('📋 [통일API] 응답 데이터: ${e.response!.data}');
          
          // 토큰 만료 오류는 재시도하지 않음 (authedGet에서 이미 처리됨)
          if (e.response!.data['msg_cd'] == 'EGW00123') {
            print('❌ [통일API] 토큰 만료 오류 - 재시도하지 않음');
            return null;
          }
          
          // 토큰 발급 제한 오류는 재시도하지 않음
          if (e.response!.data['error_code'] == 'EGW00133') {
            print('❌ [통일API] 토큰 발급 제한 오류 - 재시도하지 않음');
            return null;
          }
        }
        
        // 500 오류인 경우 재시도 (토큰 만료 제외)
        if (e.toString().contains('500') && attempt < maxRetries) {
          print('⚠️ [통일API] 500 오류 발생, ${retryDelay.inSeconds}초 후 재시도...');
          await Future.delayed(retryDelay);
          continue;
        }
        
        // 마지막 시도에서도 실패하면 null 반환
        if (attempt == maxRetries) {
          return null;
        }
      }
    }
    
    return null;
  }
  
  /// 통합 계좌 잔고 조회
  Future<Map<String, dynamic>?> getUnifiedAccountBalance({
    required String cano,
    required String acntPrdtCd,
  }) async {
    try {
      print('💰 [통일API] 통합 계좌 잔고 조회 시작');
      
      // 1. 국내 계좌 잔고 조회
      final domesticBalance = await getDomesticAccountBalance(
        cano: cano,
        acntPrdtCd: acntPrdtCd,
      );
      
      // 2. 해외 계좌 잔고 조회
      final overseasBalance = await getOverseasAccountBalance(
        cano: cano,
        acntPrdtCd: acntPrdtCd,
      );
      
      // 3. 결과 통합
      final result = {
        'domestic': domesticBalance,
        'overseas': overseasBalance,
        'domesticHoldings': domesticBalance?['holdings'] ?? [],
        'overseasHoldings': overseasBalance?['holdings'] ?? [],
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      print('✅ [통일API] 통합 계좌 잔고 조회 완료');
      return result;
    } catch (e) {
      print('❌ [통일API] 통합 계좌 잔고 조회 오류: $e');
      return null;
    }
  }

  /// ========================================
  /// 9. 편의 메서드들 (확장 파일 호출)
  /// ========================================
  
  /// 종목 코드 자동 판별 및 현재가 조회
  Future<Map<String, dynamic>?> getStockPriceAuto(String stockCode) async {
    try {
      print('🔍 [통일API] 종목 자동 판별: $stockCode');
      
      // 해외주식 판별 (대문자 영문 1-5자리)
      if (RegExp(r'^[A-Z]{1,5}$').hasMatch(stockCode)) {
        // NVDL 디버깅을 위한 특별 로깅
        if (stockCode.toUpperCase() == 'NVDL') {
          print('🔍 [NVDL getStockPriceAuto] 해외주식 현재가 조회 시작');
        }
        
        final result = await getOverseasStockPrice(
          symbol: stockCode,
          exchangeCode: 'NAS', // 기본값: 나스닥
        );
        
        // NVDL 결과 디버깅
        if (stockCode.toUpperCase() == 'NVDL' && result != null) {
          print('🔍 [NVDL getStockPriceAuto] 결과:');
          print('  - prpr: ${result['prpr']}');
          print('  - acml_vol: ${result['acml_vol']}');
          print('  - tvol: ${result['tvol']}');
          print('  - volume: ${result['volume']}');
        }
        
        return result;
      } else {
        return await getDomesticStockPrice(stockCode: stockCode);
      }
    } catch (e) {
      print('❌ [통일API] 종목 자동 판별 오류: $e');
      return null;
    }
  }
  
  /// 통합 계좌 정보 조회
  Future<Map<String, dynamic>?> getUnifiedAccountInfo() async {
    // 서버 전환: 클라이언트 계좌 API 비활성화
    print('⛔ [통일API] getUnifiedAccountInfo 비활성화(서버 전용)');
    return null;
  }
  
  /// 보유종목 조회 (호환성) - 국내 + 해외 통합
  Future<List<Map<String, dynamic>>> getPositionsCompat() async {
    try {
      final cano = extractCano();
      final acntPrdtCd = extractPrdtCd();
      // 국내 잔고에서 보유종목 추출
      final domestic = await getDomesticAccountBalance(
        cano: cano,
        acntPrdtCd: acntPrdtCd,
      );
      List<Map<String, dynamic>> positions = [];
      if (domestic != null && domestic['holdings'] != null) {
        positions.addAll(List<Map<String, dynamic>>.from(domestic['holdings']));
      }
      return positions;
    } catch (e) {
      print('❌ [통일API] getPositionsCompat 오류: $e');
      return [];
    }
  }
  
  /// 해외 보유종목 조회 (호환성)
  Future<List<Map<String, dynamic>>> getOverseasHoldingsCompat() async {
    try {
      final cano = extractCano();
      final acntPrdtCd = extractPrdtCd();
      
      final overseas = await getOverseasAccountBalance(
        cano: cano,
        acntPrdtCd: acntPrdtCd,
      );
      
      if (overseas != null && overseas['holdings'] != null) {
        final holdings = overseas['holdings'] as List;
        return holdings.cast<Map<String, dynamic>>();
      }
      
      return [];
    } catch (e) {
      print('❌ [통일API] 해외 보유종목 조회 오류: $e');
      return [];
    }
  }
  
  /// 해외주식 잔고 조회 (호환성)
  Future<List<Map<String, dynamic>>> getOverseasPresentBalanceCompat({String exchangeCode = 'NASD'}) async {
    try {
      final cano = extractCano();
      final basePrdt = extractPrdtCd();
      final List<String> acntVariants = [basePrdt, '03', '07'].toSet().toList();
      final List<String> excVariants = exchangeCode == 'NASD'
          ? ['NASD', 'NAS']
          : exchangeCode == 'NYSE'
              ? ['NYSE', 'NYS']
              : [exchangeCode];

      for (final exc in excVariants) {
        for (final prdt in acntVariants) {
          try {
            print('🌍 [통일API] 해외 보유 조회 시도: EXC=$exc, PRDT=$prdt');
            final balance = await getOverseasAccountBalance(
              cano: cano,
              acntPrdtCd: prdt,
              ovrsExcCd: exc,
            );
            if (balance != null && balance['holdings'] != null) {
              final holdings = (balance['holdings'] as List).cast<Map<String, dynamic>>();
              print('✅ [통일API] 해외 보유 조회 성공: EXC=$exc, PRDT=$prdt, count=${holdings.length}');
              if (holdings.isNotEmpty) return holdings;
            }
          } catch (inner) {
            print('⚠️ [통일API] 해외 보유 조회 실패: EXC=$exc, PRDT=$prdt, err=$inner');
          }
        }
      }

      return [];
    } catch (e) {
      print('❌ [통일API] 해외주식 잔고 조회 오류: $e');
      return [];
    }
  }
  
  /// 해외주식 체결내역 조회 (호환성)
  Future<List<Map<String, dynamic>>> getOverseasExecutionsCompat({int limit = 100}) async {
    // 서버 전환: 클라이언트 체결내역 API 비활성화
    print('⛔ [통일API] getOverseasExecutionsCompat 비활성화(서버 전용)');
    return [];
  }
  
  /// 해외주식 결제준비금 조회 (호환성)
  Future<double> getOverseasPaymentStandardBalanceCompat() async {
    try {
      final cano = extractCano();
      final acntPrdtCd = extractPrdtCd();
      final balance = await getOverseasAccountBalance(
        cano: cano,
        acntPrdtCd: acntPrdtCd,
        ovrsExcCd: 'NASD',
      );
      
      if (balance != null && balance['cashBalance'] != null) {
        final cashBalance = balance['cashBalance'] as List;
        if (cashBalance.isNotEmpty) {
          final cash = cashBalance.first as Map<String, dynamic>;
          return parseDouble(cash['frcr_evlu_amt']);
        }
      }
      
      return 0.0;
    } catch (e) {
      print('❌ [통일API] 해외주식 결제준비금 조회 오류: $e');
      return 0.0;
    }
  }
  
  /// 해외주식 결제준비금 조회 (기존 호환성)
  Future<double> getOverseasPaymentStandardBalance() async {
    return await getOverseasPaymentStandardBalanceCompat();
  }
  
  /// 해외 매수가능금액 조회 (호환성)
  Future<double> getOverseasBuyableAmountCompat2({
    String exchangeCode = 'NASD', 
    String currency = 'USD',
    String stockCode = 'AAPL',
    double price = 150.0,
  }) async {
    try {
      final cano = extractCano();
      final acntPrdtCd = extractPrdtCd();
      
      // 해외 매수가능금액 조회 API 호출
      final response = await authedGet(
        '/uapi/overseas-stock/v1/trading/inquire-psamount',
        {
          'CANO': cano,
          'ACNT_PRDT_CD': acntPrdtCd,
          'OVRS_EXCG_CD': exchangeCode,
          'OVRS_ORD_UNPR': price.toStringAsFixed(2),
          'ITEM_CD': stockCode,
        },
        trId: 'TTTS3007R',
      );

      if (response.statusCode == 200 && response.data['rt_cd'] == '0') {
        final output = response.data['output'];
        if (output != null) {
          final buyableAmount = parseDouble(output['nrcvb_buy_amt']);
          print('✅ [통일API] 해외 매수가능금액: \$${buyableAmount.toStringAsFixed(2)}');
          return buyableAmount;
        }
      }
      
      print('❌ [통일API] 해외 매수가능금액 조회 실패: ${response.data}');
      return 0.0;
    } catch (e) {
      print('❌ [통일API] 해외 매수가능금액 조회 오류: $e');
      return 0.0;
    }
  }
  
  /// 보유종목 조회 (기존 호환성)
  Future<List<Map<String, dynamic>>> getPositions() async {
    return await getPositionsCompat();
  }
  
  /// 계좌 잔고 조회 (기존 호환성)
  Future<Map<String, dynamic>?> getAccountBalanceCompat() async {
    // 서버 전환: 클라이언트 잔고 API 비활성화
    print('⛔ [통일API] getAccountBalanceCompat 비활성화(서버 전용)');
    return null;
  }
  
  /// 해외주식 미체결 주문 조회
  Future<List<Map<String, dynamic>>> getOverseasPendingOrders() async {
    try {
      print('📋 [통일API] 해외주식 미체결 주문 조회');
      
      final cano = extractCano();
      final acntPrdtCd = extractPrdtCd();
      
      final response = await authedGet(
        '/uapi/overseas-stock/v1/trading/inquire-nccs',
        {
          'CANO': cano,
          'ACNT_PRDT_CD': acntPrdtCd,
          'OVRS_EXCG_CD': 'NASD',
          'SORT_SQN': 'DS',
          'ORD_DVSN': '00',
          'CTX_AREA_FK100': '',
          'CTX_AREA_NK100': '',
        },
        trId: 'HHDFS00000300',
      );

      if (response != null && response.data['rt_cd'] == '0') {
        final output = response.data['output'] as List?;
        if (output != null) {
          print('✅ [통일API] 해외주식 미체결 주문: ${output.length}개');
          return output.cast<Map<String, dynamic>>();
        }
      }
      
      return [];
    } catch (e) {
      print('❌ [통일API] 해외주식 미체결 주문 조회 오류: $e');
      return [];
    }
  }
  
  /// 해외주식 주문 체결 확인
  Future<Map<String, dynamic>?> checkOverseasOrderExecution(String orderId) async {
    try {
      print('🔍 [통일API] 해외주식 주문 체결 확인: $orderId');
      
      final cano = extractCano();
      final acntPrdtCd = extractPrdtCd();
      
      final response = await authedGet(
        '/uapi/overseas-stock/v1/trading/inquire-ccld',
        {
          'CANO': cano,
          'ACNT_PRDT_CD': acntPrdtCd,
          'OVRS_EXCG_CD': 'NASD',
          'SORT_SQN': 'DS',
          'ORD_DVSN': '00',
          'CTX_AREA_FK100': '',
          'CTX_AREA_NK100': '',
        },
        trId: 'HHDFS00000300',
      );

      if (response != null && response.data['rt_cd'] == '0') {
        final output = response.data['output'] as List?;
        if (output != null) {
          // 주문ID로 필터링
          for (final order in output) {
            if (order['odno'] == orderId) {
              return order as Map<String, dynamic>;
            }
          }
        }
      }
      
      return null;
    } catch (e) {
      print('❌ [통일API] 해외주식 주문 체결 확인 오류: $e');
      return null;
    }
  }
  
  /// 해외주식 기간별 거래내역 조회
  Future<List<Map<String, dynamic>>> getOverseasPeriodTransactions({
    required String startDate,
    required String endDate,
    String exchangeCode = 'NASD',
  }) async {
    const maxRetries = 3;
    const retryDelay = Duration(seconds: 2);

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('📊 [통일API] 해외주식 기간별 거래내역 조회: $startDate ~ $endDate (시도 $attempt/$maxRetries)');
        
        final cano = extractCano();
        final acntPrdtCd = extractPrdtCd();
        
        final response = await authedGet(
          '/uapi/overseas-stock/v1/trading/inquire-period-trans',
          {
            'CANO': cano,
            'ACNT_PRDT_CD': acntPrdtCd,
            'OVRS_EXCG_CD': exchangeCode,
            'ERLM_STRT_DT': startDate,
            'ERLM_END_DT': endDate,
            'PDNO': '',
            'SLL_BUY_DVSN_CD': '00',
            'LOAN_DVSN_CD': '',
            'CTX_AREA_FK100': '',
            'CTX_AREA_NK100': '',
          },
          trId: 'CTOS4001R',
        );

        if (response != null && response.data['rt_cd'] == '0') {
          final output = response.data['output'] as List?;
          if (output != null) {
            print('✅ [통일API] 해외주식 기간별 거래내역: ${output.length}개');
            return output.cast<Map<String, dynamic>>();
          }
        }
        
        // 500 오류인 경우 재시도
        if (response != null && response.statusCode == 500 && attempt < maxRetries) {
          print('⚠️ [통일API] 500 오류 발생, ${retryDelay.inSeconds}초 후 재시도...');
          await Future.delayed(retryDelay);
          continue;
        }
        
        return [];
      } catch (e) {
        print('❌ [통일API] 해외주식 기간별 거래내역 조회 오류 (시도 $attempt/$maxRetries): $e');
        
        // DioException인 경우 응답 데이터 확인
        if (e is DioException && e.response != null) {
          print('📋 [통일API] 응답 상태코드: ${e.response!.statusCode}');
          print('📋 [통일API] 응답 데이터: ${e.response!.data}');
          
          // 토큰 만료 오류는 재시도하지 않음 (authedGet에서 이미 처리됨)
          if (e.response!.data['msg_cd'] == 'EGW00123') {
            print('❌ [통일API] 토큰 만료 오류 - 재시도하지 않음');
            return [];
          }
        }
        
        // 500 오류인 경우 재시도 (토큰 만료 제외)
        if (e.toString().contains('500') && attempt < maxRetries) {
          print('⚠️ [통일API] 500 오류 발생, ${retryDelay.inSeconds}초 후 재시도...');
          await Future.delayed(retryDelay);
          continue;
        }
        
        // 마지막 시도에서도 실패하면 빈 리스트 반환
        if (attempt == maxRetries) {
          return [];
        }
      }
    }
    
    return [];
  }
  
  /// 연결 상태 확인
  Future<bool> isConnected() async {
    // 서버 전환: 클라이언트 연결 확인 비활성화
    print('⛔ [통일API] isConnected 비활성화(서버 전용)');
    return false;
  }
  
  /// 국내주식 현재가 조회 (호환성)
  Future<Map<String, dynamic>?> getDomesticCurrentPrice(String stockCode) async {
    try {
      final priceData = await getDomesticStockPrice(stockCode: stockCode);
      if (priceData != null) {
        return {
          'currentPrice': priceData['currentPrice'],
          'stockName': priceData['stockName'],
          'change': priceData['change'],
          'changeRate': priceData['changeRate'],
        };
      }
      return null;
    } catch (e) {
      print('❌ [통일API] 국내주식 현재가 조회 오류: $e');
      return null;
    }
  }
  
  /// 해외주식 현재가 조회 (호환성)
  Future<Map<String, dynamic>?> getOverseasCurrentPrice(String symbol) async {
    try {
      final priceData = await getOverseasStockPrice(
        symbol: symbol,
        exchangeCode: 'NAS',
      );
      if (priceData != null) {
        return {
          'currentPrice': priceData['currentPrice'],
          'stockName': symbol,
          'change': priceData['change'],
          'changeRate': priceData['changeRate'],
        };
      }
      return null;
    } catch (e) {
      print('❌ [통일API] 해외주식 현재가 조회 오류: $e');
      return null;
    }
  }
  
  /// 해외주식 주문 실행
  Future<Map<String, dynamic>?> executeOverseasOrder({
    required String symbol,
    required String orderType,
    required int quantity,
    required double price,
    String exchangeCode = 'NASD',
  }) async {
    try {
      print('📈 [통일API] 해외주식 주문 실행: $symbol, $orderType, $quantity@$price');
      
      final cano = extractCano();
      final acntPrdtCd = extractPrdtCd();
      
      final response = await authedPost(
        '/uapi/overseas-stock/v1/trading/order',
        {
          'CANO': cano,
          'ACNT_PRDT_CD': acntPrdtCd,
          'OVRS_EXCG_CD': exchangeCode,
          'PDNO': symbol,
          'ORD_QTY': quantity.toString(),
          'OVRS_ORD_UNPR': price.toStringAsFixed(2),
          'ORD_SVR_DVSN_CD': '0', // 0: 지정가
          'ORD_DVSN': orderType == 'buy' ? '00' : '01', // 00: 매수, 01: 매도
        },
        trId: 'HHDFS00000300',
      );

      if (response != null && response.data['rt_cd'] == '0') {
        print('✅ [통일API] 해외주식 주문 성공');
        return response.data;
      } else {
        print('❌ [통일API] 해외주식 주문 실패: ${response?.data['msg1']}');
        return null;
      }
    } catch (e) {
      print('❌ [통일API] 해외주식 주문 오류: $e');
      return null;
    }
  }
  
  /// 종목명 조회
  Future<String?> getStockName(String stockCode) async {
    try {
      print('📝 [통일API] 종목명 조회: $stockCode');
      
      // 해외주식인지 확인
      final isOverseas = RegExp(r'^[A-Z]{1,5}$').hasMatch(stockCode);
      
      if (isOverseas) {
        // 해외주식은 심볼 그대로 반환
        return stockCode;
      } else {
        // 국내주식은 현재가 조회에서 종목명 추출
        final priceData = await getDomesticStockPrice(stockCode: stockCode);
        if (priceData != null && priceData['stockName'] != null) {
          return priceData['stockName'] as String;
        }
        return stockCode; // 기본값으로 종목코드 반환
      }
    } catch (e) {
      print('❌ [통일API] 종목명 조회 오류: $e');
      return stockCode; // 기본값으로 종목코드 반환
    }
  }
  
  /// WebSocket 접속키 발급
  Future<Map<String, dynamic>?> getWebSocketAccessToken() async {
    try {
      print('🔐 [통일API] WebSocket 접속키 발급 시작');
      
      final response = await _dio.post(
        '/oauth2/Approval',
        data: {
          'grant_type': 'client_credentials',
          'appkey': _appKey,
          'appsecret': _appSecret,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final approvalKey = data['approval_key'];
        if (approvalKey != null) {
          print('✅ [통일API] WebSocket 접속키 발급 성공');
          return {
            'approval_key': approvalKey,
            'expires_in': data['expires_in'],
            'timestamp': DateTime.now().toIso8601String(),
          };
        }
      }
      
      print('❌ [통일API] WebSocket 접속키 발급 실패: ${response.data}');
      return null;
    } catch (e) {
      print('❌ [통일API] WebSocket 접속키 발급 오류: $e');
      return null;
    }
  }
  
  

  /// ========================================
  /// 10. 유틸리티 메서드들
  /// ========================================
  
  /// Double 파싱 헬퍼
  double parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  /// Int 파싱 헬퍼
  int parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  /// 인증 상태 확인
  bool get isAuthenticated => _accessToken != null;

  /// API 설정 정보
  Map<String, dynamic> get apiConfig => {
    'isValid': isAuthenticated,
    'appKey': _appKey,
    'accountNumber': _accountNumber,
  };

  /// 계좌 번호에서 CANO 추출 (앞 8자리)
  String extractCano() {
    print('🔍 [통일API] extractCano 호출 - _accountNumber: $_accountNumber');
    if (_accountNumber == null) {
      print('❌ [통일API] 계좌 번호가 null입니다');
      throw Exception('계좌 번호가 null입니다');
    }
    
    // 하이픈 제거하고 숫자만 추출
    final cleanAccountNumber = _accountNumber!.replaceAll(RegExp(r'[^0-9]'), '');
    print('🔍 [통일API] 정리된 계좌번호: $cleanAccountNumber');
    
    if (cleanAccountNumber.length < 8) {
      print('❌ [통일API] 계좌 번호가 너무 짧습니다: $cleanAccountNumber (길이: ${cleanAccountNumber.length})');
      throw Exception('계좌 번호가 너무 짧습니다: $cleanAccountNumber');
    }
    
    final cano = cleanAccountNumber.substring(0, 8);
    print('✅ [통일API] CANO 추출 성공: $cano');
    return cano;
  }

  /// 계좌 번호에서 ACNT_PRDT_CD 추출 (뒤 2자리)
  String extractPrdtCd() {
    print('🔍 [통일API] extractPrdtCd 호출 - _accountNumber: $_accountNumber');
    if (_accountNumber == null) {
      print('❌ [통일API] 계좌 번호가 null입니다');
      throw Exception('계좌 번호가 null입니다');
    }
    
    // 하이픈 제거하고 숫자만 추출
    final cleanAccountNumber = _accountNumber!.replaceAll(RegExp(r'[^0-9]'), '');
    print('🔍 [통일API] 정리된 계좌번호: $cleanAccountNumber');
    
    if (cleanAccountNumber.length < 10) {
      print('❌ [통일API] 계좌 번호가 너무 짧습니다: $cleanAccountNumber (길이: ${cleanAccountNumber.length})');
      throw Exception('계좌 번호가 너무 짧습니다: $cleanAccountNumber');
    }
    
    final acntPrdtCd = cleanAccountNumber.substring(8, 10);
    print('✅ [통일API] ACNT_PRDT_CD 추출 성공: $acntPrdtCd');
    return acntPrdtCd;
  }

  /// ========================================
  /// 11. 기타 API들은 확장 파일에서 제공됨
  /// ========================================

}
