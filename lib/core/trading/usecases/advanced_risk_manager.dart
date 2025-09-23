import 'dart:math';
import '../../data/app_data_manager.dart';
import '../../database/repositories/trade_history_repository.dart';
import '../investment_style_manager.dart';
import '../investment_style.dart';
import '../../database/repositories/stock_prices_repository.dart';

/// 고급 리스크 관리 시스템
class AdvancedRiskManager {
  final TradeHistoryRepository _tradeRepo = TradeHistoryRepository();
  final InvestmentStyleManager _styleManager = InvestmentStyleManager();
  
  // 시장 충격 감지 임계값
  static const double _marketCrashThreshold = -0.05; // 5% 하락
  static const double _volatilityThreshold = 0.3; // 30% 변동성
  
  // 포지션 사이징 관련 상수
  static const double _maxPortfolioRisk = 0.02; // 2% 최대 포트폴리오 리스크
  static const double _kellyMultiplier = 0.25; // 켈리 공식 보수적 적용

  /// 일일 손실 한도 실시간 모니터링
  Future<bool> checkDailyLossLimit() async {
    try {
      final styleParams = await _styleManager.getStyleParameters(_styleManager.currentStyle);
      final dailyLossLimit = (styleParams['dailyLossLimit'] as num?)?.toDouble() ?? -10.0;
      
      // 오늘 거래 내역 조회
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      
      final todayTrades = await _tradeRepo.getTradesByDateRange(
        startOfDay.millisecondsSinceEpoch, 
        endOfDay.millisecondsSinceEpoch
      );
      
      // 오늘 총 손익 계산
      double totalPnL = 0.0;
      double totalInvestment = 0.0;
      
      for (final trade in todayTrades) {
        final amount = trade['total_amount'] as double? ?? 0.0;
        final isAutoTrade = trade['is_auto_trade'] as int? ?? 0;
        
        if (isAutoTrade == 1) { // 자동매매 거래만
          if (trade['order_type'] == '매수') {
            totalInvestment += amount;
          } else if (trade['order_type'] == '매도') {
            totalPnL += amount;
          }
        }
      }
      
      // 현재 보유종목 미실현 손익 추가
      final holdings = await AppDataManager.instance.holdingsRepository.getAllHoldings();
      for (final holding in holdings) {
        final profit = holding['profit'] as double? ?? 0.0;
        totalPnL += profit;
      }
      
      // 손실률 계산
      final dailyLossRate = totalInvestment > 0 ? (totalPnL / totalInvestment) * 100 : 0.0;
      
      print('📊 일일 손실 모니터링: ${dailyLossRate.toStringAsFixed(2)}% / ${dailyLossLimit.toStringAsFixed(1)}%');
      
      // 손실 한도 초과 시 (알림 비활성화)
      if (dailyLossRate <= dailyLossLimit) {
        print('🛑 일일 손실 한도 초과: ${dailyLossRate.toStringAsFixed(2)}% <= ${dailyLossLimit.toStringAsFixed(1)}%');
        
        // 알림 비활성화 - 로그만 출력
        print('⚠️ 일일 손실 한도 알림 비활성화됨');
        
        return false;
      }
      
      return true;
      
    } catch (e) {
      print('❌ 일일 손실 한도 체크 실패: $e');
      return true; // 오류 시 거래 허용
    }
  }

  /// 변동성 기반 동적 포지션 사이징
  Future<double> calculateDynamicPositionSize(String stockCode, double currentPrice) async {
    try {
      // 기본 포지션 사이즈 가져오기
      final styleParams = await _styleManager.getStyleParameters(_styleManager.currentStyle);
      final basePositionSize = (styleParams['positionSize'] as num?)?.toDouble() ?? 0.1;
      
      // 최근 20일 가격 데이터로 변동성 계산
      final priceRepo = AppDataManager.instance.realtimePriceService.priceRepo;
      final twentyDaysAgo = DateTime.now().subtract(const Duration(days: 20));
      final priceHistory = await priceRepo.getPricesByDateRange(stockCode, twentyDaysAgo, DateTime.now());
      
      if (priceHistory.length < 10) {
        print('⚠️ $stockCode 가격 데이터 부족, 기본 포지션 사이즈 사용');
        return basePositionSize;
      }
      
      // 일일 수익률 계산
      final dailyReturns = <double>[];
      for (int i = 1; i < priceHistory.length; i++) {
        final prevPrice = priceHistory[i - 1]['price'] as double;
        final currPrice = priceHistory[i]['price'] as double;
        final dailyReturn = (currPrice - prevPrice) / prevPrice;
        dailyReturns.add(dailyReturn);
      }
      
      // 변동성 (표준편차) 계산
      final mean = dailyReturns.reduce((a, b) => a + b) / dailyReturns.length;
      final variance = dailyReturns.map((r) => pow(r - mean, 2)).reduce((a, b) => a + b) / dailyReturns.length;
      final volatility = sqrt(variance);
      
      // 연간 변동성으로 변환
      final annualVolatility = volatility * sqrt(252);
      
      // 켈리 공식 기반 포지션 사이징
      // f = (bp - q) / b
      // 여기서는 간단하게 변동성 역수 개념 적용
      final riskAdjustedSize = min(
        basePositionSize,
        (_maxPortfolioRisk / annualVolatility) * _kellyMultiplier
      );
      
      // 최소/최대 제한
      final finalSize = max(0.01, min(riskAdjustedSize, basePositionSize * 2));
      
      print('📊 동적 포지션 사이징: $stockCode');
      print('   - 기본 사이즈: ${(basePositionSize * 100).toStringAsFixed(1)}%');
      print('   - 연간 변동성: ${(annualVolatility * 100).toStringAsFixed(1)}%');
      print('   - 조정된 사이즈: ${(finalSize * 100).toStringAsFixed(1)}%');
      
      return finalSize;
      
    } catch (e) {
      print('❌ 동적 포지션 사이징 실패: $stockCode - $e');
      final styleParams = await _styleManager.getStyleParameters(_styleManager.currentStyle);
      return (styleParams['positionSize'] as num?)?.toDouble() ?? 0.1;
    }
  }

  /// 시장 충격 감지 및 자동 손절 (비활성화 가능)
  Future<void> detectMarketCrash() async {
    // 시장 충격 감지 기능 비활성화
    print('⚠️ 시장 충격 감지 기능이 비활성화되어 있습니다.');
    return;
    
    // 기존 시장 충격 감지 로직 (주석 처리)
    /*
    try {
      // 대표 지수들의 변동률 체크 (SPY, QQQ, KOSPI200 등)
      final indexCodes = ['SPY', 'QQQ', '069500']; // SPY, QQQ, KODEX 200
      int crashSignals = 0;
      
      for (final indexCode in indexCodes) {
        final changeRate = await _getIntraDayChangeRate(indexCode);
        if (changeRate != null && changeRate <= _marketCrashThreshold) {
          crashSignals++;
          print('🚨 지수 급락 감지: $indexCode ${(changeRate * 100).toStringAsFixed(2)}%');
        }
      }
      
      // 2개 이상 지수가 급락하면 시장 충격으로 판단 (긴급매도 비활성화)
      if (crashSignals >= 2) {
        print('🚨 시장 충격 감지! (긴급매도 비활성화)');
        
        // 긴급매도 비활성화 - 알림만 발송
        print('⚠️ 긴급매도 비활성화됨 - 알림만 발송');
        
        // 긴급 알림
        await AppDataManager.instance.localNotificationManager.showNotification(
          title: '🚨 시장 충격 감지',
          body: '주요 지수 급락이 감지되었습니다.\n긴급매도는 비활성화되어 있습니다.',
        );
        
        // 30분간 신규 매수 금지
        await _setTradingPause(30);
      }
      
    } catch (e) {
      print('❌ 시장 충격 감지 실패: $e');
    }
    */
  }

  /// 장중 변동률 계산
  Future<double?> _getIntraDayChangeRate(String stockCode) async {
    try {
      final priceRepo = AppDataManager.instance.realtimePriceService.priceRepo;
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      
      final todayPrices = await priceRepo.getPricesByDateRange(stockCode, startOfDay, today);
      
      if (todayPrices.length < 2) return null;
      
      final openPrice = todayPrices.first['price'] as double;
      final currentPrice = todayPrices.last['price'] as double;
      
      return (currentPrice - openPrice) / openPrice;
      
    } catch (e) {
      print('❌ 장중 변동률 계산 실패: $stockCode - $e');
      return null;
    }
  }

  /// 긴급 청산 (모든 보유종목 매도) - 비활성화됨
  Future<void> _emergencyLiquidation(String reason) async {
    print('⚠️ 긴급청산 기능이 비활성화되어 있습니다: $reason');
    print('   - 알림만 발송하고 실제 매도는 수행하지 않습니다.');
    
    // 기존 긴급매도 로직은 주석 처리
    /*
    try {
      final holdings = await AppDataManager.instance.holdingsRepository.getAllHoldings();
      
      for (final holding in holdings) {
        final stockCode = holding['stockCode'] as String;
        final stockName = holding['stockName'] as String? ?? stockCode;
        final quantity = holding['quantity'] as int? ?? 0;
        
        if (quantity > 0) {
          // 시장가 매도 주문
          final result = await KisUnifiedApiService().executeOrderWithConfirmation(
            stockCode: stockCode,
            orderType: 'sell',
            quantity: quantity,
            price: 0, // 시장가
            orderReason: '긴급청산_$reason',
            confirmationTimeout: const Duration(minutes: 5),
          );
          
          print('🛑 긴급 매도: $stockCode $quantity주 - ${result['success'] ? '성공' : '실패'}');
          
          // 거래 내역 저장
          await _recordEmergencyTrade(stockCode, stockName, quantity, reason);
        }
      }
      
    } catch (e) {
      print('❌ 긴급 청산 실패: $e');
    }
    */
  }

  /// 긴급 거래 기록
  Future<void> _recordEmergencyTrade(String stockCode, String stockName, int quantity, String reason) async {
    try {
      final now = DateTime.now();
      
      await _tradeRepo.insertTradeHistory(
        stockCode: stockCode,
        stockName: stockName,
        orderType: '매도',
        quantity: quantity,
        price: 0.0, // 시장가
        totalAmount: 0.0, // 체결 후 업데이트
        orderDate: '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}',
        orderTime: '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
        tradeReason: '긴급청산_$reason',
        investmentStyle: _styleManager.currentStyle.name,
        isAutoTrade: true,
      );
      
    } catch (e) {
      print('❌ 긴급 거래 기록 실패: $e');
    }
  }

  /// 거래 일시정지 설정
  Future<void> _setTradingPause(int minutes) async {
    try {
      final pauseUntil = DateTime.now().add(Duration(minutes: minutes));
      
      // SharedPreferences에 일시정지 시간 저장
      final prefs = await AppDataManager.instance.sharedPreferences;
      await prefs.setString('trading_pause_until', pauseUntil.toIso8601String());
      
      print('⏸️ 거래 일시정지: ${minutes}분 (${pauseUntil.toString()})');
      
    } catch (e) {
      print('❌ 거래 일시정지 설정 실패: $e');
    }
  }

  /// 거래 일시정지 상태 확인
  Future<bool> isTradingPaused() async {
    try {
      final prefs = await AppDataManager.instance.sharedPreferences;
      final pauseUntilStr = prefs.getString('trading_pause_until');
      
      if (pauseUntilStr == null) return false;
      
      final pauseUntil = DateTime.parse(pauseUntilStr);
      final now = DateTime.now();
      
      if (now.isBefore(pauseUntil)) {
        final remainingMinutes = pauseUntil.difference(now).inMinutes;
        print('⏸️ 거래 일시정지 중 (남은 시간: ${remainingMinutes}분)');
        return true;
      } else {
        // 일시정지 시간 경과, 설정 제거
        await prefs.remove('trading_pause_until');
        return false;
      }
      
    } catch (e) {
      print('❌ 거래 일시정지 상태 확인 실패: $e');
      return false;
    }
  }

  /// 포트폴리오 VaR (Value at Risk) 계산
  Future<double> calculatePortfolioVaR({double confidenceLevel = 0.95}) async {
    try {
      final holdings = await AppDataManager.instance.holdingsRepository.getAllHoldings();
      if (holdings.isEmpty) return 0.0;
      
      double portfolioValue = 0.0;
      double portfolioVariance = 0.0;
      
      for (final holding in holdings) {
        final stockCode = holding['stockCode'] as String;
        final quantity = holding['quantity'] as int? ?? 0;
        final currentPrice = holding['currentPrice'] as double? ?? 0.0;
        final value = quantity * currentPrice;
        
        portfolioValue += value;
        
        // 각 종목의 변동성 계산 (간단히 20일 변동성 사용)
        final volatility = await _calculateStockVolatility(stockCode);
        portfolioVariance += pow(value * volatility, 2);
      }
      
      final portfolioStdDev = sqrt(portfolioVariance);
      
      // 정규분포 가정하에 VaR 계산 (Z-score 1.65 for 95% confidence)
      final zScore = confidenceLevel == 0.95 ? 1.645 : 2.576; // 95% or 99%
      final varValue = portfolioStdDev * zScore;
      
      print('📊 포트폴리오 VaR (${(confidenceLevel * 100).toInt()}%): ${varValue.toStringAsFixed(0)}원');
      
      return varValue;
      
    } catch (e) {
      print('❌ 포트폴리오 VaR 계산 실패: $e');
      return 0.0;
    }
  }

  /// 개별 종목 변동성 계산
  Future<double> _calculateStockVolatility(String stockCode) async {
    try {
      final priceRepo = AppDataManager.instance.realtimePriceService.priceRepo;
      final twentyDaysAgo = DateTime.now().subtract(const Duration(days: 20));
      final priceHistory = await priceRepo.getPricesByDateRange(stockCode, twentyDaysAgo, DateTime.now());
      
      if (priceHistory.length < 10) return 0.2; // 기본 변동성 20%
      
      final dailyReturns = <double>[];
      for (int i = 1; i < priceHistory.length; i++) {
        final prevPrice = priceHistory[i - 1]['price'] as double;
        final currPrice = priceHistory[i]['price'] as double;
        final dailyReturn = (currPrice - prevPrice) / prevPrice;
        dailyReturns.add(dailyReturn);
      }
      
      final mean = dailyReturns.reduce((a, b) => a + b) / dailyReturns.length;
      final variance = dailyReturns.map((r) => pow(r - mean, 2)).reduce((a, b) => a + b) / dailyReturns.length;
      
      return sqrt(variance) * sqrt(252); // 연간 변동성
      
    } catch (e) {
      print('❌ 개별 종목 변동성 계산 실패: $stockCode - $e');
      return 0.2;
    }
  }

  /// 리스크 상태 종합 체크
  Future<Map<String, dynamic>> checkRiskStatus() async {
    try {
      // 1. 일일 손실 한도 체크
      final dailyLossOk = await checkDailyLossLimit();
      
      // 2. 거래 일시정지 상태 체크
      final isPaused = await isTradingPaused();
      
      // 3. 보유종목 수 체크
      final holdings = await AppDataManager.instance.holdingsRepository.getAllHoldings();
      final currentPositions = holdings.length;
      
      // 4. 최대 보유종목 수 가져오기
      final styleParams = await _styleManager.getStyleParameters(_styleManager.currentStyle);
      final maxPositions = (styleParams['maxStocks'] as num?)?.toInt() ?? 5;
      
      // 5. 일일 손실 계산
      double dailyLoss = 0.0;
      try {
        final today = DateTime.now();
        final startOfDay = DateTime(today.year, today.month, today.day);
        final endOfDay = startOfDay.add(const Duration(days: 1));
        
        final todayTrades = await _tradeRepo.getTradesByDateRange(
          startOfDay.millisecondsSinceEpoch, 
          endOfDay.millisecondsSinceEpoch
        );
        
        for (final trade in todayTrades) {
          final amount = trade['total_amount'] as double? ?? 0.0;
          final isAutoTrade = trade['is_auto_trade'] as int? ?? 0;
          
          if (isAutoTrade == 1) {
            if (trade['order_type'] == '매도') {
              dailyLoss += amount;
            }
          }
        }
        
        // 보유종목 미실현 손익 추가 (음수일 때만 손실로 계산)
        for (final holding in holdings) {
          final profit = holding['profit'] as double? ?? 0.0;
          if (profit < 0) {
            dailyLoss += profit.abs(); // 손실만 절댓값으로 추가
          }
        }
      } catch (e) {
        print('⚠️ 일일 손실 계산 실패: $e');
      }
      
      // 6. 최대 낙폭 계산 (간단한 버전)
      double maxDrawdown = 0.0;
      try {
        final allTrades = await _tradeRepo.getAllTradeHistory();
        if (allTrades.isNotEmpty) {
          double peak = 0.0;
          double current = 0.0;
          
          for (final trade in allTrades) {
            final amount = trade['total_amount'] as double? ?? 0.0;
            if (trade['order_type'] == '매도') {
              current += amount;
            }
            
            if (current > peak) {
              peak = current;
            }
            
            if (peak > 0) {
              final drawdown = (current - peak) / peak * 100;
              if (drawdown < maxDrawdown) {
                maxDrawdown = drawdown;
              }
            }
          }
        }
      } catch (e) {
        print('⚠️ 최대 낙폭 계산 실패: $e');
      }
      
      // 7. 거래 가능 여부 결정 (일일 손실 한도 체크 완화)
      final canTrade = !isPaused && currentPositions < maxPositions;
      
      // 일일 손실 한도는 경고만 하고 거래는 허용
      if (!dailyLossOk) {
        print('⚠️ 일일 손실 한도 초과 경고: ${dailyLoss.toStringAsFixed(2)}원');
      }
      
      return {
        'canTrade': canTrade,
        'dailyLoss': dailyLoss,
        'maxDrawdown': maxDrawdown,
        'positionCount': currentPositions,
        'maxPositions': maxPositions,
        'isPaused': isPaused,
        'dailyLossOk': dailyLossOk,
      };
      
    } catch (e) {
      print('❌ 리스크 상태 체크 실패: $e');
      return {
        'canTrade': false,
        'dailyLoss': 0.0,
        'maxDrawdown': 0.0,
        'positionCount': 0,
        'maxPositions': 5,
        'isPaused': false,
        'dailyLossOk': false,
      };
    }
  }
}
