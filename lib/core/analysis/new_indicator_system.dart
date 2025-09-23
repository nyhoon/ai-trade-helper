import 'comprehensive_indicator_calculator.dart';
import 'volatility_calculator.dart';
import 'trading_execution_criteria.dart';
import 'signal_notification_system.dart';

/// 새로운 지표 시스템 메인 클래스
/// 모든 계산기를 통합하고 실제 매매 신호를 생성
class NewIndicatorSystem {
  static final NewIndicatorSystem _instance = NewIndicatorSystem._internal();
  factory NewIndicatorSystem() => _instance;
  NewIndicatorSystem._internal();

  final SignalNotificationSystem _notificationSystem = SignalNotificationSystem();
  
  bool _isInitialized = false;
  bool _isEnabled = true;
  
  /// 시스템 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // 알림 시스템 초기화
      await _notificationSystem.initialize();
      
      _isInitialized = true;
      print('✅ 새로운 지표 시스템 초기화 완료');
      
    } catch (e) {
      print('⚠️ 새로운 지표 시스템 초기화 실패: $e');
    }
  }

  /// 시스템 활성화/비활성화
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    print('🎯 새로운 지표 시스템 ${enabled ? "활성화" : "비활성화"}');
  }

  /// 시스템 상태 확인
  bool get isEnabled => _isEnabled;
  bool get isInitialized => _isInitialized;

  /// 종합 매매 신호 생성
  /// 
  /// [stockCode] 종목 코드
  /// [stockName] 종목명
  /// [marketData] 시장 데이터 (가격, 거래량, 지표값들)
  /// [currentTime] 현재 시간 (HH:mm 형식)
  /// 
  /// Returns: 종합 매매 신호 결과
  Future<Map<String, dynamic>> generateTradingSignal({
    required String stockCode,
    required String stockName,
    required Map<String, dynamic> marketData,
    required String currentTime,
  }) async {
    if (!_isEnabled || !_isInitialized) {
      print('⚠️ 새로운 지표 시스템이 비활성화되어 있습니다.');
      return {
        'error': '시스템이 비활성화되어 있습니다.',
        'timestamp': DateTime.now().toIso8601String(),
      };
    }

    try {
      print('🎯 종합 매매 신호 생성 시작');
      print('📊 종목: $stockName ($stockCode)');
      print('📊 시간: $currentTime');
      
      // 1. 변동성 계산
      final Map<String, dynamic> volatilityData = _calculateVolatility(marketData);
      
      // 2. 지표 데이터 준비
      final Map<String, dynamic> indicatorData = _prepareIndicatorData(marketData, volatilityData);
      
      // 3. 종합 지표 점수 계산 (사용자 지정 임계값 사용)
      final Map<String, dynamic> comprehensiveResult = ComprehensiveIndicatorCalculator.calculateComprehensiveScore(
        indicatorData: indicatorData,
        currentTime: currentTime,
        buyThreshold: marketData['buyThreshold'],
        sellThreshold: marketData['sellThreshold'],
      );
      
      // 4. 매매 실행 기준 판단 (사용자 지정 임계값 사용)
      final Map<String, dynamic> executionResult = TradingExecutionCriteria.determineTradingExecution(
        comprehensiveScore: comprehensiveResult['comprehensiveScore'] ?? 0.0,
        stockCode: stockCode,
        stockName: stockName,
        currentPrice: marketData['currentPrice'] ?? 0.0,
        currentTime: currentTime,
        buyThreshold: marketData['buyThreshold'],
        sellThreshold: marketData['sellThreshold'],
      );
      
      // 5. 알림 전송 (필요한 경우)
      await _sendNotificationIfNeeded(
        stockCode: stockCode,
        stockName: stockName,
        marketData: marketData,
        comprehensiveResult: comprehensiveResult,
        executionResult: executionResult,
        currentTime: currentTime,
      );
      
      // 6. 최종 결과 생성
      final Map<String, dynamic> finalResult = {
        'stockInfo': {
          'code': stockCode,
          'name': stockName,
          'currentPrice': marketData['currentPrice'] ?? 0.0,
          'currentTime': currentTime,
        },
        'comprehensiveAnalysis': comprehensiveResult,
        'executionAnalysis': executionResult,
        'volatilityAnalysis': volatilityData,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      print('✅ 종합 매매 신호 생성 완료');
      print('📊 종합 점수: ${comprehensiveResult['comprehensiveScore']?.toStringAsFixed(3)}');
      print('📊 매매 결정: ${executionResult['executionDecision']}');
      
      return finalResult;
      
    } catch (e) {
      print('⚠️ 종합 매매 신호 생성 실패: $e');
      return {
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  /// 변동성 계산
  Map<String, dynamic> _calculateVolatility(Map<String, dynamic> marketData) {
    try {
      final List<double> highs = List<double>.from(marketData['highs'] ?? []);
      final List<double> lows = List<double>.from(marketData['lows'] ?? []);
      final List<double> closes = List<double>.from(marketData['closes'] ?? []);
      
      if (highs.isEmpty || lows.isEmpty || closes.isEmpty) {
        return {
          'currentATR': 0.0,
          'averageATR': 0.0,
          'volatilityAnalysis': {
            'level': '데이터 부족',
            'ratio': 0.0,
            'description': '변동성 계산을 위한 데이터가 부족합니다.',
            'signal': '중립',
          },
        };
      }
      
      final double currentATR = VolatilityCalculator.calculateATR(
        highs: highs,
        lows: lows,
        closes: closes,
      );
      
      final double averageATR = VolatilityCalculator.calculateAverageATR(
        highs: highs,
        lows: lows,
        closes: closes,
      );
      
      final Map<String, dynamic> volatilityAnalysis = VolatilityCalculator.analyzeVolatilityLevel(
        currentATR: currentATR,
        averageATR: averageATR,
      );
      
      return {
        'currentATR': currentATR,
        'averageATR': averageATR,
        'volatilityAnalysis': volatilityAnalysis,
      };
      
    } catch (e) {
      print('⚠️ 변동성 계산 실패: $e');
      return {
        'currentATR': 0.0,
        'averageATR': 0.0,
        'volatilityAnalysis': {
          'level': '계산 실패',
          'ratio': 0.0,
          'description': '변동성 계산 중 오류가 발생했습니다.',
          'signal': '중립',
          'error': e.toString(),
        },
      };
    }
  }

  /// 지표 데이터 준비
  Map<String, dynamic> _prepareIndicatorData(
    Map<String, dynamic> marketData,
    Map<String, dynamic> volatilityData,
  ) {
    return {
      // 기본 가격 데이터
      'currentPrice': marketData['currentPrice'] ?? 0.0,
      'previousPrice': marketData['previousPrice'] ?? 0.0,
      
      // 거래량 데이터
      'currentVolume': marketData['currentVolume'] ?? 0,
      'averageVolume': marketData['averageVolume'] ?? 0,
      
      // 변동성 데이터
      'currentATR': volatilityData['currentATR'] ?? 0.0,
      'averageATR': volatilityData['averageATR'] ?? 0.0,
      
      // 기술적 지표 데이터
      'rsiValue': marketData['rsiValue'] ?? 50.0,
      'macdValue': marketData['macdValue'] ?? 0.0,
      'signalValue': marketData['signalValue'] ?? 0.0,
      'adxValue': marketData['adxValue'] ?? 0.0,
      
      // 볼린저 밴드 데이터
      'upperBand': marketData['upperBand'] ?? 0.0,
      'middleBand': marketData['middleBand'] ?? 0.0,
      'lowerBand': marketData['lowerBand'] ?? 0.0,
      
      // 이동평균선 데이터
      'ma5': marketData['ma5'] ?? 0.0,
      'ma20': marketData['ma20'] ?? 0.0,
      'ma60': marketData['ma60'] ?? 0.0,
      
      // VWAP 데이터
      'vwapValue': marketData['vwapValue'] ?? 0.0,
    };
  }

  /// 알림 전송 (필요한 경우)
  Future<void> _sendNotificationIfNeeded({
    required String stockCode,
    required String stockName,
    required Map<String, dynamic> marketData,
    required Map<String, dynamic> comprehensiveResult,
    required Map<String, dynamic> executionResult,
    required String currentTime,
  }) async {
    try {
      final String executionDecision = executionResult['executionDecision'] ?? '';
      final String signalStrength = executionResult['signalStrength'] ?? '';
      final double comprehensiveScore = comprehensiveResult['comprehensiveScore'] ?? 0.0;
      final double currentPrice = marketData['currentPrice'] ?? 0.0;
      
      // 관망이 아닌 경우에만 알림 전송
      if (!executionDecision.contains('관망') && !executionDecision.contains('판단 실패')) {
        // 긴급 신호인 경우 우선순위 높은 알림
        if (signalStrength.contains('강한')) {
          await _notificationSystem.sendUrgentSignalNotification(
            stockCode: stockCode,
            stockName: stockName,
            currentPrice: currentPrice,
            executionDecision: executionDecision,
            signalStrength: signalStrength,
            comprehensiveScore: comprehensiveScore,
            currentTime: currentTime,
          );
        } else {
          // 일반 신호 알림
          await _notificationSystem.sendSignalNotification(
            stockCode: stockCode,
            stockName: stockName,
            currentPrice: currentPrice,
            executionDecision: executionDecision,
            signalStrength: signalStrength,
            comprehensiveScore: comprehensiveScore,
            currentTime: currentTime,
          );
        }
      }
      
    } catch (e) {
      print('⚠️ 알림 전송 실패: $e');
    }
  }

  /// 배치 처리 (여러 종목 동시 분석)
  Future<List<Map<String, dynamic>>> analyzeMultipleStocks({
    required List<Map<String, dynamic>> stockDataList,
    required String currentTime,
  }) async {
    if (!_isEnabled || !_isInitialized) {
      print('⚠️ 새로운 지표 시스템이 비활성화되어 있습니다.');
      return [];
    }

    try {
      print('🎯 다중 종목 분석 시작 (${stockDataList.length}개 종목)');
      
      final List<Map<String, dynamic>> results = [];
      
      for (final stockData in stockDataList) {
        try {
          final result = await generateTradingSignal(
            stockCode: stockData['stockCode'] ?? '',
            stockName: stockData['stockName'] ?? '',
            marketData: stockData['marketData'] ?? {},
            currentTime: currentTime,
          );
          
          results.add(result);
          
        } catch (e) {
          print('⚠️ 종목 분석 실패: ${stockData['stockCode']} - $e');
          results.add({
            'error': '종목 분석 실패: $e',
            'stockCode': stockData['stockCode'] ?? '',
            'timestamp': DateTime.now().toIso8601String(),
          });
        }
      }
      
      print('✅ 다중 종목 분석 완료 (${results.length}개 결과)');
      return results;
      
    } catch (e) {
      print('⚠️ 다중 종목 분석 실패: $e');
      return [];
    }
  }

  /// 시스템 통계 가져오기
  Map<String, dynamic> getSystemStats() {
    return {
      'isEnabled': _isEnabled,
      'isInitialized': _isInitialized,
      'notificationSettings': _notificationSystem.getNotificationSettings(),
      'notificationStats': _notificationSystem.getNotificationStats(),
    };
  }

  /// 알림 시스템 접근
  SignalNotificationSystem get notificationSystem => _notificationSystem;

  /// 시스템 리소스 해제
  void dispose() {
    _notificationSystem.dispose();
    print('✅ 새로운 지표 시스템 리소스 해제 완료');
  }
}
