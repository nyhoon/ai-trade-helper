/// KIS 통일 API 서비스 - 계좌 관련 기능 확장
/// 
/// 계좌 잔고, 보유종목, 해외 계좌 관련 API들을 담당
/// 
/// @author AI Assistant
/// @version 1.0.0
/// @since 2024-01-01

import 'kis_unified_api_service.dart';

/// 계좌 관련 기능 확장
extension KisUnifiedApiServiceAccount on KisUnifiedApiService {
  
  /// ========================================
  /// 국내 계좌 관련 API (공식 가이드라인)
  /// ========================================
  
  /// 국내주식 잔고 조회
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/domestic-stock/v1/trading/inquire-balance
  /// - TR ID: TTTC8434R (실전), VTTC8434R (모의)
  /// - 필수 파라미터: cano, acnt_prdt_cd, afhr_flpr_yn, inqr_dvsn, unpr_dvsn, fund_sttl_icld_yn, fncg_amt_auto_rdpt_yn, prcs_dvsn
  /// - 응답 필드: output1 (보유종목), output2 (계좌정보)
  Future<Map<String, dynamic>?> getDomesticAccountBalance({
    required String cano,
    required String acntPrdtCd,
    String afhrFlprYn = 'N',
    String inqrDvsn = '02', // 02: 종목별 조회
    String unprDvsn = '01',
    String fundSttlIcldYn = 'N',
    String fncgAmtAutoRdptYn = 'N',
    String prcsDvsn = '00',
  }) async {
    try {
      print('💰 [통일API] 국내주식 잔고 조회 시작');
      
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
        
        print('📊 [통일API] 국내주식 잔고 조회 성공');
        print('📊 [통일API] output1 (보유종목) 타입: ${output1.runtimeType}');
        print('📊 [통일API] output1 길이: ${output1 is List ? output1.length : 1}');
        print('📊 [통일API] output2 (계좌정보) 타입: ${output2.runtimeType}');
        
        // output2 상세 정보 출력
        if (output2 is Map && output2.isNotEmpty) {
          print('📊 [통일API] output2 (계좌정보) 상세:');
          output2.forEach((key, value) {
            print('  $key: $value');
          });
        } else if (output2 is List && output2.isNotEmpty) {
          print('📊 [통일API] output2 (계좌정보) 배열 길이: ${output2.length}');
          for (int i = 0; i < output2.length; i++) {
            final item = output2[i];
            print('  output2[$i]: $item');
          }
        }
        
        if (output1 is List && output1.isNotEmpty) {
          print('📊 [통일API] 보유종목 상세 정보:');
          for (int i = 0; i < output1.length; i++) {
            final holding = output1[i];
            print('  ${i+1}. ${holding['pdno']} - ${holding['prdt_name']} (${holding['hldg_qty']}주)');
          }
        } else if (output1 is Map && output1.isNotEmpty) {
          print('📊 [통일API] 보유종목 (단일): ${output1['pdno']} - ${output1['prdt_name']} (${output1['hldg_qty']}주)');
        } else {
          print('⚠️ [통일API] 보유종목이 비어있습니다');
        }
        
        return {
          'holdings': output1 is List ? output1 : (output1 is Map && output1.isNotEmpty ? [output1] : []),
          'accountInfo': output2 is List ? output2 : (output2 is Map && output2.isNotEmpty ? [output2] : []),
        };
      }
      
      print('❌ [통일API] 국내주식 잔고 조회 실패: ${response.data}');
      print('❌ [통일API] 응답 코드: ${response.statusCode}');
      print('❌ [통일API] rt_cd: ${response.data['rt_cd']}');
      print('❌ [통일API] rt_msg: ${response.data['rt_msg']}');
      return null;
    } catch (e) {
      print('❌ [통일API] 국내주식 잔고 조회 오류: $e');
      return null;
    }
  }

  /// ========================================
  /// 해외 계좌 관련 API (공식 가이드라인)
  /// ========================================
  
  /// 해외주식 잔고 조회
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/overseas-stock/v1/trading/inquire-balance
  /// - TR ID: TTTS3012R (실전), VTTS3012R (모의)
  /// - 필수 파라미터: cano, acnt_prdt_cd, ovrs_excg_cd, tr_crcy_cd
  /// - 응답 필드: output1 (보유종목), output2 (현금예탁금)
  Future<Map<String, dynamic>?> getOverseasAccountBalance({
    required String cano,
    required String acntPrdtCd,
    String ovrsExcCd = 'NASD',
    String trCrcyCd = 'USD',
  }) async {
    try {
      print('🌍 [통일API] 해외주식 잔고 조회 시작');
      print('🌍 [통일API] 파라미터 - cano: $cano, acntPrdtCd: $acntPrdtCd, ovrsExcCd: $ovrsExcCd, trCrcyCd: $trCrcyCd');
      
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
        
        print('📊 [통일API] 해외주식 잔고 조회 성공');
        print('📊 [통일API] 응답 상태코드: ${response.statusCode}');
        print('📊 [통일API] rt_cd: ${response.data['rt_cd']}');
        print('📊 [통일API] rt_msg: ${response.data['rt_msg']}');
        print('📊 [통일API] output1 (보유종목) 타입: ${output1.runtimeType}');
        print('📊 [통일API] output1 길이: ${output1 is List ? output1.length : 1}');
        print('📊 [통일API] output2 (현금잔고) 타입: ${output2.runtimeType}');
        
        // output2 상세 정보 출력
        if (output2 is Map && output2.isNotEmpty) {
          print('📊 [통일API] output2 (현금잔고) 상세:');
          output2.forEach((key, value) {
            print('  $key: $value');
          });
        } else if (output2 is List && output2.isNotEmpty) {
          print('📊 [통일API] output2 (현금잔고) 배열 길이: ${output2.length}');
          for (int i = 0; i < output2.length; i++) {
            final item = output2[i];
            print('  output2[$i]: $item');
          }
        }
        
        return {
          'holdings': output1 is List ? output1 : (output1 is Map && output1.isNotEmpty ? [output1] : []),
          'cashBalance': output2 is List ? output2 : (output2 is Map && output2.isNotEmpty ? [output2] : []),
        };
      }
      
      print('❌ [통일API] 해외주식 잔고 조회 실패');
      print('❌ [통일API] 응답 상태코드: ${response.statusCode}');
      print('❌ [통일API] 응답 데이터: ${response.data}');
      print('❌ [통일API] rt_cd: ${response.data['rt_cd']}');
      print('❌ [통일API] rt_msg: ${response.data['rt_msg']}');
      return null;
    } catch (e) {
      print('❌ [통일API] 해외주식 잔고 조회 오류: $e');
      print('❌ [통일API] 오류 타입: ${e.runtimeType}');
      print('❌ [통일API] 오류 스택: ${e.toString()}');
      return null;
    }
  }
  
  /// 국내 주식 주문가능금액 조회
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/domestic-stock/v1/trading/inquire-psbl-order
  /// - TR ID: TTTC8908R (실전), VTTC8908R (모의)
  /// - 필수 파라미터: cano, acnt_prdt_cd, pdno, ord_unpr, ord_dvsn, cma_evlu_amt_icld_yn, ovrs_icld_yn
  Future<Map<String, dynamic>?> getDomesticOrderableAmount({
    required String cano,
    required String acntPrdtCd,
    String pdno = '005930', // 삼성전자 기본값
    String ordUnpr = '55000', // 주문단가
    String ordDvsn = '01', // 시장가
    String cmaEvluAmtIcldYn = 'N',
    String ovrsIcldYn = 'N',
  }) async {
    try {
      print('💰 [통일API] 국내 주식 주문가능금액 조회 시작');
      print('💰 [통일API] 파라미터 - cano: $cano, acntPrdtCd: $acntPrdtCd, pdno: $pdno');
      
      final response = await authedGet(
        '/uapi/domestic-stock/v1/trading/inquire-psbl-order',
        {
          'CANO': cano,
          'ACNT_PRDT_CD': acntPrdtCd,
          'PDNO': pdno,
          'ORD_UNPR': ordUnpr,
          'ORD_DVSN': ordDvsn,
          'CMA_EVLU_AMT_ICLD_YN': cmaEvluAmtIcldYn,
          'OVRS_ICLD_YN': ovrsIcldYn,
        },
        trId: 'TTTC8908R',
      );

      if (response.statusCode == 200 && response.data['rt_cd'] == '0') {
        final output = response.data['output'] ?? {};
        
        print('📊 [통일API] 국내 주식 주문가능금액 조회 성공');
        print('📊 [통일API] 응답 상태코드: ${response.statusCode}');
        print('📊 [통일API] rt_cd: ${response.data['rt_cd']}');
        print('📊 [통일API] rt_msg: ${response.data['rt_msg']}');
        print('📊 [통일API] output 상세:');
        output.forEach((key, value) {
          print('  $key: $value');
        });
        
        return output;
      }
      
      print('❌ [통일API] 국내 주식 주문가능금액 조회 실패');
      print('❌ [통일API] 응답 상태코드: ${response.statusCode}');
      print('❌ [통일API] 응답 데이터: ${response.data}');
      print('❌ [통일API] rt_cd: ${response.data['rt_cd']}');
      print('❌ [통일API] rt_msg: ${response.data['rt_msg']}');
      return null;
    } catch (e) {
      print('❌ [통일API] 국내 주식 주문가능금액 조회 오류: $e');
      print('❌ [통일API] 오류 타입: ${e.runtimeType}');
      return null;
    }
  }

  /// 해외 주식 주문가능금액 조회
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/overseas-stock/v1/trading/inquire-psamount
  /// - TR ID: TTTS3007R (실전), VTTS3007R (모의)
  /// - 필수 파라미터: cano, acnt_prdt_cd, ovrs_excg_cd, ovrs_ord_unpr, item_cd
  Future<Map<String, dynamic>?> getOverseasOrderableAmount({
    required String cano,
    required String acntPrdtCd,
    String ovrsExcCd = 'NASD',
    String ovrsOrdUnpr = '1.0', // 주문단가
    String itemCd = 'QQQ', // QQQ 기본값
  }) async {
    try {
      print('🌍 [통일API] 해외 주식 주문가능금액 조회 시작');
      print('🌍 [통일API] 파라미터 - cano: $cano, acntPrdtCd: $acntPrdtCd, ovrsExcCd: $ovrsExcCd');
      
      final response = await authedGet(
        '/uapi/overseas-stock/v1/trading/inquire-psamount',
        {
          'CANO': cano,
          'ACNT_PRDT_CD': acntPrdtCd,
          'OVRS_EXCG_CD': ovrsExcCd,
          'OVRS_ORD_UNPR': ovrsOrdUnpr,
          'ITEM_CD': itemCd,
        },
        trId: 'TTTS3007R',
      );

      if (response.statusCode == 200 && response.data['rt_cd'] == '0') {
        final output = response.data['output'] ?? {};
        
        print('📊 [통일API] 해외 주식 주문가능금액 조회 성공');
        print('📊 [통일API] 응답 상태코드: ${response.statusCode}');
        print('📊 [통일API] rt_cd: ${response.data['rt_cd']}');
        print('📊 [통일API] rt_msg: ${response.data['rt_msg']}');
        print('📊 [통일API] output 상세:');
        output.forEach((key, value) {
          print('  $key: $value');
        });
        
        return output;
      }
      
      print('❌ [통일API] 해외 주식 주문가능금액 조회 실패');
      print('❌ [통일API] 응답 상태코드: ${response.statusCode}');
      print('❌ [통일API] 응답 데이터: ${response.data}');
      print('❌ [통일API] rt_cd: ${response.data['rt_cd']}');
      print('❌ [통일API] rt_msg: ${response.data['rt_msg']}');
      return null;
    } catch (e) {
      print('❌ [통일API] 해외 주식 주문가능금액 조회 오류: $e');
      print('❌ [통일API] 오류 타입: ${e.runtimeType}');
      return null;
    }
  }

  /// 해외 결제기준잔고 조회
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/overseas-stock/v1/trading/inquire-balance
  /// - TR ID: TTTS3012R (실전), VTTS3012R (모의)
  Future<Map<String, dynamic>?> getOverseasPaymentStandardBalance({
    required String cano,
    required String acntPrdtCd,
    String ovrsExcCd = 'NASD',
    String trCrcyCd = 'USD',
  }) async {
    try {
      print('💰 [통일API] 해외 결제기준잔고 조회 시작');
      
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
        final output2 = response.data['output2'];
        if (output2 != null) {
          return {
            'frcr_evlu_amt': parseDouble(output2['frcr_evlu_amt']),
            'frcr_evlu_pfls_amt': parseDouble(output2['frcr_evlu_pfls_amt']),
            'frcr_evlu_pfls_rt': parseDouble(output2['frcr_evlu_pfls_rt']),
          };
        }
      }
      
      print('❌ [통일API] 해외 결제기준잔고 조회 실패: ${response.data}');
      return null;
    } catch (e) {
      print('❌ [통일API] 해외 결제기준잔고 조회 오류: $e');
      return null;
    }
  }

  /// 해외 현재잔고 조회
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/overseas-stock/v1/trading/inquire-balance
  /// - TR ID: TTTS3012R (실전), VTTS3012R (모의)
  Future<List<Map<String, dynamic>>> getOverseasPresentBalance({
    required String cano,
    required String acntPrdtCd,
    String ovrsExcCd = 'NASD',
    String trCrcyCd = 'USD',
  }) async {
    try {
      print('💰 [통일API] 해외 현재잔고 조회 시작');
      
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
        if (output1 is List) {
          return output1.cast<Map<String, dynamic>>();
        }
      }
      
      print('❌ [통일API] 해외 현재잔고 조회 실패: ${response.data}');
      return [];
    } catch (e) {
      print('❌ [통일API] 해외 현재잔고 조회 오류: $e');
      return [];
    }
  }

  /// ========================================
  /// 거래 내역 관련 API (공식 가이드라인)
  /// ========================================
  
  /// 해외 체결내역 조회
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/overseas-stock/v1/trading/inquire-ccld
  /// - TR ID: TTTS3015R (실전), VTTS3015R (모의)
  Future<List<Map<String, dynamic>>> getOverseasExecutions({
    required String cano,
    required String acntPrdtCd,
    String ovrsExcCd = 'NASD',
    String trCrcyCd = 'USD',
    int limit = 50,
  }) async {
    try {
      print('📊 [통일API] 해외 체결내역 조회 시작');
      
      final response = await authedGet(
        '/uapi/overseas-stock/v1/trading/inquire-ccld',
        {
          'CANO': cano,
          'ACNT_PRDT_CD': acntPrdtCd,
          'OVRS_EXCG_CD': ovrsExcCd,
          'TR_CRCY_CD': trCrcyCd,
          'CTX_AREA_FK200': '',
          'CTX_AREA_NK200': '',
        },
        trId: 'TTTS3015R',
      );

      if (response.statusCode == 200 && response.data['rt_cd'] == '0') {
        final output1 = response.data['output1'] ?? [];
        if (output1 is List) {
          return output1.take(limit).cast<Map<String, dynamic>>().toList();
        }
      }
      
      print('❌ [통일API] 해외 체결내역 조회 실패: ${response.data}');
      return [];
    } catch (e) {
      print('❌ [통일API] 해외 체결내역 조회 오류: $e');
      return [];
    }
  }

  /// 해외 기간별 거래내역 조회
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/overseas-stock/v1/trading/inquire-daily-ccld
  /// - TR ID: TTTS3016R (실전), VTTS3016R (모의)
  Future<List<Map<String, dynamic>>> getOverseasPeriodTransactions({
    required String cano,
    required String acntPrdtCd,
    required String startDate,
    required String endDate,
    String ovrsExcCd = 'NASD',
    String trCrcyCd = 'USD',
  }) async {
    try {
      print('📊 [통일API] 해외 기간별 거래내역 조회 시작');
      
      final response = await authedGet(
        '/uapi/overseas-stock/v1/trading/inquire-daily-ccld',
        {
          'CANO': cano,
          'ACNT_PRDT_CD': acntPrdtCd,
          'OVRS_EXCG_CD': ovrsExcCd,
          'TR_CRCY_CD': trCrcyCd,
          'INQR_STRT_DT': startDate,
          'INQR_END_DT': endDate,
          'CTX_AREA_FK200': '',
          'CTX_AREA_NK200': '',
        },
        trId: 'TTTS3016R',
      );

      if (response.statusCode == 200 && response.data['rt_cd'] == '0') {
        final output1 = response.data['output1'] ?? [];
        if (output1 is List) {
          return output1.cast<Map<String, dynamic>>();
        }
      }
      
      print('❌ [통일API] 해외 기간별 거래내역 조회 실패: ${response.data}');
      return [];
    } catch (e) {
      print('❌ [통일API] 해외 기간별 거래내역 조회 오류: $e');
      return [];
    }
  }

  // 편의 메서드들은 메인 파일에서 제공됨
}
