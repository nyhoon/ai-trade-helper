import '../data/recommended_stocks_data.dart';
import '../database/repositories/recommended_stocks_repository.dart';
import '../trading/usecases/recommended_stocks_usecase.dart';

/// 추천종목 관리 서비스
/// MVI 패턴과 클린아키텍처 원칙을 준수
class RecommendedStocksService {
  final RecommendedStocksData _recommendedStocksData;
  final RecommendedStocksRepository _repository;
  final RecommendedStocksUseCase _useCase;
  
  RecommendedStocksService({
    RecommendedStocksData? recommendedStocksData,
    RecommendedStocksRepository? repository,
    RecommendedStocksUseCase? useCase,
  }) : _recommendedStocksData = recommendedStocksData ?? RecommendedStocksData(),
       _repository = repository ?? RecommendedStocksRepository(),
       _useCase = useCase ?? RecommendedStocksUseCase();

  /// 서비스 초기화
  Future<void> initialize() async {
    try {
      // 데이터베이스 테이블 생성
      await _repository.createTable();
      
      // 메모리 데이터와 데이터베이스 동기화 (메모리 우선)
      await _syncData();
    } catch (e) {
      print('추천종목 서비스 초기화 실패: $e');
    }
  }

  /// 데이터 동기화 (메모리 우선 정책)
  Future<void> _syncData() async {
    try {
      // 현재 메모리 상태 로드
      final memoryStocks = await _useCase.getAllRecommendedStocks();

      if (memoryStocks.isEmpty) {
        // 메모리가 비어있으면 DB도 비운다 (하드코딩/이전 저장 잔재 제거)
        await _repository.deleteAllRecommendedStocks();
      } else {
        // 메모리가 있으면 DB에 반영
        await _repository.saveManyRecommendedStocks(memoryStocks);
      }
    } catch (e) {
      print('데이터 동기화 실패: $e');
    }
  }

  /// 모든 추천종목 조회
  Future<Map<String, String>> getAllRecommendedStocks() async {
    try {
      return await _useCase.getAllRecommendedStocks();
    } catch (e) {
      print('추천종목 조회 실패: $e');
      return <String, String>{};
    }
  }

  /// 특정 시장의 추천종목 조회
  Future<Map<String, String>> getRecommendedStocksByMarket(String market) async {
    try {
      return await _useCase.getRecommendedStocksByMarket(market);
    } catch (e) {
      print('시장별 추천종목 조회 실패: $e');
      return <String, String>{};
    }
  }

  /// 추천종목 검색
  Future<Map<String, String>> searchRecommendedStocks(String query) async {
    try {
      return await _useCase.searchRecommendedStocks(query);
    } catch (e) {
      print('추천종목 검색 실패: $e');
      return <String, String>{};
    }
  }

  /// 추천종목 추가
  Future<bool> addRecommendedStock(String symbol, String name) async {
    try {
      final success = await _useCase.addRecommendedStock(symbol, name);
      if (success) {
        // 데이터베이스에도 저장
        await _repository.saveRecommendedStock(symbol, name);
      }
      return success;
    } catch (e) {
      print('추천종목 추가 실패: $e');
      return false;
    }
  }

  /// 추천종목 제거
  Future<bool> removeRecommendedStock(String symbol) async {
    try {
      final success = await _useCase.removeRecommendedStock(symbol);
      if (success) {
        // 데이터베이스에서도 제거
        await _repository.removeRecommendedStock(symbol);
      }
      return success;
    } catch (e) {
      print('추천종목 제거 실패: $e');
      return false;
    }
  }

  /// 여러 추천종목 일괄 추가
  Future<bool> addManyRecommendedStocks(Map<String, String> stocks) async {
    try {
      // 데이터 유효성 검증
      final validation = await _useCase.validateRecommendedStocks(stocks);
      if (validation['errors']?.isNotEmpty == true) {
        print('추천종목 데이터 유효성 검증 실패: ${validation['errors']}');
        return false;
      }
      
      final success = await _useCase.addManyRecommendedStocks(stocks);
      if (success) {
        // 데이터베이스에도 저장
        await _repository.saveManyRecommendedStocks(stocks);
      }
      return success;
    } catch (e) {
      print('추천종목 일괄 추가 실패: $e');
      return false;
    }
  }

  /// 추천종목 존재 여부 확인
  Future<bool> isStockRecommended(String symbol) async {
    try {
      return await _useCase.isStockRecommended(symbol);
    } catch (e) {
      print('추천종목 존재 여부 확인 실패: $e');
      return false;
    }
  }

  /// 추천종목 개수 조회
  Future<int> getRecommendedStocksCount() async {
    try {
      return await _useCase.getRecommendedStocksCount();
    } catch (e) {
      print('추천종목 개수 조회 실패: $e');
      return 0;
    }
  }

  /// 추천종목 통계 정보 조회
  Future<Map<String, dynamic>> getRecommendedStocksStatistics() async {
    try {
      return await _useCase.getRecommendedStocksStatistics();
    } catch (e) {
      print('추천종목 통계 조회 실패: $e');
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
      final success = await _useCase.resetRecommendedStocks();
      if (success) {
        // 메모리가 비워졌으므로 DB도 비운다
        await _repository.deleteAllRecommendedStocks();
      }
      return success;
    } catch (e) {
      print('추천종목 초기화 실패: $e');
      return false;
    }
  }

  /// 추천종목 데이터 내보내기
  Future<Map<String, String>> exportRecommendedStocks() async {
    try {
      return await _useCase.exportRecommendedStocks();
    } catch (e) {
      print('추천종목 내보내기 실패: $e');
      return <String, String>{};
    }
  }

  /// 추천종목 데이터 가져오기
  Future<bool> importRecommendedStocks(Map<String, String> stocks) async {
    try {
      // 데이터 유효성 검증
      final validation = await _useCase.validateRecommendedStocks(stocks);
      if (validation['errors']?.isNotEmpty == true) {
        print('추천종목 데이터 유효성 검증 실패: ${validation['errors']}');
        return false;
      }
      
      final success = await _useCase.importRecommendedStocks(stocks);
      if (success) {
        // 데이터베이스에도 저장
        await _repository.saveManyRecommendedStocks(stocks);
      }
      return success;
    } catch (e) {
      print('추천종목 가져오기 실패: $e');
      return false;
    }
  }

  /// 추천종목 데이터 백업
  Future<Map<String, dynamic>> backupRecommendedStocks() async {
    try {
      final memoryBackup = await _useCase.backupRecommendedStocks();
      final dbBackup = await _repository.backupRecommendedStocksFromDB();
      
      return {
        'memory': memoryBackup,
        'database': dbBackup,
        'backupTime': DateTime.now().toIso8601String(),
        'version': '1.0',
      };
    } catch (e) {
      print('추천종목 백업 실패: $e');
      return {
        'error': '백업 실패: $e',
        'backupTime': DateTime.now().toIso8601String(),
      };
    }
  }

  /// 추천종목 데이터 복원
  Future<bool> restoreRecommendedStocks(Map<String, dynamic> backupData) async {
    try {
      if (backupData['memory'] != null) {
        final success = await _useCase.restoreRecommendedStocks(backupData['memory']);
        if (success) {
          // 데이터베이스도 복원
          await _repository.deleteAllRecommendedStocks();
          await _repository.syncWithMemoryData();
          return true;
        }
      }
      
      if (backupData['database'] != null) {
        return await _repository.restoreRecommendedStocksToDB(backupData['database']);
      }
      
      return false;
    } catch (e) {
      print('추천종목 복원 실패: $e');
      return false;
    }
  }

  /// 데이터베이스 정리
  Future<bool> cleanupDatabase() async {
    try {
      return await _repository.cleanupDatabase();
    } catch (e) {
      print('데이터베이스 정리 실패: $e');
      return false;
    }
  }

  /// 추천종목 데이터 유효성 검증
  Future<Map<String, dynamic>> validateRecommendedStocks(Map<String, String> stocks) async {
    try {
      return await _useCase.validateRecommendedStocks(stocks);
    } catch (e) {
      print('추천종목 데이터 유효성 검증 실패: $e');
      return {
        'errors': ['유효성 검증 중 오류가 발생했습니다: $e'],
        'warnings': [],
      };
    }
  }

  /// 서비스 상태 확인
  Future<Map<String, dynamic>> getServiceStatus() async {
    try {
      final memoryCount = await _useCase.getRecommendedStocksCount();
      final dbCount = await _repository.getRecommendedStocksCountFromDB();
      final memoryStats = await _useCase.getRecommendedStocksStatistics();
      final dbStats = await _repository.getRecommendedStocksStatisticsFromDB();
      
      return {
        'memory': {
          'count': memoryCount,
          'statistics': memoryStats,
        },
        'database': {
          'count': dbCount,
          'statistics': dbStats,
        },
        'syncStatus': memoryCount == dbCount ? 'synced' : 'out_of_sync',
        'lastCheck': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      print('서비스 상태 확인 실패: $e');
      return {
        'error': '상태 확인 실패: $e',
        'lastCheck': DateTime.now().toIso8601String(),
      };
    }
  }

  /// 데이터 동기화 강제 실행
  Future<bool> forceSync() async {
    try {
      await _syncData();
      return true;
    } catch (e) {
      print('강제 동기화 실패: $e');
      return false;
    }
  }

  /// 추천종목 데이터 새로고침
  Future<bool> refreshRecommendedStocks() async {
    try {
      // 메모리 데이터를 데이터베이스에 동기화 (메모리 우선)
      await _syncData();
      return true;
    } catch (e) {
      print('추천종목 데이터 새로고침 실패: $e');
      return false;
    }
  }
}
