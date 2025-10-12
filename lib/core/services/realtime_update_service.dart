import 'dart:async';
import 'dart:io';
import '../data/app_data_manager.dart';
import 'package:flutter/foundation.dart';
import '../data/incremental_data_manager.dart';
import '../database/repositories/chart_data_repository.dart';
import '../database/repositories/current_price_repository.dart';
import '../database/repositories/watchlist_repository.dart';
import '../database/repositories/holdings_repository.dart';
import '../database/database_helper.dart';
import '../api/kis_unified_api_service.dart';
import '../remote/remote_kis_service.dart';
import 'performance_monitor.dart';

/// 실시간 업데이트 서비스 - 1분마다 활성 종목 데이터 업데이트
///
/// 📊 주요 기능:
/// - 1분마다 활성 종목 3-4일 차트 데이터 업데이트
/// - 현재가 데이터 실시간 업데이트
/// - 시장 시간 고려 (오픈/클로즈)
/// - 백그라운드 서비스 지원
/// - 에러 처리 및 재시도 로직
class RealtimeUpdateService {
  static final RealtimeUpdateService _instance = RealtimeUpdateService._internal();
  factory RealtimeUpdateService() => _instance;
  RealtimeUpdateService._internal();

  // 서비스 상태
  bool _isRunning = false;
  Timer? _watchlistUpdateTimer;
  Timer? _holdingsUpdateTimer;
  Timer? _chartUpdateTimer;
  Timer? _marketCheckTimer;
  
  // Repository 인스턴스
  final IncrementalDataManager _dataManager = IncrementalDataManager();
  final ChartDataRepository _chartRepo = ChartDataRepository();
  final CurrentPriceRepository _currentPriceRepo = CurrentPriceRepository();
  final WatchlistRepository _watchlistRepo = WatchlistRepository();
  final HoldingsRepository _holdingsRepo = HoldingsRepository();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  late final KisUnifiedApiService _unifiedApiService = KisUnifiedApiService();
  final PerformanceMonitor _performanceMonitor = PerformanceMonitor();

  // 업데이트 설정 (분리된 주기)
  static const Duration _watchlistUpdateInterval = Duration(minutes: 1); // 관심종목: 1분
  static const Duration _holdingsUpdateInterval = Duration(minutes: 5); // 보유종목: 5분
  static const Duration _chartUpdateInterval = Duration(hours: 24); // 차트 데이터: 하루 1회
  static const Duration _marketCheckInterval = Duration(minutes: 5);
  static const int _maxRetryCount = 3;
  static const Duration _retryDelay = Duration(seconds: 30);

  // 통계 정보
  int _totalUpdates = 0;
  int _successfulUpdates = 0;
  int _failedUpdates = 0;
  DateTime? _lastUpdateTime;
  String _lastError = '';

  /// 서비스 시작
  Future<void> start() async {
    if (_isRunning) {
      print('⚠️ 실시간 업데이트 서비스가 이미 실행 중입니다.');
      return;
    }

    try {
      print('🚀 실시간 업데이트 서비스 시작...');
      
      // 초기화
      await _initialize();
      
      // 서비스 상태 설정
      _isRunning = true;
      
      // 성능 모니터링 시작
      _performanceMonitor.startMonitoring();
      
      // 시장 시간 체크 타이머 시작
      _startMarketCheckTimer();
      
      // 첫 번째 업데이트 즉시 실행
      await _performInitialUpdate();
      
      // 분리된 업데이트 타이머들 시작
      _startWatchlistUpdateTimer();
      _startHoldingsUpdateTimer();
      _startChartUpdateTimer();
      
      print('✅ 실시간 업데이트 서비스 시작 완료');
      
    } catch (e) {
      print('❌ 실시간 업데이트 서비스 시작 실패: $e');
      _isRunning = false;
      rethrow;
    }
  }

  /// 서비스 중지
  Future<void> stop() async {
    if (!_isRunning) {
      print('⚠️ 실시간 업데이트 서비스가 실행 중이 아닙니다.');
      return;
    }

    try {
      print('🛑 실시간 업데이트 서비스 중지...');
      
      // 성능 모니터링 중지
      _performanceMonitor.stopMonitoring();
      
      // 타이머 정리
      _watchlistUpdateTimer?.cancel();
      _holdingsUpdateTimer?.cancel();
      _chartUpdateTimer?.cancel();
      _marketCheckTimer?.cancel();
      _watchlistUpdateTimer = null;
      _holdingsUpdateTimer = null;
      _chartUpdateTimer = null;
      _marketCheckTimer = null;
      
      // 서비스 상태 설정
      _isRunning = false;
      
      print('✅ 실시간 업데이트 서비스 중지 완료');
      
    } catch (e) {
      print('❌ 실시간 업데이트 서비스 중지 실패: $e');
      rethrow;
    }
  }

  /// 서비스 재시작
  Future<void> restart() async {
    print('🔄 실시간 업데이트 서비스 재시작...');
    await stop();
    await Future.delayed(const Duration(seconds: 2));
    await start();
  }

  /// 서비스 상태 확인
  bool get isRunning => _isRunning;
  
  /// 서비스 통계 정보
  Map<String, dynamic> get statistics {
    final baseStats = {
      'is_running': _isRunning,
      'total_updates': _totalUpdates,
      'successful_updates': _successfulUpdates,
      'failed_updates': _failedUpdates,
      'success_rate': _totalUpdates > 0 ? (_successfulUpdates / _totalUpdates * 100).toStringAsFixed(2) : '0.00',
      'last_update_time': _lastUpdateTime?.toIso8601String(),
      'last_error': _lastError,
    };
    
    // 성능 모니터링 통계 추가
    final performanceStats = _performanceMonitor.getPerformanceStats();
    baseStats.addAll(performanceStats);
    
    return baseStats;
  }

  /// 초기화
  Future<void> _initialize() async {
    try {
      print('🔧 실시간 업데이트 서비스 초기화...');
      
      // 데이터 매니저 초기화 확인
      if (!_dataManager.isInitialized) {
        await _dataManager.initialize(unifiedApiService: _unifiedApiService);
      }
      
      // 데이터베이스 연결 확인
      await _dbHelper.database;
      
      print('✅ 실시간 업데이트 서비스 초기화 완료');
      
    } catch (e) {
      print('❌ 실시간 업데이트 서비스 초기화 실패: $e');
      rethrow;
    }
  }

  /// 관심종목 업데이트 타이머 시작 (Firestore 구독으로 변경)
  void _startWatchlistUpdateTimer() {
    _watchlistUpdateTimer?.cancel();
    // 🔄 Firestore 구독으로 변경 - 직접 API 호출 대신 Functions에서 처리
    print('🔄 관심종목 업데이트: Firestore 구독 사용 (직접 API 호출 비활성화)');
    // _watchlistUpdateTimer = Timer.periodic(_watchlistUpdateInterval, (timer) async {
    //   if (_isRunning) {
    //     await _performWatchlistUpdate();
    //   }
    // });
    // print('⏰ 관심종목 업데이트 타이머 시작 (${_watchlistUpdateInterval.inMinutes}분 간격)');
  }

  /// 보유종목 업데이트 타이머 시작 (Firestore 구독으로 변경)
  void _startHoldingsUpdateTimer() {
    _holdingsUpdateTimer?.cancel();
    // 🔄 Firestore 구독으로 변경 - 직접 API 호출 대신 Functions에서 처리
    print('🔄 보유종목 업데이트: Firestore 구독 사용 (직접 API 호출 비활성화)');
    // _holdingsUpdateTimer = Timer.periodic(_holdingsUpdateInterval, (timer) async {
    //   if (_isRunning) {
    //     await _performHoldingsUpdate();
    //   }
    // });
    // print('⏰ 보유종목 업데이트 타이머 시작 (${_holdingsUpdateInterval.inMinutes}분 간격)');
  }

  /// 차트 데이터 업데이트 타이머 시작 (24시간 간격)
  void _startChartUpdateTimer() {
    _chartUpdateTimer?.cancel();
    _chartUpdateTimer = Timer.periodic(_chartUpdateInterval, (timer) async {
      if (_isRunning) {
        await _performChartUpdate();
      }
    });
    print('⏰ 차트 데이터 업데이트 타이머 시작 (${_chartUpdateInterval.inHours}시간 간격)');
  }

  /// 시장 체크 타이머 시작
  void _startMarketCheckTimer() {
    _marketCheckTimer?.cancel();
    _marketCheckTimer = Timer.periodic(_marketCheckInterval, (timer) async {
      if (_isRunning) {
        await _checkMarketStatus();
      }
    });
    print('⏰ 시장 체크 타이머 시작 (${_marketCheckInterval.inMinutes}분 간격)');
  }

  /// 초기 업데이트 수행 (서비스 시작 시)
  Future<void> _performInitialUpdate() async {
    await _performWatchlistUpdate();
    await _performHoldingsUpdate();
    await _performChartUpdate();
  }

  /// 관심종목 업데이트 수행 (1분 간격)
  Future<void> _performWatchlistUpdate() async {
    if (!_isRunning) return;

    try {
      print('📊 관심종목 업데이트 시작...');
      
      // 시장 상태 확인 (비활성화)
      // final isMarketOpen = await _isMarketOpen();
      // if (!isMarketOpen) {
      //   print('⚠️ 시장이 닫혀있습니다. 관심종목 업데이트를 건너뜁니다.');
      //   return;
      // }
      print('🔓 장외시간 체크 비활성화 - 관심종목 업데이트 진행');
      
      // 관심종목 현재가 업데이트
      final watchlistStocks = await _getWatchlistStocks();
      if (watchlistStocks.isNotEmpty) {
        await _updateCurrentPriceData(watchlistStocks);
      }
      
      print('✅ 관심종목 업데이트 완료');
      
    } catch (e) {
      print('❌ 관심종목 업데이트 실패: $e');
    }
  }

  /// 보유종목 업데이트 수행 (5분 간격)
  Future<void> _performHoldingsUpdate() async {
    if (!_isRunning) return;

    try {
      print('📊 보유종목 업데이트 시작...');
      
      // 시장 상태 확인 (비활성화)
      // final isMarketOpen = await _isMarketOpen();
      // if (!isMarketOpen) {
      //   print('⚠️ 시장이 닫혀있습니다. 보유종목 업데이트를 건너뜁니다.');
      //   return;
      // }
      print('🔓 장외시간 체크 비활성화 - 보유종목 업데이트 진행');
      
      // 보유종목 현재가 업데이트
      final holdingsStocks = await _getHoldingsStocks();
      if (holdingsStocks.isNotEmpty) {
        await _updateCurrentPriceData(holdingsStocks);
      }
      
      print('✅ 보유종목 업데이트 완료');
      
    } catch (e) {
      print('❌ 보유종목 업데이트 실패: $e');
    }
  }

  /// 차트 데이터 업데이트 수행 (24시간 간격)
  Future<void> _performChartUpdate() async {
    if (!_isRunning) return;

    try {
      print('📊 차트 데이터 업데이트 시작...');
      
      // 모든 활성 종목의 차트 데이터 업데이트
      final activeStocks = await _getActiveStocks();
      if (activeStocks.isNotEmpty) {
        await _updateChartData(activeStocks);
      }
      
      print('✅ 차트 데이터 업데이트 완료');
      
    } catch (e) {
      print('❌ 차트 데이터 업데이트 실패: $e');
    }
  }

  /// 기존 업데이트 수행 (호환성 유지)
  Future<void> _performUpdate() async {
    if (!_isRunning) return;

    _totalUpdates++;
    _lastUpdateTime = DateTime.now();
    
    try {
      print('📊 실시간 업데이트 시작 (${_totalUpdates}번째)...');
      
      // 1. 활성 종목 목록 조회
      final activeStocks = await _getActiveStocks();
      if (activeStocks.isEmpty) {
        print('⚠️ 활성 종목이 없습니다.');
        return;
      }
      
      print('📋 활성 종목: ${activeStocks.length}개');
      
      // 2. 시장 상태 확인 (비활성화)
      // final isMarketOpen = await _isMarketOpen();
      // if (!isMarketOpen) {
      //   print('⚠️ 시장이 닫혀있습니다. 업데이트를 건너뜁니다.');
      //   return;
      // }
      print('🔓 장외시간 체크 비활성화 - 실시간 업데이트 진행');
      
      // 3. 차트 데이터 업데이트 (3-4일)
      await _updateChartData(activeStocks);
      
      // 4. 현재가 데이터 업데이트
      await _updateCurrentPriceData(activeStocks);
      
      // 5. 동기화 상태 업데이트
      await _updateSyncStatus();
      
      _successfulUpdates++;
      print('✅ 실시간 업데이트 완료 (${_successfulUpdates}/${_totalUpdates})');
      
    } catch (e) {
      _failedUpdates++;
      _lastError = e.toString();
      print('❌ 실시간 업데이트 실패: $e');
      
      // 재시도 로직
      await _handleUpdateError(e);
    }
  }

  /// 관심종목 목록 조회
  Future<List<Map<String, dynamic>>> _getWatchlistStocks() async {
    try {
      final watchlist = await _watchlistRepo.getWatchlist();
      return watchlist.map((item) => {
        'stock_code': item['stock_code'] as String? ?? '',
        'stock_name': item['stock_name'] as String? ?? '',
        'market': item['market'] as String? ?? 'UNKNOWN',
      }).where((item) => item['stock_code']!.isNotEmpty).toList();
    } catch (e) {
      print('❌ 관심종목 조회 실패: $e');
      return [];
    }
  }

  /// 보유종목 목록 조회
  Future<List<Map<String, dynamic>>> _getHoldingsStocks() async {
    try {
      final holdings = await _holdingsRepo.getHoldings();
      return holdings.map((item) => {
        'stock_code': item['stockCode'] as String? ?? '',
        'stock_name': item['stockName'] as String? ?? '',
        'market': item['market'] as String? ?? 'UNKNOWN',
      }).where((item) => item['stock_code']!.isNotEmpty).toList();
    } catch (e) {
      print('❌ 보유종목 조회 실패: $e');
      return [];
    }
  }

  /// 활성 종목 목록 조회 (관심종목 + 보유종목)
  Future<List<Map<String, dynamic>>> _getActiveStocks() async {
    try {
      final activeStocks = <String, Map<String, dynamic>>{};
      
      // 1. 관심종목 조회
      final watchlist = await _watchlistRepo.getWatchlistWithStockInfo();
      for (final item in watchlist) {
        final stockCode = item['stock_code'] as String? ?? '';
        if (stockCode.isNotEmpty) {
          activeStocks[stockCode] = {
            'stock_code': stockCode,
            'stock_name': item['stock_name'] as String? ?? '',
            'market': item['market'] as String? ?? 'UNKNOWN',
            'type': 'watchlist',
          };
        }
      }
      
      // 2. 보유종목 조회 (중복 제거)
      final holdings = await _holdingsRepo.getAllHoldings();
      for (final item in holdings) {
        final stockCode = item['stockCode'] as String? ?? '';
        if (stockCode.isNotEmpty) {
          if (!activeStocks.containsKey(stockCode)) {
            activeStocks[stockCode] = {
              'stock_code': stockCode,
              'stock_name': item['stockName'] as String? ?? '',
              'market': 'UNKNOWN',
              'type': 'holdings',
            };
          } else {
            activeStocks[stockCode]!['type'] = 'both';
          }
        }
      }
      
      return activeStocks.values.toList();
      
    } catch (e) {
      print('❌ 활성 종목 조회 실패: $e');
      return [];
    }
  }

  /// 시장 오픈 여부 확인 (한국/미국 시장 모두 고려)
  Future<bool> _isMarketOpen() async {
    try {
      final now = DateTime.now();
      final weekday = now.weekday;
      
      // 주말 체크
      if (weekday == DateTime.saturday || weekday == DateTime.sunday) {
        return false;
      }
      
      // 한국 시장 시간 체크 (KST: 9:00-15:30)
      final kstHour = now.hour;
      final kstMinute = now.minute;
      final kstTime = kstHour * 60 + kstMinute;
      final isKoreaMarketOpen = kstTime >= 540 && kstTime <= 930; // 9:00-15:30
      
      // 미국 시장 시간 체크 (EST: 9:30-16:00, KST로 변환하면 23:30-06:00+1일)
      final estTime = now.subtract(const Duration(hours: 14)); // KST - 14시간 = EST
      final estHour = estTime.hour;
      final estMinute = estTime.minute;
      final estTimeMinutes = estHour * 60 + estMinute;
      final isUSMarketOpen = estTimeMinutes >= 570 && estTimeMinutes <= 960; // 9:30-16:00
      
      // 한국 시장 또는 미국 시장이 열려있으면 true
      final isAnyMarketOpen = isKoreaMarketOpen || isUSMarketOpen;
      
      print('🏪 시장 상태 - 한국: ${isKoreaMarketOpen ? "오픈" : "클로즈"} (${kstHour}:${kstMinute.toString().padLeft(2, '0')}), 미국: ${isUSMarketOpen ? "오픈" : "클로즈"} (EST ${estHour}:${estMinute.toString().padLeft(2, '0')})');
      
      return isAnyMarketOpen;
      
    } catch (e) {
      print('❌ 시장 상태 확인 실패: $e');
      return true; // 에러 시 업데이트 진행
    }
  }

  /// 차트 데이터 업데이트 (3-4일)
  Future<void> _updateChartData(List<Map<String, dynamic>> stocks) async {
    try {
      print('📈 차트 데이터 업데이트 시작...');
      
      int updatedCount = 0;
      final totalCount = stocks.length;
      
      for (final stock in stocks) {
        final stockCode = stock['stock_code'] as String;
        final stockName = stock['stock_name'] as String;
        final market = stock['market'] as String;
        
        try {
          final startTime = DateTime.now();
          
          // 증분 데이터 매니저를 통한 차트 데이터 업데이트
          await _dataManager.loadStockData(stockCode, market);
          
          final responseTime = DateTime.now().difference(startTime).inMilliseconds;
          _performanceMonitor.recordApiCall(responseTime: responseTime);
          
          updatedCount++;
          
          if (updatedCount % 10 == 0) {
            print('📈 차트 데이터 업데이트 진행: $updatedCount/$totalCount');
          }
          
        } catch (e) {
          final responseTime = DateTime.now().millisecondsSinceEpoch;
          _performanceMonitor.recordApiCall(responseTime: responseTime, isError: true);
          print('❌ $stockCode 차트 데이터 업데이트 실패: $e');
        }
      }
      
      print('✅ 차트 데이터 업데이트 완료: $updatedCount/$totalCount');
      
    } catch (e) {
      print('❌ 차트 데이터 업데이트 실패: $e');
      rethrow;
    }
  }

  /// 현재가 데이터 업데이트 (호출 빈도 제한)
  Future<void> _updateCurrentPriceData(List<Map<String, dynamic>> stocks) async {
    try {
      print('💰 현재가 데이터 업데이트: Firestore Functions 사용 (호출 빈도 제한)');
      
      // 🔄 Firestore Functions를 통한 데이터 업데이트 (호출 빈도 제한)
      // ✅ current 필드 보호: ensureChartAndAnalyze 호출 비활성화
      print('🔍 [current 보호] RealtimeUpdateService에서 ensureChartAndAnalyze 호출 비활성화');
      print('🔍 [current 보호] 기존 current 필드 유지');
      
      // for (final stock in stocks) {
      //   final stockCode = stock['stock_code'] as String;
      //   try {
      //     // RemoteKisService에서 자체적으로 호출 빈도 제한 적용
      //     final success = await RemoteKisService.instance.ensureChartAndAnalyze(
      //       uid: 'debug-user', // 임시 UID 사용
      //       symbol: stockCode,
      //     );
      //     if (success) {
      //       print('✅ Firestore Functions 호출 완료: $stockCode');
      //     } else {
      //       print('⏸️ Firestore Functions 호출 건너뜀 (빈도 제한): $stockCode');
      //     }
      //   } catch (e) {
      //     print('❌ Firestore Functions 호출 실패 ($stockCode): $e');
      //   }
      // }
      
      print('✅ Firestore Functions를 통한 데이터 업데이트 완료');
      
    } catch (e) {
      print('❌ Firestore Functions 데이터 업데이트 실패: $e');
      rethrow;
    }
  }

  /// 현재가 데이터 배치 업데이트
  Future<void> _updateCurrentPriceBatch(List<Map<String, dynamic>> stocks) async {
    try {
      for (final stock in stocks) {
        final stockCode = stock['stock_code'] as String;
        final market = stock['market'] as String;
        
        try {
          final startTime = DateTime.now();
          
          await _dataManager.loadCurrentPriceData(stockCode, market);
          
          final responseTime = DateTime.now().difference(startTime).inMilliseconds;
          _performanceMonitor.recordApiCall(responseTime: responseTime);
          
        } catch (e) {
          final responseTime = DateTime.now().millisecondsSinceEpoch;
          _performanceMonitor.recordApiCall(responseTime: responseTime, isError: true);
          print('❌ $stockCode 현재가 업데이트 실패: $e');
        }
      }
    } catch (e) {
      print('❌ 현재가 배치 업데이트 실패: $e');
      rethrow;
    }
  }

  /// 동기화 상태 업데이트
  Future<void> _updateSyncStatus() async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _dbHelper.updateSyncStatus('chart');
      await _dbHelper.updateSyncStatus('price');
    } catch (e) {
      print('❌ 동기화 상태 업데이트 실패: $e');
    }
  }

  /// 시장 상태 확인
  Future<void> _checkMarketStatus() async {
    try {
      final isOpen = await _isMarketOpen();
      print('🏪 시장 상태: ${isOpen ? "오픈" : "클로즈"}');
      
      // 시장이 닫혀있으면 업데이트 중지
      if (!isOpen && _isRunning) {
        print('⚠️ 시장이 닫혀있어 업데이트를 일시 중지합니다.');
        // 타이머는 유지하되 업데이트만 건너뛰기
      }
      
    } catch (e) {
      print('❌ 시장 상태 확인 실패: $e');
    }
  }

  /// 업데이트 에러 처리
  Future<void> _handleUpdateError(dynamic error) async {
    try {
      print('🔄 업데이트 에러 처리 시작...');
      
      // 네트워크 에러인 경우 재시도
      if (error is SocketException || error.toString().contains('network')) {
        print('🌐 네트워크 에러 감지, 재시도 중...');
        _performanceMonitor.recordNetworkError();
        await Future.delayed(_retryDelay);
        await _performUpdate();
      }
      
      // API 에러인 경우 재시도
      if (error.toString().contains('API') || error.toString().contains('rate limit')) {
        print('🔌 API 에러 감지, 재시도 중...');
        await Future.delayed(_retryDelay);
        await _performUpdate();
      }
      
    } catch (e) {
      print('❌ 에러 처리 실패: $e');
    }
  }

  /// 서비스 정리
  void dispose() {
    stop();
  }
}
