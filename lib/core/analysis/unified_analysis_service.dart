import 'dart:async';
import 'dart:math';
import '../data/app_data_manager.dart';
import '../database/repositories/signal_history_repository.dart';
import '../database/repositories/realtime_data_repository.dart';
import '../database/repositories/historical_data_repository.dart';
import '../database/repositories/chart_data_repository.dart';
import '../trading/market_time_validator.dart';
import '../trading/investment_style_manager.dart';
import '../trading/investment_style.dart';
import 'dynamicCal/comprehensive_indicator_calculator.dart';
import 'technical_indicators.dart';
import '../api/kis_unified_api_service.dart';
import '../constants/chart_constants.dart';
import '../api/kis_unified_api_service_charts.dart';
import '../data/stock_master_parser.dart';

/// 통합된 분석 서비스
/// 분석탭과 자동매매에서 동일한 로직을 사용하도록 통합
class UnifiedAnalysisService {
  static UnifiedAnalysisService? _instance;
  static UnifiedAnalysisService get instance => _instance ??= UnifiedAnalysisService._();
  
  UnifiedAnalysisService._();

  // 간단한 성공 캐시 (메모리) - 빈 데이터가 아닌 마지막 성공 차트 저장
  final Map<String, List<Map<String, dynamic>>> _chartCache = {};

  // AppDataManager는 필요할 때만 참조 (순환 참조 방지)
  AppDataManager get _appDataManager => AppDataManager.instance;
  final SignalHistoryRepository _signalRepo = SignalHistoryRepository();
  final InvestmentStyleManager _styleManager = InvestmentStyleManager();
  final RealtimeDataRepository _realtimeDataRepo = RealtimeDataRepository();
  final HistoricalDataRepository _historicalDataRepo = HistoricalDataRepository();

  /// 종목 분석 실행 (통합된 로직)
  Future<Map<String, dynamic>?> analyzeStock(
    String stockCode, {
    double? currentPrice,
    double? prevClose,
    double? volume,
    double? highPrice,
    double? lowPrice,
    double? openPrice,
    InvestmentStyle? investmentStyle,
  }) async {
    try {
      print('🔍 [UnifiedAnalysis] $stockCode 종목 분석 시작');
      
      // 1. 현재 투자 스타일 설정 로드 (전달받은 스타일 또는 기본값 사용)
      final styleToUse = investmentStyle ?? _styleManager.currentStyle;
      final styleParams = await _styleManager.getStyleParameters(styleToUse);
      final buyThreshold = (styleParams['buyThreshold'] as num?)?.toDouble();
      final sellThreshold = (styleParams['sellThreshold'] as num?)?.toDouble();
      final volumeCondition = (styleParams['volumeCondition'] as num?)?.toDouble();
      
      if (buyThreshold == null || sellThreshold == null) {
        print('❌ [UnifiedAnalysis] 투자 스타일 임계값이 설정되지 않았습니다.');
        return null;
      }
      
      print('📊 [UnifiedAnalysis] 분석 기준 (로컬DB 사용자 설정):');
      print('   - 매수임계: $buyThreshold');
      print('   - 매도임계: $sellThreshold');
      print('   - 거래량조건: $volumeCondition');
      print('   - 사용된 스타일: ${styleToUse.name}');
      print('   - 전달받은 스타일: ${investmentStyle?.name ?? 'null'}');
      print('   - 기본 스타일: ${_styleManager.currentStyle.name}');
      print('   - 호출 시점: ${DateTime.now()}');
      print('   - 호출 위치: ${StackTrace.current.toString().split('\n')[1]}');

      // 2. 시장 데이터 가져오기
      final marketData = await _getMarketData(stockCode);
      if (marketData == null) {
        print('❌ [UnifiedAnalysis] 시장 데이터 없음: $stockCode');
        return null;
      }

      // 3. 현재가 업데이트 (API 실패 시 히스토리/전일가로 보정)
      double price = currentPrice ?? (marketData['currentPrice'] as double? ?? 0.0);
      
      print('🔍 [UnifiedAnalysis] 현재가 결정 과정: $stockCode');
      print('  - 파라미터 currentPrice: $currentPrice');
      print('  - marketData currentPrice: ${marketData['currentPrice']}');
      print('  - 초기 price: $price');
      
      if (price <= 0) {
        final priceHistory = (marketData['priceHistory'] as List<double>?) ?? const [];
        final fallbackFromHistory = priceHistory.isNotEmpty ? priceHistory.last : 0.0;
        final fallbackPrevClose = (marketData['prevClose'] as double? ?? 0.0);
        
        print('🔁 [UnifiedAnalysis] 현재가 폴백 시도: $stockCode');
        print('  - priceHistory 개수: ${priceHistory.length}');
        print('  - 히스토리 최신가: $fallbackFromHistory');
        print('  - 전일 종가: $fallbackPrevClose');
        
        price = fallbackFromHistory > 0 ? fallbackFromHistory : fallbackPrevClose;
        print('  - 폴백 후 price: $price');
        
        // 여전히 0이면 차트 데이터에서 직접 조회 시도
        if (price <= 0) {
          print('🔍 [UnifiedAnalysis] 차트 데이터에서 직접 현재가 조회 시도: $stockCode');
          try {
            final chartRepo = ChartDataRepository();
            final recentChartData = await chartRepo.getChartData(stockCode, limit: 1);
            if (recentChartData.isNotEmpty) {
              final latestChart = recentChartData.last;
              price = (latestChart['close'] as num?)?.toDouble() ?? 0.0;
              print('🔁 [UnifiedAnalysis] 차트 데이터에서 폴백: $price');
            }
          } catch (e) {
            print('⚠️ [UnifiedAnalysis] 차트 데이터 조회 실패: $e');
          }
        }
      }
      
      if (price <= 0) {
        print('❌ [UnifiedAnalysis] 유효하지 않은 가격: $price');
        print('❌ [UnifiedAnalysis] marketData 전체: $marketData');
        return null;
      }
      
      print('✅ [UnifiedAnalysis] 최종 현재가: $price');

      // 4. 정규장 시간 체크
      final market = MarketTimeValidator.instance.getMarketFromSymbol(stockCode);
      final tradingInfo = MarketTimeValidator.instance.getCurrentTradingInfo(market);
      final isTradingTime = tradingInfo['isTrading'] as bool;
      
      print('📊 [UnifiedAnalysis] 정규장 시간 체크: ${tradingInfo['status']} (${tradingInfo['reason']})');

      // 5. 기술적 지표 데이터 가져오기
      final technicalData = await _getTechnicalIndicators(stockCode, marketData);
      
      // 6. 데이터 유효성 검증 및 보강
      final validatedData = await _validateAndEnhanceData(stockCode, price, technicalData, marketData, openPrice);
      if (validatedData == null) {
        print('❌ [UnifiedAnalysis] 데이터 유효성 검증 실패: $stockCode');
        return null;
      }
      
      // 7. 종합 점수 계산 (ComprehensiveIndicatorCalculator가 모든 동적 지표 계산을 처리)
      final now = DateTime.now();
      final currentTimeString = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      
      // ComprehensiveIndicatorCalculator에 맞는 키 이름으로 데이터 변환
      print('🔍 [UnifiedAnalysis] validatedData 키 확인:');
      print('  - validatedData 키: ${validatedData.keys.toList()}');
      print('  - rsi 값: ${validatedData['rsi']}');
      print('  - macd 값: ${validatedData['macd']}');
      print('  - signal 값: ${validatedData['signal']}');
      print('  - bbUpper 값: ${validatedData['bbUpper']}');
      print('  - vwap 값: ${validatedData['vwap']}');
      print('  - adx 값: ${validatedData['adx']}');
      
      final calculatorData = {
        'currentPrice': validatedData['currentPrice'],
        'previousPrice': validatedData['previousPrice'],
        'openPrice': validatedData['openPrice'], // 🔧 시가 추가
        'currentVolume': validatedData['currentVolume'],
        'averageVolume': validatedData['averageVolume'],
        'rsiValue': validatedData['rsiValue'] ?? validatedData['rsi'], // 🔧 키 불일치 수정
        'macdValue': validatedData['macdValue'] ?? validatedData['macd'], // 🔧 키 불일치 수정
        'signalValue': validatedData['signalValue'] ?? validatedData['signal'], // 🔧 키 불일치 수정
        'upperBand': validatedData['upperBand'] ?? validatedData['bbUpper'], // 🔧 키 불일치 수정
        'middleBand': validatedData['middleBand'] ?? validatedData['bbMiddle'], // 🔧 키 불일치 수정
        'lowerBand': validatedData['lowerBand'] ?? validatedData['bbLower'], // 🔧 키 불일치 수정
        'ma5': validatedData['ma5'],
        'ma20': validatedData['ma20'],
        'ma60': validatedData['ma60'],
        'vwapValue': validatedData['vwapValue'] ?? validatedData['vwap'], // 🔧 키 불일치 수정
        'adxValue': validatedData['adxValue'] ?? validatedData['adx'], // 🔧 키 불일치 수정
        'currentATR': validatedData['currentATR'] ?? validatedData['atr'], // 🔧 키 불일치 수정
        'averageATR': validatedData['averageATR'] ?? validatedData['avgAtr'], // 🔧 키 불일치 수정
        'currentTime': currentTimeString,
      };
      
      print('🔍 [UnifiedAnalysis] calculatorData 변환 결과:');
      print('  - rsiValue: ${calculatorData['rsiValue']}');
      print('  - macdValue: ${calculatorData['macdValue']}');
      print('  - signalValue: ${calculatorData['signalValue']}');
      print('  - upperBand: ${calculatorData['upperBand']}');
      print('  - vwapValue: ${calculatorData['vwapValue']}');
      print('  - adxValue: ${calculatorData['adxValue']}');
      
      print('🔍 [UnifiedAnalysis] ComprehensiveIndicatorCalculator 호출 전 데이터:');
      print('  - stockCode: $stockCode');
      print('  - currentTime: $currentTimeString');
      print('  - buyThreshold: $buyThreshold');
      print('  - sellThreshold: $sellThreshold');
      print('  - calculatorData 키: ${calculatorData.keys.toList()}');
      
      print('🔍 [UnifiedAnalysis] @dynamicCal ComprehensiveIndicatorCalculator 호출');
      final comprehensiveResult = ComprehensiveIndicatorCalculator.calculateComprehensiveScore(
        indicatorData: calculatorData,
        currentTime: currentTimeString,
        buyThreshold: buyThreshold,
        sellThreshold: sellThreshold,
      );
      
      print('🔍 [UnifiedAnalysis] @dynamicCal 계산 결과:');
      print('  - comprehensiveScore: ${comprehensiveResult['comprehensiveScore']}');
      print('  - tradingDecision: ${comprehensiveResult['tradingDecision']}');
      print('  - signal: ${comprehensiveResult['signal']}');
      print('  - confidence: ${comprehensiveResult['confidence']}');
      print('  - individualScores: ${comprehensiveResult['individualScores']}');

      // 8. 결과 추출
      final comprehensiveScore = (comprehensiveResult['comprehensiveScore'] as num?)?.toDouble() ?? 0.0;
      final individualScores = (comprehensiveResult['individualScores'] as Map<String, dynamic>?) ?? {};
      final contributions = (comprehensiveResult['contributions'] as Map<String, dynamic>?) ?? {};
      final detailedAnalysis = (comprehensiveResult['detailedAnalysis'] as Map<String, dynamic>?) ?? {};
      final tradingDecision = (comprehensiveResult['tradingDecision'] as String?) ?? 'HOLD';
      final signal = (comprehensiveResult['signal'] as String?) ?? '관망';
      final confidence = (comprehensiveResult['confidence'] as num?)?.toDouble() ?? 0.0;
      final targetPrice = (comprehensiveResult['targetPrice'] as num?)?.toDouble() ?? price;

      // 9. 점수 유효성 최종 검증 (너무 엄격한 조건 완화)
      if (comprehensiveScore.isNaN || comprehensiveScore.isInfinite) {
        print('❌ [UnifiedAnalysis] 종합점수가 유효하지 않음: $comprehensiveScore');
        return null;
      }
      
      // 점수가 0에 가까워도 분석 결과는 반환 (시그널은 '관망'으로 처리됨)
      print('📊 [UnifiedAnalysis] 종합점수 유효성 확인: $comprehensiveScore');

      // 9. 분석 결과 생성
      final result = {
        'stockCode': stockCode,
        'stockName': marketData['stockName'] ?? '',
        'currentPrice': price,
        'openPrice': validatedData['openPrice'], // 🔧 시가 추가
        'comprehensiveScore': comprehensiveScore,
        'individualScores': individualScores,
        'contributions': contributions,
        'detailedAnalysis': detailedAnalysis,
        'tradingDecision': tradingDecision,
        'signal': signal,
        'confidence': confidence,
        'targetPrice': targetPrice,
        'buyThreshold': buyThreshold,
        'sellThreshold': sellThreshold,
        'isTradingTime': isTradingTime,
        'market': market,
        'tradingInfo': tradingInfo,
        'technicalData': technicalData,
        'comprehensiveResult': comprehensiveResult,
        'analysisTime': DateTime.now().toIso8601String(),
        'style': _styleManager.currentStyle.name,
      };

      print('✅ [UnifiedAnalysis] 분석 완료: $stockCode - 점수: ${comprehensiveScore.toStringAsFixed(3)}, 시그널: $signal');
      print('📊 [UnifiedAnalysis] 상세 분석 결과:');
      print('  - 현재가: $price');
      print('  - 종합점수: ${comprehensiveScore.toStringAsFixed(3)}');
      print('  - 개별지표: $individualScores');
      print('  - 기술적지표: ${technicalData.keys.toList()}');
      print('  - 정규장시간: $isTradingTime');
      print('  - 시장: $market');
      print('🔍 [UnifiedAnalysis] 데이터 소스 추적:');
      print('  - 파라미터로 전달된 현재가: $currentPrice');
      print('  - 파라미터로 전달된 전일가: $prevClose');
      print('  - 파라미터로 전달된 거래량: $volume');
      print('  - 파라미터로 전달된 고가: $highPrice');
      print('  - 파라미터로 전달된 저가: $lowPrice');
      print('  - 파라미터로 전달된 시가: $openPrice');
      
      return result;

    } catch (e) {
      print('❌ [UnifiedAnalysis] 분석 실패: $stockCode - $e');
      return null;
    }
  }

  /// 데이터 유효성 검증 및 보강
  Future<Map<String, dynamic>?> _validateAndEnhanceData(
    String stockCode, 
    double currentPrice, 
    Map<String, dynamic> technicalData,
    Map<String, dynamic> marketData,
    double? openPriceParam,
  ) async {
    try {
      print('🔍 [UnifiedAnalysis] 데이터 유효성 검증 및 보강 시작: $stockCode');
      
      // 1. 현재가 유효성 검증
      if (currentPrice <= 0) {
        print('❌ [UnifiedAnalysis] 현재가가 유효하지 않음: $currentPrice');
        return null;
      }
      
      // 2. 이전가 보강 (전일가 → 시가로 변경)
      double previousPrice = (marketData['openPrice'] as double?) ?? 
                           (marketData['prevClose'] as double?) ?? 
                           currentPrice;
      if (previousPrice <= 0) {
        previousPrice = currentPrice;
      }
      
      // 3. 거래량 보강 (타입 안전 처리)
      int _pI(dynamic v) {
        if (v == null) return 0;
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse(v.toString()) ?? 0;
      }

      List<int> _pIList(dynamic list) {
        if (list is List) {
          return list.map((e) => _pI(e)).toList();
        }
        return <int>[];
      }

      int currentVolume = _pI(technicalData['currentVolume']);
      if (currentVolume <= 0) {
        currentVolume = _pI(marketData['volume']);
      }
      if (currentVolume <= 0) {
        final List<int> volumeHistory = _pIList(marketData['volumeHistory']);
        // 과거→최신 순서이므로 마지막 요소가 최신 거래량
        currentVolume = volumeHistory.isNotEmpty ? volumeHistory.last : 0;
        print('📊 [UnifiedAnalysis] 최신 거래량 사용: $currentVolume (히스토리 ${volumeHistory.length}개 중 마지막)');
      }

      int averageVolume = _pI(technicalData['avgVolume']);
      if (averageVolume <= 0) {
        final List<int> volumeHistory = _pIList(marketData['volumeHistory']);
        if (volumeHistory.isNotEmpty) {
          final int takeN = volumeHistory.length >= 20 ? 20 : volumeHistory.length;
          final List<int> window = volumeHistory.take(takeN).toList();
          final int sum = window.fold<int>(0, (acc, v) => acc + v);
          averageVolume = takeN > 0 ? (sum ~/ takeN) : 0;
        } else {
          averageVolume = 0; // 실제값만 사용 (거래량 데이터 없음)
        }
      }
      
      // 4. 기술적 지표 보강 - 기본값 사용 금지, 데이터 없으면 계산 오류 처리
      double? rsiValue = technicalData['rsi'] as double?;
      double? macdValue = technicalData['macd'] as double?;
      double? signalValue = technicalData['signal'] as double?;
      double? upperBand = technicalData['bbUpper'] as double?;
      double? middleBand = technicalData['bbMiddle'] as double?;
      double? lowerBand = technicalData['bbLower'] as double?;
      double? ma5 = technicalData['ma5'] as double?;
      double? ma20 = technicalData['ma20'] as double?;
      double? ma60 = technicalData['ma60'] as double?;
      double? vwapValue = technicalData['vwap'] as double?;
      double? adxValue = technicalData['adx'] as double?;
      double? currentATR = technicalData['atr'] as double?;
      double? averageATR = technicalData['avgAtr'] as double?;
      
      // 5. 최종 유효성 검증 및 기본값 처리 - null 값이나 NaN 값을 기본값으로 대체
      print('🔍 [UnifiedAnalysis] 기술적 지표 값 검증 및 기본값 처리:');
      print('  - RSI: $rsiValue (${rsiValue?.isNaN == true ? 'NaN' : 'OK'})');
      print('  - MACD: $macdValue (${macdValue?.isNaN == true ? 'NaN' : 'OK'})');
      print('  - Signal: $signalValue (${signalValue?.isNaN == true ? 'NaN' : 'OK'})');
      print('  - BB Upper: $upperBand (${upperBand?.isNaN == true ? 'NaN' : 'OK'})');
      print('  - BB Middle: $middleBand (${middleBand?.isNaN == true ? 'NaN' : 'OK'})');
      print('  - BB Lower: $lowerBand (${lowerBand?.isNaN == true ? 'NaN' : 'OK'})');
      print('  - MA5: $ma5 (${ma5?.isNaN == true ? 'NaN' : 'OK'})');
      print('  - MA20: $ma20 (${ma20?.isNaN == true ? 'NaN' : 'OK'})');
      print('  - MA60: $ma60 (${ma60?.isNaN == true ? 'NaN' : 'OK'})');
      print('  - VWAP: $vwapValue (${vwapValue?.isNaN == true ? 'NaN' : 'OK'})');
      print('  - ADX: $adxValue (${adxValue?.isNaN == true ? 'NaN' : 'OK'})');
      print('  - ATR: $currentATR (${currentATR?.isNaN == true ? 'NaN' : 'OK'})');
      print('  - Avg ATR: $averageATR (${averageATR?.isNaN == true ? 'NaN' : 'OK'})');
      
      // ✅ 기본값 사용 금지: null이나 NaN 값은 그대로 유지하여 실제 데이터 부족을 표시
      // 사용자 요청: "기본값 필요없다고했어. 무조건 실제값으로 넣어야해"
      if (rsiValue != null && rsiValue.isNaN) rsiValue = null;
      if (macdValue != null && macdValue.isNaN) macdValue = null;
      if (signalValue != null && signalValue.isNaN) signalValue = null;
      if (upperBand != null && upperBand.isNaN) upperBand = null;
      if (middleBand != null && middleBand.isNaN) middleBand = null;
      if (lowerBand != null && lowerBand.isNaN) lowerBand = null;
      if (ma5 != null && ma5.isNaN) ma5 = null;
      if (ma20 != null && ma20.isNaN) ma20 = null;
      if (ma60 != null && ma60.isNaN) ma60 = null;
      if (vwapValue != null && vwapValue.isNaN) vwapValue = null;
      if (adxValue != null && adxValue.isNaN) adxValue = null;
      if (currentATR != null && currentATR.isNaN) currentATR = null;
      if (averageATR != null && averageATR.isNaN) averageATR = null;
      
      print('✅ [UnifiedAnalysis] 기본값 처리 완료:');
      print('  - RSI: $rsiValue');
      print('  - MACD: $macdValue');
      print('  - Signal: $signalValue');
      print('  - BB: $upperBand/$middleBand/$lowerBand');
      print('  - MA: $ma5/$ma20/$ma60');
      print('  - VWAP: $vwapValue');
      print('  - ADX: $adxValue');
      print('  - ATR: $currentATR/$averageATR');
      
      // 6. 현재 시간
      final now = DateTime.now();
      final currentTimeString = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      
      // 7. 시가 보강 (API 파라미터 우선, marketData 폴백)
      double openPrice = (openPriceParam != null && openPriceParam > 0) ? openPriceParam :
                        (marketData['openPrice'] as double?) ?? 
                        (marketData['highPrice'] as double?) ?? 
                        currentPrice;
      if (openPrice <= 0) {
        openPrice = currentPrice;
      }
      
      print('✅ [UnifiedAnalysis] 시가 보강 완료:');
      print('  - 시가: $openPrice');
      
      final validatedData = {
        'currentPrice': currentPrice,
        'previousPrice': previousPrice,
        'openPrice': openPrice, // 🔧 시가 추가
        'currentVolume': currentVolume,
        'averageVolume': averageVolume,
        'rsiValue': rsiValue,
        'macdValue': macdValue,
        'signalValue': signalValue,
        'upperBand': upperBand,
        'middleBand': middleBand,
        'lowerBand': lowerBand,
        'ma5': ma5,
        'ma20': ma20,
        'ma60': ma60,
        'vwapValue': vwapValue,
        'adxValue': adxValue,
        'currentATR': currentATR,
        'averageATR': averageATR,
        'currentTime': currentTimeString,
      };
      
      print('✅ [UnifiedAnalysis] 데이터 유효성 검증 및 보강 완료: $stockCode');
      print('📊 [UnifiedAnalysis] 보강된 데이터:');
      print('  - 현재가: $currentPrice');
      print('  - 이전가: $previousPrice');
      print('  - 현재거래량: $currentVolume');
      print('  - 평균거래량: $averageVolume');
      print('  - RSI: $rsiValue');
      print('  - MACD: $macdValue');
      
      return validatedData;
      
    } catch (e) {
      print('❌ [UnifiedAnalysis] 데이터 유효성 검증 실패: $stockCode - $e');
      return null;
    }
  }

  /// 시장 데이터 가져오기 (로컬DB 우선)
  Future<Map<String, dynamic>?> _getMarketData(String stockCode) async {
    try {
      print('🔍 [UnifiedAnalysis] 시장 데이터 가져오기 시작: $stockCode');
      
      // 나스닥 종목인지 확인
      final isNasdaq = _isNasdaqStock(stockCode);
      
      // 1. 로컬DB에서 차트 데이터 먼저 확인
      List<Map<String, dynamic>> chartData;
      final localChartData = await _historicalDataRepo.getRecentBars(stockCode, limit: ChartConstants.CHART_MIN_BARS);
      if (localChartData.isNotEmpty) {
        print('📊 [UnifiedAnalysis] 로컬 DB에서 데이터 발견: $stockCode (${localChartData.length}개)');
        chartData = localChartData;
      } else {
        print('📊 [UnifiedAnalysis] 로컬 DB에 데이터 없음, API 호출: $stockCode');
        // 로컬DB에 없을 때만 API 호출 (폴백)
        if (isNasdaq) {
          print('🌍 [UnifiedAnalysis] 나스닥 차트 데이터 조회: $stockCode');
          // 캐시 우선
          if (_chartCache.containsKey(stockCode) && (_chartCache[stockCode]?.isNotEmpty ?? false)) {
            chartData = _chartCache[stockCode]!;
            print('📊 [UnifiedAnalysis] 캐시에서 차트 데이터 사용: $stockCode (${chartData.length}개)');
          } else {
            print('📊 [UnifiedAnalysis] 통합 API에서 차트 데이터 조회: $stockCode');
            chartData = await KisUnifiedApiService().getDailyChart(stockCode, count: ChartConstants.CHART_MIN_BARS);
            print('📊 [UnifiedAnalysis] 통합 API 응답 차트 데이터: $stockCode (${chartData.length}개)');
            
            if (chartData.isNotEmpty) {
              _chartCache[stockCode] = chartData;
              print('✅ [UnifiedAnalysis] 차트 데이터 캐시 저장: $stockCode');
            } else {
              print('❌ [UnifiedAnalysis] 통합 API에서도 차트 데이터 없음: $stockCode');
            }
          }
        } else {
          print('🇰🇷 [UnifiedAnalysis] 통합 API에서 차트 데이터 조회: $stockCode');
          chartData = await KisUnifiedApiService().getDailyChart(stockCode, count: ChartConstants.CHART_MIN_BARS);
        }
      }
      
      // 2. 현재가 데이터 가져오기 (로컬DB 우선)
      Map<String, dynamic>? data;
      
      // 로컬DB에서 실시간 데이터 먼저 확인
      final localRealtimeData = await _realtimeDataRepo.getLatestRealtimeData(stockCode);
      if (localRealtimeData != null) {
        print('📊 [UnifiedAnalysis] 로컬 DB에서 실시간 데이터 발견: $stockCode');
        print('🔍 [UnifiedAnalysis] 로컬 DB 데이터 상세:');
        print('  - 현재가: ${localRealtimeData['current_price']}');
        print('  - 전일가: ${localRealtimeData['prev_close']}');
        print('  - 거래량: ${localRealtimeData['volume']}');
        print('  - 고가: ${localRealtimeData['high_price']}');
        print('  - 저가: ${localRealtimeData['low_price']}');
        print('  - 시가: ${localRealtimeData['open_price']}');
        data = {
          'currentPrice': localRealtimeData['current_price'],
          'prevClose': localRealtimeData['prev_close'],
          'volume': localRealtimeData['volume'],
          'high': localRealtimeData['high_price'],
          'low': localRealtimeData['low_price'],
          'open': localRealtimeData['open_price'],
          'stockName': localRealtimeData['stock_name'] ?? '',
        };
      } else {
        print('📊 [UnifiedAnalysis] 로컬 DB에 실시간 데이터 없음, API 호출: $stockCode');
        // 로컬DB에 없을 때만 API 호출 (폴백)
        try {
          if (isNasdaq) {
            print('🌍 [UnifiedAnalysis] 나스닥 종목 데이터 조회: $stockCode');
            data = await KisUnifiedApiService().getOverseasStockPrice(
              symbol: stockCode,
              exchangeCode: 'NAS',
            );
            if (data == null || (data['prpr'] ?? 0) == 0) {
              final resolved = _resolveUsSymbol(stockCode);
              if (resolved != stockCode) {
                print('🔁 해외 현재가 심볼 교정 재시도: $stockCode -> $resolved');
                data = await KisUnifiedApiService().getOverseasStockPrice(
                  symbol: resolved,
                  exchangeCode: 'NAS',
                );
              }
            }
          } else {
            print('🇰🇷 [UnifiedAnalysis] 국내주식 데이터 조회: $stockCode');
            data = await KisUnifiedApiService().getStockPrice(stockCode);
          }
          
          print('🔍 [UnifiedAnalysis] KIS API 응답: $data');
          if (data != null) {
            print('🔍 [UnifiedAnalysis] API 데이터 상세:');
            print('  - 현재가: ${data['currentPrice']}');
            print('  - 전일가: ${data['prevClose']}');
            print('  - 거래량: ${data['volume']}');
            print('  - 고가: ${data['high']}');
            print('  - 저가: ${data['low']}');
            print('  - 시가: ${data['open']}');
          } else {
            print('🔍 [UnifiedAnalysis] API 데이터가 null입니다.');
          }
          
          if (data == null || data.isEmpty) {
            print('❌ [UnifiedAnalysis] 시장 데이터 없음: $stockCode');
            return null;
          }
        } catch (e) {
          print('❌ [UnifiedAnalysis] API 호출 실패: $stockCode - $e');
          // API 실패 시 로컬 DB에서 히스토리 데이터로 보강
          print('⚠️ [UnifiedAnalysis] 로컬 DB 히스토리 데이터로 폴백: $stockCode');
          return await _getLocalMarketData(stockCode);
        }
      }
      
      // 나스닥 종목의 경우 현재가 API 응답을 차트 데이터로 변환
      List<Map<String, dynamic>> finalChartData = chartData;
      if (isNasdaq && chartData.isEmpty && data != null) {
        print('🔧 [UnifiedAnalysis] 나스닥 현재가 데이터를 차트 데이터로 변환: $stockCode');
        final currentDate = DateTime.now().toString().substring(0, 10);
        finalChartData = [{
          'date': currentDate,
          'open': data['open'] ?? data['currentPrice'] ?? 0.0,
          'high': data['high'] ?? data['currentPrice'] ?? 0.0,
          'low': data['low'] ?? data['currentPrice'] ?? 0.0,
          'close': data['currentPrice'] ?? 0.0,
          'volume': data['volume'] ?? 0,
        }];
        print('🔧 [UnifiedAnalysis] 변환된 차트 데이터: $finalChartData');
      }

      // KIS 응답 키를 내부 표준 스키마로 정규화
      final normalizedChartData = _normalizeChartData(finalChartData);

      // 데이터 정렬 및 히스토리 추출
      final sortedData = _sortChartDataByDate(normalizedChartData);
       
       // 가격 히스토리 추출 (최신순으로 정렬, 공휴일 제외)
       final priceHistory = sortedData
           .where((item) {
             final date = item['date'] ?? item['xymd'] ?? '';
             final price = double.tryParse(item['close']?.toString() ?? '0') ?? 0.0;
             return price > 0 && _isValidTradingDate(date);
           })
           .map((item) => double.tryParse(item['close']?.toString() ?? '0') ?? 0.0)
           .toList();
       
       // 거래량 히스토리 추출 (가격 데이터와 동일한 인덱스)
       final volumeHistory = sortedData
           .where((item) {
             final date = item['date'] ?? item['xymd'] ?? '';
             final price = double.tryParse(item['close']?.toString() ?? '0') ?? 0.0;
             return price > 0 && _isValidTradingDate(date);
           })
           .map((item) => int.tryParse(item['volume']?.toString() ?? '0') ?? 0)
           .toList();
       
       // 고가 히스토리 추출 (가격 데이터와 동일한 인덱스)
       final highHistory = sortedData
           .where((item) {
             final date = item['date'] ?? item['xymd'] ?? '';
             final price = double.tryParse(item['close']?.toString() ?? '0') ?? 0.0;
             return price > 0 && _isValidTradingDate(date);
           })
           .map((item) => double.tryParse(item['high']?.toString() ?? '0') ?? 0.0)
           .toList();
       
       // 저가 히스토리 추출 (가격 데이터와 동일한 인덱스)
       final lowHistory = sortedData
           .where((item) {
             final date = item['date'] ?? item['xymd'] ?? '';
             final price = double.tryParse(item['close']?.toString() ?? '0') ?? 0.0;
             return price > 0 && _isValidTradingDate(date);
           })
           .map((item) => double.tryParse(item['low']?.toString() ?? '0') ?? 0.0)
           .toList();

      // 가격/거래량/종목명 안전 파싱 (문자열 대응)
      final stockName = (data['stockName']?.toString().trim().isNotEmpty == true)
          ? data['stockName']
          : (data['hts_kor_isnm'] ?? (data['output1']?['hts_kor_isnm'])) ?? '';

      // KIS output1 우선 추출
      final output1 = (data['output1'] is Map) ? Map<String, dynamic>.from(data['output1']) : <String, dynamic>{};
      final kisCurr = output1['stck_prpr'] ?? data['stck_prpr'] ?? data['currentPrice'];
      final kisPrevClose = output1['stck_prdy_clpr'] ?? data['stck_prdy_clpr'] ?? data['prevClose'];
      final kisOpen = output1['stck_oprc'] ?? data['stck_oprc'] ?? data['open'];
      final kisHigh = output1['stck_hgpr'] ?? data['stck_hgpr'] ?? data['high'];
      final kisLow = output1['stck_lwpr'] ?? data['stck_lwpr'] ?? data['low'];
      final kisVol = output1['acml_vol'] ?? data['acml_vol'] ?? data['volume'];

      // 최종 값 결정: KIS 값 → 기존 값 → 히스토리 기반 fallback
      final fallbackCurrent = priceHistory.isNotEmpty ? priceHistory.last : 0.0;
      final fallbackPrev = priceHistory.length >= 2 ? priceHistory[priceHistory.length - 2] : fallbackCurrent;
      final fallbackOpen = (sortedData.isNotEmpty ? (sortedData.last['open'] as double? ?? 0.0) : 0.0);
      final fallbackHigh = (sortedData.isNotEmpty ? (sortedData.last['high'] as double? ?? 0.0) : 0.0);
      final fallbackLow = (sortedData.isNotEmpty ? (sortedData.last['low'] as double? ?? 0.0) : 0.0);
      final fallbackVol = (sortedData.isNotEmpty ? (sortedData.last['volume'] as int? ?? 0) : 0);

      final currentPriceParsed = double.tryParse(kisCurr?.toString() ?? '')
          ?? double.tryParse(data['currentPrice']?.toString() ?? '')
          ?? fallbackCurrent;
      final prevCloseParsed = double.tryParse(kisPrevClose?.toString() ?? '')
          ?? double.tryParse(data['prevClose']?.toString() ?? '')
          ?? fallbackPrev;
      final openParsed = double.tryParse(kisOpen?.toString() ?? '')
          ?? double.tryParse(data['open']?.toString() ?? '')
          ?? fallbackOpen;
      final highParsed = double.tryParse(kisHigh?.toString() ?? '')
          ?? double.tryParse(data['high']?.toString() ?? '')
          ?? fallbackHigh;
      final lowParsed = double.tryParse(kisLow?.toString() ?? '')
          ?? double.tryParse(data['low']?.toString() ?? '')
          ?? fallbackLow;
      final volumeParsed = int.tryParse(kisVol?.toString() ?? '')
          ?? int.tryParse(data['volume']?.toString() ?? '')
          ?? fallbackVol;

      final marketData = {
        'stockCode': stockCode, // 종목코드 추가
        'currentPrice': currentPriceParsed,
        'prevClose': prevCloseParsed,
        'volume': volumeParsed,
        'highPrice': highParsed,
        'lowPrice': lowParsed,
        'openPrice': openParsed,
        'stockName': stockName,
        'priceHistory': priceHistory,
        'volumeHistory': volumeHistory,
        'highHistory': highHistory,
        'lowHistory': lowHistory,
      };
      
      print('✅ [UnifiedAnalysis] 시장 데이터 변환 완료');
      print('📊 가격 히스토리: ${priceHistory.length}개 데이터');
      print('📊 거래량 히스토리: ${volumeHistory.length}개 데이터');
      print('📊 고가 히스토리: ${highHistory.length}개 데이터');
      print('📊 저가 히스토리: ${lowHistory.length}개 데이터');
      
      return marketData;
    } catch (e) {
      print('❌ [UnifiedAnalysis] 시장 데이터 가져오기 실패: $e');
      return null;
    }
  }

  /// 해외 심볼 교정 (마스터 데이터 또는 간단 휴리스틱)
  String _resolveUsSymbol(String symbol) {
    try {
      final parser = StockMasterParser();
      if (parser.isInitialized) {
        final nas = parser.getNasdaqStockCodes();
        if (nas.contains(symbol)) return symbol;
        // startsWith로 가장 유사한 후보 선택
        final candidate = nas.firstWhere(
          (c) => c.startsWith(symbol),
          orElse: () => '',
        );
        if (candidate.isNotEmpty) return candidate;
      }
    } catch (_) {}
    // 간단 휴리스틱: 3자 티커는 A/B/C 접미 재시도 후보
    if (symbol.length == 3) {
      for (final sfx in ['A','B','C']) {
        final cand = symbol + sfx;
        // 즉시 반환해 재시도에 사용
        return cand;
      }
    }
    return symbol;
  }

  /// KIS 일봉 응답의 키를 내부 표준 스키마로 정규화
  List<Map<String, dynamic>> _normalizeChartData(List<Map<String, dynamic>> raw) {
    try {
      if (raw.isEmpty) return raw;
      
      // 첫 번째 데이터의 키 구조 확인
      final first = raw.first;
      print('🔍 [UnifiedAnalysis] 차트 데이터 정규화: 첫 번째 데이터 키 = ${first.keys.toList()}');
      
      // 국내주식 KIS 포맷: { stck_bsop_date, stck_clpr, stck_oprc, stck_hgpr, stck_lwpr, acml_vol, ... }
      final hasKisKeys = first.containsKey('stck_bsop_date') || first.containsKey('stck_clpr');
      
      // 나스닥 포맷: { xymd, last, open, high, low, vol, ... }
      final hasNasdaqKeys = first.containsKey('xymd') || first.containsKey('last');
      
      // 이미 표준 키를 사용하는 경우 그대로 반환
      final hasStandardKeys = first.containsKey('date') && first.containsKey('close');
      
      if (hasStandardKeys) {
        print('✅ [UnifiedAnalysis] 이미 표준 키 사용 중');
        return raw;
      }
      
      if (hasKisKeys) {
        print('🇰🇷 [UnifiedAnalysis] 국내주식 KIS 포맷 정규화');
        return raw.map((row) {
          final date = row['stck_bsop_date']?.toString() ?? '';
          final close = double.tryParse(row['stck_clpr']?.toString() ?? '') ?? 0.0;
          final open = double.tryParse(row['stck_oprc']?.toString() ?? '') ?? 0.0;
          final high = double.tryParse(row['stck_hgpr']?.toString() ?? '') ?? 0.0;
          final low = double.tryParse(row['stck_lwpr']?.toString() ?? '') ?? 0.0;
          final volume = int.tryParse(row['acml_vol']?.toString() ?? '') ?? 0;
          
          print('  📊 정규화: date=$date, close=$close, open=$open, high=$high, low=$low, volume=$volume');
          
          return {
            'date': date, // YYYYMMDD
            'close': close,
            'open': open,
            'high': high,
            'low': low,
            'volume': volume,
          };
        }).toList();
      }
      
      if (hasNasdaqKeys) {
        print('🌍 [UnifiedAnalysis] 나스닥 포맷 정규화');
        return raw.map((row) {
          final date = row['xymd']?.toString() ?? '';
          final close = double.tryParse(row['last']?.toString() ?? '') ?? 0.0;
          final open = double.tryParse(row['open']?.toString() ?? '') ?? 0.0;
          final high = double.tryParse(row['high']?.toString() ?? '') ?? 0.0;
          final low = double.tryParse(row['low']?.toString() ?? '') ?? 0.0;
          final volume = int.tryParse(row['vol']?.toString() ?? '') ?? 0;
          
          print('  📊 정규화: date=$date, close=$close, open=$open, high=$high, low=$low, volume=$volume');
          
          return {
            'date': date, // YYYYMMDD
            'close': close,
            'open': open,
            'high': high,
            'low': low,
            'volume': volume,
          };
        }).toList();
      }
      
      print('⚠️ [UnifiedAnalysis] 알 수 없는 포맷, 원본 반환');
      return raw;
      
    } catch (e) {
      print('❌ [UnifiedAnalysis] KIS 차트 정규화 실패: $e');
      return raw;
    }
  }

  /// 로컬 DB에서 시장 데이터 가져오기 (API 실패 시 폴백)
  Future<Map<String, dynamic>?> _getLocalMarketData(String stockCode) async {
    try {
      print('🔍 [UnifiedAnalysis] 로컬 DB에서 시장 데이터 조회: $stockCode');
      
      // 로컬 DB에서 최신 실시간 데이터 조회
      final realtimeData = await _realtimeDataRepo.getLatestRealtimeData(stockCode);
      if (realtimeData == null) {
        print('❌ [UnifiedAnalysis] 로컬 DB 실시간 데이터 없음: $stockCode');
        return null;
      }
      
      // 로컬 DB에서 히스토리 데이터 조회
      final historicalData = await _historicalDataRepo.getRecentBars(stockCode, limit: ChartConstants.CHART_MIN_BARS);
       
       // 히스토리 데이터가 있으면 정렬 및 추출, 없으면 빈 리스트 사용
       List<double> priceHistory = [];
       List<int> volumeHistory = [];
       List<double> highHistory = [];
       List<double> lowHistory = [];
       
       if (historicalData.isNotEmpty) {
         // 데이터 정렬
         final sortedHistoricalData = _sortChartDataByDate(historicalData);
         
         // 가격 히스토리 추출 (공휴일 제외)
         priceHistory = sortedHistoricalData
             .where((item) {
               final date = item['date']?.toString() ?? item['xymd']?.toString() ?? '';
               final price = (item['close'] as num?)?.toDouble() ?? 0.0;
               return price > 0 && _isValidTradingDate(date);
             })
             .map((item) => (item['close'] as num?)?.toDouble() ?? 0.0)
             .toList();
         
         // 거래량 히스토리 추출 (가격 데이터와 동일한 인덱스)
         volumeHistory = sortedHistoricalData
             .where((item) {
               final date = item['date']?.toString() ?? item['xymd']?.toString() ?? '';
               final price = (item['close'] as num?)?.toDouble() ?? 0.0;
               return price > 0 && _isValidTradingDate(date);
             })
             .map((item) => (item['volume'] as num?)?.toInt() ?? 0)
             .toList();
         
         // 고가 히스토리 추출 (가격 데이터와 동일한 인덱스)
         highHistory = sortedHistoricalData
             .where((item) {
               final date = item['date']?.toString() ?? item['xymd']?.toString() ?? '';
               final price = (item['close'] as num?)?.toDouble() ?? 0.0;
               return price > 0 && _isValidTradingDate(date);
             })
             .map((item) => (item['high'] as num?)?.toDouble() ?? 0.0)
             .toList();
         
         // 저가 히스토리 추출 (가격 데이터와 동일한 인덱스)
         lowHistory = sortedHistoricalData
             .where((item) {
               final date = item['date']?.toString() ?? item['xymd']?.toString() ?? '';
               final price = (item['close'] as num?)?.toDouble() ?? 0.0;
               return price > 0 && _isValidTradingDate(date);
             })
             .map((item) => (item['low'] as num?)?.toDouble() ?? 0.0)
             .toList();
       } else {
         print('⚠️ [UnifiedAnalysis] 로컬 DB 히스토리 데이터 없음: $stockCode');
       }

      // 현재가를 히스토리에서 가져오기 (최신 데이터: 마지막 요소)
      final currentPriceFromHistory = priceHistory.isNotEmpty ? priceHistory.last : 0.0;
      final prevCloseFromHistory = priceHistory.length >= 2 ? priceHistory[priceHistory.length - 2] : currentPriceFromHistory;
      
      // 실시간 값이 0이거나 음수면 히스토리 값으로 폴백
      final double parsedCurrent = (realtimeData['current_price'] as num?)?.toDouble() ?? -1;
      final double parsedPrevClose = (realtimeData['prev_close'] as num?)?.toDouble() ?? -1;
      final int parsedVolume = (realtimeData['volume'] as num?)?.toInt() ?? -1;
      final double parsedHigh = (realtimeData['high_price'] as num?)?.toDouble() ?? -1;
      final double parsedLow = (realtimeData['low_price'] as num?)?.toDouble() ?? -1;
      final double parsedOpen = (realtimeData['open_price'] as num?)?.toDouble() ?? -1;

      final marketData = {
        'stockCode': stockCode, // 종목코드 추가
        'currentPrice': parsedCurrent > 0 ? parsedCurrent : currentPriceFromHistory,
        'prevClose': parsedPrevClose > 0 ? parsedPrevClose : prevCloseFromHistory,
        'volume': parsedVolume > 0 ? parsedVolume : (volumeHistory.isNotEmpty ? volumeHistory.last : 0),
        'highPrice': parsedHigh > 0 ? parsedHigh : (highHistory.isNotEmpty ? highHistory.last : 0.0),
        'lowPrice': parsedLow > 0 ? parsedLow : (lowHistory.isNotEmpty ? lowHistory.last : 0.0),
        'openPrice': parsedOpen > 0 ? parsedOpen : currentPriceFromHistory,
        'stockName': realtimeData['stock_name'] ?? '',
        'priceHistory': priceHistory,
        'volumeHistory': volumeHistory,
        'highHistory': highHistory,
        'lowHistory': lowHistory,
      };
      
      print('✅ [UnifiedAnalysis] 로컬 DB 데이터 변환 완료');
      print('📊 가격 히스토리: ${priceHistory.length}개 데이터');
      print('📊 거래량 히스토리: ${volumeHistory.length}개 데이터');
      print('📊 현재가 설정: ${marketData['currentPrice']} (히스토리: $currentPriceFromHistory)');
      print('📊 전일가 설정: ${marketData['prevClose']} (히스토리: $prevCloseFromHistory)');
      
      return marketData;
    } catch (e) {
      print('❌ [UnifiedAnalysis] 로컬 DB 데이터 조회 실패: $stockCode - $e');
      return null;
    }
  }

  /// 기술적 지표 데이터 가져오기
  Future<Map<String, dynamic>> _getTechnicalIndicators(
    String stockCode,
    Map<String, dynamic> marketData,
  ) async {
    try {
      print('🔍 [UnifiedAnalysis] 기술적 지표 데이터 가져오기 시작: $stockCode');
      
      // 나스닥 종목인지 확인
      final isNasdaq = _isNasdaqStock(stockCode);
      
      // 로컬DB에서 차트 데이터 먼저 확인 (모든 종목에 대해)
      List<Map<String, dynamic>> chartData;
      try {
        print('📊 [UnifiedAnalysis] 로컬 DB에서 차트 데이터 확인: $stockCode');
        final localChartData = await _historicalDataRepo.getRecentBars(stockCode, limit: ChartConstants.CHART_MIN_BARS);
        print('📊 [UnifiedAnalysis] 로컬 DB 차트 데이터 개수: ${localChartData.length}개');
        
        if (localChartData.isNotEmpty && localChartData.length >= 20) {
          // 로컬 DB 데이터가 있지만 최신 데이터인지 확인
          final latestDate = localChartData.last['date'] ?? '';
          final today = DateTime.now().toString().substring(0, 10).replaceAll('-', '');
          final isDataRecent = latestDate == today || latestDate == _getYesterday();
          
          if (isDataRecent) {
            print('📊 [UnifiedAnalysis] 로컬 DB에서 최신 데이터 발견: $stockCode (${localChartData.length}개, 최신: $latestDate)');
            // 🔧 로컬 DB 데이터가 최신이면 그대로 사용 (에뮬레이터와 동일한 데이터 보장)
            chartData = localChartData;
            print('📊 [UnifiedAnalysis] 로컬 DB 데이터 사용: $stockCode (${localChartData.length}개)');
          } else {
            print('📊 [UnifiedAnalysis] 로컬 DB 데이터가 오래됨 (최신: $latestDate, 오늘: $today), API 호출: $stockCode');
            // 통합 API 사용으로 자동 시장 판별 및 적절한 exchangeCode 선택
            print('🔄 [UnifiedAnalysis] 통합 API 호출: $stockCode (자동 시장 판별)');
            chartData = await KisUnifiedApiService().getDailyChart(stockCode, count: ChartConstants.CHART_MIN_BARS);
            print('📊 [UnifiedAnalysis] 통합 API 응답: $stockCode (${chartData.length}개)');
            
            // API에서 가져온 최신 데이터를 DB에 저장
            if (chartData.isNotEmpty) {
              print('💾 [UnifiedAnalysis] 최신 데이터를 DB에 저장: $stockCode');
              await _historicalDataRepo.upsertDailyBars(
                stockCode: stockCode,
                market: isNasdaq ? 'NASDAQ' : 'KOSPI',
                bars: chartData,
                keepDays: 100,
              );
            }
          }
        } else {
          print('📊 [UnifiedAnalysis] 로컬 DB에 데이터 없음, 통합 API 호출: $stockCode');
          // 통합 API 사용으로 자동 시장 판별 및 적절한 exchangeCode 선택
          print('🔄 [UnifiedAnalysis] 통합 API 호출: $stockCode (자동 시장 판별)');
          chartData = await KisUnifiedApiService().getDailyChart(stockCode, count: ChartConstants.CHART_MIN_BARS);
          print('📊 [UnifiedAnalysis] 통합 API 응답: $stockCode (${chartData.length}개)');
          
          // API에서 가져온 데이터를 DB에 저장
          if (chartData.isNotEmpty) {
            print('💾 [UnifiedAnalysis] API 데이터를 DB에 저장: $stockCode');
            await _historicalDataRepo.upsertDailyBars(
              stockCode: stockCode,
              market: isNasdaq ? 'NASDAQ' : 'KOSPI',
              bars: chartData,
              keepDays: 100,
            );
          }
        }
        
        print('📊 [UnifiedAnalysis] API 응답 데이터: $stockCode');
        print('  - 응답 개수: ${chartData.length}개');
        if (chartData.isNotEmpty) {
          print('  - 첫 번째 데이터: ${chartData.first}');
          print('  - 마지막 데이터: ${chartData.last}');
        }
        
        if (chartData.isEmpty) {
          print('⚠️ [UnifiedAnalysis] 차트 데이터 없음: $stockCode');
          return _getDefaultTechnicalData(marketData);
        }
      } catch (e) {
        print('❌ [UnifiedAnalysis] 차트 데이터 API 호출 실패: $stockCode - $e');
        // API 실패 시 로컬 DB에서 차트 데이터 사용
        print('⚠️ [UnifiedAnalysis] 로컬 DB 차트 데이터로 폴백: $stockCode');
        final localChartData = await _historicalDataRepo.getRecentBars(stockCode, limit: ChartConstants.CHART_MIN_BARS);
        print('📊 [UnifiedAnalysis] 로컬 DB 데이터: $stockCode');
        print('  - 로컬 데이터 개수: ${localChartData.length}개');
        if (localChartData.isNotEmpty) {
          print('  - 첫 번째 데이터: ${localChartData.first}');
          print('  - 마지막 데이터: ${localChartData.last}');
        }
        if (localChartData.isEmpty || localChartData.length < 20) {
          print('❌ [UnifiedAnalysis] 로컬 DB 차트 데이터 부족: $stockCode (${localChartData.length}개 < 20개)');
          print('⚠️ [UnifiedAnalysis] 기본값 반환: RSI = 50.0');
          // 기본값 반환 시에도 priceHistory 포함
          final defaultData = _getDefaultTechnicalData(marketData);
          print('📊 [UnifiedAnalysis] 기본값 데이터 키: ${defaultData.keys.toList()}');
          return defaultData;
        }
        chartData = localChartData;
      }

      // KIS 응답을 내부 표준 스키마로 정규화한 뒤 정렬
      print('📊 [UnifiedAnalysis] 데이터 정규화 시작: $stockCode');
      final normalizedData = _normalizeChartData(chartData);
      print('📊 [UnifiedAnalysis] 정규화 결과: $stockCode');
      print('  - 정규화 전: ${chartData.length}개');
      print('  - 정규화 후: ${normalizedData.length}개');
      if (normalizedData.isNotEmpty) {
        print('  - 정규화된 첫 번째: ${normalizedData.first}');
        print('  - 정규화된 마지막: ${normalizedData.last}');
      }
      
      // SQL에서 이미 과거→최신 순서로 불러왔으므로 정렬 불필요
      final sortedData = normalizedData;
      // 요구사항: 종가(일봉 stck_clpr)만 사용. 당일 일봉이 없으면 합성하지 않고 전일까지 사용.
      List<Map<String, dynamic>> effectiveData = sortedData;
      
      // 가격 데이터 추출 (최신순으로 정렬, 공휴일 제외)
      print('📊 [UnifiedAnalysis] 가격 데이터 추출 시작: $stockCode');
      print('  - 정렬된 데이터 개수: ${sortedData.length}개');
      
      final prices = effectiveData
          .where((data) {
            final date = data['date'] ?? data['xymd'] ?? data['stck_bsop_date'] ?? '';
            final price = double.tryParse(data['close']?.toString() ?? '0') ?? 0.0;
            final isValid = price > 0 && _isValidTradingDate(date);
            if (!isValid) {
              print('  - 필터링된 데이터: date=$date, price=$price, isValid=$isValid');
            }
            // 공휴일이 아니고 가격이 유효한 데이터만 포함
            return isValid;
          })
          .map((data) => double.tryParse(data['close']?.toString() ?? '0') ?? 0.0)
          .toList();

      // 가격과 동일한 필터로 날짜 시퀀스 생성 (과거→최신)
      final dates = effectiveData
          .where((data) {
            final date = data['date'] ?? data['xymd'] ?? data['stck_bsop_date'] ?? '';
            final price = double.tryParse(data['close']?.toString() ?? '0') ?? 0.0;
            return price > 0 && _isValidTradingDate(date);
          })
          .map((data) => (data['date'] ?? data['xymd'] ?? data['stck_bsop_date'] ?? '').toString())
          .toList();
      
      print('📊 [UnifiedAnalysis] 가격 데이터 추출 결과: $stockCode');
      print('  - 추출된 가격 개수: ${prices.length}개');
      if (prices.isNotEmpty) {
        print('  - 첫 번째 가격: ${prices.first}');
        print('  - 마지막 가격: ${prices.last}');
      }
      
      // 거래량 데이터 추출 (가격 데이터와 동일한 인덱스)
      final volumes = effectiveData
          .where((data) {
            final date = data['date'] ?? data['xymd'] ?? data['stck_bsop_date'] ?? '';
            final price = double.tryParse(data['close']?.toString() ?? '0') ?? 0.0;
            return price > 0 && _isValidTradingDate(date);
          })
          .map((data) => int.tryParse(data['volume']?.toString() ?? '0') ?? 0)
          .toList();
      
      // 최신 거래량 추출 (과거→최신 순서이므로 마지막 요소가 최신)
      final latestVolume = volumes.isNotEmpty ? volumes.last : 0;
      print('📊 [UnifiedAnalysis] 최신 거래량: $latestVolume (전체 ${volumes.length}개 중 마지막)');
      print('📊 [UnifiedAnalysis] 거래량 데이터 상세:');
      if (volumes.isNotEmpty) {
        print('  - 첫 번째 거래량: ${volumes.first}');
        print('  - 마지막 거래량: ${volumes.last}');
        print('  - 전체 거래량 리스트: ${volumes.take(5).toList()}...${volumes.skip(volumes.length - 5).toList()}');
      }
      
      // OHLC 데이터 추출 (가격 데이터와 동일한 인덱스)
      final highs = effectiveData
          .where((data) {
            final date = data['date'] ?? data['xymd'] ?? data['stck_bsop_date'] ?? '';
            final price = double.tryParse(data['close']?.toString() ?? '0') ?? 0.0;
            return price > 0 && _isValidTradingDate(date);
          })
          .map((data) => double.tryParse(data['high']?.toString() ?? '0') ?? 0.0)
          .toList();
      
      final lows = effectiveData
          .where((data) {
            final date = data['date'] ?? data['xymd'] ?? data['stck_bsop_date'] ?? '';
            final price = double.tryParse(data['close']?.toString() ?? '0') ?? 0.0;
            return price > 0 && _isValidTradingDate(date);
          })
          .map((data) => double.tryParse(data['low']?.toString() ?? '0') ?? 0.0)
          .toList();

      print('📊 [UnifiedAnalysis] 데이터 추출 결과:');
      print('  - 원본 차트 데이터: ${chartData.length}개');
      print('  - 정규화 후: ${normalizedData.length}개');
      print('  - 정렬 후: ${sortedData.length}개');
      print('  - 유효 가격 데이터: ${prices.length}개');
      print('  - 거래량 데이터: ${volumes.length}개');
      print('  - 고가 데이터: ${highs.length}개');
      print('  - 저가 데이터: ${lows.length}개');
      
      if (prices.isEmpty) {
        print('⚠️ [UnifiedAnalysis] 가격 데이터 없음: $stockCode');
        return _getDefaultTechnicalData(marketData);
      }
      
      if (prices.length < 20) {
        print('⚠️ [UnifiedAnalysis] 볼린저밴드 계산 불가능: 데이터 ${prices.length}개 < 20개 필요');
        return _getDefaultTechnicalData(marketData);
      }

      // 현재가가 없거나 0 이면 히스토리 최신 종가로 폴백
      double currentPrice = (marketData['currentPrice'] as num?)?.toDouble() ?? 0.0;
      if (currentPrice <= 0 && prices.isNotEmpty) {
        currentPrice = prices.last;
        print('🔁 [UnifiedAnalysis] 현재가 폴백 적용: $currentPrice');
      }
      final currentVolume = (marketData['volume'] ?? 0).toInt();
      
      // RSI 계산용 데이터 디버깅
      print('🔍 [UnifiedAnalysis] RSI 계산용 가격 데이터 (과거→최신):');
      for (int i = 0; i < prices.length; i++) {
        print('  ${i+1}: ${prices[i].toStringAsFixed(0)}원');
      }
      
      // 최근 N일 윈도우 추출 헬퍼
      List<T> _lastN<T>(List<T> list, int n) {
        if (list.isEmpty) return list;
        if (list.length <= n) return list;
        return list.sublist(list.length - n);
      }

      // 기술적 지표 계산
      // RSI: TradingView 규격(Wilder, RMA) 방식으로 계산 (close, 14)
      final rsi = TechnicalIndicators.calculateRSI(prices);
      // 디버그: 두 방식 동시 출력
      final rsiWilder = TechnicalIndicators.calculateRSI(prices);
      final last15 = prices.length >= 15 ? prices.sublist(prices.length - 15) : prices;
      final last15Dates = dates.length >= 15 ? dates.sublist(dates.length - 15) : dates;
      print('🔎 RSI 디버그: last15=${last15.map((e)=>e.toStringAsFixed(2)).toList()}');
      print('🔎 RSI 디버그: last15Dates=$last15Dates (과거→최신)');
      print('🔎 RSI(Cutler,14)=$rsi, RSI(Wilder,14)=$rsiWilder');
      // MACD: EMA 수렴 향상을 위해 전체 시계열 사용
      final macd = TechnicalIndicators.calculateMACD(prices);
      
      // 볼린저밴드 계산 전 추가 검증
      Map<String, double> bb;
      if (prices.length >= 20) {
        bb = TechnicalIndicators.calculateBollingerBands(_lastN(prices, 20));
        // 볼린저밴드 값 검증
        if ((bb['upper'] ?? 0.0) <= 0 || (bb['middle'] ?? 0.0) <= 0 || (bb['lower'] ?? 0.0) <= 0) {
          print('❌ [UnifiedAnalysis] 볼린저밴드 계산 결과가 유효하지 않음: $bb');
          return _getDefaultTechnicalData(marketData);
        }
      } else {
        print('❌ [UnifiedAnalysis] 볼린저밴드 계산을 위한 데이터 부족: ${prices.length}개');
        return _getDefaultTechnicalData(marketData);
      }
      
      final ma5 = TechnicalIndicators.calculateSMA(prices, 5);
      final ma20 = TechnicalIndicators.calculateSMA(prices, 20);
      final ma60 = TechnicalIndicators.calculateSMA(prices, 60);
      
      // VWAP 계산 (기본: 일봉 기반), 장중/가능 시 세션(당일 분봉) 기반으로 대체
      double vwap = volumes.isNotEmpty && prices.length == volumes.length 
          ? TechnicalIndicators.calculateVWAP(prices, volumes, highs: highs, lows: lows) 
          : currentPrice;

      // 분봉/세션 병합 로직 제거: VWAP은 일봉 기반으로만 계산
      
      // ADX 계산
      final adx = highs.isNotEmpty && lows.isNotEmpty && prices.length == highs.length && prices.length == lows.length
          ? TechnicalIndicators.calculateADX(highs, lows, prices)
          : 25.0;
      
      // ATR 계산
      final atr = _calculateATR(highs, lows, prices);
      final avgAtr = _calculateAverageATR(highs, lows, prices);
      
      // 거래량 평균 계산
      final avgVolume = volumes.isNotEmpty 
          ? (volumes.length >= 20 
              ? _lastN(volumes, 20).reduce((a, b) => a + b) / 20 
              : volumes.reduce((a, b) => a + b) / volumes.length)
          : currentVolume.toDouble();

      final technicalData = {
        'rsi': rsi,
        'macd': macd['macd'] ?? 0.0,
        'signal': macd['signal'] ?? 0.0,
        'histogram': macd['histogram'] ?? 0.0,
        'bbUpper': bb['upper'] ?? 0.0,
        'bbMiddle': bb['middle'] ?? 0.0,
        'bbLower': bb['lower'] ?? 0.0,
        'ma5': ma5,
        'ma20': ma20,
        'ma60': ma60,
        'vwap': vwap,
        'adx': adx,
        'atr': atr,
        'avgAtr': avgAtr,
        'avgVolume': avgVolume,
        'currentVolume': latestVolume, // 최신 거래량 사용
        'currentPrice': currentPrice,
        'previousPrice': marketData['openPrice'] ?? marketData['prevClose'] ?? currentPrice,
        // 가격 히스토리 추가 (기본값 계산용)
        'priceHistory': prices,
        'volumeHistory': volumes,
        'highHistory': highs,
        'lowHistory': lows,
      };
      
      print('🔍 [UnifiedAnalysis] 기술적 지표 계산 결과:');
      print('  - RSI: ${rsi.toStringAsFixed(2)}');
      print('  - MACD: ${(macd['macd'] ?? 0.0).toStringAsFixed(4)}');
      print('  - Signal: ${(macd['signal'] ?? 0.0).toStringAsFixed(4)}');
              print('  - BB Upper: ${(bb['upper'] ?? 0.0).toStringAsFixed(2)}');
        print('  - BB Middle: ${(bb['middle'] ?? 0.0).toStringAsFixed(2)}');
        print('  - BB Lower: ${(bb['lower'] ?? 0.0).toStringAsFixed(2)}');
      print('  - MA5: ${ma5.toStringAsFixed(2)}');
      print('  - MA20: ${ma20.toStringAsFixed(2)}');
      print('  - MA60: ${ma60.toStringAsFixed(2)}');
      print('  - VWAP: ${vwap.toStringAsFixed(2)}');
      print('  - ADX: ${adx.toStringAsFixed(2)}');
      print('  - ATR: ${atr.toStringAsFixed(4)}');
      print('  - Avg ATR: ${avgAtr.toStringAsFixed(4)}');
      print('  - Avg Volume: ${avgVolume.toStringAsFixed(0)}');
      print('  - Current Volume: ${currentVolume.toStringAsFixed(0)}');
      print('  - Current Price: ${currentPrice.toStringAsFixed(2)}');
      print('  - Previous Price: ${(marketData['prevClose'] ?? currentPrice).toStringAsFixed(2)}');

      print('✅ [UnifiedAnalysis] 기술적 지표 계산 완료: $stockCode');
      print('📊 RSI: ${rsi.toStringAsFixed(1)}, MACD: ${macd['macd']?.toStringAsFixed(3) ?? 'N/A'}');
      print('📊 BB: ${bb['upper']?.toStringAsFixed(0) ?? 'N/A'}/${bb['middle']?.toStringAsFixed(0) ?? 'N/A'}/${bb['lower']?.toStringAsFixed(0) ?? 'N/A'}');
      print('📊 MA: ${ma5.toStringAsFixed(0)}/${ma20.toStringAsFixed(0)}/${ma60.toStringAsFixed(0)}');
      print('📊 VWAP: ${vwap.toStringAsFixed(0)}, ADX: ${adx.toStringAsFixed(1)}');
      print('📊 ATR: ${atr.toStringAsFixed(2)}/${avgAtr.toStringAsFixed(2)}');
      print('📊 Volume: $currentVolume/${avgVolume.toStringAsFixed(0)}');
      print('📊 [UnifiedAnalysis] 기술적 지표 데이터 반환:');
      print('  - rsi: $rsi');
      print('  - macd: ${macd['macd']}');
      print('  - signal: ${macd['signal']}');
      print('  - bbUpper: ${bb['upper']}');
      print('  - bbMiddle: ${bb['middle']}');
      print('  - bbLower: ${bb['lower']}');
      print('  - ma5: $ma5');
      print('  - ma20: $ma20');
      print('  - ma60: $ma60');
      print('  - vwap: $vwap');
      print('  - adx: $adx');
      print('  - atr: $atr');
      print('  - avgAtr: $avgAtr');
      print('  - avgVolume: $avgVolume');
      print('  - currentVolume: $currentVolume');
      print('  - currentPrice: $currentPrice');
      print('  - previousPrice: ${marketData['prevClose']}');
      
      return technicalData;
      
    } catch (e) {
      print('❌ [UnifiedAnalysis] 기술적 지표 계산 실패: $e');
      return _getDefaultTechnicalData(marketData);
    }
  }

  /// 기본 기술적 지표 데이터 (실패 시 사용)
  /// 가상/더미 데이터 생성 금지 - 실제 계산만 사용
  Map<String, dynamic> _getDefaultTechnicalData(Map<String, dynamic> marketData) {
    final currentPrice = marketData['currentPrice'] ?? 0.0;
    final currentVolume = (marketData['volume'] ?? 0).toInt();
    final prevClose = marketData['openPrice'] ?? marketData['prevClose'] ?? currentPrice;
    
    // 나스닥 종목 여부 확인 (stockCode가 marketData에 있는 경우)
    final stockCode = marketData['stockCode'] as String? ?? '';
    final isNasdaq = _isNasdaqStock(stockCode);
    
    // 가격 변화에 따른 기본 지표 설정
    final priceChange = currentPrice - prevClose;
    final priceChangePercent = prevClose > 0 ? (priceChange / prevClose) * 100 : 0.0;
    
    // 모든 지표를 실제 계산으로 처리 (가상 데이터 금지)
    // 데이터가 없으면 null로 설정하여 계산 오류 처리
    double? rsi;
    double? macd;
    double? signal;
    double? bbUpper;
    double? bbMiddle;
    double? bbLower;
    double? ma5;
    double? ma20;
    double? ma60;
    double? vwap;
    double? adx;
    double? atr;
    double? avgAtr;
    double? avgVolume;
    
    // 가격 히스토리가 있는 경우 실제 계산 수행
    if (marketData.containsKey('priceHistory') && marketData['priceHistory'] is List) {
      final priceHistory = List<double>.from(marketData['priceHistory']);
      
      if (priceHistory.length >= 15) {
        // RSI 실제 계산
        rsi = TechnicalIndicators.calculateRSI(priceHistory);
        print('📊 실제 RSI 계산값: ${rsi.toStringAsFixed(2)}');
      } else {
        print('⚠️ RSI 계산을 위한 데이터 부족: ${priceHistory.length}개 (필요: 15개)');
        rsi = null; // 계산 오류 처리 - 기본값 사용 금지
      }
      
      if (priceHistory.length >= 26) {
        // MACD 실제 계산
        final macdResult = TechnicalIndicators.calculateMACD(priceHistory);
        macd = macdResult['macd'] as double?;
        signal = macdResult['signal'] as double?;
        print('📊 실제 MACD 계산값: MACD=${macd?.toStringAsFixed(4) ?? "계산 오류"}, Signal=${signal?.toStringAsFixed(4) ?? "계산 오류"}');
      } else {
        print('⚠️ MACD 계산을 위한 데이터 부족: ${priceHistory.length}개 (필요: 26개)');
        macd = null; // 계산 오류 처리 - 기본값 사용 금지
        signal = null; // 계산 오류 처리 - 기본값 사용 금지
      }
      
      if (priceHistory.length >= 20) {
        // 볼린저밴드 실제 계산
        final bbResult = TechnicalIndicators.calculateBollingerBands(priceHistory);
        bbUpper = bbResult['upper'] as double?;
        bbMiddle = bbResult['middle'] as double?;
        bbLower = bbResult['lower'] as double?;
        print('📊 실제 볼린저밴드 계산값: Upper=${bbUpper?.toStringAsFixed(2) ?? "계산 오류"}, Middle=${bbMiddle?.toStringAsFixed(2) ?? "계산 오류"}, Lower=${bbLower?.toStringAsFixed(2) ?? "계산 오류"}');
      } else {
        print('⚠️ 볼린저밴드 계산을 위한 데이터 부족: ${priceHistory.length}개 (필요: 20개)');
        // 기본값 사용 금지 - 데이터가 없으면 null로 처리
        bbUpper = null;
        bbMiddle = null;
        bbLower = null;
        print('⚠️ [UnifiedAnalysis] 볼린저밴드 데이터 부족으로 null 처리');
      }
      
      if (priceHistory.length >= 5) {
        // 이동평균선 실제 계산
        ma5 = TechnicalIndicators.calculateSMA(priceHistory, 5);
        print('📊 실제 MA5 계산값: ${ma5?.toStringAsFixed(2) ?? "계산 오류"}');
      } else {
        // 기본값 사용 금지 - 데이터가 없으면 null로 처리
        ma5 = null;
        print('⚠️ [UnifiedAnalysis] MA5 데이터 부족으로 null 처리');
      }
      
      if (priceHistory.length >= 20) {
        ma20 = TechnicalIndicators.calculateSMA(priceHistory, 20);
        print('📊 실제 MA20 계산값: ${ma20?.toStringAsFixed(2) ?? "계산 오류"}');
      } else {
        // 기본값 사용 금지 - 데이터가 없으면 null로 처리
        ma20 = null;
        print('⚠️ [UnifiedAnalysis] MA20 데이터 부족으로 null 처리');
      }
      
      if (priceHistory.length >= 60) {
        ma60 = TechnicalIndicators.calculateSMA(priceHistory, 60);
        print('📊 실제 MA60 계산값: ${ma60?.toStringAsFixed(2) ?? "계산 오류"}');
      } else {
        // 기본값 사용 금지 - 데이터가 없으면 null로 처리
        ma60 = null;
        print('⚠️ [UnifiedAnalysis] MA60 데이터 부족으로 null 처리');
      }
      
      // VWAP 계산 (거래량 데이터가 있는 경우)
      if (marketData.containsKey('volumeHistory') && marketData['volumeHistory'] is List) {
        final volumeHistory = List<int>.from(marketData['volumeHistory']);
        if (volumeHistory.length == priceHistory.length && volumeHistory.length >= 20) {
          // High/Low 히스토리도 확인하여 Typical Price 계산
          List<double>? highHistory;
          List<double>? lowHistory;
          
          if (marketData.containsKey('highHistory') && marketData['highHistory'] is List) {
            highHistory = List<double>.from(marketData['highHistory']);
          }
          if (marketData.containsKey('lowHistory') && marketData['lowHistory'] is List) {
            lowHistory = List<double>.from(marketData['lowHistory']);
          }
          
          vwap = TechnicalIndicators.calculateVWAP(priceHistory, volumeHistory, 
                                                   highs: highHistory, lows: lowHistory);
          print('📊 실제 VWAP 계산값: ${vwap?.toStringAsFixed(2) ?? "계산 오류"}');
        } else {
          // 기본값 사용 금지 - 데이터가 없으면 null로 처리
          vwap = null;
          print('⚠️ [UnifiedAnalysis] VWAP 데이터 부족으로 null 처리');
        }
      } else {
        // 기본값 사용 금지 - 데이터가 없으면 null로 처리
        vwap = null;
        print('⚠️ [UnifiedAnalysis] VWAP 거래량 데이터 없음으로 null 처리');
      }
      
      // ADX 계산
      if (marketData.containsKey('highHistory') && marketData['highHistory'] is List &&
          marketData.containsKey('lowHistory') && marketData['lowHistory'] is List) {
        final highHistory = List<double>.from(marketData['highHistory']);
        final lowHistory = List<double>.from(marketData['lowHistory']);
        if (highHistory.length == priceHistory.length && lowHistory.length == priceHistory.length && priceHistory.length >= 14) {
          adx = TechnicalIndicators.calculateADX(highHistory, lowHistory, priceHistory);
          print('📊 실제 ADX 계산값: ${adx?.toStringAsFixed(2) ?? "계산 오류"}');
        } else {
          // 기본값 사용 금지 - 데이터가 없으면 null로 처리
          adx = null;
          print('⚠️ [UnifiedAnalysis] ADX 데이터 부족으로 null 처리');
        }
      } else {
        // 기본값 사용 금지 - 데이터가 없으면 null로 처리
        adx = null;
        print('⚠️ [UnifiedAnalysis] ADX 고가/저가 데이터 없음으로 null 처리');
      }
      
      // ATR 계산
      if (marketData.containsKey('highHistory') && marketData['highHistory'] is List &&
          marketData.containsKey('lowHistory') && marketData['lowHistory'] is List) {
        final highHistory = List<double>.from(marketData['highHistory']);
        final lowHistory = List<double>.from(marketData['lowHistory']);
        if (highHistory.length == priceHistory.length && lowHistory.length == priceHistory.length && priceHistory.length >= 14) {
          atr = _calculateATR(highHistory, lowHistory, priceHistory);
          print('📊 실제 ATR 계산값: ${atr?.toStringAsFixed(4) ?? "계산 오류"}');
        } else {
          atr = null;
        }
      } else {
        atr = null;
      }
      
      // 평균 ATR 계산
      if (marketData.containsKey('highHistory') && marketData['highHistory'] is List &&
          marketData.containsKey('lowHistory') && marketData['lowHistory'] is List) {
        final highHistory = List<double>.from(marketData['highHistory']);
        final lowHistory = List<double>.from(marketData['lowHistory']);
        if (highHistory.length == priceHistory.length && lowHistory.length == priceHistory.length && priceHistory.length >= 20) {
          avgAtr = _calculateAverageATR(highHistory, lowHistory, priceHistory);
          print('📊 실제 평균 ATR 계산값: ${avgAtr?.toStringAsFixed(4) ?? "계산 오류"}');
        } else {
          avgAtr = null;
        }
      } else {
        avgAtr = null;
      }
      
      // 거래량 평균 계산
      if (marketData.containsKey('volumeHistory') && marketData['volumeHistory'] is List) {
        final volumeHistory = List<int>.from(marketData['volumeHistory']);
        if (volumeHistory.length >= 20) {
          avgVolume = volumeHistory.take(20).reduce((a, b) => a + b) / 20;
          print('📊 실제 거래량 평균 계산값: ${avgVolume?.toStringAsFixed(0) ?? "계산 오류"}');
        } else if (volumeHistory.isNotEmpty) {
          avgVolume = volumeHistory.reduce((a, b) => a + b) / volumeHistory.length;
          print('📊 실제 거래량 평균 계산값: ${avgVolume?.toStringAsFixed(0) ?? "계산 오류"}');
        } else {
          avgVolume = null;
        }
      } else {
        avgVolume = null;
      }
      
    } else {
      print('⚠️ 가격 히스토리 데이터 없음, 모든 지표를 null로 처리');
      // 기본값 사용 금지 - 모든 지표를 null로 처리
      rsi = null;
      macd = null;
      signal = null;
      bbUpper = null;
      bbMiddle = null;
      bbLower = null;
      ma5 = null;
      ma20 = null;
      ma60 = null;
      vwap = null;
      adx = null;
      atr = null;
      avgAtr = null;
      avgVolume = null;
    }
    
    // 기본값 처리 제거 - 실제 데이터만 사용
    // 데이터가 없으면 null로 유지하여 UI에서 "N/A" 표시
    
    print('✅ [UnifiedAnalysis] 기본 기술적 지표 데이터 생성 완료:');
    print('  - RSI: $rsi');
    print('  - MACD: $macd');
    print('  - Signal: $signal');
    print('  - BB: $bbUpper/$bbMiddle/$bbLower');
    print('  - MA: $ma5/$ma20/$ma60');
    print('  - VWAP: $vwap');
    print('  - ADX: $adx');
    print('  - ATR: $atr/$avgAtr');
    print('  - Avg Volume: $avgVolume');
    
    return {
      'rsi': rsi,
      'macd': macd,
      'signal': signal,
      'histogram': (macd != null && signal != null) ? macd - signal : null,
      'bbUpper': bbUpper,
      'bbMiddle': bbMiddle,
      'bbLower': bbLower,
      'ma5': ma5,
      'ma20': ma20,
      'ma60': ma60,
      'vwap': vwap,
      'adx': adx,
      'atr': atr,
      'avgAtr': avgAtr,
      'avgVolume': avgVolume,
      'currentVolume': currentVolume,
      'currentPrice': currentPrice,
      'previousPrice': prevClose,
    };
  }

  /// ATR (Average True Range) 계산
  double _calculateATR(List<double> highs, List<double> lows, List<double> closes) {
    if (highs.length < 2 || lows.length < 2 || closes.length < 2) return 1.0;
    
    try {
      final trueRanges = <double>[];
      
      for (int i = 1; i < closes.length; i++) {
        final high = highs[i];
        final low = lows[i];
        final prevClose = closes[i - 1];
        
        final tr1 = high - low;
        final tr2 = (high - prevClose).abs();
        final tr3 = (low - prevClose).abs();
        
        final trueRange = [tr1, tr2, tr3].reduce((a, b) => a > b ? a : b);
        trueRanges.add(trueRange);
      }
      
      if (trueRanges.isEmpty) return 1.0;
      
      // 14일 ATR (간단한 평균 사용)
      final period = trueRanges.length >= 14 ? 14 : trueRanges.length;
      final atr = trueRanges.take(period).reduce((a, b) => a + b) / period;
      
      return atr;
    } catch (e) {
      print('❌ ATR 계산 실패: $e');
      return 1.0;
    }
  }

  /// 평균 ATR 계산
  double _calculateAverageATR(List<double> highs, List<double> lows, List<double> closes) {
    if (highs.length < 20 || lows.length < 20 || closes.length < 20) return 1.0;
    
    try {
      final trueRanges = <double>[];
      
      for (int i = 1; i < closes.length; i++) {
        final high = highs[i];
        final low = lows[i];
        final prevClose = closes[i - 1];
        
        final tr1 = high - low;
        final tr2 = (high - prevClose).abs();
        final tr3 = (low - prevClose).abs();
        
        final trueRange = [tr1, tr2, tr3].reduce((a, b) => a > b ? a : b);
        trueRanges.add(trueRange);
      }
      
      if (trueRanges.isEmpty) return 1.0;
      
      // 20일 평균 ATR
      final period = trueRanges.length >= 20 ? 20 : trueRanges.length;
      final avgAtr = trueRanges.take(period).reduce((a, b) => a + b) / period;
      
      return avgAtr;
    } catch (e) {
      print('❌ 평균 ATR 계산 실패: $e');
      return 1.0;
    }
  }

  /// 신뢰도 계산
  double _calculateConfidence(
    double comprehensiveScore,
    Map<String, double> individualScores,
    Map<String, dynamic> technicalData,
  ) {
    try {
      // 기본 신뢰도 (점수 절댓값 기반)
      double baseConfidence = comprehensiveScore.abs();
      
      // 지표 일관성 점수
      double consistencyScore = 0.0;
      int validIndicators = 0;
      
      individualScores.forEach((indicator, score) {
        if (score != 0.0) {
          consistencyScore += score.abs();
          validIndicators++;
        }
      });
      
      if (validIndicators > 0) {
        consistencyScore /= validIndicators;
      }
      
      // 거래량 가중치
      double volumeWeight = 1.0;
      final currentVolume = technicalData['currentVolume'] ?? 0.0;
      final averageVolume = technicalData['averageVolume'] ?? 1.0;
      
      if (averageVolume > 0) {
        final volumeRatio = currentVolume / averageVolume;
        if (volumeRatio >= 2.0) {
          volumeWeight = 1.2; // 거래량 급증 시 신뢰도 증가
        } else if (volumeRatio >= 1.5) {
          volumeWeight = 1.1;
        } else if (volumeRatio < 0.5) {
          volumeWeight = 0.8; // 거래량 부족 시 신뢰도 감소
        }
      }
      
      // 최종 신뢰도 계산
      final confidence = (baseConfidence * 0.6 + consistencyScore * 0.4) * volumeWeight;
      
      return confidence.clamp(0.0, 1.0);
    } catch (e) {
      print('❌ [UnifiedAnalysis] 신뢰도 계산 실패: $e');
      return 0.5;
    }
  }

  /// 목표가 계산
  double _calculateTargetPrice(
    double currentPrice,
    double comprehensiveScore,
    double confidence,
    Map<String, dynamic> technicalData,
  ) {
    try {
      if (currentPrice <= 0) return 0.0;
      
      // 기본 변동폭 (ATR 기반)
      final atr = technicalData['currentATR'] ?? 1.0;
      final avgAtr = technicalData['averageATR'] ?? 1.0;
      final volatility = (atr / avgAtr).clamp(0.5, 2.0);
      
      // 점수 기반 방향성
      final direction = comprehensiveScore > 0 ? 1.0 : -1.0;
      final strength = comprehensiveScore.abs().clamp(0.0, 1.0);
      
      // 신뢰도 기반 가중치
      final confidenceWeight = confidence.clamp(0.3, 1.0);
      
      // 목표가 계산 (최소 변동폭 보장)
      final baseChange = direction * strength * confidenceWeight * volatility * 0.05; // 5% 기본 변동폭
      
      // 최소 변동폭 보장 (현재가의 1% 이상)
      final minChange = direction * 0.01; // 최소 1% 변동
      final targetChange = baseChange.abs() < 0.01 ? minChange : baseChange;
      
      final targetPrice = currentPrice * (1.0 + targetChange);
      
      print('🎯 [UnifiedAnalysis] 목표가 계산:');
      print('  - 현재가: ${currentPrice.toStringAsFixed(0)}');
      print('  - 종합점수: ${comprehensiveScore.toStringAsFixed(3)}');
      print('  - 방향성: ${direction > 0 ? "상승" : "하락"}');
      print('  - 강도: ${strength.toStringAsFixed(3)}');
      print('  - 신뢰도: ${confidence.toStringAsFixed(3)}');
      print('  - 변동폭: ${(targetChange * 100).toStringAsFixed(2)}%');
      print('  - 목표가: ${targetPrice.toStringAsFixed(0)}');
      
      return targetPrice;
    } catch (e) {
      print('❌ [UnifiedAnalysis] 목표가 계산 실패: $e');
      return currentPrice;
    }
  }

  /// 나스닥 종목인지 확인
  bool _isNasdaqStock(String stockCode) {
    final result = RegExp(r'^[A-Z]{1,5}$').hasMatch(stockCode);
    // 심볼별 1회 로깅 가드
    _nasdaqLogGuard ??= <String,bool>{};
    if (!(_nasdaqLogGuard![stockCode] ?? false)) {
      print('🔍 [UnifiedAnalysis] 나스닥 종목 판별: $stockCode -> $result');
      _nasdaqLogGuard![stockCode] = true;
    }
    return result;
  }

  Map<String,bool>? _nasdaqLogGuard;

  /// 헬퍼 메서드: 어제 날짜 문자열 반환 (YYYYMMDD)
  String _getYesterday() {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return '${yesterday.year}${yesterday.month.toString().padLeft(2, '0')}${yesterday.day.toString().padLeft(2, '0')}';
  }

  /// 공휴일 체크 (주말 및 공휴일 제외)
  bool _isValidTradingDate(String dateStr) {
    try {
      final date = _parseDate(dateStr);
      final weekday = date.weekday;
      
      // 주말 제외 (토요일=6, 일요일=7)
      if (weekday == 6 || weekday == 7) {
        return false;
      }
      
      // 주요 공휴일 체크 (간단한 버전)
      final month = date.month;
      final day = date.day;
      
      // 설날 (음력은 복잡하므로 간단히 처리)
      if (month == 1 && (day >= 1 && day <= 3)) return false;
      
      // 추석 (음력은 복잡하므로 간단히 처리)
      if (month == 9 && (day >= 15 && day <= 17)) return false;
      
      // 기타 주요 공휴일
      if ((month == 3 && day == 1) || // 삼일절
          (month == 5 && day == 5) || // 어린이날
          (month == 6 && day == 6) || // 현충일
          (month == 8 && day == 15) || // 광복절
          (month == 10 && day == 3) || // 개천절
          (month == 10 && day == 9) || // 한글날
          (month == 12 && day == 25)) { // 크리스마스
        return false;
      }
      
      return true;
    } catch (e) {
      print('❌ [UnifiedAnalysis] 공휴일 체크 실패: $dateStr - $e');
      return true; // 에러 시 기본적으로 유효한 날짜로 처리
    }
  }

  /// 중복 시그널 체크
  Future<bool> _isDuplicateSignal(String stockCode, String signal) async {
    try {
      final now = DateTime.now();
      final oneHourAgo = now.subtract(const Duration(hours: 1));
      
      final recentSignals = await _signalRepo.getSignalsByDateRange(oneHourAgo, now);
      
      return recentSignals.any((row) =>
          (row['stock_code']?.toString() ?? '') == stockCode &&
          (row['signal_type']?.toString() ?? '') == signal);
    } catch (e) {
      print('❌ [UnifiedAnalysis] 중복 시그널 체크 실패: $e');
      return false;
    }
  }

  /// 시그널 저장
  Future<void> _saveSignal(
    String stockCode,
    String signal,
    double price,
    double confidence,
    Map<String, dynamic> analysis,
  ) async {
    try {
      await _signalRepo.saveSignal(
        stockCode: stockCode,
        signalType: signal,
        signalStrength: confidence,
        price: price,
        volume: 0.0,
        confidence: confidence,
        memo: 'UnifiedAnalysis_${_styleManager.currentStyle.name}',
      );
      
      print('✅ [UnifiedAnalysis] 시그널 저장 완료: $stockCode - $signal');
    } catch (e) {
      print('❌ [UnifiedAnalysis] 시그널 저장 실패: $e');
    }
  }

  /// 차트 데이터를 날짜순으로 정렬 (과거→최신 순서 - 기술적 지표 계산용)
  List<Map<String, dynamic>> _sortChartDataByDate(List<Map<String, dynamic>> chartData) {
    try {
      print('📊 [UnifiedAnalysis] 차트 데이터 정렬 시작: ${chartData.length}개');
      
      // 날짜 파싱 및 정렬 (과거 → 최신 순서로 정렬 - 기술적 지표 계산 표준)
      final sortedData = List<Map<String, dynamic>>.from(chartData);
      sortedData.sort((a, b) {
        final dateA = _parseDate(a['date'] ?? a['xymd'] ?? '');
        final dateB = _parseDate(b['date'] ?? b['xymd'] ?? '');
        return dateA.compareTo(dateB); // 과거→최신 순서로 정렬 (기술지표 계산 표준)
      });
      
      print('📊 [UnifiedAnalysis] 정렬 완료: ${sortedData.length}개');
      
      // 정렬 결과 확인 (첫 3개와 마지막 3개 출력)
      if (sortedData.isNotEmpty) {
        print('📊 [UnifiedAnalysis] 정렬 결과 확인:');
        print('  - 첫 번째: ${sortedData.first['date'] ?? sortedData.first['xymd']} (과거)');
        print('  - 마지막: ${sortedData.last['date'] ?? sortedData.last['xymd']} (최신)');
        
        if (sortedData.length >= 3) {
          print('  - 첫 3개: ${sortedData.take(3).map((item) => item['date'] ?? item['xymd']).toList()} (과거순)');
          print('  - 마지막 3개: ${sortedData.skip(sortedData.length - 3).map((item) => item['date'] ?? item['xymd']).toList()} (최신순)');
        }
      }
      
      return sortedData;
    } catch (e) {
      print('❌ [UnifiedAnalysis] 차트 데이터 정렬 실패: $e');
      return chartData; // 정렬 실패 시 원본 반환
    }
  }

  /// Cutler RSI (최근 period 구간 단순 평균 기반)
  double _calculateCutlerRSI(List<double> closes, int period) {
    try {
      if (closes.length < period + 1) return 50.0;
      final List<double> window = closes.sublist(closes.length - (period + 1));
      double gain = 0.0;
      double loss = 0.0;
      for (int i = 1; i < window.length; i++) {
        final change = window[i] - window[i - 1];
        if (change > 0) gain += change; else loss += -change;
      }
      final avgGain = gain / period;
      final avgLoss = loss / period;
      if (avgLoss == 0) return 100.0;
      final rs = avgGain / avgLoss;
      final rsi = 100 - (100 / (1 + rs));
      return rsi.isNaN || !rsi.isFinite ? 50.0 : rsi;
    } catch (_) {
      return 50.0;
    }
  }

  /// 날짜 문자열을 DateTime으로 파싱
  DateTime _parseDate(String dateStr) {
    try {
      if (dateStr.isEmpty) return DateTime(1900);
      
      // YYYYMMDD 형식 (예: 20250828)
      if (dateStr.length == 8 && RegExp(r'^\d{8}$').hasMatch(dateStr)) {
        final year = int.parse(dateStr.substring(0, 4));
        final month = int.parse(dateStr.substring(4, 6));
        final day = int.parse(dateStr.substring(6, 8));
        return DateTime(year, month, day);
      }
      
      // YYYY-MM-DD 형식 (예: 2025-08-28)
      if (dateStr.contains('-')) {
        return DateTime.parse(dateStr);
      }
      
      // 기타 형식은 기본값 반환
      return DateTime(1900);
    } catch (e) {
      print('❌ [UnifiedAnalysis] 날짜 파싱 실패: $dateStr - $e');
      return DateTime(1900);
    }
  }
}
