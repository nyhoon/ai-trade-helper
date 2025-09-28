import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/api/kis_unified_api_service.dart';
import '../../../core/api/kis_unified_api_service_account.dart';
import '../state/account_change.dart';

/// 계좌 데이터 로드 UseCase
/// MVI 패턴의 Domain 계층 역할을 담당
class LoadAccountDataUseCase {
  static const int _maxRetries = 3;
  
  final KisUnifiedApiService _apiService;
  
  LoadAccountDataUseCase(this._apiService);
  
  /// 계좌 데이터 로드 실행 (서버 읽기 전용)
  Future<AccountChange> execute({bool silent = false}) async {
    try {
      print('🔍 [UseCase] 계좌(서버) 데이터 로드 시작... (silent='+silent.toString()+')');

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        return AccountDataLoadFailedChange('로그인 필요', 1);
      }

      // 서버에 저장된 설정/계좌 요약 읽기 (마스킹/설정상태)
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('api')
          .get();

      final data = doc.data() ?? const {};
      final isConfigured = data['isConfigured'] == true;
      final maskedAccount = (data['maskedAccount'] ?? '') as String;

      final result = {
        'isConfigured': isConfigured,
        'maskedAccount': maskedAccount,
        'updatedAt': data['updatedAt'],
        // 확장 여지: 서버가 제공하는 요약치(총자산/보유/현금)를 추후 포함
      };

      print('✅ [UseCase] 계좌(서버) 요약 로드 완료: '+result.toString());
      return AccountDataLoadedChange(result);
    } catch (e) {
      print('❌ [UseCase] 계좌(서버) 데이터 로드 실패: '+e.toString());
      return AccountDataLoadFailedChange('계좌 정보를 불러올 수 없습니다: '+e.toString(), 1);
    }
  }
  
  /// 계좌 데이터 통합
  Map<String, dynamic>? _integrateAccountData(
    Map<String, dynamic>? domesticBalance,
    Map<String, dynamic>? overseasNasdBalance,
    Map<String, dynamic>? overseasNyseBalance,
    Map<String, dynamic>? domesticOrderableAmount,
    Map<String, dynamic>? overseasNasdOrderableAmount,
    Map<String, dynamic>? overseasNyseOrderableAmount,
  ) {
    try {
      // 국내 계좌 정보 추출
      final domesticHoldings = domesticBalance?['holdings'] as List<dynamic>? ?? [];
      final domesticAccountInfo = domesticBalance?['accountInfo'] as List<dynamic>? ?? [];
      
      print('🔍 [UseCase] 국내 계좌 원본 데이터:');
      print('  domesticBalance: $domesticBalance');
      print('  domesticHoldings 개수: ${domesticHoldings.length}');
      print('  domesticAccountInfo 개수: ${domesticAccountInfo.length}');
      
      // 해외 계좌 정보 추출
      final overseasNasdHoldings = overseasNasdBalance?['holdings'] as List<dynamic>? ?? [];
      final overseasNyseHoldings = overseasNyseBalance?['holdings'] as List<dynamic>? ?? [];
      final overseasNasdCash = overseasNasdBalance?['cashBalance'] as List<dynamic>? ?? [];
      final overseasNyseCash = overseasNyseBalance?['cashBalance'] as List<dynamic>? ?? [];
      
      print('🔍 [UseCase] 해외 계좌 원본 데이터:');
      print('  overseasNasdBalance: $overseasNasdBalance');
      print('  overseasNyseBalance: $overseasNyseBalance');
      print('  overseasNasdHoldings 개수: ${overseasNasdHoldings.length}');
      print('  overseasNyseHoldings 개수: ${overseasNyseHoldings.length}');
      print('  overseasNasdCash 개수: ${overseasNasdCash.length}');
      print('  overseasNyseCash 개수: ${overseasNyseCash.length}');
      
      // 해외 보유종목 통합
      final allOverseasHoldings = [...overseasNasdHoldings, ...overseasNyseHoldings];
      
      // 국내 보유종목 데이터 변환
      final transformedDomesticHoldings = _transformDomesticHoldings(domesticHoldings);
      
      // 해외 보유종목 데이터 변환
      final transformedOverseasHoldings = _transformOverseasHoldings(allOverseasHoldings);
      
      // 실제 보유 종목 합계 계산 (디버깅용)
      double actualDomesticTotal = 0.0;
      for (final holding in transformedDomesticHoldings) {
        actualDomesticTotal += holding['totalValue'] as double;
      }
      print('🔍 [UseCase] 실제 보유 종목 합계: ${actualDomesticTotal}원');
      
      // 국내 계좌 정보 계산 (실제 보유 종목 기준으로 계산)
      double domesticTotalAssets = 0.0;
      double domesticTotalProfit = 0.0;
      double domesticAvailableBalance = 0.0;
      
      // 실제 보유 종목의 합계로 총 자산과 손익 계산
      for (final holding in transformedDomesticHoldings) {
        domesticTotalAssets += holding['totalValue'] as double;
        domesticTotalProfit += holding['profit'] as double;
      }
      
      // 공식 주문가능금액 API에서 주문가능금액 가져오기
      if (domesticOrderableAmount != null) {
        print('📊 [UseCase] 국내 주문가능금액 API 응답:');
        domesticOrderableAmount.forEach((key, value) {
          print('  $key: $value');
        });
        
        // 공식 문서 기준 필드명 사용 (실제 주문가능금액 우선)
        final nrcvbBuyAmt = _parseDouble(domesticOrderableAmount['nrcvb_buy_amt']);
        final maxBuyAmt = _parseDouble(domesticOrderableAmount['max_buy_amt']);
        final ordPsblCash = _parseDouble(domesticOrderableAmount['ord_psbl_cash']);
        
        print('🔍 [UseCase] 파싱된 값들:');
        print('  nrcvb_buy_amt 파싱 결과: $nrcvbBuyAmt');
        print('  max_buy_amt 파싱 결과: $maxBuyAmt');
        print('  ord_psbl_cash 파싱 결과: $ordPsblCash');
        
        domesticAvailableBalance = nrcvbBuyAmt ??  // 미수없는매수금액 (1,413원)
                                  maxBuyAmt ??    // 최대매수금액 (1,413원)
                                  ordPsblCash ??  // 주문가능현금 (4,262원 - fallback)
                                  0.0;
        
        print('📊 [UseCase] 국내 계좌 주문가능금액 파싱 결과:');
        print('  ord_psbl_cash: ${domesticOrderableAmount['ord_psbl_cash']} (주문가능현금)');
        print('  ord_psbl_sbst: ${domesticOrderableAmount['ord_psbl_sbst']} (주문가능대용)');
        print('  ruse_psbl_amt: ${domesticOrderableAmount['ruse_psbl_amt']} (재사용가능금액)');
        print('  nrcvb_buy_amt: ${domesticOrderableAmount['nrcvb_buy_amt']} (미수없는매수금액)');
        print('  max_buy_amt: ${domesticOrderableAmount['max_buy_amt']} (최대매수금액)');
        print('  cma_evlu_amt: ${domesticOrderableAmount['cma_evlu_amt']} (CMA평가금액)');
        print('  최종 주문가능금액: ${domesticAvailableBalance}');
      } else {
        print('⚠️ [UseCase] 국내 주문가능금액 API 응답이 null');
      }
      
      print('📊 [UseCase] 국내 계좌 정보 (실제 보유종목 기준):');
      print('  총 자산: ${domesticTotalAssets}원');
      print('  총 손익: ${domesticTotalProfit}원');
      print('  주문가능: ${domesticAvailableBalance}원');
      print('  보유종목 수: ${transformedDomesticHoldings.length}개');
      
       // 해외 계좌 정보 계산 (보유 종목 + 주문가능금액 기준으로 계산)
       double overseasTotalAssets = 0.0;
       double overseasTotalProfit = 0.0;
       double overseasAvailableBalance = 0.0;
       
       // 해외 보유 종목의 자산과 손익 계산
       for (final holding in transformedOverseasHoldings) {
         overseasTotalAssets += holding['totalValue'] as double;
         overseasTotalProfit += holding['profit'] as double;
       }
       
       // 해외 주문가능금액을 총 자산에 포함 (현금 잔고)
       double overseasCashBalance = 0.0;
       double overseasOrderableAmount = 0.0;
      
      // 공식 해외 주문가능금액 API에서 주문가능금액 가져오기
      print('🔍 [UseCase] 해외 주문가능금액 API 응답 분석:');
      
       // 나스닥 주문가능금액
       if (overseasNasdOrderableAmount != null) {
         print('📊 [UseCase] 해외 나스닥 주문가능금액 API 응답:');
         overseasNasdOrderableAmount.forEach((key, value) {
           print('  $key: $value');
         });
         
         // ovrs_ord_psbl_amt: 해외주문가능금액 (총 자산)
         final nasdOrderableAmount = _parseDouble(overseasNasdOrderableAmount['ovrs_ord_psbl_amt']) ?? 0.0;
         // ord_psbl_frcr_amt: 주문가능외화금액 (현금 잔고)
         final nasdCashBalance = _parseDouble(overseasNasdOrderableAmount['ord_psbl_frcr_amt']) ?? 0.0;
         
         overseasOrderableAmount += nasdOrderableAmount;
         overseasAvailableBalance += nasdOrderableAmount;
         overseasCashBalance += nasdCashBalance;
         
         print('📊 [UseCase] 해외 나스닥 주문가능금액: \$${nasdOrderableAmount}');
         print('📊 [UseCase] 해외 나스닥 현금 잔고: \$${nasdCashBalance}');
       }
       
       // 뉴욕 주문가능금액
       if (overseasNyseOrderableAmount != null) {
         print('📊 [UseCase] 해외 뉴욕 주문가능금액 API 응답:');
         overseasNyseOrderableAmount.forEach((key, value) {
           print('  $key: $value');
         });
         
         // ovrs_ord_psbl_amt: 해외주문가능금액 (총 자산)
         final nyseOrderableAmount = _parseDouble(overseasNyseOrderableAmount['ovrs_ord_psbl_amt']) ?? 0.0;
         // ord_psbl_frcr_amt: 주문가능외화금액 (현금 잔고)
         final nyseCashBalance = _parseDouble(overseasNyseOrderableAmount['ord_psbl_frcr_amt']) ?? 0.0;
         
         overseasOrderableAmount += nyseOrderableAmount;
         overseasAvailableBalance += nyseOrderableAmount;
         overseasCashBalance += nyseCashBalance;
         
         print('📊 [UseCase] 해외 뉴욕 주문가능금액: \$${nyseOrderableAmount}');
         print('📊 [UseCase] 해외 뉴욕 현금 잔고: \$${nyseCashBalance}');
       }
      
       // 해외 현금 잔고 정보 (output2에서 현금 잔고 정보) - 추가 정보용
       print('🔍 [UseCase] 해외 현금 데이터 상세 분석:');
       print('  overseasNasdCash 개수: ${overseasNasdCash.length}');
       print('  overseasNyseCash 개수: ${overseasNyseCash.length}');
       
       for (final cash in [...overseasNasdCash, ...overseasNyseCash]) {
         final cashMap = cash as Map<String, dynamic>;
         
         // API 응답 필드명 디버깅
         print('📊 [UseCase] 해외 계좌 output2 필드들:');
         cashMap.forEach((key, value) {
           print('  $key: $value');
         });
         
         // KIS API 공식 필드명 사용 (공식 문서 기준)
         // frcr_evlu_amt: 외화평가금액 (현금 잔고)
         final cashAmount = _parseDouble(cashMap['frcr_evlu_amt']) ?? 0.0;
         
         // 주문가능금액 API에서 이미 현금 잔고를 가져왔으므로 중복 계산 방지
         // overseasTotalAssets += cashAmount; // 이 부분 제거
         
         print('📊 [UseCase] 해외 현금 파싱 결과:');
         print('  frcr_evlu_amt: ${cashMap['frcr_evlu_amt']} → ${cashAmount}');
       }
      
      // 해외 현금 데이터가 없는 경우 디버깅
      if (overseasNasdCash.isEmpty && overseasNyseCash.isEmpty) {
        print('⚠️ [UseCase] 해외 현금 데이터가 없음 - API 응답 확인 필요');
        print('⚠️ [UseCase] 해외 계좌가 없거나 API 호출 실패 가능성');
      }
      
       // 해외 계좌 총 자산 = 보유종목 자산 + 주문가능금액 (현금 잔고)
       overseasTotalAssets += overseasOrderableAmount;
       
       // 해외 계좌 데이터가 전혀 없는 경우 기본값 설정
       if (overseasTotalAssets == 0.0 && overseasTotalProfit == 0.0 && overseasAvailableBalance == 0.0) {
         print('⚠️ [UseCase] 해외 계좌 데이터가 모두 0 - 해외 계좌 없음 또는 API 오류');
         print('⚠️ [UseCase] 해외 계좌가 없는 경우 정상적인 상황일 수 있음');
         
         // 해외 계좌가 없는 경우 기본값으로 설정 (0으로 유지)
         overseasTotalAssets = 0.0;
         overseasTotalProfit = 0.0;
         overseasAvailableBalance = 0.0;
       }
      
       print('📊 [UseCase] 해외 계좌 정보 (보유종목 + 주문가능금액 기준):');
       print('  보유종목 자산: \$${overseasTotalAssets - overseasOrderableAmount}');
       print('  주문가능금액 (현금): \$${overseasOrderableAmount}');
       print('  총 자산: \$${overseasTotalAssets}');
       print('  총 손익: \$${overseasTotalProfit}');
       print('  주문가능 (ovrs_ord_psbl_amt): \$${overseasAvailableBalance}');
       print('  보유종목 수: ${transformedOverseasHoldings.length}개');
      
      // 수익률 계산
      final domesticProfitRate = domesticTotalAssets > 0 ? (domesticTotalProfit / domesticTotalAssets) * 100 : 0.0;
      final overseasProfitRate = overseasTotalAssets > 0 ? (overseasTotalProfit / overseasTotalAssets) * 100 : 0.0;
      
      return {
        // 국내 계좌 정보
        'domesticHoldings': transformedDomesticHoldings,
        'domesticTotalAssets': domesticTotalAssets,
        'domesticTotalProfit': domesticTotalProfit,
        'domesticProfitRate': domesticProfitRate,
        'domesticAvailableBalance': domesticAvailableBalance,
        
        // 해외 계좌 정보
        'overseasHoldings': transformedOverseasHoldings,
        'overseasTotalAssets': overseasTotalAssets,
        'overseasTotalProfit': overseasTotalProfit,
        'overseasProfitRate': overseasProfitRate,
        'overseasAvailableBalance': overseasAvailableBalance,
        
        // 통합 정보
        'totalAssets': domesticTotalAssets + overseasTotalAssets,
        'totalProfit': domesticTotalProfit + overseasTotalProfit,
        'allHoldings': [...transformedDomesticHoldings, ...transformedOverseasHoldings],
      };
    } catch (e) {
      print('❌ [UseCase] 계좌 데이터 통합 실패: $e');
      return null;
    }
  }
  
  /// 국내 보유종목 데이터 변환 (보유수량 0인 종목 필터링)
  List<Map<String, dynamic>> _transformDomesticHoldings(List<dynamic> holdings) {
    return holdings
        .where((holding) {
          final holdingMap = holding as Map<String, dynamic>;
          final quantity = _parseDouble(holdingMap['hldg_qty'])?.toInt() ?? 0;
          return quantity > 0; // 보유수량이 0보다 큰 종목만 필터링
        })
        .map((holding) {
          final holdingMap = holding as Map<String, dynamic>;
          final quantity = _parseDouble(holdingMap['hldg_qty'])?.toInt() ?? 0;
          final avgPrice = _parseDouble(holdingMap['pchs_avg_pric']) ?? 0.0;
          final currentPrice = _parseDouble(holdingMap['prpr']) ?? 0.0;
          final totalValue = _parseDouble(holdingMap['evlu_amt']) ?? 0.0;
          final profit = _parseDouble(holdingMap['evlu_pfls_amt']) ?? 0.0;
          final profitRate = _parseDouble(holdingMap['evlu_pfls_rt']) ?? 0.0;
          
          return {
            'stockCode': holdingMap['pdno'] ?? '',
            'stockName': holdingMap['prdt_name'] ?? '',
            'quantity': quantity,
            'avgPrice': avgPrice,
            'currentPrice': currentPrice,
            'totalValue': totalValue,
            'profit': profit,
            'profitRate': profitRate,
          };
        }).toList();
  }
  
  /// 해외 보유종목 데이터 변환 (보유수량 0인 종목 필터링)
  List<Map<String, dynamic>> _transformOverseasHoldings(List<dynamic> holdings) {
    return holdings
        .where((holding) {
          final holdingMap = holding as Map<String, dynamic>;
          // 수량 키가 응답에 따라 다름: ovrs_cblc_qty | cblc_qty | hldg_qty | quantity
          final quantity = _parseDouble(
                holdingMap['ovrs_cblc_qty'] ??
                holdingMap['cblc_qty'] ??
                holdingMap['hldg_qty'] ??
                holdingMap['quantity'],
              )
              ?.toInt() ?? 0;
          return quantity > 0; // 보유수량이 0보다 큰 종목만 필터링
        })
        .map((holding) {
          final holdingMap = holding as Map<String, dynamic>;
          final quantity = _parseDouble(
                holdingMap['ovrs_cblc_qty'] ??
                holdingMap['cblc_qty'] ??
                holdingMap['hldg_qty'] ??
                holdingMap['quantity'],
              )
              ?.toInt() ?? 0;
          final avgPrice = _parseDouble(holdingMap['pchs_avg_pric'] ?? holdingMap['avg_pric'] ?? holdingMap['avgPrice']) ?? 0.0;
          // 현재가 키 다양성 대응: now_pric2 | ovrs_now_prpr | now_prpr | last | prpr
          final currentPrice = _parseDouble(
                holdingMap['now_pric2'] ??
                holdingMap['ovrs_now_prpr'] ??
                holdingMap['now_prpr'] ??
                holdingMap['prpr'] ??
                holdingMap['last'],
              ) ?? 0.0;
          // 평가금액 키 다양성 대응: ovrs_stck_evlu_amt | evlu_amt
          final totalValueRaw = _parseDouble(
                holdingMap['ovrs_stck_evlu_amt'] ??
                holdingMap['evlu_amt'],
              ) ?? 0.0;
          // 손익 키 다양성 대응: ovrs_stck_evlu_pfls_amt | evlu_pfls_amt
          final profitRaw = _parseDouble(
                holdingMap['ovrs_stck_evlu_pfls_amt'] ??
                holdingMap['evlu_pfls_amt'],
              ) ?? 0.0;
          // 수익률 키 다양성 대응: ovrs_stck_evlu_pfls_rt | evlu_pfls_rt
          final profitRateRaw = _parseDouble(
                holdingMap['ovrs_stck_evlu_pfls_rt'] ??
                holdingMap['evlu_pfls_rt'],
              ) ?? 0.0;

          // 거래탭과 동일한 폴백 계산 적용
          final computedTotalValue = totalValueRaw > 0
              ? totalValueRaw
              : (currentPrice > 0 && quantity > 0
                  ? currentPrice * quantity
                  : 0.0);
          final computedProfit = profitRaw != 0.0
              ? profitRaw
              : (avgPrice > 0 && currentPrice > 0 && quantity > 0
                  ? (currentPrice - avgPrice) * quantity
                  : 0.0);
          final baseForRate = computedTotalValue > 0
              ? computedTotalValue
              : (avgPrice > 0 && quantity > 0 ? avgPrice * quantity : 0.0);
          final computedProfitRate = profitRateRaw != 0.0
              ? profitRateRaw
              : (baseForRate > 0 ? (computedProfit / baseForRate) * 100.0 : 0.0);
          
          return {
            // 종목코드 키 다양성 대응: ovrs_pdno | ovrs_item_cd | ITEM_CD | item_cd | SYMB | symb
            'stockCode': (holdingMap['ovrs_pdno'] ??
                          holdingMap['ovrs_item_cd'] ??
                          holdingMap['ITEM_CD'] ??
                          holdingMap['item_cd'] ??
                          holdingMap['SYMB'] ??
                          holdingMap['symb'] ??
                          '') as String,
            // 종목명 키 다양성 대응
            'stockName': (holdingMap['ovrs_item_name'] ??
                          holdingMap['item_name'] ??
                          '') as String,
            'quantity': quantity,
            'avgPrice': avgPrice,
            'currentPrice': currentPrice,
            'totalValue': computedTotalValue,
            'profit': computedProfit,
            'profitRate': computedProfitRate,
          };
        }).toList();
  }

  /// 안전한 double 파싱
  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.replaceAll(',', ''));
    }
    return null;
  }
}
