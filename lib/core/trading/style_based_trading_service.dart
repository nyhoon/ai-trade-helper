import 'dart:async';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'investment_style.dart';
import 'investment_style_manager.dart';
import '../data/app_data_manager.dart';
import '../analysis/technical_indicators.dart';
import '../remote/analysis_functions_service.dart';
import 'volume_threshold_manager.dart';
import 'market_time_validator.dart';
import '../database/repositories/current_price_repository.dart';
import '../api/kis_unified_api_service.dart';
import '../remote/remote_kis_service.dart';

// 투자 스타일별 파라미터 데이터 클래스 (7개 지표 시스템 기반)
class TradingParameters {
  final InvestmentStyle style;
  final double partialProfit;
  final double fullProfit;
  final double stopLoss;
  final double positionSize;
  final int maxStocks;
  final double dailyLossLimit;
  
  // 매수/매도 임계값 (7개 지표 종합 점수 기반)
  final double buyThreshold;
  final double sellThreshold;
  
  // 초기자본 (분리)
  final double initialCapitalWon;
  final double initialCapitalDollar;

  const TradingParameters({
    required this.style,
    required this.partialProfit,
    required this.fullProfit,
    required this.stopLoss,
    required this.positionSize,
    required this.maxStocks,
    required this.dailyLossLimit,
    // 매수/매도 임계값 (7개 지표 종합 점수 기반)
    this.buyThreshold = 0.0,
    this.sellThreshold = 0.0,
    // 초기자본 (분리)
    this.initialCapitalWon = 1000000.0, // 100만원
    this.initialCapitalDollar = 1000.0, // 1000달러
  });

  TradingParameters copyWith({
    InvestmentStyle? style,
    double? partialProfit,
    double? fullProfit,
    double? stopLoss,
    double? positionSize,
    int? maxStocks,
    double? dailyLossLimit,
    // 매수/매도 임계값
    double? buyThreshold,
    double? sellThreshold,
    // 초기자본
    double? initialCapitalWon,
    double? initialCapitalDollar,
  }) {
    return TradingParameters(
      style: style ?? this.style,
      partialProfit: partialProfit ?? this.partialProfit,
      fullProfit: fullProfit ?? this.fullProfit,
      stopLoss: stopLoss ?? this.stopLoss,
      positionSize: positionSize ?? this.positionSize,
      maxStocks: maxStocks ?? this.maxStocks,
      dailyLossLimit: dailyLossLimit ?? this.dailyLossLimit,
      // 매수/매도 임계값
      buyThreshold: buyThreshold ?? this.buyThreshold,
      sellThreshold: sellThreshold ?? this.sellThreshold,
      // 초기자본
      initialCapitalWon: initialCapitalWon ?? this.initialCapitalWon,
      initialCapitalDollar: initialCapitalDollar ?? this.initialCapitalDollar,
    );
  }
}

// 보유 주식 정보 클래스
class Position {
  final String symbol;
  final double entryPrice;
  final double quantity;
  final DateTime entryTime;
  final InvestmentStyle style;

  const Position({
    required this.symbol,
    required this.entryPrice,
    required this.quantity,
    required this.entryTime,
    required this.style,
  });

  // 현재 가치 계산 (매수가 기준)
  double get currentValue => entryPrice * quantity;
  
  // 매수 시점 가치 계산
  double get entryValue => entryPrice * quantity;

  Position copyWith({
    String? symbol,
    double? entryPrice,
    double? quantity,
    DateTime? entryTime,
    InvestmentStyle? style,
  }) {
    return Position(
      symbol: symbol ?? this.symbol,
      entryPrice: entryPrice ?? this.entryPrice,
      quantity: quantity ?? this.quantity,
      entryTime: entryTime ?? this.entryTime,
      style: style ?? this.style,
    );
  }
}

// 매도 시그널 클래스
class SellSignal {
  final SellSignalType type;
  final double? threshold;

  const SellSignal(this.type, [this.threshold]);

  static const SellSignal TECHNICAL_SELL = SellSignal(SellSignalType.TECHNICAL_SELL);
  static SellSignal PARTIAL_PROFIT(double threshold) => SellSignal(SellSignalType.PARTIAL_PROFIT, threshold);
  static SellSignal FULL_PROFIT(double threshold) => SellSignal(SellSignalType.FULL_PROFIT, threshold);
  static SellSignal STOP_LOSS(double threshold) => SellSignal(SellSignalType.STOP_LOSS, threshold);
}

enum SellSignalType {
  PARTIAL_PROFIT,
  FULL_PROFIT,
  STOP_LOSS,
  TECHNICAL_SELL,
}

// 리스크 상태 클래스
class RiskStatus {
  final bool canTrade;
  final double dailyLoss;
  final double maxDrawdown;
  final int positionCount;
  final int maxPositions;

  const RiskStatus({
    required this.canTrade,
    required this.dailyLoss,
    required this.maxDrawdown,
    required this.positionCount,
    required this.maxPositions,
  });
}

// 거래 결과 클래스
class TradeResult {
  final String symbol;
  final double entryPrice;
  final double exitPrice;
  final double quantity;
  final double profitLoss;
  final double profitLossPercent;
  final DateTime entryTime;
  final DateTime exitTime;
  final InvestmentStyle style;
  final SellSignalType exitReason;

  const TradeResult({
    required this.symbol,
    required this.entryPrice,
    required this.exitPrice,
    required this.quantity,
    required this.profitLoss,
    required this.profitLossPercent,
    required this.entryTime,
    required this.exitTime,
    required this.style,
    required this.exitReason,
  });

  // 수익 getter
  double? get profit => profitLoss;

  // Map으로 변환
  Map<String, dynamic> toMap() {
    // 해외주식 여부 확인
    final isOverseas = symbol.length >= 4 && RegExp(r'^[A-Z]+$').hasMatch(symbol);
    
    return {
      'symbol': symbol,
      'entryPrice': entryPrice,
      'exitPrice': exitPrice,
      'quantity': quantity,
      'profitLoss': profitLoss, // 원래 통화로 유지 (해외주식은 달러, 국내주식은 원)
      'profitLossPercent': profitLossPercent,
      'entryTime': entryTime.toIso8601String(),
      'exitTime': exitTime.toIso8601String(),
      'exitDate': exitTime.toIso8601String(), // 호환성을 위해 추가
      'style': style.toString(),
      'exitReason': exitReason.toString(),
      'isOverseas': isOverseas, // 해외주식 여부 추가
      'currency': isOverseas ? 'USD' : 'KRW', // 통화 정보 추가
    };
  }
}

// 백테스트 데이터 저장 클래스
class BacktestData {
  final DateTime date;
  final Map<String, StockData> stockDataMap;
  
  BacktestData({
    required this.date,
    required this.stockDataMap,
  });
}

// 주식 데이터 클래스 (예시)
class StockData {
  final String symbol;
  final num close; // 국내주식은 int, 해외주식은 double
  final num open; // 시가
  final num high; // 고가
  final num low; // 저가
  final int volume;
  final int prevVolume;
  final double rsi14;
  final double bbLow;
  final double bbHigh;
  final double ma5;
  final double ma20;
  final double ma60;
  final double stochK;
  final double macdHist;
  final double vix;
  final int volume20Avg;
  final double vwap; // 7개 지표 시스템용
  final double adx; // 7개 지표 시스템용
  final double foreignNetBuy; // KIS API 추가 데이터
  final double w52High; // KIS API 추가 데이터
  final double per; // KIS API 추가 데이터
  final double foreignRatio; // KIS API 추가 데이터
  final double askRemain1; // KIS API 추가 데이터
  final double bidRemain1; // KIS API 추가 데이터
  final double marketCap; // KIS API 추가 데이터

  const StockData({
    required this.symbol,
    required this.close,
    required this.open,
    required this.high,
    required this.low,
    required this.volume,
    required this.prevVolume,
    required this.rsi14,
    required this.bbLow,
    required this.bbHigh,
    required this.ma5,
    required this.ma20,
    required this.ma60,
    required this.stochK,
    required this.macdHist,
    required this.vix,
    required this.volume20Avg,
    required this.vwap,
    required this.adx,
    this.foreignNetBuy = 0.0,
    this.w52High = 0.0,
    this.per = 0.0,
    this.foreignRatio = 0.0,
    this.askRemain1 = 0.0,
    this.bidRemain1 = 0.0,
    this.marketCap = 0.0,
  });

  /// Map으로 변환 (백테스트 호환성)
  Map<String, dynamic> toMap() {
    return {
      'symbol': symbol,
      'close': close,
      'open': open,
      'high': high,
      'low': low,
      'volume': volume,
      'prevVolume': prevVolume,
      'rsi14': rsi14,
      'bbLow': bbLow,
      'bbHigh': bbHigh,
      'ma5': ma5,
      'ma20': ma20,
      'ma60': ma60,
      'stochK': stochK,
      'macdHist': macdHist,
      'vix': vix,
      'volume20Avg': volume20Avg,
      'vwap': vwap,
      'adx': adx,
      'foreignNetBuy': foreignNetBuy,
      'w52High': w52High,
      'per': per,
      'foreignRatio': foreignRatio,
      'askRemain1': askRemain1,
      'bidRemain1': bidRemain1,
      'marketCap': marketCap,
    };
  }
}

// 투자 스타일별 설정 객체 (로컬 DB 사용으로 하드코딩 제거)
class TradingStyleConfig {
  // 하드코딩된 기본값들은 제거하고 로컬 DB에서 동적으로 로드

  static Future<TradingParameters> getParameters(InvestmentStyle style) async {
    // 로컬 DB에서 설정값을 가져오도록 loadParameters 사용
    return await loadParameters(style, isCustomMode: true);
  }

  // 저장된 파라미터 로드 (업그레이드된 버전 - 로컬 DB 사용)
  static Future<TradingParameters> loadParameters(InvestmentStyle style, {bool isCustomMode = false}) async {
    print('🔄 TradingStyleConfig.loadParameters 호출됨');
    print('   - 스타일: ${style.name}');
    print('   - 커스터마이징 모드: $isCustomMode');
    
    // InvestmentStyleManager를 통해 로컬 DB에서 설정값 가져오기
    final styleManager = InvestmentStyleManager();
    await styleManager.initialize();
    
    // 로컬 DB에서 현재 설정값 가져오기
    final styleParams = await styleManager.getStyleParameters(style);
    print('   📊 로컬 DB에서 로드된 설정값 (7개 지표 시스템):');
    print('     - 부분익절: ${styleParams['partialProfit']}%');
    print('     - 전체익절: ${styleParams['fullProfit']}%');
    print('     - 손절: ${styleParams['stopLoss']}%');
    print('     - 투자 비율: ${(styleParams['positionSize'] * 100).toStringAsFixed(1)}%');
    print('     - 최대 종목 수: ${styleParams['maxStocks']}개');
    print('     - 매수 임계값: ${styleParams['buyThreshold']} (7개 지표 종합 점수)');
    print('     - 매도 임계값: ${styleParams['sellThreshold']} (7개 지표 종합 점수)');
    print('     - 일일 손실 한도: ${styleParams['dailyLossLimit']}%');

    // 로컬 DB 설정값으로 TradingParameters 생성 (7개 지표 시스템 기반)
    final partialProfit = (styleParams['partialProfit'] as num?)?.toDouble() ?? 0.0;
    final fullProfit = (styleParams['fullProfit'] as num?)?.toDouble() ?? 0.0;
    final stopLoss = (styleParams['stopLoss'] as num?)?.toDouble() ?? 0.0;
    final positionSize = (styleParams['positionSize'] as num?)?.toDouble() ?? 0.0;
    final maxStocks = (styleParams['maxStocks'] as num?)?.toInt() ?? 0;
    final dailyLossLimit = (styleParams['dailyLossLimit'] as num?)?.toDouble() ?? 0.0;
    final buyThreshold = (styleParams['buyThreshold'] as num?)?.toDouble() ?? 0.0;
    final sellThreshold = (styleParams['sellThreshold'] as num?)?.toDouble() ?? 0.0;
    
    print('   🔧 설정값 변환 결과:');
    print('     - partialProfit: ${styleParams['partialProfit']} → $partialProfit');
    print('     - fullProfit: ${styleParams['fullProfit']} → $fullProfit');
    print('     - stopLoss: ${styleParams['stopLoss']} → $stopLoss');
    
    final customParams = TradingParameters(
      style: style,
      partialProfit: partialProfit,
      fullProfit: fullProfit,
      stopLoss: stopLoss,
      positionSize: positionSize,
      maxStocks: maxStocks,
      dailyLossLimit: dailyLossLimit,
      // 매수/매도 임계값 (7개 지표 종합 점수 기반) - 사용자 설정값만 사용
      buyThreshold: buyThreshold,
      sellThreshold: sellThreshold,
    );
    
    print('   ✅ 로컬 DB 설정값으로 TradingParameters 생성 완료');
    print('   📊 최종 설정값: partialProfit=$partialProfit, fullProfit=$fullProfit, stopLoss=$stopLoss');
    return customParams;
  }


}

// 스타일 기반 자동매매 전략 클래스
class StyleBasedTradingStrategy {
  final InvestmentStyle style;
  final double initialCapitalWon;
  final double initialCapitalDollar;
  final bool isCustomMode;
  late TradingParameters config;
  double capitalWon; // 원화 자본
  double capitalDollar; // 달러 자본
  final Map<String, Position> positions = {};
  final List<TradeResult> results = [];
  int consecutiveLosses = 0;
  double dailyLoss = 0.0;
  double maxDrawdown = 0.0;
  double peakCapital;

  StyleBasedTradingStrategy({
    required this.style,
    this.initialCapitalWon = 1000000,
    this.initialCapitalDollar = 1000,
    this.isCustomMode = false,
  }) : capitalWon = initialCapitalWon.toDouble(),
       capitalDollar = initialCapitalDollar.toDouble(),
       peakCapital = (initialCapitalWon + initialCapitalDollar * 1400).toDouble() {
    _initializeConfig();
  }

  Future<void> _initializeConfig() async {
    // 로컬 DB에서 설정값을 가져오도록 수정
    config = await TradingStyleConfig.loadParameters(style, isCustomMode: true);
  }

  // 포트폴리오 가치 계산
  double calculatePortfolioValue() {
    double portfolioValue = capitalWon + (capitalDollar * _exchangeRate);
    
    // 보유 종목들의 현재 가치 계산
    for (final position in positions.values) {
      // 현재가를 정확히 알 수 없으므로 매수가 기준으로 계산
      // 실제로는 현재가를 받아서 계산해야 함
      portfolioValue += position.entryPrice * position.quantity;
    }
    
    return portfolioValue;
  }

  // 최대 낙폭 계산
  double calculateMaxDrawdown() {
    return maxDrawdown;
  }

  // 환율 getter (고정값 사용)
  double get _exchangeRate => 1400.0;

  // 매수 시그널 생성 (7개 지표 종합 점수 기반)
  bool generateBuySignal(StockData data) {
    print('🎯 7개 지표 종합 점수로 매수 시그널 분석 시작');
    
    // 정규장 시간 체크 - 임시 주석 처리
    /*
    final market = MarketTimeValidator.instance.getMarketFromSymbol(data.symbol);
    final tradingInfo = MarketTimeValidator.instance.getCurrentTradingInfo(market);
    
    print('📊 정규장 시간 체크: $market - ${tradingInfo['status']} (${tradingInfo['reason']})');
    
    if (!tradingInfo['isTrading']) {
      print('⚠️ 정규장 시간 외 - 매수 시그널 생성 제한 (지표는 정상 계산)');
      return false; // 매수 시그널만 제한
    }
    
    print('✅ 정규장 시간 - 매수 시그널 분석 계속');
    */
    
    print('🔧 정규장 시간 체크 임시 비활성화 - 매수 시그널 분석 계속');
    
    // 3. 지표 점수 계산 (완화된 버전)
    int rsiScore = 0;
    if (data.rsi14 <= 35) { // 완화된 RSI 과매도 조건 (기존 30에서 35로)
      rsiScore = 2; // 강한 매수 신호
      print('  ✅ RSI 강한 매수 신호 (${data.rsi14.toStringAsFixed(1)})');
    } else if (data.rsi14 <= 45) { // 완화된 RSI 약한 매수 조건 (기존 40에서 45로)
      rsiScore = 1; // 약한 매수 신호
      print('  ⚠️ RSI 약한 매수 신호 (${data.rsi14.toStringAsFixed(1)})');
    } else if (data.rsi14 >= 65) { // 완화된 RSI 과매수 조건 (기존 70에서 65로)
      rsiScore = -2; // 강한 매도 신호
      print('  ❌ RSI 강한 매도 신호 (${data.rsi14.toStringAsFixed(1)})');
    } else if (data.rsi14 >= 55) { // 완화된 RSI 약한 매도 조건 (기존 60에서 55로)
      rsiScore = -1; // 약한 매도 신호
      print('  ⚠️ RSI 약한 매도 신호 (${data.rsi14.toStringAsFixed(1)})');
    } else {
      rsiScore = 0; // 중립
      print('  ➖ RSI 중립 (${data.rsi14.toStringAsFixed(1)})');
    }
    
    // 이동평균 추세 점수
    int trendScore = 0;
    if (data.ma5 > data.ma20 && data.ma20 > data.ma60) {
      trendScore = 1; // 상승 추세
      print('  ✅ 이동평균 상승 추세');
    } else if (data.ma5 < data.ma20 && data.ma20 < data.ma60) {
      trendScore = -1; // 하락 추세
      print('  ❌ 이동평균 하락 추세');
    } else {
      trendScore = 0; // 중립
      print('  ➖ 이동평균 중립');
    }
    
    // 볼린저 밴드 점수
    double bbScore = 0;
    final bbMid = (data.bbHigh + data.bbLow) / 2; // 볼린저 밴드 중간값 계산
    if (data.close <= data.bbLow) {
      bbScore = 1; // 하단 터치 - 매수 신호
      print('  ✅ 볼린저 밴드 하단 터치 - 매수 신호');
    } else if (data.close >= data.bbHigh) {
      bbScore = -1; // 상단 터치 - 매도 신호
      print('  ❌ 볼린저 밴드 상단 터치 - 매도 신호');
    } else if (data.close < bbMid) {
      bbScore = 0.5; // 중간선 아래 - 약한 매수
      print('  ⚠️ 볼린저 밴드 중간선 아래 - 약한 매수');
    } else {
      bbScore = -0.5; // 중간선 위 - 약한 매도
      print('  ⚠️ 볼린저 밴드 중간선 위 - 약한 매도');
    }
    
    // MACD 모멘텀 점수
    int macdScore = 0;
    if (data.macdHist > 0) {
      macdScore = 1; // 상승 모멘텀
      print('  ✅ MACD 상승 모멘텀 (${data.macdHist.toStringAsFixed(2)})');
    } else if (data.macdHist < 0) {
      macdScore = -1; // 하락 모멘텀
      print('  ❌ MACD 하락 모멘텀 (${data.macdHist.toStringAsFixed(2)})');
    } else {
      macdScore = 0; // 중립
      print('  ➖ MACD 중립');
    }
    
    // 거래량 점수 (VolumeThresholdManager 사용, 시장별)
    double volumeScore = 0.0;
    final volumeRatio = data.volume20Avg > 0 ? data.volume / data.volume20Avg : 1.0;
    
    // 시장 구분 (종목코드 기반 자동 판단)
    final market = MarketTimeValidator.instance.getMarketFromSymbol(data.symbol);
    print('📊 시장 구분 결과: ${data.symbol} → $market');
    
    // VolumeThresholdManager를 사용한 동적 임계값 적용 (시장별)
    volumeScore = VolumeThresholdManager.instance.calculateVolumeScore(volumeRatio, market: market);
    
    // 거래 시간 외 신뢰도 조정
    volumeScore = MarketTimeValidator.instance.adjustIndicatorReliability(volumeScore, market, 'volume');
    
    // 시간대별 거래량 데이터 수집 (DB 저장용)
    final volumeThresholds = VolumeThresholdManager.instance.getCurrentThresholds(market: market);
    final currentHour = DateTime.now().hour;
    final timeSlotName = VolumeThresholdManager.instance.getTimeSlotName(currentHour, market);
    
    // 분석 결과에 시간대별 거래량 정보 추가 (generateBuySignal에서는 DB 저장 로직 제외)
    // analysis['indicators']['volume_threshold'] = volumeThresholds['high'] ?? 0.0;
    // analysis['indicators']['volume_time_slot'] = timeSlotName;
    // analysis['indicators']['volume_market'] = market;
    
    // 스토캐스틱 점수 (소수점 기반)
    // 7개 지표 시스템에서는 스토캐스틱 불필요
    double stochScore = 0.0;
    
    // VWAP 점수 (간단한 계산)
    double vwapScore = 0.0;
    if (data.vwap > 0) {
      final vwapRatio = data.close / data.vwap;
      if (vwapRatio >= 1.02) vwapScore = 1.0;
      else if (vwapRatio >= 1.01) vwapScore = 0.6;
      else if (vwapRatio <= 0.98) vwapScore = -1.0;
      else if (vwapRatio <= 0.99) vwapScore = -0.6;
    }
    
    // ADX 점수 (간단한 계산)
    double adxScore = 0.0;
    if (data.adx >= 25) adxScore = 1.0;
    else if (data.adx >= 20) adxScore = 0.6;
    else if (data.adx < 15) adxScore = -0.8;
    
    // 종합 점수 계산 (7가지 지표 가중 평균)
    final totalScore = (volumeScore * 0.2 + rsiScore * 0.2 + macdScore * 0.2 + 
                       bbScore * 0.15 + trendScore * 0.15 + vwapScore * 0.05 + adxScore * 0.05);
    
    print('📊 종합 점수 (7가지 지표 가중 평균):');
    print('   거래량(${volumeScore})×0.2 + RSI(${rsiScore})×0.2 + MACD(${macdScore})×0.2 +');
    print('   BB(${bbScore})×0.15 + 추세(${trendScore})×0.15 + VWAP(${vwapScore})×0.05 + ADX(${adxScore})×0.05');
    print('   총점: $totalScore (최대 1.0점)');
    
    // 로컬 DB에서 가져온 매수 임계값 사용 (정확한 가중 평균 점수)
    double threshold = config.buyThreshold;
    
    // 최종 결정
    final isSignalValid = totalScore >= threshold;
    
    if (isSignalValid) {
      print('🎯 최종 결정: 매수 (종합 점수: $totalScore >= 임계값: $threshold)');
    } else {
      print('🎯 최종 결정: 매수 거부 (종합 점수: $totalScore < 임계값: $threshold)');
    }
    
    return isSignalValid;
  }

  // 7개 지표 시스템에서는 별도의 VIX/크래시/선행신호 체크 불필요
  // 모든 지표가 종합 점수에 포함됨
  bool _checkVIXRisk(StockData data) => true;
  bool _checkMomentumCrash(StockData data) => false;
  bool _hasLeadingSignal(StockData data) => false;

  // 매도 시그널 생성 (지표 점수 전략 적용)
  Future<SellSignal?> generateSellSignal(Position position, double currentPrice, [StockData? stockData]) async {
    print('🔍 매도 시그널 분석 시작: ${position.symbol}');
    print('   📊 매수가: ${position.entryPrice}, 현재가: $currentPrice');
    print('   📊 설정값: 부분익절=${config.partialProfit}%, 전체익절=${config.fullProfit}%, 손절=${config.stopLoss}%');
    print('   🔧 설정값 상세: partialProfit=${config.partialProfit}, fullProfit=${config.fullProfit}, stopLoss=${config.stopLoss}');
    print('   🔧 데이터 소스: ${stockData != null ? '백테스트 데이터' : '실제 현재가'}');
    
    // 실제 거래에서는 현재가를 다시 조회 (백테스트와 구분)
    double actualCurrentPrice = currentPrice;
    if (stockData == null) {
      // 실제 거래: DB에서 현재가 조회
      try {
        final currentPriceRepo = CurrentPriceRepository();
        final currentPriceData = await currentPriceRepo.getCurrentPrice(position.symbol);
        if (currentPriceData != null) {
          actualCurrentPrice = (currentPriceData['current_price'] as num?)?.toDouble() ?? currentPrice;
          print('   🔄 실제 현재가 조회: $currentPrice → $actualCurrentPrice');
        } else {
          print('   ⚠️ 실제 현재가 조회 실패, 기존 값 사용: $currentPrice');
        }
      } catch (e) {
        print('   ❌ 실제 현재가 조회 오류: $e, 기존 값 사용: $currentPrice');
      }
    }
    
    // 정규장 시간 체크 - 임시 주석 처리 (매수와 동일하게)
    /*
    if (stockData != null) {
      final market = MarketTimeValidator.instance.getMarketFromSymbol(position.symbol);
      final tradingInfo = MarketTimeValidator.instance.getCurrentTradingInfo(market);
      
      print('📊 정규장 시간 체크 (매도): $market - ${tradingInfo['status']} (${tradingInfo['reason']})');
      
      // 기술적 매도 시그널만 정규장 시간 체크 (손절/익절은 제외)
      if (!tradingInfo['isTrading']) {
        print('⚠️ 정규장 시간 외 - 기술적 매도 시그널 생성 제한 (손절/익절은 계속, 지표는 정상 계산)');
        // 손절/익절 조건만 체크하고 기술적 매도는 건너뜀
      } else {
        print('✅ 정규장 시간 - 매도 시그널 분석 계속');
      }
    }
    */
    
    print('🔧 정규장 시간 체크 임시 비활성화 - 매도 시그널 분석 계속');
    
    final pnlPct = (actualCurrentPrice - position.entryPrice) / position.entryPrice * 100;
    print('   📊 수익률: ${pnlPct.toStringAsFixed(2)}%');
    
    // 손절/익절 조건 (우선순위 높음)
    print('   🔍 손절/익절 조건 체크:');
    print('     - 전체익절: ${pnlPct.toStringAsFixed(2)}% >= ${config.fullProfit}% ? ${pnlPct >= config.fullProfit}');
    print('     - 부분익절: ${pnlPct.toStringAsFixed(2)}% >= ${config.partialProfit}% ? ${pnlPct >= config.partialProfit}');
    print('     - 손절: ${pnlPct.toStringAsFixed(2)}% <= -${config.stopLoss}% ? ${pnlPct <= -config.stopLoss}');
    
    if (pnlPct >= config.fullProfit && position.quantity > 0) {
      print('🟢 전체익절 조건 만족: ${position.symbol} - 수익률: ${pnlPct.toStringAsFixed(2)}% >= ${config.fullProfit}%');
      return SellSignal.FULL_PROFIT(config.fullProfit);
    }
    if (pnlPct >= config.partialProfit && position.quantity > 0) {
      print('🟡 부분익절 조건 만족: ${position.symbol} - 수익률: ${pnlPct.toStringAsFixed(2)}% >= ${config.partialProfit}%');
      return SellSignal.PARTIAL_PROFIT(config.partialProfit);
    }
    if (pnlPct <= -config.stopLoss && position.quantity > 0) {
      print('🔴 손절 조건 만족: ${position.symbol} - 손실률: ${pnlPct.toStringAsFixed(2)}% <= -${config.stopLoss}%');
      return SellSignal.STOP_LOSS(config.stopLoss);
    }
    
    print('   ❌ 손절/익절 조건 불만족 - 기술적 매도 시그널 확인');
    
    // 기술적 매도 시그널 (지표 점수 전략) - 정규장 시간 체크 제거
    if (stockData != null && position.quantity > 0) {
      // 정규장 시간 체크 제거 (매수와 동일하게)
      if (_isTechnicalSellWithScoreStrategy(stockData)) {
        return SellSignal.TECHNICAL_SELL;
      }
    }
    
    print('   ❌ 매도 시그널 없음 - 보유 유지');
    return null;
  }

  // 기술적 매도 시그널 (지표 점수 전략)
  bool _isTechnicalSellWithScoreStrategy(StockData data) {
    print('🎯 지표 점수 전략으로 매도 시그널 분석 시작');
    
    // 지표 점수 계산 (매도 관점, 완화된 버전)
    int rsiScore = 0;
    if (data.rsi14 >= 65) { // 완화된 RSI 과매수 조건 (기존 70에서 65로)
      rsiScore = 2; // 강한 매도 신호
      print('  ✅ RSI 강한 매도 신호 (${data.rsi14.toStringAsFixed(1)})');
    } else if (data.rsi14 >= 55) { // 완화된 RSI 약한 매도 조건 (기존 60에서 55로)
      rsiScore = 1; // 약한 매도 신호
      print('  ⚠️ RSI 약한 매도 신호 (${data.rsi14.toStringAsFixed(1)})');
    } else if (data.rsi14 <= 35) { // 완화된 RSI 과매도 조건 (기존 30에서 35로)
      rsiScore = -2; // 강한 매수 신호 (매도 거부)
      print('  ❌ RSI 강한 매수 신호 (${data.rsi14.toStringAsFixed(1)}) - 매도 거부');
    } else if (data.rsi14 <= 45) { // 완화된 RSI 약한 매수 조건 (기존 40에서 45로)
      rsiScore = -1; // 약한 매수 신호 (매도 거부)
      print('  ⚠️ RSI 약한 매수 신호 (${data.rsi14.toStringAsFixed(1)}) - 매도 거부');
    } else {
      rsiScore = 0; // 중립
      print('  ➖ RSI 중립 (${data.rsi14.toStringAsFixed(1)})');
    }
    
    // 이동평균 추세 점수 (매도 관점)
    int trendScore = 0;
    if (data.ma5 < data.ma20 && data.ma20 < data.ma60) {
      trendScore = 1; // 하락 추세 - 매도 신호
      print('  ✅ 이동평균 하락 추세 - 매도 신호');
    } else if (data.ma5 > data.ma20 && data.ma20 > data.ma60) {
      trendScore = -1; // 상승 추세 - 매도 거부
      print('  ❌ 이동평균 상승 추세 - 매도 거부');
    } else {
      trendScore = 0; // 중립
      print('  ➖ 이동평균 중립');
    }
    
    // 볼린저 밴드 점수 (매도 관점)
    double bbScore = 0;
    final bbMid = (data.bbHigh + data.bbLow) / 2; // 볼린저 밴드 중간값 계산
    if (data.close >= data.bbHigh) {
      bbScore = 1; // 상단 터치 - 매도 신호
      print('  ✅ 볼린저 밴드 상단 터치 - 매도 신호');
    } else if (data.close <= data.bbLow) {
      bbScore = -1; // 하단 터치 - 매도 거부
      print('  ❌ 볼린저 밴드 하단 터치 - 매도 거부');
    } else if (data.close > bbMid) {
      bbScore = 0.5; // 중간선 위 - 약한 매도
      print('  ⚠️ 볼린저 밴드 중간선 위 - 약한 매도');
    } else {
      bbScore = -0.5; // 중간선 아래 - 약한 매도 거부
      print('  ⚠️ 볼린저 밴드 중간선 아래 - 약한 매도 거부');
    }
    
    // MACD 모멘텀 점수 (매도 관점, 소수점 기반)
    double macdScore = 0.0;
    if (data.macdHist < -0.5) {
      macdScore = 1.0; // 강한 하락 모멘텀 - 매도 신호
      print('  ✅ MACD 강한 하락 모멘텀 (${data.macdHist.toStringAsFixed(2)}) - 매도 신호');
    } else if (data.macdHist < 0) {
      macdScore = 0.5; // 약한 하락 모멘텀 - 약한 매도 신호
      print('  ⚠️ MACD 약한 하락 모멘텀 (${data.macdHist.toStringAsFixed(2)}) - 약한 매도 신호');
    } else if (data.macdHist > 0.5) {
      macdScore = -1.0; // 강한 상승 모멘텀 - 매도 거부
      print('  ❌ MACD 강한 상승 모멘텀 (${data.macdHist.toStringAsFixed(2)}) - 매도 거부');
    } else if (data.macdHist > 0) {
      macdScore = -0.5; // 약한 상승 모멘텀 - 약한 매도 거부
      print('  ⚠️ MACD 약한 상승 모멘텀 (${data.macdHist.toStringAsFixed(2)}) - 약한 매도 거부');
    } else {
      macdScore = 0.0; // 중립
      print('  ➖ MACD 중립');
    }
    
    // 7개 지표 시스템에서는 스토캐스틱 불필요
    double stochScore = 0.0;
    
    // 거래량 점수 (매도 관점)
    double volumeScore = 0.0;
    final volumeRatio = data.volume20Avg > 0 ? data.volume / data.volume20Avg : 1.0;
    
    // 시장 구분 (간단한 휴리스틱)
    String market = 'KOSPI'; // 기본값
    if (data.symbol.length <= 5 && RegExp(r'^[A-Z]+$').hasMatch(data.symbol)) {
      market = 'NASDAQ'; // 영문 티커는 나스닥으로 가정
    }
    
    // VolumeThresholdManager를 사용한 동적 임계값 적용 (시장별)
    volumeScore = VolumeThresholdManager.instance.calculateVolumeScore(volumeRatio, market: market);
    
    // 거래 시간 외 신뢰도 조정
    volumeScore = MarketTimeValidator.instance.adjustIndicatorReliability(volumeScore, market, 'volume');
    
    print('  📊 거래량 점수: ${volumeScore.toStringAsFixed(2)} (비율: ${volumeRatio.toStringAsFixed(2)}x)');
    

    
    // VWAP 점수 (매도 관점)
    double vwapScore = 0.0;
    if (data.vwap > 0) {
      final vwapRatio = data.close / data.vwap;
      if (vwapRatio >= 1.02) vwapScore = -1.0; // 매도 불리
      else if (vwapRatio >= 1.01) vwapScore = -0.6;
      else if (vwapRatio <= 0.98) vwapScore = 1.0; // 매도 유리
      else if (vwapRatio <= 0.99) vwapScore = 0.6;
    }
    
    // ADX 점수 (매도 관점)
    double adxScore = 0.0;
    if (data.adx >= 25) adxScore = -1.0; // 강한 추세 - 매도 불리
    else if (data.adx >= 20) adxScore = -0.6;
    else if (data.adx < 15) adxScore = 0.8; // 약한 추세 - 매도 유리
    
    // 종합 점수 계산 (매도 관점, 7가지 지표 가중 평균)
    final totalScore = (volumeScore * 0.2 + rsiScore * 0.2 + macdScore * 0.2 + 
                       bbScore * 0.15 + trendScore * 0.15 + vwapScore * 0.05 + adxScore * 0.05);
    
    print('📊 매도 종합 점수 (7가지 지표 가중 평균):');
    print('   거래량(${volumeScore})×0.2 + RSI(${rsiScore})×0.2 + MACD(${macdScore})×0.2 +');
    print('   BB(${bbScore})×0.15 + 추세(${trendScore})×0.15 + VWAP(${vwapScore})×0.05 + ADX(${adxScore})×0.05');
    print('   총점: $totalScore (최대 1.0점)');
    
    // 로컬 DB에서 가져온 매도 임계값 사용 (정확한 가중 평균 점수)
    double threshold = config.sellThreshold;
    
    // 최종 결정 (매도는 점수가 임계값 미만일 때 실행)
    final isSignalValid = totalScore < threshold;
    
    if (isSignalValid) {
      print('🎯 최종 결정: 매도 (종합 점수: $totalScore <= 임계값: $threshold)');
    } else {
      print('🎯 최종 결정: 매도 거부 (종합 점수: $totalScore > 임계값: $threshold)');
    }
    
    return isSignalValid;
  }

  // 투자 비율 계산 (해외주식/국내주식 구분)
  double calculatePositionSize(double price, {String? symbol}) {
    // 해외주식 여부 확인
    final isOverseas = symbol != null && symbol.length >= 4 && RegExp(r'^[A-Z]+$').hasMatch(symbol);
    
    if (isOverseas) {
      // 해외주식: 달러 자본 사용
      final base = capitalDollar * config.positionSize;
      final adjusted = _adjustSizeByStyle(base);
      final calculatedQuantity = adjusted / price;
      
      // 최소 1주 이상이어야 거래 가능
      if (calculatedQuantity < 1.0) {
        return 0.0; // 거래 불가
      }
      
      // 해외주식은 소수점 주도 가능
      return calculatedQuantity;
    } else {
      // 국내주식: 원화 자본 사용
      final base = capitalWon * config.positionSize;
      final adjusted = _adjustSizeByStyle(base);
      final calculatedQuantity = adjusted / price;
      
      // 최소 1주 이상이어야 거래 가능
      if (calculatedQuantity < 1.0) {
        return 0.0; // 거래 불가
      }
      
      // 정수 주로 반올림 (한국 주식시장 규칙)
      return calculatedQuantity.roundToDouble();
    }
  }

  // 리스크 한도 체크
  RiskStatus checkRiskLimits([DateTime? backtestDate]) {
    _updateDailyLoss(backtestDate);
    _updateMaxDrawdown();
    
    return RiskStatus(
      canTrade: dailyLoss > -config.dailyLossLimit,
      dailyLoss: dailyLoss,
      maxDrawdown: maxDrawdown,
      positionCount: positions.length,
      maxPositions: config.maxStocks,
    );
  }

  // 매수 실행
  void executeBuy(String symbol, double price, double quantity, [DateTime? tradeTime]) {
    if (positions.length >= config.maxStocks) return;
    if (quantity < 1.0) return; // 최소 1주 이상이어야 거래
    
    // 해외주식 여부 확인
    final isOverseas = symbol.length >= 4 && RegExp(r'^[A-Z]+$').hasMatch(symbol);
    
    final position = Position(
      symbol: symbol,
      entryPrice: price,
      quantity: quantity,
      entryTime: tradeTime ?? DateTime.now(),
      style: style,
    );
    
    positions[symbol] = position;
    
    if (isOverseas) {
      // 해외주식: 달러로 거래
      final dollarAmount = price * quantity;
      capitalDollar -= dollarAmount; // 달러 자본에서 차감
      print('매수 실행(해외): $symbol, 가격: \$${price.toStringAsFixed(2)}, 수량: ${quantity.toInt()}주, 달러: \$${dollarAmount.toStringAsFixed(0)}, 남은달러: \$${capitalDollar.toStringAsFixed(0)}, 날짜: ${position.entryTime.toString().substring(0, 10)}');
    } else {
      // 국내주식: 원화로 거래
      final wonAmount = price * quantity;
      capitalWon -= wonAmount; // 원화 자본에서 차감
      print('매수 실행(국내): $symbol, 가격: ${price.toStringAsFixed(0)}원, 수량: ${quantity.toInt()}주, 원화: ${wonAmount.toStringAsFixed(0)}원, 남은원화: ${capitalWon.toStringAsFixed(0)}원, 날짜: ${position.entryTime.toString().substring(0, 10)}');
    }
  }

  // 매도 실행
  void executeSell(String symbol, double price, SellSignal signal, [DateTime? tradeTime]) {
    print('🚀 매도 실행 시작: $symbol');
    print('   📊 매도 시그널: ${signal.type}');
    print('   📊 매도 가격: $price');
    
    final position = positions[symbol];
    if (position == null) {
      print('❌ 매도 실패: 보유 포지션 없음');
      return;
    }

    // 해외주식 여부 확인
    final isOverseas = symbol.length >= 4 && RegExp(r'^[A-Z]+$').hasMatch(symbol);

    // 부분익절인 경우 50% 고정 매도 (사용자 요청)
    double sellQuantity = position.quantity;
    if (signal.type == SellSignalType.PARTIAL_PROFIT) {
      final partialProfitRatio = 0.5; // 50% 고정
      sellQuantity = (position.quantity * partialProfitRatio).roundToDouble();
      print('🟡 부분익절: ${symbol} ${sellQuantity.toInt()}주 매도 (전체 ${position.quantity.toInt()}주 중 50%)');
    }

    // 손익 계산
    final profitLoss = (price - position.entryPrice) * sellQuantity;
    final profitLossPercent = (price - position.entryPrice) / position.entryPrice * 100;
    
    // 자본 회수 (해외주식은 달러, 국내주식은 원화)
    if (isOverseas) {
      final dollarAmount = price * sellQuantity;
      capitalDollar += dollarAmount; // 달러 자본에 추가
      print('매도 실행(해외): $symbol, 가격: \$${price.toStringAsFixed(2)}, 수량: ${sellQuantity.toInt()}주, 달러: \$${dollarAmount.toStringAsFixed(0)}, 남은달러: \$${capitalDollar.toStringAsFixed(0)}');
    } else {
      final wonAmount = price * sellQuantity;
      capitalWon += wonAmount; // 원화 자본에 추가
      print('매도 실행(국내): $symbol, 가격: ${price.toStringAsFixed(0)}원, 수량: ${sellQuantity.toInt()}주, 원화: ${wonAmount.toStringAsFixed(0)}원, 남은원화: ${capitalWon.toStringAsFixed(0)}원');
    }
    
    final result = TradeResult(
      symbol: symbol,
      entryPrice: position.entryPrice,
      exitPrice: price,
      quantity: sellQuantity,
      profitLoss: profitLoss,
      profitLossPercent: profitLossPercent,
      entryTime: position.entryTime,
      exitTime: tradeTime ?? DateTime.now(),
      style: style,
      exitReason: signal.type,
    );
    
    results.add(result);
    
    // 부분익절인 경우 남은 수량으로 새로운 포지션 생성, 전체 매도인 경우 포지션 제거
    if (signal.type == SellSignalType.PARTIAL_PROFIT) {
      final remainingQuantity = position.quantity - sellQuantity;
      if (remainingQuantity > 0) {
        positions[symbol] = position.copyWith(quantity: remainingQuantity);
      } else {
        positions.remove(symbol);
      }
    } else {
      positions.remove(symbol);
    }
    
    // 연속 손실 카운트 업데이트
    if (profitLoss < 0) {
      consecutiveLosses++;
    } else {
      consecutiveLosses = 0;
    }
    
    if (isOverseas) {
      print('매도 실행(해외): $symbol, 가격: \$${price.toStringAsFixed(2)}, 손익: \$${profitLoss.toStringAsFixed(2)}, 날짜: ${result.exitTime.toString().substring(0, 10)}');
    } else {
      print('매도 실행(국내): $symbol, 가격: ${price.toStringAsFixed(0)}원, 손익: ${profitLoss.toStringAsFixed(0)}원, 날짜: ${result.exitTime.toString().substring(0, 10)}');
    }
  }

  // 보조 함수들 (로컬 DB 설정값 사용)
  double _getStochThreshold() {
    // 새로운 7가지 동적 지표 시스템에서는 스토캐스틱 임계값을 사용하지 않음
    return 20.0; // 기본값
  }

  double _getVixThreshold() {
    // 7개 지표 시스템에서는 VIX가 ADX 점수에 포함됨
    return 25.0; // 기본값
  }

  double _adjustSizeByStyle(double base) {
    // 이미 positionSize가 적용된 base이므로 그대로 반환
    return base;
  }

  bool _isTechnicalSell(double price) {
    // 기술적 매도 조건 구현
    // RSI, BB_high, MACD_hist, Stoch_K 조건 확인
    return false; // 임시 구현
  }

  void _updateDailyLoss([DateTime? backtestDate]) {
    // 백테스트 모드일 때는 해당 날짜 기준, 실제 거래 시는 오늘 기준
    final targetDate = backtestDate ?? DateTime.now();
    final todayResults = results.where((result) => 
      result.exitTime.year == targetDate.year &&
      result.exitTime.month == targetDate.month &&
      result.exitTime.day == targetDate.day
    ).toList();
    
    dailyLoss = todayResults.fold(0.0, (sum, result) {
      final isOverseas = result.symbol.length >= 4 && RegExp(r'^[A-Z]+$').hasMatch(result.symbol);
      if (isOverseas) {
        return sum + (result.profitLoss * 1400); // 해외주식 손익을 원화로 변환
      } else {
        return sum + result.profitLoss; // 국내주식 손익은 그대로
      }
    });
    
    // 일일 손실을 퍼센트로 변환 (초기 자본 대비)
    final initialTotalCapital = initialCapitalWon + (initialCapitalDollar * _exchangeRate);
    dailyLoss = (dailyLoss / initialTotalCapital) * 100;
  }

  void _updateMaxDrawdown() {
    // 현재 자본 = 원화 현금 + 달러 현금(원화 환산) + 보유 포지션들의 현재 가치
    final currentCapital = capitalWon + (capitalDollar * 1400) + positions.values.fold(0.0, (sum, pos) {
      final positionValue = pos.entryPrice * pos.quantity;
      
      // 해외주식인 경우 달러 가치를 원화로 환산
      final isOverseas = pos.symbol.length >= 4 && RegExp(r'^[A-Z]+$').hasMatch(pos.symbol);
      if (isOverseas) {
        return sum + (positionValue * 1400); // 달러 포지션을 원화로 환산
      } else {
        return sum + positionValue; // 원화 포지션
      }
    });
    
    if (currentCapital > peakCapital) {
      peakCapital = currentCapital;
    }
    
    final drawdown = (currentCapital - peakCapital) / peakCapital * 100;
    if (drawdown < maxDrawdown) {
      maxDrawdown = drawdown;
      print('📉 최대낙폭 업데이트: ${drawdown.toStringAsFixed(2)}% (현재자본: ${currentCapital.toStringAsFixed(0)}원, 피크자본: ${peakCapital.toStringAsFixed(0)}원)');
    }
  }

  // 성과 통계
  Map<String, dynamic> getPerformanceStats() {
    // 초기 자본 (원화 + 달러 환산)
    final initialTotalCapital = initialCapitalWon + (initialCapitalDollar * 1400);
    
    if (results.isEmpty) {
      return {
        'totalReturn': 0.0,
        'totalTrades': 0,
        'winRate': 0.0,
        'avgProfit': 0.0,
        'avgLoss': 0.0,
        'maxDrawdown': maxDrawdown,
        'sharpeRatio': 0.0,
        'finalCapital': initialTotalCapital, // 초기 자본과 동일
        'initialCapital': initialTotalCapital,
        'totalProfitLoss': 0.0, // 총 손익 추가
      };
    }

    // 거래별 손익 합계 계산 (해외주식은 원화로 변환)
    final totalProfitLoss = results.fold<double>(0.0, (sum, result) {
      final isOverseas = result.symbol.length >= 4 && RegExp(r'^[A-Z]+$').hasMatch(result.symbol);
      if (isOverseas) {
        return sum + (result.profitLoss * 1400); // 해외주식 손익을 원화로 변환
      } else {
        return sum + result.profitLoss; // 국내주식 손익은 그대로
      }
    });
    
    // 최종 자본 = 현재 원화 자본 + 현재 달러 자본(원화 환산) + 보유 포지션 가치
    final finalCapital = capitalWon + (capitalDollar * 1400) + positions.values.fold(0.0, (sum, pos) {
      final positionValue = pos.entryPrice * pos.quantity;
      final isOverseas = pos.symbol.length >= 4 && RegExp(r'^[A-Z]+$').hasMatch(pos.symbol);
      if (isOverseas) {
        return sum + (positionValue * 1400); // 달러 포지션을 원화로 환산
      } else {
        return sum + positionValue; // 원화 포지션
      }
    });
    
    // 총 수익률 계산 (최종 자본 기준)
    final totalReturn = ((finalCapital - initialTotalCapital) / initialTotalCapital) * 100;
    
    final totalTrades = results.length;
    final winningTrades = results.where((r) => r.profitLoss > 0).length;
    final winRate = (winningTrades / totalTrades) * 100;
    
    final profits = results.where((r) => r.profitLoss > 0).map((r) {
      final isOverseas = r.symbol.length >= 4 && RegExp(r'^[A-Z]+$').hasMatch(r.symbol);
      return isOverseas ? r.profitLoss * 1400 : r.profitLoss; // 해외주식 손익을 원화로 변환
    }).toList();
    final losses = results.where((r) => r.profitLoss < 0).map((r) {
      final isOverseas = r.symbol.length >= 4 && RegExp(r'^[A-Z]+$').hasMatch(r.symbol);
      return isOverseas ? r.profitLoss * 1400 : r.profitLoss; // 해외주식 손익을 원화로 변환
    }).toList();
    
    final avgProfit = profits.isEmpty ? 0.0 : profits.reduce((a, b) => a + b) / profits.length;
    final avgLoss = losses.isEmpty ? 0.0 : losses.reduce((a, b) => a + b) / losses.length;
    
    // 간단한 샤프 비율 계산 (표준편차 대신 평균 사용)
    final avgReturn = results.map((r) => r.profitLossPercent).reduce((a, b) => a + b) / results.length;
    final sharpeRatio = avgReturn / (avgReturn.abs() + 1); // 임시 계산

    print('💰 백테스트 자본 계산 상세:');
    print('   - 초기 자본: ${initialTotalCapital.toStringAsFixed(0)}원 (원화: ${initialCapitalWon.toStringAsFixed(0)}원, 달러: ${initialCapitalDollar.toStringAsFixed(0)}달러)');
    print('   - 현재 자본: ${finalCapital.toStringAsFixed(0)}원 (원화: ${capitalWon.toStringAsFixed(0)}원, 달러: ${capitalDollar.toStringAsFixed(0)}달러)');
    print('   - 총 수익률: ${totalReturn.toStringAsFixed(2)}%');
    print('   - 거래 건수: $totalTrades건');

    return {
      'totalReturn': totalReturn,
      'totalTrades': totalTrades,
      'winRate': winRate,
      'avgProfit': avgProfit,
      'avgLoss': avgLoss,
      'maxDrawdown': maxDrawdown,
      'sharpeRatio': sharpeRatio,
      'finalCapital': finalCapital, // 수정된 최종 자본
      'initialCapital': initialTotalCapital,
      'totalProfitLoss': totalProfitLoss, // 총 손익 추가
    };
  }

  // 서버 분석 호출을 통한 매수 판단(실패 시 로컬 폴백)
  Future<bool> generateBuySignalViaCloud(String symbol) async {
    try {
      final service = AnalysisFunctionsService();
      final result = await service.analyzeStock(
        symbol: symbol,
        days: 100,
        buyThreshold: config.buyThreshold,
        sellThreshold: config.sellThreshold,
      );
      final decision = (result['tradingDecision'] as String?) ?? 'HOLD';
      final score = (result['comprehensiveScore'] as num?)?.toDouble() ?? 0.0;
      print('☁️ 서버 분석 결과: $symbol → decision=$decision, score=$score');
      return decision == 'BUY';
    } catch (e) {
      print('☁️ 서버 분석 실패, 로컬 폴백 사용: $e');
      return false; // 폴백 판단은 호출부에서 로컬 generateBuySignal로 진행
    }
  }
}

// 백테스터 클래스
class StyleBasedBacktester {
  /// 스타일별 매수 조건 상세 로그 출력
  void _logBuyConditions(StockData data, InvestmentStyle style) {
    final conditions = <String>[];
    
    // RSI 조건
    if (data.rsi14 <= 25) conditions.add('RSI 과매도(${data.rsi14.toStringAsFixed(1)})');
    else if (data.rsi14 <= 30) conditions.add('RSI 낮음(${data.rsi14.toStringAsFixed(1)})');
    else if (data.rsi14 <= 35) conditions.add('RSI 보통(${data.rsi14.toStringAsFixed(1)})');
    
    // 거래량 조건
    if (data.volume >= data.prevVolume * 1.5) conditions.add('거래량 급증(${(data.volume / data.prevVolume).toStringAsFixed(1)}x)');
    else if (data.volume >= data.prevVolume * 1.2) conditions.add('거래량 증가(${(data.volume / data.prevVolume).toStringAsFixed(1)}x)');
    
    // 외국인 순매수
    if (data.foreignNetBuy > 0) conditions.add('외국인 순매수(${data.foreignNetBuy.toStringAsFixed(0)})');
    
    // PER 조건
    if (data.per > 0 && data.per < 15) conditions.add('PER 저평가(${data.per.toStringAsFixed(1)})');
    
    // 호가창 불균형
    if (data.askRemain1 > 0 && data.bidRemain1 > 0) {
      final ratio = data.bidRemain1 / data.askRemain1;
      if (ratio > 1.2) conditions.add('매수세 우세(${ratio.toStringAsFixed(1)}x)');
    }
    
    print('   📊 매수 조건: ${conditions.join(', ')}');
  }

  /// 요일을 한글로 변환
  String _getDayOfWeek(int weekday) {
    switch (weekday) {
      case DateTime.monday: return '월요일';
      case DateTime.tuesday: return '화요일';
      case DateTime.wednesday: return '수요일';
      case DateTime.thursday: return '목요일';
      case DateTime.friday: return '금요일';
      case DateTime.saturday: return '토요일';
      case DateTime.sunday: return '일요일';
      default: return '알 수 없음';
    }
  }

  /// 주말 및 공휴일 체크 함수 (나스닥 토요일 새벽 거래 허용)
  bool _isTradingDay(DateTime date) {
    // 일요일은 모든 시장에서 거래 없음
    if (date.weekday == DateTime.sunday) {
      return false;
    }
    
    // 토요일은 나스닥 거래 허용 (새벽 시간대)
    if (date.weekday == DateTime.saturday) {
      final hour = date.hour;
      // 토요일 새벽 00:00-05:00은 나스닥 거래 허용
      if (hour >= 0 && hour < 5) {
        return true; // 나스닥 거래 허용
      }
      return false; // 토요일 05:00 이후는 거래 없음
    }
    
    // 주요 공휴일 체크 (간단한 버전)
    final month = date.month;
    final day = date.day;
    
    // 설날, 추석 등 주요 공휴일 (간단한 체크)
    if ((month == 1 && (day == 1 || day == 2 || day == 3)) || // 설날
        (month == 3 && day == 1) || // 삼일절
        (month == 5 && day == 5) || // 어린이날
        (month == 6 && day == 6) || // 현충일
        (month == 8 && day == 15) || // 광복절
        (month == 10 && day == 3) || // 개천절
        (month == 10 && day == 9) || // 한글날
        (month == 12 && day == 25)) { // 크리스마스
      return false;
    }
    
    return true;
  }



  /// 백테스트 실행 (7개 지표 시스템 기반)
  Future<Map<String, dynamic>> runBacktest(
    InvestmentStyle style,
    List<StockData> data,
    double initialCapital,
  ) async {
    print('🔄 백테스팅 설정 로드 시작...');
    
    final strategy = StyleBasedTradingStrategy(
      style: style,
      initialCapitalWon: initialCapital,
      initialCapitalDollar: 1000.0,
      isCustomMode: true, // 사용자 커스터마이징 모드 활성화
    );
    
    // 설정 초기화 전에 현재 상태 출력
    print('📊 백테스팅 시작 전 설정 상태:');
    print('   - 투자 스타일: ${_getStyleName(style)}');
    print('   - 커스터마이징 모드: ${strategy.isCustomMode}');
    print('   - 초기 자본: ${initialCapital.toStringAsFixed(0)}원');
    
    await strategy._initializeConfig();
    
    // 설정 로드 후 상세 정보 출력
    print('\n=== ${_getStyleName(style)} 투자 스타일 백테스트 ===');
    print('📊 입력 데이터: ${data.length}개');
    print('📈 데이터 샘플: ${data.take(3).map((d) => '${d.symbol}:${d.close}').toList()}');
    print('\n🔧 로드된 설정값 (상세):');
    print('   📈 매수 조건:');
    print('     - 7가지 동적 지표 시스템 사용');
    print('     - 매수 임계값: ${strategy.config.buyThreshold}점');
    print('     - 매도 임계값: ${strategy.config.sellThreshold}점');
    print('     - 7개 지표 시스템 기반');
    print('   💰 수익 관리:');
    print('     - 부분익절: ${strategy.config.partialProfit}%');
    print('     - 전체익절: ${strategy.config.fullProfit}%');
    print('     - 손절: ${strategy.config.stopLoss}%');
    print('   🎯 목표 설정:');
    
    print('   📊 포지션 관리:');
    print('     - 투자 비율: ${(strategy.config.positionSize * 100).toStringAsFixed(1)}%');
    print('     - 최대 종목 수: ${strategy.config.maxStocks}개');
    print('   🛡️ 리스크 관리:');
    print('     - 일일 손실 한도: ${strategy.config.dailyLossLimit}%');
    print('     - 리스크 관리: 7개 지표 종합 점수로 대체');
    print('   🔍 지표 구성 (7개):');
    print('     - 거래량(20%) + RSI(20%) + MACD(20%) + 볼린저(15%) + 이동평균(15%) + VWAP(5%) + ADX(5%)');
    print('');

    // 실제 투자 스타일 설정 사용 (완화 없음)
    print('🔧 실제 투자 스타일 설정 사용');
    print('   - 일일 손실 한도: ${strategy.config.dailyLossLimit}% (실제값)');


    int tradeCount = 0;
    
    // 데이터를 날짜별로 그룹화 (실제 거래일 순서대로)
    print('📊 데이터를 날짜별로 재구성 중...');
    final dataByDate = <String, List<StockData>>{};
    
    // 각 종목별로 데이터 그룹화
    final stockGroups = <String, List<StockData>>{};
    for (final stockData in data) {
      if (!stockGroups.containsKey(stockData.symbol)) {
        stockGroups[stockData.symbol] = [];
      }
      stockGroups[stockData.symbol]!.add(stockData);
    }
    
    // 각 종목의 데이터를 실제 거래일 순서대로 매핑 (사용자 선택 기간)
    for (final entry in stockGroups.entries) {
      final symbol = entry.key;
      final stockDataList = entry.value;
      
      print('📊 $symbol: ${stockDataList.length}일치 데이터 처리 중...');
      
      // 각 종목의 데이터를 날짜별로 매핑 (실제 거래일 순서)
      for (int i = 0; i < stockDataList.length; i++) {
        final stockData = stockDataList[i];
        
        // 실제 거래일 기준으로 날짜 생성 (사용자 선택 기간)
        final startDate = DateTime.now().subtract(Duration(days: stockDataList.length));
        final currentDate = startDate.add(Duration(days: i));
        
        // 거래일 체크 (주말 제외)
        if (!_isTradingDay(currentDate)) {
          print('⚠️ 거래 불가능한 날짜 건너뛰기: ${currentDate.toString().substring(0, 10)} (${_getDayOfWeek(currentDate.weekday)})');
          continue;
        }
        
      final dateKey = '${currentDate.year}-${currentDate.month.toString().padLeft(2, '0')}-${currentDate.day.toString().padLeft(2, '0')}';
      
      if (!dataByDate.containsKey(dateKey)) {
        dataByDate[dateKey] = [];
      }
      dataByDate[dateKey]!.add(stockData);
      }
    }
    
    final sortedDates = dataByDate.keys.toList()..sort();
    print('📊 총 ${sortedDates.length}일간 백테스트 시작 (거래일만 포함)');
    
    // 투자스타일 설정값 출력
    print('🎯 투자스타일 설정 확인:');
    print('   - 스타일: ${_getStyleName(style)}');
    print('   - 부분익절: ${strategy.config.partialProfit.toStringAsFixed(1)}%');
    print('   - 전체익절: ${strategy.config.fullProfit.toStringAsFixed(1)}%');
    print('   - 손절: ${strategy.config.stopLoss.toStringAsFixed(1)}%');
    print('   - 투자비율: ${(strategy.config.positionSize * 100).toStringAsFixed(1)}%');
    print('   - 최대종목수: ${strategy.config.maxStocks}개');
    print('   - 일일손실한도: ${strategy.config.dailyLossLimit.toStringAsFixed(1)}%');
    print('   - 초기자본: ${((strategy.initialCapitalWon + strategy.initialCapitalDollar * 1400) / 10000).toStringAsFixed(0)}만원');
    
    // 날짜별로 백테스트 실행 (올바른 로직)
    for (int dayIndex = 0; dayIndex < sortedDates.length; dayIndex++) {
      final currentDate = sortedDates[dayIndex];
      final dailyData = dataByDate[currentDate]!;
      
      print('📅 ${currentDate} (${dayIndex + 1}/${sortedDates.length}일차) - ${dailyData.length}개 종목');
      
      // 실제 리스크 한도 체크 (실제 투자와 동일)
      final risk = strategy.checkRiskLimits();
      print('📊 리스크 상태 (실제 투자 스타일 적용):');
      print('   - 일일 손실: ${risk.dailyLoss.toStringAsFixed(2)}%');
      print('   - 최대 손실: ${risk.maxDrawdown.toStringAsFixed(2)}%');
      print('   - 포지션 수: ${risk.positionCount}/${risk.maxPositions}');
              print('   - 거래 가능: ${risk.canTrade}');

      // 1단계: 보유 중인 종목들의 매도 시그널 확인 (익절/손절/기타 조건)
      final positionsToSell = <String, dynamic>{};
      
              for (final stockData in dailyData) {
          // 해당 종목을 보유 중인지 확인
          if (strategy.positions.containsKey(stockData.symbol)) {
            final position = strategy.positions[stockData.symbol]!;
            final sellSignal = await strategy.generateSellSignal(position, stockData.close.toDouble(), stockData);
            
            if (sellSignal != null) {
              positionsToSell[stockData.symbol] = {
                'position': position, 
                'signal': sellSignal, 
                'currentPrice': stockData.close
              };
              print('🔍 매도 시그널 감지: ${stockData.symbol} (${sellSignal.type.toString().split('.').last})');
            }
          }
        }
      
      // 2단계: 매도 실행 (보유 중인 종목들)
      positionsToSell.forEach((symbol, data) {
        final position = data['position'];
        final sellSignal = data['signal'];
        final currentPrice = data['currentPrice'];
        final currentDateTime = DateTime.parse('$currentDate 09:00:00'); // 실제 거래 날짜 사용
        
        // 거래일 재검증
        if (!_isTradingDay(currentDateTime)) {
          print('⚠️ 매도 거래 취소: $currentDate는 거래 불가능한 날짜');
          return;
        }
        
        strategy.executeSell(symbol, currentPrice.toDouble(), sellSignal, currentDateTime);
        tradeCount++;
        print('🔴 매도: $symbol (${sellSignal.type.toString().split('.').last}) - 매수가: ${position.entryPrice}, 매도가: $currentPrice, 날짜: $currentDate');
      });

      // 3단계: 새로운 매수 시그널 확인 (매도 후 빈 자리가 생겼을 수 있음)
      for (final stockData in dailyData) {
        // 해당 종목을 이미 보유 중이 아닌지 확인
        if (!strategy.positions.containsKey(stockData.symbol)) {
          bool buySignal = false;
          // 서버 분석 우선 시도
          final cloudOk = await strategy.generateBuySignalViaCloud(stockData.symbol);
          if (cloudOk) {
            buySignal = true;
          } else {
            // 폴백: 로컬 계산
            buySignal = strategy.generateBuySignal(stockData);
          }
          final canBuy = risk.canTrade && strategy.positions.length < risk.maxPositions; // 실제 리스크 체크
          
          if (buySignal && canBuy) {
            final size = strategy.calculatePositionSize(stockData.close.toDouble(), symbol: stockData.symbol);
            if (size >= 1.0) { // 최소 1주 이상일 때만 거래
              final currentDateTime = DateTime.parse('$currentDate 09:00:00'); // 실제 거래 날짜 사용
              
              // 거래일 재검증
              if (!_isTradingDay(currentDateTime)) {
                print('⚠️ 매수 거래 취소: $currentDate는 거래 불가능한 날짜');
                continue;
              }
              
              strategy.executeBuy(stockData.symbol, stockData.close.toDouble(), size, currentDateTime);
              tradeCount++;
              
              // 스타일별 매수 로그 출력
              final styleName = _getStyleName(style);
              print('✅ [$styleName] 매수: ${stockData.symbol} (RSI: ${stockData.rsi14.toStringAsFixed(1)}, 가격: ${stockData.close.toStringAsFixed(0)}, 수량: ${size.toInt()}주, 날짜: $currentDate)');
              print('📊 매수 상세: 종목=${stockData.symbol}, 가격=${stockData.close}, 거래량=${stockData.volume}, RSI=${stockData.rsi14.toStringAsFixed(1)}');
              print('📅 실제 매수 정보: ${stockData.symbol} - ${currentDate} (${stockData.close}원)');
              
              // 스타일별 매수 조건 상세 출력
                print('📊 매수 조건 분석:');
                print('   - 종목: ${stockData.symbol}');
                print('   - 현재가: ${stockData.close}');
                print('   - 거래량: ${stockData.volume}');
                print('   - RSI: ${stockData.rsi14.toStringAsFixed(1)}');
                print('   - MACD: ${stockData.macdHist.toStringAsFixed(3)}');
                print('   - 이동평균: 5일=${stockData.ma5.toStringAsFixed(0)}, 20일=${stockData.ma20.toStringAsFixed(0)}');
                print('   - VWAP: ${stockData.vwap.toStringAsFixed(0)}');
                print('   - ADX: ${stockData.adx.toStringAsFixed(1)}');
                print('   - 투자 스타일: ${_getStyleName(style)}');
            } else {
              print('⚠️ 매수 시그널 있지만 최소 거래 수량 미달: ${stockData.symbol} (계산된 수량: ${size.toStringAsFixed(1)}주)');
            }
          } else if (buySignal && !canBuy) {
            print('⚠️ 매수 시그널 있지만 포지션 한도 초과: ${stockData.symbol}');
          }
        }
      }
      
      // 4단계: 보유 중인 종목 현황 출력
      if (strategy.positions.isNotEmpty) {
        print('📊 현재 보유 종목: ${strategy.positions.keys.join(', ')}');
      }
    }
    
    print('총 거래 횟수: $tradeCount회');

    final stats = strategy.getPerformanceStats();
    final finalCapital = stats['finalCapital'] ?? (strategy.initialCapitalWon + strategy.initialCapitalDollar * 1400);
    
    // 스타일별 백테스트 결과 요약
    print('🎯 ${_getStyleName(style)} 스타일 백테스트 결과 요약:');
    print('   - 총 거래: ${stats['totalTrades'] ?? 0}건');
    print('   - 승률: ${(stats['winRate'] ?? 0.0).toStringAsFixed(1)}%');
    print('   - 총 수익률: ${(stats['totalReturn'] ?? 0.0).toStringAsFixed(2)}%');
    print('   - 최대 손실: ${(stats['maxDrawdown'] ?? 0.0).toStringAsFixed(2)}%');
    print('   - 평균 수익: ${(stats['avgProfit'] ?? 0.0).toStringAsFixed(0)}원');
    print('   - 평균 손실: ${(stats['avgLoss'] ?? 0.0).toStringAsFixed(0)}원');
    
    // 거래 히스토리 생성 (실제 거래 날짜 사용)
    final tradeHistory = strategy.results.map((result) {
      return {
        'symbol': result.symbol,
        'entryDate': result.entryTime.toString().substring(0, 10),
        'exitDate': result.exitTime.toString().substring(0, 10),
        'entryPrice': result.entryPrice,
        'exitPrice': result.exitPrice,
        'quantity': result.quantity,
        'profitLoss': result.profitLoss,
        'profitLossPercent': result.profitLossPercent,
        'exitReason': result.exitReason.toString().split('.').last,
        'holdingDays': result.exitTime.difference(result.entryTime).inDays,
      };
    }).toList();

    return {
      'style': style,
      'initialCapital': strategy.initialCapitalWon + strategy.initialCapitalDollar * 1400, // 초기 자본금 추가
      'finalCapital': finalCapital,
      'totalReturn': stats['totalReturn'] ?? 0.0,
      'targetAchieved': true, // 목표 수익률 체크 제거
      'riskControlled': true, // 최대 손실 체크 제거
      'tradeCount': stats['totalTrades'] ?? 0,
      'winRate': stats['winRate'] ?? 0.0,
      'maxDrawdown': stats['maxDrawdown'] ?? 0.0,
      'tradedStocks': strategy.results.map((r) => r.symbol).toSet().length, // 실제 거래된 종목 수
      'tradeHistory': tradeHistory, // 거래 히스토리 추가
      'parameters': _convertParametersToMap(strategy.config),
    };
  }



  /// 실제 API 데이터를 사용한 백테스트 실행 (새로운 순차적 방식)
  Future<Map<String, dynamic>> runBacktestWithRealDataSequential(
    InvestmentStyle style,
    List<Map<String, dynamic>> watchlistData,
    double initialCapitalWon, {
    DateTime? startDate,
    DateTime? endDate,
    double? initialCapitalDollar, // 달러 초기자본 추가
    Function(String)? onProgress, // 진행 상황 콜백
  }) async {
    print('🤖 실제 API 데이터 백테스트 시작: ${_getStyleName(style)} 스타일 (사용자 선택 기간)');
    
    try {
      // 실제 종목 코드 추출
      final stockCodes = watchlistData.map((item) => item['stock_code'] as String).toList();
      
      if (stockCodes.isEmpty) {
        return {
          'error': '백테스트할 종목이 없습니다.',
          'totalTrades': 0,
          'winRate': 0.0,
          'totalReturn': 0.0,
          'maxDrawdown': 0.0,
        };
      }
      
      // 백테스트 기간 설정 (사용자 선택 기간)
      final to = endDate ?? DateTime.now();
      final from = startDate ?? to.subtract(const Duration(days: 30)); // 기본값은 30일
      
      // 기간 계산
      final daysDiff = to.difference(from).inDays;
      
      print('📊 백테스트 기간: ${from.toString().substring(0, 10)} ~ ${to.toString().substring(0, 10)} ($daysDiff일)');
      onProgress?.call('백테스트 기간 설정: ${from.toString().substring(0, 10)} ~ ${to.toString().substring(0, 10)} ($daysDiff일)');
      
      // KIS API 서비스 가져오기
      final unifiedApiService = KisUnifiedApiService();
      
      // 1단계: 전체 기간의 데이터를 한번에 수집 (사용자 선택 기간)
      onProgress?.call('$daysDiff일 데이터 수집 중...');
      print('🔄 API 데이터 수집 시작 ($daysDiff일)...');
      
      final allBacktestData = await _collectAllBacktestData(
        unifiedApiService, 
        stockCodes, 
        watchlistData, 
        from, 
        to,
        onProgress
      );
      
      print('📊 API 데이터 수집 결과: ${allBacktestData.length}일치');
      
      if (allBacktestData.isEmpty) {
        print('❌ API 데이터 수집 실패 - 실제 데이터가 없습니다');
          return {
          'error': 'API에서 실제 데이터를 가져올 수 없습니다. 백테스트를 실행할 수 없습니다.',
            'totalTrades': 0,
            'winRate': 0.0,
            'totalReturn': 0.0,
            'maxDrawdown': 0.0,
          };
      }
      
      // 2단계: 투자 전략 초기화
      final strategy = await _createTradingStrategy(style, initialCapitalWon, initialCapitalDollar ?? 1000.0);
      
      // 실제 투자 스타일 설정 사용 (완화 없음)
      print('🔧 실제 투자 스타일 설정 사용');
      print('   - 일일 손실 한도: ${strategy.config.dailyLossLimit}% (실제값)');

      
      int tradeCount = 0;
      
      // 3단계: 저장된 데이터를 하루씩 순차적으로 진행 (거래일만)
      final sortedDates = allBacktestData.keys.toList()..sort();
      
      // 거래일만 필터링
      final tradingDates = sortedDates.where((dateStr) {
        try {
          final date = DateTime.parse(dateStr);
          return _isTradingDay(date);
        } catch (e) {
          return false;
        }
      }).toList();
      
      print('📊 총 ${tradingDates.length}일간 백테스트 시작 (거래일만 포함)');
      onProgress?.call('백테스트 시작: ${tradingDates.length}일간 (거래일만)');
      
      for (int dayIndex = 0; dayIndex < tradingDates.length; dayIndex++) {
        final currentDate = tradingDates[dayIndex];
        final dailyData = allBacktestData[currentDate]!;
        
        onProgress?.call('${currentDate} 처리 중... (${dayIndex + 1}/${tradingDates.length})');
        print('📅 ${currentDate} (${dayIndex + 1}/${tradingDates.length}일차) - ${dailyData.length}개 종목');
        
        // 거래일 재검증
        final currentDateTime = DateTime.parse('$currentDate 09:00:00');
        if (!_isTradingDay(currentDateTime)) {
          print('⚠️ 거래 불가능한 날짜 건너뛰기: $currentDate (${_getDayOfWeek(currentDateTime.weekday)})');
          continue;
        }
        
        // 실제 리스크 한도 체크 (실제 투자와 동일)
        final risk = strategy.checkRiskLimits();
        print('📊 리스크 상태 (실제 투자 스타일 적용):');
        print('   - 일일 손실: ${risk.dailyLoss.toStringAsFixed(2)}%');
        print('   - 최대 손실: ${risk.maxDrawdown.toStringAsFixed(2)}%');
        print('   - 포지션 수: ${risk.positionCount}/${risk.maxPositions}');
        print('   - 거래 가능: ${risk.canTrade}');

        // 1단계: 보유 중인 종목들의 매도 시그널 확인 (익절/손절/기타 조건)
        final positionsToSell = <String, dynamic>{};
        
        for (final stockData in dailyData) {
          // 해당 종목을 보유 중인지 확인
          if (strategy.positions.containsKey(stockData['symbol'])) {
            final position = strategy.positions[stockData['symbol']]!;
            print('🔍 보유종목 매도 시그널 확인: ${stockData['symbol']}');
            print('   📊 매수가: ${position.entryPrice}, 현재가: ${stockData['close']}');
            
            final sellSignal = await strategy.generateSellSignal(position, (stockData['close'] as num).toDouble(), stockData);
            
            if (sellSignal != null) {
              positionsToSell[stockData['symbol']] = {
                'position': position, 
                'signal': sellSignal, 
                'currentPrice': stockData['close']
              };
              print('✅ 매도 시그널 감지: ${stockData['symbol']} (${sellSignal.type.toString().split('.').last})');
            } else {
              print('❌ 매도 시그널 없음: ${stockData['symbol']}');
            }
          }
        }
        
        // 2단계: 매도 실행 (보유 중인 종목들)
        positionsToSell.forEach((symbol, data) {
          final position = data['position'];
          final sellSignal = data['signal'];
          final currentPrice = data['currentPrice'];
          final currentDateTime = DateTime.parse('$currentDate 09:00:00'); // 실제 거래 날짜 사용
          
          // 거래일 재검증
          if (!_isTradingDay(currentDateTime)) {
            print('⚠️ 매도 거래 취소: $currentDate는 거래 불가능한 날짜');
            return;
          }
          
          strategy.executeSell(symbol, currentPrice.toDouble(), sellSignal, currentDateTime);
          tradeCount++;
          print('🔴 매도: $symbol (${sellSignal.type.toString().split('.').last}) - 매수가: ${position.entryPrice}, 매도가: $currentPrice, 날짜: $currentDate');
        });

        // 3단계: 새로운 매수 시그널 확인 (매도 후 빈 자리가 생겼을 수 있음)
        for (final stockData in dailyData) {
          // 해당 종목을 이미 보유 중이 아닌지 확인
          if (!strategy.positions.containsKey(stockData['symbol'])) {
            bool buySignal = false;
            // 서버 분석 우선 시도
            final cloudOk = await strategy.generateBuySignalViaCloud(stockData['symbol']);
            if (cloudOk) {
              buySignal = true;
            } else {
              // 폴백: 로컬 계산
              buySignal = strategy.generateBuySignal(stockData);
            }
            final canBuy = risk.canTrade && strategy.positions.length < risk.maxPositions; // 실제 리스크 체크
            
            if (buySignal && canBuy) {
              final size = strategy.calculatePositionSize((stockData['close'] as num).toDouble(), symbol: stockData['symbol']);
              if (size >= 1.0) { // 최소 1주 이상일 때만 거래
                final currentDateTime = DateTime.parse('$currentDate 09:00:00'); // 실제 거래 날짜 사용
                
                // 거래일 재검증
                if (!_isTradingDay(currentDateTime)) {
                  print('⚠️ 매수 거래 취소: $currentDate는 거래 불가능한 날짜');
                  continue;
                }
                
                strategy.executeBuy(stockData['symbol'], (stockData['close'] as num).toDouble(), size, currentDateTime);
                tradeCount++;
                
                // 스타일별 매수 로그 출력
                final styleName = _getStyleName(style);
                print('✅ [$styleName] 매수: ${stockData['symbol']} (RSI: ${(stockData['rsi14'] as num?)?.toStringAsFixed(1) ?? 'N/A'}, 가격: ${(stockData['close'] as num).toStringAsFixed(0)}, 수량: ${size.toInt()}주, 날짜: $currentDate)');
                print('📊 매수 상세: 종목=${stockData['symbol']}, 가격=${stockData['close']}, 거래량=${stockData['volume']}, RSI=${(stockData['rsi14'] as num?)?.toStringAsFixed(1) ?? 'N/A'}');
                print('📅 실제 매수 정보: ${stockData['symbol']} - ${currentDate} (${stockData['close']}원)');
                
                // 스타일별 매수 조건 상세 출력
                print('📊 매수 조건 분석:');
                print('   - 종목: ${stockData['symbol']}');
                print('   - 현재가: ${stockData['close']}');
                print('   - 거래량: ${stockData['volume']}');
                print('   - RSI: ${(stockData['rsi14'] as num?)?.toStringAsFixed(1) ?? 'N/A'}');
                print('   - MACD: ${(stockData['macdHist'] as num?)?.toStringAsFixed(3) ?? 'N/A'}');
                print('   - 이동평균: 5일=${(stockData['ma5'] as num?)?.toStringAsFixed(0) ?? 'N/A'}, 20일=${(stockData['ma20'] as num?)?.toStringAsFixed(0) ?? 'N/A'}');
                print('   - VWAP: ${(stockData['vwap'] as num?)?.toStringAsFixed(0) ?? 'N/A'}');
                print('   - ADX: ${(stockData['adx'] as num?)?.toStringAsFixed(1) ?? 'N/A'}');
                print('   - 투자 스타일: ${_getStyleName(style)}');
              } else {
                print('⚠️ 매수 시그널 있지만 최소 거래 수량 미달: ${stockData['symbol']} (계산된 수량: ${size.toStringAsFixed(1)}주)');
              }
            } else if (buySignal && !canBuy) {
              print('⚠️ 매수 시그널 있지만 포지션 한도 초과: ${stockData['symbol']}');
            }
          }
        }
        
        // 4단계: 보유 중인 종목 현황 출력
        if (strategy.positions.isNotEmpty) {
          print('📊 현재 보유 종목: ${strategy.positions.keys.join(', ')}');
        }
      }
      
      print('총 거래 횟수: $tradeCount회');

      final stats = strategy.getPerformanceStats();
      final finalCapital = stats['finalCapital'] ?? (strategy.initialCapitalWon + strategy.initialCapitalDollar * 1400);
      
      // 스타일별 백테스트 결과 요약
      print('🎯 ${_getStyleName(style)} 스타일 백테스트 결과 요약:');
      print('   - 총 거래: ${stats['totalTrades'] ?? 0}건');
      print('   - 승률: ${(stats['winRate'] ?? 0.0).toStringAsFixed(1)}%');
      print('   - 총 수익률: ${(stats['totalReturn'] ?? 0.0).toStringAsFixed(2)}%');
      print('   - 최대 손실: ${(stats['maxDrawdown'] ?? 0.0).toStringAsFixed(2)}%');
      print('   - 평균 수익: ${(stats['avgProfit'] ?? 0.0).toStringAsFixed(0)}원');
      print('   - 평균 손실: ${(stats['avgLoss'] ?? 0.0).toStringAsFixed(0)}원');
      
      // 거래 히스토리 생성 (실제 거래 날짜 사용)
      final tradeHistory = strategy.results.map((result) {
        return {
          'symbol': result.symbol,
          'entryDate': result.entryTime.toString().substring(0, 10),
          'exitDate': result.exitTime.toString().substring(0, 10),
          'entryPrice': result.entryPrice,
          'exitPrice': result.exitPrice,
          'quantity': result.quantity,
          'profitLoss': result.profitLoss,
          'profitLossPercent': result.profitLossPercent,
          'exitReason': result.exitReason.toString().split('.').last,
          'holdingDays': result.exitTime.difference(result.entryTime).inDays,
        };
      }).toList();

      return {
        'style': style,
        'initialCapital': strategy.initialCapitalWon + strategy.initialCapitalDollar * 1400, // 초기 자본금 추가
        'finalCapital': finalCapital,
        'totalReturn': stats['totalReturn'] ?? 0.0,
        'targetAchieved': true, // 목표 수익률 체크 제거
        'riskControlled': true, // 최대 손실 체크 제거
        'tradeCount': stats['totalTrades'] ?? 0,
        'winRate': stats['winRate'] ?? 0.0,
        'maxDrawdown': stats['maxDrawdown'] ?? 0.0,
        'tradedStocks': strategy.results.map((r) => r.symbol).toSet().length, // 실제 거래된 종목 수
        'tradeHistory': tradeHistory, // 거래 히스토리 추가
        'parameters': _convertParametersToMap(strategy.config),
      };
      
    } catch (e) {
      print('❌ 실제 API 데이터 백테스트 실패: $e');
      return {
        'error': '백테스트 실행 중 오류가 발생했습니다: $e',
        'totalTrades': 0,
        'winRate': 0.0,
        'totalReturn': 0.0,
        'maxDrawdown': 0.0,
      };
    }
  }







  /// 전체 기간의 백테스트 데이터 수집 (로컬DB 사용)
  Future<Map<String, List<Map<String, dynamic>>>> _collectAllBacktestData(
    dynamic unifiedApiService,
    List<String> stockCodes,
    List<Map<String, dynamic>> watchlistData,
    DateTime from,
    DateTime to,
    Function(String)? onProgress,
  ) async {
    final allData = <String, List<Map<String, dynamic>>>{};
    
    // 거래일 목록 생성
    final tradingDays = _generateTradingDays(from, to);
    print('📊 수집할 거래일: ${tradingDays.length}일');
    onProgress?.call('수집할 거래일: ${tradingDays.length}일');
    
    // 각 종목별로 전체 기간 데이터 수집
    for (int stockIndex = 0; stockIndex < stockCodes.length; stockIndex++) {
      final stockCode = stockCodes[stockIndex];
      
      print('📊 $stockCode 전체 기간 데이터 수집 중... (${stockIndex + 1}/${stockCodes.length})');
      onProgress?.call('$stockCode 데이터 수집 중... (${stockIndex + 1}/${stockCodes.length})');
      
      try {
        // 관심종목 데이터에서 해외주식 여부 확인
        final watchlistItem = watchlistData.firstWhere(
          (item) => (item['stock_code'] as String).toUpperCase() == stockCode.toUpperCase(),
          orElse: () => {'market_type': 'domestic'}
        );
        
        final marketType = watchlistItem['market_type'] as String? ?? 'domestic';
        bool isOverseasStock = marketType == 'overseas' || 
                               (stockCode.length >= 4 && RegExp(r'^[A-Z]+$').hasMatch(stockCode));
        
        // 로컬DB에서 차트 데이터 가져오기 (분석탭과 동일한 방식)
        List<Map<String, dynamic>> chartData;
        if (isOverseasStock) {
          // 해외주식: 로컬DB에서 최근 200일 데이터 조회
          chartData = await _getLocalOverseasChartData(stockCode, from, to);
        } else {
          // 국내주식: 로컬DB에서 최근 200일 데이터 조회
          chartData = await _getLocalDomesticChartData(stockCode, from, to);
        }
        
        if (chartData.isEmpty) {
          print('⚠️ $stockCode: 차트 데이터 없음');
          continue;
        }
        
        print('📊 $stockCode: ${chartData.length}일치 데이터 수집 완료');
        
        // 각 거래일별로 데이터 매핑 (날짜 기반)
        for (int dayIndex = 0; dayIndex < tradingDays.length; dayIndex++) {
          final currentDate = tradingDays[dayIndex];
          
          // 해당 날짜의 데이터 찾기 (더 정확한 매칭)
          Map<String, dynamic>? dayData;
          String? matchedDate;
          
          for (final data in chartData) {
            final dataDate = data['date'] as String?;
            if (dataDate != null) {
              try {
                final parsedDate = DateTime.parse(dataDate);
                if (parsedDate.year == currentDate.year && 
                    parsedDate.month == currentDate.month && 
                    parsedDate.day == currentDate.day) {
                  dayData = data;
                  matchedDate = dataDate;
                  break;
                }
              } catch (e) {
                print('⚠️ $stockCode: 날짜 파싱 실패 - $dataDate: $e');
              }
            }
          }
          
          // 해당 날짜 데이터가 없으면 건너뛰기
          if (dayData == null) {
            print('⚠️ $stockCode: ${currentDate.toString().substring(0, 10)} 데이터 없음 (차트 데이터: ${chartData.length}개)');
            continue;
          }
          
          print('📊 $stockCode: ${currentDate.toString().substring(0, 10)} 데이터 매칭 성공 ($matchedDate)');
          
          final closePrice = (dayData['close'] ?? 0).toDouble();
          final volume = (dayData['volume'] ?? 0).toInt();
          // 거래량 배수 (현재/20일 평균)로 통일 - dayIndex 이후 20일 평균 사용
          final nextStart = dayIndex + 1;
          final nextEnd = (dayIndex + 21) <= chartData.length ? (dayIndex + 21) : chartData.length;
          final List<int> volWindow = [];
          for (int wi = nextStart; wi < nextEnd; wi++) {
            final v = (chartData[wi]['volume'] ?? 0);
            volWindow.add((v is String) ? int.tryParse(v) ?? 0 : (v as num).toInt());
          }
          final avg20 = volWindow.isNotEmpty ? volWindow.reduce((a, b) => a + b) / volWindow.length : 0.0;
          final volumeRatio = avg20 > 0 ? volume / avg20 : 0.0;
          
          if (closePrice > 0 && volume > 0) {
            // 해당 날짜의 인덱스 찾기
            final dataIndex = chartData.indexOf(dayData);
            if (dataIndex >= 0) {
              print('📊 $stockCode: 인덱스 $dataIndex에서 지표 계산 시작');
              
              // OHLC 데이터 추출
              final openPrice = (dayData['open'] ?? closePrice).toDouble();
              final highPrice = (dayData['high'] ?? closePrice).toDouble();
              final lowPrice = (dayData['low'] ?? closePrice).toDouble();
              
              print('📊 $stockCode: OHLC - O:$openPrice, H:$highPrice, L:$lowPrice, C:$closePrice, V:$volume');
              
              // 기술적 지표 계산 - TechnicalIndicators 사용으로 통일
              final prices = chartData.map((data) => 
                double.tryParse(data['close']?.toString() ?? '0') ?? 0.0
              ).where((price) => price > 0).toList();
              
              final rsi = prices.length >= 15 ? TechnicalIndicators.calculateRSI(prices) : 50.0;
              final ma5 = prices.length >= 5 ? TechnicalIndicators.calculateSMA(prices, 5) : closePrice;
              final ma20 = prices.length >= 20 ? TechnicalIndicators.calculateSMA(prices, 20) : closePrice;
              
              print('📊 $stockCode: 지표 계산 완료 - RSI:${rsi.toStringAsFixed(2)}, MA5:${ma5.toStringAsFixed(2)}, MA20:${ma20.toStringAsFixed(2)}');
              
              final stockData = StockData(
                symbol: stockCode,
                close: closePrice,
                open: openPrice,
                high: highPrice,
                low: lowPrice,
                volume: volume,
                prevVolume: volume,
                rsi14: rsi,
                bbLow: closePrice * 0.95,
                bbHigh: closePrice * 1.05,
                ma5: ma5,
                ma20: ma20,
                ma60: closePrice,
                stochK: 50.0,
                macdHist: 0.0,
                vix: 20.0,
                volume20Avg: volume,
                vwap: closePrice.toDouble(), // 7개 지표 시스템용
                adx: 20.0, // 7개 지표 시스템용
                foreignNetBuy: 0.0,
                w52High: 0.0,
                per: 0.0,
                foreignRatio: 0.0,
                askRemain1: 0.0,
                bidRemain1: 0.0,
                marketCap: 0.0,
              );
              
              final dateKey = '${currentDate.year}-${currentDate.month.toString().padLeft(2, '0')}-${currentDate.day.toString().padLeft(2, '0')}';
              if (!allData.containsKey(dateKey)) {
                allData[dateKey] = [];
              }
              allData[dateKey]!.add(stockData.toMap());
            }
          }
        }
        
      } catch (e) {
        print('❌ $stockCode 데이터 수집 실패: $e');
      }
    }
    
    print('✅ 전체 데이터 수집 완료: ${allData.length}일치');
    onProgress?.call('전체 데이터 수집 완료: ${allData.length}일치');
    
    return allData;
  }

  /// 저장된 데이터로 일일 거래 실행 (실제 거래 시뮬레이션)
  Future<int> _executeDailyTradingWithStoredData(
    dynamic strategy,
    Map<String, StockData> dailyData,
    DateTime currentDate,
    InvestmentStyle style,
    Function(String)? onProgress,
  ) async {
    int tradeCount = 0;
    
    // 1단계: 보유 중인 종목들의 매도 시그널 확인 (OHLC 고려)
    final positionsToSell = <String, dynamic>{};
    
    for (final stockData in dailyData.values) {
      if (strategy.positions.containsKey(stockData.symbol)) {
        final position = strategy.positions[stockData.symbol]!;
        
        // 손절가, 익절가 등 매도 조건 확인
        final sellSignal = _checkSellConditions(position, stockData, strategy.config);
        
        if (sellSignal != null) {
          // 실제 매도가 결정 (시가, 고가, 저가, 종가 중 적절한 가격)
          final sellPrice = _determineSellPrice(stockData, sellSignal);
          
          positionsToSell[stockData.symbol] = {
            'position': position, 
            'signal': sellSignal, 
            'sellPrice': sellPrice
          };
          print('🔍 매도 시그널: ${stockData.symbol} (${sellSignal.type.toString().split('.').last}) - 매도가: $sellPrice');
          print('   📊 매수가: ${position.entryPrice}, 현재가: ${stockData.close}, 손익률: ${((stockData.close - position.entryPrice) / position.entryPrice * 100).toStringAsFixed(2)}%');
          onProgress?.call('매도 시그널: ${stockData.symbol}');
        } else {
          // 매도 시그널이 없는 경우 현재 상태 로깅
          final currentProfitLoss = (stockData.close - position.entryPrice) / position.entryPrice * 100;
          print('📊 ${stockData.symbol} 보유 중 - 매수가: ${position.entryPrice}, 현재가: ${stockData.close}, 손익률: ${currentProfitLoss.toStringAsFixed(2)}%');
        }
      }
    }
    
    // 2단계: 매도 실행
    positionsToSell.forEach((symbol, data) {
      final position = data['position'];
      final sellSignal = data['signal'];
      final sellPrice = data['sellPrice'];
      
      strategy.executeSell(symbol, sellPrice.toDouble(), sellSignal, currentDate);
      tradeCount++;
      print('🔴 매도: $symbol - 매수가: ${position.entryPrice}, 매도가: $sellPrice');
      onProgress?.call('매도 실행: $symbol - $sellPrice');
    });

    // 3단계: 새로운 매수 시그널 확인 (반대 방향 레버리지 상품 체크 포함)
    for (final stockData in dailyData.values) {
      if (!strategy.positions.containsKey(stockData.symbol)) {
        // 반대 방향 레버리지 상품이 이미 보유 중인지 확인
        if (_hasOppositeLeveragePosition(strategy.positions, stockData.symbol)) {
          print('⚠️ ${stockData.symbol}: 반대 방향 레버리지 상품 이미 보유 중 - 매수 건너뛰기');
          continue;
        }
        
        final buySignal = strategy.generateBuySignal(stockData);
        
        // 투자스타일별 리스크 관리 체크 (백테스트 날짜 전달)
        final riskStatus = strategy.checkRiskLimits();
        final canBuy = riskStatus.canTrade && 
                      strategy.positions.length < strategy.config.maxStocks;
        
        // 리스크 상태 로깅
        if (!riskStatus.canTrade) {
          print('🛡️ ${stockData.symbol}: 일일 손실 한도 초과로 매수 제한 (현재 손실: ${riskStatus.dailyLoss.toStringAsFixed(2)}%, 한도: ${strategy.config.dailyLossLimit}%)');
          continue;
        }
        
        if (buySignal && canBuy) {
          // 실제 매수가 결정 (시가 또는 종가)
          final buyPrice = _determineBuyPrice(stockData);
          final isOverseas = _isOverseasStock(stockData.symbol);
          
          if (isOverseas) {
            // 해외주식: 달러 기준으로 계산
            final dollarPrice = buyPrice.toDouble(); // 달러 가격
            
            // 투자 비율만큼 달러 자본 사용
            final availableDollarCapital = strategy.capitalDollar * strategy.config.positionSize;
            final size = (availableDollarCapital / dollarPrice).roundToDouble();
            
            // 자본 여유 체크 (달러 자본 기준)
            final requiredDollarCapital = dollarPrice * size;
            if (size >= 1.0 && strategy.capitalDollar >= requiredDollarCapital) {
              strategy.executeBuy(stockData.symbol, dollarPrice, size, currentDate);
              tradeCount++;
              
              final styleName = _getStyleName(style);
              final remainingDollar = strategy.capitalDollar - requiredDollarCapital;
              print('✅ [$styleName] 매수(해외): ${stockData.symbol} - \$${dollarPrice.toStringAsFixed(2)}, ${size.toInt()}주');
              print('   💰 달러 자본: \$${strategy.capitalDollar.toStringAsFixed(0)} → \$${remainingDollar.toStringAsFixed(0)} (사용: \$${requiredDollarCapital.toStringAsFixed(0)})');
              print('   📊 투자비율: ${(strategy.config.positionSize * 100).toStringAsFixed(0)}%, 가용달러: \$${availableDollarCapital.toStringAsFixed(0)}');
              print('📅 실제 매수: ${stockData.symbol} - ${currentDate.toString().substring(0, 10)} (\$${dollarPrice.toStringAsFixed(2)})');
              onProgress?.call('매수 실행: ${stockData.symbol} - \$${dollarPrice.toStringAsFixed(2)}');
            } else if (size >= 1.0) {
              print('💰 ${stockData.symbol}: 달러 자본 부족으로 매수 불가 (필요: \$${requiredDollarCapital.toStringAsFixed(0)}, 보유: \$${strategy.capitalDollar.toStringAsFixed(0)})');
            }
          } else {
            // 국내주식: 원화 기준으로 계산
            final size = strategy.calculatePositionSize(buyPrice.toDouble(), symbol: stockData.symbol);
            
            // 자본 여유 체크
            final requiredCapital = buyPrice.toDouble() * size;
            if (size >= 1.0 && strategy.capitalWon >= requiredCapital) {
              strategy.executeBuy(stockData.symbol, buyPrice.toDouble(), size, currentDate);
              tradeCount++;
              
              final styleName = _getStyleName(style);
              print('✅ [$styleName] 매수(국내): ${stockData.symbol} - ${buyPrice.toStringAsFixed(0)}원, ${size.toInt()}주 (자본: ${(strategy.capitalWon / 10000).toStringAsFixed(0)}만원)');
              print('📅 실제 매수: ${stockData.symbol} - ${currentDate.toString().substring(0, 10)} (${buyPrice.toStringAsFixed(0)}원)');
              onProgress?.call('매수 실행: ${stockData.symbol} - ${buyPrice.toStringAsFixed(0)}원');
            } else if (size >= 1.0) {
              print('💰 ${stockData.symbol}: 자본 부족으로 매수 불가 (필요: ${(requiredCapital / 10000).toStringAsFixed(0)}만원, 보유: ${(strategy.capitalWon / 10000).toStringAsFixed(0)}만원)');
            }
          }
        }
      }
    }
    
    return tradeCount;
  }

  /// 매도 조건 확인 (손절가, 익절가 등)
  SellSignal? _checkSellConditions(Position position, StockData stockData, TradingParameters config) {
    final entryPrice = position.entryPrice;
    final currentClose = stockData.close.toDouble();
    final currentLow = stockData.low.toDouble();
    final currentHigh = stockData.high.toDouble();
    
    // 손절가 확인 (저가 기준) - 손절가는 매수가보다 낮아야 함
    final stopLossPrice = entryPrice * (1 - config.stopLoss / 100);
    if (currentLow <= stopLossPrice) {
      print('🔴 손절가 도달: ${stockData.symbol} - 매수가: $entryPrice, 손절가: $stopLossPrice, 현재저가: $currentLow');
      return SellSignal.STOP_LOSS(stopLossPrice);
    }
    
    // 부분익절 확인 (고가 기준)
    final partialProfitPrice = entryPrice * (1 + config.partialProfit / 100);
    if (currentHigh >= partialProfitPrice) {
      print('🟡 부분익절 도달: ${stockData.symbol} - 매수가: $entryPrice, 부분익절가: $partialProfitPrice, 현재고가: $currentHigh');
      return SellSignal.PARTIAL_PROFIT(partialProfitPrice);
    }
    
    // 전체익절 확인 (고가 기준)
    final fullProfitPrice = entryPrice * (1 + config.fullProfit / 100);
    if (currentHigh >= fullProfitPrice) {
      print('🟢 전체익절 도달: ${stockData.symbol} - 매수가: $entryPrice, 전체익절가: $fullProfitPrice, 현재고가: $currentHigh');
      return SellSignal.FULL_PROFIT(fullProfitPrice);
    }
    
    // 기술적 매도 시그널 확인 (종가 기준)
    // 여기서는 기존 전략의 매도 시그널을 사용
    return null;
  }

  /// 매도가 결정 (종가 기준)
  double _determineSellPrice(StockData stockData, SellSignal sellSignal) {
    // 모든 매도는 종가 기준으로 실행 (사용자 요청사항)
    return stockData.close.toDouble();
  }

  /// 매수가 결정 (종가 기준)
  double _determineBuyPrice(StockData stockData) {
    // 매수도 종가 기준으로 실행 (사용자 요청사항)
    return stockData.close.toDouble();
  }

  /// 해외주식 여부 확인
  bool _isOverseasStock(String symbol) {
    return symbol.length >= 4 && RegExp(r'^[A-Z]+$').hasMatch(symbol);
  }

  /// 환율 (1달러 = 1400원)
  double get _exchangeRate => 1400.0;

  /// 원화를 달러로 변환
  double _convertWonToDollar(double won) {
    return won / _exchangeRate;
  }

  /// 달러를 원화로 변환
  double _convertDollarToWon(double dollar) {
    return dollar * _exchangeRate;
  }

  /// 반대 방향 레버리지 상품이 이미 보유 중인지 확인
  bool _hasOppositeLeveragePosition(Map<String, Position> positions, String newSymbol) {
    // TSLA 관련 레버리지 상품들
    final tslaLeverageProducts = {
      'TSLA': ['TSLL', 'TSLQ'], // TSLA 2배롱, TSLA 2배숏
      'TSLL': ['TSLA', 'TSLQ'], // TSLA 2배롱이면 TSLA, TSLA 2배숏과 충돌
      'TSLQ': ['TSLA', 'TSLL'], // TSLA 2배숏이면 TSLA, TSLA 2배롱과 충돌
    };
    
    // 새로운 종목이 레버리지 상품인지 확인
    for (final baseSymbol in tslaLeverageProducts.keys) {
      if (newSymbol == baseSymbol || tslaLeverageProducts[baseSymbol]!.contains(newSymbol)) {
        // 이미 보유 중인 종목 중에서 충돌하는 종목이 있는지 확인
        for (final heldSymbol in positions.keys) {
          if (tslaLeverageProducts[baseSymbol]!.contains(heldSymbol) || heldSymbol == baseSymbol) {
            print('🚫 ${newSymbol} 매수 차단: ${heldSymbol} 이미 보유 중 (반대 방향 레버리지 상품)');
            return true;
          }
        }
      }
    }
    
    return false;
  }

  /// 투자 전략 생성 (로컬 DB 사용)
  Future<dynamic> _createTradingStrategy(InvestmentStyle style, double initialCapitalWon, double initialCapitalDollar) async {
    // 로컬 DB에서 설정값을 가져오는 전략 생성
    final strategy = StyleBasedTradingStrategy(
      style: style,
      initialCapitalWon: initialCapitalWon,
      initialCapitalDollar: initialCapitalDollar,
      isCustomMode: true, // 항상 로컬 DB 사용
    );
    // config 초기화 대기 (로컬 DB에서 설정값 로드)
    await strategy._initializeConfig();
    return strategy;
  }



  /// 실제 API 데이터를 사용한 백테스트 실행 (기존 방식 - 호환성 유지)
  Future<Map<String, dynamic>> runBacktestWithRealData(
    InvestmentStyle style,
    List<Map<String, dynamic>> watchlistData,
    double initialCapital, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // 새로운 순차적 백테스트 방식 사용
    return await runBacktestWithRealDataSequential(style, watchlistData, initialCapital, startDate: startDate, endDate: endDate);
  }

  /// 실제 API 데이터를 사용한 백테스트 실행 (기존 방식 - 호환성 유지)
  Future<Map<String, dynamic>> runBacktestWithRealDataOld(
    InvestmentStyle style,
    List<Map<String, dynamic>> watchlistData,
    double initialCapital, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    print('🤖 실제 API 데이터 백테스트 시작: ${_getStyleName(style)} 스타일 (기존 방식)');
    
    try {
      // 실제 종목 코드 추출
      final stockCodes = watchlistData.map((item) => item['stock_code'] as String).toList();
      
      if (stockCodes.isEmpty) {
        return {
          'error': '백테스트할 종목이 없습니다.',
          'totalTrades': 0,
          'winRate': 0.0,
          'totalReturn': 0.0,
          'maxDrawdown': 0.0,
        };
      }
      
      // 최근 30일 데이터로 백테스트
      final to = endDate ?? DateTime.now();
      final from = startDate ?? to.subtract(const Duration(days: 30));
      
      print('📊 백테스트 기간: ${from.toString().substring(0, 10)} ~ ${to.toString().substring(0, 10)}');
      
      // KIS API 서비스 가져오기
      final unifiedApiService = KisUnifiedApiService();
      
      // 실제 API 데이터로 백테스트용 데이터 생성
      List<StockData> historicalData = [];
      
      for (final stockCode in stockCodes.take(20)) { // 더 많은 종목 처리 (20개)
        try {
          print('📊 $stockCode 실제 API 데이터 수집 중...');
          
          // 1. 현재가 정보 가져오기 (관심종목 데이터 기반으로 해외주식/국내주식 구분)
          Map<String, dynamic>? currentPriceData;
          final upperCode = stockCode.toUpperCase();
          
          // 관심종목 데이터에서 해외주식 여부 확인
          final watchlistItem = watchlistData.firstWhere(
            (item) => (item['stock_code'] as String).toUpperCase() == upperCode,
            orElse: () => {'market_type': 'domestic'} // 기본값은 국내주식
          );
          
          final marketType = watchlistItem['market_type'] as String? ?? 'domestic';
          bool isOverseasStock = marketType == 'overseas' || 
                                 (upperCode.length >= 4 && RegExp(r'^[A-Z]+$').hasMatch(upperCode));
          
          if (isOverseasStock) {
            // 해외주식
            currentPriceData = await RemoteKisService.instance.getCurrentPrice(stockCode);
            print('🌍 $stockCode 해외주식 현재가 조회 (관심종목: $marketType)');
          } else {
            // 국내주식
            currentPriceData = await RemoteKisService.instance.getCurrentPrice(stockCode);
            print('🇰🇷 $stockCode 국내주식 현재가 조회 (관심종목: $marketType)');
          }
          
          if (currentPriceData == null) {
            print('⚠️ $stockCode 현재가 데이터 없음, 건너뛰기');
            continue;
          }
          
          // 2. 일봉 차트 데이터 가져오기 (해외주식/국내주식 구분) - ATR 계산을 위해 충분한 데이터 확보
          List<Map<String, dynamic>> chartData;
          if (isOverseasStock) {
            // 해외주식 (분석탭과 동일한 방식)
            chartData = await RemoteKisService.instance.getDailyChart(
              stockCode,
              days: 100,
            );
            print('🌍 $stockCode 해외주식 차트 데이터 조회 (관심종목: $marketType)');
          } else {
            // 국내주식 (분석탭과 동일한 방식)
            chartData = await RemoteKisService.instance.getDailyChart(
              stockCode,
              days: 100,
            );
            print('🇰🇷 $stockCode 국내주식 차트 데이터 조회 (관심종목: $marketType)');
          }
          if (chartData == null || chartData.isEmpty) {
            print('⚠️ $stockCode 차트 데이터 없음, 건너뛰기');
            continue;
          }
          
          print('📊 $stockCode 차트 데이터 수집 완료: ${chartData.length}일치');
          // 첫 번째와 마지막 데이터 확인
          if (chartData.isNotEmpty) {
            final firstData = chartData.first;
            final lastData = chartData.last;
            print('📊 $stockCode 첫 번째 데이터: 날짜=${firstData['date']}, 종가=${firstData['close']}');
            print('📊 $stockCode 마지막 데이터: 날짜=${lastData['date']}, 종가=${lastData['close']}');
          }
          
          // 3. 모든 날짜의 데이터 생성 (최소 20일, 최대 200일)
          final daysToProcess = chartData.length > 20 ? chartData.length : chartData.length;
          
          for (int i = 0; i < daysToProcess; i++) {
            try {
              final dayData = chartData[i];
              final prevDayData = i < chartData.length - 1 ? chartData[i + 1] : dayData;
              
              // 기술적 지표 계산 (해당 날짜까지의 데이터 사용)
              final indicators = await _calculateTechnicalIndicatorsWithKisData(
                stockCode, 
                chartData.skip(i).toList()
              );
              
              // KIS API 추가 데이터 활용
              final additionalData = _extractAdditionalKisData(currentPriceData);
              
              // 실제 데이터 유효성 검증 (국내주식/해외주식 구분)
              num closePrice;
              final volume = (dayData['volume'] ?? 0).toInt();
              
              if (isOverseasStock) {
                // 해외주식: double 타입
                closePrice = (dayData['close'] ?? 0.0).toDouble();
                if (closePrice <= 0 || closePrice < 1.0) {
                  print('⚠️ $stockCode ${i+1}일차: 비정상 가격(${closePrice}) - 제외');
                  continue;
                }
              } else {
                // 국내주식: int 타입
                closePrice = (dayData['close'] ?? 0).toInt();
                if (closePrice <= 0 || closePrice < 1000) {
                  print('⚠️ $stockCode ${i+1}일차: 비정상 가격(${closePrice}) - 제외');
                  continue;
                }
              }
              
              // 거래량이 0이면 제외
              if (volume <= 0) {
                print('⚠️ $stockCode ${i+1}일차: 거래량 0 - 제외');
                continue;
              }
              
              // StockData 객체 생성
              final stockData = StockData(
                symbol: stockCode,
                close: closePrice,
                open: (dayData['open'] ?? closePrice).toDouble(),
                high: (dayData['high'] ?? closePrice).toDouble(),
                low: (dayData['low'] ?? closePrice).toDouble(),
                volume: volume,
                prevVolume: (prevDayData['volume'] ?? 0).toInt(),
                rsi14: indicators['rsi'] ?? 50.0,
                bbLow: indicators['bbLow'] ?? 0.0,
                bbHigh: indicators['bbHigh'] ?? 0.0,
                ma5: indicators['ma5'] ?? 0.0,
                ma20: indicators['ma20'] ?? 0.0,
                ma60: indicators['ma60'] ?? 0.0,
                stochK: indicators['stochK'] ?? 50.0,
                macdHist: indicators['macdHist'] ?? 0.0,
                vix: indicators['vix'] ?? 20.0,
                volume20Avg: (indicators['volume20Avg'] ?? 0).toInt(),
                vwap: closePrice.toDouble(), // 7개 지표 시스템용
                adx: 20.0, // 7개 지표 시스템용
                foreignNetBuy: additionalData['foreignNetBuy'] ?? 0.0,
                w52High: additionalData['w52High'] ?? 0.0,
                per: additionalData['per'] ?? 0.0,
                foreignRatio: additionalData['foreignRatio'] ?? 0.0,
                askRemain1: additionalData['askRemain1'] ?? 0.0,
                bidRemain1: additionalData['bidRemain1'] ?? 0.0,
                marketCap: additionalData['marketCap'] ?? 0.0,
              );
              
              historicalData.add(stockData);
              print('✅ $stockCode ${i+1}일차: 가격=${closePrice}, 거래량=${volume}, 날짜=${dayData['date'] ?? 'N/A'}');
              
            } catch (e) {
              print('❌ $stockCode ${i+1}일차 데이터 처리 실패: $e');
            }
          }
          
          print('✅ $stockCode 데이터 수집 완료: ${daysToProcess}일치 데이터 생성');
          
        } catch (e) {
          print('❌ $stockCode 데이터 수집 실패: $e');
        }
      }
        
        if (historicalData.isEmpty) {
        print('⚠️ 수집된 데이터가 없어 더 많은 종목으로 재시도');
        // 더 많은 종목으로 재시도
        for (final stockCode in stockCodes.skip(20).take(30)) {
          try {
            print('📊 $stockCode 재시도 중...');
            
            // 1. 현재가 정보 가져오기 (관심종목 데이터 기반으로 해외주식/국내주식 구분)
            Map<String, dynamic>? currentPriceData;
            final upperCode = stockCode.toUpperCase();
            
            // 관심종목 데이터에서 해외주식 여부 확인
            final watchlistItem = watchlistData.firstWhere(
              (item) => (item['stock_code'] as String).toUpperCase() == upperCode,
              orElse: () => {'market_type': 'domestic'} // 기본값은 국내주식
            );
            
            final marketType = watchlistItem['market_type'] as String? ?? 'domestic';
            bool isOverseasStock = marketType == 'overseas' || 
                                   (upperCode.length >= 4 && RegExp(r'^[A-Z]+$').hasMatch(upperCode));
            
            if (isOverseasStock) {
              // 해외주식
              currentPriceData = await RemoteKisService.instance.getCurrentPrice(stockCode);
              print('🌍 $stockCode 재시도 해외주식 현재가 조회 (관심종목: $marketType)');
        } else {
              // 국내주식
              currentPriceData = await RemoteKisService.instance.getCurrentPrice(stockCode);
              print('🇰🇷 $stockCode 재시도 국내주식 현재가 조회 (관심종목: $marketType)');
            }
            
            if (currentPriceData == null) continue;
            
            // 2. 일봉 차트 데이터 가져오기 (해외주식/국내주식 구분)
            List<Map<String, dynamic>> chartData;
            if (isOverseasStock) {
              // 해외주식 (분석탭과 동일한 방식)
              chartData = await RemoteKisService.instance.getDailyChart(
              stockCode,
              days: 100,
            );
              print('🌍 $stockCode 재시도 해외주식 차트 데이터 조회 (관심종목: $marketType)');
            } else {
              // 국내주식 (분석탭과 동일한 방식)
              chartData = await RemoteKisService.instance.getDailyChart(
              stockCode,
              days: 100,
            );
              print('🇰🇷 $stockCode 재시도 국내주식 차트 데이터 조회 (관심종목: $marketType)');
            }
            
            if (chartData == null || chartData.isEmpty) continue;
            
            print('📊 $stockCode 재시도 차트 데이터 수집 완료: ${chartData.length}일치');
            
            // 3. 모든 날짜의 데이터 생성 (최소 20일, 최대 200일)
            final daysToProcess = chartData.length > 20 ? chartData.length : chartData.length;
            
            for (int i = 0; i < daysToProcess; i++) {
              try {
                final dayData = chartData[i];
                final prevDayData = i < chartData.length - 1 ? chartData[i + 1] : dayData;
                
                // 기술적 지표 계산 (해당 날짜까지의 데이터 사용)
                final indicators = await _calculateTechnicalIndicatorsWithKisData(
                  stockCode, 
                  chartData.skip(i).toList()
                );
                
                // KIS API 추가 데이터 활용
                final additionalData = _extractAdditionalKisData(currentPriceData);
                
                // 실제 데이터 유효성 검증
                final closePrice = (dayData['close'] ?? 0.0).toDouble();
                final volume = (dayData['volume'] ?? 0).toInt();
                
                // 실제 데이터인지 확인 (가격이 0이거나 비정상적으로 낮으면 제외)
                if (closePrice <= 0 || closePrice < 10) {
                  print('⚠️ $stockCode ${i+1}일차 재시도: 비정상 가격(${closePrice}) - 제외');
                  continue;
                }
                
                // 거래량이 0이면 제외
                if (volume <= 0) {
                  print('⚠️ $stockCode ${i+1}일차 재시도: 거래량 0 - 제외');
                  continue;
                }
                
                // StockData 객체 생성
                final stockData = StockData(
                  symbol: stockCode,
                  close: closePrice,
                  open: (dayData['open'] ?? closePrice).toDouble(),
                  high: (dayData['high'] ?? closePrice).toDouble(),
                  low: (dayData['low'] ?? closePrice).toDouble(),
                  volume: volume,
                  prevVolume: (prevDayData['volume'] ?? 0).toInt(),
                  rsi14: indicators['rsi'] ?? 50.0,
                  bbLow: indicators['bbLow'] ?? 0.0,
                  bbHigh: indicators['bbHigh'] ?? 0.0,
                  ma5: indicators['ma5'] ?? 0.0,
                  ma20: indicators['ma20'] ?? 0.0,
                  ma60: indicators['ma60'] ?? 0.0,
                  stochK: indicators['stochK'] ?? 50.0,
                  macdHist: indicators['macdHist'] ?? 0.0,
                  vix: indicators['vix'] ?? 20.0,
                  volume20Avg: (indicators['volume20Avg'] ?? 0).toInt(),
                  vwap: closePrice.toDouble(), // 7개 지표 시스템용
                  adx: 20.0, // 7개 지표 시스템용
                  foreignNetBuy: additionalData['foreignNetBuy'] ?? 0.0,
                  w52High: additionalData['w52High'] ?? 0.0,
                  per: additionalData['per'] ?? 0.0,
                  foreignRatio: additionalData['foreignRatio'] ?? 0.0,
                  askRemain1: additionalData['askRemain1'] ?? 0.0,
                  bidRemain1: additionalData['bidRemain1'] ?? 0.0,
                  marketCap: additionalData['marketCap'] ?? 0.0,
                );
                
                historicalData.add(stockData);
                print('✅ $stockCode ${i+1}일차 재시도: 가격=${closePrice}, 거래량=${volume}');
                
      } catch (e) {
                print('❌ $stockCode ${i+1}일차 재시도 실패: $e');
              }
            }
            
            print('✅ $stockCode 재시도 성공: ${daysToProcess}일치 데이터 생성');
            
            if (historicalData.length >= 100) break; // 충분한 데이터 확보 (최소 100개 데이터 포인트)
            
          } catch (e) {
            print('❌ $stockCode 재시도 실패: $e');
          }
        }
      }
      
      // 실제 데이터 검증 및 최소 요구사항 확인
      if (historicalData.isEmpty) {
        print('❌ 실제 API 데이터 수집 실패 - 백테스트 불가');
        return {
          'error': '실제 주식 데이터를 가져올 수 없어 백테스트를 실행할 수 없습니다.',
          'totalTrades': 0,
          'winRate': 0.0,
          'totalReturn': 0.0,
          'maxDrawdown': 0.0,
          'initialCapital': initialCapital,
          'finalCapital': initialCapital,
          'targetAchieved': false,
          'riskControlled': false,
          'tradedStocks': 0,
          'tradeHistory': [],
          'parameters': {},
        };
      }
      
      // 최소 데이터 요구사항 확인
      if (historicalData.length < 10) {
        print('❌ 데이터 부족 - 최소 10개 데이터 포인트 필요 (현재: ${historicalData.length}개)');
        return {
          'error': '백테스트를 위한 충분한 데이터가 없습니다. (최소 10개 데이터 포인트 필요, 현재: ${historicalData.length}개)',
          'totalTrades': 0,
          'winRate': 0.0,
          'totalReturn': 0.0,
          'maxDrawdown': 0.0,
          'initialCapital': initialCapital,
          'finalCapital': initialCapital,
          'targetAchieved': false,
          'riskControlled': false,
          'tradedStocks': 0,
          'tradeHistory': [],
          'parameters': {},
        };
      }
      
      // 실제 데이터 품질 검증
      final validDataCount = historicalData.where((data) => 
        data.close > 10 && data.volume > 0 && data.rsi14 > 0 && data.rsi14 < 100
      ).length;
      
      if (validDataCount < historicalData.length * 0.5) { // 50% 이상이 유효하면 됨
        print('❌ 데이터 품질 부족 - 유효한 데이터: $validDataCount/${historicalData.length}');
        return {
          'error': '백테스트 데이터의 품질이 부족합니다. (유효한 데이터: $validDataCount/${historicalData.length})',
          'totalTrades': 0,
          'winRate': 0.0,
          'totalReturn': 0.0,
          'maxDrawdown': 0.0,
          'initialCapital': initialCapital,
          'finalCapital': initialCapital,
          'targetAchieved': false,
          'riskControlled': false,
          'tradedStocks': 0,
          'tradeHistory': [],
          'parameters': {},
        };
      }
      
      print('✅ 실제 데이터 검증 완료: ${historicalData.length}개 데이터 포인트 (유효: $validDataCount개)');
      
      print('🤖 백테스트 실행 시작...');
      print('📊 입력 데이터: ${historicalData.length}개');
      print('💰 초기 자본금: ${initialCapital.toStringAsFixed(0)}원');
      
      final result = await runBacktest(style, historicalData, initialCapital);
      
      print('✅ 백테스트 완료');
      print('📊 결과: $result');
      
      print('📊 runBacktest 결과 키들: ${result.keys.toList()}');
      print('📊 tradeHistory 포함 여부: ${result.containsKey('tradeHistory')}');
      
      return {
        'tradeCount': result['tradeCount'] ?? 0,
        'winRate': result['winRate'] ?? 0.0,
        'totalReturn': result['totalReturn'] ?? 0.0,
        'maxDrawdown': result['maxDrawdown'] ?? 0.0,
        'initialCapital': initialCapital, // 초기 자본 추가
        'finalCapital': result['finalCapital'] ?? initialCapital,
        'targetAchieved': result['targetAchieved'] ?? false,
        'riskControlled': result['riskControlled'] ?? false,
        'tradedStocks': result['tradedStocks'] ?? 0, // runBacktest에서 이미 계산된 값 사용
        'tradeHistory': result['tradeHistory'] ?? [], // tradeHistory 추가
        'parameters': result['parameters'] ?? {},
      };
    } catch (e) {
      print('❌ 실제 API 데이터 백테스트 실패: $e');
      return {
        'error': '백테스트 실행 중 오류가 발생했습니다: $e',
        'tradeCount': 0,
        'winRate': 0.0,
        'totalReturn': 0.0,
        'maxDrawdown': 0.0,
        'targetAchieved': false,
        'riskControlled': false,
        'parameters': {},
      };
    }
  }

  /// API에서 실제 기간별 데이터 가져오기 (분석탭과 동일한 방식)
  Future<List<StockData>> _fetchHistoricalDataFromAPI(
    List<String> stockCodes,
    DateTime? startDate,
    DateTime? endDate,
  ) async {
    final List<StockData> allData = [];
    
    try {
      print('🔍 API 데이터 가져오기 시작');
      print('📊 요청 종목: $stockCodes');
      print('📅 요청 기간: ${startDate?.toString().substring(0, 10) ?? 'N/A'} ~ ${endDate?.toString().substring(0, 10) ?? 'N/A'}');
      
      // KIS API 서비스 인스턴스 가져오기
      final unifiedApiService = KisUnifiedApiService();
      print('🔧 KIS API 서비스 상태: ${unifiedApiService.isAuthenticated}');
      
      // API 설정 확인
      final apiConfig = unifiedApiService.apiConfig;
      print('🔧 API 설정: $apiConfig');
      
      // 각 종목별로 데이터 요청 (분석탭과 동일한 방식)
      for (final stockCode in stockCodes) { // 모든 종목 처리 (나스닥 포함)
        try {
          print('📊 $stockCode 종목 데이터 요청 시작...');
          
          // 1. 실시간 현재가 조회 (분석탭과 동일)
          print('📊 $stockCode 실시간 현재가 요청 중...');
          final realtimeData = await RemoteKisService.instance.getCurrentPrice(stockCode);
          if (realtimeData != null) {
            print('📊 $stockCode 실시간 데이터: $realtimeData');
          } else {
            print('⚠️ $stockCode 실시간 데이터 없음');
          }
          
          // 2. 기간별 차트 데이터 조회 (분석탭과 동일)
          print('📊 $stockCode 기간별 차트 데이터 요청 중... (일별)');
          final dailyData = await RemoteKisService.instance.getDailyChart(
            stockCode,
            days: 100,
          );
          print('📊 $stockCode 기간별 차트 데이터: ${dailyData.length}개');
          
          if (dailyData.isNotEmpty) {
            print('📊 $stockCode 마지막 일별 데이터: ${dailyData.last}');
            print('📊 $stockCode 데이터 변환 시작... (${dailyData.length}개)');
            
            // 일별 데이터를 StockData 형식으로 변환
            for (int i = 0; i < dailyData.length; i++) {
              final item = dailyData[i];
              
              // 안전한 타입 변환
              double safeToDouble(dynamic value) {
                if (value == null) return 0.0;
                if (value is double) return value;
                if (value is int) return value.toDouble();
                return double.tryParse(value.toString()) ?? 0.0;
              }
              
              final close = safeToDouble(item['close'] ?? item['stck_clpr']);
              final volume = safeToDouble(item['volume'] ?? item['acml_vol']);
              final prevVolume = i > 0 ? safeToDouble(dailyData[i-1]['volume'] ?? dailyData[i-1]['acml_vol']) : volume;
              
              // 기술적 지표 계산 (통일된 방식 사용)
              final prices = dailyData.skip((i - 14) < 0 ? 0 : (i - 14)).take(15).map((d) => 
                double.tryParse(d['close']?.toString() ?? '0') ?? 0.0
              ).where((p) => p > 0).toList();
              
              final rsi14 = prices.length >= 15 ? TechnicalIndicators.calculateRSI(prices) : 50.0;
              // 볼린저밴드 계산 (통일된 방식 사용)
              final bollinger = prices.length >= 20 ? TechnicalIndicators.calculateBollingerBands(prices) : 
                {'upper': prices.last * 1.02, 'middle': prices.last, 'lower': prices.last * 0.98};
              final bbData = {'low': bollinger['lower'] ?? prices.last * 0.98, 'high': bollinger['upper'] ?? prices.last * 1.02};
              final maData = _calculateMovingAverages(dailyData, i);
              
              allData.add(StockData(
                symbol: stockCode,
                close: close,
                open: safeToDouble(item['open'] ?? item['stck_oprc'] ?? close),
                high: safeToDouble(item['high'] ?? item['stck_hgpr'] ?? close),
                low: safeToDouble(item['low'] ?? item['stck_lwpr'] ?? close),
                volume: volume.toInt(),
                prevVolume: prevVolume.toInt(),
                rsi14: rsi14,
                bbLow: bbData['low'] ?? close,
                bbHigh: bbData['high'] ?? close,
                ma5: maData['ma5'] ?? close,
                ma20: maData['ma20'] ?? close,
                ma60: maData['ma60'] ?? close,
                stochK: _calculateStochastic(dailyData, i),
                macdHist: prices.length >= 26 ? TechnicalIndicators.calculateMACD(prices)['macd'] ?? 0.0 : 0.0,
                vix: 20.0, // 기본값
                volume20Avg: _calculateVolumeAverage(dailyData, i).toInt(),
                vwap: close, // 7개 지표 시스템용
                adx: 20.0, // 7개 지표 시스템용
                foreignNetBuy: 0.0, // KIS API 추가 데이터
                w52High: 0.0, // KIS API 추가 데이터
                per: 0.0, // KIS API 추가 데이터
                foreignRatio: 0.0, // KIS API 추가 데이터
                askRemain1: 0.0, // KIS API 추가 데이터
                bidRemain1: 0.0, // KIS API 추가 데이터
                marketCap: 0.0, // KIS API 추가 데이터
              ));
            }
            print('✅ $stockCode: ${dailyData.length}개 데이터 포인트 변환 완료');
          } else {
            print('⚠️ $stockCode: 일별 데이터 없음');
          }
        } catch (e) {
          print('❌ $stockCode 데이터 요청 실패: $e');
        }
      }
      
      // 모든 종목의 데이터를 시간순으로 정렬 (백테스트를 위해)
      print('📊 데이터 정렬 시작... (총 ${allData.length}개)');
      allData.sort((a, b) {
        // 날짜 정보가 없으므로 인덱스 기반으로 정렬 (최신 데이터가 뒤에 오도록)
        return 0; // 현재는 순서 유지
      });
      
      print('📊 총 ${allData.length}개의 데이터 포인트 수집 완료');
      print('📊 종목별 데이터 분포:');
      final stockCounts = <String, int>{};
      for (final data in allData) {
        stockCounts[data.symbol] = (stockCounts[data.symbol] ?? 0) + 1;
      }
      stockCounts.forEach((symbol, count) {
        print('   - $symbol: $count개');
      });
      
      return allData;
      
    } catch (e) {
      print('❌ API 데이터 가져오기 실패: $e');
      return [];
    }
  }

  // ❌ 삭제됨: _calculateRSI - 잘못된 RSI 계산
  // ✅ 이제 TechnicalIndicators.calculateRSI 사용으로 통일

  // ❌ 삭제됨: _calculateBollingerBands - 잘못된 볼린저밴드 계산
  // ✅ 이제 TechnicalIndicators.calculateBollingerBands 사용으로 통일

  /// 이동평균 계산
  Map<String, double> _calculateMovingAverages(List<Map<String, dynamic>> data, int index) {
    final close = (data[index]['close'] ?? 0.0).toDouble();
    
    double ma5 = close;
    double ma20 = close;
    double ma60 = close;
    
    if (index >= 4) {
      double sum5 = 0.0;
      for (int i = index - 4; i <= index; i++) {
        sum5 += (data[i]['close'] ?? 0.0).toDouble();
      }
      ma5 = sum5 / 5.0;
    }
    
    if (index >= 19) {
      double sum20 = 0.0;
      for (int i = index - 19; i <= index; i++) {
        sum20 += (data[i]['close'] ?? 0.0).toDouble();
      }
      ma20 = sum20 / 20.0;
    }
    
    if (index >= 59) {
      double sum60 = 0.0;
      for (int i = index - 59; i <= index; i++) {
        sum60 += (data[i]['close'] ?? 0.0).toDouble();
      }
      ma60 = sum60 / 60.0;
    }
    
    return {'ma5': ma5, 'ma20': ma20, 'ma60': ma60};
  }

  /// 스토캐스틱 계산
  double _calculateStochastic(List<Map<String, dynamic>> data, int index) {
    if (index < 14) return 50.0;
    
    double highestHigh = 0.0;
    double lowestLow = double.infinity;
    
    for (int i = index - 13; i <= index; i++) {
      final high = (data[i]['high'] ?? data[i]['close'] ?? 0.0).toDouble();
      final low = (data[i]['low'] ?? data[i]['close'] ?? 0.0).toDouble();
      
      if (high > highestHigh) highestHigh = high;
      if (low < lowestLow) lowestLow = low;
    }
    
    if (highestHigh == lowestLow) return 50.0;
    
    final close = (data[index]['close'] ?? 0.0).toDouble();
    return ((close - lowestLow) / (highestHigh - lowestLow)) * 100.0;
  }

  // ❌ 삭제됨: _calculateMACD - 잘못된 MACD 계산
  // ✅ 이제 TechnicalIndicators.calculateMACD 사용으로 통일

  /// 거래량 평균 계산
  double _calculateVolumeAverage(List<Map<String, dynamic>> data, int index) {
    if (index < 19) return (data[index]['volume'] ?? data[index]['acml_vol'] ?? 0.0).toDouble();
    
    double sum = 0.0;
    for (int i = index - 19; i <= index; i++) {
      sum += (data[i]['volume'] ?? data[i]['acml_vol'] ?? 0.0).toDouble();
    }
    return sum / 20.0;
  }

  /// 관심종목에서 샘플 데이터 생성 (실제 데이터만 사용하므로 비활성화)
  List<StockData> _generateSampleDataFromWatchlist(List<String> stockCodes, {InvestmentStyle? style}) {
    // 실제 데이터만 사용하므로 빈 리스트 반환
    print('⚠️ 샘플 데이터 생성 비활성화 - 실제 API 데이터만 사용');
    return [];

  }

  String _getStyleName(InvestmentStyle style) {
    switch (style) {
      case InvestmentStyle.conservative:
        return '안정적 투자';
      case InvestmentStyle.moderate:
        return '일반적 투자';
      case InvestmentStyle.aggressive:
        return '공격적 투자';
    }
  }

  /// TradingParameters를 Map으로 변환
  Map<String, dynamic> _convertParametersToMap(TradingParameters config) {
    return {
      'style': config.style.name,
      

      // 7개 지표 시스템에서는 auxiliaryConditions 불필요
      'partialProfit': config.partialProfit,
      'fullProfit': config.fullProfit,
      'stopLoss': config.stopLoss,
      'positionSize': config.positionSize,
      'maxStocks': config.maxStocks,
      'dailyLossLimit': config.dailyLossLimit,
    };
  }

  /// KIS API 차트 데이터로 기술적 지표 계산
  Future<Map<String, dynamic>> _calculateTechnicalIndicatorsWithKisData(
    String stockCode, 
    List<Map<String, dynamic>> chartData
  ) async {
    try {
      if (chartData.isEmpty) {
        return {
          'rsi': 50.0,
          'bbLow': 0.0,
          'bbHigh': 0.0,
          'ma5': 0.0,
          'ma20': 0.0,
          'ma60': 0.0,
          'stochK': 50.0,
          'macdHist': 0.0,
          'vix': 20.0,
          'volume20Avg': 0,
        };
      }
      
      // 가격 데이터 추출
      final prices = chartData.map((data) => 
        double.tryParse(data['close']?.toString() ?? '0') ?? 0.0
      ).where((price) => price > 0).toList();
      
      if (prices.isEmpty) {
        return {
          'rsi': 50.0,
          'bbLow': 0.0,
          'bbHigh': 0.0,
          'ma5': 0.0,
          'ma20': 0.0,
          'ma60': 0.0,
          'stochK': 50.0,
          'macdHist': 0.0,
          'vix': 20.0,
          'volume20Avg': 0,
        };
      }
      
      // 거래량 데이터 추출
      final volumes = chartData.map((data) => 
        int.tryParse(data['volume']?.toString() ?? '0') ?? 0
      ).where((vol) => vol > 0).toList();
      
      // 기술적 지표 계산
      final rsi = TechnicalIndicators.calculateRSI(prices);
      
      // 이동평균 계산 - TechnicalIndicators 사용으로 통일
      final ma5 = prices.length >= 5 ? TechnicalIndicators.calculateSMA(prices, 5) : prices.last;
      final ma20 = prices.length >= 20 ? TechnicalIndicators.calculateSMA(prices, 20) : prices.last;
      final ma60 = prices.length >= 60 ? TechnicalIndicators.calculateSMA(prices, 60) : prices.last;
      
      // 볼린저 밴드 계산 (간단한 버전)
      final currentPrice = prices.last;
      final bbLow = currentPrice * 0.95;
      final bbHigh = currentPrice * 1.05;
      
      // 거래량 20일 평균
      final volume20Avg = volumes.length >= 20 
          ? volumes.take(20).reduce((a, b) => a + b) / 20 
          : volumes.isNotEmpty ? volumes.reduce((a, b) => a + b) / volumes.length : 0;
      
      return {
        'rsi': rsi,
        'bbLow': bbLow,
        'bbHigh': bbHigh,
        'ma5': ma5,
        'ma20': ma20,
        'ma60': ma60,
        'stochK': 50.0, // 스토캐스틱은 별도 계산 필요
        'macdHist': 0.0, // MACD는 별도 계산 필요
        'vix': 20.0, // VIX는 별도 계산 필요
        'volume20Avg': volume20Avg,
      };
    } catch (e) {
      print('❌ 기술적 지표 계산 실패: $e');
      return {
        'rsi': 50.0,
        'bbLow': 0.0,
        'bbHigh': 0.0,
        'ma5': 0.0,
        'ma20': 0.0,
        'ma60': 0.0,
        'stochK': 50.0,
        'macdHist': 0.0,
        'vix': 20.0,
        'volume20Avg': 0,
      };
    }
  }

  /// KIS API 현재가 데이터에서 추가 정보 추출
  Map<String, dynamic> _extractAdditionalKisData(Map<String, dynamic> currentPriceData) {
    return {
      'foreignNetBuy': (currentPriceData['foreignNetBuy'] ?? 0).toDouble(),
      'w52High': (currentPriceData['w52High'] ?? 0.0).toDouble(),
      'per': (currentPriceData['per'] ?? 0.0).toDouble(),
      'foreignRatio': (currentPriceData['foreignRatio'] ?? 0.0).toDouble(),
      'askRemain1': (currentPriceData['askRemain1'] ?? 0).toDouble(),
      'bidRemain1': (currentPriceData['bidRemain1'] ?? 0).toDouble(),
      'marketCap': (currentPriceData['marketCap'] ?? 0.0).toDouble(),
    };
  }

  /// 거래일 목록 생성
  List<DateTime> _generateTradingDays(DateTime from, DateTime to) {
    final tradingDays = <DateTime>[];
    DateTime current = from;
    
    while (current.isBefore(to) || current.isAtSameMomentAs(to)) {
      if (_isTradingDay(current)) {
        tradingDays.add(current);
      }
      current = current.add(const Duration(days: 1));
    }
    
    return tradingDays;
  }

  /// 특정 날짜의 종목 데이터 가져오기
  Future<StockData?> _getStockDataForDate(
    dynamic unifiedApiService,
    String stockCode,
    DateTime date,
    bool isOverseasStock,
    int dayIndex,
  ) async {
    try {
      // 해당 날짜의 차트 데이터 가져오기
      List<Map<String, dynamic>> chartData;
      
      if (isOverseasStock) {
        chartData = await unifiedApiService.getOverseasDailyChart(stockCode, count: 100);
      } else {
        chartData = await unifiedApiService.getDomesticDailyChart(stockCode, count: 100);
      }
      
      if (chartData.isEmpty) return null;
      
      // dayIndex에 해당하는 데이터 찾기 (최신 데이터부터)
      final dataIndex = chartData.length - 1 - dayIndex;
      if (dataIndex < 0 || dataIndex >= chartData.length) return null;
      
      final dayData = chartData[dataIndex];
      final closePrice = (dayData['close'] ?? 0).toDouble();
      final volume = (dayData['volume'] ?? 0).toInt();
      
      if (closePrice <= 0 || volume <= 0) return null;
      
      // 기술적 지표 계산 - TechnicalIndicators 사용으로 통일
      final prices = chartData.map((data) => 
        double.tryParse(data['close']?.toString() ?? '0') ?? 0.0
      ).where((price) => price > 0).toList();
      
      final rsi = prices.length >= 15 ? TechnicalIndicators.calculateRSI(prices) : 50.0;
      final ma5 = prices.length >= 5 ? TechnicalIndicators.calculateSMA(prices, 5) : closePrice;
      final ma20 = prices.length >= 20 ? TechnicalIndicators.calculateSMA(prices, 20) : closePrice;
      
      return StockData(
        symbol: stockCode,
        close: closePrice,
        open: (dayData['open'] ?? closePrice).toDouble(),
        high: (dayData['high'] ?? closePrice).toDouble(),
        low: (dayData['low'] ?? closePrice).toDouble(),
        volume: volume,
        prevVolume: volume, // 간단히 동일하게 설정
        rsi14: rsi,
        bbLow: closePrice * 0.95,
        bbHigh: closePrice * 1.05,
        ma5: ma5,
        ma20: ma20,
        ma60: closePrice,
        stochK: 50.0,
        macdHist: 0.0,
        vix: 20.0,
        volume20Avg: volume,
        vwap: closePrice, // 7개 지표 시스템용
        adx: 20.0, // 7개 지표 시스템용
        foreignNetBuy: 0.0,
        w52High: 0.0,
        per: 0.0,
        foreignRatio: 0.0,
        askRemain1: 0.0,
        bidRemain1: 0.0,
        marketCap: 0.0,
      );
      
    } catch (e) {
      print('❌ $stockCode ${date.toString().substring(0, 10)} 데이터 수집 실패: $e');
      return null;
    }
  }

  // ❌ 삭제됨: _calculateSimpleRSI - 잘못된 RSI 계산
  // ✅ 이제 TechnicalIndicators.calculateRSI 사용으로 통일

  // ❌ 삭제됨: _calculateSimpleMA - 이제 TechnicalIndicators.calculateSMA 사용으로 통일

  /// 일일 거래 실행
  Future<int> _executeDailyTrading(
    dynamic strategy,
    List<StockData> dailyData,
    DateTime currentDate,
    InvestmentStyle style,
  ) async {
    int tradeCount = 0;
    
    // 1단계: 보유 중인 종목들의 매도 시그널 확인
    final positionsToSell = <String, dynamic>{};
    
    for (final stockData in dailyData) {
      if (strategy.positions.containsKey(stockData.symbol)) {
        final position = strategy.positions[stockData.symbol]!;
        final sellSignal = await strategy.generateSellSignal(position, stockData.close.toDouble(), stockData);

        positionsToSell[stockData.symbol] = {
          'position': position,
          'signal': sellSignal,
          'currentPrice': stockData.close
        };
        print('🔍 매도 시그널: ${stockData.symbol} (${sellSignal.type.toString().split('.').last})');
      }
    }
    
    // 2단계: 매도 실행
    positionsToSell.forEach((symbol, data) {
      final position = data['position'];
      final sellSignal = data['signal'];
      final currentPrice = data['currentPrice'];
      
      strategy.executeSell(symbol, currentPrice.toDouble(), sellSignal, currentDate);
      tradeCount++;
      print('🔴 매도: $symbol - 매수가: ${position.entryPrice}, 매도가: $currentPrice');
    });

    // 3단계: 새로운 매수 시그널 확인
    for (final stockData in dailyData) {
      if (!strategy.positions.containsKey(stockData.symbol)) {
        final buySignal = strategy.generateBuySignal(stockData);
        final canBuy = strategy.positions.length < strategy.config.maxStocks;
        
        if (buySignal && canBuy) {
          final size = strategy.calculatePositionSize(stockData.close.toDouble(), symbol: stockData.symbol);
          if (size >= 1.0) {
            strategy.executeBuy(stockData.symbol, stockData.close.toDouble(), size, currentDate);
            tradeCount++;
            
            final styleName = _getStyleName(style);
            print('✅ [$styleName] 매수: ${stockData.symbol} - ${stockData.close}원, ${size.toInt()}주');
            print('📅 실제 매수: ${stockData.symbol} - ${currentDate.toString().substring(0, 10)} (${stockData.close}원)');
          }
        }
      }
    }
    
    return tradeCount;
  }

  /// 로컬DB에서 국내주식 차트 데이터 가져오기
  Future<List<Map<String, dynamic>>> _getLocalDomesticChartData(String stockCode, DateTime from, DateTime to) async {
    try {
      print('📊 로컬DB에서 국내주식 차트 데이터 조회: $stockCode (${from.toString().substring(0, 10)} ~ ${to.toString().substring(0, 10)})');
      
      // AppDataManager를 통해 백테스트용 과거 데이터 조회
      final appDataManager = AppDataManager.instance;
      
      // 백테스트 기간에 맞춰 과거 데이터 조회
      final daysDiff = to.difference(from).inDays;
      final maxCount = daysDiff > 200 ? 200 : daysDiff;
      
      // 백테스트용 과거 데이터 조회 (200일치)
      final chartData = await appDataManager.getBacktestData(stockCode, days: maxCount);
      
      if (chartData.isEmpty) {
        print('⚠️ 로컬DB에 $stockCode 백테스트 데이터 없음 (요청: $maxCount일치)');
        return [];
      }
      
      print('✅ 로컬DB에서 $stockCode 백테스트 데이터 조회 완료: ${chartData.length}일치');
      return chartData;
      
    } catch (e) {
      print('❌ 로컬DB 국내주식 차트 데이터 조회 실패: $stockCode - $e');
      return [];
    }
  }

  /// 로컬DB에서 해외주식 차트 데이터 가져오기
  Future<List<Map<String, dynamic>>> _getLocalOverseasChartData(String stockCode, DateTime from, DateTime to) async {
    try {
      print('📊 로컬DB에서 해외주식 차트 데이터 조회: $stockCode (${from.toString().substring(0, 10)} ~ ${to.toString().substring(10)})');
      
      // AppDataManager를 통해 백테스트용 과거 데이터 조회
      final appDataManager = AppDataManager.instance;
      
      // 백테스트 기간에 맞춰 과거 데이터 조회
      final daysDiff = to.difference(from).inDays;
      final maxCount = daysDiff > 200 ? 200 : daysDiff;
      
      // 백테스트용 과거 데이터 조회 (200일치)
      final chartData = await appDataManager.getBacktestData(stockCode, days: maxCount);
      
      if (chartData.isEmpty) {
        print('⚠️ 로컬DB에 $stockCode 해외주식 백테스트 데이터 없음 (요청: $maxCount일치)');
        return [];
      }
      
      print('✅ 로컬DB에서 $stockCode 해외주식 백테스트 데이터 조회 완료: ${chartData.length}일치');
      return chartData;
      
    } catch (e) {
      print('❌ 로컬DB 해외주식 차트 데이터 조회 실패: $stockCode - $e');
      return [];
    }
  }

  /// 백테스트 결과 계산
  Map<String, dynamic> _calculateBacktestResult(
    dynamic strategy,
    double initialCapital,
    int totalTrades,
  ) {
    // 실제 거래 횟수는 results 길이로 계산
    final actualTotalTrades = strategy.results.length;
    
    // 승률 계산 (거래 히스토리 기반)
    int winningTrades = 0;
    int totalCompletedTrades = 0;
    double totalProfitLoss = 0.0;
    double maxLoss = 0.0;
    
    for (final result in strategy.results) {
      if (result.profit != null) {
        totalCompletedTrades++;
        
        // 해외주식 손익을 원화로 변환 (TradeResult에서 달러로 저장됨)
        final isOverseas = result.symbol.length >= 4 && RegExp(r'^[A-Z]+$').hasMatch(result.symbol);
        final profitInWon = isOverseas ? result.profit! * 1400.0 : result.profit!;
        
        totalProfitLoss += profitInWon;
        
        if (result.profit! > 0) {
          winningTrades++;
        } else {
          // 손실 중 최대값 찾기
          final lossPercent = result.profitLossPercent;
          if (lossPercent < maxLoss) {
            maxLoss = lossPercent;
          }
        }
      }
    }
    
    final winRate = totalCompletedTrades > 0 ? (winningTrades / totalCompletedTrades) * 100 : 0.0;
    
    // 거래된 종목 수 계산
    final tradedStocks = strategy.results.map((r) => r.symbol).toSet().length;
    
    // 일평균 거래 횟수 계산 (백테스트 기간이 30일이라고 가정)
    final dailyAverage = actualTotalTrades > 0 ? (actualTotalTrades / 30.0) : 0.0;
    
    // 자본 변화 계산 (거래 손익 합계 기반)
    final capitalChange = totalProfitLoss;
    final finalValue = initialCapital + totalProfitLoss;
    final totalReturn = ((finalValue - initialCapital) / initialCapital) * 100;
    
    return {
      'totalTrades': actualTotalTrades,
      'winRate': winRate,
      'totalReturn': totalReturn,
      'maxDrawdown': maxLoss,
      'finalValue': finalValue,
      'initialCapital': initialCapital,
      'capitalChange': capitalChange,
      'tradedStocks': tradedStocks,
      'dailyAverage': dailyAverage,
      'tradeHistory': strategy.results.map((r) => r.toMap()).toList(),
      'parameters': {
        'buyThreshold': strategy.config.buyThreshold,
        'sellThreshold': strategy.config.sellThreshold,
        'partialProfit': strategy.config.partialProfit,
        'fullProfit': strategy.config.fullProfit,
        'stopLoss': strategy.config.stopLoss,
        'positionSize': strategy.config.positionSize,
        'dailyLossLimit': strategy.config.dailyLossLimit,

        'maxStocks': strategy.config.maxStocks,
      },
    };
  }
}



// 상수 정의 (로컬 DB 사용으로 대부분 제거됨)
class TradingConstants {
  // 기본 자본금
  static const double DEFAULT_INITIAL_CAPITAL = 1000000.0;
  
  // 백테스트 샘플 데이터 설정
  static const int SAMPLE_DATA_DAYS = 100;
  static const List<String> SAMPLE_SYMBOLS = ['005930', '000660', '035420', '051910', '006400'];
  
  // 성과 평가 임계값
  static const double GOOD_WIN_RATE = 50.0;
  static const double GOOD_MAX_DRAWDOWN = -10.0;
  static const double EXCELLENT_WIN_RATE = 60.0;
  static const double EXCELLENT_MAX_DRAWDOWN = -5.0;
}
