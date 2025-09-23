import 'dart:math';
import '../../trading/market_time_validator.dart';

/// 거래량 동적 점수 계산기
/// 시간대별 가중치, 거래량비율, 상승/하락일 판단, 장 시작 보정 등을 포함
class VolumeDynamicScoreCalculator {
  
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

  /// 거래량비율별 점수 정의
  static const Map<String, Map<String, double>> _volumeRatioScores = {
    '≥2.0': {'up': 1.0, 'down': -1.0},
    '≥1.5': {'up': 0.8, 'down': -0.8},
    '≥1.2': {'up': 0.6, 'down': -0.6},
    '≥0.8': {'up': 0.4, 'down': -0.4},
    '<0.8': {'up': 0.2, 'down': -0.2},
  };

  /// 장 시작 보정이 적용되는 시간대
  static const List<String> _marketStartTimes = ['22:30-23:30', '09:00-10:00'];

  /// 거래량 동적 점수 계산
  /// 
  /// [currentVolume] 현재 거래량
  /// [averageVolume] 기준 거래량 (20일 평균 등)
  /// [currentPrice] 현재가
  /// [previousPrice] 이전가
  /// [openPrice] 시가 (당일 기준 방향성 판단용)
  /// [currentTime] 현재 시간 (HH:mm 형식)
  /// 
  /// Returns: -1.0 ~ +1.0 범위의 점수
  static double calculateVolumeScore({
    required int currentVolume,
    required int averageVolume,
    required double currentPrice,
    required double previousPrice,
    required double openPrice,
    required String currentTime,
    bool isMarketClosed = false,
    String? market,
  }) {
    try {
      // 1. 현재가 방향성 판단 (시가 기준)
      // 시가와 현재가가 같으면 중립으로 처리 (하락일이 아닌 상승일로 간주)
      final bool isUpDay = currentPrice >= openPrice;
      
      // 2. 거래량비율 계산
      final double volumeRatio = _calculateVolumeRatio(
        currentVolume: currentVolume,
        averageVolume: averageVolume,
        currentTime: currentTime,
      );
      
      // 3. 기본 점수 계산 (장후 모드에서는 시간 보정 없이 최종 배율 기반)
      final double baseScore = _calculateBaseScore(
        volumeRatio: volumeRatio,
        isUpDay: isUpDay,
      );
      
      // 4. 장 시작 보정 적용
      final double marketStartAdjustment = _calculateMarketStartAdjustment(
        volumeRatio: volumeRatio,
        currentTime: currentTime,
      );
      
      // 5. 장중 조기 튐 방지 캡: MarketTimeValidator 기반
      final String detectedMarket = market ?? _detectMarketFromContext(indicatorMarket: market);
      final bool closed = isMarketClosed || MarketTimeValidator.instance.isMarketClosed(detectedMarket);
      final bool early = MarketTimeValidator.instance.isEarlySession(detectedMarket);

      double cappedScore = baseScore + marketStartAdjustment;
      if (!closed && early) {
        cappedScore = cappedScore.clamp(-0.6, 0.6);
      }

      // 6. 최종 점수 (장후 모드는 그대로 확정)
      final double finalScore = cappedScore;
      
      print('📊 거래량 동적 점수 계산 결과:');
      print('  - 현재가: ${currentPrice.toStringAsFixed(0)}원');
      print('  - 시가: ${openPrice.toStringAsFixed(0)}원');
      print('  - 이전가: ${previousPrice.toStringAsFixed(0)}원');
      print('  - 방향성: ${isUpDay ? "상승일" : "하락일"} (시가 기준)');
      print('  - 현재거래량: ${currentVolume.toStringAsFixed(0)}');
      print('  - 기준거래량: ${averageVolume.toStringAsFixed(0)}');
      print('  - 거래량비율: ${volumeRatio.toStringAsFixed(2)}');
      print('  - 기본점수: ${baseScore.toStringAsFixed(2)}');
      print('  - 장시작보정: ${marketStartAdjustment.toStringAsFixed(2)}');
      print('  - 최종점수: ${finalScore.toStringAsFixed(2)} (${closed ? "마감 확정" : (early ? "장중 보정(초반 캡)" : "장중 보정")})');
      print('  - 시간대: $currentTime');
      
      return finalScore.clamp(-1.0, 1.0);
      
    } catch (e) {
      print('⚠️ 거래량 동적 점수 계산 실패: $e');
      return 0.0;
    }
  }

  /// 거래량비율 계산 (시간가중치 적용)
  static double _calculateVolumeRatio({
    required int currentVolume,
    required int averageVolume,
    required String currentTime,
  }) {
    if (averageVolume <= 0) return 1.0;

    // 표 기준: 거래량비율 = 현재거래량 ÷ (기준거래량 × 시간가중치)
    final double timeWeight = _getTimeWeight(currentTime);
    final double baseline = (averageVolume * timeWeight).clamp(1.0, double.infinity);
    final double ratio = currentVolume / baseline;
    return ratio;
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

  // 기대 누적 비율 기반 로직은 표준화된 시간 가중치 방식으로 대체되었습니다.

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

  /// 기본 점수 계산
  static double _calculateBaseScore({
    required double volumeRatio,
    required bool isUpDay,
  }) {
    if (volumeRatio >= 2.0) {
      return isUpDay ? 1.0 : -1.0;
    } else if (volumeRatio >= 1.5) {
      return isUpDay ? 0.8 : -0.8;
    } else if (volumeRatio >= 1.2) {
      return isUpDay ? 0.6 : -0.6;
    } else if (volumeRatio >= 0.8) {
      return isUpDay ? 0.4 : -0.4;
    } else {
      return isUpDay ? 0.2 : -0.2;
    }
  }

  /// 장 시작 보정 계산
  static double _calculateMarketStartAdjustment({
    required double volumeRatio,
    required String currentTime,
  }) {
    // 장 시작 시간대이고 거래량비율이 0.8 미만일 때만 보정
    if (volumeRatio < 0.8 && _isMarketStartTime(currentTime)) {
      return 0.3;
    }
    
    return 0.0;
  }

  /// 장 시작 시간대 여부 확인
  static bool _isMarketStartTime(String currentTime) {
    final time = _parseTime(currentTime);
    
    // 22:30-23:30 (나스닥 시작)
    if (_isTimeInRange(time, 22, 30, 23, 30)) {
      return true;
    }
    
    // 09:00-10:00 (코스피 시작)
    if (_isTimeInRange(time, 9, 0, 10, 0)) {
      return true;
    }
    
    return false;
  }

  /// 장중 초반 시간대 여부 (캡 적용)
  static bool _isEarlySession(String currentTime) {
    final int t = _parseTime(currentTime);
    // KR: 09:00~10:00, US: 22:30~23:30
    if (_isTimeInRange(t, 9, 0, 10, 0)) return true;
    if (_isTimeInRange(t, 22, 30, 23, 30)) return true;
    return false;
  }

  /// 시장 자동 감지 (선택적): 명시적 market 미제공 시 KOSPI 기본
  static String _detectMarketFromContext({String? indicatorMarket}) {
    if (indicatorMarket != null && indicatorMarket.isNotEmpty) {
      return indicatorMarket;
    }
    // 호출부에서 심볼을 주지 않으므로 최소 기본값 제공
    return 'KOSPI';
  }

}
