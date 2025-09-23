import 'dart:math';

/// RSI 동적 점수 계산기
/// RSI 값, 거래량 동반 여부, 변동성 높음 여부, 시간가중치 등을 포함
class RSIDynamicScoreCalculator {
  
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

  /// RSI 동적 점수 계산
  /// 
  /// [rsiValue] RSI 값 (0-100)
  /// [currentVolume] 현재 거래량
  /// [averageVolume] 평균 거래량
  /// [currentATR] 현재 ATR 값
  /// [averageATR] 평균 ATR 값
  /// [currentTime] 현재 시간 (HH:mm 형식)
  /// 
  /// Returns: -1.0 ~ +1.0 범위의 점수
  static double calculateRSIScore({
    required double rsiValue,
    required int currentVolume,
    required int averageVolume,
    required double currentATR,
    required double averageATR,
    required String currentTime,
  }) {
    try {
      // 1. 기본 RSI 점수 계산
      final double baseScore = _calculateBaseRSIScore(rsiValue);
      
      // 2. 거래량 가중치 계산
      final double volumeWeight = _calculateVolumeWeight(currentVolume, averageVolume);
      
      // 3. 변동성 가중치 계산
      final double volatilityWeight = _calculateVolatilityWeight(currentATR, averageATR);
      
      // 4. 시간가중치 적용
      final double timeWeight = _getTimeWeight(currentTime);
      
      // 5. 최종 점수 계산: 기본점수 × 시간가중치 + 거래량가중치 + 변동성가중치
      final double finalScore = (baseScore * timeWeight) + volumeWeight + volatilityWeight;
      
      print('📊 RSI 동적 점수 계산 결과:');
      print('  - RSI 값: ${rsiValue.toStringAsFixed(1)}');
      print('  - 기본점수: ${baseScore.toStringAsFixed(2)}');
      print('  - 거래량가중치: ${volumeWeight.toStringAsFixed(2)}');
      print('  - 변동성가중치: ${volatilityWeight.toStringAsFixed(2)}');
      print('  - 시간가중치: ${timeWeight.toStringAsFixed(2)}');
      print('  - 최종점수: ${finalScore.toStringAsFixed(2)} (시간×기본 + 거래량 + 변동성)');
      
      return finalScore.clamp(-1.0, 1.0);
      
    } catch (e) {
      print('⚠️ RSI 동적 점수 계산 실패: $e');
      return 0.0;
    }
  }

  /// 기본 RSI 점수 계산
  static double _calculateBaseRSIScore(double rsiValue) {
    // 과매도 구간 (RSI ≤ 45)
    if (rsiValue <= 30) {
      return 1.0; // 강한 매수 신호
    } else if (rsiValue <= 35) {
      return 0.8; // 매수 신호
    } else if (rsiValue <= 40) {
      return 0.6; // 약한 매수 신호
    } else if (rsiValue <= 45) {
      return 0.4; // 매우 약한 매수 신호
    }
    
    // 중립 구간 (45 < RSI < 55)
    if (rsiValue < 55) {
      return 0.0; // 중립
    }
    
    // 과매수 구간 (RSI ≥ 55)
    if (rsiValue >= 70) {
      return -1.0; // 강한 매도 신호
    } else if (rsiValue >= 65) {
      return -0.8; // 매도 신호
    } else if (rsiValue >= 60) {
      return -0.6; // 약한 매도 신호
    } else if (rsiValue >= 55) {
      return -0.4; // 매우 약한 매도 신호
    }
    
    return 0.0;
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

  /// 변동성 가중치 계산
  static double _calculateVolatilityWeight(double currentATR, double averageATR) {
    if (averageATR <= 0) return 0.0;
    
    final double atrRatio = currentATR / averageATR;
    
    // 높은 변동성에서는 RSI 신호가 더 강력함
    if (atrRatio >= 2.0) {
      return 0.2; // 매우 높은 변동성
    } else if (atrRatio >= 1.5) {
      return 0.1; // 높은 변동성
    } else if (atrRatio >= 1.2) {
      return 0.1; // 약간 높은 변동성
    } else if (atrRatio < 0.8) {
      return -0.1; // 낮은 변동성으로 신호 약화
    }
    
    return 0.0; // 보통 변동성
  }

  /// 시간대별 가중치 반환
  static double _getTimeWeight(String currentTime) {
    final time = _parseTime(currentTime);
    
    // 22:30-23:30 (나스닥 시작)
    if (_isTimeInRange(time, 22, 30, 23, 30)) {
      return _timeWeights['22:30-23:30']!;
    }
    
    // 23:30-05:00 (나스닥 본격)
    if (_isTimeInRange(time, 23, 30, 24, 0) || _isTimeInRange(time, 0, 0, 5, 0)) {
      return _timeWeights['23:30-05:00']!;
    }
    
    // 05:00-06:00 (나스닥 마감)
    if (_isTimeInRange(time, 5, 0, 6, 0)) {
      return _timeWeights['05:00-06:00']!;
    }
    
    // 09:00-10:00 (코스피 시작)
    if (_isTimeInRange(time, 9, 0, 10, 0)) {
      return _timeWeights['09:00-10:00']!;
    }
    
    // 10:00-14:00 (코스피 중반)
    if (_isTimeInRange(time, 10, 0, 14, 0)) {
      return _timeWeights['10:00-14:00']!;
    }
    
    // 14:00-15:30 (코스피 마감)
    if (_isTimeInRange(time, 14, 0, 15, 30)) {
      return _timeWeights['14:00-15:30']!;
    }
    
    // 기타 시간
    return _timeWeights['default']!;
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
