import 'dart:math';

/// VWAP 동적 점수 계산기
/// 거래량 수준, VWAP 대비 위치, 시간대별 중요도, 변동성 등을 포함
class VWAPDynamicScoreCalculator {
  
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

  /// VWAP 동적 점수 계산
  /// 
  /// [currentPrice] 현재가
  /// [vwapValue] VWAP 값
  /// [currentVolume] 현재 거래량
  /// [averageVolume] 평균 거래량
  /// [currentATR] 현재 ATR 값
  /// [averageATR] 평균 ATR 값
  /// [currentTime] 현재 시간 (HH:mm 형식)
  /// 
  /// Returns: -1.0 ~ +1.0 범위의 점수
  static double calculateVWAPScore({
    required double currentPrice,
    required double vwapValue,
    required int currentVolume,
    required int averageVolume,
    required double currentATR,
    required double averageATR,
    required String currentTime,
  }) {
    try {
      // 1. 거래량 수준 판단
      final bool isHighVolume = _isHighVolume(currentVolume, averageVolume);
      
      // 2. VWAP 대비 위치 계산
      final double vwapPosition = _calculateVWAPPosition(currentPrice, vwapValue);
      
      // 3. 기본 점수 계산
      final double baseScore = _calculateBaseScore(vwapPosition);
      
      // 4. 시간대별 보정치 적용
      final double timeBias = _getTimeBias(currentTime);
      
      // 5. 변동성 가중치 계산
      final double volatilityWeight = _calculateVolatilityWeight(currentATR, averageATR);
      
      // 6. 최종 점수 계산
      // 가중치들을 곱해서 점수 범위를 -1.0~1.0으로 유지
      final double volumeMultiplier = isHighVolume ? 1.4 : 1.0;
      final double finalScore = (baseScore * volumeMultiplier) + volatilityWeight + timeBias;
      
      print('📊 VWAP 동적 점수 계산 결과:');
      print('  - 현재가: ${currentPrice.toStringAsFixed(0)}원');
      print('  - VWAP: ${vwapValue.toStringAsFixed(0)}원');
      print('  - VWAP대비: ${vwapPosition.toStringAsFixed(2)}%');
      print('  - 거래량: ${isHighVolume ? "급증" : "보통"}');
      print('  - 기본점수: ${baseScore.toStringAsFixed(2)}');
      print('  - 시간보정: ${timeBias.toStringAsFixed(2)}');
      print('  - 변동성가중치: ${volatilityWeight.toStringAsFixed(2)}');
      print('  - 최종점수: ${finalScore.toStringAsFixed(2)} (거래량×기본 + 변동성 + 시간보정)');
      
      return finalScore.clamp(-1.0, 1.0);
      
    } catch (e) {
      print('⚠️ VWAP 동적 점수 계산 실패: $e');
      return 0.0;
    }
  }

  /// 거래량 수준 판단
  static bool _isHighVolume(int currentVolume, int averageVolume) {
    if (averageVolume <= 0) return false;
    return currentVolume >= averageVolume * 2.0;
  }

  /// VWAP 대비 위치 계산
  static double _calculateVWAPPosition(double currentPrice, double vwapValue) {
    if (vwapValue <= 0) return 0.0;
    
    // VWAP 대비 현재가의 위치를 백분율로 계산
    return ((currentPrice - vwapValue) / vwapValue) * 100;
  }

  /// 기본 점수 계산
  static double _calculateBaseScore(double vwapPosition) {
    // VWAP 상단 (+2% 이상)
    if (vwapPosition >= 2.0) {
      return 1.0; // 강한 매수 신호
    }
    // VWAP 근접 (±1%)
    else if (vwapPosition.abs() <= 1.0) {
      return 0.6; // 약한 매수 신호
    }
    // VWAP 하단 (-2% 이하)
    else if (vwapPosition <= -2.0) {
      return -1.0; // 강한 매도 신호
    }
    // VWAP 중간 (±1-2%)
    else if (vwapPosition > 1.0 && vwapPosition < 2.0) {
      return 0.6; // 약한 매수 신호
    }
    else if (vwapPosition < -1.0 && vwapPosition > -2.0) {
      return -0.6; // 약한 매도 신호
    }
    else {
      return 0.0; // 중립
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
    
    // 높은 변동성에서는 VWAP 신호가 더 강력함
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
