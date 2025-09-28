import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'stock_master_parser.dart';
import '../database/repositories/top_stocks_repository.dart';
import 'app_data_manager.dart';

/// 추천종목 데이터를 관리하는 클래스
/// MVI 패턴과 클린아키텍처 원칙을 준수
class RecommendedStocksData {
  static const String _key = 'recommended_stocks_data_v2';
  static const String _lastUpdateKey = 'recommended_stocks_last_update_v2';
  
  // 기본 추천종목 데이터: 8397개 종목 마스터 데이터에서 로드
  static Map<String, String> _defaultStocks = {};

  Map<String, String> _stocks = {};
  bool _loaded = false;

  /// 싱글톤 인스턴스
  static final RecommendedStocksData _instance = RecommendedStocksData._internal();
  
  factory RecommendedStocksData() => _instance;
  
  RecommendedStocksData._internal();

  /// 데이터 로드 상태 확인
  bool get isLoaded => _loaded;

  /// 추천종목 개수 반환
  int get stockCount => _stocks.length;

  /// 기본 추천종목 데이터 반환
  Map<String, String> get defaultStocks => Map.unmodifiable(_defaultStocks);

  /// 추천종목 데이터 로드
  Future<void> load() async {
    if (_loaded) {
      print('📊 [RecommendedStocksData] 이미 로드됨 - 종목 수: ${_stocks.length}개');
      // 이미 로드됐지만 비어있다면 마스터에서 기본 데이터 보강
      if (_stocks.isEmpty) {
        print('⚠️ [RecommendedStocksData] 로드 상태이지만 비어있음 -> 마스터에서 보강');
        if (_defaultStocks.isEmpty) {
          await _loadDefaultStocksFromMaster();
        }
        if (_defaultStocks.isNotEmpty) {
          _stocks = Map<String, String>.from(_defaultStocks);
          await _saveToStorage();
          print('✅ [RecommendedStocksData] 보강 완료: ${_stocks.length}개');
        }
      }
      return;
    }
    
    try {
      print('🔄 [RecommendedStocksData] 데이터 로드 시작...');
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_key);
      
      if (jsonStr != null && jsonStr.isNotEmpty) {
        _stocks = Map<String, String>.from(jsonDecode(jsonStr) as Map);
        print('📊 [RecommendedStocksData] 저장된 데이터 로드 완료: ${_stocks.length}개');
        if (_stocks.isEmpty) {
          print('⚠️ [RecommendedStocksData] 저장된 데이터가 비어있음 -> 마스터에서 로드');
          if (_defaultStocks.isEmpty) {
            await _loadDefaultStocksFromMaster();
          }
          _stocks = Map<String, String>.from(_defaultStocks);
          await _saveToStorage();
          print('✅ [RecommendedStocksData] 마스터 데이터 로드 완료: ${_stocks.length}개');
        }
      } else {
        print('📊 [RecommendedStocksData] 저장된 데이터 없음 - 마스터 데이터에서 로드');
        if (_defaultStocks.isEmpty) {
          await _loadDefaultStocksFromMaster();
        }
        _stocks = Map<String, String>.from(_defaultStocks);
        await _saveToStorage();
        print('📊 [RecommendedStocksData] 마스터 데이터 로드 완료: ${_stocks.length}개');
      }
      
      _loaded = true;
    } catch (e) {
      print('❌ [RecommendedStocksData] 데이터 로드 실패: $e');
      if (_defaultStocks.isEmpty) {
        await _loadDefaultStocksFromMaster();
      }
      _stocks = Map<String, String>.from(_defaultStocks);
      _loaded = true;
      print('📊 [RecommendedStocksData] 에러 복구 후 로드 완료: ${_stocks.length}개');
    }
  }

  /// 추천종목 데이터 저장
  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(_stocks));
      await prefs.setString(_lastUpdateKey, DateTime.now().toIso8601String());
    } catch (e) {
      // 에러 로깅 (실제 프로덕션에서는 적절한 로깅 시스템 사용)
      print('추천종목 데이터 저장 실패: $e');
    }
  }

  /// 모든 추천종목 반환
  Future<Map<String, String>> getAllStocks() async {
    await load();
    // 여전히 비어있다면 마지막 보강 시도 (1회성)
    if (_stocks.isEmpty) {
      print('⚠️ [RecommendedStocksData] getAllStocks 시 비어있음 -> 최종 보강 시도');
      if (_defaultStocks.isEmpty) {
        await _loadDefaultStocksFromMaster();
      }
      if (_defaultStocks.isNotEmpty) {
        _stocks = Map<String, String>.from(_defaultStocks);
        await _saveToStorage();
      }
    }
    print('📊 [RecommendedStocksData] getAllStocks 호출 - 반환 종목 수: ${_stocks.length}개');
    return Map.unmodifiable(_stocks);
  }

  /// 특정 종목명 반환
  Future<String?> getStockName(String symbol) async {
    await load();
    return _stocks[symbol];
  }

  /// 종목 존재 여부 확인
  Future<bool> hasStock(String symbol) async {
    await load();
    return _stocks.containsKey(symbol);
  }

  /// 추천종목 추가
  Future<void> addStock(String symbol, String name) async {
    await load();
    _stocks[symbol] = name;
    await _saveToStorage();
  }

  /// 추천종목 제거
  Future<void> removeStock(String symbol) async {
    await load();
    _stocks.remove(symbol);
    await _saveToStorage();
  }

  /// 여러 종목 일괄 추가
  Future<void> addManyStocks(Map<String, String> stocks) async {
    await load();
    _stocks.addAll(stocks);
    await _saveToStorage();
  }

  /// 추천종목 데이터 초기화 (빈 목록으로 복원)
  Future<void> resetToDefault() async {
    _stocks = <String, String>{};
    await _saveToStorage();
  }

  /// 마지막 업데이트 시간 반환
  Future<DateTime?> getLastUpdateTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timeStr = prefs.getString(_lastUpdateKey);
      return timeStr != null ? DateTime.parse(timeStr) : null;
    } catch (e) {
      return null;
    }
  }

  /// 특정 시장의 종목만 반환
  Future<Map<String, String>> getStocksByMarket(String market) async {
    await load();
    
    switch (market.toLowerCase()) {
      case 'us':
      case 'usa':
      case 'america':
        return Map.unmodifiable(_stocks.entries
            .where((entry) => !_isKoreanStock(entry.key))
            .fold<Map<String, String>>({}, (map, entry) {
          map[entry.key] = entry.value;
          return map;
        }));
      
      case 'kr':
      case 'korea':
      case 'kospi':
      case 'kosdaq':
        return Map.unmodifiable(_stocks.entries
            .where((entry) => _isKoreanStock(entry.key))
            .fold<Map<String, String>>({}, (map, entry) {
          map[entry.key] = entry.value;
          return map;
        }));
      
      default:
        return Map.unmodifiable(_stocks);
    }
  }

  /// 한국 주식 여부 확인
  bool _isKoreanStock(String symbol) {
    return symbol.length == 6 && int.tryParse(symbol) != null;
  }

  /// 추천종목 데이터 내보내기
  Future<Map<String, String>> export() async {
    await load();
    return Map.unmodifiable(_stocks);
  }

  /// 추천종목 데이터 가져오기
  Future<void> import(Map<String, String> stocks) async {
    _stocks = Map<String, String>.from(stocks);
    await _saveToStorage();
  }

  /// 추천종목 검색
  Future<Map<String, String>> searchStocks(String query) async {
    await load();
    
    if (query.isEmpty) return Map.unmodifiable(_stocks);
    
    final lowercaseQuery = query.toLowerCase();
    final results = <String, String>{};
    
    for (final entry in _stocks.entries) {
      if (entry.key.toLowerCase().contains(lowercaseQuery) ||
          entry.value.toLowerCase().contains(lowercaseQuery)) {
        results[entry.key] = entry.value;
      }
    }
    
    return Map.unmodifiable(results);
  }

  /// 추천종목 통계 정보
  Future<Map<String, dynamic>> getStatistics() async {
    await load();
    
    final usStocks = _stocks.entries
        .where((entry) => !_isKoreanStock(entry.key))
        .length;
    
    final krStocks = _stocks.entries
        .where((entry) => _isKoreanStock(entry.key))
        .length;
    
    return {
      'total': _stocks.length,
      'us': usStocks,
      'korea': krStocks,
      'lastUpdate': await getLastUpdateTime(),
    };
  }

  // 점수와 가격 정보를 저장하는 Map
  final Map<String, Map<String, dynamic>> _stockScores = {};

  /// 종목 점수와 가격 정보 저장 (SQL 단일화) - 락 방지
  Future<void> updateStockScore(String symbol, double score, {Map<String, dynamic>? metadata}) async {
    // SQL 단일화: SharedPreferences 제거, SQL만 사용
    try {
      // DB 락 방지를 위한 지연 실행
      await Future.delayed(const Duration(milliseconds: 10));
      
      final topRepo = TopStocksRepository();
      final name = await getStockName(symbol);
      final market = metadata?['market'] ?? 'UNKNOWN';
      final price = (metadata?['price'] as num?)?.toDouble() ?? 0.0;
      // 거래대금 계산: 전일 종가*전일 거래량 (캐시 우선)
      double tradingAmount = 0;
      String tradingCurrency = (market == 'KOSPI' || market == 'KOSDAQ') ? 'KRW' : 'USD';
      try {
        final cached = AppDataManager.instance.getCachedStockData(symbol);
        final double? volume = (cached['volume'] as num?)?.toDouble()
            ?? (cached['acml_vol'] as num?)?.toDouble();
        final double priceForAmount = price > 0
            ? price
            : ((cached['currentPrice'] as num?)?.toDouble()
                ?? (cached['prpr'] as num?)?.toDouble()
                ?? 0.0);
        if (priceForAmount > 0 && (volume ?? 0) > 0) {
          tradingAmount = priceForAmount * (volume ?? 0);
        }
      } catch (_) {}
      
      // 서버 전환: 클라이언트에서 top_stocks 저장 금지 → 저장 스킵
      // 서버 Functions가 recommendations/top10 및 분석 결과를 관리합니다.
      
      // 메모리 캐시 업데이트 (선택적)
      _stockScores[symbol] = {
        'score': score,
        'comprehensiveScore': score,
        'price': price,
        'market': market,
        'timestamp': DateTime.now().toIso8601String(),
        ...?metadata,
      };
      
      print('💾 [$symbol] 점수 캐시 갱신(서버 저장 스킵): $score');
    } catch (e) {
      print('❌ [$symbol] SQL 점수 저장 실패: $e');
    }
  }

  /// 종목 점수와 가격 정보 조회 (SQL 단일화)
  Future<Map<String, dynamic>?> getStockScore(String symbol) async {
    // 메모리에서 먼저 조회
    if (_stockScores.containsKey(symbol)) {
      return _stockScores[symbol];
    }
    
    // SQL에서 조회
    try {
      final topRepo = TopStocksRepository();
      final scoreData = await topRepo.getStockScore(symbol);
      
      if (scoreData != null) {
        // 메모리 캐시에 저장
        _stockScores[symbol] = {
          'score': scoreData['score'],
          'comprehensiveScore': scoreData['score'],
          'price': scoreData['currentPrice'],
          'market': scoreData['market'],
          'timestamp': scoreData['lastUpdated'].toIso8601String(),
        };
        print('📊 [$symbol] SQL 점수 로드 완료: ${scoreData['score']}');
        return _stockScores[symbol];
      }
    } catch (e) {
      print('❌ [$symbol] SQL 점수 로드 실패: $e');
    }
    
    return null;
  }

  /// 모든 종목의 점수와 가격 정보 조회 (SQL 단일화)
  Future<Map<String, Map<String, dynamic>>> getAllStocksWithScores() async {
    await load();
    final result = <String, Map<String, dynamic>>{};
    
    try {
      // SQL에서 상위 점수 종목들 조회
      final topRepo = TopStocksRepository();
      final topStocks = await topRepo.getTopStocks(limit: 1000); // 상위 1000개
      
      // SQL 데이터를 결과에 추가
      for (final stock in topStocks) {
        final symbol = stock['stockCode'] as String;
        result[symbol] = {
          'name': stock['stockName'],
          'score': stock['score'],
          'price': stock['currentPrice'],
          'market': stock['market'],
          'timestamp': stock['lastUpdated'].toIso8601String(),
        };
      }
      
      // 나머지 종목들은 기본값으로 추가
      for (final entry in _stocks.entries) {
        final symbol = entry.key;
        if (!result.containsKey(symbol)) {
          result[symbol] = {
            'name': entry.value,
            'score': 0.0,
            'price': 0.0,
            'market': 'UNKNOWN',
            'timestamp': DateTime.now().toIso8601String(),
          };
        }
      }
      
      print('📊 SQL에서 종목 점수 조회 완료: ${result.length}개');
    } catch (e) {
      print('❌ SQL 종목 점수 조회 실패: $e');
      // 폴백: 기본 데이터만 반환
      for (final entry in _stocks.entries) {
        result[entry.key] = {
          'name': entry.value,
          'score': 0.0,
          'price': 0.0,
          'market': 'UNKNOWN',
          'timestamp': DateTime.now().toIso8601String(),
        };
      }
    }
    
    return result;
  }

  /// 점수 정보 초기화
  Future<void> clearScores() async {
    _stockScores.clear();
  }

  /// 마스터 데이터에서 기본 추천종목 로드
  Future<void> _loadDefaultStocksFromMaster() async {
    try {
      print('📊 마스터 데이터에서 기본 추천종목 로드 시작...');
      
      // StockMasterParser를 통해 8397개 종목 데이터 로드
      final stockMasterParser = StockMasterParser();
      if (!stockMasterParser.isInitialized) {
        await stockMasterParser.initialize();
      }
      
      final defaultStocks = <String, String>{};
      
      // KOSPI 종목 추가
      final kospiCodes = stockMasterParser.getKospiStockCodes();
      for (final code in kospiCodes) {
        final name = stockMasterParser.getStockName(code);
        if (name != null && name.isNotEmpty) {
          defaultStocks[code] = name;
        }
      }
      
      // KOSDAQ 종목 추가
      final kosdaqCodes = stockMasterParser.getKosdaqStockCodes();
      for (final code in kosdaqCodes) {
        final name = stockMasterParser.getStockName(code);
        if (name != null && name.isNotEmpty) {
          defaultStocks[code] = name;
        }
      }
      
      // NASDAQ 종목 추가
      final nasdaqCodes = stockMasterParser.getNasdaqStockCodes();
      for (final code in nasdaqCodes) {
        final name = stockMasterParser.getStockName(code);
        if (name != null && name.isNotEmpty) {
          defaultStocks[code] = name;
        }
      }
      
      _defaultStocks = defaultStocks;
      print('✅ 기본 추천종목 로드 완료: ${_defaultStocks.length}개');
      print('   - KOSPI: ${kospiCodes.length}개');
      print('   - KOSDAQ: ${kosdaqCodes.length}개');
      print('   - NASDAQ: ${nasdaqCodes.length}개');
      
    } catch (e) {
      print('❌ 마스터 데이터에서 기본 추천종목 로드 실패: $e');
      _defaultStocks = <String, String>{};
    }
  }
}
