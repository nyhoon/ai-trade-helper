import 'dart:math';

/// ADX 동적 점수 계산기
/// 거래량 수준, ADX 값, 시간대별 신뢰도, 변동성 등을 포함
class ADXDynamicScoreCalculator {
  
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

  /// ADX 동적 점수 계산
  /// 
  /// [adxValue] ADX 값
  /// [currentVolume] 현재 거래량
  /// [averageVolume] 평균 거래량
  /// [currentATR] 현재 ATR 값
  /// [averageATR] 평균 ATR 값
  /// [currentTime] 현재 시간 (HH:mm 형식)
  /// 
  /// Returns: -1.0 ~ +1.0 범위의 점수
  static double calculateADXScore({
    required double adxValue,
    required int currentVolume,
    required int averageVolume,
    required double currentATR,
    required double averageATR,
    required String currentTime,
  }) {
    try {
      // 1. 거래량 수준 판단
      final bool isHighVolume = _isHighVolume(currentVolume, averageVolume);
      
      // 2. 기본 ADX 점수 계산
      final double baseScore = _calculateBaseADXScore(adxValue);
      
      // 3. 시간대별 보정치 적용
      final double timeBias = _getTimeBias(currentTime);
      
      // 4. 변동성 가중치 계산
      final double volatilityWeight = _calculateVolatilityWeight(currentATR, averageATR);
      
      // 5. 최종 점수 계산
      // 가중치들을 곱해서 점수 범위를 -1.0~1.0으로 유지
      final double volumeMultiplier = isHighVolume ? 1.4 : 1.0;
      final double finalScore = (baseScore * volumeMultiplier) + volatilityWeight + timeBias;
      
      print('📊 ADX 동적 점수 계산 결과:');
      print('  - ADX: ${adxValue.toStringAsFixed(1)}');
      print('  - 거래량: ${isHighVolume ? "급증" : "보통"}');
      print('  - 기본점수: ${baseScore.toStringAsFixed(2)}');
      print('  - 시간보정: ${timeBias.toStringAsFixed(2)}');
      print('  - 변동성가중치: ${volatilityWeight.toStringAsFixed(2)}');
      print('  - 최종점수: ${finalScore.toStringAsFixed(2)} (거래량×기본 + 변동성 + 시간보정)');
      
      return finalScore.clamp(-1.0, 1.0);
      
    } catch (e) {
      print('⚠️ ADX 동적 점수 계산 실패: $e');
      return 0.0;
    }
  }

  /// 거래량 수준 판단
  static bool _isHighVolume(int currentVolume, int averageVolume) {
    if (averageVolume <= 0) return false;
    return currentVolume >= averageVolume * 2.0;
  }

  /// 기본 ADX 점수 계산
  static double _calculateBaseADXScore(double adxValue) {
    // ADX ≥ 25: 강한 추세 (매수 신호)
    if (adxValue >= 25) {
      return 1.0; // 강한 추세
    }
    // ADX ≥ 20: 보통 추세 (약한 매수 신호)
    else if (adxValue >= 20) {
      return 0.8; // 보통 추세
    }
    // ADX < 20: 약한 추세 (매도 신호)
    else if (adxValue >= 15) {
      return -0.3; // 약한 추세
    }
    // ADX < 15: 무추세 (강한 매도 신호)
    else {
      return -0.8; // 무추세
    }
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

  /// 변동성 가중치 계산
  static double _calculateVolatilityWeight(double currentATR, double averageATR) {
    if (averageATR <= 0) return 0.0;
    
    final double atrRatio = currentATR / averageATR;
    
    // 높은 변동성에서는 추세 신호가 약화됨 (박스권 시장)
    if (atrRatio >= 2.0) {
      return -0.2; // 매우 높은 변동성 (추세 신호 약화)
    } else if (atrRatio >= 1.5) {
      return -0.1; // 높은 변동성 (추세 신호 약화)
    } else if (atrRatio < 0.8) {
      return 0.2; // 낮은 변동성 (추세 신호 강화)
    } else if (atrRatio < 0.5) {
      return 0.3; // 매우 낮은 변동성 (추세 신호 강화)
    }
    
    return 0.0; // 보통 변동성
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
