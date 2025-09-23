import 'dart:math';
import 'market_time_validator.dart';

/// 거래량 동적 임계값 관리 클래스
class VolumeThresholdManager {
  static VolumeThresholdManager? _instance;
  static VolumeThresholdManager get instance => _instance ??= VolumeThresholdManager._();
  
  VolumeThresholdManager._();

  /// 시장별 거래 시간 정의
  static const Map<String, Map<String, int>> _marketTradingHours = {
    'KOSPI': {
      'start': 9,
      'end': 15,
      'end_minute': 30,
    },
    'KOSDAQ': {
      'start': 9,
      'end': 15,
      'end_minute': 30,
    },
    'NASDAQ': {
      'start': 22,
      'start_minute': 30,
      'end': 5,
      'end_minute': 0,
    },
  };

  /// 시간대별 거래량 임계값 정의 (거래 시간 내에서만)
  static const Map<String, Map<String, double>> _timeBasedThresholds = {
    'market_open': {      // 9:00-10:00 (장 시작)
      'high': 2.5,        // 거래량 급증 임계값
      'medium': 1.8,      // 거래량 증가 임계값
      'low': 0.8,         // 거래량 감소 임계값
      'very_low': 0.4,    // 거래량 급감 임계값
    },
    'morning_peak': {     // 10:00-11:00 (오전 피크)
      'high': 2.2,
      'medium': 1.6,
      'low': 0.8,
      'very_low': 0.4,
    },
    'lunch_time': {       // 11:00-13:00 (점심 시간)
      'high': 1.8,
      'medium': 1.4,
      'low': 0.7,
      'very_low': 0.3,
    },
    'afternoon': {        // 13:00-14:00 (오후)
      'high': 1.6,
      'medium': 1.3,
      'low': 0.7,
      'very_low': 0.3,
    },
    'market_close': {     // 14:00-15:00 (장 마감)
      'high': 2.3,
      'medium': 1.7,
      'low': 0.8,
      'very_low': 0.4,
    },
    'nasdaq_night': {     // 22:30-00:00 (나스닥 밤)
      'high': 2.0,
      'medium': 1.5,
      'low': 0.8,
      'very_low': 0.4,
    },
    'nasdaq_midnight': {  // 00:00-02:00 (나스닥 자정)
      'high': 1.8,
      'medium': 1.4,
      'low': 0.7,
      'very_low': 0.3,
    },
    'nasdaq_early_morning': { // 02:00-05:00 (나스닥 새벽)
      'high': 1.6,
      'medium': 1.3,
      'low': 0.7,
      'very_low': 0.3,
    },
  };

  /// 현재 시간대에 따른 거래량 임계값 가져오기 (시장별)
  Map<String, double> getCurrentThresholds({String market = 'KOSPI'}) {
    final now = DateTime.now();
    final hour = now.hour;
    final minute = now.minute;
    
    // 거래 시간 외인지 확인
    if (!isTradingTime(market)) {
      print('⚠️ 거래 시간 외: $market 시장은 현재 거래 중이 아닙니다');
      return {
        'high': 0.0,
        'medium': 0.0,
        'low': 0.0,
        'very_low': 0.0,
      };
    }
    
    // 시장별 시간대 구분
    if (market == 'KOSPI' || market == 'KOSDAQ') {
      // 국내주식 시장
      if (hour >= 9 && hour < 10) {
        return _timeBasedThresholds['market_open']!;
      } else if (hour >= 10 && hour < 11) {
        return _timeBasedThresholds['morning_peak']!;
      } else if (hour >= 11 && hour < 13) {
        return _timeBasedThresholds['lunch_time']!;
      } else if (hour >= 13 && hour < 14) {
        return _timeBasedThresholds['afternoon']!;
      } else if (hour >= 14 && hour < 15) {
        return _timeBasedThresholds['market_close']!;
      } else if (hour == 15 && minute <= 30) {
        return _timeBasedThresholds['market_close']!;
      }
    } else if (market == 'NASDAQ') {
      // 나스닥 시장
      if (hour >= 22 && minute >= 30) {
        return _timeBasedThresholds['nasdaq_night']!;
      } else if (hour >= 0 && hour < 2) {
        return _timeBasedThresholds['nasdaq_midnight']!;
      } else if (hour >= 2 && hour < 5) {
        return _timeBasedThresholds['nasdaq_early_morning']!;
      }
    }
    
    // 기본값 (거래 시간 외)
    return {
      'high': 0.0,
      'medium': 0.0,
      'low': 0.0,
      'very_low': 0.0,
    };
  }

  /// 현재 시점이 거래 시간인지 확인
  bool isTradingTime(String market) {
    return MarketTimeValidator.instance.isTradingTime(market);
  }

  /// 거래량 비율에 따른 점수 계산 (동적 임계값 적용, 시장별)
  double calculateVolumeScore(double volumeRatio, {String market = 'KOSPI', DateTime? customTime}) {
    final thresholds = getCurrentThresholds(market: market);
    final currentHour = customTime?.hour ?? DateTime.now().hour;
    
    // 백테스트 모드에서는 거래 시간 체크 비활성화
    if (customTime != null) {
      print('📊 백테스트 모드: 거래 시간 체크 비활성화 (${customTime.toString().substring(0, 10)})');
    } else {
      // 실시간 모드에서는 거래 시간 외에도 지표 계산 (매매 시그널만 제한)
      if (!isTradingTime(market)) {
        print('⚠️ 거래 시간 외: $market 시장 거래량 점수 계산 계속 (매매 시그널만 제한)');
        // 정규장 시간 외에도 지표는 계산하되 매매 시그널만 제한
      }
    }
    
    print('📊 거래량 점수 계산: 비율=${volumeRatio.toStringAsFixed(2)}, 시장=$market, 시간대=${getTimeSlotName(currentHour, market)}');
    print('📊 임계값: 높음=${thresholds['high']}, 중간=${thresholds['medium']}, 낮음=${thresholds['low']}, 매우낮음=${thresholds['very_low']}');
    
    if (volumeRatio >= thresholds['high']!) {
      return 1.0; // 거래량 급증
    } else if (volumeRatio >= thresholds['medium']!) {
      return 0.5; // 거래량 증가
    } else if (volumeRatio >= thresholds['low']!) {
      return 0.0; // 중립
    } else if (volumeRatio >= thresholds['very_low']!) {
      return -0.5; // 거래량 감소
    } else {
      return -1.0; // 거래량 급감
    }
  }

  /// 시간대별 거래량 패턴 분석
  Map<String, dynamic> analyzeVolumePattern(List<double> volumeHistory, {int days = 20}) {
    if (volumeHistory.isEmpty) {
      return {
        'avgVolume': 0.0,
        'volatility': 0.0,
        'trend': 'neutral',
        'pattern': 'insufficient_data',
      };
    }

    // 최근 N일간 거래량 데이터
    final recentVolumes = volumeHistory.take(days).toList();
    final avgVolume = recentVolumes.reduce((a, b) => a + b) / recentVolumes.length;
    
    // 변동성 계산
    final variance = recentVolumes.map((v) => pow(v - avgVolume, 2)).reduce((a, b) => a + b) / recentVolumes.length;
    final volatility = sqrt(variance);
    final coefficientOfVariation = avgVolume > 0 ? volatility / avgVolume : 0.0;
    
    // 추세 분석
    String trend = 'neutral';
    if (recentVolumes.length >= 5) {
      final recent5 = recentVolumes.take(5).toList();
      final older5 = recentVolumes.skip(recentVolumes.length - 5).take(5).toList();
      final recentAvg = recent5.reduce((a, b) => a + b) / recent5.length;
      final olderAvg = older5.reduce((a, b) => a + b) / older5.length;
      
      if (recentAvg > olderAvg * 1.2) {
        trend = 'increasing';
      } else if (recentAvg < olderAvg * 0.8) {
        trend = 'decreasing';
      }
    }
    
    // 패턴 분석
    String pattern = 'normal';
    if (coefficientOfVariation > 0.5) {
      pattern = 'high_volatility';
    } else if (coefficientOfVariation < 0.2) {
      pattern = 'low_volatility';
    }
    
    return {
      'avgVolume': avgVolume,
      'volatility': volatility,
      'coefficientOfVariation': coefficientOfVariation,
      'trend': trend,
      'pattern': pattern,
      'recentVolumes': recentVolumes,
    };
  }

  /// 거래량 임계값 동적 조정
  Map<String, double> getAdjustedThresholds(List<double> volumeHistory, {int days = 20}) {
    final baseThresholds = getCurrentThresholds();
    final pattern = analyzeVolumePattern(volumeHistory, days: days);
    
    // 변동성에 따른 조정 계수
    double adjustmentFactor = 1.0;
    if (pattern['pattern'] == 'high_volatility') {
      adjustmentFactor = 1.3; // 높은 변동성 시 임계값 상향
    } else if (pattern['pattern'] == 'low_volatility') {
      adjustmentFactor = 0.8; // 낮은 변동성 시 임계값 하향
    }
    
    // 추세에 따른 추가 조정
    if (pattern['trend'] == 'increasing') {
      adjustmentFactor *= 1.1; // 증가 추세 시 임계값 상향
    } else if (pattern['trend'] == 'decreasing') {
      adjustmentFactor *= 0.9; // 감소 추세 시 임계값 하향
    }
    
    return {
      'high': baseThresholds['high']! * adjustmentFactor,
      'medium': baseThresholds['medium']! * adjustmentFactor,
      'low': baseThresholds['low']! * adjustmentFactor,
      'very_low': baseThresholds['very_low']! * adjustmentFactor,
      'adjustmentFactor': adjustmentFactor,
    };
  }

  /// 시간대 이름 반환 (시장별)
  String getTimeSlotName(int hour, String market) {
    if (market == 'KOSPI' || market == 'KOSDAQ') {
      if (hour >= 9 && hour < 10) return '장시작';
      if (hour >= 10 && hour < 11) return '오전피크';
      if (hour >= 11 && hour < 13) return '점심시간';
      if (hour >= 13 && hour < 14) return '오후';
      if (hour >= 14 && hour < 15) return '장마감';
      if (hour == 15) return '장마감';
      return '거래시간외';
    } else if (market == 'NASDAQ') {
      if (hour >= 22) return '나스닥밤';
      if (hour >= 0 && hour < 2) return '나스닥자정';
      if (hour >= 2 && hour < 5) return '나스닥새벽';
      return '거래시간외';
    }
    return '거래시간외';
  }

  /// 거래량 점수 계산 (고급 버전 - 패턴 분석 포함)
  double calculateAdvancedVolumeScore(double currentVolume, List<double> volumeHistory, {int days = 20}) {
    final adjustedThresholds = getAdjustedThresholds(volumeHistory, days: days);
    final avgVolume = volumeHistory.isNotEmpty ? volumeHistory.take(days).reduce((a, b) => a + b) / min(days, volumeHistory.length) : currentVolume;
    final volumeRatio = avgVolume > 0 ? currentVolume / avgVolume : 1.0;
    
    print('📊 고급 거래량 점수 계산:');
    print('  - 현재 거래량: ${currentVolume.toStringAsFixed(0)}');
    print('  - 평균 거래량: ${avgVolume.toStringAsFixed(0)}');
    print('  - 거래량 비율: ${volumeRatio.toStringAsFixed(2)}');
    print('  - 조정 계수: ${adjustedThresholds['adjustmentFactor']!.toStringAsFixed(2)}');
    
    if (volumeRatio >= adjustedThresholds['high']!) {
      return 1.0; // 거래량 급증
    } else if (volumeRatio >= adjustedThresholds['medium']!) {
      return 0.5; // 거래량 증가
    } else if (volumeRatio >= adjustedThresholds['low']!) {
      return 0.0; // 중립
    } else if (volumeRatio >= adjustedThresholds['very_low']!) {
      return -0.5; // 거래량 감소
    } else {
      return -1.0; // 거래량 급감
    }
  }
}
