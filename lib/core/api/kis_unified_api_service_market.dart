/// KIS 통일 API 서비스 - 시장 데이터 관련 기능 확장
/// 
/// 시장 데이터 조회, 현재가 조회 등 시장 관련 API들을 담당
/// 
/// @author AI Assistant
/// @version 1.0.0
/// @since 2024-01-01

import 'kis_unified_api_service.dart';

/// 시장 데이터 관련 기능 확장
extension KisUnifiedApiServiceMarket on KisUnifiedApiService {
  
  /// ========================================
  /// 국내주식 현재가 API (공식 가이드라인)
  /// ========================================
  
  /// 국내주식 현재가 조회 (공식 가이드라인 준수)
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/domestic-stock/v1/quotations/inquire-price
  /// - TR ID: FHKST01010100 (실전/모의 동일)
  /// - 필수 파라미터: env_dv, fid_cond_mrkt_div_code, fid_input_iscd
  Future<Map<String, dynamic>> getDomesticCurrentPrice(String stockCode) async {
    try {
      print('🇰🇷 [통일API] 국내주식 현재가 조회: $stockCode');
      
      final response = await authedGet(
        '/uapi/domestic-stock/v1/quotations/inquire-price',
        {
          'env_dv': 'real', // 실전 거래
          'fid_cond_mrkt_div_code': 'J', // J: KRX
          'fid_input_iscd': stockCode,
        },
        trId: 'FHKST01010100',
      );

      if (response.statusCode == 200 && response.data['rt_cd'] == '0') {
        final output = response.data['output'];
        if (output != null) {
          return _parseDomesticCurrentPriceResponse(output);
        }
      }
      
      print('❌ [통일API] 국내주식 현재가 조회 실패: ${response.data}');
      return {};
    } catch (e) {
      print('❌ [통일API] 국내주식 현재가 조회 오류: $e');
      return {};
    }
  }

  /// ========================================
  /// 해외주식 현재가 API (공식 가이드라인)
  /// ========================================
  
  /// 해외주식 현재가 조회 (공식 가이드라인 준수)
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/overseas-price/v1/quotations/price
  /// - TR ID: HHDFS00000300 (실전/모의 동일)
  /// - 필수 파라미터: auth, excd, symb, env_dv
  Future<Map<String, dynamic>> getOverseasCurrentPrice(String symbol) async {
    try {
      print('🌍 [통일API] 해외주식 현재가 조회: $symbol');
      
      final response = await authedGet(
        '/uapi/overseas-price/v1/quotations/price',
        {
          'auth': '', // 사용자권한정보 (보통 빈 문자열)
          'excd': 'NAS', // 거래소코드: NAS(나스닥), NYS(뉴욕), HKS(홍콩)
          'symb': symbol, // 종목코드
          'env_dv': 'real', // 실전 거래
        },
        trId: 'HHDFS00000300',
      );

      if (response.statusCode == 200 && response.data['rt_cd'] == '0') {
        final output = response.data['output'];
        if (output != null) {
          return _parseOverseasCurrentPriceResponse(output);
        }
      }
      
      print('❌ [통일API] 해외주식 현재가 조회 실패: ${response.data}');
      return {};
    } catch (e) {
      print('❌ [통일API] 해외주식 현재가 조회 오류: $e');
      return {};
    }
  }

  /// ========================================
  /// 시장 정보 API (공식 가이드라인)
  /// ========================================
  
  /// 국내주식 시장 정보 조회
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/domestic-stock/v1/quotations/inquire-market-index
  /// - TR ID: FHPST01010100 (실전/모의 동일)
  Future<Map<String, dynamic>?> getDomesticMarketIndex({
    String marketCode = 'J', // J: KRX, NX: NXT, UN: 통합
  }) async {
    try {
      print('📊 [통일API] 국내주식 시장 정보 조회: $marketCode');
      
      final response = await authedGet(
        '/uapi/domestic-stock/v1/quotations/inquire-market-index',
        {
          'FID_COND_MRKT_DIV_CODE': marketCode,
          'FID_COND_SCR_DIV_CODE': '20178',
        },
        trId: 'FHPST01010100',
      );

      if (response.statusCode == 200 && response.data['rt_cd'] == '0') {
        final output = response.data['output'];
        if (output != null) {
          return _parseDomesticMarketIndexResponse(output);
        }
      }
      
      print('❌ [통일API] 국내주식 시장 정보 조회 실패: ${response.data}');
      return null;
    } catch (e) {
      print('❌ [통일API] 국내주식 시장 정보 조회 오류: $e');
      return null;
    }
  }

  /// 해외주식 시장 정보 조회
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/overseas-price/v1/quotations/inquire-daily-chartprice
  /// - TR ID: FHKST03030100 (실전/모의 동일)
  Future<Map<String, dynamic>?> getOverseasMarketIndex({
    String exchangeCode = 'NAS', // NAS: 나스닥, NYS: 뉴욕, HKS: 홍콩
  }) async {
    try {
      print('🌍 [통일API] 해외주식 시장 정보 조회: $exchangeCode');
      
      // 날짜 설정 (오늘)
      final now = DateTime.now();
      final endDate = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final startDate = now.subtract(Duration(days: 1)).toString().replaceAll('-', '').substring(0, 8);
      
      final response = await authedGet(
        '/uapi/overseas-price/v1/quotations/inquire-daily-chartprice',
        {
          'FID_COND_MRKT_DIV_CODE': 'N', // N: 해외지수
          'FID_INPUT_ISCD': '^IXIC', // 나스닥 지수
          'FID_INPUT_DATE_1': startDate,
          'FID_INPUT_DATE_2': endDate,
          'FID_PERIOD_DIV_CODE': 'D', // D: 일봉
        },
        trId: 'FHKST03030100',
      );

      if (response.statusCode == 200 && response.data['rt_cd'] == '0') {
        final output = response.data['output'];
        if (output != null) {
          return _parseOverseasMarketIndexResponse(output);
        }
      }
      
      print('❌ [통일API] 해외주식 시장 정보 조회 실패: ${response.data}');
      return null;
    } catch (e) {
      print('❌ [통일API] 해외주식 시장 정보 조회 오류: $e');
      return null;
    }
  }

  /// ========================================
  /// 종목 검색 API (공식 가이드라인)
  /// ========================================
  
  /// 국내주식 종목 검색
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/domestic-stock/v1/quotations/inquire-daily-itemchartprice
  /// - TR ID: FHKST03010100 (실전/모의 동일)
  Future<List<Map<String, dynamic>>> searchDomesticStocks({
    required String keyword,
    String marketCode = 'J',
    int limit = 20,
  }) async {
    try {
      print('🔍 [통일API] 국내주식 종목 검색: $keyword');
      
      // 날짜 설정 (오늘)
      final now = DateTime.now();
      final endDate = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final startDate = now.subtract(Duration(days: 1)).toString().replaceAll('-', '').substring(0, 8);
      
      final response = await authedGet(
        '/uapi/domestic-stock/v1/quotations/inquire-daily-itemchartprice',
        {
          'FID_COND_MRKT_DIV_CODE': marketCode,
          'FID_INPUT_ISCD': keyword,
          'FID_INPUT_DATE_1': startDate,
          'FID_INPUT_DATE_2': endDate,
          'FID_PERIOD_DIV_CODE': 'D',
          'FID_ORG_ADJ_PRC': '1',
        },
        trId: 'FHKST03010100',
      );

      if (response.statusCode == 200 && response.data['rt_cd'] == '0') {
        final output = response.data['output2'] ?? [];
        if (output is List) {
          final stocks = output.take(limit).map((item) => _parseDomesticStockSearchResult(item)).toList();
          print('✅ [통일API] 국내주식 종목 검색 성공: ${stocks.length}개');
          return stocks;
        }
      }
      
      print('❌ [통일API] 국내주식 종목 검색 실패: ${response.data}');
      return [];
    } catch (e) {
      print('❌ [통일API] 국내주식 종목 검색 오류: $e');
      return [];
    }
  }

  /// 해외주식 종목 검색
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/overseas-price/v1/quotations/inquire-asking-price
  /// - TR ID: HHDFS76200100 (실전/모의 동일)
  Future<List<Map<String, dynamic>>> searchOverseasStocks({
    required String keyword,
    String exchangeCode = 'NAS',
    int limit = 20,
  }) async {
    try {
      print('🔍 [통일API] 해외주식 종목 검색: $keyword');
      
      final response = await authedGet(
        '/uapi/overseas-price/v1/quotations/inquire-asking-price',
        {
          'AUTH': '',
          'EXCD': exchangeCode,
          'SYMB': keyword,
        },
        trId: 'HHDFS76200100',
      );

      if (response.statusCode == 200 && response.data['rt_cd'] == '0') {
        final output = response.data['output'];
        if (output != null) {
          final stock = _parseOverseasStockSearchResult(output);
          print('✅ [통일API] 해외주식 종목 검색 성공: 1개');
          return [stock];
        }
      }
      
      print('❌ [통일API] 해외주식 종목 검색 실패: ${response.data}');
      return [];
    } catch (e) {
      print('❌ [통일API] 해외주식 종목 검색 오류: $e');
      return [];
    }
  }

  /// ========================================
  /// 편의 메서드 (기존 호환성 유지)
  /// ========================================
  
  /// 종목 검색 (자동 판별)
  Future<List<Map<String, dynamic>>> searchStocks({
    required String keyword,
    String market = 'J',
    int limit = 20,
  }) async {
    try {
      // 해외주식 판별 (대문자 영문 1-5자리)
      if (RegExp(r'^[A-Z]{1,5}$').hasMatch(keyword)) {
        return await searchOverseasStocks(
          keyword: keyword,
          exchangeCode: market,
          limit: limit,
        );
      } else {
        return await searchDomesticStocks(
          keyword: keyword,
          marketCode: market,
          limit: limit,
        );
      }
    } catch (e) {
      print('❌ [통일API] 종목 검색 오류: $e');
      return [];
    }
  }

  /// 시장 정보 조회 (자동 판별)
  Future<Map<String, dynamic>?> getMarketIndex({
    String market = 'J',
  }) async {
    try {
      // 해외주식 판별 (대문자 영문 1-5자리)
      if (RegExp(r'^[A-Z]{1,5}$').hasMatch(market)) {
        return await getOverseasMarketIndex(exchangeCode: market);
      } else {
        return await getDomesticMarketIndex(marketCode: market);
      }
    } catch (e) {
      print('❌ [통일API] 시장 정보 조회 오류: $e');
      return null;
    }
  }

  /// ========================================
  /// 응답 파싱 헬퍼
  /// ========================================
  
  /// 국내주식 현재가 응답 파싱 (원본 필드명 사용)
  Map<String, dynamic> _parseDomesticCurrentPriceResponse(Map<String, dynamic> output) {
    return {
      'stockCode': output['fid_input_iscd'] ?? '',
      'prpr': parseDouble(output['stck_prpr']), // 현재가
      'stck_prdy_clpr': parseDouble(output['stck_prdy_clpr']), // 전일가
      'acml_vol': parseInt(output['acml_vol']), // 거래량
      'high': parseDouble(output['stck_hgpr']), // 고가
      'low': parseDouble(output['stck_lwpr']), // 저가
      'open': parseDouble(output['stck_oprc']), // 시가
      'diff': parseDouble(output['prdy_vrss']), // 전일대비
      'rate': parseDouble(output['prdy_ctrt']), // 전일대비율
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  /// 해외주식 현재가 응답 파싱 (원본 필드명 사용)
  Map<String, dynamic> _parseOverseasCurrentPriceResponse(Map<String, dynamic> output) {
    return {
      'symbol': output['symb'] ?? '',
      'exchange': output['excd'] ?? '',
      'prpr': parseDouble(output['last']), // 현재가
      'stck_prdy_clpr': parseDouble(output['base']), // 전일가
      'acml_vol': parseInt(output['tvol']), // 거래량
      'open': parseDouble(output['open']), // 시가
      'high': parseDouble(output['high']), // 고가
      'low': parseDouble(output['low']), // 저가
      'diff': parseDouble(output['diff']), // 대비
      'rate': parseDouble(output['rate']), // 등락율
      'amount': parseDouble(output['tamt']), // 거래대금
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// 국내주식 시장 정보 응답 파싱
  Map<String, dynamic> _parseDomesticMarketIndexResponse(Map<String, dynamic> output) {
    return {
      'marketCode': output['mrkt_cd'] ?? '',
      'marketName': output['mrkt_nm'] ?? '',
      'index': parseDouble(output['bstp_nmix_prpr']),
      'change': parseDouble(output['bstp_nmix_vrss']),
      'changeRate': parseDouble(output['bstp_nmix_ctrt']),
      'volume': parseInt(output['acml_vol']),
      'amount': parseDouble(output['acml_tr_pbmn']),
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// 해외주식 시장 정보 응답 파싱
  Map<String, dynamic> _parseOverseasMarketIndexResponse(Map<String, dynamic> output) {
    return {
      'symbol': output['symb'] ?? '',
      'exchange': output['excd'] ?? '',
      'index': parseDouble(output['last']),
      'change': parseDouble(output['diff']),
      'changeRate': parseDouble(output['rate']),
      'volume': parseInt(output['tvol']),
      'amount': parseDouble(output['tamt']),
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// 국내주식 종목 검색 결과 파싱
  Map<String, dynamic> _parseDomesticStockSearchResult(Map<String, dynamic> item) {
    return {
      'stockCode': item['pdno'] ?? '',
      'stockName': item['prdt_name'] ?? '',
      'currentPrice': parseDouble(item['prpr']),
      'change': parseDouble(item['prdy_vrss']),
      'changeRate': parseDouble(item['prdy_ctrt']),
      'volume': parseInt(item['acml_vol']),
      'market': 'domestic',
    };
  }

  /// 해외주식 종목 검색 결과 파싱
  Map<String, dynamic> _parseOverseasStockSearchResult(Map<String, dynamic> output) {
    return {
      'stockCode': output['symb'] ?? '',
      'stockName': output['symb'] ?? '', // 해외주식은 심볼만 제공
      'currentPrice': parseDouble(output['last']),
      'change': parseDouble(output['diff']),
      'changeRate': parseDouble(output['rate']),
      'volume': parseInt(output['tvol']),
      'market': 'overseas',
    };
  }
}
