import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/realtime_update_service.dart';
import '../services/smart_lifecycle_manager.dart';
import '../analysis/realtime_analysis_engine.dart';
import '../services/performance_monitor.dart';
import '../ai/ai_recommendation_service.dart';
import '../database/database_helper.dart';

/// 통합 모니터링 서비스 - 모든 서비스 상태 모니터링 및 관리
///
/// 📊 주요 기능:
/// - 모든 서비스 상태 실시간 모니터링
/// - 성능 통계 수집 및 분석
/// - 에러 처리 및 자동 복구
/// - 서비스 상태 대시보드 제공
/// - 로깅 시스템 관리
class IntegratedMonitoringService {
  static final IntegratedMonitoringService _instance = IntegratedMonitoringService._internal();
  factory IntegratedMonitoringService() => _instance;
  IntegratedMonitoringService._internal();

  // 서비스 상태
  bool _isRunning = false;
  Timer? _monitoringTimer;
  Timer? _healthCheckTimer;
  
  // 서비스 인스턴스
  final RealtimeUpdateService _realtimeService = RealtimeUpdateService();
  final SmartLifecycleManager _lifecycleManager = SmartLifecycleManager();
  final RealtimeAnalysisEngine _analysisEngine = RealtimeAnalysisEngine();
  final PerformanceMonitor _performanceMonitor = PerformanceMonitor();
  final AiRecommendationService _aiService = AiRecommendationService();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // 모니터링 설정
  static const Duration _monitoringInterval = Duration(minutes: 1); // 1분마다 모니터링
  static const Duration _healthCheckInterval = Duration(minutes: 5); // 5분마다 헬스체크
  static const int _maxRetryCount = 3; // 최대 재시도 횟수

  // 서비스 상태 정보
  final Map<String, Map<String, dynamic>> _serviceStatus = {};
  final List<Map<String, dynamic>> _errorLog = [];
  final List<Map<String, dynamic>> _performanceLog = [];

  /// 서비스 시작
  Future<void> start() async {
    if (_isRunning) {
      print('⚠️ 통합 모니터링 서비스가 이미 실행 중입니다.');
      return;
    }

    try {
      print('🚀 통합 모니터링 서비스 시작...');
      
      // 초기화
      await _initialize();
      
      // 서비스 상태 설정
      _isRunning = true;
      
      // 첫 번째 모니터링 즉시 실행
      await _performMonitoring();
      
      // 모니터링 타이머 시작
      _startMonitoringTimer();
      
      // 헬스체크 타이머 시작
      _startHealthCheckTimer();
      
      print('✅ 통합 모니터링 서비스 시작 완료');
      
    } catch (e) {
      print('❌ 통합 모니터링 서비스 시작 실패: $e');
      _isRunning = false;
      rethrow;
    }
  }

  /// 서비스 중지
  Future<void> stop() async {
    if (!_isRunning) {
      print('⚠️ 통합 모니터링 서비스가 실행 중이 아닙니다.');
      return;
    }

    try {
      print('🛑 통합 모니터링 서비스 중지...');
      
      // 타이머 정리
      _monitoringTimer?.cancel();
      _healthCheckTimer?.cancel();
      _monitoringTimer = null;
      _healthCheckTimer = null;
      
      // 서비스 상태 설정
      _isRunning = false;
      
      print('✅ 통합 모니터링 서비스 중지 완료');
      
    } catch (e) {
      print('❌ 통합 모니터링 서비스 중지 실패: $e');
      rethrow;
    }
  }

  /// 서비스 재시작
  Future<void> restart() async {
    print('🔄 통합 모니터링 서비스 재시작...');
    await stop();
    await Future.delayed(const Duration(seconds: 2));
    await start();
  }

  /// 서비스 상태 확인
  bool get isRunning => _isRunning;
  
  /// 전체 서비스 상태 정보
  Map<String, dynamic> get systemStatus => {
    'is_running': _isRunning,
    'services': _serviceStatus,
    'error_count': _errorLog.length,
    'performance_log_count': _performanceLog.length,
    'last_monitoring_time': DateTime.now().toIso8601String(),
  };

  /// 초기화
  Future<void> _initialize() async {
    try {
      print('🔧 통합 모니터링 서비스 초기화...');
      
      // 서비스 상태 초기화
      _serviceStatus.clear();
      _errorLog.clear();
      _performanceLog.clear();
      
      // 각 서비스 상태 초기화
      _initializeServiceStatus();
      
      print('✅ 통합 모니터링 서비스 초기화 완료');
      
    } catch (e) {
      print('❌ 통합 모니터링 서비스 초기화 실패: $e');
      rethrow;
    }
  }

  /// 서비스 상태 초기화
  void _initializeServiceStatus() {
    _serviceStatus['realtime_update'] = {
      'name': '실시간 업데이트 서비스',
      'status': 'unknown',
      'last_check': DateTime.now().millisecondsSinceEpoch,
      'error_count': 0,
      'retry_count': 0,
    };
    
    _serviceStatus['smart_lifecycle'] = {
      'name': '스마트 생명주기 관리',
      'status': 'unknown',
      'last_check': DateTime.now().millisecondsSinceEpoch,
      'error_count': 0,
      'retry_count': 0,
    };
    
    _serviceStatus['analysis_engine'] = {
      'name': '실시간 분석 엔진',
      'status': 'unknown',
      'last_check': DateTime.now().millisecondsSinceEpoch,
      'error_count': 0,
      'retry_count': 0,
    };
    
    _serviceStatus['ai_recommendation'] = {
      'name': 'AI 추천 서비스',
      'status': 'unknown',
      'last_check': DateTime.now().millisecondsSinceEpoch,
      'error_count': 0,
      'retry_count': 0,
    };
    
    _serviceStatus['performance_monitor'] = {
      'name': '성능 모니터링',
      'status': 'unknown',
      'last_check': DateTime.now().millisecondsSinceEpoch,
      'error_count': 0,
      'retry_count': 0,
    };
  }

  /// 모니터링 타이머 시작
  void _startMonitoringTimer() {
    _monitoringTimer?.cancel();
    _monitoringTimer = Timer.periodic(_monitoringInterval, (timer) async {
      if (_isRunning) {
        await _performMonitoring();
      }
    });
    print('⏰ 모니터링 타이머 시작 (${_monitoringInterval.inMinutes}분 간격)');
  }

  /// 헬스체크 타이머 시작
  void _startHealthCheckTimer() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(_healthCheckInterval, (timer) async {
      if (_isRunning) {
        await _performHealthCheck();
      }
    });
    print('⏰ 헬스체크 타이머 시작 (${_healthCheckInterval.inMinutes}분 간격)');
  }

  /// 모니터링 수행
  Future<void> _performMonitoring() async {
    if (!_isRunning) return;

    try {
      print('📊 통합 모니터링 시작...');
      
      // 1. 각 서비스 상태 확인
      await _checkServiceStatus();
      
      // 2. 성능 통계 수집
      await _collectPerformanceStats();
      
      // 3. 에러 로그 분석
      await _analyzeErrorLogs();
      
      // 4. 시스템 상태 요약 출력
      _printSystemSummary();
      
      print('✅ 통합 모니터링 완료');
      
    } catch (e) {
      print('❌ 통합 모니터링 실패: $e');
      _logError('monitoring', '모니터링 실패', e.toString());
    }
  }

  /// 서비스 상태 확인
  Future<void> _checkServiceStatus() async {
    try {
      // 실시간 업데이트 서비스 상태 확인
      await _checkService('realtime_update', _realtimeService);
      
      // 스마트 생명주기 관리 상태 확인
      await _checkService('smart_lifecycle', _lifecycleManager);
      
      // 실시간 분석 엔진 상태 확인
      await _checkService('analysis_engine', _analysisEngine);
      
      // AI 추천 서비스는 자동 상태 확인/재시작 대상에서 제외 (수동 실행 전용)
      
      // 성능 모니터링 상태 확인
      await _checkService('performance_monitor', _performanceMonitor);
      
    } catch (e) {
      print('❌ 서비스 상태 확인 실패: $e');
      _logError('service_check', '서비스 상태 확인 실패', e.toString());
    }
  }

  /// 개별 서비스 상태 확인
  Future<void> _checkService(String serviceKey, dynamic service) async {
    try {
      final status = _serviceStatus[serviceKey]!;
      final isRunning = service.isRunning;
      
      status['status'] = isRunning ? 'running' : 'stopped';
      status['last_check'] = DateTime.now().millisecondsSinceEpoch;
      
      if (isRunning) {
        // 서비스 통계 정보 수집
        if (service.statistics != null) {
          status['statistics'] = service.statistics;
        }
        status['error_count'] = 0; // 성공 시 에러 카운트 리셋
      } else {
        status['error_count'] = (status['error_count'] as int) + 1;
      }
      
    } catch (e) {
      print('❌ $serviceKey 상태 확인 실패: $e');
      final status = _serviceStatus[serviceKey]!;
      status['status'] = 'error';
      status['error_count'] = (status['error_count'] as int) + 1;
      status['last_error'] = e.toString();
      
      _logError(serviceKey, '서비스 상태 확인 실패', e.toString());
    }
  }

  /// 성능 통계 수집
  Future<void> _collectPerformanceStats() async {
    try {
      final performanceStats = _performanceMonitor.getPerformanceStats();
      
      _performanceLog.add({
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'stats': performanceStats,
      });
      
      // 최근 100개만 유지
      if (_performanceLog.length > 100) {
        _performanceLog.removeAt(0);
      }
      
      print('📈 성능 통계 수집 완료');
      
    } catch (e) {
      print('❌ 성능 통계 수집 실패: $e');
      _logError('performance', '성능 통계 수집 실패', e.toString());
    }
  }

  /// 에러 로그 분석
  Future<void> _analyzeErrorLogs() async {
    try {
      if (_errorLog.isEmpty) {
        print('✅ 에러 로그 없음');
        return;
      }
      
      // 최근 에러 분석
      final recentErrors = _errorLog.where((error) {
        final timestamp = error['timestamp'] as int;
        final errorTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        final now = DateTime.now();
        return now.difference(errorTime).inMinutes < 10; // 최근 10분
      }).toList();
      
      if (recentErrors.isNotEmpty) {
        print('⚠️ 최근 10분간 ${recentErrors.length}개 에러 발생');
        
        // 에러별 그룹핑
        final errorGroups = <String, int>{};
        for (final error in recentErrors) {
          final service = error['service'] as String;
          errorGroups[service] = (errorGroups[service] ?? 0) + 1;
        }
        
        for (final entry in errorGroups.entries) {
          print('  - ${entry.key}: ${entry.value}개');
        }
      }
      
    } catch (e) {
      print('❌ 에러 로그 분석 실패: $e');
    }
  }

  /// 헬스체크 수행
  Future<void> _performHealthCheck() async {
    try {
      print('🏥 시스템 헬스체크 시작...');
      
      // 1. 데이터베이스 연결 확인
      await _checkDatabaseHealth();
      
      // 2. 서비스 상태 확인
      await _checkServiceHealth();
      
      // 3. 자동 복구 시도
      await _attemptAutoRecovery();
      
      print('✅ 시스템 헬스체크 완료');
      
    } catch (e) {
      print('❌ 시스템 헬스체크 실패: $e');
      _logError('health_check', '헬스체크 실패', e.toString());
    }
  }

  /// 데이터베이스 헬스체크
  Future<void> _checkDatabaseHealth() async {
    try {
      final db = await _dbHelper.database;
      await db.rawQuery('SELECT 1'); // 간단한 쿼리로 연결 확인
      print('✅ 데이터베이스 연결 정상');
    } catch (e) {
      print('❌ 데이터베이스 연결 실패: $e');
      _logError('database', '데이터베이스 연결 실패', e.toString());
    }
  }

  /// 서비스 헬스체크
  Future<void> _checkServiceHealth() async {
    try {
      for (final entry in _serviceStatus.entries) {
        final serviceKey = entry.key;
        final status = entry.value;
        final errorCount = status['error_count'] as int;
        
        if (errorCount > 5) {
          print('⚠️ $serviceKey 에러가 많이 발생함 ($errorCount회)');
          
          // 자동 재시작 시도
          await _attemptServiceRestart(serviceKey);
        }
      }
    } catch (e) {
      print('❌ 서비스 헬스체크 실패: $e');
    }
  }

  /// 자동 복구 시도
  Future<void> _attemptAutoRecovery() async {
    try {
      for (final entry in _serviceStatus.entries) {
        final serviceKey = entry.key;
        final status = entry.value;
        final currentStatus = status['status'] as String;
        final retryCount = status['retry_count'] as int;
        
        if (currentStatus == 'error' && retryCount < _maxRetryCount) {
          print('🔄 $serviceKey 자동 복구 시도 (${retryCount + 1}/$_maxRetryCount)');
          
          await _attemptServiceRestart(serviceKey);
        }
      }
    } catch (e) {
      print('❌ 자동 복구 실패: $e');
    }
  }

  /// 서비스 재시작 시도
  Future<void> _attemptServiceRestart(String serviceKey) async {
    try {
      final status = _serviceStatus[serviceKey]!;
      status['retry_count'] = (status['retry_count'] as int) + 1;
      
      switch (serviceKey) {
        case 'realtime_update':
          await _realtimeService.restart();
          break;
        case 'smart_lifecycle':
          await _lifecycleManager.restart();
          break;
        case 'analysis_engine':
          await _analysisEngine.restart();
          break;
        case 'ai_recommendation':
          // 추천 서비스는 수동 실행 전용: 자동 재시작하지 않음
          return;
        case 'performance_monitor':
          _performanceMonitor.stopMonitoring();
          _performanceMonitor.startMonitoring();
          break;
      }
      
      print('✅ $serviceKey 재시작 성공');
      _serviceStatus[serviceKey] = {
        ..._serviceStatus[serviceKey]!,
        'status': 'running',
        'error_count': 0,
      };
      
    } catch (e) {
      print('❌ $serviceKey 재시작 실패: $e');
      _serviceStatus[serviceKey] = {
        ..._serviceStatus[serviceKey]!,
        'status': 'error',
      };
      _logError(serviceKey, '서비스 재시작 실패', e.toString());
    }
  }

  /// 에러 로그 기록
  void _logError(String service, String message, String details) {
    _errorLog.add({
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'service': service,
      'message': message,
      'details': details,
    });
    
    // 최근 1000개만 유지
    if (_errorLog.length > 1000) {
      _errorLog.removeAt(0);
    }
  }

  /// 시스템 상태 요약 출력
  void _printSystemSummary() {
    print('\n📊 시스템 상태 요약:');
    print('=' * 50);
    
    for (final entry in _serviceStatus.entries) {
      final serviceKey = entry.key;
      final status = entry.value;
      final serviceName = status['name'] as String;
      final currentStatus = status['status'] as String;
      final errorCount = status['error_count'] as int;
      
      final statusIcon = currentStatus == 'running' ? '✅' : 
                        currentStatus == 'stopped' ? '⏸️' : '❌';
      
      print('$statusIcon $serviceName: $currentStatus (에러: $errorCount회)');
    }
    
    print('=' * 50);
    print('총 에러 로그: ${_errorLog.length}개');
    print('성능 로그: ${_performanceLog.length}개');
    print('모니터링 상태: ${_isRunning ? "실행 중" : "중지됨"}');
    print('');
  }

  /// 에러 로그 조회
  List<Map<String, dynamic>> getErrorLogs({int limit = 100}) {
    final sortedLogs = List<Map<String, dynamic>>.from(_errorLog)
      ..sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));
    
    return sortedLogs.take(limit).toList();
  }

  /// 성능 로그 조회
  List<Map<String, dynamic>> getPerformanceLogs({int limit = 100}) {
    final sortedLogs = List<Map<String, dynamic>>.from(_performanceLog)
      ..sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));
    
    return sortedLogs.take(limit).toList();
  }

  /// 서비스 정리
  void dispose() {
    stop();
  }
}
