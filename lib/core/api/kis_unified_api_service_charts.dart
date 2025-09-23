/// KIS 통일 API 서비스 - 차트 관련 기능 확장
/// 
/// 차트 데이터 조회, 기술적 지표 계산 등 차트 관련 API들을 담당
/// 
/// @author AI Assistant
/// @version 1.0.0
/// @since 2024-01-01

import 'kis_unified_api_service.dart';

/// 차트 관련 기능 확장
extension KisUnifiedApiServiceCharts on KisUnifiedApiService {
  
  /// ========================================
  /// 국내주식 차트 API (공식 가이드라인)
  /// ========================================
  
  /// 국내주식 분봉 차트 조회
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/domestic-stock/v1/quotations/inquire-time-itemchartprice
  /// - TR ID: FHKST03010200 (실전/모의 동일)
  Future<List<Map<String, dynamic>>> getDomesticMinuteChart({
    required String stockCode,
    required String period, // 1, 3, 5, 10, 15, 30, 60
    int count = 100,
    String marketCode = 'J',
  }) async {
    try {
      print('📊 [통일API] 국내주식 분봉 차트 조회: $stockCode (${period}분)');
      
      final response = await authedGet(
        '/uapi/domestic-stock/v1/quotations/inquire-time-itemchartprice',
        {
          'FID_COND_MRKT_DIV_CODE': marketCode,
          'FID_INPUT_ISCD': stockCode,
          'FID_INPUT_HOUR_1': period,
          'FID_PW_DATA_INCU_YN': 'N',
        },
        trId: 'FHKST03010200',
      );

      if (response.statusCode == 200 && response.data['rt_cd'] == '0') {
        final output = response.data['output2'] ?? [];
        if (output is List) {
          final charts = output.take(count).map((item) => _parseDomesticChartItem(item)).toList();
          print('✅ [통일API] 국내주식 분봉 차트 조회 성공: ${charts.length}개');
          return charts;
        }
      }
      
      print('❌ [통일API] 국내주식 분봉 차트 조회 실패: ${response.data}');
      return [];
    } catch (e) {
      print('❌ [통일API] 국내주식 분봉 차트 조회 오류: $e');
      return [];
    }
  }

  /// 국내주식 주봉 차트 조회
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/domestic-stock/v1/quotations/inquire-daily-itemchartprice
  /// - TR ID: FHKST03010100 (실전/모의 동일)
  Future<List<Map<String, dynamic>>> getDomesticWeeklyChart({
    required String stockCode,
    int count = 100,
    String marketCode = 'J',
  }) async {
    try {
      print('📊 [통일API] 국내주식 주봉 차트 조회: $stockCode');
      
      // 날짜 설정
      final now = DateTime.now();
      final endDate = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final startDate = now.subtract(Duration(days: count * 7)).toString().replaceAll('-', '').substring(0, 8);
      
      final response = await authedGet(
        '/uapi/domestic-stock/v1/quotations/inquire-daily-itemchartprice',
        {
          'FID_COND_MRKT_DIV_CODE': marketCode,
          'FID_INPUT_ISCD': stockCode,
          'FID_INPUT_DATE_1': startDate,
          'FID_INPUT_DATE_2': endDate,
          'FID_PERIOD_DIV_CODE': 'W',
          'FID_ORG_ADJ_PRC': '1',
        },
        trId: 'FHKST03010100',
      );

      if (response.statusCode == 200 && response.data['rt_cd'] == '0') {
        final output = response.data['output2'] ?? [];
        if (output is List) {
          final charts = output.take(count).map((item) => _parseDomesticChartItem(item)).toList();
          print('✅ [통일API] 국내주식 주봉 차트 조회 성공: ${charts.length}개');
          return charts;
        }
      }
      
      print('❌ [통일API] 국내주식 주봉 차트 조회 실패: ${response.data}');
      return [];
    } catch (e) {
      print('❌ [통일API] 국내주식 주봉 차트 조회 오류: $e');
      return [];
    }
  }

  /// 국내주식 일별 차트 조회 (공식 가이드라인 준수)
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/domestic-stock/v1/quotations/inquire-daily-price
  /// - TR ID: FHKST01010400 (실전/모의 동일)
  /// - 필수 파라미터: env_dv, fid_cond_mrkt_div_code, fid_input_iscd, fid_period_div_code, fid_org_adj_prc
  Future<List<Map<String, dynamic>>> getDomesticDailyChart({
    required String stockCode,
    int count = 100,
    String marketCode = 'J',
  }) async {
    try {
      print('📊 [통일API] 국내주식 일별 차트 조회: $stockCode');
      
      // 날짜 설정
      final now = DateTime.now();
      final endDate = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final startDate = now.subtract(Duration(days: count)).toString().replaceAll('-', '').substring(0, 8);
      
      final response = await authedGet(
        '/uapi/domestic-stock/v1/quotations/inquire-daily-price',
        {
          'env_dv': 'real', // 실전 거래
          'fid_cond_mrkt_div_code': marketCode, // J: KRX
          'fid_input_iscd': stockCode, // 종목코드
          'fid_input_date_1': startDate, // 시작일
          'fid_input_date_2': endDate, // 종료일
          'fid_period_div_code': 'D', // D: 일, W: 주, M: 월
          'fid_org_adj_prc': '1', // 1: 수정주가반영
        },
        trId: 'FHKST01010400',
      );

      if (response.statusCode == 200 && response.data['rt_cd'] == '0') {
        final output = response.data['output2'] ?? [];
        if (output is List) {
          final charts = output.take(count).map((item) => _parseDomesticChartItem(item)).toList();
          print('✅ [통일API] 국내주식 일별 차트 조회 성공: ${charts.length}개');
          return charts;
        }
      }
      
      print('❌ [통일API] 국내주식 일별 차트 조회 실패: ${response.data}');
      return [];
    } catch (e) {
      print('❌ [통일API] 국내주식 일별 차트 조회 오류: $e');
      return [];
    }
  }

  /// 국내주식 월봉 차트 조회
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/domestic-stock/v1/quotations/inquire-daily-itemchartprice
  /// - TR ID: FHKST03010100 (실전/모의 동일)
  Future<List<Map<String, dynamic>>> getDomesticMonthlyChart({
    required String stockCode,
    int count = 100,
    String marketCode = 'J',
  }) async {
    try {
      print('📊 [통일API] 국내주식 월봉 차트 조회: $stockCode');
      
      // 날짜 설정
      final now = DateTime.now();
      final endDate = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final startDate = now.subtract(Duration(days: count * 30)).toString().replaceAll('-', '').substring(0, 8);
      
      final response = await authedGet(
        '/uapi/domestic-stock/v1/quotations/inquire-daily-itemchartprice',
        {
          'FID_COND_MRKT_DIV_CODE': marketCode,
          'FID_INPUT_ISCD': stockCode,
          'FID_INPUT_DATE_1': startDate,
          'FID_INPUT_DATE_2': endDate,
          'FID_PERIOD_DIV_CODE': 'M',
          'FID_ORG_ADJ_PRC': '1',
        },
        trId: 'FHKST03010100',
      );

      if (response.statusCode == 200 && response.data['rt_cd'] == '0') {
        final output = response.data['output2'] ?? [];
        if (output is List) {
          final charts = output.take(count).map((item) => _parseDomesticChartItem(item)).toList();
          print('✅ [통일API] 국내주식 월봉 차트 조회 성공: ${charts.length}개');
          return charts;
        }
      }
      
      print('❌ [통일API] 국내주식 월봉 차트 조회 실패: ${response.data}');
      return [];
    } catch (e) {
      print('❌ [통일API] 국내주식 월봉 차트 조회 오류: $e');
      return [];
    }
  }

  /// ========================================
  /// 해외주식 차트 API (공식 가이드라인)
  /// ========================================
  
  /// 해외주식 분봉 차트 조회
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/overseas-price/v1/quotations/inquire-time-itemchartprice
  /// - TR ID: HHDFS76950200 (실전/모의 동일)
  Future<List<Map<String, dynamic>>> getOverseasMinuteChart({
    required String symbol,
    required String exchangeCode,
    required String period, // 1, 3, 5, 10, 15, 30, 60
    int count = 100,
  }) async {
    try {
      print('🌍 [통일API] 해외주식 분봉 차트 조회: $symbol (${period}분)');
      
      final response = await authedGet(
        '/uapi/overseas-price/v1/quotations/inquire-time-itemchartprice',
        {
          'AUTH': '',
          'EXCD': exchangeCode,
          'SYMB': symbol,
          'NMIN': period,
          'PINC': '1',
          'NEXT': '',
          'NREC': count.toString(),
        },
        trId: 'HHDFS76950200',
      );

      if (response.statusCode == 200 && response.data['rt_cd'] == '0') {
        final output = response.data['output2'] ?? [];
        if (output is List) {
          final charts = output.take(count).map((item) => _parseOverseasChartItem(item)).toList();
          print('✅ [통일API] 해외주식 분봉 차트 조회 성공: ${charts.length}개');
          return charts;
        }
      }
      
      print('❌ [통일API] 해외주식 분봉 차트 조회 실패: ${response.data}');
      return [];
    } catch (e) {
      print('❌ [통일API] 해외주식 분봉 차트 조회 오류: $e');
      return [];
    }
  }

  /// 해외주식 주봉 차트 조회
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/overseas-price/v1/quotations/inquire-daily-chartprice
  /// - TR ID: FHKST03030100 (실전/모의 동일)
  Future<List<Map<String, dynamic>>> getOverseasWeeklyChart({
    required String symbol,
    required String exchangeCode,
    int count = 100,
  }) async {
    try {
      print('🌍 [통일API] 해외주식 주봉 차트 조회: $symbol');
      
      // 날짜 설정
      final now = DateTime.now();
      final endDate = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final startDate = now.subtract(Duration(days: count * 7)).toString().replaceAll('-', '').substring(0, 8);
      
      final response = await authedGet(
        '/uapi/overseas-price/v1/quotations/inquire-daily-chartprice',
        {
          'FID_COND_MRKT_DIV_CODE': 'N', // N: 해외지수
          'FID_INPUT_ISCD': symbol,
          'FID_INPUT_DATE_1': startDate,
          'FID_INPUT_DATE_2': endDate,
          'FID_PERIOD_DIV_CODE': 'W', // W: 주봉
        },
        trId: 'FHKST03030100',
      );

      if (response.statusCode == 200 && response.data['rt_cd'] == '0') {
        final output = response.data['output2'] ?? [];
        if (output is List) {
          final charts = output.take(count).map((item) => _parseOverseasChartItem(item)).toList();
          print('✅ [통일API] 해외주식 주봉 차트 조회 성공: ${charts.length}개');
          return charts;
        }
      }
      
      print('❌ [통일API] 해외주식 주봉 차트 조회 실패: ${response.data}');
      return [];
    } catch (e) {
      print('❌ [통일API] 해외주식 주봉 차트 조회 오류: $e');
      return [];
    }
  }

  /// 해외주식 일별 차트 조회 (공식 가이드라인 준수)
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/overseas-price/v1/quotations/inquire-daily-chartprice
  /// - TR ID: FHKST03030100 (실전/모의 동일)
  /// - 필수 파라미터: fid_cond_mrkt_div_code, fid_input_iscd, fid_input_date_1, fid_input_date_2, fid_period_div_code
  Future<List<Map<String, dynamic>>> getOverseasDailyChart({
    required String symbol,
    required String exchangeCode,
    int count = 100,
  }) async {
    try {
      print('🌍 [통일API] 해외주식 일별 차트 조회: $symbol');
      
      // 날짜 설정 (오늘 기준)
      final now = DateTime.now();
      final endDate = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final startDate = now.subtract(Duration(days: count)).toString().replaceAll('-', '').substring(0, 8);
      
      final response = await authedGet(
        '/uapi/overseas-price/v1/quotations/inquire-daily-chartprice',
        {
          'FID_COND_MRKT_DIV_CODE': 'N', // N: 해외지수
          'FID_INPUT_ISCD': symbol, // 종목코드
          'FID_INPUT_DATE_1': startDate, // 시작일자
          'FID_INPUT_DATE_2': endDate, // 종료일자
          'FID_PERIOD_DIV_CODE': 'D', // D:일, W:주, M:월, Y:년
        },
        trId: 'FHKST03030100', // 공식 가이드라인 TR ID
      );

      if (response.statusCode == 200 && response.data['rt_cd'] == '0') {
        final output2 = response.data['output2'] ?? [];
        if (output2 is List) {
          final charts = output2.take(count).map((item) => _parseOverseasChartItem(item)).toList();
          print('✅ [통일API] 해외주식 일별 차트 조회 성공: ${charts.length}개');
          return charts;
        }
      }
      
      print('❌ [통일API] 해외주식 일별 차트 조회 실패: ${response.data}');
      return [];
    } catch (e) {
      print('❌ [통일API] 해외주식 일별 차트 조회 오류: $e');
      return [];
    }
  }

  /// 해외주식 월봉 차트 조회
  /// 
  /// 공식 가이드라인:
  /// - API URL: /uapi/overseas-price/v1/quotations/inquire-daily-chartprice
  /// - TR ID: FHKST03030100 (실전/모의 동일)
  Future<List<Map<String, dynamic>>> getOverseasMonthlyChart({
    required String symbol,
    required String exchangeCode,
    int count = 100,
  }) async {
    try {
      print('🌍 [통일API] 해외주식 월봉 차트 조회: $symbol');
      
      // 날짜 설정
      final now = DateTime.now();
      final endDate = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final startDate = now.subtract(Duration(days: count * 30)).toString().replaceAll('-', '').substring(0, 8);
      
      final response = await authedGet(
        '/uapi/overseas-price/v1/quotations/inquire-daily-chartprice',
        {
          'FID_COND_MRKT_DIV_CODE': 'N', // N: 해외지수
          'FID_INPUT_ISCD': symbol,
          'FID_INPUT_DATE_1': startDate,
          'FID_INPUT_DATE_2': endDate,
          'FID_PERIOD_DIV_CODE': 'M', // M: 월봉
        },
        trId: 'FHKST03030100',
      );

      if (response.statusCode == 200 && response.data['rt_cd'] == '0') {
        final output = response.data['output2'] ?? [];
        if (output is List) {
          final charts = output.take(count).map((item) => _parseOverseasChartItem(item)).toList();
          print('✅ [통일API] 해외주식 월봉 차트 조회 성공: ${charts.length}개');
          return charts;
        }
      }
      
      print('❌ [통일API] 해외주식 월봉 차트 조회 실패: ${response.data}');
      return [];
    } catch (e) {
      print('❌ [통일API] 해외주식 월봉 차트 조회 오류: $e');
      return [];
    }
  }

  /// ========================================
  /// 통합 차트 API (편의 메서드)
  /// ========================================
  
  /// 차트 데이터 조회 (자동 판별)
  Future<List<Map<String, dynamic>>> getChartDataByMarket(
    String stockCode,
    String market, {
    String period = 'D',
    int count = 100,
  }) async {
    try {
      // 해외주식 판별 (대문자 영문 1-5자리)
      if (RegExp(r'^[A-Z]{1,5}$').hasMatch(stockCode)) {
        // 해외주식 차트
        switch (period) {
          case 'D':
            return await getOverseasDailyChart(
              symbol: stockCode,
              exchangeCode: market,
              count: count,
            );
          case 'W':
            return await getOverseasWeeklyChart(
              symbol: stockCode,
              exchangeCode: market,
              count: count,
            );
          case 'M':
            return await getOverseasMonthlyChart(
              symbol: stockCode,
              exchangeCode: market,
              count: count,
            );
          default:
            // 분봉
            return await getOverseasMinuteChart(
              symbol: stockCode,
              exchangeCode: market,
              period: period,
              count: count,
            );
        }
      } else {
        // 국내주식 차트
        switch (period) {
          case 'D':
            return await getDomesticDailyChart(
              stockCode: stockCode,
              count: count,
            );
          case 'W':
            return await getDomesticWeeklyChart(
              stockCode: stockCode,
              count: count,
            );
          case 'M':
            return await getDomesticMonthlyChart(
              stockCode: stockCode,
              count: count,
            );
          default:
            // 분봉
            return await getDomesticMinuteChart(
              stockCode: stockCode,
              period: period,
              count: count,
            );
        }
      }
    } catch (e) {
      print('❌ [통일API] 차트 데이터 조회 오류: $e');
      return [];
    }
  }

  /// ========================================
  /// 차트 데이터 파싱 헬퍼
  /// ========================================
  
  /// 국내주식 차트 아이템 파싱 (공식 가이드라인 준수)
  Map<String, dynamic> _parseDomesticChartItem(Map<String, dynamic> item) {
    return {
      'date': item['stck_bsop_date'] ?? '', // 날짜
      'time': item['stck_cntg_hour'] ?? '', // 시간
      'open': parseDouble(item['stck_oprc']), // 시가
      'high': parseDouble(item['stck_hgpr']), // 고가
      'low': parseDouble(item['stck_lwpr']), // 저가
      'close': parseDouble(item['stck_clpr']), // 종가
      'volume': parseInt(item['acml_vol']), // 거래량
    };
  }

  /// 해외주식 차트 아이템 파싱 (공식 가이드라인 준수)
  Map<String, dynamic> _parseOverseasChartItem(Map<String, dynamic> item) {
    return {
      'date': item['stck_bsop_date'] ?? item['xymd'] ?? '', // 영업일자
      'time': item['xtms'] ?? '', // 시간
      'open': parseDouble(item['ovrs_nmix_oprc'] ?? item['ovrs_prod_oprc'] ?? item['open']), // 시가
      'high': parseDouble(item['ovrs_nmix_hgpr'] ?? item['ovrs_prod_hgpr'] ?? item['high']), // 고가
      'low': parseDouble(item['ovrs_nmix_lwpr'] ?? item['ovrs_prod_lwpr'] ?? item['low']), // 저가
      'close': parseDouble(item['ovrs_nmix_prpr'] ?? item['ovrs_prod_clpr'] ?? item['clos']), // 종가
      'volume': parseInt(item['acml_vol'] ?? item['tvol']), // 거래량
    };
  }
}
