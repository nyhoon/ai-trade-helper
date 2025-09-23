import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// 성능 모니터링 서비스 - 실시간 업데이트 성능 추적
///
/// 📊 모니터링 항목:
/// - 메모리 사용량
/// - API 호출 횟수 및 응답 시간
/// - 데이터베이스 쿼리 성능
/// - 네트워크 상태
/// - 에러 발생률
class PerformanceMonitor {
  static final PerformanceMonitor _instance = PerformanceMonitor._internal();
  factory PerformanceMonitor() => _instance;
  PerformanceMonitor._internal();

  // 모니터링 상태
  bool _isMonitoring = false;
  Timer? _monitoringTimer;
  
  // 성능 메트릭
  final Map<String, dynamic> _metrics = {
    'memory_usage': <double>[],
    'api_calls': 0,
    'api_response_times': <int>[],
    'db_queries': 0,
    'db_query_times': <int>[],
    'network_errors': 0,
    'api_errors': 0,
    'db_errors': 0,
    'start_time': DateTime.now(),
    'last_update': DateTime.now(),
  };

  // 임계값 설정 (메모리 부족 방지를 위해 더 엄격하게 설정)
  static const int _maxMemoryUsage = 80; // MB (기존 100MB에서 80MB로 감소)
  static const int _maxApiResponseTime = 3000; // ms (기존 5000ms에서 3000ms로 감소)
  static const int _maxDbQueryTime = 500; // ms (기존 1000ms에서 500ms로 감소)
  static const double _maxErrorRate = 0.05; // 5% (기존 10%에서 5%로 감소)

  /// 모니터링 시작
  void startMonitoring() {
    if (_isMonitoring) {
      print('⚠️ 성능 모니터링이 이미 실행 중입니다.');
      return;
    }

    _isMonitoring = true;
    _monitoringTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _collectMetrics();
      _analyzePerformance();
    });

    print('📊 성능 모니터링 시작');
  }

  /// 모니터링 중지
  void stopMonitoring() {
    if (!_isMonitoring) {
      print('⚠️ 성능 모니터링이 실행 중이 아닙니다.');
      return;
    }

    _isMonitoring = false;
    _monitoringTimer?.cancel();
    _monitoringTimer = null;

    print('📊 성능 모니터링 중지');
  }

  /// API 호출 기록
  void recordApiCall({required int responseTime, bool isError = false}) {
    _metrics['api_calls'] = (_metrics['api_calls'] as int) + 1;
    (_metrics['api_response_times'] as List<int>).add(responseTime);
    
    if (isError) {
      _metrics['api_errors'] = (_metrics['api_errors'] as int) + 1;
    }
    
    _metrics['last_update'] = DateTime.now();
  }

  /// 데이터베이스 쿼리 기록
  void recordDbQuery({required int queryTime, bool isError = false}) {
    _metrics['db_queries'] = (_metrics['db_queries'] as int) + 1;
    (_metrics['db_query_times'] as List<int>).add(queryTime);
    
    if (isError) {
      _metrics['db_errors'] = (_metrics['db_errors'] as int) + 1;
    }
    
    _metrics['last_update'] = DateTime.now();
  }

  /// 네트워크 에러 기록
  void recordNetworkError() {
    _metrics['network_errors'] = (_metrics['network_errors'] as int) + 1;
    _metrics['last_update'] = DateTime.now();
  }

  /// 메모리 사용량 기록
  void recordMemoryUsage(double memoryUsageMB) {
    (_metrics['memory_usage'] as List<double>).add(memoryUsageMB);
    
    // 최근 10개만 유지
    if ((_metrics['memory_usage'] as List<double>).length > 10) {
      (_metrics['memory_usage'] as List<double>).removeAt(0);
    }
    
    _metrics['last_update'] = DateTime.now();
  }

  /// 성능 메트릭 수집
  void _collectMetrics() {
    try {
      // 메모리 사용량 수집 (Flutter에서는 제한적)
      // 실제 구현에서는 Platform Channel을 통해 네이티브 메모리 정보를 가져올 수 있음
      
      // 네트워크 상태 확인
      _checkNetworkStatus();
      
    } catch (e) {
      print('❌ 성능 메트릭 수집 실패: $e');
    }
  }

  /// 네트워크 상태 확인
  Future<void> _checkNetworkStatus() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      if (result.isEmpty || result[0].rawAddress.isEmpty) {
        recordNetworkError();
      }
    } catch (e) {
      recordNetworkError();
    }
  }

  /// 성능 분석
  void _analyzePerformance() {
    try {
      final recommendations = <String>[];
      
      // 1. 메모리 사용량 분석 (강화된 모니터링)
      final memoryUsage = _metrics['memory_usage'] as List<double>;
      if (memoryUsage.isNotEmpty) {
        final avgMemory = memoryUsage.reduce((a, b) => a + b) / memoryUsage.length;
        if (avgMemory > _maxMemoryUsage) {
          recommendations.add('🚨 메모리 사용량이 위험 수준입니다 (${avgMemory.toStringAsFixed(2)}MB). 즉시 데이터 캐시를 정리하고 불필요한 데이터를 해제하세요.');
          
          // 메모리 부족 시 자동 정리 시도
          _triggerMemoryCleanup();
        } else if (avgMemory > _maxMemoryUsage * 0.8) {
          recommendations.add('⚠️ 메모리 사용량이 높습니다 (${avgMemory.toStringAsFixed(2)}MB). 데이터 캐시를 정리하세요.');
        }
      }
      
      // 2. API 응답 시간 분석
      final responseTimes = _metrics['api_response_times'] as List<int>;
      if (responseTimes.isNotEmpty) {
        final avgResponseTime = responseTimes.reduce((a, b) => a + b) / responseTimes.length;
        if (avgResponseTime > _maxApiResponseTime) {
          recommendations.add('⚠️ API 응답 시간이 느립니다 (${avgResponseTime.toStringAsFixed(0)}ms). 네트워크 상태를 확인하세요.');
        }
      }
      
      // 3. 데이터베이스 쿼리 시간 분석
      final queryTimes = _metrics['db_query_times'] as List<int>;
      if (queryTimes.isNotEmpty) {
        final avgQueryTime = queryTimes.reduce((a, b) => a + b) / queryTimes.length;
        if (avgQueryTime > _maxDbQueryTime) {
          recommendations.add('⚠️ 데이터베이스 쿼리가 느립니다 (${avgQueryTime.toStringAsFixed(0)}ms). 인덱스를 확인하세요.');
        }
      }
      
      // 4. 에러율 분석
      final totalApiCalls = _metrics['api_calls'] as int;
      final apiErrors = _metrics['api_errors'] as int;
      if (totalApiCalls > 0) {
        final errorRate = apiErrors / totalApiCalls;
        if (errorRate > _maxErrorRate) {
          recommendations.add('⚠️ API 에러율이 높습니다 (${(errorRate * 100).toStringAsFixed(1)}%). API 키와 네트워크를 확인하세요.');
        }
      }
      
      // 5. 네트워크 에러 분석
      final networkErrors = _metrics['network_errors'] as int;
      if (networkErrors > 5) {
        recommendations.add('⚠️ 네트워크 에러가 많이 발생했습니다 ($networkErrors회). 인터넷 연결을 확인하세요.');
      }
      
      // 권장사항 출력
      if (recommendations.isNotEmpty) {
        print('📊 성능 최적화 권장사항:');
        for (final recommendation in recommendations) {
          print('  $recommendation');
        }
      } else {
        print('✅ 성능 상태 양호');
      }
      
    } catch (e) {
      print('❌ 성능 분석 실패: $e');
    }
  }

  /// 성능 통계 반환
  Map<String, dynamic> getPerformanceStats() {
    final stats = Map<String, dynamic>.from(_metrics);
    
    // 평균값 계산
    final responseTimes = _metrics['api_response_times'] as List<int>;
    if (responseTimes.isNotEmpty) {
      stats['avg_api_response_time'] = responseTimes.reduce((a, b) => a + b) / responseTimes.length;
    }
    
    final queryTimes = _metrics['db_query_times'] as List<int>;
    if (queryTimes.isNotEmpty) {
      stats['avg_db_query_time'] = queryTimes.reduce((a, b) => a + b) / queryTimes.length;
    }
    
    final memoryUsage = _metrics['memory_usage'] as List<double>;
    if (memoryUsage.isNotEmpty) {
      stats['avg_memory_usage'] = memoryUsage.reduce((a, b) => a + b) / memoryUsage.length;
    }
    
    // 에러율 계산
    final totalApiCalls = _metrics['api_calls'] as int;
    final apiErrors = _metrics['api_errors'] as int;
    if (totalApiCalls > 0) {
      stats['api_error_rate'] = apiErrors / totalApiCalls;
    }
    
    // 실행 시간 계산
    final startTime = _metrics['start_time'] as DateTime;
    stats['uptime_minutes'] = DateTime.now().difference(startTime).inMinutes;
    
    return stats;
  }

  /// 성능 메트릭 초기화
  void resetMetrics() {
    _metrics.clear();
    _metrics.addAll({
      'memory_usage': <double>[],
      'api_calls': 0,
      'api_response_times': <int>[],
      'db_queries': 0,
      'db_query_times': <int>[],
      'network_errors': 0,
      'api_errors': 0,
      'db_errors': 0,
      'start_time': DateTime.now(),
      'last_update': DateTime.now(),
    });
    
    print('📊 성능 메트릭 초기화 완료');
  }

  /// 모니터링 상태 확인
  bool get isMonitoring => _isMonitoring;

  /// 통합 모니터링 호환 게터
  bool get isRunning => _isMonitoring;
  Map<String, dynamic> get statistics => getPerformanceStats();

  /// 메모리 정리 트리거
  void _triggerMemoryCleanup() {
    try {
      print('🧹 메모리 정리 시작...');
      
      // 메트릭 데이터 정리 (최근 5개만 유지)
      final memoryUsage = _metrics['memory_usage'] as List<double>;
      if (memoryUsage.length > 5) {
        memoryUsage.removeRange(0, memoryUsage.length - 5);
      }
      
      final responseTimes = _metrics['api_response_times'] as List<int>;
      if (responseTimes.length > 10) {
        responseTimes.removeRange(0, responseTimes.length - 10);
      }
      
      final queryTimes = _metrics['db_query_times'] as List<int>;
      if (queryTimes.length > 10) {
        queryTimes.removeRange(0, queryTimes.length - 10);
      }
      
      print('✅ 메모리 정리 완료');
      
    } catch (e) {
      print('❌ 메모리 정리 실패: $e');
    }
  }

  /// 강제 메모리 정리 (외부에서 호출 가능)
  void forceMemoryCleanup() {
    _triggerMemoryCleanup();
  }

  /// 서비스 정리
  void dispose() {
    stopMonitoring();
  }
}
