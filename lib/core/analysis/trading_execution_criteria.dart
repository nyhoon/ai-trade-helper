/// 매매 실행 기준 판단기
/// 종합 점수를 기반으로 매매 실행 여부를 판단하고, 신호 알림을 생성
/// 사용자가 지정한 투자 스타일별 임계값을 SQL에서 불러와서 사용
class TradingExecutionCriteria {
  
  /// 기본 매매 실행 기준 정의 (사용자 설정이 없을 때 사용)
  static const Map<String, double> _defaultExecutionThresholds = {
    'immediateBuy': 0.0,    // 즉시 매수 기준 (사용자 설정값 사용)
    'buyInterest': 0.0,     // 매수 관심 기준 (사용자 설정값 사용)
    'neutral': 0.0,         // 중립 기준 (사용자 설정값 사용)
    'sellInterest': 0.0,    // 매도 관심 기준 (사용자 설정값 사용)
    'immediateSell': 0.0,   // 즉시 매도 기준 (사용자 설정값 사용)
  };

  /// 매매 실행 기준 판단
  /// 
  /// [comprehensiveScore] 종합 지표 점수
  /// [stockCode] 종목 코드
  /// [stockName] 종목명
  /// [currentPrice] 현재가
  /// [currentTime] 현재 시간
  /// [buyThreshold] 사용자 지정 매수 임계값 (SQL에서 불러온 값)
  /// [sellThreshold] 사용자 지정 매도 임계값 (SQL에서 불러온 값)
  /// 
  /// Returns: 매매 실행 판단 결과
  static Map<String, dynamic> determineTradingExecution({
    required double comprehensiveScore,
    required String stockCode,
    required String stockName,
    required double currentPrice,
    required String currentTime,
    double? buyThreshold,
    double? sellThreshold,
  }) {
    try {
      print('🎯 매매 실행 기준 판단 시작');
      print('📊 종합 점수: ${comprehensiveScore.toStringAsFixed(3)}');
      print('📊 종목: $stockName ($stockCode)');
      print('📊 현재가: ${currentPrice.toStringAsFixed(0)}원');
      
      // 1. 매매 실행 여부 판단 (사용자 지정 임계값 사용)
      final String executionDecision = _getExecutionDecision(
        comprehensiveScore, 
        buyThreshold, 
        sellThreshold
      );
      
      // 2. 신호 강도 분석
      final String signalStrength = _analyzeSignalStrength(comprehensiveScore);
      
      // 3. 실행 우선순위 설정
      final int priority = _calculatePriority(comprehensiveScore);
      
      // 4. 신뢰도 계산
      final double confidence = _calculateConfidence(comprehensiveScore);
      
      // 5. 위험도 평가
      final String riskLevel = _assessRiskLevel(comprehensiveScore);
      
      // 6. 상세 분석 생성
      final Map<String, dynamic> detailedAnalysis = _generateDetailedAnalysis(
        comprehensiveScore: comprehensiveScore,
        executionDecision: executionDecision,
        signalStrength: signalStrength,
        priority: priority,
        confidence: confidence,
        riskLevel: riskLevel,
      );
      
      // 7. 알림 메시지 생성
      final String notificationMessage = _generateNotificationMessage(
        stockCode: stockCode,
        stockName: stockName,
        currentPrice: currentPrice,
        executionDecision: executionDecision,
        signalStrength: signalStrength,
        comprehensiveScore: comprehensiveScore,
        currentTime: currentTime,
      );
      
      final Map<String, dynamic> result = {
        'executionDecision': executionDecision,
        'signalStrength': signalStrength,
        'priority': priority,
        'confidence': confidence,
        'riskLevel': riskLevel,
        'comprehensiveScore': comprehensiveScore,
        'detailedAnalysis': detailedAnalysis,
        'notificationMessage': notificationMessage,
        'timestamp': DateTime.now().toIso8601String(),
        'stockInfo': {
          'code': stockCode,
          'name': stockName,
          'currentPrice': currentPrice,
          'currentTime': currentTime,
        },
      };
      
      print('✅ 매매 실행 기준 판단 완료');
      print('📊 실행 결정: $executionDecision');
      print('📊 신호 강도: $signalStrength');
      print('📊 우선순위: $priority');
      print('📊 신뢰도: ${(confidence * 100).toStringAsFixed(1)}%');
      print('📊 위험도: $riskLevel');
      
      return result;
      
    } catch (e) {
      print('⚠️ 매매 실행 기준 판단 실패: $e');
      return {
        'executionDecision': '판단 실패',
        'signalStrength': '알 수 없음',
        'priority': 0,
        'confidence': 0.0,
        'riskLevel': '알 수 없음',
        'comprehensiveScore': comprehensiveScore,
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  /// 매매 실행 결정 (사용자 지정 임계값 사용)
  static String _getExecutionDecision(
    double comprehensiveScore, 
    double? buyThreshold, 
    double? sellThreshold
  ) {
    // 사용자 지정 임계값만 사용 (기본값 없이)
    if (buyThreshold == null || sellThreshold == null) {
      return '관망'; // 임계값이 설정되지 않으면 관망
    }
    
    final double immediateBuyThreshold = buyThreshold;
    final double buyInterestThreshold = buyThreshold * 0.67;
    final double immediateSellThreshold = sellThreshold;
    final double sellInterestThreshold = sellThreshold * 0.67;
    
    print('📊 매매 실행 기준 임계값:');
    print('  - 즉시 매수: ${immediateBuyThreshold.toStringAsFixed(2)}');
    print('  - 매수 관심: ${buyInterestThreshold.toStringAsFixed(2)}');
    print('  - 즉시 매도: ${immediateSellThreshold.toStringAsFixed(2)}');
    print('  - 매도 관심: ${sellInterestThreshold.toStringAsFixed(2)}');
    
    if (comprehensiveScore >= immediateBuyThreshold) {
      return '즉시 매수';
    } else if (comprehensiveScore >= buyInterestThreshold) {
      return '관심 지켜보기 (매수)';
    } else if (comprehensiveScore <= immediateSellThreshold) {
      return '즉시 매도';
    } else if (comprehensiveScore <= sellInterestThreshold) {
      return '관심 지켜보기 (매도)';
    } else {
      return '관망';
    }
  }

  /// 신호 강도 분석
  static String _analyzeSignalStrength(double comprehensiveScore) {
    final absScore = comprehensiveScore.abs();
    
    if (absScore >= 0.8) {
      return '매우 강한 신호';
    } else if (absScore >= 0.6) {
      return '강한 신호';
    } else if (absScore >= 0.4) {
      return '보통 신호';
    } else if (absScore >= 0.2) {
      return '약한 신호';
    } else {
      return '매우 약한 신호';
    }
  }

  /// 우선순위 계산
  static int _calculatePriority(double comprehensiveScore) {
    final absScore = comprehensiveScore.abs();
    
    if (absScore >= 0.8) {
      return 1; // 최고 우선순위
    } else if (absScore >= 0.6) {
      return 2; // 높은 우선순위
    } else if (absScore >= 0.4) {
      return 3; // 보통 우선순위
    } else if (absScore >= 0.2) {
      return 4; // 낮은 우선순위
    } else {
      return 5; // 최저 우선순위
    }
  }

  /// 신뢰도 계산
  static double _calculateConfidence(double comprehensiveScore) {
    final absScore = comprehensiveScore.abs();
    
    if (absScore >= 0.8) {
      return 0.95; // 95% 신뢰도
    } else if (absScore >= 0.6) {
      return 0.85; // 85% 신뢰도
    } else if (absScore >= 0.4) {
      return 0.70; // 70% 신뢰도
    } else if (absScore >= 0.2) {
      return 0.50; // 50% 신뢰도
    } else {
      return 0.30; // 30% 신뢰도
    }
  }

  /// 위험도 평가
  static String _assessRiskLevel(double comprehensiveScore) {
    final absScore = comprehensiveScore.abs();
    
    if (absScore >= 0.8) {
      return '낮음 (강한 신호)';
    } else if (absScore >= 0.6) {
      return '보통 (확실한 신호)';
    } else if (absScore >= 0.4) {
      return '보통 (약한 신호)';
    } else if (absScore >= 0.2) {
      return '높음 (불확실한 신호)';
    } else {
      return '매우 높음 (신호 없음)';
    }
  }

  /// 상세 분석 생성
  static Map<String, dynamic> _generateDetailedAnalysis({
    required double comprehensiveScore,
    required String executionDecision,
    required String signalStrength,
    required int priority,
    required double confidence,
    required String riskLevel,
  }) {
    return {
      'scoreAnalysis': {
        'range': _getScoreRange(comprehensiveScore),
        'trend': _getScoreTrend(comprehensiveScore),
        'momentum': _getScoreMomentum(comprehensiveScore),
      },
      'executionAnalysis': {
        'decision': executionDecision,
        'strength': signalStrength,
        'priority': priority,
        'confidence': confidence,
        'riskLevel': riskLevel,
      },
      'marketAnalysis': {
        'condition': _getMarketCondition(comprehensiveScore),
        'volatility': _getMarketVolatility(comprehensiveScore),
        'trend': _getMarketTrend(comprehensiveScore),
      },
      'recommendation': {
        'action': _getRecommendedAction(comprehensiveScore),
        'timing': _getRecommendedTiming(comprehensiveScore),
        'caution': _getCautionPoints(comprehensiveScore),
      },
    };
  }

  /// 점수 범위 분석
  static String _getScoreRange(double score) {
    if (score >= 0.8) return '매우 강한 매수 구간';
    if (score >= 0.6) return '강한 매수 구간';
    if (score >= 0.4) return '약한 매수 구간';
    if (score >= 0.2) return '매우 약한 매수 구간';
    if (score >= -0.2) return '중립 구간';
    if (score >= -0.4) return '매우 약한 매도 구간';
    if (score >= -0.6) return '약한 매도 구간';
    if (score >= -0.8) return '강한 매도 구간';
    return '매우 강한 매도 구간';
  }

  /// 점수 트렌드 분석
  static String _getScoreTrend(double score) {
    if (score >= 0.6) return '강한 상승 트렌드';
    if (score >= 0.2) return '상승 트렌드';
    if (score >= -0.2) return '횡보 트렌드';
    if (score >= -0.6) return '하락 트렌드';
    return '강한 하락 트렌드';
  }

  /// 점수 모멘텀 분석
  static String _getScoreMomentum(double score) {
    final absScore = score.abs();
    if (absScore >= 0.8) return '매우 강한 모멘텀';
    if (absScore >= 0.6) return '강한 모멘텀';
    if (absScore >= 0.4) return '보통 모멘텀';
    if (absScore >= 0.2) return '약한 모멘텀';
    return '모멘텀 없음';
  }

  /// 시장 상황 분석
  static String _getMarketCondition(double score) {
    final absScore = score.abs();
    if (absScore >= 0.8) return '명확한 방향성';
    if (absScore >= 0.6) return '방향성 있음';
    if (absScore >= 0.4) return '약한 방향성';
    if (absScore >= 0.2) return '불확실한 방향성';
    return '방향성 없음';
  }

  /// 시장 변동성 분석
  static String _getMarketVolatility(double score) {
    final absScore = score.abs();
    if (absScore >= 0.8) return '낮은 변동성 (트렌드)';
    if (absScore >= 0.6) return '보통 변동성';
    if (absScore >= 0.4) return '보통 변동성';
    if (absScore >= 0.2) return '높은 변동성 (박스권)';
    return '매우 높은 변동성 (박스권)';
  }

  /// 시장 트렌드 분석
  static String _getMarketTrend(double score) {
    if (score >= 0.6) return '강한 상승 트렌드';
    if (score >= 0.2) return '상승 트렌드';
    if (score >= -0.2) return '횡보 시장';
    if (score >= -0.6) return '하락 트렌드';
    return '강한 하락 트렌드';
  }

  /// 추천 액션
  static String _getRecommendedAction(double score) {
    if (score >= 0.6) return '즉시 매수 실행';
    if (score >= 0.4) return '매수 관심, 추가 신호 대기';
    if (score <= -0.6) return '즉시 매도 실행';
    if (score <= -0.4) return '매도 관심, 추가 신호 대기';
    return '관망, 명확한 신호 대기';
  }

  /// 추천 타이밍
  static String _getRecommendedTiming(double score) {
    final absScore = score.abs();
    if (absScore >= 0.8) return '즉시 실행';
    if (absScore >= 0.6) return '단기 내 실행';
    if (absScore >= 0.4) return '중기 내 실행';
    if (absScore >= 0.2) return '장기 내 실행';
    return '실행 권장하지 않음';
  }

  /// 주의사항
  static String _getCautionPoints(double score) {
    final absScore = score.abs();
    if (absScore >= 0.8) return '강한 신호이므로 신중하게 접근';
    if (absScore >= 0.6) return '확실한 신호이지만 리스크 관리 필요';
    if (absScore >= 0.4) return '약한 신호이므로 추가 확인 필요';
    if (absScore >= 0.2) return '불확실한 신호이므로 관망 권장';
    return '신호가 없으므로 거래 자제';
  }

  /// 알림 메시지 생성
  static String _generateNotificationMessage({
    required String stockCode,
    required String stockName,
    required double currentPrice,
    required String executionDecision,
    required String signalStrength,
    required double comprehensiveScore,
    required String currentTime,
  }) {
    final String action = executionDecision.contains('매수') ? '매수' : 
                         executionDecision.contains('매도') ? '매도' : '관망';
    
    final String urgency = signalStrength.contains('강한') ? '긴급' : 
                          signalStrength.contains('보통') ? '일반' : '참고';
    
    return '''
🚨 $urgency 알림: $stockName ($stockCode)

📊 현재가: ${currentPrice.toStringAsFixed(0)}원
📈 종합 점수: ${comprehensiveScore.toStringAsFixed(3)}
🎯 매매 결정: $executionDecision
⚡ 신호 강도: $signalStrength
⏰ 시간: $currentTime

$action 신호가 감지되었습니다. 
상세 분석을 확인하시고 투자 결정을 내려주세요.
    '''.trim();
  }
}
