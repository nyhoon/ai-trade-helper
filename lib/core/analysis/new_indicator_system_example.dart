import 'new_indicator_system.dart';

/// 새로운 지표 시스템 사용 예시
/// 실제 사용 방법과 테스트 코드를 포함
class NewIndicatorSystemExample {
  
  /// 시스템 초기화 및 기본 사용 예시
  static Future<void> basicUsageExample() async {
    print('🚀 새로운 지표 시스템 기본 사용 예시 시작');
    
    // 1. 시스템 초기화
    final newIndicatorSystem = NewIndicatorSystem();
    await newIndicatorSystem.initialize();
    
    // 2. 샘플 시장 데이터 생성
    final Map<String, dynamic> sampleMarketData = _createSampleMarketData();
    
    // 3. 현재 시간 생성
    final String currentTime = _getCurrentTime();
    
    // 4. 종합 매매 신호 생성
    final Map<String, dynamic> result = await newIndicatorSystem.generateTradingSignal(
      stockCode: '005930', // 삼성전자
      stockName: '삼성전자',
      marketData: sampleMarketData,
      currentTime: currentTime,
    );
    
    // 5. 결과 출력
    _printAnalysisResult(result);
    
    print('✅ 기본 사용 예시 완료');
  }

  /// 다중 종목 분석 예시
  static Future<void> multipleStocksExample() async {
    print('🚀 다중 종목 분석 예시 시작');
    
    // 1. 시스템 초기화
    final newIndicatorSystem = NewIndicatorSystem();
    await newIndicatorSystem.initialize();
    
    // 2. 다중 종목 데이터 생성
    final List<Map<String, dynamic>> stockDataList = [
      {
        'stockCode': '005930',
        'stockName': '삼성전자',
        'marketData': _createSampleMarketData(),
      },
      {
        'stockCode': '000660',
        'stockName': 'SK하이닉스',
        'marketData': _createSampleMarketData(price: 150000),
      },
      {
        'stockCode': '035420',
        'stockName': 'NAVER',
        'marketData': _createSampleMarketData(price: 200000),
      },
    ];
    
    // 3. 현재 시간 생성
    final String currentTime = _getCurrentTime();
    
    // 4. 다중 종목 분석
    final List<Map<String, dynamic>> results = await newIndicatorSystem.analyzeMultipleStocks(
      stockDataList: stockDataList,
      currentTime: currentTime,
    );
    
    // 5. 결과 출력
    for (int i = 0; i < results.length; i++) {
      print('\n📊 종목 ${i + 1} 분석 결과:');
      _printAnalysisResult(results[i]);
    }
    
    print('✅ 다중 종목 분석 예시 완료');
  }

  /// 알림 시스템 테스트 예시
  static Future<void> notificationTestExample() async {
    print('🚀 알림 시스템 테스트 예시 시작');
    
    // 1. 시스템 초기화
    final newIndicatorSystem = NewIndicatorSystem();
    await newIndicatorSystem.initialize();
    
    // 2. 알림 시스템 접근
    final notificationSystem = newIndicatorSystem.notificationSystem;
    
    // 3. 알림 권한 요청
    final bool hasPermission = await notificationSystem.requestPermissions();
    print('📱 알림 권한: ${hasPermission ? "허용" : "거부"}');
    
    // 4. 테스트 알림 전송
    await notificationSystem.sendSignalNotification(
      stockCode: '005930',
      stockName: '삼성전자',
      currentPrice: 70000.0,
      executionDecision: '즉시 매수',
      signalStrength: '강한 신호',
      comprehensiveScore: 0.75,
      currentTime: _getCurrentTime(),
    );
    
    // 5. 긴급 알림 테스트
    await notificationSystem.sendUrgentSignalNotification(
      stockCode: '000660',
      stockName: 'SK하이닉스',
      currentPrice: 150000.0,
      executionDecision: '즉시 매도',
      signalStrength: '매우 강한 신호',
      comprehensiveScore: -0.85,
      currentTime: _getCurrentTime(),
    );
    
    print('✅ 알림 시스템 테스트 예시 완료');
  }

  /// 시스템 통계 확인 예시
  static Future<void> systemStatsExample() async {
    print('🚀 시스템 통계 확인 예시 시작');
    
    // 1. 시스템 초기화
    final newIndicatorSystem = NewIndicatorSystem();
    await newIndicatorSystem.initialize();
    
    // 2. 시스템 통계 가져오기
    final Map<String, dynamic> stats = newIndicatorSystem.getSystemStats();
    
    // 3. 통계 출력
    print('📊 시스템 통계:');
    print('  - 시스템 활성화: ${stats['isEnabled']}');
    print('  - 시스템 초기화: ${stats['isInitialized']}');
    print('  - 알림 설정: ${stats['notificationSettings']}');
    print('  - 알림 통계: ${stats['notificationStats']}');
    
    print('✅ 시스템 통계 확인 예시 완료');
  }

  /// 샘플 시장 데이터 생성
  static Map<String, dynamic> _createSampleMarketData({double price = 70000.0}) {
    return {
      // 기본 가격 데이터
      'currentPrice': price,
      'previousPrice': price * 0.98, // 2% 상승
      
      // 거래량 데이터
      'currentVolume': 1000000,
      'averageVolume': 800000,
      
      // 기술적 지표 데이터
      'rsiValue': 35.0, // 과매도 구간
      'macdValue': 0.5,
      'signalValue': 0.3,
      'adxValue': 28.0, // 강한 추세
      
      // 볼린저 밴드 데이터
      'upperBand': price * 1.05,
      'middleBand': price,
      'lowerBand': price * 0.95,
      
      // 이동평균선 데이터
      'ma5': price * 1.02,
      'ma20': price * 1.01,
      'ma60': price * 0.99,
      
      // VWAP 데이터
      'vwapValue': price * 1.01,
      
      // 과거 가격 데이터 (변동성 계산용)
      'highs': List.generate(30, (i) => price * (1.0 + (i % 3) * 0.01)),
      'lows': List.generate(30, (i) => price * (0.99 - (i % 3) * 0.005)),
      'closes': List.generate(30, (i) => price * (1.0 + (i % 5 - 2) * 0.005)),
    };
  }

  /// 현재 시간 생성 (HH:mm 형식)
  static String _getCurrentTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  /// 분석 결과 출력
  static void _printAnalysisResult(Map<String, dynamic> result) {
    if (result.containsKey('error')) {
      print('❌ 오류: ${result['error']}');
      return;
    }
    
    final stockInfo = result['stockInfo'] ?? {};
    final comprehensiveAnalysis = result['comprehensiveAnalysis'] ?? {};
    final executionAnalysis = result['executionAnalysis'] ?? {};
    final volatilityAnalysis = result['volatilityAnalysis'] ?? {};
    
    print('📊 종목 정보:');
    print('  - 종목코드: ${stockInfo['code']}');
    print('  - 종목명: ${stockInfo['name']}');
    print('  - 현재가: ${stockInfo['currentPrice']?.toStringAsFixed(0)}원');
    print('  - 시간: ${stockInfo['currentTime']}');
    
    print('\n📈 종합 분석:');
    print('  - 종합 점수: ${comprehensiveAnalysis['comprehensiveScore']?.toStringAsFixed(3)}');
    print('  - 매매 결정: ${executionAnalysis['executionDecision']}');
    print('  - 신호 강도: ${executionAnalysis['signalStrength']}');
    print('  - 우선순위: ${executionAnalysis['priority']}');
    print('  - 신뢰도: ${(executionAnalysis['confidence'] * 100)?.toStringAsFixed(1)}%');
    print('  - 위험도: ${executionAnalysis['riskLevel']}');
    
    print('\n📊 개별 지표 점수:');
    final individualScores = comprehensiveAnalysis['individualScores'] ?? {};
    individualScores.forEach((indicator, score) {
      print('  - $indicator: ${score.toStringAsFixed(3)}');
    });
    
    print('\n📊 변동성 분석:');
    final volatilityData = volatilityAnalysis['volatilityAnalysis'] ?? {};
    print('  - 변동성 수준: ${volatilityData['level']}');
    print('  - 변동성 비율: ${volatilityData['ratio']?.toStringAsFixed(2)}');
    print('  - 설명: ${volatilityData['description']}');
    print('  - 신호: ${volatilityData['signal']}');
    
    print('\n📊 상위 기여 지표:');
    final topContributors = comprehensiveAnalysis['topContributors'] ?? [];
    for (int i = 0; i < topContributors.length; i++) {
      final contributor = topContributors[i];
      print('  ${i + 1}. ${contributor['indicator']}: ${contributor['contribution']?.toStringAsFixed(3)} (가중치: ${contributor['weight']?.toStringAsFixed(2)})');
    }
  }

  /// 전체 시스템 테스트
  static Future<void> runFullSystemTest() async {
    print('🚀 새로운 지표 시스템 전체 테스트 시작');
    print('=' * 50);
    
    try {
      // 1. 기본 사용 예시
      await basicUsageExample();
      print('\n' + '=' * 50);
      
      // 2. 다중 종목 분석 예시
      await multipleStocksExample();
      print('\n' + '=' * 50);
      
      // 3. 알림 시스템 테스트 예시
      await notificationTestExample();
      print('\n' + '=' * 50);
      
      // 4. 시스템 통계 확인 예시
      await systemStatsExample();
      print('\n' + '=' * 50);
      
      print('✅ 새로운 지표 시스템 전체 테스트 완료');
      
    } catch (e) {
      print('❌ 전체 테스트 실패: $e');
    }
  }
}
