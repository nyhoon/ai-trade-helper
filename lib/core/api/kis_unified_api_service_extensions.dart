/// KIS 통일 API 서비스 - 편의 확장 함수
/// 
/// 공식 가이드를 100% 준수한 후에 추가된 편의성 확장 함수들
/// 
/// @author AI Assistant
/// @version 1.0.0
/// @since 2024-01-01

import 'dart:math' as math;
import 'kis_unified_api_service.dart';

/// 편의성 확장 함수들
extension KisUnifiedApiServiceExtensions on KisUnifiedApiService {
  
  /// ========================================
  /// 편의성 확장 함수들 (우리만의 기능)
  /// ========================================
  
  /// 종목 코드 자동 판별 및 현재가 조회
  /// 
  /// 종목 코드 패턴을 분석하여 국내/해외 자동 판별
  /// - 국내주식: 6자리 숫자 (예: 005930)
  /// - 해외주식: 1-5자리 영문 (예: AAPL, TSLA)
  Future<Map<String, dynamic>?> getStockPriceAuto(String stockCode) async {
    // 서버 전환: 클라이언트에서 통일API 호출 금지
    return null;
  }
  
  /// 종목 코드 자동 판별 및 차트 조회
  /// 
  /// 종목 코드 패턴을 분석하여 국내/해외 자동 판별 후 차트 조회
  Future<List<Map<String, dynamic>>> getChartDataAuto(
    String stockCode, {
    String period = 'D',
    int count = 80,
  }) async {
    try {
      print('📊 [확장API] 차트 자동 판별: $stockCode (기간: $period)');
      
      // 해외주식 판별 (대문자 영문 1-5자리)
      if (RegExp(r'^[A-Z]{1,5}$').hasMatch(stockCode)) {
        return await getOverseasDailyChart(
          symbol: stockCode,
          exchangeCode: 'NAS', // 기본값: 나스닥
          periodCode: period,
          count: count,
        );
      } else {
        return await getDomesticDailyChart(
          stockCode: stockCode,
          periodCode: period,
          count: count,
        );
      }
    } catch (e) {
      print('❌ [확장API] 차트 자동 판별 오류: $e');
      return [];
    }
  }
  
  /// 통합 계좌 정보 조회 (국내 + 해외)
  /// 
  /// 국내와 해외 계좌 정보를 모두 조회하여 통합된 결과 반환
  Future<Map<String, dynamic>?> getUnifiedAccountInfo() async {
    try {
      print('💰 [확장API] 통합 계좌 정보 조회 시작');
      
      final cano = extractCano();
      final acntPrdtCd = extractPrdtCd();
      
      // 1. 국내 계좌 잔고 조회 (계좌 확장 파일 사용)
      print('🔍 [확장API] 국내 계좌 잔고 조회 시작 - cano: $cano, acntPrdtCd: $acntPrdtCd');
      final domesticBalance = await getDomesticAccountBalance(
        cano: cano,
        acntPrdtCd: acntPrdtCd,
      );
      print('📊 [확장API] 국내 계좌 잔고 조회 결과: ${domesticBalance != null ? '성공' : '실패'}');
      if (domesticBalance != null) {
        print('📊 [확장API] 국내 보유종목 개수: ${(domesticBalance['holdings'] as List?)?.length ?? 0}개');
        final holdings = domesticBalance['holdings'] as List? ?? [];
        for (int i = 0; i < holdings.length; i++) {
          final holding = holdings[i];
          print('  국내 보유종목 ${i+1}: ${holding['pdno']} - ${holding['prdt_name']} (${holding['hldg_qty']}주)');
        }
      }
      
      // 2. 해외 계좌 잔고 조회 (계좌 확장 파일 사용)
      // 서버 전용 모드: 해외 계좌 잔고 조회 비활성화 (UI는 서버 데이터만 사용)
      print('⛔ [확장API] 해외 계좌 잔고 조회 비활성화 - 서버 전용 모드');
      final Map<String, dynamic>? overseasBalance = null;
      
      // 3. 결과 통합
      final result = {
        'domestic': domesticBalance,
        'overseas': overseasBalance,
        'domesticHoldings': domesticBalance?['holdings'] ?? [],
        'overseasHoldings': overseasBalance?['holdings'] ?? [],
        'timestamp': DateTime.now().toIso8601String(),
        'totalValue': _calculateTotalValue(domesticBalance, overseasBalance),
      };
      
      print('✅ [확장API] 통합 계좌 정보 조회 완료');
      return result;
    } catch (e) {
      print('❌ [확장API] 통합 계좌 정보 조회 오류: $e');
      return null;
    }
  }
  
  /// ========================================
  /// 호환성 메서드들 (기존 코드 지원)
  /// ========================================
  
  /// 보유종목 조회 (호환성)
  Future<List<Map<String, dynamic>>> getPositionsCompat() async {
    try {
      final cano = extractCano();
      final acntPrdtCd = extractPrdtCd();
      
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
      print('❌ [확장API] 보유종목 조회 오류: $e');
      return [];
    }
  }
  
  /// 해외 보유종목 조회 (호환성)
  Future<List<Map<String, dynamic>>> getOverseasHoldingsCompat() async {
    try {
      final cano = extractCano();
      final acntPrdtCd = extractPrdtCd();
      
      // 서버 전용 모드: 해외 보유종목 조회 비활성화
      print('⛔ [확장API] 해외 보유종목 조회 비활성화 - 서버 전용 모드');
      final Map<String, dynamic>? overseas = null;
      
      if (overseas != null && overseas['holdings'] != null) {
        final holdings = overseas['holdings'] as List;
        return holdings.cast<Map<String, dynamic>>();
      }
      
      return [];
    } catch (e) {
      print('❌ [확장API] 해외 보유종목 조회 오류: $e');
      return [];
    }
  }
  
  /// 해외주식 잔고 조회 (호환성)
  Future<List<Map<String, dynamic>>> getOverseasPresentBalanceCompat({String exchangeCode = 'NASD'}) async {
    try {
      final cano = extractCano();
      final acntPrdtCd = extractPrdtCd();
      final balance = await getOverseasAccountBalance(
        cano: cano,
        acntPrdtCd: acntPrdtCd,
        ovrsExcCd: exchangeCode,
      );
      
      if (balance != null && balance['holdings'] != null) {
        final holdings = balance['holdings'] as List;
        return holdings.cast<Map<String, dynamic>>();
      }
      
      return [];
    } catch (e) {
      print('❌ [확장API] 해외주식 잔고 조회 오류: $e');
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
      print('❌ [확장API] 해외주식 체결내역 조회 오류: $e');
      return [];
    }
  }
  
  /// 해외주식 결제준비금 조회 (호환성)
  Future<double> getOverseasPaymentStandardBalanceCompat() async {
    try {
      final cano = extractCano();
      final acntPrdtCd = extractPrdtCd();
      // 서버 전용 모드: 해외 결제준비금 조회 비활성화
      print('⛔ [확장API] 해외 결제준비금 조회 비활성화 - 서버 전용 모드');
      final Map<String, dynamic>? balance = null;
      
      if (balance != null && balance['cashBalance'] != null) {
        final cashBalance = balance['cashBalance'] as List;
        if (cashBalance.isNotEmpty) {
          final cash = cashBalance.first as Map<String, dynamic>;
          return parseDouble(cash['frcr_evlu_amt']);
        }
      }
      
      return 0.0;
    } catch (e) {
      print('❌ [확장API] 해외주식 결제준비금 조회 오류: $e');
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
    String stockCode = 'AAPL', // 기본값: 애플
    double price = 150.0, // 기본값: 150달러
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
          print('✅ [확장API] 해외 매수가능금액: \$${buyableAmount.toStringAsFixed(2)}');
          return buyableAmount;
        }
      }
      
      print('❌ [확장API] 해외 매수가능금액 조회 실패: ${response.data}');
      return 0.0;
    } catch (e) {
      print('❌ [확장API] 해외 매수가능금액 조회 오류: $e');
      return 0.0;
    }
  }
  
  /// 보유종목 조회 (기존 호환성)
  Future<List<Map<String, dynamic>>> getPositions() async {
    return await getPositionsCompat();
  }
  
  /// ========================================
  /// 유틸리티 메서드들
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

  /// 인증 상태 확인 (메인 API 서비스에서 제공)
  bool get isAuthenticated => isAuthenticated;

  /// API 설정 정보 (메인 API 서비스에서 제공)
  Map<String, dynamic> get apiConfig => apiConfig;

  /// 계좌 번호에서 CANO 추출 (메인 API 서비스에서 제공)
  String extractCano() => extractCano();

  /// 계좌 번호에서 ACNT_PRDT_CD 추출 (메인 API 서비스에서 제공)
  String extractPrdtCd() => extractPrdtCd();

  /// 해외 고객 번호 추출 (기본값 사용)
  String _extractOverseasCustNo() {
    // 실제 구현에서는 해외 고객 번호를 조회해야 함
    // 현재는 기본값 사용
    return '0000000000';
  }
  
  /// 해외주식 미체결 주문 조회
  Future<List<Map<String, dynamic>>> getOverseasPendingOrders() async {
    try {
      print('📋 [확장API] 해외주식 미체결 주문 조회');
      
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
          print('✅ [확장API] 해외주식 미체결 주문: ${output.length}개');
          return output.cast<Map<String, dynamic>>();
        }
      }
      
      return [];
    } catch (e) {
      print('❌ [확장API] 해외주식 미체결 주문 조회 오류: $e');
      return [];
    }
  }

  /// 해외주식 주문 체결 확인
  Future<Map<String, dynamic>?> checkOverseasOrderExecution(String orderId) async {
    try {
      print('🔍 [확장API] 해외주식 주문 체결 확인: $orderId');
      
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
      print('❌ [확장API] 해외주식 주문 체결 확인 오류: $e');
      return null;
    }
  }

  /// 해외주식 기간별 거래내역 조회
  Future<List<Map<String, dynamic>>> getOverseasPeriodTransactions({
    required String startDate,
    required String endDate,
    String exchangeCode = 'NASD',
  }) async {
    try {
      print('📊 [확장API] 해외주식 기간별 거래내역 조회: $startDate ~ $endDate');
      
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
          print('✅ [확장API] 해외주식 기간별 거래내역: ${output.length}개');
          return output.cast<Map<String, dynamic>>();
        }
      }
      
      return [];
    } catch (e) {
      print('❌ [확장API] 해외주식 기간별 거래내역 조회 오류: $e');
      return [];
    }
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
      print('❌ [확장API] 연결 상태 확인 실패: $e');
      return false;
    }
  }

  /// 국내주식 현재가 조회 (호환성)
  Future<Map<String, dynamic>?> getDomesticCurrentPrice(String stockCode) async {
    try {
      final priceData = await getStockPrice(stockCode);
      if (priceData != null) {
        return {
          'prpr': priceData['prpr'],
          'stockName': priceData['stockName'],
          'diff': priceData['diff'],
          'rate': priceData['rate'],
        };
      }
      return null;
    } catch (e) {
      print('❌ [확장API] 국내주식 현재가 조회 오류: $e');
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
          'prpr': priceData['prpr'],
          'stockName': symbol,
          'diff': priceData['diff'],
          'rate': priceData['rate'],
        };
      }
      return null;
    } catch (e) {
      print('❌ [확장API] 해외주식 현재가 조회 오류: $e');
      return null;
    }
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
      print('❌ [확장API] 계좌 잔고 조회 오류: $e');
      return null;
    }
  }
  
  /// WebSocket 접속키 발급 (메인 API 서비스에서 제공)
  Future<Map<String, dynamic>?> getWebSocketAccessToken() async {
    // 메인 API 서비스의 메서드 호출
    return await getWebSocketAccessToken();
  }
  
  /// 해외주식 주문 실행
  Future<Map<String, dynamic>?> executeOverseasOrder({
    required String symbol,
    required String orderType, // 'buy' or 'sell'
    required int quantity,
    required double price,
    String exchangeCode = 'NASD',
  }) async {
    try {
      print('📈 [확장API] 해외주식 주문 실행: $symbol, $orderType, $quantity@$price');
      
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
        print('✅ [확장API] 해외주식 주문 성공');
        return response.data;
      } else {
        print('❌ [확장API] 해외주식 주문 실패: ${response?.data['msg1']}');
        return null;
      }
    } catch (e) {
      print('❌ [확장API] 해외주식 주문 오류: $e');
      return null;
    }
  }
  
  /// 종목명 조회
  Future<String?> getStockName(String stockCode) async {
    try {
      print('📝 [확장API] 종목명 조회: $stockCode');
      
      // 해외주식인지 확인
      final isOverseas = RegExp(r'^[A-Z]{1,5}$').hasMatch(stockCode);
      
      if (isOverseas) {
        // 해외주식은 심볼 그대로 반환
        return stockCode;
      } else {
        // 국내주식은 현재가 조회에서 종목명 추출
        final priceData = await getStockPrice(stockCode);
        if (priceData != null && priceData['stockName'] != null) {
          return priceData['stockName'] as String;
        }
        return stockCode; // 기본값으로 종목코드 반환
      }
    } catch (e) {
      print('❌ [확장API] 종목명 조회 오류: $e');
      return stockCode; // 기본값으로 종목코드 반환
    }
  }
  
  /// 종목별 상세 정보 조회
  /// 
  /// 현재가, 차트, 기술적 지표 등을 종합한 상세 정보 제공
  Future<Map<String, dynamic>?> getStockDetailInfo(
    String stockCode, {
    int chartDays = 30,
  }) async {
    try {
      print('📈 [확장API] 종목 상세 정보 조회: $stockCode');
      
      // 1. 현재가 조회
      final currentPrice = await getStockPriceAuto(stockCode);
      if (currentPrice == null) {
        print('❌ [확장API] 현재가 조회 실패: $stockCode');
        return null;
      }
      
      // 2. 차트 데이터 조회
      final chartData = await getChartDataAuto(
        stockCode,
        period: 'D',
        count: chartDays,
      );
      
      // 3. 기술적 지표 계산
      final technicalIndicators = _calculateTechnicalIndicators(chartData);
      
      // 4. 결과 통합
      final result = {
        'stockCode': stockCode,
        'prpr': currentPrice,
        'chartData': chartData,
        'technicalIndicators': technicalIndicators,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      print('✅ [확장API] 종목 상세 정보 조회 완료: $stockCode');
      return result;
    } catch (e) {
      print('❌ [확장API] 종목 상세 정보 조회 오류: $e');
      return null;
    }
  }
  
  /// 포트폴리오 분석
  /// 
  /// 보유 종목들의 포트폴리오 분석 결과 제공
  Future<Map<String, dynamic>?> getPortfolioAnalysis() async {
    try {
      print('📊 [확장API] 포트폴리오 분석 시작');
      
      final accountInfo = await getUnifiedAccountInfo();
      if (accountInfo == null) {
        print('❌ [확장API] 계좌 정보 조회 실패');
        return null;
      }
      
      final domesticHoldings = accountInfo['domestic']?['holdings'] ?? [];
      final overseasHoldings = accountInfo['overseas']?['holdings'] ?? [];
      
      // 포트폴리오 분석 계산
      final analysis = {
        'totalHoldings': domesticHoldings.length + overseasHoldings.length,
        'domesticHoldings': domesticHoldings.length,
        'overseasHoldings': overseasHoldings.length,
        'totalValue': accountInfo['totalValue'],
        'diversification': _calculateDiversification(domesticHoldings, overseasHoldings),
        'riskAnalysis': _calculateRiskAnalysis(domesticHoldings, overseasHoldings),
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      print('✅ [확장API] 포트폴리오 분석 완료');
      return analysis;
    } catch (e) {
      print('❌ [확장API] 포트폴리오 분석 오류: $e');
      return null;
    }
  }
  
  /// 실시간 모니터링
  /// 
  /// 보유 종목들의 실시간 가격 모니터링
  Future<List<Map<String, dynamic>>> getRealTimeMonitoring() async {
    try {
      print('📡 [확장API] 실시간 모니터링 시작');
      
      final accountInfo = await getUnifiedAccountInfo();
      if (accountInfo == null) {
        print('❌ [확장API] 계좌 정보 조회 실패');
        return [];
      }
      
      final domesticHoldings = accountInfo['domestic']?['holdings'] ?? [];
      final overseasHoldings = accountInfo['overseas']?['holdings'] ?? [];
      
      List<Map<String, dynamic>> monitoringData = [];
      
      // 국내주식 모니터링
      for (final holding in domesticHoldings) {
        final stockCode = holding['pdno'] ?? '';
        if (stockCode.isNotEmpty) {
          final currentPrice = await getStockPrice(stockCode);
          if (currentPrice != null) {
            monitoringData.add({
              'stockCode': stockCode,
              'stockName': holding['prdt_name'] ?? '',
              'quantity': holding['hldg_qty'] ?? 0,
              'currentPrice': currentPrice,
              'market': 'domestic',
            });
          }
        }
      }
      
      // 해외주식 모니터링
      for (final holding in overseasHoldings) {
        final stockCode = holding['pdno'] ?? '';
        if (stockCode.isNotEmpty) {
          final currentPrice = await getOverseasStockPrice(
            symbol: stockCode,
            exchangeCode: 'NAS',
          );
          if (currentPrice != null) {
            monitoringData.add({
              'stockCode': stockCode,
              'stockName': holding['prdt_name'] ?? '',
              'quantity': holding['hldg_qty'] ?? 0,
              'currentPrice': currentPrice,
              'market': 'overseas',
            });
          }
        }
      }
      
      print('✅ [확장API] 실시간 모니터링 완료: ${monitoringData.length}개 종목');
      return monitoringData;
    } catch (e) {
      print('❌ [확장API] 실시간 모니터링 오류: $e');
      return [];
    }
  }
  
  /// ========================================
  /// 내부 헬퍼 함수들
  /// ========================================
  
  /// 총 자산 가치 계산
  double _calculateTotalValue(
    Map<String, dynamic>? domesticBalance,
    Map<String, dynamic>? overseasBalance,
  ) {
    double totalValue = 0.0;
    
    // 국내 자산 가치
    if (domesticBalance != null) {
      final holdings = domesticBalance['holdings'] as List? ?? [];
      for (final holding in holdings) {
        final quantity = _parseDouble(holding['hldg_qty']);
        final price = _parseDouble(holding['prpr']);
        totalValue += quantity * price;
      }
    }
    
    // 해외 자산 가치 (USD 기준)
    if (overseasBalance != null) {
      final holdings = overseasBalance['holdings'] as List? ?? [];
      for (final holding in holdings) {
        final quantity = _parseDouble(holding['hldg_qty']);
        final price = _parseDouble(holding['prpr']);
        totalValue += quantity * price;
      }
    }
    
    return totalValue;
  }
  
  /// 기술적 지표 계산 (간단한 버전만 유지)
  /// @dynamicCal/ 폴더의 전문 계산기는 UnifiedAnalysisService에서 사용
  Map<String, dynamic> _calculateTechnicalIndicators(List<Map<String, dynamic>> chartData) {
    if (chartData.isEmpty) {
      return {};
    }
    
    final closes = chartData.map((item) => _parseDouble(item['close'])).toList();
    final volumes = chartData.map((item) => _parseInt(item['volume'])).toList();
    
    // 기본 지표만 계산 (호환성 유지)
    return {
      'sma20': _calculateSMA(closes, 20),
      'sma50': _calculateSMA(closes, 50),
      'rsi': _calculateRSI(closes, 14),
      'volumeAvg': _calculateAverage(volumes),
      'volatility': _calculateVolatility(closes),
      'priceHistory': closes,
      'volumeHistory': volumes,
    };
  }
  
  /// 포트폴리오 다양성 계산
  Map<String, dynamic> _calculateDiversification(
    List domesticHoldings,
    List overseasHoldings,
  ) {
    final totalHoldings = domesticHoldings.length + overseasHoldings.length;
    
    return {
      'domesticRatio': totalHoldings > 0 ? domesticHoldings.length / totalHoldings : 0.0,
      'overseasRatio': totalHoldings > 0 ? overseasHoldings.length / totalHoldings : 0.0,
      'diversificationScore': _calculateDiversificationScore(domesticHoldings, overseasHoldings),
    };
  }
  
  /// 리스크 분석
  Map<String, dynamic> _calculateRiskAnalysis(
    List domesticHoldings,
    List overseasHoldings,
  ) {
    return {
      'concentrationRisk': _calculateConcentrationRisk(domesticHoldings, overseasHoldings),
      'marketRisk': _calculateMarketRisk(domesticHoldings, overseasHoldings),
      'liquidityRisk': _calculateLiquidityRisk(domesticHoldings, overseasHoldings),
    };
  }
  
  /// 단순 이동평균 계산
  double _calculateSMA(List<double> prices, int period) {
    if (prices.length < period) return 0.0;
    
    final recentPrices = prices.take(period).toList();
    return recentPrices.reduce((a, b) => a + b) / period;
  }
  
  /// RSI 계산
  double _calculateRSI(List<double> prices, int period) {
    if (prices.length < period + 1) return 50.0;
    
    double gain = 0.0;
    double loss = 0.0;
    
    for (int i = 1; i <= period; i++) {
      final change = prices[i] - prices[i - 1];
      if (change > 0) {
        gain += change;
      } else {
        loss += -change;
      }
    }
    
    final avgGain = gain / period;
    final avgLoss = loss / period;
    
    if (avgLoss == 0) return 100.0;
    
    final rs = avgGain / avgLoss;
    return 100 - (100 / (1 + rs));
  }
  
  /// 평균 계산
  double _calculateAverage(List<int> values) {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }
  
  /// 변동성 계산
  double _calculateVolatility(List<double> prices) {
    if (prices.length < 2) return 0.0;
    
    final returns = <double>[];
    for (int i = 1; i < prices.length; i++) {
      returns.add((prices[i] - prices[i - 1]) / prices[i - 1]);
    }
    
    final mean = returns.reduce((a, b) => a + b) / returns.length;
    final variance = returns.map((r) => (r - mean) * (r - mean)).reduce((a, b) => a + b) / returns.length;
    
    return variance * 100; // 백분율로 변환
  }
  
  /// 다양성 점수 계산
  double _calculateDiversificationScore(List domesticHoldings, List overseasHoldings) {
    // 간단한 다양성 점수 계산 (0-100)
    final totalHoldings = domesticHoldings.length + overseasHoldings.length;
    if (totalHoldings == 0) return 0.0;
    
    final domesticRatio = domesticHoldings.length / totalHoldings;
    final overseasRatio = overseasHoldings.length / totalHoldings;
    
    // 균형잡힌 포트폴리오일수록 높은 점수
    final balanceScore = 100 - (domesticRatio - overseasRatio).abs() * 100;
    final quantityScore = (totalHoldings / 20 * 100).clamp(0, 100); // 최대 20개 종목 기준
    
    return (balanceScore + quantityScore) / 2;
  }
  
  /// 집중도 리스크 계산
  double _calculateConcentrationRisk(List domesticHoldings, List overseasHoldings) {
    // 보유 종목 수가 적을수록 높은 집중도 리스크
    final totalHoldings = domesticHoldings.length + overseasHoldings.length;
    return (20 - totalHoldings).clamp(0, 20) / 20 * 100;
  }
  
  /// 시장 리스크 계산
  double _calculateMarketRisk(List domesticHoldings, List overseasHoldings) {
    // 해외 비중이 높을수록 높은 시장 리스크
    final totalHoldings = domesticHoldings.length + overseasHoldings.length;
    if (totalHoldings == 0) return 0.0;
    
    final overseasRatio = overseasHoldings.length / totalHoldings;
    return overseasRatio * 100;
  }
  
  /// 유동성 리스크 계산
  double _calculateLiquidityRisk(List domesticHoldings, List overseasHoldings) {
    // 해외 비중이 높을수록 높은 유동성 리스크
    final totalHoldings = domesticHoldings.length + overseasHoldings.length;
    if (totalHoldings == 0) return 0.0;
    
    final overseasRatio = overseasHoldings.length / totalHoldings;
    return overseasRatio * 100;
  }
  
  /// Double 파싱 헬퍼
  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }
  
  /// Int 파싱 헬퍼
  int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

}
