import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/stock_master_parser.dart';

/// 시장 거래 시간 기반 지표 검증 클래스 (싱글톤)
class MarketTimeValidator {
  static MarketTimeValidator? _instance;
  static MarketTimeValidator get instance => _instance ??= MarketTimeValidator._();
  
  MarketTimeValidator._();

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

  /// 종목코드로 시장 구분 (@api 마스터 데이터 기준 → 휴리스틱 폴백)
  String getMarketFromSymbol(String symbol) {
    print('🔍 시장 구분: 종목코드="$symbol", 길이=${symbol.length}');
    
    // 빈 문자열 체크
    if (symbol.isEmpty) {
      print('⚠️ 빈 종목코드 - 기본값 KOSPI 반환');
      return 'KOSPI';
    }

    // 1) 마스터 데이터 기준 우선 판별
    try {
      final parser = StockMasterParser();
      if (parser.isInitialized) {
        // 국내
        final isKospi = parser.getKospiStockCodes().contains(symbol);
        final isKosdaq = !isKospi && parser.getKosdaqStockCodes().contains(symbol);
        if (isKospi) {
          print('✅ [MASTER] KOSPI 매칭: $symbol');
          return 'KOSPI';
        }
        if (isKosdaq) {
          print('✅ [MASTER] KOSDAQ 매칭: $symbol');
          return 'KOSDAQ';
        }
        // 해외
        if (RegExp(r'^[A-Z]{1,6}$').hasMatch(symbol)) {
          final isNas = parser.getNasdaqStockCodes().contains(symbol);
          if (isNas) {
            print('✅ [MASTER] NASDAQ 매칭: $symbol');
            return 'NASDAQ';
          }
          final isNy = parser.getNyseStockCodes().contains(symbol);
          if (isNy) {
            print('✅ [MASTER] NYSE 매칭: $symbol');
            return 'NYSE';
          }
        }
      }
    } catch (_) {}

    // 2) 폴백 휴리스틱 (@api 미사용 시 안정적 분류)
    // 해외: 영문 1~5자리 → NASDAQ, 그 외 영문 → NYSE
    if (RegExp(r'^[A-Z]+$').hasMatch(symbol)) {
      if (symbol.length <= 5) {
        print('✅ [FALLBACK] 나스닥으로 판단: $symbol');
        return 'NASDAQ';
      }
      print('✅ [FALLBACK] NYSE로 판단: $symbol');
      return 'NYSE';
    }

    // 국내: 숫자 6자리 → 첫 자리 0이면 KOSPI, 나머지 KOSDAQ
    if (symbol.length == 6 && RegExp(r'^[0-9]+$').hasMatch(symbol)) {
      final firstDigit = int.parse(symbol[0]);
      if (firstDigit == 0) {
        print('✅ [FALLBACK] KOSPI로 판단: $symbol');
        return 'KOSPI';
      }
      print('✅ [FALLBACK] KOSDAQ으로 판단: $symbol');
      return 'KOSDAQ';
    }
    
    print('⚠️ 패턴 불일치 - 기본값 KOSPI 반환: $symbol');
    return 'KOSPI'; // 기본값
  }

  /// 현재 시점이 거래 시간인지 확인
  bool isTradingTime(String market) {
    final now = DateTime.now();
    final hour = now.hour;
    final minute = now.minute;
    final weekday = now.weekday; // 1=월요일, 7=일요일

    if (market == 'KOSPI' || market == 'KOSDAQ') {
      // 국내주식: 평일 09:00-15:30
      if (weekday == 6 || weekday == 7) return false; // 주말 휴장
      if (hour < 9) return false;
      if (hour > 15) return false;
      if (hour == 15 && minute > 30) return false;
      return true;
    } else if (market == 'NASDAQ') {
      // 나스닥: 월-금 22:30~다음날 05:00 (KR시간)
      if (weekday == 7) return false; // 일요일
      if (weekday == 6) {
        // 토요일 00:00~05:00은 금요일 세션 연장
        return hour < 5;
      }
      if (weekday == 5) {
        // 금요일: 22:30부터 시작
        return (hour > 22) || (hour == 22 && minute >= 30);
      }
      // 월~목
      if (hour >= 22 && (hour > 22 || minute >= 30)) return true; // 22:30~24:00
      if (hour < 5) return true; // 00:00~05:00
      return false;
    }

    return false;
  }

  /// 장 마감 여부
  bool isMarketClosed(String market) {
    return !isTradingTime(market);
  }

  /// 장중 초반 여부 (개장 1시간)
  bool isEarlySession(String market) {
    final now = DateTime.now();
    final hour = now.hour;
    final minute = now.minute;
    final int t = hour * 60 + minute;

    if (market == 'KOSPI' || market == 'KOSDAQ') {
      return t >= 9 * 60 && t < 10 * 60;
    }
    if (market == 'NASDAQ') {
      // 22:30~23:30
      final int start = 22 * 60 + 30;
      final int end = 23 * 60 + 30;
      final int tm = t;
      return tm >= start && tm < end;
    }
    return false;
  }

  /// 종목코드로 거래 시간 확인 (편의 메서드)
  bool isTradingTimeForSymbol(String symbol) {
    final market = getMarketFromSymbol(symbol);
    return isTradingTime(market);
  }

  /// 매매 신호 차단 여부 확인
  bool shouldBlockTradingSignal(String market, String signalType) {
    // 손절/익절은 정규장 시간 외에도 허용
    if (signalType == 'stop_loss' || signalType == 'take_profit') {
      return false;
    }
    
    // 긴급 매도는 정규장 시간 외에도 허용
    if (signalType == 'emergency_sell') {
      return false;
    }
    
    // 일반 매수/매도는 정규장 시간 체크
    return !isTradingTime(market);
  }

  /// 정규장 시간 외 매매 허용 여부 확인 (설정 기반)
  Future<bool> isOffHoursTradingAllowed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('allow_off_hours_trading') ?? false;
    } catch (e) {
      return false; // 기본값은 비활성화
    }
  }

  /// 정규장 시간 외 매수 주문 시도 허용 여부 확인 (테스트용)
  Future<bool> isOffHoursBuyOrderAllowed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allowed = prefs.getBool('allow_off_hours_buy_order') ?? true; // 기본값은 허용 (테스트용)
      print('🔧 정규장 시간 외 매수 주문 허용 설정: $allowed');
      return allowed;
    } catch (e) {
      print('⚠️ 설정 읽기 실패 - 기본값 허용으로 설정');
      return true; // 기본값은 허용
    }
  }

  /// 매매 신호 차단 여부 확인 (설정 고려)
  Future<bool> shouldBlockTradingSignalWithSettings(String market, String signalType) async {
    // 손절/익절은 정규장 시간 외에도 허용
    if (signalType == 'stop_loss' || signalType == 'take_profit') {
      return false;
    }
    
    // 긴급 매도는 정규장 시간 외에도 허용
    if (signalType == 'emergency_sell') {
      return false;
    }
    
    // 정규장 시간 내면 허용
    if (isTradingTime(market)) {
      return false;
    }
    
    // 정규장 시간 외이지만 설정에서 허용하면 허용
    if (await isOffHoursTradingAllowed()) {
      return false;
    }
    
    // 정규장 시간 외이고 설정에서도 비활성화면 차단
    return true;
  }

  /// 매수 주문 시도 허용 여부 확인 (실제 주문 전 체크)
  Future<bool> shouldAllowBuyOrder(String market) async {
    print('🔍 매수 주문 허용 여부 확인: 시장=$market');
    
    // 정규장 시간 내면 허용
    if (isTradingTime(market)) {
      print('✅ 정규장 시간 내 - 매수 주문 허용');
      return true;
    }
    
    // 정규장 시간 외이지만 매수 주문 시도 허용 설정이 있으면 허용
    if (await isOffHoursBuyOrderAllowed()) {
      print('⚠️ 정규장 시간 외이지만 매수 주문 시도 허용 (테스트/디버깅용)');
      return true;
    }
    
    print('❌ 정규장 시간 외 - 매수 주문 차단');
    return false;
  }

  /// 종목코드로 매매 신호 차단 여부 확인 (편의 메서드)
  bool shouldBlockTradingSignalForSymbol(String symbol, String signalType) {
    final market = getMarketFromSymbol(symbol);
    return shouldBlockTradingSignal(market, signalType);
  }

  /// 현재 거래 시간 정보 반환
  Map<String, dynamic> getCurrentTradingInfo(String market) {
    final now = DateTime.now();
    final hour = now.hour;
    final minute = now.minute;
    final weekday = now.weekday;
    
    print('🔍 거래시간 체크: 시장=$market, 요일=$weekday, 시간=${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}');
    
    final isTrading = isTradingTime(market);
    String status = '거래시간';
    String reason = '';
    
    if (!isTrading) {
      if (market == 'KOSPI' || market == 'KOSDAQ') {
        if (weekday == 6 || weekday == 7) {
          status = '거래시간외';
          reason = '주말';
        } else if (hour < 9) {
          status = '거래시간외';
          reason = '장 시작 전';
        } else if (hour > 15 || (hour == 15 && minute > 30)) {
          status = '거래시간외';
          reason = '장 마감 후';
        }
      } else if (market == 'NASDAQ') {
        if (weekday == 7) {
          status = '거래시간외';
          reason = '일요일';
        } else if (weekday == 6 && hour >= 5) {
          status = '거래시간외';
          reason = '토요일 장 마감 후';
        } else if (weekday == 5 && hour < 22) {
          status = '거래시간외';
          reason = '금요일 장 시작 전';
        } else if (weekday >= 1 && weekday <= 4) {
          if (hour >= 5 && hour < 22) {
            status = '거래시간외';
            reason = '평일 장 마감 후';
          }
        }
      }
    }
    
    print('📊 거래시간 결과: $status ($reason)');
    
    return {
      'isTrading': isTrading,
      'status': status,
      'reason': reason,
      'currentTime': '${weekday}요일 ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
      'market': market,
    };
  }

  /// 거래 시간 외 지표 신뢰도 조정
  double adjustIndicatorReliability(double originalScore, String market, String indicatorType) {
    if (isTradingTime(market)) {
      return originalScore; // 거래 시간 내: 원래 점수 유지
    }
    
    // 거래 시간 외: 지표별 신뢰도 조정
    switch (indicatorType) {
      case 'volume':
        return 0.0; // 거래량은 거래 시간 외에 의미 없음
      case 'price':
        return originalScore * 0.3; // 가격은 30% 신뢰도
      case 'rsi':
        return originalScore * 0.2; // RSI는 20% 신뢰도
      case 'macd':
        return originalScore * 0.2; // MACD는 20% 신뢰도
      case 'bollinger':
        return originalScore * 0.3; // 볼린저 밴드는 30% 신뢰도
      case 'stochastic':
        return originalScore * 0.2; // 스토캐스틱은 20% 신뢰도
      case 'moving_average':
        return originalScore * 0.4; // 이동평균은 40% 신뢰도
      case 'vix':
        return originalScore * 0.5; // VIX는 50% 신뢰도
      default:
        return originalScore * 0.3; // 기본값 30%
    }
  }

  /// 종합 점수 계산 시 거래 시간 고려
  double calculateTimeAdjustedScore(Map<String, double> indicatorScores, String market) {
    if (isTradingTime(market)) {
      // 거래 시간 내: 모든 지표 정상 가중
      return _calculateWeightedScore(indicatorScores);
    } else {
      // 거래 시간 외: 신뢰도 조정된 점수 계산
      final adjustedScores = <String, double>{};
      indicatorScores.forEach((indicator, score) {
        adjustedScores[indicator] = adjustIndicatorReliability(score, market, indicator);
      });
      return _calculateWeightedScore(adjustedScores);
    }
  }

  /// 가중 평균 점수 계산
  double _calculateWeightedScore(Map<String, double> scores) {
    if (scores.isEmpty) return 0.0;
    
    // 지표별 가중치 정의
    const weights = {
      'rsi': 0.15,
      'macd': 0.15,
      'bollinger': 0.15,
      'volume': 0.15,
      'moving_average': 0.10,
      'stochastic': 0.10,
      'vix': 0.10,
      'momentum': 0.10,
    };
    
    double weightedSum = 0.0;
    double totalWeight = 0.0;
    
    scores.forEach((indicator, score) {
      final weight = weights[indicator] ?? 0.1; // 기본 가중치 0.1
      weightedSum += score * weight;
      totalWeight += weight;
    });
    
    return totalWeight > 0 ? weightedSum / totalWeight : 0.0;
  }



  /// 시장별 거래 시간 정보 반환
  Map<String, dynamic> getMarketTradingInfo(String market) {
    final now = DateTime.now();
    final isTrading = isTradingTime(market);
    
    if (market == 'KOSPI' || market == 'KOSDAQ') {
      return {
        'market': market,
        'isTrading': isTrading,
        'tradingHours': '09:00-15:30',
        'currentTime': '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
        'nextTradingDay': _getNextTradingDay(),
      };
    } else if (market == 'NASDAQ') {
      return {
        'market': market,
        'isTrading': isTrading,
        'tradingHours': '22:30-05:00 (한국시간)',
        'currentTime': '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
        'nextTradingDay': _getNextTradingDay(),
      };
    }
    
    return {
      'market': market,
      'isTrading': false,
      'tradingHours': 'Unknown',
      'currentTime': '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      'nextTradingDay': _getNextTradingDay(),
    };
  }

  /// 다음 거래일 계산
  String _getNextTradingDay() {
    final now = DateTime.now();
    final weekday = now.weekday;
    
    if (weekday == 5) { // 금요일
      return '월요일'; // 다음주 월요일
    } else if (weekday == 6) { // 토요일
      return '월요일'; // 다음주 월요일
    } else if (weekday == 7) { // 일요일
      return '월요일'; // 다음주 월요일
    } else {
      return '내일';
    }
  }

  /// 지표별 거래 시간 외 신뢰도 설명
  String getIndicatorReliabilityDescription(String indicatorType, String market) {
    if (isTradingTime(market)) {
      return '거래 시간 내: 정상 신뢰도';
    }
    
    switch (indicatorType) {
      case 'volume':
        return '거래 시간 외: 거래량 지표 무의미 (0% 신뢰도)';
      case 'price':
        return '거래 시간 외: 가격 지표 신뢰도 30%';
      case 'rsi':
        return '거래 시간 외: RSI 지표 신뢰도 20%';
      case 'macd':
        return '거래 시간 외: MACD 지표 신뢰도 20%';
      case 'bollinger':
        return '거래 시간 외: 볼린저 밴드 신뢰도 30%';
      case 'stochastic':
        return '거래 시간 외: 스토캐스틱 신뢰도 20%';
      case 'moving_average':
        return '거래 시간 외: 이동평균 신뢰도 40%';
      case 'vix':
        return '거래 시간 외: VIX 신뢰도 50%';
      default:
        return '거래 시간 외: 기본 신뢰도 30%';
    }
  }
}
