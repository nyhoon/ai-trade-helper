import 'dart:async';
import 'package:flutter/foundation.dart';
import '../database/repositories/chart_data_repository.dart';
import '../database/repositories/current_price_repository.dart';
import '../database/repositories/watchlist_repository.dart';
import '../database/repositories/holdings_repository.dart';
import '../database/repositories/ai_recommendation_repository.dart';
import '../database/database_helper.dart';
import '../data/incremental_data_manager.dart';

/// 스마트 DB 생명주기 관리 서비스
///
/// 📊 주요 기능:
/// - 관심종목/보유종목 변경 감지
/// - 100일 초과 데이터 자동 정리
/// - 비활성 종목 데이터 정리
/// - 스마트 캐싱 시스템
/// - 메모리 최적화
class SmartLifecycleManager {
  static final SmartLifecycleManager _instance = SmartLifecycleManager._internal();
  factory SmartLifecycleManager() => _instance;
  SmartLifecycleManager._internal();

  // 서비스 상태
  bool _isRunning = false;
  Timer? _lifecycleTimer;
  Timer? _cacheTimer;
  
  // Repository 인스턴스
  final ChartDataRepository _chartRepo = ChartDataRepository();
  final CurrentPriceRepository _currentPriceRepo = CurrentPriceRepository();
  final WatchlistRepository _watchlistRepo = WatchlistRepository();
  final HoldingsRepository _holdingsRepo = HoldingsRepository();
  final AiRecommendationRepository _aiRepo = AiRecommendationRepository();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final IncrementalDataManager _dataManager = IncrementalDataManager();

  // 캐시 관리
  final Map<String, dynamic> _dataCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  
  // 변경 감지를 위한 이전 상태
  List<String> _previousWatchlist = [];
  List<String> _previousHoldings = [];
  
  // 통계 정보
  int _cacheHits = 0;
  int _cacheMisses = 0;
  DateTime? _lastCleanupTime;
  int _totalCleanups = 0;
  int _dataCleanupCount = 0;
  int _cacheCleanupCount = 0;
  
  // 설정
  static const Duration _lifecycleInterval = Duration(hours: 6); // 6시간마다 정리
  static const Duration _cacheInterval = Duration(minutes: 30); // 30분마다 캐시 정리
  static const Duration _cacheExpiry = Duration(hours: 1); // 캐시 1시간 만료
  static const int _maxCacheSize = 100; // 최대 캐시 항목 수

  /// 서비스 시작
  Future<void> start() async {
    if (_isRunning) {
      print('⚠️ 스마트 생명주기 관리가 이미 실행 중입니다.');
      return;
    }

    try {
      print('🚀 스마트 생명주기 관리 시작...');
      
      // 초기화
      await _initialize();
      
      // 서비스 상태 설정
      _isRunning = true;
      
      // 초기 상태 저장
      await _saveCurrentState();
      
      // 생명주기 타이머 시작
      _startLifecycleTimer();
      
      // 캐시 타이머 시작
      _startCacheTimer();
      
      print('✅ 스마트 생명주기 관리 시작 완료');
      
    } catch (e) {
      print('❌ 스마트 생명주기 관리 시작 실패: $e');
      _isRunning = false;
      rethrow;
    }
  }

  /// 서비스 중지
  Future<void> stop() async {
    if (!_isRunning) {
      print('⚠️ 스마트 생명주기 관리가 실행 중이 아닙니다.');
      return;
    }

    try {
      print('🛑 스마트 생명주기 관리 중지...');
      
      // 타이머 정리
      _lifecycleTimer?.cancel();
      _cacheTimer?.cancel();
      _lifecycleTimer = null;
      _cacheTimer = null;
      
      // 캐시 정리
      _clearCache();
      
      // 서비스 상태 설정
      _isRunning = false;
      
      print('✅ 스마트 생명주기 관리 중지 완료');
      
    } catch (e) {
      print('❌ 스마트 생명주기 관리 중지 실패: $e');
      rethrow;
    }
  }

  /// 서비스 재시작
  Future<void> restart() async {
    print('🔄 스마트 생명주기 관리 재시작...');
    await stop();
    await Future.delayed(const Duration(seconds: 2));
    await start();
  }

  /// 서비스 상태 확인
  bool get isRunning => _isRunning;
  
  /// 서비스 통계 정보
  Map<String, dynamic> get statistics => {
    'is_running': _isRunning,
    'cache_size': _dataCache.length,
    'cache_hits': _cacheHits,
    'cache_misses': _cacheMisses,
    'last_cleanup': _lastCleanupTime?.toIso8601String(),
    'total_cleanups': _totalCleanups,
    'data_cleanup_count': _dataCleanupCount,
    'cache_cleanup_count': _cacheCleanupCount,
  };

  /// 초기화
  Future<void> _initialize() async {
    try {
      print('🔧 스마트 생명주기 관리 초기화...');
      
      // 데이터베이스 연결 확인
      await _dbHelper.database;
      
      // 초기 상태 로드
      await _loadCurrentState();
      
      print('✅ 스마트 생명주기 관리 초기화 완료');
      
    } catch (e) {
      print('❌ 스마트 생명주기 관리 초기화 실패: $e');
      rethrow;
    }
  }

  /// 생명주기 타이머 시작
  void _startLifecycleTimer() {
    _lifecycleTimer?.cancel();
    _lifecycleTimer = Timer.periodic(_lifecycleInterval, (timer) async {
      if (_isRunning) {
        await _performLifecycleManagement();
      }
    });
    print('⏰ 생명주기 타이머 시작 (${_lifecycleInterval.inHours}시간 간격)');
  }

  /// 캐시 타이머 시작
  void _startCacheTimer() {
    _cacheTimer?.cancel();
    _cacheTimer = Timer.periodic(_cacheInterval, (timer) async {
      if (_isRunning) {
        await _cleanupCache();
      }
    });
    print('⏰ 캐시 타이머 시작 (${_cacheInterval.inMinutes}분 간격)');
  }

  /// 생명주기 관리 수행
  Future<void> _performLifecycleManagement() async {
    if (!_isRunning) return;

    try {
      print('🔄 생명주기 관리 시작...');
      
      // 1. 변경 감지 및 처리
      await _detectAndHandleChanges();
      
      // 2. 데이터 정리
      await _cleanupOldData();
      
      // 3. 비활성 종목 데이터 정리
      await _cleanupInactiveStocks();
      
      // 4. 데이터베이스 최적화
      await _optimizeDatabase();
      
      print('✅ 생명주기 관리 완료');
      
    } catch (e) {
      print('❌ 생명주기 관리 실패: $e');
    }
  }

  /// 변경 감지 및 처리
  Future<void> _detectAndHandleChanges() async {
    try {
      print('🔍 변경 감지 시작...');
      
      // 현재 상태 조회
      final currentWatchlist = await _getWatchlistStockCodes();
      final currentHoldings = await _getHoldingsStockCodes();
      
      // 관심종목 변경 감지
      final watchlistChanges = _detectChanges(_previousWatchlist, currentWatchlist);
      if ((watchlistChanges['added']?.isNotEmpty ?? false) || (watchlistChanges['removed']?.isNotEmpty ?? false)) {
        print('📋 관심종목 변경 감지:');
        print('  추가: ${watchlistChanges['added']}');
        print('  제거: ${watchlistChanges['removed']}');
        
        await _handleWatchlistChanges(watchlistChanges);
      }
      
      // 보유종목 변경 감지
      final holdingsChanges = _detectChanges(_previousHoldings, currentHoldings);
      if ((holdingsChanges['added']?.isNotEmpty ?? false) || (holdingsChanges['removed']?.isNotEmpty ?? false)) {
        print('📊 보유종목 변경 감지:');
        print('  추가: ${holdingsChanges['added']}');
        print('  제거: ${holdingsChanges['removed']}');
        
        await _handleHoldingsChanges(holdingsChanges);
      }
      
      // 현재 상태 저장
      _previousWatchlist = currentWatchlist;
      _previousHoldings = currentHoldings;
      await _saveCurrentState();
      
    } catch (e) {
      print('❌ 변경 감지 실패: $e');
    }
  }

  /// 관심종목 변경 처리
  Future<void> _handleWatchlistChanges(Map<String, List<String>> changes) async {
    try {
      // 새로 추가된 종목 데이터 로딩
      for (final stockCode in changes['added']!) {
        print('📊 새 관심종목 데이터 로딩: $stockCode');
        try {
          await _dataManager.loadStockData(stockCode, 'UNKNOWN');
          await _dataManager.loadCurrentPriceData(stockCode, 'UNKNOWN');
        } catch (e) {
          print('❌ $stockCode 데이터 로딩 실패: $e');
        }
      }
      
      // 제거된 종목은 데이터 유지 (다른 곳에서 사용할 수 있음)
      print('📋 제거된 관심종목 데이터는 유지 (다른 용도로 사용 가능)');
      
    } catch (e) {
      print('❌ 관심종목 변경 처리 실패: $e');
    }
  }

  /// 보유종목 변경 처리
  Future<void> _handleHoldingsChanges(Map<String, List<String>> changes) async {
    try {
      // 새로 추가된 종목 데이터 로딩
      for (final stockCode in changes['added']!) {
        print('📊 새 보유종목 데이터 로딩: $stockCode');
        try {
          await _dataManager.loadStockData(stockCode, 'UNKNOWN');
          await _dataManager.loadCurrentPriceData(stockCode, 'UNKNOWN');
        } catch (e) {
          print('❌ $stockCode 데이터 로딩 실패: $e');
        }
      }
      
      // 제거된 종목은 데이터 유지 (다른 곳에서 사용할 수 있음)
      print('📊 제거된 보유종목 데이터는 유지 (다른 용도로 사용 가능)');
      
    } catch (e) {
      print('❌ 보유종목 변경 처리 실패: $e');
    }
  }

  /// 변경 감지
  Map<String, List<String>> _detectChanges(List<String> previous, List<String> current) {
    final added = current.where((item) => !previous.contains(item)).toList();
    final removed = previous.where((item) => !current.contains(item)).toList();
    
    return {
      'added': added,
      'removed': removed,
    };
  }

  /// 오래된 데이터 정리
  Future<void> _cleanupOldData() async {
    try {
      print('🧹 오래된 데이터 정리 시작...');
      
      // 100일 초과 차트 데이터 정리
      final chartCleanupResult = await _chartRepo.cleanupOldChartData();
      print('📈 차트 데이터 정리: ${chartCleanupResult['deleted_records']}개 레코드 삭제');
      
      // 1시간 초과 현재가 데이터 정리
      final priceCleanupResult = await _currentPriceRepo.cleanupOldCurrentPriceData();
      print('💰 현재가 데이터 정리: ${priceCleanupResult['deleted_records']}개 레코드 삭제');
      
      // 7일 초과 AI 추천 데이터 정리
      final aiCleanupResult = await _aiRepo.cleanupOldRecommendations();
      print('🤖 AI 추천 데이터 정리: ${aiCleanupResult['deleted_records']}개 레코드 삭제');
      
    } catch (e) {
      print('❌ 오래된 데이터 정리 실패: $e');
    }
  }

  /// 비활성 종목 데이터 정리
  Future<void> _cleanupInactiveStocks() async {
    try {
      print('🧹 비활성 종목 데이터 정리 시작...');
      
      // 활성 종목 목록 조회
      final activeStocks = <String>{};
      
      // 관심종목 추가
      final watchlist = await _getWatchlistStockCodes();
      activeStocks.addAll(watchlist);
      
      // 보유종목 추가
      final holdings = await _getHoldingsStockCodes();
      activeStocks.addAll(holdings);
      
      // 비활성 종목 데이터 정리
      final chartCleanupResult = await _chartRepo.cleanupInactiveStocks(activeStocks.toList());
      print('📈 비활성 종목 차트 데이터 정리: ${chartCleanupResult['deleted_records']}개 레코드 삭제');
      
      final priceCleanupResult = await _currentPriceRepo.cleanupInactiveStocks(activeStocks.toList());
      print('💰 비활성 종목 현재가 데이터 정리: ${priceCleanupResult['deleted_records']}개 레코드 삭제');
      
    } catch (e) {
      print('❌ 비활성 종목 데이터 정리 실패: $e');
    }
  }

  /// 데이터베이스 최적화
  Future<void> _optimizeDatabase() async {
    try {
      print('⚡ 데이터베이스 최적화 시작...');
      
      // VACUUM 실행 (SQLite 최적화)
      await _dbHelper.optimizeDatabase();
      
      print('✅ 데이터베이스 최적화 완료');
      
    } catch (e) {
      print('❌ 데이터베이스 최적화 실패: $e');
    }
  }

  /// 캐시 정리
  Future<void> _cleanupCache() async {
    try {
      final now = DateTime.now();
      final expiredKeys = <String>[];
      
      // 만료된 캐시 항목 찾기
      for (final entry in _cacheTimestamps.entries) {
        if (now.difference(entry.value) > _cacheExpiry) {
          expiredKeys.add(entry.key);
        }
      }
      
      // 만료된 항목 제거
      for (final key in expiredKeys) {
        _dataCache.remove(key);
        _cacheTimestamps.remove(key);
      }
      
      // 캐시 크기 제한
      if (_dataCache.length > _maxCacheSize) {
        final sortedEntries = _cacheTimestamps.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        
        final removeCount = _dataCache.length - _maxCacheSize;
        for (int i = 0; i < removeCount; i++) {
          final key = sortedEntries[i].key;
          _dataCache.remove(key);
          _cacheTimestamps.remove(key);
        }
      }
      
      if (expiredKeys.isNotEmpty || _dataCache.length > _maxCacheSize) {
        print('🧹 캐시 정리: ${expiredKeys.length}개 만료, ${_dataCache.length}개 유지');
      }
      
    } catch (e) {
      print('❌ 캐시 정리 실패: $e');
    }
  }

  /// 캐시에 데이터 저장
  void setCache(String key, dynamic data) {
    _dataCache[key] = data;
    _cacheTimestamps[key] = DateTime.now();
  }

  /// 캐시에서 데이터 조회
  dynamic getCache(String key) {
    final timestamp = _cacheTimestamps[key];
    if (timestamp == null) return null;
    
    // 만료 체크
    if (DateTime.now().difference(timestamp) > _cacheExpiry) {
      _dataCache.remove(key);
      _cacheTimestamps.remove(key);
      return null;
    }
    
    return _dataCache[key];
  }

  /// 캐시 정리
  void _clearCache() {
    _dataCache.clear();
    _cacheTimestamps.clear();
  }

  /// 관심종목 종목코드 조회
  Future<List<String>> _getWatchlistStockCodes() async {
    try {
      final watchlist = await _watchlistRepo.getWatchlist();
      return watchlist.map((item) => item['stock_code'] as String).toList();
    } catch (e) {
      print('❌ 관심종목 조회 실패: $e');
      return [];
    }
  }

  /// 보유종목 종목코드 조회
  Future<List<String>> _getHoldingsStockCodes() async {
    try {
      final holdings = await _holdingsRepo.getAllHoldings();
      return holdings.map((item) => item['stockCode'] as String? ?? '').where((code) => code.isNotEmpty).toList();
    } catch (e) {
      print('❌ 보유종목 조회 실패: $e');
      return [];
    }
  }

  /// 현재 상태 저장
  Future<void> _saveCurrentState() async {
    try {
      // 간단한 메모리 저장 (실제로는 SharedPreferences 사용 가능)
      _previousWatchlist = await _getWatchlistStockCodes();
      _previousHoldings = await _getHoldingsStockCodes();
    } catch (e) {
      print('❌ 현재 상태 저장 실패: $e');
    }
  }

  /// 현재 상태 로드
  Future<void> _loadCurrentState() async {
    try {
      _previousWatchlist = await _getWatchlistStockCodes();
      _previousHoldings = await _getHoldingsStockCodes();
    } catch (e) {
      print('❌ 현재 상태 로드 실패: $e');
      _previousWatchlist = [];
      _previousHoldings = [];
    }
  }

  /// 서비스 정리
  void dispose() {
    stop();
  }
}
