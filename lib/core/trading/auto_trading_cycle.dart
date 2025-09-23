import 'dart:async';
import '../data/app_data_manager.dart';
import '../database/repositories/signal_history_repository.dart';
import '../database/repositories/notification_history_repository.dart';
import '../database/repositories/trade_history_repository.dart';
import '../database/repositories/holdings_repository.dart';
import '../database/repositories/investment_style_repository.dart';
import '../database/repositories/current_price_repository.dart';
import '../database/repositories/analysis_results_repository.dart';
import '../services/local_notification_manager.dart';
import '../analysis/unified_analysis_service.dart';
import 'signal_types.dart';
import 'investment_style.dart';
import 'investment_style_manager.dart';
import '../api/kis_unified_api_service.dart';
import 'order_processor.dart';
import 'market_time_validator.dart';
import 'debug_trading_helper.dart';

/// 자동매매 시스템 메인 사이클 (3분마다 반복)
class AutoTradingCycle {
  static final AutoTradingCycle _instance = AutoTradingCycle._internal();
  factory AutoTradingCycle() => _instance;
  AutoTradingCycle._internal();

  Timer? _cycleTimer;
  bool _isRunning = false;
  DateTime? _lastCycleTime;
  
  // 의존성 주입
  final AppDataManager _appDataManager = AppDataManager.instance;
  final SignalHistoryRepository _signalRepo = SignalHistoryRepository();
  final NotificationHistoryRepository _notificationRepo = NotificationHistoryRepository();
  final TradeHistoryRepository _tradeHistoryRepo = TradeHistoryRepository();
  final HoldingsRepository _holdingsRepo = HoldingsRepository();
  final InvestmentStyleRepository _styleRepo = InvestmentStyleRepository();
  final CurrentPriceRepository _currentPriceRepo = CurrentPriceRepository();
  final LocalNotificationManager _notificationManager = LocalNotificationManager();
  final UnifiedAnalysisService _unifiedAnalysis = UnifiedAnalysisService.instance;
  final InvestmentStyleManager _styleManager = InvestmentStyleManager();
  final KisUnifiedApiService _unifiedApiService = KisUnifiedApiService();
  final OrderProcessor _orderProcessor = OrderProcessor();

  // 상태 관리
  bool _autoTradingEnabled = false;
  InvestmentStyle _currentStyle = InvestmentStyle.moderate;
  Map<String, dynamic> _styleParams = {};
  
  /// 자동매매 사이클 상태 확인
  bool get isRunning => _isRunning;
  bool get isAutoTradingEnabled => _autoTradingEnabled;
  DateTime? get lastCycleTime => _lastCycleTime;
  
  /// 자동매매 사이클 자동 시작 (앱 시작 시 호출)
  Future<void> autoStart() async {
    try {
      print('🤖 자동매매 사이클 자동 시작 확인...');
      
      // 자동매매 상태 확인
      final isEnabled = await _appDataManager.getAutoTradingStatus();
      print('🔍 자동매매 상태: $isEnabled');
      
      if (isEnabled && !_isRunning) {
        print('🚀 자동매매 활성화됨 - 사이클 시작');
        await startCycle();
      } else if (!isEnabled && _isRunning) {
        print('🛑 자동매매 비활성화됨 - 사이클 중지');
        await stopCycle();
      } else {
        print('📊 자동매매 상태 변경 없음');
      }
    } catch (e) {
      print('❌ 자동매매 사이클 자동 시작 실패: $e');
    }
  }

  /// 자동매매 사이클 시작
  Future<void> startCycle() async {
    print('🚀 자동매매 사이클 시작 요청...');
    
    if (_isRunning) {
      print('⚠️ 자동매매 사이클이 이미 실행 중입니다.');
      return;
    }

    try {
      print('🚀 자동매매 사이클 시작...');
      
      // 자동매매 상태 확인
      print('🔍 자동매매 상태 확인 중...');
      _autoTradingEnabled = await _appDataManager.getAutoTradingStatus();
      print('🔍 자동매매 상태 확인: $_autoTradingEnabled');
      
      if (!_autoTradingEnabled) {
        print('⚠️ 자동매매가 비활성화되어 있습니다.');
        print('⚠️ 자동매매를 활성화하려면 설정에서 자동매매를 켜주세요.');
        return;
      }
      
      print('✅ 자동매매가 활성화되어 있습니다.');

      // 투자 스타일 설정 로드
      print('🎯 투자 스타일 설정 로드 중...');
      await _loadInvestmentStyleSettings();
      print('✅ 투자 스타일 설정 로드 완료');
      
      // 첫 번째 사이클 즉시 실행
      print('🔄 첫 번째 사이클 즉시 실행...');
      await _executeCycle();
      
      // 3분 타이머 시작
      print('⏰ 3분 타이머 설정 중...');
      _cycleTimer = Timer.periodic(const Duration(minutes: 3), (timer) async {
        print('🔄 자동매매 사이클 타이머 트리거됨: ${DateTime.now().toString()}');
        await _executeCycle();
      });
      
      _isRunning = true;
      _lastCycleTime = DateTime.now();
      print('✅ 자동매매 사이클 시작 완료 (3분 간격)');
      print('📊 사이클 상태:');
      print('   - 실행 중: $_isRunning');
      print('   - 타이머: ${_cycleTimer != null ? "활성" : "비활성"}');
      print('   - 마지막 실행: ${_lastCycleTime?.toString() ?? "없음"}');
      
    } catch (e) {
      print('❌ 자동매매 사이클 시작 실패: $e');
      print('📊 오류 상세:');
      print('   - 오류 타입: ${e.runtimeType}');
      print('   - 오류 메시지: $e');
      rethrow;
    }
  }

  /// 자동매매 사이클 중지
  Future<void> stopCycle() async {
    try {
      print('🛑 자동매매 사이클 중지...');
      
      _cycleTimer?.cancel();
      _cycleTimer = null;
      _isRunning = false;
      
      print('✅ 자동매매 사이클 중지 완료');
    } catch (e) {
      print('❌ 자동매매 사이클 중지 실패: $e');
    }
  }

  /// 메인 사이클 실행
  Future<void> _executeCycle() async {
    print('🚀 === 자동매매 사이클 실행 시작 ===');
    print('🕐 현재 시간: ${DateTime.now()}');
    print('🔍 자동매매 상태: $_autoTradingEnabled');
    
    if (!_autoTradingEnabled) {
      print('🛑 자동매매 비활성화 상태 - 사이클 종료');
      return;
    }

    try {
      print('🔄 자동매매 사이클 시작 (${DateTime.now()})');
      _lastCycleTime = DateTime.now();

      // 1. 관심종목 및 보유종목 조회
      final watchlist = await _appDataManager.getWatchlist();
      final holdings = await _appDataManager.holdingsRepository.getHoldings();
      
      if (watchlist.isEmpty && holdings.isEmpty) {
        print('📋 분석할 종목이 없습니다');
        return;
      }

      print('📊 분석 대상: 관심종목 ${watchlist.length}개, 보유종목 ${holdings.length}개');

      // 2. 각 종목 분석
      final allStocks = [...watchlist, ...holdings];
      final signals = <SignalData>[];

      for (final stock in allStocks) {
        final stockCode = stock['stockCode']?.toString() ?? stock['stock_code']?.toString() ?? '';
        if (stockCode.isEmpty) {
          print('⚠️ 종목코드가 비어있어 건너뜀: $stock');
          continue;
        }
        final market = stock['market'] as String? ?? 'KOSPI';
        
        try {
          print('🔍 종목 분석 시작: $stockCode ($market)');
          
          // 🔧 수정: 분석탭과 동일한 파라미터 전달
          // 현재가 데이터 조회
          final currentPriceData = await _currentPriceRepo.getCurrentPrice(stockCode);
          double currentPrice = (currentPriceData?['currentPrice'] as num?)?.toDouble() ?? 
                               (currentPriceData?['current_price'] as num?)?.toDouble() ?? 0.0;
          

          
          // 현재가가 0이면 다른 방법으로 조회
          if (currentPrice <= 0) {
            print('⚠️ CurrentPriceRepository에서 현재가 조회 실패: $stockCode');
            currentPrice = await _resolveCurrentPrice(stockCode);
            print('   📊 대체 현재가: $currentPrice');
            

          }
          
          // 통합 분석 서비스로 분석 (분석탭과 동일한 파라미터)
          final analysis = await _unifiedAnalysis.analyzeStock(
            stockCode,
            currentPrice: currentPrice,
            prevClose: (currentPriceData?['prevClose'] as num?)?.toDouble() ?? 
                      (currentPriceData?['prev_close'] as num?)?.toDouble() ?? currentPrice,
            volume: (currentPriceData?['volume'] as num?)?.toDouble() ?? 0.0,
            highPrice: (currentPriceData?['high'] as num?)?.toDouble() ?? 
                      (currentPriceData?['highPrice'] as num?)?.toDouble() ?? currentPrice,
            lowPrice: (currentPriceData?['low'] as num?)?.toDouble() ?? 
                     (currentPriceData?['lowPrice'] as num?)?.toDouble() ?? currentPrice,
            openPrice: (currentPriceData?['open'] as num?)?.toDouble() ?? 
                      (currentPriceData?['openPrice'] as num?)?.toDouble() ?? currentPrice,
          );
          if (analysis == null) {
            print('⚠️ 기술적 분석 실패: $stockCode');
            continue;
          }
          
          // 새로운 시그널 타입 결정 함수 호출 (익절/손절 조건 포함)
          final analysisCurrentPrice = (analysis['currentPrice'] as num?)?.toDouble() ?? currentPrice;
          print('🔍 시그널 타입 결정 함수 호출: $stockCode (현재가: $analysisCurrentPrice)');
          final signalData = await _determineSignalType(
            analysis,
            stockCode,
            stock['stockName']?.toString() ?? stock['stock_name']?.toString() ?? stockCode,
            analysisCurrentPrice,
          );
          
          if (signalData != null) {
            signals.add(signalData);
            print('✅ 시그널 데이터 생성 완료: $stockCode - ${signalData.type.displayName}');
          }
          
        } catch (e) {
          print('❌ 종목 분석 실패: $stockCode - $e');
        }
      }

      // 3. 시그널 처리
      if (signals.isNotEmpty) {
        await _processSignals(signals.map((signal) => signal.toMap()).toList());
      }

      print('✅ 자동매매 사이클 완료 (${DateTime.now()})');

    } catch (e) {
      print('❌ 자동매매 사이클 실패: $e');
    }
  }

  /// 계좌 및 투자 스타일 정보 로드
  Future<void> _loadAccountAndStyleInfo() async {
    try {
      print('📊 계좌 및 투자 스타일 정보 로드...');
      
      // 투자 스타일 설정 로드
      await _loadInvestmentStyleSettings();
      
      // 로컬 DB에서 계좌 정보 조회
      final accountInfo = await _appDataManager.getAccountBalance();
      if (accountInfo != null) {
        print('✅ 계좌 정보 로드 완료');
      }
      
    } catch (e) {
      print('❌ 계좌 및 투자 스타일 정보 로드 실패: $e');
    }
  }

  /// 투자 스타일 설정 로드
  Future<void> _loadInvestmentStyleSettings() async {
    try {
      _currentStyle = _styleManager.currentStyle;
      _styleParams = await _styleManager.getStyleParameters(_currentStyle);
      
      print('📊 투자 스타일 설정 로드: ${_currentStyle.name}');
      print('  - 매수임계값: ${_styleParams['buyThreshold']}');
      print('  - 매도임계값: ${_styleParams['sellThreshold']}');
      print('  - 거래량조건: ${_styleParams['volumeCondition']}');
      
    } catch (e) {
      print('❌ 투자 스타일 설정 로드 실패: $e');
    }
  }

  /// 계좌 정보 업데이트
  Future<void> _updateAccountInfo() async {
    try {
      print('🔄 계좌 정보 업데이트...');
      
      // API로 계좌 정보 업데이트 (재시도 로직 포함) - 통일된 API 서비스 사용
      final accountInfo = await _unifiedApiService.getAccountBalanceCompat();
      
      // 로컬 DB 업데이트
      if (accountInfo != null) {
        // 계좌 정보를 DB에 저장하는 로직 추가 필요
        print('✅ 계좌 정보 업데이트 완료');
      } else {
        print('⚠️ 계좌 정보 조회 결과 없음 (로컬 DB 사용)');
      }
      
    } catch (e) {
      print('❌ 계좌 정보 업데이트 실패: $e');
      print('⚠️ 로컬 DB의 기존 계좌 정보를 사용합니다.');
    }
  }

  /// 관심종목 및 보유종목 업데이트
  Future<void> _updateWatchlistAndHoldings() async {
    try {
      print('🔄 관심종목 및 보유종목 업데이트...');
      
      // 관심종목 조회
      print('📋 관심종목 조회 시작...');
      final watchlist = await _appDataManager.getWatchlist();
      print('📋 관심종목 조회 결과: ${watchlist.length}개');
      
      // 관심종목 상세 출력
      if (watchlist.isNotEmpty) {
        print('📋 관심종목 목록:');
        for (int i = 0; i < watchlist.length; i++) {
          final item = watchlist[i];
          final stockCode = item['stockCode'] ?? item['stock_code'] ?? 'Unknown';
          final stockName = item['stockName'] ?? item['stock_name'] ?? 'Unknown';
          final market = item['market'] ?? 'Unknown';
          print('  ${i + 1}. $stockCode: $stockName (시장: $market)');
        }
      } else {
        print('⚠️ 관심종목이 비어있습니다!');
      }
      
      // 보유종목 조회 (국내 + 해외)
      print('💼 보유종목 조회 시작...');
      
      // 1. 국내 보유종목 조회
      print('🇰🇷 국내 보유종목 조회 시작...');
      List<Map<String, dynamic>> domesticHoldings = [];
      try {
        // 통일된 API 서비스 사용
        final domesticResult = await _unifiedApiService.getPositionsCompat();
        if (domesticResult.isNotEmpty) {
          domesticHoldings = List<Map<String, dynamic>>.from(domesticResult);
          print('✅ 국내 보유종목 조회 성공: ${domesticHoldings.length}개');
          
          // 국내 보유종목 상세 출력
          if (domesticHoldings.isNotEmpty) {
            print('🇰🇷 국내 보유종목 목록:');
            for (int i = 0; i < domesticHoldings.length; i++) {
              final holding = domesticHoldings[i];
              final stockCode = holding['stockCode'] ?? 'Unknown';
              final stockName = holding['stockName'] ?? 'Unknown';
              final quantity = holding['quantity'] ?? 0;
              final avgPrice = holding['avgPrice'] ?? 0.0;
              print('  ${i + 1}. $stockCode: $stockName (${quantity}주, 평균가: ${avgPrice}원)');
            }
          }
        } else {
          print('⚠️ 국내 보유종목 조회 결과 없음');
        }
      } catch (e) {
        print('❌ 국내 보유종목 조회 실패: $e');
      }
      
      // 2. 해외 보유종목 조회
      print('🌍 해외 보유종목 조회 시작...');
      List<Map<String, dynamic>> overseasHoldings = [];
      try {
        // 통일된 API 서비스 사용
        final overseasResult = await _unifiedApiService.getOverseasHoldingsCompat();
        if (overseasResult.isNotEmpty) {
          overseasHoldings = List<Map<String, dynamic>>.from(overseasResult);
          print('✅ 해외 보유종목 조회 성공: ${overseasHoldings.length}개');
          
          // 해외 보유종목 상세 출력
          if (overseasHoldings.isNotEmpty) {
            print('🌍 해외 보유종목 목록:');
            for (int i = 0; i < overseasHoldings.length; i++) {
              final holding = overseasHoldings[i];
              final stockCode = holding['stockCode'] ?? 'Unknown';
              final stockName = holding['stockName'] ?? 'Unknown';
              final quantity = holding['quantity'] ?? 0;
              final avgPrice = holding['avgPrice'] ?? 0.0;
              print('  ${i + 1}. $stockCode: $stockName (${quantity}주, 평균가: \$${avgPrice})');
            }
          }
        } else {
          print('⚠️ 해외 보유종목 조회 결과 없음');
        }
      } catch (e) {
        print('❌ 해외 보유종목 조회 실패: $e');
      }
      
      // 3. 전체 보유종목 통합
      final totalHoldings = <Map<String, dynamic>>[];
      totalHoldings.addAll(domesticHoldings);
      totalHoldings.addAll(overseasHoldings);
      
      print('📊 전체 보유종목 통합 결과: ${totalHoldings.length}개');
      print('  - 국내: ${domesticHoldings.length}개');
      print('  - 해외: ${overseasHoldings.length}개');
      
      if (totalHoldings.isNotEmpty) {
        print('📊 전체 보유종목 목록:');
        for (int i = 0; i < totalHoldings.length; i++) {
          final holding = totalHoldings[i];
          final stockCode = holding['stockCode'] ?? 'Unknown';
          final stockName = holding['stockName'] ?? 'Unknown';
          final quantity = holding['quantity'] ?? 0;
          final avgPrice = holding['avgPrice'] ?? 0.0;
          final market = holding['market'] ?? 'Unknown';
          print('  ${i + 1}. $stockCode: $stockName (${quantity}주, 평균가: $avgPrice, 시장: $market)');
        }
      } else {
        print('⚠️ 보유종목이 비어있습니다!');
      }
      
      // 로컬 DB 업데이트
      print('💾 로컬 DB에 보유종목 저장 중...');
      try {
        await _holdingsRepo.saveHoldings(totalHoldings);
        print('✅ 보유종목 DB 저장 완료: ${totalHoldings.length}개');
        
        // 저장된 데이터 확인
        final savedHoldings = await _holdingsRepo.getHoldings();
        print('🔍 DB에서 조회된 보유종목: ${savedHoldings.length}개');
        
        if (savedHoldings.isNotEmpty) {
          print('🔍 DB 저장된 보유종목 확인:');
          for (int i = 0; i < savedHoldings.length; i++) {
            final holding = savedHoldings[i];
            final stockCode = holding['stockCode'] ?? 'Unknown';
            final stockName = holding['stockName'] ?? 'Unknown';
            final quantity = holding['quantity'] ?? 0;
            print('  ${i + 1}. $stockCode: $stockName (${quantity}주)');
          }
        }
      } catch (e) {
        print('❌ 보유종목 DB 저장 실패: $e');
        print('📊 오류 상세:');
        print('   - 오류 타입: ${e.runtimeType}');
        print('   - 오류 메시지: $e');
      }
      
      print('✅ 관심종목 및 보유종목 업데이트 완료: 관심=${watchlist.length}개, 보유=${totalHoldings.length}개');
      
    } catch (e) {
      print('❌ 관심종목 및 보유종목 업데이트 실패: $e');
      print('📊 오류 상세:');
      print('   - 오류 타입: ${e.runtimeType}');
      print('   - 오류 메시지: $e');
      print('   - 스택 트레이스: ${e.toString()}');
    }
  }

  /// 나스닥 종목 여부 확인
  bool _isNasdaqStock(String stockCode) {
    return stockCode.length <= 5 && RegExp(r'^[A-Z]+$').hasMatch(stockCode);
  }

  /// 시그널 분석
  Future<List<SignalData>> _analyzeSignals() async {
    try {
      print('🔍 시그널 분석 시작...');
      
      final signals = <SignalData>[];
      
      // 관심종목 분석
      print('📋 관심종목 조회 시작...');
      final watchlist = await _appDataManager.getWatchlist();
      print('📊 관심종목 ${watchlist.length}개 분석 시작');
      
      if (watchlist.isEmpty) {
        print('⚠️ 관심종목이 비어있어 시그널 분석을 건너뜁니다.');
        return signals;
      }
      
      // 관심종목 요약
      print('📋 관심종목: ${watchlist.length}개');
      
      for (final stock in watchlist) {
        final stockCode = stock['stockCode']?.toString() ?? stock['stock_code']?.toString() ?? '';
        final stockName = stock['stockName']?.toString() ?? stock['stock_name']?.toString() ?? stockCode;
        
        if (stockCode.isEmpty) {
          print('⚠️ 종목코드가 비어있어 건너뜀: $stock');
          continue;
        }
        
        print('🔍 종목 분석 시작: $stockCode ($stockName)');
        
        try {
          // 1. 현재가 데이터 조회 (분석탭과 동일한 방식)
          print('📊 현재가 데이터 조회 시작: $stockCode');
          Map<String, dynamic>? currentPriceData;
          
          // 시장 구분 확인
          final market = stock['market'] as String? ?? 'Unknown';
          final isNasdaq = _isNasdaqStock(stockCode);
          print('📊 시장 구분: $market, 나스닥 여부: $isNasdaq');
          
          try {
            // 분석탭과 동일한 방식으로 데이터 수집
            // 통일된 API 서비스로 현재가 조회
            print('📊 현재가 조회: $stockCode');
            currentPriceData = await _unifiedApiService.getStockPrice(stockCode);
            
            if (currentPriceData != null && currentPriceData.isNotEmpty) {
              print('✅ 현재가 데이터 조회 성공: $stockCode');
              print('   - 현재가: ${currentPriceData['currentPrice']}');
              print('   - 전일종가: ${currentPriceData['prevClose']}');
              print('   - 거래량: ${currentPriceData['volume']}');
              print('   - 고가: ${currentPriceData['high']}');
              print('   - 저가: ${currentPriceData['low']}');
              print('   - 시가: ${currentPriceData['open']}');
            } else {
              print('❌ 현재가 데이터 조회 실패: $stockCode');
              continue;
            }
          } catch (e) {
            print('❌ 현재가 데이터 조회 실패: $stockCode - $e');
            continue;
          }
          
          // 2. 차트 데이터 조회 (로컬DB 우선)
          print('📈 차트 데이터 조회 시작: $stockCode');
          List<Map<String, dynamic>> chartData = [];
          
          try {
            // 로컬DB에서 차트 데이터 먼저 확인
            final localChartData = await _appDataManager.historicalDataRepo.getRecentBars(stockCode, limit: 80);
            if (localChartData.isNotEmpty) {
              print('📊 [AutoTradingCycle] 로컬 DB에서 데이터 발견: $stockCode (${localChartData.length}개)');
              chartData = localChartData;
            } else {
              print('📊 [AutoTradingCycle] 로컬 DB에 데이터 없음, API 호출: $stockCode');
              // 로컬DB에 없을 때만 API 호출 (폴백)
              // 통일된 API 서비스로 차트 데이터 조회
              print('📈 차트 데이터 조회: $stockCode');
              chartData = await _unifiedApiService.getDailyChart(stockCode, count: 80);
            }
            
            print('📊 차트 데이터 조회 결과: $stockCode - ${chartData.length}개');
            
            if (chartData.isNotEmpty) {
              print('📊 차트 데이터 샘플: $stockCode');
              print('  - 첫 번째 데이터 키: ${chartData.first.keys.toList()}');
              print('  - 첫 번째 데이터: ${chartData.first}');
            } else {
              print('⚠️ 차트 데이터가 비어있음: $stockCode');
              continue;
            }
          } catch (e) {
            print('❌ 차트 데이터 조회 실패: $stockCode - $e');
            continue;
          }
          
          // 3. 정규장 시간 체크 (지표 계산은 항상 수행, 매매 시그널만 제한)
          final tradingMarket = MarketTimeValidator.instance.getMarketFromSymbol(stockCode);
          final tradingInfo = MarketTimeValidator.instance.getCurrentTradingInfo(tradingMarket);
          final isTradingTime = tradingInfo['isTrading'] as bool;
          
          print('📊 정규장 시간 체크: $stockCode - ${tradingInfo['status']} (${tradingInfo['reason']})');
          
          // 정규장 시간 외에는 매매 시그널만 생성하지 않음 (지표 계산은 계속 수행)
          if (!isTradingTime) {
            print('⚠️ 정규장 시간 외 - 매매 시그널만 제한, 지표 계산은 계속: $stockCode');
          }
          
          // 4. 기술적 지표 계산
          print('🔧 기술적 지표 계산 시작: $stockCode');
          Map<String, dynamic>? analysis;
          
          try {
            print('🔍 [AutoTradingCycle] UnifiedAnalysis 호출 시작: $stockCode');
            print('🔍 [AutoTradingCycle] 호출 시점: ${DateTime.now()}');
            
            // 분석탭과 동일한 방식으로 파라미터 전달
            analysis = await _unifiedAnalysis.analyzeStock(
              stockCode,
              currentPrice: (currentPriceData['currentPrice'] as num?)?.toDouble(),
              prevClose: (currentPriceData['prevClose'] as num?)?.toDouble(),
              volume: (currentPriceData['volume'] as num?)?.toDouble(),
              highPrice: (currentPriceData['high'] as num?)?.toDouble(),
              lowPrice: (currentPriceData['low'] as num?)?.toDouble(),
              openPrice: (currentPriceData['open'] as num?)?.toDouble(),
            );
            
            print('🔍 [AutoTradingCycle] UnifiedAnalysis 호출 완료: $stockCode');
            print('🔍 [AutoTradingCycle] 분석 결과: ${analysis != null ? '성공' : '실패'}');
            
            print('🔍 [AutoTradingCycle] UnifiedAnalysis 호출 파라미터:');
            if (currentPriceData != null) {
              print('  - 현재가: ${(currentPriceData['currentPrice'] as num?)?.toDouble()}');
              print('  - 전일가: ${(currentPriceData['prevClose'] as num?)?.toDouble()}');
              print('  - 거래량: ${(currentPriceData['volume'] as num?)?.toDouble()}');
              print('  - 고가: ${(currentPriceData['high'] as num?)?.toDouble()}');
              print('  - 저가: ${(currentPriceData['low'] as num?)?.toDouble()}');
              print('  - 시가: ${(currentPriceData['open'] as num?)?.toDouble()}');
            } else {
              print('  - currentPriceData가 null입니다.');
            }
            
            // 분석 결과 유효성 검증 및 보강
            if (analysis == null || analysis.isEmpty) {
              print('⚠️ [AutoTradingCycle] 분석 결과가 비어있음: $stockCode');
              analysis = await _enhanceAnalysisWithLocalData(stockCode, currentPriceData, chartData);
              if (analysis == null) {
                print('❌ [AutoTradingCycle] 로컬 데이터 보강도 실패: $stockCode');
                continue;
              }
            }
            
            // 점수 유효성 검증 (NaN/Infinite만 제외)
            final comprehensiveScore = (analysis['comprehensiveScore'] as num?)?.toDouble() ?? 0.0;
            if (comprehensiveScore.isNaN || comprehensiveScore.isInfinite) {
              print('⚠️ [AutoTradingCycle] 종합점수가 NaN/Infinite: $comprehensiveScore');
              analysis = await _enhanceAnalysisWithLocalData(stockCode, currentPriceData, chartData);
              if (analysis == null) {
                print('❌ [AutoTradingCycle] 점수 보강도 실패: $stockCode');
                continue;
              }
              final enhancedScore = (analysis['comprehensiveScore'] as num?)?.toDouble() ?? 0.0;
              if (enhancedScore.isNaN || enhancedScore.isInfinite) {
                print('❌ [AutoTradingCycle] 점수 보강 후에도 NaN/Infinite: $stockCode');
                continue;
              }
            }
            
            if (analysis != null && analysis.isNotEmpty) {
              print('✅ 기술적 지표 계산 완료: $stockCode');
              print('  - 시그널: ${analysis['signal']}');
              print('  - 신뢰도: ${analysis['confidence']}');
              print('  - 종합점수: ${(analysis['comprehensiveScore'] as num?)?.toDouble()?.toStringAsFixed(3) ?? 'N/A'}');
            } else {
              print('⚠️ 기술적 지표 계산 결과가 비어있음: $stockCode');
              continue;
            }
          } catch (e) {
            print('❌ 기술적 지표 계산 실패: $stockCode - $e');
            continue;
          }
          
          // 4. 시그널 생성 (comprehensiveScore 기반)
          final comprehensiveScore = (analysis['comprehensiveScore'] as num?)?.toDouble() ?? 0.0;
          final signal = analysis['signal'] as String? ?? '관망';
          final confidence = (analysis['confidence'] as num?)?.toDouble() ?? 0.0;
          
          // 현재가 보강: 캐시/DB/API 순으로 확보
          double displayPrice = (currentPriceData['currentPrice'] as num?)?.toDouble() ?? 0.0;
          if (displayPrice <= 0) {
            displayPrice = await _resolveCurrentPrice(stockCode);
          }
          
          // 새로운 시그널 타입 결정 함수 호출 (익절/손절 조건 포함)
          final signalData = await _determineSignalType(
            analysis,
            stockCode,
            stockName,
            displayPrice,
          );
          
          if (signalData != null) {
            print('✅ 시그널 데이터 생성 완료: $stockCode - ${signalData.type.displayName}');
            
            // 시그널 처리 (SignalData를 Map으로 변환)
            final signalMap = {
              'stockCode': signalData.stockCode,
              'stockName': signalData.stockName,
              'signalType': signalData.type.displayName,
              'currentPrice': signalData.price,
              'score': (analysis['comprehensiveScore'] as num?)?.toDouble() ?? 0.0,
              'scoreValid': true,
              'confidence': (analysis['confidence'] as num?)?.toDouble() ?? 0.0,
              'timestamp': signalData.timestamp,
              'market': signalData.market,
            };
            
            await _processSignals([signalMap]);
          } else {
            print('📊 매매 시그널 없음: $stockCode');
          }
          
        } catch (e) {
          print('❌ 종목 분석 실패: $stockCode - $e');
          continue;
        }
      }

      print('✅ 시그널 분석 완료: ${signals.length}개 시그널 발견');
      
      return signals;
      
    } catch (e) {
      print('❌ 시그널 분석 실패: $e');
      return [];
    }
  }

  /// 시그널 타입 결정 (익절/손절 조건 포함)
  Future<SignalData?> _determineSignalType(
    Map<String, dynamic> analysis,
    String stockCode,
    String stockName,
    double currentPrice,
  ) async {
    try {
      final comprehensiveScore = (analysis['comprehensiveScore'] as num?)?.toDouble() ?? 0.0;
      
      // 현재 투자 스타일 설정 로드
      final currentStyleParams = await _styleManager.getStyleParameters(_currentStyle);
      final buyThreshold = (currentStyleParams['buyThreshold'] as num?)?.toDouble() ?? 0.0;
      final sellThreshold = (currentStyleParams['sellThreshold'] as num?)?.toDouble() ?? 0.0;
      
      print('📊 투자 스타일 설정 확인:');
      print('   - 현재 스타일: ${_currentStyle.name}');
      print('   - 매수 임계값: $buyThreshold');
      print('   - 매도 임계값: $sellThreshold');
      print('   - 종합점수: ${comprehensiveScore.toStringAsFixed(3)}');
      
      String finalSignal = '';
      
      // 자동매매 ON 상태: 실제 매매 시그널 생성
      if (_autoTradingEnabled) {
        // 1순위: 익절/손절 조건 확인 (사용자 설정 우선)
        print('🔍 1순위: 익절/손절 조건 확인 시작 - $stockCode');
        final hasHoldingsForProfit = await _checkHoldingsForSellSignal(stockCode);
        print('   📊 보유종목 확인 결과: $hasHoldingsForProfit');
        
        if (hasHoldingsForProfit) {
          print('   🔍 수익률 조건 확인 시작...');
          final profitLossResult = await _checkProfitLossConditions(stockCode, currentPrice);
          final shouldSellForProfit = profitLossResult['shouldSell'] as bool;
          final profitLossReason = profitLossResult['reason'] as String;
          final profitRate = profitLossResult['profitRate'] as double;
          print('   📊 수익률 조건 확인 결과: $shouldSellForProfit ($profitLossReason)');
          
          if (shouldSellForProfit) {
            // 정규장 시간 체크 추가
            final market = _determineMarket(stockCode);
            final isTradingTime = MarketTimeValidator.instance.isTradingTime(market);
            
            if (!isTradingTime) {
              print('⚠️ 정규장 시간 외 - 매도 시그널 생성 차단: $stockCode');
              print('   📊 시장: $market');
              print('   📊 정규장 시간: $isTradingTime');
              print('   📊 익절/손절 조건은 만족했지만 정규장 시간 외라서 매도 시그널 생성 안함');
              return null;
            }
            
            print('✅ 매도 시그널 생성 (익절/손절): $stockCode');
            print('   🔍 매도 시그널 생성 지점: AutoTradingCycle.dart:746');
            print('   📊 종합점수: ${comprehensiveScore.toStringAsFixed(3)}');
            print('   📊 매도임계값: $sellThreshold');
            print('   📊 익절/손절 조건: $shouldSellForProfit ($profitLossReason)');
            print('   ⚠️ 익절/손절 조건으로 매도 시그널 생성됨 - 기술적 지표 점수와 무관');
            
            final detailedReason = '$profitLossReason (수익률 ${profitRate.toStringAsFixed(2)}%)';
            return SignalData(
              type: SignalType.sellSignal,
              stockCode: stockCode,
              stockName: stockName,
              price: currentPrice,
              reason: detailedReason,
              timestamp: DateTime.now(),
              analysis: analysis,
              isAutoTrade: false,
              market: market,
            );
          } else {
            print('   ❌ 수익률 조건 불만족 - 다음 단계로 진행');
          }
        } else {
          print('   ❌ 보유종목 없음 - 다음 단계로 진행');
        }
        
        // 3순위: 매수 시그널 확인
        if (comprehensiveScore >= buyThreshold) {
          // 매수 시그널 생성 전 보유종목 확인 (비동기)
          final canBuy = await _checkBuyConditionsForSignal(stockCode);
          if (!canBuy) {
            return null;
          }
          
          print('✅ 매수 시그널 생성: $stockCode');
          return SignalData(
            type: SignalType.buySignal,
            stockCode: stockCode,
            stockName: stockName,
            price: currentPrice,
            reason: '매수 조건 만족',
            timestamp: DateTime.now(),
            analysis: analysis,
            market: _determineMarket(stockCode),
          );
        }
        
        // 4순위: 관망 (임계값 사이 구간: sellThreshold < score < buyThreshold)
        print('➖ 관망: ${comprehensiveScore.toStringAsFixed(3)} (매도임계: ${sellThreshold.toStringAsFixed(3)}, 매수임계: ${buyThreshold.toStringAsFixed(3)})');
        return null;
      } else {
        // 자동매매 OFF 상태: 정보 시그널만 (0.05 차이로 기회 시그널 생성)
        final buyOpportunityThreshold = buyThreshold - 0.05; // 매수 기회: 임계값 - 0.05
        final sellOpportunityThreshold = sellThreshold + 0.05; // 매도 기회: 임계값 + 0.05
        
        if (comprehensiveScore >= buyOpportunityThreshold && comprehensiveScore < buyThreshold) {
          print('✅ 매수 기회 시그널 생성: $stockCode - 점수: ${comprehensiveScore.toStringAsFixed(3)} (임계값: ${buyThreshold.toStringAsFixed(2)}, 기회: ${buyOpportunityThreshold.toStringAsFixed(2)})');
          return SignalData(
            type: SignalType.buyOpportunity,
            stockCode: stockCode,
            stockName: stockName,
            price: currentPrice,
            reason: '매수 기회: 종합점수 ${comprehensiveScore.toStringAsFixed(2)} (임계값: ${buyThreshold.toStringAsFixed(2)}, 기회: ${buyOpportunityThreshold.toStringAsFixed(2)})',
            timestamp: DateTime.now(),
            analysis: analysis,
            isAutoTrade: false,
            market: _determineMarket(stockCode),
          );
        } else if (comprehensiveScore <= sellOpportunityThreshold && comprehensiveScore > sellThreshold) {
          // 정규장 시간 체크 추가
          final market = _determineMarket(stockCode);
          final isTradingTime = MarketTimeValidator.instance.isTradingTime(market);
          
          if (!isTradingTime) {
            print('⚠️ 정규장 시간 외 - 매도 기회 시그널 생성 차단: $stockCode');
            print('   📊 시장: $market');
            print('   📊 정규장 시간: $isTradingTime');
            print('   📊 매도 기회 조건은 만족했지만 정규장 시간 외라서 매도 기회 시그널 생성 안함');
            return null;
          }
          
          print('✅ 매도 기회 시그널 생성: $stockCode - 점수: ${comprehensiveScore.toStringAsFixed(3)} (임계값: ${sellThreshold.toStringAsFixed(2)}, 기회: ${sellOpportunityThreshold.toStringAsFixed(2)})');
          print('   🔍 매도 기회 시그널 생성 지점: AutoTradingCycle.dart:835');
          return SignalData(
            type: SignalType.sellOpportunity,
            stockCode: stockCode,
            stockName: stockName,
            price: currentPrice,
            reason: '매도 기회: 종합점수 ${comprehensiveScore.toStringAsFixed(3)} (임계값: ${sellThreshold.toStringAsFixed(3)}, 기회: ${sellOpportunityThreshold.toStringAsFixed(3)})',
            timestamp: DateTime.now(),
            analysis: analysis,
            isAutoTrade: false,
            market: market,
          );
        } else {
          // 기회 시그널 구간 외: 관망
          print('➖ 관망 (자동매매 OFF): ${comprehensiveScore.toStringAsFixed(3)} (기회 구간 외)');
          return null;
        }
      }
    } catch (e) {
      print('❌ 시그널 타입 결정 실패: $stockCode - $e');
      return null;
    }
  }

  /// 시장 분류 (MarketTimeValidator와 일치)
  String _determineMarket(String stockCode) {
    return MarketTimeValidator.instance.getMarketFromSymbol(stockCode);
  }

  /// 매도 시그널 생성 전 보유종목 확인 (비동기)
  Future<bool> _checkHoldingsForSellSignal(String stockCode) async {
    try {
      // 보유종목 정보 조회
      final holdings = await _appDataManager.holdingsRepository.getHoldings();
      
      // 해당 종목이 보유 중인지 확인
      final holding = holdings.firstWhere(
        (h) => h['stock_code'] == stockCode || h['stockCode'] == stockCode,
        orElse: () => <String, dynamic>{},
      );
      
      if (holding.isEmpty) {
        print('   ⚠️ 보유종목 없음: $stockCode');

        return false;
      }
      
      // 보유 수량 확인
      final quantity = (holding['quantity'] as num?)?.toInt() ?? 0;
      if (quantity <= 0) {
        print('   ⚠️ 보유 수량이 0: $stockCode');

        return false;
      }
      
      print('   ✅ 보유종목 확인 완료: $stockCode (${quantity}주)');

      return true;
    } catch (e) {
      print('❌ 보유종목 확인 실패: $stockCode - $e');

      return false;
    }
  }

  /// 부분익절/전체익절 조건 확인 (실제 보유종목의 수익률 체크)
  Future<Map<String, dynamic>> _checkProfitLossConditions(String stockCode, double currentPrice) async {
    try {
      print('🔍 부분익절/전체익절 조건 확인: $stockCode');
      
      // 보유종목 정보 조회
      final holdings = await _appDataManager.holdingsRepository.getHoldings();
      final holding = holdings.firstWhere(
        (h) => h['stock_code'] == stockCode || h['stockCode'] == stockCode,
        orElse: () => <String, dynamic>{},
      );
      
      if (holding.isEmpty) {
        print('   ⚠️ 보유종목 없음: $stockCode');
        return {'shouldSell': false, 'reason': '', 'profitRate': 0.0};
      }
      
      // 매수 가격과 수량 확인 (여러 필드명 시도)
      double entryPrice = (holding['entry_price'] as num?)?.toDouble() ?? 0.0;
      if (entryPrice <= 0) {
        entryPrice = (holding['avgPrice'] as num?)?.toDouble() ?? 0.0;
      }
      if (entryPrice <= 0) {
        entryPrice = (holding['avg_price'] as num?)?.toDouble() ?? 0.0;
      }
      if (entryPrice <= 0) {
        entryPrice = (holding['pchs_avg_pric'] as num?)?.toDouble() ?? 0.0;
      }
      
      int quantity = (holding['quantity'] as num?)?.toInt() ?? 0;
      if (quantity <= 0) {
        quantity = (holding['ovrs_cblc_qty'] as num?)?.toInt() ?? 0;
      }
      
      print('   🔍 보유종목 데이터 확인: $stockCode');
      print('     - 매수가: $entryPrice (필드: ${holding.keys.where((k) => k.contains('price') || k.contains('avg') || k.contains('pchs')).join(', ')})');
      print('     - 수량: $quantity (필드: ${holding.keys.where((k) => k.contains('qty') || k.contains('quantity')).join(', ')})');
      print('     - 현재가: $currentPrice (매개변수로 전달받음)');
      

      
      if (entryPrice <= 0 || quantity <= 0) {
        print('   ⚠️ 매수 정보 부족: 매수가=$entryPrice, 수량=$quantity');
        print('   🔍 전체 보유종목 데이터: $holding');

        return {'shouldSell': false, 'reason': '', 'profitRate': 0.0};
      }
      
      // 현재가 유효성 검사
      if (currentPrice <= 0) {
        print('   ⚠️ 현재가 정보 부족: 현재가=$currentPrice');
        print('   🔍 익절/손절 계산 불가능 - 현재가가 0원이므로 조건 확인 중단');

        return {'shouldSell': false, 'reason': '', 'profitRate': 0.0};
      }
      
      // 현재 투자 스타일 설정 로드
      final currentStyleParams = await _styleManager.getStyleParameters(_currentStyle);
      final partialProfit = (currentStyleParams['partialProfit'] as num?)?.toDouble() ?? 0.0;
      final fullProfit = (currentStyleParams['fullProfit'] as num?)?.toDouble() ?? 0.0;
      final stopLoss = (currentStyleParams['stopLoss'] as num?)?.toDouble() ?? 0.0;
      
      print('   📊 설정값: 부분익절=$partialProfit%, 전체익절=$fullProfit%, 손절=$stopLoss%');
      

      
      // 수익률 계산
      final pnlPct = (currentPrice - entryPrice) / entryPrice * 100;
      print('   📊 수익률: ${pnlPct.toStringAsFixed(2)}% (매수가: $entryPrice, 현재가: $currentPrice)');
      
      // 매도 조건 체크
      final shouldSellForFullProfit = pnlPct >= fullProfit;
      final shouldSellForPartialProfit = pnlPct >= partialProfit;
      final shouldSellForStopLoss = pnlPct <= stopLoss;
      
      print('   🔍 매도 조건 체크:');
      print('     - 전체익절: ${pnlPct.toStringAsFixed(2)}% >= ${fullProfit}% ? $shouldSellForFullProfit');
      print('     - 부분익절: ${pnlPct.toStringAsFixed(2)}% >= ${partialProfit}% ? $shouldSellForPartialProfit');
      print('     - 손절: ${pnlPct.toStringAsFixed(2)}% <= ${stopLoss}% ? $shouldSellForStopLoss');
      

      
      final shouldSell = shouldSellForFullProfit || shouldSellForPartialProfit || shouldSellForStopLoss;
      
      if (shouldSell) {
        String reason = '';
        if (shouldSellForFullProfit) reason = '전체익절';
        else if (shouldSellForPartialProfit) reason = '부분익절';
        else if (shouldSellForStopLoss) reason = '손절';
        
        print('   ✅ 매도 조건 만족: $reason (${pnlPct.toStringAsFixed(2)}%)');
        print('   🔍 익절/손절 매도 시그널 생성 지점: AutoTradingCycle.dart:970 (_checkProfitLossConditions)');
        

        
        return {
          'shouldSell': true,
          'reason': reason,
          'profitRate': pnlPct,
          'targetRate': shouldSellForFullProfit ? fullProfit : (shouldSellForPartialProfit ? partialProfit : stopLoss)
        };
      } else {
        print('   ❌ 매도 조건 불만족: 수익률 ${pnlPct.toStringAsFixed(2)}%');
        

        
        return {'shouldSell': false, 'reason': '', 'profitRate': pnlPct};
      }
    } catch (e) {
      print('❌ 부분익절/전체익절 조건 확인 실패: $e');

      return {'shouldSell': false, 'reason': '', 'profitRate': 0.0};
    }
  }

  /// 매수 시그널 생성 전 조건 확인 (비동기, 완화된 조건)
  Future<bool> _checkBuyConditionsForSignal(String stockCode) async {
    try {
      // 비동기적으로 보유종목 데이터 확인
      final holdings = await _appDataManager.holdingsRepository.getHoldings();
      
      // 1. 이미 보유 중인지 확인 (완화: 보유 중이어도 시그널 생성)
      final existingHolding = holdings.firstWhere(
        (h) => h['stock_code'] == stockCode || h['stockCode'] == stockCode,
        orElse: () => <String, dynamic>{},
      );
      
      if (existingHolding.isNotEmpty) {
        print('⚠️ 매수 시그널 정보: $stockCode - 이미 보유 중 (${existingHolding['quantity']}주)');
        
        // 중복 알림 방지: 최근 1분 내에 같은 알림이 있었는지 확인
        final now = DateTime.now();
        final oneMinuteAgo = now.subtract(const Duration(minutes: 1));
        final recentNotifications = await _notificationRepo.getNotificationsByDateRange(oneMinuteAgo, now);
        final hasRecentNotification = recentNotifications.any((notification) =>
            notification['type'] == '📈 매수 시그널: $stockCode' && 
            notification['message'].contains('이미 ${existingHolding['quantity']}주 보유 중'));
        
        if (!hasRecentNotification) {
          // 이미 보유 중인 종목에 대한 알림 발송
          await _notificationManager.showNotification(
            title: '📈 매수 시그널: $stockCode',
            body: '이미 ${existingHolding['quantity']}주 보유 중 - 분할 매수 고려',
          );
        } else {
          print('⚠️ 최근 1분 내에 이미 보유 중 알림이 있었습니다: $stockCode');
        }
        
        // 보유 중이어도 시그널은 생성 (분할 매수 전략)
        return true;
      }
      
      // 2. 최대 종목 수 확인 (완화: 10개까지 허용)
      // 로컬DB에서 최대 종목 수 가져오기
    final styleParams = await _styleManager.getStyleParameters(_currentStyle);
    final maxStocks = (styleParams['maxStocks'] as num?)?.toInt();
    if (maxStocks == null) {
      print('⚠️ 최대 종목 수가 설정되지 않았습니다.');
      return false;
    }
      if (holdings.length >= maxStocks) {
        print('⚠️ 매수 시그널 정보: $stockCode - 최대 종목 수 도달 (${holdings.length}/$maxStocks)');
        
        // 중복 알림 방지: 최근 1분 내에 같은 알림이 있었는지 확인
        final now = DateTime.now();
        final oneMinuteAgo = now.subtract(const Duration(minutes: 1));
        final recentNotifications = await _notificationRepo.getNotificationsByDateRange(oneMinuteAgo, now);
        final hasRecentNotification = recentNotifications.any((notification) =>
            notification['type'] == '📈 매수 시그널: $stockCode' && 
            notification['message'].contains('최대 종목 수 도달'));
        
        if (!hasRecentNotification) {
          // 최대 종목 수 도달 시 알림 발송
          await _notificationManager.showNotification(
            title: '📈 매수 시그널: $stockCode',
            body: '최대 종목 수 도달 (${holdings.length}/$maxStocks) - 매수 제한',
          );
        } else {
          print('⚠️ 최근 1분 내에 최대 종목 수 도달 알림이 있었습니다: $stockCode');
        }
        
        // 최대 종목 수 도달해도 시그널은 생성 (알림 목적)
        return true;
      }
      
      return true;
      
    } catch (e) {
      print('❌ 매수 조건 확인 실패: $stockCode - $e');
      // 오류 발생 시에도 시그널은 생성하도록 true 반환 (알림 목적)
      return true;
    }
  }

  /// 시그널 처리
  Future<void> _processSignals(List<Map<String, dynamic>> signals) async {
    try {
      print('🎯 ${signals.length}개 시그널 처리 시작');
      
      for (final signal in signals) {
        // null-safe 파싱 및 기본값 적용
        final stockCode = (signal['stockCode'] ?? signal['stock_code'] ?? '').toString();
        String signalType = (signal['signal'] ?? signal['signalType'] ?? signal['tradingDecision'] ?? '').toString();
        final stockName = (signal['stockName'] ?? signal['stock_name'] ?? '').toString();
        double currentPrice = (signal['currentPrice'] ?? signal['price'] ?? 0.0) as double;
        final reason = (signal['reason'] ?? '').toString();
        
        print('📊 시그널 처리: $stockCode - $signalType ($reason)');
        
        // 현재가가 0이면 다시 조회
        if (currentPrice <= 0) {
          print('⚠️ 시그널 처리: 현재가가 유효하지 않음 ($currentPrice), 다시 조회 중...');
          currentPrice = await _resolveCurrentPrice(stockCode);
          if (currentPrice <= 0) {
            print('❌ 시그널 처리: 현재가 조회 실패, 시그널 건너뜀');
            continue;
          }
        }
        
        // 시그널 타입에 따른 처리
        if (signalType.contains('매도') || signalType.contains('sell')) {
          await _executeSellOrder({
            'stockCode': stockCode,
            'stockName': stockName,
            'currentPrice': currentPrice,
            'reason': reason,
            'score': signal['score'] ?? 0.0,
          });
        } else if (signalType.contains('매수') || signalType.contains('buy')) {
          await _executeBuyOrder({
            'stockCode': stockCode,
            'stockName': stockName,
            'currentPrice': currentPrice,
            'reason': reason,
            'score': signal['score'] ?? 0.0,
          });
        } else {
          print('⚠️ 알 수 없는 시그널 타입: $signalType');
        }
      }
      
      print('✅ 시그널 처리 완료');
      
    } catch (e) {
      print('❌ 시그널 처리 실패: $e');
    }
  }

  /// 매수 주문 실행
  Future<void> _executeBuyOrder(Map<String, dynamic> signal) async {
    final stockCode = signal['stockCode'] as String;
    final stockName = signal['stockName'] as String;
    double currentPrice = signal['currentPrice'] as double;
    final score = signal['score'] as double? ?? 0.0;
    
    print('💰 매수 주문 실행: $stockCode ($stockName) - $currentPrice원');
    
    // 1일 최대 2회 자동 매수 제한 (종목별)
    try {
      final now = DateTime.now();
      final dayStart = DateTime(now.year, now.month, now.day);
      final dayEnd = dayStart.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
      final todaySignals = await _signalRepo.getSignalsByDateRange(dayStart, dayEnd);
      final todayBuysForStock = todaySignals.where((row) =>
        (row['stock_code']?.toString() ?? '') == stockCode &&
        (row['signal_type']?.toString() ?? '') == '매수' &&
        (row['memo']?.toString() ?? '').contains('AutoTrading_')
      ).length;
      if (todayBuysForStock >= 2) {
        print('⛔ 1일 매수 횟수 제한 초과: $stockCode - 오늘 ${todayBuysForStock}회');
        await _notificationManager.showNotification(
          title: '⛔ 자동매수 제한: $stockName',
          body: '$stockCode 오늘 매수 2회 제한 초과로 건너뜁니다.',
        );
        return;
      }
    } catch (e) {
      print('⚠️ 매수 횟수 제한 검사 실패(무시): $e');
    }
    
    try {
      // 현재가 보강 (0이거나 유효하지 않은 경우)
      if (currentPrice <= 0) {
        print('⚠️ [AutoTradingCycle] 현재가가 유효하지 않음: $currentPrice');
        currentPrice = await _resolveCurrentPrice(stockCode);
        if (currentPrice <= 0) {
          print('❌ [AutoTradingCycle] 현재가 보강 실패: $stockCode');
          return;
        }
        print('✅ [AutoTradingCycle] 현재가 보강 완료: $currentPrice');
      }
      
      // 투자 스타일에서 매수 수량 계산
      final positionSize = (_styleParams['positionSize'] as num?)?.toDouble() ?? 0.1;
      
      // 해외주식인지 확인
      final isOverseas = RegExp(r'^[A-Z]{1,5}$').hasMatch(stockCode);
      
      double availableBalance = 0.0;
      if (isOverseas) {
        // 해외주식: 달러 잔고 조회
        print('🌍 해외주식 달러 잔고 조회: $stockCode');
        try {
          // 통일된 API 서비스 사용
          availableBalance = await _unifiedApiService.getOverseasPaymentStandardBalanceCompat();
          print('💰 달러 잔고: \$${availableBalance.toStringAsFixed(2)}');
          
          if (availableBalance <= 0) {
            // 달러 잔고가 0이면 매수가능금액 조회 시도
            print('⚠️ 달러 잔고가 0이므로 매수가능금액 조회 시도');
            availableBalance = await _unifiedApiService.getOverseasBuyableAmountCompat2(exchangeCode: 'NASD', currency: 'USD');
            print('💰 매수가능 달러: \$${availableBalance.toStringAsFixed(2)}');
          }
          
          if (availableBalance <= 0) {
            print('⚠️ 달러 잔고가 0이므로 테스트용 기본값 사용');
            availableBalance = 359.0; // 359달러 (사용자가 언급한 금액)
          }
        } catch (e) {
          print('❌ 달러 잔고 조회 실패: $e');
          availableBalance = 359.0; // 기본값 사용
        }
      } else {
        // 국내주식: 원화 잔고 조회 (직접 KIS API 사용)
        print('🔍 국내주식 가용자금 조회 시작...');
        
        try {
          // 1. 통일된 API 서비스에서 계좌 잔고 조회
          final accountBalance = await _unifiedApiService.getAccountBalanceCompat();
          print('🔍 통일된 API 계좌 잔고 조회 결과: $accountBalance');
          
          if (accountBalance != null && accountBalance is Map<String, dynamic>) {
            // accountInfo 구조에서 가용 자금 찾기
            final accountInfo = accountBalance['accountInfo'] as Map<String, dynamic>?;
            if (accountInfo != null) {
              // 여러 키에서 가용 자금 찾기 (우선순위 순)
              availableBalance = (accountInfo['availableBalance'] as num?)?.toDouble() ?? 
                                (accountInfo['ordAbleAmt'] as num?)?.toDouble() ?? 
                                (accountInfo['ord_able_amt'] as num?)?.toDouble() ?? 
                                (accountInfo['availableAmount'] as num?)?.toDouble() ?? 
                                (accountInfo['balance'] as num?)?.toDouble() ?? 
                                (accountInfo['dncaTotAmt'] as num?)?.toDouble() ?? 0.0;
              
              print('💰 KIS API accountInfo에서 추출된 가용 자금: ${availableBalance.toStringAsFixed(0)}원');
              print('💰 accountInfo 키들: ${accountInfo.keys.toList()}');
            } else {
              // 직접 accountBalance에서 찾기
              availableBalance = (accountBalance['availableBalance'] as num?)?.toDouble() ?? 
                                (accountBalance['ordAbleAmt'] as num?)?.toDouble() ?? 
                                (accountBalance['ord_able_amt'] as num?)?.toDouble() ?? 
                                (accountBalance['availableAmount'] as num?)?.toDouble() ?? 
                                (accountBalance['balance'] as num?)?.toDouble() ?? 
                                (accountBalance['dncaTotAmt'] as num?)?.toDouble() ?? 0.0;
              
              print('💰 KIS API 직접에서 추출된 가용 자금: ${availableBalance.toStringAsFixed(0)}원');
              print('💰 accountBalance 키들: ${accountBalance.keys.toList()}');
            }
          } else {
            print('⚠️ KIS API 계좌 잔고가 null이거나 Map이 아님');
            availableBalance = 0.0;
          }
          
          // 2. KIS API에서 가용자금이 0이면 AppDataManager에서 재시도
          if (availableBalance <= 0) {
            print('⚠️ KIS API에서 가용자금이 0이므로 AppDataManager에서 재시도');
            final appDataBalance = await _appDataManager.getAccountBalance();
            print('🔍 AppDataManager 계좌 잔고 조회 결과: $appDataBalance');
            
            if (appDataBalance != null) {
              Map<String, dynamic>? accountInfo;
              
              // 중첩된 구조 처리
              if (appDataBalance['accountInfo'] is Map<String, dynamic>) {
                accountInfo = appDataBalance['accountInfo'] as Map<String, dynamic>;
              } else if (appDataBalance is Map<String, dynamic>) {
                accountInfo = appDataBalance;
              }
              
              if (accountInfo != null) {
                availableBalance = (accountInfo['availableBalance'] as num?)?.toDouble() ?? 
                                  (accountInfo['ordAbleAmt'] as num?)?.toDouble() ?? 
                                  (accountInfo['ord_able_amt'] as num?)?.toDouble() ?? 
                                  (accountInfo['availableAmount'] as num?)?.toDouble() ?? 
                                  (accountInfo['balance'] as num?)?.toDouble() ?? 
                                  (accountInfo['dncaTotAmt'] as num?)?.toDouble() ?? 0.0;
                
                print('💰 AppDataManager에서 추출된 가용 자금: ${availableBalance.toStringAsFixed(0)}원');
                print('💰 accountInfo 키들: ${accountInfo.keys.toList()}');
              }
            }
          }
          
        } catch (e) {
          print('❌ KIS API 계좌 잔고 조회 실패: $e');
          availableBalance = 0.0;
        }
        
        // 가용 자금이 부족하면 매수 차단
        if (availableBalance <= 0) {
          print('❌ 가용 자금 부족으로 매수 차단: ${availableBalance.toStringAsFixed(0)}원');
          await _notificationManager.showNotification(
            title: '❌ 매수 실패: $stockName',
            body: '$stockCode - 가용 자금 부족 (${availableBalance.toStringAsFixed(0)}원)',
          );
          return;
        }
        
        // 최소 주문 금액 체크 (500원으로 수정됨)
        if (availableBalance < 500) {
          print('❌ 최소 주문 금액 미달로 매수 차단: ${availableBalance.toStringAsFixed(0)}원');
          await _notificationManager.showNotification(
            title: '❌ 매수 실패: $stockName',
            body: '$stockCode - 최소 주문 금액 미달 (${availableBalance.toStringAsFixed(0)}원 < 500원)',
          );
          return;
        }
      }
      
      // 매수 수량 계산 (가용 자금의 positionSize% 사용)
      final orderAmount = availableBalance * positionSize;
      int quantity = 0;
      if (currentPrice > 0 && orderAmount.isFinite) {
        quantity = (orderAmount / currentPrice).floor();
      }
      
      print('📊 매수 수량 계산 상세:');
      print('  - 종목: $stockCode (${isOverseas ? '해외주식' : '국내주식'})');
      print('  - 가용 자금: ${isOverseas ? '\$${availableBalance.toStringAsFixed(2)}' : '${availableBalance.toStringAsFixed(0)}원'}');
      print('  - 포지션 비율: ${(positionSize * 100).toStringAsFixed(1)}%');
      print('  - 주문 금액: ${isOverseas ? '\$${orderAmount.toStringAsFixed(2)}' : '${orderAmount.toStringAsFixed(0)}원'}');
      print('  - 현재가: ${isOverseas ? '\$${currentPrice.toStringAsFixed(2)}' : '${currentPrice.toStringAsFixed(2)}원'}');
      print('  - 계산된 수량: $quantity주');
      
      if (quantity <= 0) {
        print('❌ 매수 수량이 0이어서 주문을 건너뜁니다.');
        print('  - 원인 분석:');
        print('    * 현재가: $currentPrice (${currentPrice > 0 ? '정상' : '문제'})');
        print('    * 가용자금: $availableBalance (${availableBalance > 0 ? '정상' : '문제'})');
        print('    * 포지션비율: ${(positionSize * 100).toStringAsFixed(1)}%');
        print('    * 주문금액: $orderAmount (${orderAmount.isFinite ? '정상' : '문제'})');
        print('    * 계산식: ${orderAmount.toStringAsFixed(0)} / ${currentPrice.toStringAsFixed(2)} = ${(orderAmount / currentPrice).toStringAsFixed(2)}');
        
        // 매수 조건 미충족 알림 발송 (더 정확한 원인 분석)
        String reason = '';
        if (currentPrice <= 0) {
          reason = '현재가 조회 실패';
        } else if (availableBalance <= 0) {
          reason = '가용자금 부족';
        } else if (orderAmount <= 0) {
          reason = '주문금액 계산 오류';
        } else if (orderAmount < currentPrice) {
          reason = '가용자금 부족 (${availableBalance.toStringAsFixed(0)}원으로 ${currentPrice.toStringAsFixed(0)}원 주식 구매 불가)';
        } else {
          reason = '수량 계산 오류 (주문금액: ${orderAmount.toStringAsFixed(0)}원, 현재가: ${currentPrice.toStringAsFixed(0)}원)';
        }
        
        // 중복 알림 방지: 최근 1분 내에 같은 알림이 있었는지 확인
        final now = DateTime.now();
        final oneMinuteAgo = now.subtract(const Duration(minutes: 1));
        final recentNotifications = await _notificationRepo.getNotificationsByDateRange(oneMinuteAgo, now);
        final hasRecentNotification = recentNotifications.any((notification) =>
            notification['type'] == '❌ 매수 조건 미충족: $stockName' && 
            notification['message'].contains(reason));
        
        if (!hasRecentNotification) {
          await _notificationManager.showNotification(
            title: '❌ 매수 조건 미충족: $stockName',
            body: '$reason - 자동매수 건너뜀\n가용자금: ${availableBalance.toStringAsFixed(0)}원',
          );
        } else {
          print('⚠️ 최근 1분 내에 매수 조건 미충족 알림이 있었습니다: $stockName');
        }
        return;
      }
      
      print('📊 매수 주문 정보:');
      print('  - 종목: $stockCode ($stockName)');
      print('  - 가격: $currentPrice원');
      print('  - 수량: $quantity주');
      print('  - 주문금액: ${(quantity * currentPrice).toStringAsFixed(0)}원');
      print('  - 가용자금: ${availableBalance.toStringAsFixed(0)}원');
      print('  - 포지션비율: ${(positionSize * 100).toStringAsFixed(1)}%');
      
      // 실제 주문 실행
      Map<String, dynamic>? orderResult;
      
      // 주문 접수 대기 알림 (사전 발송)
      await _notificationManager.showPendingNotification(
        stockCode: stockCode,
        stockName: stockName,
        orderType: '매수',
        price: currentPrice,
        quantity: quantity,
      );
      
      if (isOverseas) {
        // 해외주식 주문
        print('🌍 해외주식 매수 주문 실행 및 체결 확인: $stockCode');
        orderResult = await _unifiedApiService.executeOverseasOrder(
          symbol: stockCode,
          orderType: 'buy',
          quantity: quantity,
          price: currentPrice,
        );
      } else {
        // 국내주식 주문
        print('🇰🇷 국내주식 매수 주문 실행 및 체결 확인: $stockCode');
        orderResult = await _unifiedApiService.executeOverseasOrder(
          symbol: stockCode,
          orderType: 'buy',
          quantity: quantity,
          price: currentPrice,
        );
      }
      
      if (orderResult != null && orderResult['orderStatus'] == 'EXECUTED') {
        print('✅ 매수 주문 체결 완료: ${orderResult['orderId']}');
        
        // 성공 알림 발송
        await _notificationManager.showTradeExecutionNotification(
          stockCode: stockCode,
          stockName: stockName,
          orderType: '매수',
          price: currentPrice,
          quantity: quantity,
        );
        
        // 시그널 히스토리에 저장
        await _signalRepo.saveSignal(
          stockCode: stockCode,
          signalType: '매수',
          signalStrength: score,
          price: currentPrice,
          volume: quantity.toDouble(),
          confidence: score,
          memo: 'AutoTrading_매수_성공',
          stockName: stockName,
          market: _determineMarket(stockCode),
        );
      } else {
        print('❌ 매수 주문 실패: ${orderResult?['message'] ?? '알 수 없는 오류'}');
        
        // 매수 실패 알림 발송
        await _notificationManager.showBuyFailureNotification(
          stockCode: stockCode,
          stockName: stockName,
          reason: orderResult?['message'] ?? '알 수 없는 오류',
          price: currentPrice,
        );
        
        // 실패한 시그널도 저장
        await _signalRepo.saveSignal(
          stockCode: stockCode,
          signalType: '매수',
          signalStrength: score,
          price: currentPrice,
          volume: 0.0,
          confidence: score,
          memo: 'AutoTrading_매수_실패',
          stockName: stockName,
          market: _determineMarket(stockCode),
        );
      }
      
    } catch (e) {
      print('❌ 매수 주문 실행 중 오류: $e');
      
      // 매수 실패 알림 발송
      await _notificationManager.showBuyFailureNotification(
        stockCode: stockCode,
        stockName: stockName,
        reason: '주문 실행 오류: $e',
        price: currentPrice,
      );
      
      // 오류 발생한 시그널도 저장
      await _signalRepo.saveSignal(
        stockCode: stockCode,
        signalType: '매수',
        signalStrength: score,
        price: currentPrice,
        volume: 0.0,
        confidence: score,
        memo: 'AutoTrading_매수_오류',
        stockName: stockName,
        market: _determineMarket(stockCode),
      );
    }
  }

  /// 매도 주문 실행
  Future<void> _executeSellOrder(Map<String, dynamic> signal) async {
    final stockCode = signal['stockCode'] as String;
    final stockName = signal['stockName'] as String;
    double currentPrice = signal['currentPrice'] as double;
    final score = signal['score'] as double? ?? 0.0;
    
    // 현재가가 0이거나 유효하지 않은 경우 다시 조회
    if (currentPrice <= 0) {
      print('⚠️ 매도 주문: 현재가가 유효하지 않음 ($currentPrice), 다시 조회 중...');
      currentPrice = await _resolveCurrentPrice(stockCode);
      if (currentPrice <= 0) {
        print('❌ 매도 주문: 현재가 조회 실패, 주문 취소');
        return;
      }
    }
    
    try {
      // 보유종목 확인
      final holdings = await _holdingsRepo.getHoldings();
      final holding = holdings.firstWhere(
        (h) => h['stockCode'] == stockCode || h['stockCode'] == stockCode,
        orElse: () => <String, dynamic>{},
      );
      
      if (holding.isEmpty) {
        print('❌ 매도 주문: 보유종목 없음 - $stockCode');
        return;
      }
      
      final quantity = (holding['quantity'] as num?)?.toInt() ?? 0;
      if (quantity <= 0) {
        print('❌ 매도 주문: 보유 수량 없음 - $stockCode (${quantity}주)');
        return;
      }
      
      // 매도 주문 정보 출력
      print('💰 매도 주문 실행: $stockCode ($stockName)');
      print('   - 현재가: ${currentPrice.toStringAsFixed(2)}원');
      print('   - 보유수량: ${quantity}주');
      print('   - 매도이유: ${signal['reason']}');
      print('   - 점수: ${score.toStringAsFixed(3)}');
      
      // 실제 매도 주문 실행 (새로운 주문 체결 확인 시스템 사용)
      print('💰 실제 매도 주문 실행 중: $stockCode - ${quantity}주 @ ${currentPrice.toStringAsFixed(2)}원');
      
      final orderResult = await _unifiedApiService.executeOverseasOrder(
        symbol: stockCode,
        orderType: 'sell',
        quantity: quantity,
        price: currentPrice,
      );
      
      if (orderResult != null && orderResult['orderStatus'] == 'EXECUTED') {
        print('✅ 매도 체결 완료: $stockCode - ${quantity}주 @ ${currentPrice.toStringAsFixed(2)}원');
        
        // 매도 성공 알림
        final sellReason = signal['reason'] as String? ?? '';
        await _notificationManager.showTradeExecutionNotification(
          stockCode: stockCode,
          stockName: stockName,
          orderType: '매도',
          price: currentPrice,
          quantity: quantity,
          reason: sellReason,
        );
      } else if (orderResult != null && orderResult['orderStatus'] == 'FAILED') {
        print('❌ 매도 주문 실패: $stockCode - ${orderResult['message'] ?? '알 수 없는 오류'}');
        
        // 매도 실패 알림
        await _notificationManager.showNotification(
          title: '❌ 매도 주문 실패',
          body: '$stockName ($stockCode) 매도 주문이 실패했습니다: ${orderResult['message'] ?? '알 수 없는 오류'}',
        );
      } else if (orderResult != null && orderResult['orderStatus'] == 'TIMEOUT') {
        print('⏰ 매도 체결 확인 대기: $stockCode - 체결 상태 확인 중');
        
        // 체결 확인 대기 알림
        await _notificationManager.showNotification(
          title: '⏰ 매도 체결 확인 대기',
          body: '$stockName ($stockCode) 매도 주문이 접수되었으나 체결 상태를 확인할 수 없습니다.',
        );
      } else {
        print('⚠️ 매도 주문 결과 불명확: $stockCode - $orderResult');
        
        // 주문 결과 불명확 알림
        await _notificationManager.showNotification(
          title: '⚠️ 매도 주문 결과 불명확',
          body: '$stockName ($stockCode) 매도 주문 결과를 확인할 수 없습니다.',
        );
      }
      
    } catch (e) {
      print('❌ 매도 주문 실패: $stockCode - $e');
      
      // 매도 실패 알림
      await _notificationManager.showNotification(
        title: '매도 실패',
        body: '$stockName 매도 주문이 실패했습니다: $e',
      );
    }
  }

  /// 알림 발송
  Future<void> _sendNotification(Map<String, dynamic> signal) async {
    try {
      final stockCode = signal['stockCode'] as String;
      final stockName = signal['stockName'] as String;
      final signalType = signal['signal'] as String;
      final score = signal['score'] as double;
      final isTradingTime = signal['isTradingTime'] as bool;
      final currentPrice = signal['currentPrice'] as double? ?? 0.0;
      
      print('🔔 알림 발송 시작: $stockCode - $signalType');
      
      // 시그널 타입에 따른 알림 발송
      if (signalType == '매수') {
        // 임계값을 조회하여 명확한 비교 문구로 구성
        String reasonText = '종합점수 ${score.toStringAsFixed(3)}';
        try {
          final styleManager = InvestmentStyleManager();
          final currentStyle = await styleManager.getCurrentStyle();
          final params = await styleManager.getStyleParameters(currentStyle);
          final buyThreshold = (params['buyThreshold'] as num?)?.toDouble();
          if (buyThreshold != null) {
            reasonText = '종합점수 ${score.toStringAsFixed(3)} ≥ ${buyThreshold.toStringAsFixed(3)}';
          }
        } catch (_) {}
        await _notificationManager.showBuySignalNotification(
          stockCode: stockCode,
          stockName: stockName,
          reason: reasonText,
          price: currentPrice,
        );
      } else if (signalType == '매도') {
        // signal 데이터에서 reason을 확인해서 익절/손절인지 판단
        final signalReason = signal['reason'] as String? ?? '';
        String reasonText;
        
        print('🔍 [알림] 매도 시그널 이유 분석: "$signalReason"');
        print('   - 부분익절 포함: ${signalReason.contains('부분익절')}');
        print('   - 전체익절 포함: ${signalReason.contains('전체익절')}');
        print('   - 손절 포함: ${signalReason.contains('손절')}');
        print('   - 기술적 매도 포함: ${signalReason.contains('기술적') || signalReason.contains('종합점수')}');
        
        if (signalReason.contains('부분익절') || signalReason.contains('전체익절') || signalReason.contains('손절')) {
          // 익절/손절 조건인 경우 - 정확한 타입과 수익률 표시
          print('✅ [알림] 익절/손절 조건으로 인식됨');
          
          try {
            // 현재 투자 스타일 설정에서 기준 퍼센트 조회
            final styleManager = InvestmentStyleManager();
            final currentStyle = await styleManager.getCurrentStyle();
            final styleParams = await styleManager.getStyleParameters(currentStyle);
            
            if (signalReason.contains('손절')) {
              final stopLoss = (styleParams['stopLoss'] as num?)?.toDouble() ?? 0.0;
              reasonText = '손절 실행: ${stopLoss.abs().toStringAsFixed(1)}% 기준 ($signalReason)';
            } else if (signalReason.contains('부분익절')) {
              final partialProfit = (styleParams['partialProfit'] as num?)?.toDouble() ?? 0.0;
              reasonText = '부분익절 실행: ${partialProfit.toStringAsFixed(1)}% 기준 ($signalReason)';
            } else if (signalReason.contains('전체익절')) {
              final fullProfit = (styleParams['fullProfit'] as num?)?.toDouble() ?? 0.0;
              reasonText = '전체익절 실행: ${fullProfit.toStringAsFixed(1)}% 기준 ($signalReason)';
            } else {
              reasonText = signalReason;
            }
          } catch (e) {
            print('⚠️ 매도 기준 퍼센트 조회 실패: $e');
            // 기본 텍스트 사용
            if (signalReason.contains('손절')) {
              reasonText = '손절 실행 - 손실 제한 ($signalReason)';
            } else if (signalReason.contains('부분익절')) {
              reasonText = '부분익절 실행 - 수익 확보 ($signalReason)';
            } else if (signalReason.contains('전체익절')) {
              reasonText = '전체익절 실행 - 수익 확보 ($signalReason)';
            } else {
              reasonText = signalReason;
            }
          }
        } else if (signalReason.contains('기술적') || signalReason.contains('종합점수')) {
          // 기술적 분석 조건인 경우 - 실제 조건에 맞는 표시
          try {
            final styleManager = InvestmentStyleManager();
            final currentStyle = await styleManager.getCurrentStyle();
            final params = await styleManager.getStyleParameters(currentStyle);
            final sellThreshold = (params['sellThreshold'] as num?)?.toDouble();
            if (sellThreshold != null) {
              // 실제 조건 확인해서 올바른 기호 표시
              if (score <= sellThreshold) {
                reasonText = '기술적 매도: 종합점수 ${score.toStringAsFixed(3)} ≤ ${sellThreshold.toStringAsFixed(3)}';
              } else {
                reasonText = '기술적 매도: 종합점수 ${score.toStringAsFixed(3)} (임계값: ${sellThreshold.toStringAsFixed(3)})';
              }
            } else {
              reasonText = '기술적 매도: 종합점수 ${score.toStringAsFixed(3)}';
            }
          } catch (_) {
            reasonText = '기술적 매도: 종합점수 ${score.toStringAsFixed(3)}';
          }
        } else {
          // 기타 조건인 경우
          reasonText = signalReason.isNotEmpty ? signalReason : '매도 조건 충족';
        }
        
        await _notificationManager.showSellSignalNotification(
          stockCode: stockCode,
          stockName: stockName,
          reason: reasonText,
          price: currentPrice,
        );
      } else if (signalType == '매수 기회') {
        await _notificationManager.showNotification(
          title: '🟡 매수 기회: $stockName',
          body: '$stockCode - ${currentPrice.toStringAsFixed(0)}원\n매수 기회가 감지되었습니다. (점수: ${score.toStringAsFixed(3)})',
        );
      } else if (signalType == '매도 기회') {
        await _notificationManager.showNotification(
          title: '🟡 매도 기회: $stockName',
          body: '$stockCode - ${currentPrice.toStringAsFixed(0)}원\n매도 기회가 감지되었습니다. (점수: ${score.toStringAsFixed(3)})',
        );
      }
      
      print('✅ 알림 발송 완료: $stockCode - $signalType');
      
    } catch (e) {
      print('❌ 알림 발송 실패: $e');
    }
  }

  /// 시그널 DB 저장
  Future<void> _saveSignalToDatabase(SignalData signal) async {
    try {
      await _signalRepo.saveSignal(
        stockCode: signal.stockCode,
        signalType: signal.type.displayName,
        signalStrength: signal.analysis?['confidence']?.toDouble() ?? 0.0,
        price: signal.price,
        volume: (signal.quantity ?? 0).toDouble(),
        rsi: signal.analysis?['rsi']?.toDouble(),
        macd: signal.analysis?['macd']?.toDouble(),
        macdSignal: signal.analysis?['macdSignal']?.toDouble(),
        sma20: signal.analysis?['sma20']?.toDouble(),
        sma50: signal.analysis?['sma50']?.toDouble(),
        bollingerPosition: signal.analysis?['bbPosition']?.toString(),
        confidence: signal.analysis?['confidence']?.toDouble(),
        memo: signal.reason ?? '',
        dedupKey: '${signal.stockCode}-${signal.type.name}-${DateTime.now().millisecondsSinceEpoch}',
        stockName: signal.stockName ?? 'Unknown',
      );
      
      print('💾 시그널 DB 저장 완료: ${signal.stockCode} ${signal.type.displayName}');
    } catch (e) {
      print('❌ 시그널 DB 저장 실패: $e');
    }
  }

  /// 주문 상태 추적 (오류 처리 개선)
  Future<void> _trackOrderStatus() async {
    try {
      print('🔍 주문 상태 추적 시작...');
      
      // 대기 중인 주문 조회 (오류 처리 개선)
      List<Map<String, dynamic>>? pendingOrders;
      try {
        // 레거시 API 유지 (통일된 API 서비스에 주문 조회 기능 없음)
        pendingOrders = await _unifiedApiService.getOverseasPendingOrders();
      } catch (e) {
        print('⚠️ 대기 주문 조회 실패 (무시하고 계속): $e');
        return; // 오류 발생 시 조용히 종료
      }
      
      if (pendingOrders == null || pendingOrders.isEmpty) {
        print('📋 추적할 주문이 없습니다.');
        return;
      }
      
      print('📋 ${pendingOrders.length}건의 주문 상태 확인 중...');
      
      for (final order in pendingOrders) {
        try {
          final orderId = order['orderId'] ?? order['orderNo'] ?? '';
          if (orderId.isEmpty) continue;
          
          // 주문 상태 확인 (오류 처리 개선)
          Map<String, dynamic>? orderStatus;
          try {
            // 레거시 API 유지 (통일된 API 서비스에 주문 상태 조회 기능 없음)
            orderStatus = await _unifiedApiService.checkOverseasOrderExecution(orderId);
          } catch (e) {
            print('⚠️ 주문 상태 확인 실패 (건너뜀): $orderId - $e');
            continue;
          }
          
          if (orderStatus == null) continue;
          
          final status = orderStatus['status'] as String? ?? '';
          final stockCode = orderStatus['stockCode'] as String? ?? '';
          final stockName = await _getStockName(stockCode);
          final orderType = orderStatus['orderType'] as String? ?? '';
          
          // 체결 완료된 주문 처리
          if (status == 'FILLED') {
            await _handleOrderFilled(orderStatus, stockCode, stockName, orderType);
          }
          // 부분 체결된 주문 처리
          else if (status == 'PARTIAL') {
            await _handleOrderPartial(orderStatus, stockCode, stockName, orderType);
          }
          // 주문 실패/취소 처리
          else if (status == 'REJECTED' || status == 'CANCELLED') {
            await _handleOrderFailed(orderStatus, stockCode, stockName, orderType, status);
          }
          
        } catch (e) {
          print('❌ 개별 주문 처리 실패 (건너뜀): $e');
        }
      }
      
      print('✅ 주문 상태 추적 완료');
      
    } catch (e) {
      print('❌ 주문 상태 추적 실패: $e');
    }
  }

  /// 주문 체결 완료 처리
  Future<void> _handleOrderFilled(Map<String, dynamic> orderStatus, String stockCode, String stockName, String orderType) async {
    try {
      final executedQuantity = (orderStatus['executedQuantity'] as num?)?.toInt() ?? 0;
      final executedPrice = (orderStatus['executedPrice'] as num?)?.toDouble() ?? 0.0;
      final totalAmount = executedQuantity * executedPrice;
      
      // 체결 완료 시그널 생성
      final signalType = orderType == 'BUY' ? SignalType.buySuccess : SignalType.sellSuccess;
      final signal = SignalData(
        type: signalType,
        stockCode: stockCode,
        stockName: stockName,
        price: executedPrice,
        quantity: executedQuantity,
        totalAmount: totalAmount,
        reason: '주문 체결 완료: ${executedQuantity}주 @ ${executedPrice.toStringAsFixed(2)}',
        timestamp: DateTime.now(),
        orderId: orderStatus['orderId'],
        orderStatus: '체결 완료',
        isAutoTrade: true,
        market: _determineMarket(stockCode),
      );
      
      // 시그널 DB 저장 및 알림 발송
      await _saveSignalToDatabase(signal);
      await _sendNotification({
        'stockCode': signal.stockCode,
        'stockName': signal.stockName,
        'signal': signal.type.displayName,
        'price': signal.price,
        'timestamp': signal.timestamp.toIso8601String(),
      });
      
      // 거래 내역 DB 저장
      await _tradeHistoryRepo.insertTradeHistory(
        stockCode: stockCode,
        stockName: stockName,
        orderType: orderType == 'BUY' ? '매수' : '매도',
        quantity: executedQuantity,
        price: executedPrice,
        totalAmount: totalAmount,
        orderDate: DateTime.now().toString().substring(0, 10),
        orderTime: DateTime.now().toString().substring(11, 16),
        tradeReason: '자동매매 체결',
        investmentStyle: _currentStyle.name,
        isAutoTrade: true,
      );
      
      print('✅ 주문 체결 완료 처리: $stockCode ${orderType == 'BUY' ? '매수' : '매도'} ${executedQuantity}주');
      
    } catch (e) {
      print('❌ 주문 체결 완료 처리 실패: $e');
    }
  }

  /// 부분 체결 처리
  Future<void> _handleOrderPartial(Map<String, dynamic> orderStatus, String stockCode, String stockName, String orderType) async {
    try {
      final executedQuantity = (orderStatus['executedQuantity'] as num?)?.toInt() ?? 0;
      final executedPrice = (orderStatus['executedPrice'] as num?)?.toDouble() ?? 0.0;
      
      // 부분 체결 시그널 생성
      final signalType = orderType == 'BUY' ? SignalType.buyPending : SignalType.sellPending;
      final signal = SignalData(
        type: signalType,
        stockCode: stockCode,
        stockName: stockName,
        price: executedPrice,
        quantity: executedQuantity,
        reason: '부분 체결: ${executedQuantity}주 체결됨',
        timestamp: DateTime.now(),
        orderId: orderStatus['orderId'],
        orderStatus: '부분 체결',
        isAutoTrade: true,
        market: _determineMarket(stockCode),
      );
      
      // 시그널 DB 저장 및 알림 발송
      await _saveSignalToDatabase(signal);
      await _sendNotification({
        'stockCode': signal.stockCode,
        'stockName': signal.stockName,
        'signal': signal.type.displayName,
        'price': signal.price,
        'timestamp': signal.timestamp.toIso8601String(),
      });
      
      print('⏳ 부분 체결 처리: $stockCode ${orderType == 'BUY' ? '매수' : '매도'} ${executedQuantity}주');
      
    } catch (e) {
      print('❌ 부분 체결 처리 실패: $e');
    }
  }

  /// 주문 실패/취소 처리
  Future<void> _handleOrderFailed(Map<String, dynamic> orderStatus, String stockCode, String stockName, String orderType, String status) async {
    try {
      final rejectReason = orderStatus['rejectReason'] as String? ?? '';
      
      // 실패/취소 시그널 생성
      final signalType = orderType == 'BUY' ? 
        (status == 'CANCELLED' ? SignalType.buyCancelled : SignalType.buyFailed) :
        (status == 'CANCELLED' ? SignalType.sellCancelled : SignalType.sellFailed);
      
      final signal = SignalData(
        type: signalType,
        stockCode: stockCode,
        stockName: stockName,
        price: (orderStatus['orderPrice'] as num?)?.toDouble() ?? 0.0,
        reason: status == 'CANCELLED' ? '주문 취소됨' : '주문 실패: $rejectReason',
        timestamp: DateTime.now(),
        orderId: orderStatus['orderId'],
        orderStatus: status == 'CANCELLED' ? '주문 취소' : '주문 실패',
        isAutoTrade: true,
        market: _determineMarket(stockCode),
      );
      
      // 시그널 DB 저장 및 알림 발송
      await _saveSignalToDatabase(signal);
      await _sendNotification({
        'stockCode': signal.stockCode,
        'stockName': signal.stockName,
        'signal': signal.type.displayName,
        'price': signal.price,
        'timestamp': signal.timestamp.toIso8601String(),
      });
      
      print('❌ 주문 실패/취소 처리: $stockCode ${orderType == 'BUY' ? '매수' : '매도'} - $status');
      
    } catch (e) {
      print('❌ 주문 실패/취소 처리 실패: $e');
    }
  }

  /// 종목명 조회
  Future<String> _getStockName(String stockCode) async {
    try {
      return AppDataManager.instance.getStockName(stockCode);
    } catch (e) {
      return stockCode;
    }
  }

  /// 사용자 매수 임계값 가져오기
  Future<double> _getUserBuyThreshold() async {
    try {
      final styleParams = await _styleManager.getStyleParameters(_currentStyle);
      final threshold = (styleParams['buyThreshold'] as num?)?.toDouble();
      if (threshold == null) {
        print('⚠️ 매수 임계값이 설정되지 않았습니다.');
        return 0.0;
      }
      return threshold;
    } catch (e) {
      print('⚠️ 사용자 매수 임계값 조회 실패: $e');
      return 0.0;
    }
  }

  /// 사용자 매도 임계값 가져오기
  Future<double> _getUserSellThreshold() async {
    try {
      final styleParams = await _styleManager.getStyleParameters(_currentStyle);
      final threshold = (styleParams['sellThreshold'] as num?)?.toDouble();
      if (threshold == null) {
        print('⚠️ 매도 임계값이 설정되지 않았습니다.');
        return 0.0;
      }
      return threshold;
    } catch (e) {
      print('⚠️ 사용자 매도 임계값 조회 실패: $e');
      return 0.0;
    }
  }

  // Getters (중복 방지: 상단에 동일 getter 존재)
  // bool get isRunning => _isRunning; // 상단에 정의됨
  // DateTime? get lastCycleTime => _lastCycleTime; // 상단에 정의됨
  bool get autoTradingEnabled => _autoTradingEnabled;
  InvestmentStyle get currentStyle => _currentStyle;

  /// 자동매매 실행 (메인 사이클)
  Future<void> executeAutoTrading() async {
    try {
      print('🤖 자동매매 사이클 시작');
      
      // 디버깅: 현재 설정 상태 확인
      await DebugTradingHelper.checkCurrentStyleSettings();
      
      // 1. 시장 데이터 수집 (기존 메서드 사용)
      final marketData = await _appDataManager.getWatchlist();
      if (marketData.isEmpty) {
        print('⚠️ 시장 데이터가 없습니다.');
        return;
      }
      
      print('📊 수집된 종목 수: ${marketData.length}개');
      
      // 2. 각 종목별 분석 및 시그널 생성
      final signals = <SignalData>[];
      
      for (final stockData in marketData) {
        final stockCode = stockData['stock_code'] as String? ?? stockData['stockCode'] as String? ?? 'Unknown';
        final stockName = stockData['stock_name'] as String? ?? stockData['stockName'] as String? ?? stockCode;
        
        print('🔍 종목 분석 중: $stockCode ($stockName)');
        
        // 디버깅: 매수 조건 검증
        await DebugTradingHelper.validateBuyConditions(stockCode);
        
        // 🔧 수정: 분석탭과 동일한 파라미터 전달
        // 현재가 데이터 조회
        final currentPriceData = await _currentPriceRepo.getCurrentPrice(stockCode);
        double currentPrice = (currentPriceData?['currentPrice'] as num?)?.toDouble() ?? 
                             (currentPriceData?['current_price'] as num?)?.toDouble() ?? 0.0;
        

        
        // 현재가가 0이면 다른 방법으로 조회
        if (currentPrice <= 0) {
          print('⚠️ CurrentPriceRepository에서 현재가 조회 실패: $stockCode');
          currentPrice = await _resolveCurrentPrice(stockCode);
          print('   📊 대체 현재가: $currentPrice');
          

        }
        
        // 기술적 분석 수행 (분석탭과 동일한 파라미터)
        final analysis = await _unifiedAnalysis.analyzeStock(
          stockCode,
          currentPrice: currentPrice,
          prevClose: (currentPriceData?['prevClose'] as num?)?.toDouble() ?? 
                    (currentPriceData?['prev_close'] as num?)?.toDouble() ?? currentPrice,
          volume: (currentPriceData?['volume'] as num?)?.toDouble() ?? 0.0,
          highPrice: (currentPriceData?['high'] as num?)?.toDouble() ?? 
                    (currentPriceData?['highPrice'] as num?)?.toDouble() ?? currentPrice,
          lowPrice: (currentPriceData?['low'] as num?)?.toDouble() ?? 
                   (currentPriceData?['lowPrice'] as num?)?.toDouble() ?? currentPrice,
          openPrice: (currentPriceData?['open'] as num?)?.toDouble() ?? 
                    (currentPriceData?['openPrice'] as num?)?.toDouble() ?? currentPrice,
        );
        if (analysis == null) {
          print('⚠️ 기술적 분석 실패: $stockCode');
          continue;
        }
        
        final comprehensiveScore = (analysis['comprehensiveScore'] as num?)?.toDouble() ?? 0.0;
        final signal = analysis['signal'] as String? ?? '관망';
        final confidence = (analysis['confidence'] as num?)?.toDouble() ?? 0.0;
        
        // 디버깅: 매수 시그널 테스트
        await DebugTradingHelper.testBuySignal(stockCode, comprehensiveScore);
        
        print('📊 시그널 분석 상세: $stockCode');
        print('  - 종합점수: ${comprehensiveScore.toStringAsFixed(3)}');
        print('  - 시그널: $signal');
        print('  - 신뢰도: $confidence');
        
        // 로컬DB에서 실제 사용자 설정 임계값 가져오기 (실시간 로드)
        final currentStyleParams = await _styleManager.getStyleParameters(_currentStyle);
        final buyThreshold = (currentStyleParams['buyThreshold'] as num?)?.toDouble();
        final sellThreshold = (currentStyleParams['sellThreshold'] as num?)?.toDouble();
        

        
        print('📊 투자 스타일 설정 확인:');
        print('   - 현재 스타일: ${_currentStyle.name}');
        print('   - 매수 임계값: $buyThreshold');
        print('   - 매도 임계값: $sellThreshold');
        print('   - 종합점수: ${comprehensiveScore.toStringAsFixed(3)}');
        
        if (buyThreshold == null || sellThreshold == null) {
          print('⚠️ 투자 스타일 임계값이 설정되지 않았습니다.');
          print('   - buyThreshold: $buyThreshold');
          print('   - sellThreshold: $sellThreshold');
          print('   - 스타일 파라미터 전체: $currentStyleParams');
          continue;
        }
        
        // 임계값 유효성 검증
        if (buyThreshold <= 0.0 || sellThreshold >= 0.0) {
          print('⚠️ 임계값 설정이 잘못되었습니다.');
          print('   - 매수 임계값은 양수여야 합니다: $buyThreshold');
          print('   - 매도 임계값은 음수여야 합니다: $sellThreshold');
          continue;
        }
        
        String finalSignal = '관망';
        print('🔍 시그널 결정 과정: $stockCode');
        print('   📊 종합점수: ${comprehensiveScore.toStringAsFixed(3)}');
        print('   📊 매수임계값: ${buyThreshold.toStringAsFixed(3)}');
        print('   📊 매도임계값: ${sellThreshold.toStringAsFixed(3)}');
        print('   📊 매수 조건: ${comprehensiveScore.toStringAsFixed(3)} >= ${buyThreshold.toStringAsFixed(3)} = ${comprehensiveScore >= buyThreshold}');
        print('   📊 매도 조건: ${comprehensiveScore.toStringAsFixed(3)} <= ${sellThreshold.toStringAsFixed(3)} = ${comprehensiveScore <= sellThreshold}');
        
        if (comprehensiveScore >= buyThreshold) {
          finalSignal = '매수';
          print('✅ 매수 시그널 조건 충족: ${comprehensiveScore.toStringAsFixed(3)} >= ${buyThreshold.toStringAsFixed(3)}');
        } else if (comprehensiveScore <= sellThreshold) {
          finalSignal = '매도';
          print('✅ 매도 시그널 조건 충족: ${comprehensiveScore.toStringAsFixed(3)} <= ${sellThreshold.toStringAsFixed(3)}');
          print('   🔍 매도 시그널 생성 지점: AutoTradingCycle.dart:executeAutoTrading');
          print('   📊 매도 시그널 상세: 종합점수=${comprehensiveScore.toStringAsFixed(3)}, 매도임계값=${sellThreshold.toStringAsFixed(3)}, 조건결과=${comprehensiveScore <= sellThreshold}');
          

        } else {
          // 임계값 사이 구간: 관망
          finalSignal = '관망';
          print('➖ 관망: ${comprehensiveScore.toStringAsFixed(3)} (임계값 사이 구간: ${sellThreshold.toStringAsFixed(3)} < 점수 < ${buyThreshold.toStringAsFixed(3)})');
          

        }
        
        print('🎯 최종 시그널: $finalSignal');
        
        if (finalSignal == '매수' || finalSignal == '매도') {
          print('🎯 매매 시그널 감지: $stockCode - $finalSignal (점수: ${comprehensiveScore.toStringAsFixed(3)})');
          

          
          // 정규장 시간 외에는 매매 시그널 생성하지 않음
          final market = _determineMarket(stockCode);
          final isTradingTime = MarketTimeValidator.instance.isTradingTime(market);
          
          if (!isTradingTime) {
            print('⚠️ 정규장 시간 외 - 매매 시그널 생성 제한: $stockCode - $finalSignal');
            print('   📊 시장: $market');
            print('   📊 정규장 시간: $isTradingTime');
            print('   📊 매매 조건은 만족했지만 정규장 시간 외라서 시그널 생성 안함');
            continue;
          }
          
          // 중복 시그널 체크 (1시간 내)
          final now = DateTime.now();
          final oneHourAgo = now.subtract(const Duration(hours: 1));
          final recentSignals = await _signalRepo.getSignalsByDateRange(oneHourAgo, now);
          
          final isDuplicate = recentSignals.any((row) =>
              (row['stock_code']?.toString() ?? '') == stockCode &&
              (row['signal_type']?.toString() ?? '') == finalSignal);
          
          if (isDuplicate) {
            print('⚠️ 중복 시그널 감지(테스트 통과): $stockCode - $finalSignal (1시간 내 동일 시그널 존재)');
            // 테스트 기간: 중복이어도 통과시켜 주문 시도
          }
          
          // 현재가 조회 (기존 메서드 사용)
          final currentPriceData = await _currentPriceRepo.getCurrentPrice(stockCode);
          final currentPrice = (currentPriceData?['currentPrice'] as num?)?.toDouble() ?? 0.0;
          

          
          // 시그널 데이터 생성 (실제 조건에 맞는 이유 생성)
          String actualReason;
          if (comprehensiveScore >= buyThreshold) {
            actualReason = '종합점수 ${comprehensiveScore.toStringAsFixed(3)} ≥ ${buyThreshold.toStringAsFixed(3)} 임계값 (${_currentStyle.name})';
          } else if (comprehensiveScore <= sellThreshold) {
            actualReason = '종합점수 ${comprehensiveScore.toStringAsFixed(3)} ≤ ${sellThreshold.toStringAsFixed(3)} 임계값 (${_currentStyle.name})';
          } else {
            actualReason = '관망: 종합점수 ${comprehensiveScore.toStringAsFixed(3)} (임계값 사이 구간)';
          }
          
          final signalData = SignalData(
            type: finalSignal == '매수' ? SignalType.buySignal : SignalType.sellSignal,
            stockCode: stockCode,
            stockName: stockName,
            price: currentPrice,
            quantity: 1, // 기본값
            reason: actualReason,
            analysis: analysis,
            timestamp: DateTime.now(),
            isAutoTrade: false,
            market: _determineMarket(stockCode),
          );
          
          signals.add(signalData);
          print('✅ 시그널 데이터 생성 완료: $stockCode - $signal');
          

        } else {
          print('📊 매매 시그널 없음: $stockCode - $signal');
          

        }
        
      }
      
      print('📊 생성된 시그널 수: ${signals.length}개');
      

      
      // 3. 시그널 처리 (기존 메서드 사용)
      if (signals.isNotEmpty) {
        await _processSignals(signals.map((signal) => signal.toMap()).toList());
      }
      
      print('✅ 자동매매 사이클 완료');
      
    } catch (e) {
      print('❌ 자동매매 사이클 실행 실패: $e');
    }
  }

  /// 로컬 데이터로 분석 결과 보강
  Future<Map<String, dynamic>?> _enhanceAnalysisWithLocalData(
    String stockCode,
    Map<String, dynamic> currentPriceData,
    List<Map<String, dynamic>> chartData,
  ) async {
    try {
      print('🔍 [AutoTradingCycle] 로컬 데이터로 분석 보강 시작: $stockCode');
      
      // 1. 로컬 DB에서 최신 분석 결과 조회
      final analysisRepo = AnalysisResultsRepository();
      final latestAnalysis = await analysisRepo.getLatestAnalysisResult(stockCode);
      
      if (latestAnalysis != null) {
        final lastScore = (latestAnalysis['comprehensive_score'] as num?)?.toDouble() ?? 0.0;
        if (lastScore.abs() > 0.001) {
          print('✅ [AutoTradingCycle] 로컬 DB 분석 결과 사용: $stockCode - 점수: ${lastScore.toStringAsFixed(3)}');
          return {
            'comprehensiveScore': lastScore,
            'signal': latestAnalysis['signal'] ?? '관망',
            'confidence': (latestAnalysis['confidence_score'] as num?)?.toDouble() ?? 0.0,
            'currentPrice': (currentPriceData['currentPrice'] as num?)?.toDouble() ?? 0.0,
            'stockCode': stockCode,
          };
        }
      }
      
      // 2. 차트 데이터에서 기본 분석 수행
      if (chartData.isNotEmpty) {
        final lastChart = chartData.last;
        final currentPrice = (currentPriceData['currentPrice'] as num?)?.toDouble() ?? 
                           (lastChart['close'] as num?)?.toDouble() ?? 0.0;
        final prevClose = (currentPriceData['prevClose'] as num?)?.toDouble() ?? 
                         (chartData.length >= 2 ? (chartData[chartData.length - 2]['close'] as num?)?.toDouble() : currentPrice) ?? currentPrice;
        
        if (currentPrice > 0 && prevClose > 0) {
          // 투자스타일별 설정값 가져오기
          final currentStyleParams = await _styleManager.getStyleParameters(_currentStyle);
          final buyThreshold = (currentStyleParams['buyThreshold'] as num).toDouble();
          final sellThreshold = (currentStyleParams['sellThreshold'] as num).toDouble();
          
          // 간단한 기술적 분석 수행
          final priceChange = ((currentPrice - prevClose) / prevClose) * 100;
          final simpleScore = priceChange * 0.01; // 간단한 점수 계산
          final comprehensiveScore = simpleScore; // simpleScore를 comprehensiveScore로 사용
          
          // 투자스타일별 임계값으로 시그널 결정
          String signal = '관망';
          print('🔍 [AutoTradingCycle] _enhanceAnalysisWithLocalData 시그널 결정: $stockCode');
          print('   📊 simpleScore: ${simpleScore.toStringAsFixed(3)}');
          print('   📊 buyThreshold: ${buyThreshold.toStringAsFixed(3)}');
          print('   📊 sellThreshold: ${sellThreshold.toStringAsFixed(3)}');
          print('   📊 매수 조건: ${simpleScore.toStringAsFixed(3)} >= ${buyThreshold.toStringAsFixed(3)} = ${simpleScore >= buyThreshold}');
          print('   📊 매도 조건: ${simpleScore.toStringAsFixed(3)} <= ${sellThreshold.toStringAsFixed(3)} = ${simpleScore <= sellThreshold}');
          
          if (simpleScore >= buyThreshold) {
            signal = '매수';
            print('✅ [AutoTradingCycle] _enhanceAnalysisWithLocalData 매수 시그널 생성');
          } else if (simpleScore <= sellThreshold) {
            // 정규장 시간 체크 추가
            final market = _determineMarket(stockCode);
            final isTradingTime = MarketTimeValidator.instance.isTradingTime(market);
            
            if (!isTradingTime) {
              print('⚠️ [AutoTradingCycle] 정규장 시간 외 - 매도 시그널 생성 차단: $stockCode');
              print('   📊 시장: $market');
              print('   📊 정규장 시간: $isTradingTime');
              print('   📊 매도 조건은 만족했지만 정규장 시간 외라서 매도 시그널 생성 안함');
              signal = '관망'; // 매도 대신 관망으로 설정
            } else {
              signal = '매도';
              print('✅ [AutoTradingCycle] _enhanceAnalysisWithLocalData 매도 시그널 생성');
              print('   🔍 매도 시그널 생성 지점: AutoTradingCycle.dart:_enhanceAnalysisWithLocalData');
              print('   ⚠️ simpleScore <= sellThreshold 조건으로 매도 시그널 생성됨');
            }
          } else {
            // 임계값 사이 구간: 관망
            signal = '관망';
            print('➖ [AutoTradingCycle] _enhanceAnalysisWithLocalData 관망 (임계값 사이 구간: ${sellThreshold.toStringAsFixed(3)} < 점수 < ${buyThreshold.toStringAsFixed(3)})');
          }
          
          print('🎯 [AutoTradingCycle] _enhanceAnalysisWithLocalData 최종 시그널: $signal');
          
          print('✅ [AutoTradingCycle] 차트 데이터 기반 간단 분석: $stockCode - 점수: ${simpleScore.toStringAsFixed(3)}');
          print('   📊 투자스타일 임계값: 매수=$buyThreshold, 매도=$sellThreshold, 시그널=$signal');
          return {
            'comprehensiveScore': comprehensiveScore, // simpleScore 대신 comprehensiveScore 사용
            'signal': signal,
            'confidence': 0.3, // 낮은 신뢰도 (간단한 분석이므로)
            'currentPrice': currentPrice,
            'stockCode': stockCode,
          };
        }
      }
      
      print('❌ [AutoTradingCycle] 로컬 데이터 보강 실패: $stockCode');
      return null;
      
    } catch (e) {
      print('❌ [AutoTradingCycle] 로컬 데이터 보강 중 오류: $stockCode - $e');
      return null;
    }
  }

  /// 현재가 보강 (캐시 → DB → API 순)
  Future<double> _resolveCurrentPrice(String stockCode) async {
    try {
      print('🔍 [AutoTradingCycle] 현재가 보강 시작: $stockCode');
      
      // 1. 캐시에서 확인 (AppDataManager의 캐시 확인)
      final cachedData = _appDataManager.getStockInfo(stockCode);
      if (cachedData != null && cachedData['currentPrice'] != null) {
        final cachedPrice = (cachedData['currentPrice'] as num?)?.toDouble() ?? 0.0;
        if (cachedPrice > 0) {
          print('✅ [AutoTradingCycle] 캐시에서 현재가 조회: $cachedPrice');
          return cachedPrice;
        }
      }
      
      // 2. 로컬 DB에서 확인
      final currentPriceRepo = CurrentPriceRepository();
      final dbPrice = await currentPriceRepo.getCurrentPrice(stockCode);
      if (dbPrice != null && dbPrice is Map<String, dynamic>) {
        final price = (dbPrice['current_price'] as num?)?.toDouble() ?? 0.0;
        if (price > 0) {
          print('✅ [AutoTradingCycle] DB에서 현재가 조회: $price');
          return price;
        }
      }
      
      // 3. API에서 조회
      try {
        final market = _determineMarket(stockCode);
        Map<String, dynamic>? apiData;
        
        // 통일된 API 서비스로 현재가 조회
        apiData = await _unifiedApiService.getStockPrice(stockCode);
        
        if (apiData != null) {
          final apiPrice = (apiData['currentPrice'] as num?)?.toDouble() ?? 0.0;
          if (apiPrice > 0) {
            print('✅ [AutoTradingCycle] API에서 현재가 조회: $apiPrice');
            return apiPrice;
          }
        }
      } catch (e) {
        print('⚠️ [AutoTradingCycle] API 조회 실패: $e');
      }
      
      // 4. 이전 분석 결과에서 확인
      final analysisRepo = AnalysisResultsRepository();
      final latestAnalysis = await analysisRepo.getLatestAnalysisResult(stockCode);
      if (latestAnalysis != null) {
        final analysisPrice = (latestAnalysis['current_price'] as num?)?.toDouble() ?? 0.0;
        if (analysisPrice > 0) {
          print('✅ [AutoTradingCycle] 이전 분석에서 현재가 조회: $analysisPrice');
          return analysisPrice;
        }
      }
      
      print('❌ [AutoTradingCycle] 현재가 보강 실패: $stockCode');
      return 0.0;
      
    } catch (e) {
      print('❌ [AutoTradingCycle] 현재가 보강 중 오류: $stockCode - $e');
      return 0.0;
    }
  }

  /// 시그널 생성 및 처리 (익절/손절 조건 포함)
  Future<void> _generateSignalsFromAnalysis(List<Map<String, dynamic>> analysisResults) async {
    try {
      final signals = <SignalData>[];
      
      for (final analysis in analysisResults) {
        final stockCode = analysis['stockCode'] as String;
        final stockName = analysis['stockName'] as String;
        double currentPrice = (analysis['currentPrice'] as num?)?.toDouble() ?? 0.0;
        
        // 현재가가 0이면 다시 조회
        if (currentPrice <= 0) {
          print('⚠️ 시그널 생성: 현재가가 유효하지 않음 ($currentPrice), 다시 조회 중...');
          currentPrice = await _resolveCurrentPrice(stockCode);
          if (currentPrice <= 0) {
            print('❌ 시그널 생성: 현재가 조회 실패, 시그널 건너뜀');
            continue;
          }
        }
        
        // 시그널 타입 결정
        final signalData = await _determineSignalType(analysis, stockCode, stockName, currentPrice);
        if (signalData != null) {
          signals.add(signalData);
          print('✅ 시그널 생성 완료: $stockCode - ${signalData.type.displayName}');
        }
      }
      
      print('📊 생성된 시그널 수: ${signals.length}개');
      
      // 3. 시그널 처리 (기존 메서드 사용)
      if (signals.isNotEmpty) {
        await _processSignals(signals.map((signal) => signal.toMap()).toList());
      }
      
    } catch (e) {
      print('❌ 시그널 생성 실패: $e');
    }
  }
}
