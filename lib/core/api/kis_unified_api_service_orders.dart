/// KIS 통일 API 서비스 - 주문 관련 기능 확장
/// 
/// 주문 실행, 체결 확인, 주문 취소 등 주문 관련 API들을 담당
/// 
/// @author AI Assistant
/// @version 1.0.0
/// @since 2024-01-01

import 'dart:async';
import 'kis_unified_api_service.dart';

/// 주문 관련 기능 확장
extension KisUnifiedApiServiceOrders on KisUnifiedApiService {
  
  /// ========================================
  /// 국내주식 주문 API (공식 가이드라인)
  /// ========================================
  
  /// 국내주식 주문 실행
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/domestic-stock/v1/trading/order-cash
  /// - TR ID: TTTC0802U (실전), VTTC0802U (모의)
  Future<Map<String, dynamic>> executeDomesticOrder({
    required String cano,
    required String acntPrdtCd,
    required String stockCode,
    required String orderType, // 01: 매수, 02: 매도
    required int quantity,
    required double price,
    String? orderReason,
  }) async {
    try {
      print('📈 [통일API] 국내주식 주문 실행: $stockCode ($orderType)');
      
      final response = await authedPost(
        '/uapi/domestic-stock/v1/trading/order-cash',
        {
          'CANO': cano,
          'ACNT_PRDT_CD': acntPrdtCd,
          'PDNO': stockCode,
          'ORD_DVSN': orderType,
          'ORD_QTY': quantity.toString(),
          'ORD_UNPR': price.toStringAsFixed(0),
          'CTAC_TLNO': '',
          'SLL_TYPE': '01',
          'ALGO_NO': '',
        },
        trId: 'TTTC0802U',
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['rt_cd'] == '0') {
          final orderId = data['ODNO'] ?? '';
          print('✅ [통일API] 국내주식 주문 성공: $stockCode (주문번호: $orderId)');
          
          return {
            'success': true,
            'orderId': orderId,
            'message': '주문이 성공적으로 접수되었습니다',
            'data': data,
          };
        } else {
          print('❌ [통일API] 국내주식 주문 실패: ${data['msg1']}');
          return {
            'success': false,
            'orderId': '',
            'message': data['msg1'] ?? '주문 실패',
            'data': data,
          };
        }
      } else {
        print('❌ [통일API] 국내주식 주문 HTTP 오류: ${response.statusCode}');
        return {
          'success': false,
          'orderId': '',
          'message': 'HTTP 오류: ${response.statusCode}',
          'data': null,
        };
      }
    } catch (e) {
      print('❌ [통일API] 국내주식 주문 오류: $e');
      return {
        'success': false,
        'orderId': '',
        'message': '주문 오류: $e',
        'data': null,
      };
    }
  }

  /// 해외주식 주문 실행
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/overseas-stock/v1/trading/order
  /// - TR ID: 거래소별/매수매도별로 다름 (TTTT1002U, TTTT1006U, TTTS1002U 등)
  Future<Map<String, dynamic>> executeOverseasOrder({
    required String cano,
    required String acntPrdtCd,
    required String stockCode,
    required String orderType, // buy: 매수, sell: 매도
    required int quantity,
    required double price,
    String exchangeCode = 'NASD',
    String currency = 'USD',
    String? orderReason,
  }) async {
    try {
      print('🌍 [통일API] 해외주식 주문 실행: $stockCode ($orderType)');
      
      // TR ID 결정 (거래소별/매수매도별)
      String trId;
      String sllType;
      
      if (orderType == 'buy') {
        if (['NASD', 'NYSE', 'AMEX'].contains(exchangeCode)) {
          trId = 'TTTT1002U'; // 미국 매수
        } else if (exchangeCode == 'SEHK') {
          trId = 'TTTS1002U'; // 홍콩 매수
        } else if (exchangeCode == 'SHAA') {
          trId = 'TTTS0202U'; // 중국상해 매수
        } else if (exchangeCode == 'SZAA') {
          trId = 'TTTS0305U'; // 중국심천 매수
        } else if (exchangeCode == 'TKSE') {
          trId = 'TTTS0308U'; // 일본 매수
        } else if (['HASE', 'VNSE'].contains(exchangeCode)) {
          trId = 'TTTS0311U'; // 베트남 매수
        } else {
          throw Exception('지원하지 않는 거래소: $exchangeCode');
        }
        sllType = '';
      } else {
        if (['NASD', 'NYSE', 'AMEX'].contains(exchangeCode)) {
          trId = 'TTTT1006U'; // 미국 매도
        } else if (exchangeCode == 'SEHK') {
          trId = 'TTTS1001U'; // 홍콩 매도
        } else if (exchangeCode == 'SHAA') {
          trId = 'TTTS1005U'; // 중국상해 매도
        } else if (exchangeCode == 'SZAA') {
          trId = 'TTTS0304U'; // 중국심천 매도
        } else if (exchangeCode == 'TKSE') {
          trId = 'TTTS0307U'; // 일본 매도
        } else if (['HASE', 'VNSE'].contains(exchangeCode)) {
          trId = 'TTTS0310U'; // 베트남 매도
        } else {
          throw Exception('지원하지 않는 거래소: $exchangeCode');
        }
        sllType = '00';
      }
      
      final response = await authedPost(
        '/uapi/overseas-stock/v1/trading/order',
        {
          'CANO': cano,
          'ACNT_PRDT_CD': acntPrdtCd,
          'OVRS_EXCG_CD': exchangeCode,
          'PDNO': stockCode,
          'ORD_QTY': quantity.toString(),
          'OVRS_ORD_UNPR': price.toStringAsFixed(2),
          'CTAC_TLNO': '',
          'MGCO_APTM_ODNO': '',
          'SLL_TYPE': sllType,
          'ORD_SVR_DVSN_CD': '0',
          'ORD_DVSN': '00', // 00: 지정가
        },
        trId: trId,
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['rt_cd'] == '0') {
          final orderId = data['ODNO'] ?? '';
          print('✅ [통일API] 해외주식 주문 성공: $stockCode (주문번호: $orderId)');
          
          return {
            'success': true,
            'orderId': orderId,
            'message': '주문이 성공적으로 접수되었습니다',
            'data': data,
          };
        } else {
          print('❌ [통일API] 해외주식 주문 실패: ${data['msg1']}');
          return {
            'success': false,
            'orderId': '',
            'message': data['msg1'] ?? '주문 실패',
            'data': data,
          };
        }
      } else {
        print('❌ [통일API] 해외주식 주문 HTTP 오류: ${response.statusCode}');
        return {
          'success': false,
          'orderId': '',
          'message': 'HTTP 오류: ${response.statusCode}',
          'data': null,
        };
      }
    } catch (e) {
      print('❌ [통일API] 해외주식 주문 오류: $e');
      return {
        'success': false,
        'orderId': '',
        'message': '주문 오류: $e',
        'data': null,
      };
    }
  }

  /// ========================================
  /// 주문 체결 확인 API (공식 가이드라인)
  /// ========================================
  
  /// 국내주식 주문 체결 확인
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/domestic-stock/v1/trading/inquire-psbl-order
  /// - TR ID: TTTC8001R (실전), VTTC8001R (모의)
  Future<Map<String, dynamic>?> checkDomesticOrderExecution({
    required String cano,
    required String acntPrdtCd,
    required String orderId,
  }) async {
    try {
      print('🔍 [통일API] 국내주식 주문 체결 확인: $orderId');
      
      final response = await authedGet(
        '/uapi/domestic-stock/v1/trading/inquire-psbl-order',
        {
          'CANO': cano,
          'ACNT_PRDT_CD': acntPrdtCd,
          'CTX_AREA_FK100': '',
          'CTX_AREA_NK100': '',
        },
        trId: 'TTTC8001R',
      );

      if (response.statusCode == 200 && response.data['rt_cd'] == '0') {
        final output = response.data['output1'] ?? [];
        if (output is List) {
          final order = output.firstWhere(
            (item) => item['ODNO'] == orderId,
            orElse: () => null,
          );
          
          if (order != null) {
            return {
              'orderId': order['ODNO'],
              'status': order['ORD_STAT_CD'],
              'executedQuantity': parseInt(order['TOT_CCLD_QTY']),
              'remainingQuantity': parseInt(order['RMND_QTY']),
              'executedPrice': parseDouble(order['AVG_PRC']),
              'orderPrice': parseDouble(order['ORD_UNPR']),
            };
          }
        }
      }
      
      print('❌ [통일API] 국내주식 주문 체결 확인 실패: ${response.data}');
      return null;
    } catch (e) {
      print('❌ [통일API] 국내주식 주문 체결 확인 오류: $e');
      return null;
    }
  }

  /// 해외주식 주문 체결 확인
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/overseas-stock/v1/trading/inquire-psbl-order
  /// - TR ID: TTTS3014R (실전), VTTS3014R (모의)
  Future<Map<String, dynamic>?> checkOverseasOrderExecution({
    required String cano,
    required String acntPrdtCd,
    required String orderId,
    String exchangeCode = 'NASD',
  }) async {
    try {
      print('🔍 [통일API] 해외주식 주문 체결 확인: $orderId');
      
      final response = await authedGet(
        '/uapi/overseas-stock/v1/trading/inquire-psbl-order',
        {
          'CANO': cano,
          'ACNT_PRDT_CD': acntPrdtCd,
          'OVRS_EXCG_CD': exchangeCode,
          'CTX_AREA_FK200': '',
          'CTX_AREA_NK200': '',
        },
        trId: 'TTTS3014R',
      );

      if (response.statusCode == 200 && response.data['rt_cd'] == '0') {
        final output1 = response.data['output1'] ?? [];
        if (output1 is List) {
          final order = output1.firstWhere(
            (item) => item['ODNO'] == orderId,
            orElse: () => null,
          );
          
          if (order != null) {
            return {
              'orderId': order['ODNO'],
              'status': order['ORD_STAT_CD'],
              'executedQuantity': parseInt(order['TOT_CCLD_QTY']),
              'remainingQuantity': parseInt(order['RMND_QTY']),
              'executedPrice': parseDouble(order['AVG_PRC']),
              'orderPrice': parseDouble(order['OVRS_ORD_UNPR']),
            };
          }
        }
      }
      
      print('❌ [통일API] 해외주식 주문 체결 확인 실패: ${response.data}');
      return null;
    } catch (e) {
      print('❌ [통일API] 해외주식 주문 체결 확인 오류: $e');
      return null;
    }
  }

  /// ========================================
  /// 주문 취소 API (공식 가이드라인)
  /// ========================================
  
  /// 국내주식 주문 취소
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/domestic-stock/v1/trading/order-rvsecncl
  /// - TR ID: TTTC0803U (실전), VTTC0803U (모의)
  Future<Map<String, dynamic>?> cancelDomesticOrder({
    required String cano,
    required String acntPrdtCd,
    required String orderId,
    required String stockCode,
  }) async {
    try {
      print('❌ [통일API] 국내주식 주문 취소: $orderId');
      
      final response = await authedPost(
        '/uapi/domestic-stock/v1/trading/order-rvsecncl',
        {
          'CANO': cano,
          'ACNT_PRDT_CD': acntPrdtCd,
          'KRX_FWDG_ORD_ORGNO': '',
          'ORGN_ODNO': orderId,
          'ORD_DVSN': '00',
          'RVSE_CNCL_DVSN_CD': '02',
          'ORD_QTY': '0',
          'ORD_UNPR': '0',
          'QTY_ALL_ORD_YN': 'Y',
        },
        trId: 'TTTC0803U',
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['rt_cd'] == '0') {
          print('✅ [통일API] 국내주식 주문 취소 성공: $orderId');
          return {
            'success': true,
            'message': '주문이 성공적으로 취소되었습니다',
            'data': data,
          };
        } else {
          print('❌ [통일API] 국내주식 주문 취소 실패: ${data['msg1']}');
          return {
            'success': false,
            'message': data['msg1'] ?? '주문 취소 실패',
            'data': data,
          };
        }
      }
      
      print('❌ [통일API] 국내주식 주문 취소 HTTP 오류: ${response.statusCode}');
      return null;
    } catch (e) {
      print('❌ [통일API] 국내주식 주문 취소 오류: $e');
      return null;
    }
  }

  /// ========================================
  /// 편의 메서드 (기존 호환성 유지)
  /// ========================================
  
  /// 주문 실행 (자동 판별)
  Future<Map<String, dynamic>> executeOrder({
    required String stockCode,
    required String orderType,
    required int quantity,
    required double price,
    String? orderReason,
  }) async {
    try {
      final cano = extractCano();
      final acntPrdtCd = extractPrdtCd();
      
      // 해외주식 판별 (대문자 영문 1-5자리)
      if (RegExp(r'^[A-Z]{1,5}$').hasMatch(stockCode)) {
        return await executeOverseasOrder(
          cano: cano,
          acntPrdtCd: acntPrdtCd,
          stockCode: stockCode,
          orderType: orderType,
          quantity: quantity,
          price: price,
          orderReason: orderReason,
        );
      } else {
        return await executeDomesticOrder(
          cano: cano,
          acntPrdtCd: acntPrdtCd,
          stockCode: stockCode,
          orderType: orderType,
          quantity: quantity,
          price: price,
          orderReason: orderReason,
        );
      }
    } catch (e) {
      print('❌ [통일API] 주문 실행 오류: $e');
      return {
        'success': false,
        'orderId': '',
        'message': '주문 실행 오류: $e',
        'data': null,
      };
    }
  }

  /// 주문 체결 확인 (자동 판별)
  Future<Map<String, dynamic>?> checkOrderExecution(String orderId, {
    Duration timeout = const Duration(minutes: 5),
    Duration checkInterval = const Duration(seconds: 10),
  }) async {
    try {
      final cano = extractCano();
      final acntPrdtCd = extractPrdtCd();
      
      final endTime = DateTime.now().add(timeout);
      
      while (DateTime.now().isBefore(endTime)) {
        // 국내주식 체결 확인 시도
        final domesticResult = await checkDomesticOrderExecution(
          cano: cano,
          acntPrdtCd: acntPrdtCd,
          orderId: orderId,
        );
        
        if (domesticResult != null) {
          return domesticResult;
        }
        
        // 해외주식 체결 확인 시도
        final overseasResult = await checkOverseasOrderExecution(
          cano: cano,
          acntPrdtCd: acntPrdtCd,
          orderId: orderId,
        );
        
        if (overseasResult != null) {
          return overseasResult;
        }
        
        // 대기
        await Future.delayed(checkInterval);
      }
      
      print('⏰ [통일API] 주문 체결 확인 타임아웃: $orderId');
      return null;
    } catch (e) {
      print('❌ [통일API] 주문 체결 확인 오류: $e');
      return null;
    }
  }

  /// 주문 실행 및 체결 확인 (통합)
  Future<Map<String, dynamic>> executeOrderWithConfirmation({
    required String stockCode,
    required String orderType,
    required int quantity,
    required double price,
    String? orderReason,
    Duration confirmationTimeout = const Duration(minutes: 5),
  }) async {
    try {
      // 1. 주문 실행
      final orderResult = await executeOrder(
        stockCode: stockCode,
        orderType: orderType,
        quantity: quantity,
        price: price,
        orderReason: orderReason,
      );
      
      if (!orderResult['success']) {
        return orderResult;
      }
      
      final orderId = orderResult['orderId'];
      if (orderId.isEmpty) {
        return {
          'success': false,
          'message': '주문번호를 받지 못했습니다',
          'data': orderResult,
        };
      }
      
      // 2. 체결 확인
      final executionResult = await checkOrderExecution(
        orderId,
        timeout: confirmationTimeout,
      );
      
      if (executionResult != null) {
        return {
          'success': true,
          'orderId': orderId,
          'execution': executionResult,
          'message': '주문이 성공적으로 체결되었습니다',
          'data': orderResult,
        };
      } else {
        return {
          'success': false,
          'orderId': orderId,
          'message': '주문 체결 확인 실패',
          'data': orderResult,
        };
      }
    } catch (e) {
      print('❌ [통일API] 주문 실행 및 체결 확인 오류: $e');
      return {
        'success': false,
        'orderId': '',
        'message': '주문 실행 및 체결 확인 오류: $e',
        'data': null,
      };
    }
  }

  /// 주문 취소 (자동 판별)
  Future<Map<String, dynamic>?> cancelOrder(String stockCode) async {
    try {
      final cano = extractCano();
      final acntPrdtCd = extractPrdtCd();
      
      // 해외주식 판별 (대문자 영문 1-5자리)
      if (RegExp(r'^[A-Z]{1,5}$').hasMatch(stockCode)) {
        // 해외주식 주문 취소는 별도 구현 필요
        print('⚠️ [통일API] 해외주식 주문 취소는 아직 구현되지 않았습니다: $stockCode');
        return null;
      } else {
        // 국내주식 주문 취소는 미체결 주문 조회 후 취소 필요
        print('⚠️ [통일API] 국내주식 주문 취소는 미체결 주문 조회 후 취소해야 합니다: $stockCode');
        return null;
      }
    } catch (e) {
      print('❌ [통일API] 주문 취소 오류: $e');
      return null;
    }
  }
}
