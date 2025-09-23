import 'dart:math';

/// 볼린저밴드 동적 점수 계산기
/// 변동성 수준, 밴드 위치, 거래량 급증 여부, 시간대별 가중치 등을 포함
class BollingerDynamicScoreCalculator {
  
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

  /// 볼린저밴드 동적 점수 계산
  /// 
  /// [currentPrice] 현재가
  /// [upperBand] 상단 밴드
  /// [middleBand] 중간 밴드
  /// [lowerBand] 하단 밴드
  /// [currentATR] 현재 ATR 값
  /// [averageATR] 평균 ATR 값
  /// [currentVolume] 현재 거래량
  /// [averageVolume] 평균 거래량
  /// [currentTime] 현재 시간 (HH:mm 형식)
  /// 
  /// Returns: -1.0 ~ +1.0 범위의 점수
  static double calculateBollingerScore({
    required double currentPrice,
    required double upperBand,
    required double middleBand,
    required double lowerBand,
    required double currentATR,
    required double averageATR,
    required int currentVolume,
    required int averageVolume,
    required String currentTime,
  }) {
    try {
      // 1. 변동성 수준 판단
      final bool isHighVolatility = _isHighVolatility(currentATR, averageATR);
      
      // 2. 밴드 위치 판단
      final double bandPosition = _calculateBandPosition(currentPrice, upperBand, middleBand, lowerBand);
      
      // 3. 기본 점수 계산
      final double baseScore = _calculateBaseScore(bandPosition, isHighVolatility);
      
      // 4. 거래량 가중치 계산
      final double volumeWeight = _calculateVolumeWeight(currentVolume, averageVolume);
      
      // 5. 시간대별 보정치 적용
      final double timeBias = _getTimeBias(currentTime);
      
      // 6. 최종 점수 계산
      // 가중치들을 곱해서 점수 범위를 -1.0~1.0으로 유지
      final double volatilityMultiplier = isHighVolatility ? 1.3 : 1.0;
      final double finalScore = (baseScore * volatilityMultiplier) + volumeWeight + timeBias;
      
      print('📊 볼린저밴드 동적 점수 계산 결과:');
      print('  - 현재가: ${currentPrice.toStringAsFixed(0)}원');
      print('  - 상단밴드: ${upperBand.toStringAsFixed(0)}원');
      print('  - 중간밴드: ${middleBand.toStringAsFixed(0)}원');
      print('  - 하단밴드: ${lowerBand.toStringAsFixed(0)}원');
      print('  - 밴드위치: ${bandPosition.toStringAsFixed(2)}%');
      print('  - 변동성: ${isHighVolatility ? "높음" : "보통"}');
      print('  - 기본점수: ${baseScore.toStringAsFixed(2)}');
      print('  - 거래량가중치: ${volumeWeight.toStringAsFixed(2)}');
      print('  - 시간보정: ${timeBias.toStringAsFixed(2)}');
      print('  - 최종점수: ${finalScore.toStringAsFixed(2)} (변동성×기본 + 거래량 + 시간보정)');
      
      return finalScore.clamp(-1.0, 1.0);
      
    } catch (e) {
      print('⚠️ 볼린저밴드 동적 점수 계산 실패: $e');
      return 0.0;
    }
  }

  /// 변동성 수준 판단
  static bool _isHighVolatility(double currentATR, double averageATR) {
    if (averageATR <= 0) return false;
    return currentATR >= averageATR * 1.5;
  }

  /// 밴드 위치 계산 (중간 밴드 대비 현재가의 위치)
  static double _calculateBandPosition(double currentPrice, double upperBand, double middleBand, double lowerBand) {
    if (middleBand <= 0) return 0.0;
    
    final double bandRange = upperBand - lowerBand;
    if (bandRange <= 0) return 0.0;
    
    // 중간 밴드 대비 현재가의 위치를 백분율로 계산
    final double positionFromMiddle = ((currentPrice - middleBand) / bandRange) * 100;
    
    return positionFromMiddle;
  }

  /// 기본 점수 계산
  static double _calculateBaseScore(double bandPosition, bool isHighVolatility) {
    // 하단 터치 (0-5%)
    if (bandPosition <= 5) {
      return isHighVolatility ? 1.0 : 0.8; // 매수 신호
    }
    // 하단 근접 (5-15%)
    else if (bandPosition <= 15) {
      return isHighVolatility ? 0.6 : 0.5; // 약한 매수 신호
    }
    // 상단 터치 (95-100%)
    else if (bandPosition >= 95) {
      return isHighVolatility ? -1.0 : -0.8; // 매도 신호
    }
    // 상단 근접 (85-95%)
    else if (bandPosition >= 85) {
      return isHighVolatility ? -0.6 : -0.5; // 약한 매도 신호
    }
    // 중간 구간 (15-85%)
    else {
      return 0.0; // 중립
    }
  }

  /// 거래량 가중치 계산
  static double _calculateVolumeWeight(int currentVolume, int averageVolume) {
    if (averageVolume <= 0) return 0.0;
    
    final double volumeRatio = currentVolume / averageVolume;
    
    // 거래량이 급증하면 신호 강화
    if (volumeRatio >= 2.0) {
      return 0.3; // 강한 거래량 급증
    } else if (volumeRatio >= 1.5) {
      return 0.2; // 거래량 급증
    } else if (volumeRatio >= 1.2) {
      return 0.1; // 약한 거래량 급증
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
