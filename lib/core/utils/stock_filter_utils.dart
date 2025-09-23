/// 종목 필터링 유틸리티
class StockFilterUtils {
  /// 상장폐지/관리종목 여부 확인
  static bool isDelistedOrManaged(Map<String, dynamic> stockData) {
    // 거래정지 여부
    final trhtYn = stockData['trht_yn'] as String? ?? '';
    if (trhtYn == 'Y') return true;
    
    // 정리매매 여부
    final sltrYn = stockData['sltr_yn'] as String? ?? '';
    if (sltrYn == 'Y') return true;
    
    // 관리 종목 여부
    final mangIssuYn = stockData['mang_issu_yn'] as String? ?? '';
    if (mangIssuYn == 'Y') return true;
    
    // 시장 경고 구분 코드 (01:투자주의, 02:투자경고, 03:투자위험)
    final mrktAlrmClsCode = stockData['mrkt_alrm_cls_code'] as String? ?? '';
    if (mrktAlrmClsCode.isNotEmpty && mrktAlrmClsCode != '00') return true;
    
    return false;
  }
  
  /// ETF/ETN/펀드 등 비개별주 여부 확인
  static bool isNonIndividualStock(Map<String, dynamic> stockData) {
    // 증권그룹구분코드 확인
    final scrtGrpClsCode = stockData['scrt_grp_cls_code'] as String? ?? '';
    
    // ETF, ETN, 증권투자회사, 부동산투자회사 등 제외
    if (scrtGrpClsCode == 'EF' || // ETF
        scrtGrpClsCode == 'ET' || // ETN
        scrtGrpClsCode == 'MF' || // 증권투자회사
        scrtGrpClsCode == 'RT' || // 부동산투자회사
        scrtGrpClsCode == 'SC' || // 선박투자회사
        scrtGrpClsCode == 'IF' || // 사회간접자본투융자회사
        scrtGrpClsCode == 'DR' || // 주식예탁증서
        scrtGrpClsCode == 'EW' || // ELW
        scrtGrpClsCode == 'SW' || // 신주인수권증권
        scrtGrpClsCode == 'SR' || // 신주인수권증서
        scrtGrpClsCode == 'BC' || // 수익증권
        scrtGrpClsCode == 'FE' || // 해외ETF
        scrtGrpClsCode == 'FS') { // 외국주권
      return true;
    }
    
    // ETP 상품구분코드 확인 (ETF/ETN)
    final etpProdClsCode = stockData['etp_prod_cls_code'] as String? ?? '';
    if (etpProdClsCode != '0' && etpProdClsCode.isNotEmpty) return true;
    
    return false;
  }
  
  /// 개별주만 필터링 (ETF/ETN/펀드 제외)
  static List<Map<String, dynamic>> filterIndividualStocks(List<Map<String, dynamic>> stocks) {
    return stocks.where((stock) {
      // 상장폐지/관리종목 제외
      if (isDelistedOrManaged(stock)) return false;
      
      // ETF/ETN/펀드 제외
      if (isNonIndividualStock(stock)) return false;
      
      return true;
    }).toList();
  }
  
  /// 종목명으로 ETF/ETN/펀드 여부 확인 (추가 필터링)
  static bool isNonIndividualStockByName(String stockName) {
    final name = stockName.toLowerCase();
    
    // ETF 관련 키워드
    if (name.contains('tiger') || 
        name.contains('rise') || 
        name.contains('kodex') ||
        name.contains('kodex') ||
        name.contains('etf') ||
        name.contains('etn') ||
        name.contains('reit') ||
        name.contains('리츠') ||
        name.contains('펀드') ||
        name.contains('fund') ||
        name.contains('plus') ||
        name.contains('value') ||
        name.contains('bt') ||
        name.contains('igis')) {
      return true;
    }
    
    return false;
  }
  
  /// 종목명 기반 개별주 필터링
  static List<Map<String, dynamic>> filterIndividualStocksByName(List<Map<String, dynamic>> stocks) {
    return stocks.where((stock) {
      final stockName = stock['stock_name'] as String? ?? 
                       stock['hts_kor_isnm'] as String? ?? 
                       stock['name'] as String? ?? '';
      
      // 종목명으로 ETF/ETN/펀드 제외
      if (isNonIndividualStockByName(stockName)) return false;
      
      return true;
    }).toList();
  }
  
  /// 종합 필터링 (상장폐지 + ETF/ETN/펀드 제외)
  static List<Map<String, dynamic>> filterValidIndividualStocks(List<Map<String, dynamic>> stocks) {
    return stocks.where((stock) {
      // 상장폐지/관리종목 제외
      if (isDelistedOrManaged(stock)) return false;
      
      // ETF/ETN/펀드 제외 (데이터 기반)
      if (isNonIndividualStock(stock)) return false;
      
      // 종목명 기반 ETF/ETN/펀드 제외
      final stockName = stock['stock_name'] as String? ?? 
                       stock['hts_kor_isnm'] as String? ?? 
                       stock['name'] as String? ?? '';
      if (isNonIndividualStockByName(stockName)) return false;
      
      return true;
    }).toList();
  }

  /// 종합 필터링 (상장폐지 + ETF/ETN/펀드 제외)
  bool shouldIncludeStock({
    required String market,
    String? scrtGrpClsCode,
    String? name,
  }) {
    // 나스닥/NYSE 등 미국 시장은 ETF 필터 미적용
    final upperMarket = market.toUpperCase();
    if (upperMarket == 'NASDAQ' || upperMarket == 'NAS' || upperMarket == 'NYSE' || upperMarket == 'NYS') {
      return true;
    }
    // 기존 국내/기타 시장 필터 유지
    // ETF/ETN/펀드 제외 (데이터 기반)
    if (_etpByCode(scrtGrpClsCode)) return false;
    // 종목명 기반 ETF/ETN/펀드 제외
    if (_etpByName(name)) return false;
    return true;
  }

  bool _etpByCode(String? code) {
    final c = (code ?? '').toUpperCase();
    return c == 'EF' || c == 'EN' || c == 'FE' || c == 'FN' || c == 'FD';
  }

  bool _etpByName(String? name) {
    if (name == null) return false;
    final n = name.toLowerCase();
    return n.contains('etf') || n.contains('etn') || n.contains('trust') || n.contains('fund');
  }
}
