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
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../data/stock_master_parser.dart';

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

  /// 초기화
  Future<void> initialize({
    required String appKey,
    required String appSecret,
    required String accountNumber,
  }) async {
    _appKey = appKey;
    _appSecret = appSecret;
    _accountNumber = accountNumber;

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
            // Firestore prices 업서트(denormalize)
            try {
              final nowMs = DateTime.now().millisecondsSinceEpoch;
              final market = MarketTimeValidator.instance.getMarketFromSymbol(stockCode);
              final stockName = (parsed['stockName'] ?? '').toString().trim().isNotEmpty
                  ? (parsed['stockName'] ?? '').toString()
                  : (StockMasterParser().getStockInfo(stockCode)?['name']?.toString() ?? '');
              // 보정 계산
              final pr = parsed['prpr'] as num?;
              final pc = parsed['stck_prdy_clpr'] as num?;
              num? diff = parsed['diff'] as num?;
              num? rate = parsed['rate'] as num?;
              if ((diff == null || diff == 0) && pr != null && pc != null) {
                diff = pr - pc;
              }
              if ((rate == null || rate == 0) && pr != null && pc != null && pc != 0) {
                rate = ((pr - pc) / pc) * 100;
              }
              // TODO(server-migration): kClientWritesEnabled=false 시 서버로 이전
              await FirebaseFirestore.instance.collection('prices').doc(stockCode).set({
                'stock_name': stockName,
                'market': market,
                'current_price': pr ?? 0,
                'prev_close': pc ?? 0,
                'change_amount': diff ?? 0,
                'change_rate': rate ?? 0,
                'volume': parsed['acml_vol'] ?? 0,
                'trade_amount': 0,
                'high_price': parsed['high'] ?? 0,
                'low_price': parsed['low'] ?? 0,
                'open_price': parsed['open'] ?? 0,
                'market_cap': null,
                'per': null,
                'pbr': null,
                'timestamp': nowMs,
              }, SetOptions(merge: true));

              // Fallback: 값이 비어 있으면 일봉 2개로 보정 (현재/전일 종가, 거래량)
              final needFallback = (pr == null || pr == 0) || (pc == null || pc == 0) || (parsed['acml_vol'] == null || parsed['acml_vol'] == 0);
              if (needFallback) {
                try {
                  final raw = await getDomesticDailyChart(stockCode: stockCode, count: 2);
                  if (raw.isNotEmpty) {
                    final last = raw.first;
                    final prev = raw.length > 1 ? raw[1] : null;
                    final closeNow = parseDouble(last['stck_clpr']);
                    final volNow = parseInt(last['acml_vol']);
                    final prevClose = prev != null ? parseDouble(prev['stck_clpr']) : null;
                    double? diff2;
                    double? rate2;
                    if (closeNow != null && prevClose != null) {
                      diff2 = closeNow - prevClose;
                      if (prevClose != 0) rate2 = (diff2 / prevClose) * 100;
                    }
                    await FirebaseFirestore.instance.collection('prices').doc(stockCode).set({
                      'current_price': closeNow ?? pr ?? 0,
                      'prev_close': prevClose ?? pc ?? 0,
                      'volume': volNow ?? parsed['acml_vol'] ?? 0,
                      'change_amount': diff2 ?? (pr != null && pc != null ? (pr - pc) : 0),
                      'change_rate': rate2 ?? ((pr != null && pc != null && pc != 0) ? ((pr - pc) / pc) * 100 : 0),
                    }, SetOptions(merge: true));
                  }
                } catch (e) {
                  print('⚠️ domestic chart fallback 실패: $e');
                }
              }
            } catch (e) {
              print('⚠️ Firestore prices 업서트 실패(domestic): $e');
            }
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
        trId: 'HHDFS76200100',
      );

      print('🔍 [API] 응답 상태: ${response.statusCode}');
      print('🔍 [API] 응답 데이터: ${response.data}');
      
      if (response.statusCode == 200 && response.data['rt_cd'] == '0') {
        final output1 = response.data['output1'];
        if (output1 != null) {
          print('✅ [API] 해외주식 현재가 조회 성공: $symbol (거래소: $exchangeCode)');
          print('🔍 [API] output1 데이터: $output1');
          
          // 1차: 1호가 응답 파싱
          final parsed = _parseOverseasStockPriceResponse(output1);
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

            // TODO(server-migration): kClientWritesEnabled=false 시 서버로 이전
            await FirebaseFirestore.instance.collection('prices').doc(symbol).set({
              'stock_name': name,
              'market': market,
              'current_price': parsed['last'] ?? parsed['prpr'] ?? 0,
              'prev_close': parsed['prevClose'] ?? 0,
              'change_amount': parsed['change'] ?? 0,
              'change_rate': parsed['changeRate'] ?? 0,
              'volume': parsed['volume'] ?? 0,
              'trade_amount': parsed['totalValue'] ?? 0,
              'high_price': parsed['high'] ?? 0,
              'low_price': parsed['low'] ?? 0,
              'open_price': parsed['open'] ?? 0,
              'market_cap': parsed['marketCap'],
              'per': parsed['pe'],
              'pbr': parsed['pb'],
              'timestamp': nowMs,
            }, SetOptions(merge: true));
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
                  await FirebaseFirestore.instance.collection('prices').doc(symbol).set({
                    'open_price': open ?? 0,
                    'high_price': high ?? 0,
                    'low_price': low ?? 0,
                    'prev_close': prevClose2 ?? FieldValue.delete(),
                    'volume': volume2 ?? FieldValue.delete(),
                    'trade_amount': totalValue2 ?? FieldValue.delete(),
                    'change_amount': changeAmt2 ?? FieldValue.delete(),
                    'change_rate': changeRt2 ?? FieldValue.delete(),
                  }, SetOptions(merge: true));
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

  /// 해외주식 현재가 응답 파싱 (원본 필드명 사용)
  Map<String, dynamic> _parseOverseasStockPriceResponse(Map<String, dynamic> output) {
    // 현재가 우선순위: last -> ovrs_nmix_prpr -> ovrs_prod_prpr -> prpr
    final currentPrice = parseDouble(output['last'] ?? 
                                   output['ovrs_nmix_prpr'] ?? 
                                   output['ovrs_prod_prpr'] ?? 
                                   output['prpr']);
    
    // 전일가 우선순위: base -> ovrs_nmix_clpr -> ovrs_prod_clpr -> stck_prdy_clpr
    final prevClose = parseDouble(output['base'] ?? 
                                output['ovrs_nmix_clpr'] ?? 
                                output['ovrs_prod_clpr'] ?? 
                                output['stck_prdy_clpr']);
    
    // 등락과 등락률 계산
    final diff = currentPrice - prevClose;
    final rate = prevClose > 0 ? ((diff / prevClose) * 100) : 0.0;
    
    // 디버깅: NVDL 거래량 특별 로깅 (모든 해외주식에 대해 로깅)
    final symbol = output['symb'] ?? '';
    print('🔍 [해외주식 디버깅] API 응답 원본:');
    print('  - symbol: $symbol');
    print('  - output keys: ${output.keys.toList()}');
    print('  - tvol: ${output['tvol']}');
    print('  - acml_vol: ${output['acml_vol']}');
    print('  - volume: ${output['volume']}');
    print('  - last: ${output['last']}');
    print('  - ovrs_nmix_prpr: ${output['ovrs_nmix_prpr']}');
    print('  - ovrs_prod_prpr: ${output['ovrs_prod_prpr']}');
    print('  - prpr: ${output['prpr']}');
    print('🔍 [해외주식 디버깅] 파싱 결과:');
    print('  - 현재가: $currentPrice');
    print('  - 전일가: $prevClose');
    print('  - 거래량: ${parseInt(output['tvol'] ?? output['acml_vol'])}');
    print('  - 등락: $diff');
    print('  - 등락률: ${rate.toStringAsFixed(2)}%');
    
    return {
      'prpr': currentPrice, // 현재가
      'stck_prdy_clpr': prevClose, // 전일가
      'acml_vol': parseInt(output['tvol'] ?? output['acml_vol']), // 거래량
      'open': parseDouble(output['open'] ?? output['ovrs_nmix_oprc'] ?? output['ovrs_prod_oprc'] ?? 0), // 시가
      'high': parseDouble(output['high'] ?? output['ovrs_nmix_hgpr'] ?? output['ovrs_prod_hgpr'] ?? 0), // 고가
      'low': parseDouble(output['low'] ?? output['ovrs_nmix_lwpr'] ?? output['ovrs_prod_lwpr'] ?? 0), // 저가
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
      
      // 날짜 설정 (오늘 기준)
      final now = DateTime.now();
      final endDate = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final startDate = now.subtract(Duration(days: count)).toString().replaceAll('-', '').substring(0, 8);
      
      final response = await authedGet(
        '/uapi/domestic-stock/v1/quotations/inquire-daily-itemchartprice',
        {
          'FID_COND_MRKT_DIV_CODE': marketCode,
          'FID_INPUT_ISCD': stockCode,
          'FID_INPUT_DATE_1': startDate,
          'FID_INPUT_DATE_2': endDate,
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
    // 디버깅: NVDL 거래량 특별 로깅
    final symbol = item['symb'] ?? '';
    if (symbol.toUpperCase() == 'NVDL') {
      print('🔍 [NVDL 일별시세 디버깅] 일별시세 아이템 필드들: ${item.keys.toList()}');
      print('🔍 [NVDL 일별시세 디버깅] 일별시세 아이템 값들: $item');
      print('🔍 [NVDL 일별시세 디버깅] 거래량 필드들:');
      print('  - tvol: ${item['tvol']}');
      print('  - volume: ${item['volume']}');
      print('  - acml_vol: ${item['acml_vol']}');
    }
    
    // KIS API 해외주식 일별시세의 공식 필드명들 사용
    return {
      'date': item['xymd'] ?? item['date'] ?? DateTime.now().toString().substring(0, 10), // 일자
      'open': parseDouble(item['open'] ?? 0), // 시가
      'high': parseDouble(item['high'] ?? 0), // 고가
      'low': parseDouble(item['low'] ?? 0), // 저가
      'close': parseDouble(item['clos'] ?? item['close'] ?? 0), // 종가
      'volume': parseInt(item['tvol'] ?? item['volume'] ?? 0), // 거래량
    };
  }

  /// ========================================
  /// 5. 통합 API 메서드 (기존 호환성 유지)
  /// ========================================
  
  /// 종목 코드로 자동 판별하여 현재가 조회
  Future<Map<String, dynamic>?> getStockPrice(String stockCode) async {
    // 해외주식 판별 (대문자 영문 1-5자리)
    if (RegExp(r'^[A-Z]{1,5}$').hasMatch(stockCode)) {
      // 여러 거래소 시도 (KIS API 공식 코드)
      final exchanges = ['NAS', 'NYS', 'AMS']; // NAS: 나스닥, NYS: 뉴욕, AMS: 아메리칸
      
      for (final exchange in exchanges) {
        final result = await getOverseasStockPrice(
          symbol: stockCode,
          exchangeCode: exchange,
        );
        if (result != null && result.isNotEmpty) {
          print('✅ [통일API] $stockCode 현재가 조회 성공 (거래소: $exchange)');
          return result;
        }
      }
      
      print('❌ [통일API] $stockCode 모든 거래소에서 현재가 조회 실패');
      return null;
    } else {
      return await getDomesticStockPrice(stockCode: stockCode);
    }
  }

  /// 종목 코드로 자동 판별하여 일별 차트 조회
  Future<List<Map<String, dynamic>>> getDailyChart(String stockCode, {int count = ChartConstants.CHART_MIN_BARS}) async {
    final periodCode = 'D';
    final cacheKey = _chartKey(stockCode, periodCode, count);

    // 1) 캐시 히트 시 즉시 반환
    if (_isFresh(_chartCacheAt[cacheKey]) && (_chartCache[cacheKey]?.isNotEmpty ?? false)) {
      return _chartCache[cacheKey]!;
    }

    // 2) 동일 키 인플라이트 콜이 있으면 해당 Future 대기하여 중복 호출 방지
    if (_inflightChart.containsKey(cacheKey)) {
      return await _inflightChart[cacheKey]!;
    }

    // 3) 새 요청 수행 (해외/국내 병렬 시도로 지연 최소화)
    final completer = Completer<List<Map<String, dynamic>>>();
    _inflightChart[cacheKey] = completer.future;

    () async {
      try {
        final isOverseas = RegExp(r'^[A-Z]{1,5}$').hasMatch(stockCode);
        if (isOverseas) {
          // 해외: 다중 거래소 병렬 시도 → 첫 성공 결과 채택
          final List<String> exchanges = ['NAS', 'NYS', 'AMS'];
          final futures = exchanges.map((ex) => getOverseasDailyChart(symbol: stockCode, exchangeCode: ex, count: count)).toList();
          final results = await Future.wait(futures);
          final firstNonEmpty = results.firstWhere((r) => r.isNotEmpty, orElse: () => const []);
          if (firstNonEmpty.isNotEmpty) {
            _chartCache[cacheKey] = firstNonEmpty;
            _chartCacheAt[cacheKey] = DateTime.now();
            completer.complete(firstNonEmpty);
            return;
          }
          print('❌ [통일API] $stockCode 모든 거래소에서 차트 데이터 조회 실패');
          completer.complete(const []);
          return;
        } else {
          final data = await getDomesticDailyChart(stockCode: stockCode, count: count);
          if (data.isNotEmpty) {
            _chartCache[cacheKey] = data;
            _chartCacheAt[cacheKey] = DateTime.now();
          }
          completer.complete(data);
        }
      } catch (e) {
        completer.complete(const []);
      } finally {
        _inflightChart.remove(cacheKey);
      }
    }();

    return await _inflightChart[cacheKey]!;
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
    try {
      print('💰 [통일API] 통합 계좌 정보 조회 시작');
      
      final cano = extractCano();
      final acntPrdtCd = extractPrdtCd();
      
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
      
      print('✅ [통일API] 통합 계좌 정보 조회 완료');
      return result;
    } catch (e) {
      print('❌ [통일API] 통합 계좌 정보 조회 오류: $e');
      return null;
    }
  }
  
  /// 보유종목 조회 (호환성) - 국내 + 해외 통합
  Future<List<Map<String, dynamic>>> getPositionsCompat() async {
    try {
      final cano = extractCano();
      final acntPrdtCd = extractPrdtCd();
      
      print('📋 [통일API] 통합 보유종목 조회 시작 (국내 + 해외)');
      
      // 1. 국내 보유종목 조회
      final domestic = await getDomesticAccountBalance(
        cano: cano,
        acntPrdtCd: acntPrdtCd,
      );
      
      // 2. 해외 보유종목 조회
      // 기본(NASD) 조회에 더해 다양한 거래소/상품코드 변형까지 커버
      final overseasNasdDefault = await getOverseasAccountBalance(
        cano: cano,
        acntPrdtCd: acntPrdtCd,
      );
      List<Map<String, dynamic>> overseasNasdVariants = [];
      List<Map<String, dynamic>> overseasNyseVariants = [];
      List<Map<String, dynamic>> overseasAmexVariants = [];
      try {
        overseasNasdVariants = await getOverseasPresentBalanceCompat(exchangeCode: 'NASD');
      } catch (_) {}
      try {
        overseasNyseVariants = await getOverseasPresentBalanceCompat(exchangeCode: 'NYSE');
      } catch (_) {}
      try {
        overseasAmexVariants = await getOverseasPresentBalanceCompat(exchangeCode: 'AMEX');
      } catch (_) {}
      
      List<Map<String, dynamic>> positions = [];
      
      // 3. 국내 보유종목 추가
      if (domestic != null && domestic['holdings'] != null) {
        final domesticHoldings = List<Map<String, dynamic>>.from(domestic['holdings']);
        positions.addAll(domesticHoldings);
        print('✅ [통일API] 국내 보유종목: ${domesticHoldings.length}개');
        if (domesticHoldings.isNotEmpty) {
          print('   - 국내 샘플 keys: ${domesticHoldings.first.keys.toList()}');
        }
      }
      
      // 4. 해외 보유종목 추가
      if (overseasNasdDefault != null && overseasNasdDefault['holdings'] != null) {
        final overseasHoldings = List<Map<String, dynamic>>.from(overseasNasdDefault['holdings']);
        positions.addAll(overseasHoldings);
        print('✅ [통일API] 해외 보유종목(NASD 기본): ${overseasHoldings.length}개');
        if (overseasHoldings.isNotEmpty) {
          print('   - 해외(NASD 기본) 샘플 keys: ${overseasHoldings.first.keys.toList()}');
        }
      }
      if (overseasNasdVariants.isNotEmpty) {
        positions.addAll(overseasNasdVariants);
        print('✅ [통일API] 해외 보유종목(NASD variants): ${overseasNasdVariants.length}개');
        print('   - 해외(NASD variants) 첫 샘플 keys: ${overseasNasdVariants.first.keys.toList()}');
      }
      if (overseasNyseVariants.isNotEmpty) {
        positions.addAll(overseasNyseVariants);
        print('✅ [통일API] 해외 보유종목(NYSE variants): ${overseasNyseVariants.length}개');
        print('   - 해외(NYSE variants) 첫 샘플 keys: ${overseasNyseVariants.first.keys.toList()}');
      }
      if (overseasAmexVariants.isNotEmpty) {
        positions.addAll(overseasAmexVariants);
        print('✅ [통일API] 해외 보유종목(AMEX variants): ${overseasAmexVariants.length}개');
        print('   - 해외(AMEX variants) 첫 샘플 keys: ${overseasAmexVariants.first.keys.toList()}');
      }

      // 5. 중복 제거 (pdno|stockCode|symbol|symb 기준)
      final seen = <String>{};
      final deduped = <Map<String, dynamic>>[];
      for (final p in positions) {
        final key = (p['pdno'] ?? p['stockCode'] ?? p['stock_code'] ?? p['symbol'] ?? p['symb'] ?? '').toString();
        if (key.isEmpty) {
          deduped.add(p);
          continue;
        }
        if (seen.add(key)) {
          deduped.add(p);
        }
      }
      
      print('✅ [통일API] 총 보유종목: ${deduped.length}개 (국내 + 해외)');
      if (deduped.isNotEmpty) {
        print('   - 통합 샘플: ${deduped.first}');
      }
      return deduped;
    } catch (e) {
      print('❌ [통일API] 보유종목 조회 오류: $e');
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
    try {
      final cano = extractCano();
      final acntPrdtCd = extractPrdtCd();
      
      // 최근 7일간의 거래내역 조회
      final endDate = DateTime.now();
      final startDate = endDate.subtract(const Duration(days: 7));
      
      final transactions = await getOverseasPeriodTransactions(
        startDate: '${startDate.year}${startDate.month.toString().padLeft(2, '0')}${startDate.day.toString().padLeft(2, '0')}',
        endDate: '${endDate.year}${endDate.month.toString().padLeft(2, '0')}${endDate.day.toString().padLeft(2, '0')}',
        exchangeCode: 'NASD',
      );
      
      return transactions.take(limit).toList();
    } catch (e) {
      print('❌ [통일API] 해외주식 체결내역 조회 오류: $e');
      return [];
    }
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
    try {
      final cano = extractCano();
      final acntPrdtCd = extractPrdtCd();
      
      return await getUnifiedAccountBalance(
        cano: cano,
        acntPrdtCd: acntPrdtCd,
      );
    } catch (e) {
      print('❌ [통일API] 계좌 잔고 조회 오류: $e');
      return null;
    }
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
    try {
      // 간단한 API 호출로 연결 상태 확인
      final cano = extractCano();
      final acntPrdtCd = extractPrdtCd();
      await getDomesticAccountBalance(cano: cano, acntPrdtCd: acntPrdtCd);
      return true;
    } catch (e) {
      print('❌ [통일API] 연결 상태 확인 실패: $e');
      return false;
    }
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
