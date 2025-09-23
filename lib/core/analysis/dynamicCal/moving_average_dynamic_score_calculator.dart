import 'dart:math';

/// 이동평균선 동적 점수 계산기
/// 시장환경(ADX), 배열상태, 거래량 동반 여부, 시간대별 가중치 등을 포함
class MovingAverageDynamicScoreCalculator {
  
  /// 시간대별 가중치 정의
  static const Map<String, double> _timeWeights = {
    '22:30-23:30': 1.4, // 나스닥 시작
    '23:30-05:00': 1.2, // 나스닥 본격
    '05:00-06:00': 1.5, // 나스닥 마감
    '09:00-10:00': 1.2, // 코스피 시작
    '10:00-14:00': 1.0, // 코스피 중반
    '14:00-15:30': 1.3, // 코스피 마감
    'default': 0.8,     // 기타 시간
  };

  /// 이동평균선 동적 점수 계산
  /// 
  /// [ma5] 5일 이동평균
  /// [ma20] 20일 이동평균
  /// [ma60] 60일 이동평균
  /// [adxValue] ADX 값 (시장환경 판단)
  /// [currentVolume] 현재 거래량
  /// [averageVolume] 평균 거래량
  /// [currentTime] 현재 시간 (HH:mm 형식)
  /// 
  /// Returns: -1.0 ~ +1.0 범위의 점수
  static double calculateMovingAverageScore({
    required double ma5,
    required double ma20,
    required double ma60,
    required double adxValue,
    required int currentVolume,
    required int averageVolume,
    required String currentTime,
  }) {
    try {
      // 1. 시장환경 판단 (ADX 기반)
      final bool isTrendMarket = _isTrendMarket(adxValue);
      
      // 2. 배열 상태 판단
      final String arrayStatus = _analyzeArrayStatus(ma5, ma20, ma60);
      
      // 3. 기본 점수 계산
      final double baseScore = _calculateBaseScore(arrayStatus);
      
      // 4. 거래량 가중치 계산
      final double volumeWeight = _calculateVolumeWeight(currentVolume, averageVolume);
      
      // 5. 시간대별 보정치 적용
      final double timeBias = _getTimeBias(currentTime);
      
      // 6. 최종 점수 계산
      // 가중치들을 곱해서 점수 범위를 -1.0~1.0으로 유지
      final double trendMultiplier = isTrendMarket ? 1.4 : 1.0;
      final double finalScore = (baseScore * trendMultiplier) + volumeWeight + timeBias;
      
      print('📊 이동평균선 동적 점수 계산 결과:');
      print('  - MA5: ${ma5.toStringAsFixed(0)}원');
      print('  - MA20: ${ma20.toStringAsFixed(0)}원');
      print('  - MA60: ${ma60.toStringAsFixed(0)}원');
      print('  - ADX: ${adxValue.toStringAsFixed(1)}');
      print('  - 시장환경: ${isTrendMarket ? "트렌드" : "박스권"}');
      print('  - 배열상태: $arrayStatus');
      print('  - 기본점수: ${baseScore.toStringAsFixed(2)}');
      print('  - 거래량가중치: ${volumeWeight.toStringAsFixed(2)}');
      print('  - 시간보정: ${timeBias.toStringAsFixed(2)}');
      print('  - 최종점수: ${finalScore.toStringAsFixed(2)} (트렌드×기본 + 거래량 + 시간보정)');
      
      return finalScore.clamp(-1.0, 1.0);
      
    } catch (e) {
      print('⚠️ 이동평균선 동적 점수 계산 실패: $e');
      return 0.0;
    }
  }

  /// 시장환경 판단 (ADX 기반)
  static bool _isTrendMarket(double adxValue) {
    return adxValue >= 25; // ADX ≥ 25: 트렌드, ADX < 25: 박스권
  }

  /// 배열 상태 분석
  static String _analyzeArrayStatus(double ma5, double ma20, double ma60) {
    // 완전정배열 (5 > 20 > 60)
    if (ma5 > ma20 && ma20 > ma60) {
      return '완전정배열';
    }
    // 부분정배열 (5 > 20)
    else if (ma5 > ma20) {
      return '부분정배열';
    }
    // 부분역배열 (5 < 20)
    else if (ma5 < ma20) {
      return '부분역배열';
    }
    // 완전역배열 (5 < 20 < 60)
    else if (ma5 < ma20 && ma20 < ma60) {
      return '완전역배열';
    }
    // 중립 (5 = 20)
    else {
      return '중립';
    }
  }

  /// 기본 점수 계산
  static double _calculateBaseScore(String arrayStatus) {
    switch (arrayStatus) {
      case '완전정배열':
        return 1.0; // 강한 상승 신호
      case '부분정배열':
        return 0.6; // 상승 신호
      case '부분역배열':
        return -0.6; // 하락 신호
      case '완전역배열':
        return -1.0; // 강한 하락 신호
      case '중립':
      default:
        return 0.0; // 중립
    }
  }

  /// 거래량 가중치 계산
  static double _calculateVolumeWeight(int currentVolume, int averageVolume) {
    if (averageVolume <= 0) return 0.0;
    
    final double volumeRatio = currentVolume / averageVolume;
    
    // 거래량이 동반되면 신호 강화
    if (volumeRatio >= 2.0) {
      return 0.3; // 강한 거래량 동반
    } else if (volumeRatio >= 1.5) {
      return 0.2; // 거래량 동반
    } else if (volumeRatio >= 1.2) {
      return 0.1; // 약한 거래량 동반
    } else if (volumeRatio < 0.8) {
      return -0.1; // 거래량 부족으로 신호 약화
    }
    
    return 0.0; // 보통 거래량
  }

  /// 시간대별 보정치 반환 (표 규칙)
  static double _getTimeBias(String currentTime) {
    final time = _parseTime(currentTime);
    
    // 22:30-23:30 (나스닥 시작)
    if (_isTimeInRange(time, 22, 30, 23, 30)) {
      return 0.2;
    }
    
    // 23:30-05:00 (나스닥 본격)
    if (_isTimeInRange(time, 23, 30, 24, 0) || _isTimeInRange(time, 0, 0, 5, 0)) {
      return 0.1;
    }
    
    // 05:00-06:00 (나스닥 마감)
    if (_isTimeInRange(time, 5, 0, 6, 0)) {
      return 0.3;
    }
    
    // 09:00-10:00 (코스피 시작)
    if (_isTimeInRange(time, 9, 0, 10, 0)) {
      return 0.2;
    }
    
    // 10:00-14:00 (코스피 중반)
    if (_isTimeInRange(time, 10, 0, 14, 0)) {
      return 0.0;
    }
    
    // 14:00-15:30 (코스피 마감)
    if (_isTimeInRange(time, 14, 0, 15, 30)) {
      return 0.1;
    }
    
    // 기타 시간
    return 0.0;
  }

  /// 시간 파싱 (HH:mm → 분 단위)
  static int _parseTime(String timeStr) {
    final parts = timeStr.split(':');
    if (parts.length != 2) return 0;
    
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    
    return hour * 60 + minute;
  }

  /// 시간 범위 체크
  static bool _isTimeInRange(int time, int startHour, int startMinute, int endHour, int endMinute) {
    final startTime = startHour * 60 + startMinute;
    final endTime = endHour * 60 + endMinute;
    
    if (startTime <= endTime) {
      return time >= startTime && time < endTime;
    } else {
      // 자정을 넘는 경우 (예: 23:30-05:00)
      return time >= startTime || time < endTime;
    }
  }

}
