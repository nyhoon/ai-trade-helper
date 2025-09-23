import '../style_based_trading_service.dart';
import '../../data/recommended_stocks_data.dart';

/// 추천종목 관리를 위한 UseCase
/// MVI 패턴과 클린아키텍처 원칙을 준수
class RecommendedStocksUseCase {
  final RecommendedStocksData _recommendedStocksData;
  
  RecommendedStocksUseCase({
    RecommendedStocksData? recommendedStocksData,
  }) : _recommendedStocksData = recommendedStocksData ?? RecommendedStocksData();

  /// 모든 추천종목 조회
  Future<Map<String, String>> getAllRecommendedStocks() async {
    try {
      return await _recommendedStocksData.getAllStocks();
    } catch (e) {
      // 에러 발생 시 빈 맵 반환
      return <String, String>{};
    }
  }

  /// 특정 시장의 추천종목 조회
  Future<Map<String, String>> getRecommendedStocksByMarket(String market) async {
    try {
      return await _recommendedStocksData.getStocksByMarket(market);
    } catch (e) {
      // 에러 발생 시 빈 맵 반환
      return <String, String>{};
    }
  }

  /// 추천종목 검색
  Future<Map<String, String>> searchRecommendedStocks(String query) async {
    try {
      if (query.trim().isEmpty) {
        return await _recommendedStocksData.getAllStocks();
      }
      return await _recommendedStocksData.searchStocks(query.trim());
    } catch (e) {
      // 에러 발생 시 빈 맵 반환
      return <String, String>{};
    }
  }

  /// 추천종목 추가
  Future<bool> addRecommendedStock(String symbol, String name) async {
    try {
      if (symbol.trim().isEmpty || name.trim().isEmpty) {
        return false;
      }
      
      await _recommendedStocksData.addStock(symbol.trim().toUpperCase(), name.trim());
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 추천종목 제거
  Future<bool> removeRecommendedStock(String symbol) async {
    try {
      if (symbol.trim().isEmpty) {
        return false;
      }
      
      await _recommendedStocksData.removeStock(symbol.trim().toUpperCase());
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 여러 추천종목 일괄 추가
  Future<bool> addManyRecommendedStocks(Map<String, String> stocks) async {
    try {
      if (stocks.isEmpty) {
        return false;
      }
      
      // 데이터 정제 (공백 제거, 심볼 대문자 변환)
      final cleanedStocks = <String, String>{};
      for (final entry in stocks.entries) {
        if (entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty) {
          cleanedStocks[entry.key.trim().toUpperCase()] = entry.value.trim();
        }
      }
      
      if (cleanedStocks.isEmpty) {
        return false;
      }
      
      await _recommendedStocksData.addManyStocks(cleanedStocks);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 추천종목 존재 여부 확인
  Future<bool> isStockRecommended(String symbol) async {
    try {
      if (symbol.trim().isEmpty) {
        return false;
      }
      
      return await _recommendedStocksData.hasStock(symbol.trim().toUpperCase());
    } catch (e) {
      return false;
    }
  }

  /// 추천종목 개수 조회
  Future<int> getRecommendedStocksCount() async {
    try {
      return _recommendedStocksData.stockCount;
    } catch (e) {
      return 0;
    }
  }

  /// 추천종목 통계 정보 조회
  Future<Map<String, dynamic>> getRecommendedStocksStatistics() async {
    try {
      return await _recommendedStocksData.getStatistics();
    } catch (e) {
      // 에러 발생 시 기본 통계 반환
      return {
        'total': 0,
        'us': 0,
        'korea': 0,
        'lastUpdate': null,
      };
    }
  }

  /// 추천종목 데이터 초기화
  Future<bool> resetRecommendedStocks() async {
    try {
      await _recommendedStocksData.resetToDefault();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 추천종목 데이터 내보내기
  Future<Map<String, String>> exportRecommendedStocks() async {
    try {
      return await _recommendedStocksData.export();
    } catch (e) {
      return <String, String>{};
    }
  }

  /// 추천종목 데이터 가져오기
  Future<bool> importRecommendedStocks(Map<String, String> stocks) async {
    try {
      if (stocks.isEmpty) {
        return false;
      }
      
      await _recommendedStocksData.import(stocks);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 추천종목 데이터 유효성 검증
  Future<Map<String, dynamic>> validateRecommendedStocks(Map<String, String> stocks) async {
    final errors = <String, List<String>>{};
    final warnings = <String, List<String>>{};
    
    try {
      for (final entry in stocks.entries) {
        final symbol = entry.key.trim();
        final name = entry.value.trim();
        
        // 심볼 검증
        if (symbol.isEmpty) {
          errors['symbol'] ??= [];
          errors['symbol']!.add('빈 심볼이 존재합니다.');
        }
        
        // 이름 검증
        if (name.isEmpty) {
          errors['name'] ??= [];
          errors['name']!.add('빈 종목명이 존재합니다.');
        }
        
        // 심볼 형식 검증
        if (symbol.isNotEmpty) {
          if (_isKoreanStock(symbol) && (symbol.length != 6 || int.tryParse(symbol) == null)) {
            warnings['symbol'] ??= [];
            warnings['symbol']!.add('한국 주식 심볼 형식이 올바르지 않습니다: $symbol');
          }
          
          if (!_isKoreanStock(symbol) && symbol.length < 1) {
            warnings['symbol'] ??= [];
            warnings['symbol']!.add('미국 주식 심볼 형식이 올바르지 않습니다: $symbol');
          }
        }
      }
      
      return {
        'errors': errors,
        'warnings': warnings,
      };
    } catch (e) {
      errors['general'] = ['데이터 검증 중 오류가 발생했습니다: $e'];
      return {
        'errors': errors,
        'warnings': warnings,
      };
    }
  }

  /// 한국 주식 여부 확인
  bool _isKoreanStock(String symbol) {
    return symbol.length == 6 && int.tryParse(symbol) != null;
  }

  /// 추천종목 데이터 백업
  Future<Map<String, dynamic>> backupRecommendedStocks() async {
    try {
      final stocks = await _recommendedStocksData.export();
      final lastUpdate = await _recommendedStocksData.getLastUpdateTime();
      final statistics = await _recommendedStocksData.getStatistics();
      
      return {
        'stocks': stocks,
        'lastUpdate': lastUpdate?.toIso8601String(),
        'statistics': statistics,
        'backupTime': DateTime.now().toIso8601String(),
        'version': '1.0',
      };
    } catch (e) {
      return {
        'error': '백업 실패: $e',
        'backupTime': DateTime.now().toIso8601String(),
      };
    }
  }

  /// 추천종목 데이터 복원
  Future<bool> restoreRecommendedStocks(Map<String, dynamic> backupData) async {
    try {
      if (backupData['stocks'] == null) {
        return false;
      }
      
      final stocks = Map<String, String>.from(backupData['stocks'] as Map);
      await _recommendedStocksData.import(stocks);
      return true;
    } catch (e) {
      return false;
    }
  }
}
