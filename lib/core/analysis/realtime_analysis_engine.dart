import 'dart:async';
import 'package:flutter/foundation.dart';
import '../database/repositories/historical_data_repository.dart';
import '../database/repositories/current_price_repository.dart';
import '../database/repositories/analysis_results_repository.dart';
import '../analysis/dynamicCal/comprehensive_indicator_calculator.dart';
import '../services/smart_lifecycle_manager.dart';
import '../constants/chart_constants.dart';

/// 실시간 분석 엔진 - 로컬DB → 지표 계산 → 캐싱 → 신호
///
/// 📊 주요 기능:
/// - 로컬DB에서 차트 데이터 실시간 조회
/// - 기술적 지표 실시간 계산
/// - 분석 결과 캐싱 및 최적화
/// - 매수/매도 신호 생성
/// - 실시간 알림 시스템
class RealtimeAnalysisEngine {
  static final RealtimeAnalysisEngine _instance = RealtimeAnalysisEngine._internal();
  factory RealtimeAnalysisEngine() => _instance;
  RealtimeAnalysisEngine._internal();

  // 서비스 상태
  bool _isRunning = false;
  Timer? _analysisTimer;
  
  // Repository 인스턴스
  final HistoricalDataRepository _historicalRepo = HistoricalDataRepository();
  final CurrentPriceRepository _currentPriceRepo = CurrentPriceRepository();
  final AnalysisResultsRepository _analysisRepo = AnalysisResultsRepository();
  final SmartLifecycleManager _lifecycleManager = SmartLifecycleManager();

  // 분석 캐시
  final Map<String, Map<String, dynamic>> _analysisCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  
  // 설정
  static const Duration _analysisInterval = Duration(minutes: 1); // 1분마다 분석
  static const Duration _cacheExpiry = Duration(minutes: 5); // 캐시 5분 만료
  static const int _maxCacheSize = 200; // 최대 캐시 항목 수

  // 통계 정보
  int _totalAnalyses = 0;
  int _successfulAnalyses = 0;
  int _failedAnalyses = 0;
  DateTime? _lastAnalysisTime;
  String _lastError = '';

  /// 서비스 시작
  Future<void> start() async {
    if (_isRunning) {
      print('⚠️ 실시간 분석 엔진이 이미 실행 중입니다.');
      return;
    }

    try {
      print('🚀 실시간 분석 엔진 시작...');
      
      // 초기화
      await _initialize();
      
      // 서비스 상태 설정
      _isRunning = true;
      
      // 첫 번째 분석 즉시 실행
      await _performAnalysis();
      
      // 정기 분석 타이머 시작
      _startAnalysisTimer();
      
      print('✅ 실시간 분석 엔진 시작 완료');
      
    } catch (e) {
      print('❌ 실시간 분석 엔진 시작 실패: $e');
      _isRunning = false;
      rethrow;
    }
  }

  /// 서비스 중지
  Future<void> stop() async {
    if (!_isRunning) {
      print('⚠️ 실시간 분석 엔진이 실행 중이 아닙니다.');
      return;
    }

    try {
      print('🛑 실시간 분석 엔진 중지...');
      
      // 타이머 정리
      _analysisTimer?.cancel();
      _analysisTimer = null;
      
      // 캐시 정리
      _clearCache();
      
      // 서비스 상태 설정
      _isRunning = false;
      
      print('✅ 실시간 분석 엔진 중지 완료');
      
    } catch (e) {
      print('❌ 실시간 분석 엔진 중지 실패: $e');
      rethrow;
    }
  }

  /// 서비스 재시작
  Future<void> restart() async {
    print('🔄 실시간 분석 엔진 재시작...');
    await stop();
    await Future.delayed(const Duration(seconds: 2));
    await start();
  }

  /// 서비스 상태 확인
  bool get isRunning => _isRunning;
  
  /// 서비스 통계 정보
  Map<String, dynamic> get statistics => {
    'is_running': _isRunning,
    'total_analyses': _totalAnalyses,
    'successful_analyses': _successfulAnalyses,
    'failed_analyses': _failedAnalyses,
    'success_rate': _totalAnalyses > 0 ? (_successfulAnalyses / _totalAnalyses * 100).toStringAsFixed(2) : '0.00',
    'last_analysis_time': _lastAnalysisTime?.toIso8601String(),
    'last_error': _lastError,
    'cache_size': _analysisCache.length,
  };

  /// 초기화
  Future<void> _initialize() async {
    try {
      print('🔧 실시간 분석 엔진 초기화...');
      
      // 캐시 초기화
      _clearCache();
      
      print('✅ 실시간 분석 엔진 초기화 완료');
      
    } catch (e) {
      print('❌ 실시간 분석 엔진 초기화 실패: $e');
      rethrow;
    }
  }

  /// 분석 타이머 시작
  void _startAnalysisTimer() {
    _analysisTimer?.cancel();
    _analysisTimer = Timer.periodic(_analysisInterval, (timer) async {
      if (_isRunning) {
        await _performAnalysis();
      }
    });
    print('⏰ 분석 타이머 시작 (${_analysisInterval.inMinutes}분 간격)');
  }

  /// 분석 수행
  Future<void> _performAnalysis() async {
    if (!_isRunning) return;

    _totalAnalyses++;
    _lastAnalysisTime = DateTime.now();
    
    try {
      print('📊 실시간 분석 시작 (${_totalAnalyses}번째)...');
      
      // 1. 활성 종목 목록 조회
      final activeStocks = await _getActiveStocks();
      if (activeStocks.isEmpty) {
        print('⚠️ 활성 종목이 없습니다.');
        return;
      }
      
      print('📋 분석 대상 종목: ${activeStocks.length}개');
      
      // 2. 각 종목별 분석 수행
      int analyzedCount = 0;
      final totalCount = activeStocks.length;
      
      for (final stock in activeStocks) {
        final stockCode = stock['stock_code'] as String;
        final stockName = stock['stock_name'] as String;
        
        try {
          // 캐시된 분석 결과 확인
          final cachedResult = _getCachedAnalysis(stockCode);
          if (cachedResult != null) {
            print('📊 $stockCode 캐시된 분석 결과 사용');
            analyzedCount++;
            continue;
          }
          
          // 새로운 분석 수행
          final analysisResult = await _analyzeStock(stockCode, stockName);
          if (analysisResult != null) {
            // 분석 결과 캐싱
            _setCachedAnalysis(stockCode, analysisResult);
            
            // 분석 결과 저장
            await _saveAnalysisResult(stockCode, analysisResult);
            
            analyzedCount++;
            print('✅ $stockCode ($stockName) 분석 완료 ($analyzedCount/$totalCount)');
          }
          
        } catch (e) {
          print('❌ $stockCode ($stockName) 분석 실패: $e');
        }
      }
      
      _successfulAnalyses++;
      print('✅ 실시간 분석 완료: $analyzedCount/$totalCount');
      
      // 3. 캐시 정리
      await _cleanupCache();
      
    } catch (e) {
      _failedAnalyses++;
      _lastError = e.toString();
      print('❌ 실시간 분석 실패: $e');
    }
  }

  /// 활성 종목 목록 조회
  Future<List<Map<String, dynamic>>> _getActiveStocks() async {
    try {
      // 현재가 데이터가 있는 종목들을 활성 종목으로 간주
      final currentPrices = await _currentPriceRepo.getAllCurrentPrices();
      
      return currentPrices.map((price) => {
        'stock_code': price['stock_code'] as String,
        'stock_name': price['stock_name'] as String? ?? 'Unknown',
        'market': price['market'] as String? ?? 'UNKNOWN',
      }).toList();
      
    } catch (e) {
      print('❌ 활성 종목 조회 실패: $e');
      return [];
    }
  }

  /// 개별 종목 분석
  Future<Map<String, dynamic>?> _analyzeStock(String stockCode, String stockName) async {
    try {
      // 1. 차트 데이터 조회 (최신 CHART_MIN_BARS일) - 통일된 방식 사용
      final chartData = await _historicalRepo.getRecentBars(stockCode, limit: ChartConstants.CHART_MIN_BARS);
      if (chartData.length < 20) {
        print('⚠️ $stockCode: 충분한 차트 데이터가 없습니다 (${chartData.length}일)');
        return null;
      }
      
      // 2. 현재가 데이터 조회
      final currentPrice = await _currentPriceRepo.getCurrentPrice(stockCode);
      if (currentPrice == null) {
        print('⚠️ $stockCode: 현재가 데이터가 없습니다');
        return null;
      }
      
      // 3. 동적 지표 계산을 위한 데이터 준비
      final indicatorData = await _prepareIndicatorData(chartData, currentPrice);
      
      // 4. 종합 지표 계산
      final comprehensiveResult = ComprehensiveIndicatorCalculator.calculateComprehensiveScore(
        indicatorData: indicatorData,
        currentTime: _getCurrentTimeString(),
        buyThreshold: 0.6,
        sellThreshold: -0.6,
      );
      
      // 5. 분석 결과 구성
      final analysisResult = {
        'stock_code': stockCode,
        'stock_name': stockName,
        'analysis_time': DateTime.now().millisecondsSinceEpoch,
        'comprehensive_score': comprehensiveResult['comprehensiveScore'] as double? ?? 0.0,
        'trading_decision': comprehensiveResult['tradingDecision'] as String? ?? 'HOLD',
        'signal_strength': comprehensiveResult['signalStrength'] as String? ?? 'WEAK',
        'confidence_score': _calculateConfidenceScore(comprehensiveResult),
        'target_price': _calculateTargetPrice(currentPrice['current_price'] as double, comprehensiveResult),
        'analysis_details': comprehensiveResult,
        'current_price': currentPrice['current_price'] as double,
        'prev_close': currentPrice['prev_close'] as double,
        'change_rate': currentPrice['change_rate'] as double,
      };
      
      return analysisResult;
      
    } catch (e) {
      print('❌ $stockCode 분석 실패: $e');
      return null;
    }
  }

  /// 지표 계산을 위한 데이터 준비
  Future<Map<String, dynamic>> _prepareIndicatorData(List<Map<String, dynamic>> chartData, Map<String, dynamic> currentPrice) async {
    try {
      // OHLCV 데이터 추출
      final closes = chartData.map((d) => d['close'] as double).toList();
      final opens = chartData.map((d) => d['open'] as double).toList();
      final highs = chartData.map((d) => d['high'] as double).toList();
      final lows = chartData.map((d) => d['low'] as double).toList();
      final volumes = chartData.map((d) => d['volume'] as int).toList();
      
      return {
        'closes': closes,
        'opens': opens,
        'highs': highs,
        'lows': lows,
        'volumes': volumes,
        'current_price': currentPrice['current_price'] as double,
        'prev_close': currentPrice['prev_close'] as double,
        'change_rate': currentPrice['change_rate'] as double,
        'volume': currentPrice['volume'] as int,
      };
      
    } catch (e) {
      print('❌ 지표 데이터 준비 실패: $e');
      rethrow;
    }
  }

  /// 신뢰도 점수 계산
  double _calculateConfidenceScore(Map<String, dynamic> comprehensiveResult) {
    try {
      // 각 지표의 신뢰도를 종합하여 최종 신뢰도 계산
      final rsiScore = comprehensiveResult['rsiScore'] as double? ?? 0.0;
      final macdScore = comprehensiveResult['macdScore'] as double? ?? 0.0;
      final bollingerScore = comprehensiveResult['bollingerScore'] as double? ?? 0.0;
      final movingAverageScore = comprehensiveResult['movingAverageScore'] as double? ?? 0.0;
      final vwapScore = comprehensiveResult['vwapScore'] as double? ?? 0.0;
      final adxScore = comprehensiveResult['adxScore'] as double? ?? 0.0;
      final volumeScore = comprehensiveResult['volumeScore'] as double? ?? 0.0;
      
      // 가중 평균으로 신뢰도 계산
      final weights = [0.15, 0.15, 0.15, 0.15, 0.15, 0.10, 0.15]; // 각 지표별 가중치
      final scores = [rsiScore, macdScore, bollingerScore, movingAverageScore, vwapScore, adxScore, volumeScore];
      
      double weightedSum = 0.0;
      double totalWeight = 0.0;
      
      for (int i = 0; i < scores.length; i++) {
        weightedSum += scores[i] * weights[i];
        totalWeight += weights[i];
      }
      
      final confidenceScore = totalWeight > 0 ? weightedSum / totalWeight : 0.0;
      return confidenceScore.clamp(0.0, 1.0); // 0.0 ~ 1.0 범위로 제한
      
    } catch (e) {
      print('❌ 신뢰도 점수 계산 실패: $e');
      return 0.5; // 기본값
    }
  }

  /// 목표가 계산
  double _calculateTargetPrice(double currentPrice, Map<String, dynamic> comprehensiveResult) {
    try {
      final comprehensiveScore = comprehensiveResult['comprehensiveScore'] as double? ?? 0.0;
      final tradingDecision = comprehensiveResult['tradingDecision'] as String? ?? 'HOLD';
      
      // 종합 점수와 매매 결정에 따른 목표가 계산
      if (tradingDecision == 'BUY' && comprehensiveScore > 0.3) {
        // 매수 신호: 현재가 + (점수 * 10%)
        return currentPrice * (1.0 + (comprehensiveScore * 0.1));
      } else if (tradingDecision == 'SELL' && comprehensiveScore < -0.3) {
        // 매도 신호: 현재가 - (점수 * 10%)
        return currentPrice * (1.0 + (comprehensiveScore * 0.1));
      } else {
        // 홀드: 현재가 유지
        return currentPrice;
      }
      
    } catch (e) {
      print('❌ 목표가 계산 실패: $e');
      return currentPrice;
    }
  }

  /// 현재 시간 문자열 반환
  String _getCurrentTimeString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
  }

  /// 캐시된 분석 결과 조회
  Map<String, dynamic>? _getCachedAnalysis(String stockCode) {
    final timestamp = _cacheTimestamps[stockCode];
    if (timestamp == null) return null;
    
    // 만료 체크
    if (DateTime.now().difference(timestamp) > _cacheExpiry) {
      _analysisCache.remove(stockCode);
      _cacheTimestamps.remove(stockCode);
      return null;
    }
    
    return _analysisCache[stockCode];
  }

  /// 분석 결과 캐싱
  void _setCachedAnalysis(String stockCode, Map<String, dynamic> result) {
    _analysisCache[stockCode] = result;
    _cacheTimestamps[stockCode] = DateTime.now();
  }

  /// 분석 결과 저장
  Future<void> _saveAnalysisResult(String stockCode, Map<String, dynamic> result) async {
    try {
      await _analysisRepo.insertAnalysisResult(result);
    } catch (e) {
      print('❌ 분석 결과 저장 실패: $e');
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
        _analysisCache.remove(key);
        _cacheTimestamps.remove(key);
      }
      
      // 캐시 크기 제한
      if (_analysisCache.length > _maxCacheSize) {
        final sortedEntries = _cacheTimestamps.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        
        final removeCount = _analysisCache.length - _maxCacheSize;
        for (int i = 0; i < removeCount; i++) {
          final key = sortedEntries[i].key;
          _analysisCache.remove(key);
          _cacheTimestamps.remove(key);
        }
      }
      
      if (expiredKeys.isNotEmpty || _analysisCache.length > _maxCacheSize) {
        print('🧹 분석 캐시 정리: ${expiredKeys.length}개 만료, ${_analysisCache.length}개 유지');
      }
      
    } catch (e) {
      print('❌ 캐시 정리 실패: $e');
    }
  }

  /// 캐시 정리
  void _clearCache() {
    _analysisCache.clear();
    _cacheTimestamps.clear();
  }

  /// 특정 종목 분석 결과 조회
  Future<Map<String, dynamic>?> getAnalysisResult(String stockCode) async {
    try {
      // 캐시에서 먼저 확인
      final cachedResult = _getCachedAnalysis(stockCode);
      if (cachedResult != null) {
        return cachedResult;
      }
      
      // 데이터베이스에서 조회
      final dbResult = await _analysisRepo.getLatestAnalysisResult(stockCode);
      if (dbResult != null) {
        // 캐시에 저장
        _setCachedAnalysis(stockCode, dbResult);
        return dbResult;
      }
      
      return null;
      
    } catch (e) {
      print('❌ 분석 결과 조회 실패: $e');
      return null;
    }
  }

  /// 서비스 정리
  void dispose() {
    stop();
  }
}
