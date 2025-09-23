import 'dart:math';

/// MACD 동적 점수 계산기
/// ADX 추세 강도, MACD 신호, 거래량 동반 여부, 시간대별 가중치 등을 포함
class MACDDynamicScoreCalculator {
  
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

  /// MACD 동적 점수 계산
  /// 
  /// [macdValue] MACD 값
  /// [signalValue] Signal 값
  /// [adxValue] ADX 값 (추세 강도)
  /// [currentVolume] 현재 거래량
  /// [averageVolume] 평균 거래량
  /// [currentTime] 현재 시간 (HH:mm 형식)
  /// 
  /// Returns: -1.0 ~ +1.0 범위의 점수
  static double calculateMACDScore({
    required double macdValue,
    required double signalValue,
    required double adxValue,
    required int currentVolume,
    required int averageVolume,
    required String currentTime,
  }) {
    try {
      // 1. 기본 MACD 점수 계산
      final double baseScore = _calculateBaseMACDScore(macdValue, signalValue);
      
      // 2. 추세 강도 가중치 계산
      final double trendWeight = _calculateTrendWeight(adxValue);
      
      // 3. 거래량 가중치 계산
      final double volumeWeight = _calculateVolumeWeight(currentVolume, averageVolume);
      
      // 4. 시간대별 가중치 적용
      final double timeWeight = _getTimeWeight(currentTime);
      
      // 5. 최종 점수 계산: 기본 점수 × 추세가중치 + 거래량가중치 + 시간대가중치
      final double finalScore = (baseScore * trendWeight) + volumeWeight + _mapTimeWeightToBias(timeWeight, macdValue, signalValue);
      
      print('📊 MACD 동적 점수 계산 결과:');
      print('  - MACD: ${macdValue.toStringAsFixed(3)}');
      print('  - Signal: ${signalValue.toStringAsFixed(3)}');
      print('  - ADX: ${adxValue.toStringAsFixed(1)}');
      print('  - 기본점수: ${baseScore.toStringAsFixed(2)}');
      print('  - 추세가중치: ${trendWeight.toStringAsFixed(2)}');
      print('  - 거래량가중치: ${volumeWeight.toStringAsFixed(2)}');
      print('  - 시간가중치: ${timeWeight.toStringAsFixed(2)}');
      print('  - 최종점수: ${finalScore.toStringAsFixed(2)} (추세×기본 + 거래량 + 시간보정)');
      
      return finalScore.clamp(-1.0, 1.0);
      
    } catch (e) {
      print('⚠️ MACD 동적 점수 계산 실패: $e');
      return 0.0;
    }
  }

  /// 시간대 가중치를 점수 바이어스로 환산
  /// 규칙: 나스닥 마감(05:00-06:00) +0.3, 나스닥 시작/코스피 시작 +0.2,
  /// 나스닥 본격 +0.1, 코스피 마감 +0.1, 그 외 0.0
  static double _mapTimeWeightToBias(double timeWeight, double macdValue, double signalValue) {
    // timeWeight는 파일 상단 매핑을 그대로 쓰지 않고, 범주에 따라 상수 보정으로 변환
    // ratio로 구분(대략): 1.5->마감, 1.4/1.2->시작, 1.2 나스닥본격, 1.3 코스피마감, 1.0/0.8 기타
    if (timeWeight >= 1.49) return 0.3; // 05:00-06:00
    if (timeWeight >= 1.39) return 0.2; // 22:30-23:30
    if (timeWeight >= 1.29 && timeWeight < 1.31) return 0.1; // 14:00-15:30
    if (timeWeight >= 1.19 && timeWeight < 1.21) return 0.1; // 23:30-05:00
    if (timeWeight >= 1.19 && timeWeight < 1.21) return 0.1; // safety
    if (timeWeight >= 1.19 && timeWeight < 1.25) return 0.2; // 09:00-10:00 근사
    return 0.0;
  }

  /// 기본 MACD 점수 계산
  static double _calculateBaseMACDScore(double macdValue, double signalValue) {
    final double macdDiff = macdValue - signalValue;
    final double macdRatio = signalValue != 0 ? macdValue / signalValue : 0;
    
    // 골든크로스 (MACD > Signal)
    if (macdDiff > 0) {
      if (macdRatio >= 1.5) {
        return 1.0; // 강한 골든크로스
      } else if (macdRatio >= 1.2) {
        return 0.8; // 골든크로스
      } else if (macdRatio >= 1.05) {
        return 0.6; // 약한 골든크로스
      } else {
        return 0.3; // 매우 약한 골든크로스
      }
    }
    
    // 데드크로스 (MACD < Signal)
    if (macdDiff < 0) {
      if (macdRatio <= 0.5) {
        return -1.0; // 강한 데드크로스
      } else if (macdRatio <= 0.8) {
        return -0.8; // 데드크로스
      } else if (macdRatio <= 0.95) {
        return -0.6; // 약한 데드크로스
      } else {
        return -0.3; // 매우 약한 데드크로스
      }
    }
    
    // MACD = Signal (중립)
    return 0.0;
  }

  /// 추세 강도 가중치 계산 (ADX 기반)
  static double _calculateTrendWeight(double adxValue) {
    // ADX ≥ 25: 강한 추세
    if (adxValue >= 25) {
      return 1.5;
    }
    // ADX < 25: 약한 추세 (박스권)
    else {
      return 1.0;
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
