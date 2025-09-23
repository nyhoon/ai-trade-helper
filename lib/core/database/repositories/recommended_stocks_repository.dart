import '../../data/recommended_stocks_data.dart';
import '../database_helper.dart';
import '../../trading/market_time_validator.dart';

/// 추천종목 데이터베이스 Repository
/// MVI 패턴과 클린아키텍처 원칙을 준수
class RecommendedStocksRepository {
  final DatabaseHelper _databaseHelper;
  final RecommendedStocksData _recommendedStocksData;
  
  RecommendedStocksRepository({
    DatabaseHelper? databaseHelper,
    RecommendedStocksData? recommendedStocksData,
  }) : _databaseHelper = databaseHelper ?? DatabaseHelper(),
       _recommendedStocksData = recommendedStocksData ?? RecommendedStocksData();

  /// 데이터베이스 테이블 생성
  Future<void> createTable() async {
    try {
      await _databaseHelper.execute('''
        CREATE TABLE IF NOT EXISTS recommended_stocks (
          symbol TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          market TEXT NOT NULL,
          added_date TEXT NOT NULL,
          last_updated TEXT NOT NULL,
          is_active INTEGER DEFAULT 1
        )
      ''');
      
      // 스캔 진행률 저장 테이블 (단일 로우 사용)
      await _databaseHelper.execute('''
        CREATE TABLE IF NOT EXISTS recommend_scan_progress (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          current_index INTEGER NOT NULL DEFAULT 0,
          total_count INTEGER NOT NULL DEFAULT 0,
          current_symbol TEXT NOT NULL DEFAULT '',
          current_name TEXT NOT NULL DEFAULT '',
          is_completed INTEGER NOT NULL DEFAULT 0,
          updated_at TEXT NOT NULL
        )
      ''');
      
      // 기본 로우 보장
      await _databaseHelper.execute('''
        INSERT OR IGNORE INTO recommend_scan_progress
          (id, current_index, total_count, current_symbol, current_name, is_completed, updated_at)
        VALUES (1, 0, 0, '', '', 0, ?)
      ''', [DateTime.now().toIso8601String()]);

      // 스캐너 설정 테이블: on/off 플래그 보관 (단일 로우)
      await _databaseHelper.execute('''
        CREATE TABLE IF NOT EXISTS recommend_settings (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          scanner_enabled INTEGER NOT NULL DEFAULT 1,
          updated_at TEXT NOT NULL
        )
      ''');
      await _databaseHelper.execute('''
        INSERT OR IGNORE INTO recommend_settings (id, scanner_enabled, updated_at)
        VALUES (1, 1, ?)
      ''', [DateTime.now().toIso8601String()]);
    } catch (e) {
      // 에러 로깅 (실제 프로덕션에서는 적절한 로깅 시스템 사용)
      print('추천종목 테이블 생성 실패: $e');
    }
  }

  /// 스캐너 on/off 조회
  Future<bool> isScannerEnabled() async {
    try {
      final rows = await _databaseHelper.query('SELECT scanner_enabled FROM recommend_settings WHERE id = 1');
      if (rows.isNotEmpty) {
        final v = (rows.first['scanner_enabled'] as num?)?.toInt() ?? 1;
        return v == 1;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  /// 스캐너 on/off 저장
  Future<bool> setScannerEnabled(bool enabled) async {
    try {
      await _databaseHelper.execute(
        'UPDATE recommend_settings SET scanner_enabled = ?, updated_at = ? WHERE id = 1',
        [enabled ? 1 : 0, DateTime.now().toIso8601String()],
      );
      return true;
    } catch (e) {
      print('스캐너 설정 저장 실패: $e');
      return false;
    }
  }

  /// 모든 추천종목 완전 삭제
  Future<bool> deleteAllRecommendedStocks() async {
    try {
      await _databaseHelper.execute('DELETE FROM recommended_stocks');
      return true;
    } catch (e) {
      print('추천종목 전체 삭제 실패: $e');
      return false;
    }
  }

  /// 추천종목 데이터베이스에 저장
  Future<bool> saveRecommendedStock(String symbol, String name) async {
    try {
      final market = _getMarketFromSymbol(symbol);
      final now = DateTime.now().toIso8601String();
      
      await _databaseHelper.execute('''
        INSERT OR REPLACE INTO recommended_stocks 
        (symbol, name, market, added_date, last_updated, is_active)
        VALUES (?, ?, ?, ?, ?, ?)
      ''', [symbol, name, market, now, now, 1]);
      
      return true;
    } catch (e) {
      print('추천종목 저장 실패: $e');
      return false;
    }
  }

  /// 여러 추천종목 일괄 저장
  Future<bool> saveManyRecommendedStocks(Map<String, String> stocks) async {
    try {
      await _databaseHelper.transaction((db) async {
        for (final entry in stocks.entries) {
          final market = _getMarketFromSymbol(entry.key);
          final now = DateTime.now().toIso8601String();
          
          await db.execute('''
            INSERT OR REPLACE INTO recommended_stocks 
            (symbol, name, market, added_date, last_updated, is_active)
            VALUES (?, ?, ?, ?, ?, ?)
          ''', [entry.key, entry.value, market, now, now, 1]);
        }
      });
      
      return true;
    } catch (e) {
      print('추천종목 일괄 저장 실패: $e');
      return false;
    }
  }

  /// 추천종목 데이터베이스에서 조회
  Future<Map<String, String>> getRecommendedStocksFromDB() async {
    try {
      final results = await _databaseHelper.query('''
        SELECT symbol, name FROM recommended_stocks 
        WHERE is_active = 1 
        ORDER BY symbol
      ''');
      
      final stocks = <String, String>{};
      for (final row in results) {
        stocks[row['symbol'] as String] = row['name'] as String;
      }
      
      return stocks;
    } catch (e) {
      print('추천종목 조회 실패: $e');
      return <String, String>{};
    }
  }

  /// 특정 시장의 추천종목 조회
  Future<Map<String, String>> getRecommendedStocksByMarketFromDB(String market) async {
    try {
      final results = await _databaseHelper.query('''
        SELECT symbol, name FROM recommended_stocks 
        WHERE market = ? AND is_active = 1 
        ORDER BY symbol
      ''', [market]);
      
      final stocks = <String, String>{};
      for (final row in results) {
        stocks[row['symbol'] as String] = row['name'] as String;
      }
      
      return stocks;
    } catch (e) {
      print('시장별 추천종목 조회 실패: $e');
      return <String, String>{};
    }
  }

  /// 추천종목 검색
  Future<Map<String, String>> searchRecommendedStocksFromDB(String query) async {
    try {
      if (query.trim().isEmpty) {
        return await getRecommendedStocksFromDB();
      }
      
      final results = await _databaseHelper.query('''
        SELECT symbol, name FROM recommended_stocks 
        WHERE (symbol LIKE ? OR name LIKE ?) AND is_active = 1 
        ORDER BY symbol
      ''', ['%$query%', '%$query%']);
      
      final stocks = <String, String>{};
      for (final row in results) {
        stocks[row['symbol'] as String] = row['name'] as String;
      }
      
      return stocks;
    } catch (e) {
      print('추천종목 검색 실패: $e');
      return <String, String>{};
    }
  }

  /// 추천종목 제거 (비활성화)
  Future<bool> removeRecommendedStock(String symbol) async {
    try {
      await _databaseHelper.execute('''
        UPDATE recommended_stocks 
        SET is_active = 0, last_updated = ? 
        WHERE symbol = ?
      ''', [DateTime.now().toIso8601String(), symbol]);
      
      return true;
    } catch (e) {
      print('추천종목 제거 실패: $e');
      return false;
    }
  }

  /// 추천종목 완전 삭제
  Future<bool> deleteRecommendedStock(String symbol) async {
    try {
      await _databaseHelper.execute('''
        DELETE FROM recommended_stocks WHERE symbol = ?
      ''', [symbol]);
      
      return true;
    } catch (e) {
      print('추천종목 삭제 실패: $e');
      return false;
    }
  }

  /// 추천종목 존재 여부 확인
  Future<bool> hasRecommendedStock(String symbol) async {
    try {
      final results = await _databaseHelper.query('''
        SELECT COUNT(*) as count FROM recommended_stocks 
        WHERE symbol = ? AND is_active = 1
      ''', [symbol]);
      
      return results.isNotEmpty && (results.first['count'] as int) > 0;
    } catch (e) {
      print('추천종목 존재 여부 확인 실패: $e');
      return false;
    }
  }

  /// 추천종목 개수 조회
  Future<int> getRecommendedStocksCountFromDB() async {
    try {
      final results = await _databaseHelper.query('''
        SELECT COUNT(*) as count FROM recommended_stocks WHERE is_active = 1
      ''');
      
      return results.isNotEmpty ? results.first['count'] as int : 0;
    } catch (e) {
      print('추천종목 개수 조회 실패: $e');
      return 0;
    }
  }

  /// 추천종목 통계 정보 조회 (시장별 상세)
  Future<Map<String, dynamic>> getRecommendedStocksStatisticsFromDB() async {
    try {
      final totalResults = await _databaseHelper.query('''
        SELECT COUNT(*) as count FROM recommended_stocks WHERE is_active = 1
      ''');

      // 시장별 카운트(KOSPI/KOSDAQ/NASDAQ/NYSE)
      final marketResults = await _databaseHelper.query('''
        SELECT market, COUNT(*) as count
        FROM recommended_stocks
        WHERE is_active = 1
        GROUP BY market
      ''');

      final lastUpdateResults = await _databaseHelper.query('''
        SELECT MAX(last_updated) as last_updated FROM recommended_stocks
      ''');

      final byMarket = <String, int>{};
      for (final row in marketResults) {
        byMarket[(row['market'] as String?) ?? 'UNKNOWN'] = (row['count'] as num?)?.toInt() ?? 0;
      }

      return {
        'total': totalResults.isNotEmpty ? totalResults.first['count'] as int : 0,
        'byMarket': byMarket,
        'lastUpdate': lastUpdateResults.isNotEmpty
            ? lastUpdateResults.first['last_updated'] as String?
            : null,
      };
    } catch (e) {
      print('추천종목 통계 조회 실패: $e');
      return {
        'total': 0,
        'byMarket': <String, int>{},
        'lastUpdate': null,
      };
    }
  }

  /// 데이터베이스와 메모리 데이터 동기화
  Future<bool> syncWithMemoryData() async {
    try {
      final memoryStocks = await _recommendedStocksData.getAllStocks();
      if (memoryStocks.isEmpty) {
        await deleteAllRecommendedStocks();
        return true;
      }
      await saveManyRecommendedStocks(memoryStocks);
      return true;
    } catch (e) {
      print('데이터 동기화 실패: $e');
      return false;
    }
  }

  /// 데이터베이스에서 메모리로 데이터 로드
  Future<bool> loadFromDatabase() async {
    try {
      final dbStocks = await getRecommendedStocksFromDB();
      if (dbStocks.isNotEmpty) {
        await _recommendedStocksData.import(dbStocks);
        return true;
      }
      return false;
    } catch (e) {
      print('데이터베이스에서 로드 실패: $e');
      return false;
    }
  }

  /// 추천종목 데이터 백업
  Future<Map<String, dynamic>> backupRecommendedStocksFromDB() async {
    try {
      final stocks = await getRecommendedStocksFromDB();
      final statistics = await getRecommendedStocksStatisticsFromDB();
      
      return {
        'stocks': stocks,
        'statistics': statistics,
        'backupTime': DateTime.now().toIso8601String(),
        'source': 'database',
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
  Future<bool> restoreRecommendedStocksToDB(Map<String, dynamic> backupData) async {
    try {
      if (backupData['stocks'] == null) {
        return false;
      }
      
      final stocks = Map<String, String>.from(backupData['stocks'] as Map);
      await saveManyRecommendedStocks(stocks);
      return true;
    } catch (e) {
      print('데이터 복원 실패: $e');
      return false;
    }
  }

  /// 데이터베이스 정리 (비활성화된 종목 완전 삭제)
  Future<bool> cleanupDatabase() async {
    try {
      await _databaseHelper.execute('''
        DELETE FROM recommended_stocks WHERE is_active = 0
      ''');
      return true;
    } catch (e) {
      print('데이터베이스 정리 실패: $e');
      return false;
    }
  }

  /// 스캔 진행률 조회
  Future<Map<String, dynamic>> getScanProgress() async {
    try {
      final rows = await _databaseHelper.query('SELECT * FROM recommend_scan_progress WHERE id = 1');
      if (rows.isNotEmpty) {
        return Map<String, dynamic>.from(rows.first);
      }
      return {
        'id': 1,
        'current_index': 0,
        'total_count': 0,
        'current_symbol': '',
        'current_name': '',
        'is_completed': 0,
        'updated_at': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      print('스캔 진행률 조회 실패: $e');
      return {
        'id': 1,
        'current_index': 0,
        'total_count': 0,
        'current_symbol': '',
        'current_name': '',
        'is_completed': 0,
        'updated_at': DateTime.now().toIso8601String(),
      };
    }
  }

  /// 스캔 진행률 저장 (단일 업데이트, 트랜잭션 사용 안함: 락 최소화)
  Future<bool> saveScanProgress({
    required int currentIndex,
    required int totalCount,
    required String currentSymbol,
    required String currentName,
    required bool isCompleted,
  }) async {
    try {
      // 단일 트랜잭션으로 upsert 처리 (락 경고 최소화)
      await _databaseHelper.transaction((db) async {
        await db.execute('''
          UPDATE recommend_scan_progress
          SET current_index = ?, total_count = ?, current_symbol = ?, current_name = ?, is_completed = ?, updated_at = ?
          WHERE id = 1
        ''', [
          currentIndex,
          totalCount,
          currentSymbol,
          currentName,
          isCompleted ? 1 : 0,
          DateTime.now().toIso8601String(),
        ]);
      });
      return true;
    } catch (e) {
      print('스캔 진행률 저장 실패: $e');
      return false;
    }
  }

  /// 시장별 심볼 분류(단일화)
  String _getMarketFromSymbol(String symbol) {
    return MarketTimeValidator.instance.getMarketFromSymbol(symbol);
  }
}
