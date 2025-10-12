import 'dart:async';
import 'dart:math';
import '../api/kis_unified_api_service.dart';
import '../trading/strategy_engine.dart';
import '../trading/risk_manager.dart';
import '../trading/investment_style.dart';
import 'trade_record.dart';

class BacktestResult {
  final double initialEquity;
  final double finalEquity;
  final double totalReturn;
  final double totalReturnPercent;
  final int totalTrades;
  final int winningTrades;
  final int losingTrades;
  final double winRate;
  final double maxDrawdown;
  final List<TradeRecord> trades;
  final Map<String, dynamic> performance;

  BacktestResult({
    required this.initialEquity,
    required this.finalEquity,
    required this.totalReturn,
    required this.totalReturnPercent,
    required this.totalTrades,
    required this.winningTrades,
    required this.losingTrades,
    required this.winRate,
    required this.maxDrawdown,
    required this.trades,
    required this.performance,
  });
}

class Backtester {
  final KisUnifiedApiService unifiedApiService;
  final StrategyEngine strategy;
  final RiskManager risk;

  Backtester({
    required this.unifiedApiService,
    required this.strategy,
    required this.risk,
  });

  Future<BacktestResult> run({
    required List<String> universe,
    required DateTime from,
    required DateTime to,
    required double initialEquity,
  }) async {
    print('🤖 백테스트 시작: ${universe.length}개 종목, ${from.toString().substring(0, 10)} ~ ${to.toString().substring(0, 10)}');
    
    double currentEquity = initialEquity;
    final trades = <TradeRecord>[];
    double maxEquity = initialEquity;
    double maxDrawdown = 0;
    
    // 각 종목별로 백테스트 실행
    for (final stockCode in universe.take(5)) { // 테스트용으로 5개만
      try {
        final stockTrades = await _backtestStock(
          stockCode: stockCode,
          from: from,
          to: to,
          initialCapital: currentEquity * 0.2, // 각 종목당 20% 자본 배분
        );
        
        trades.addAll(stockTrades);
        
        // 수익률 계산
        final stockReturn = stockTrades.fold<double>(0, (sum, trade) => sum + trade.pnl);
        currentEquity += stockReturn;
        
        // 최대 낙폭 계산
        if (currentEquity > maxEquity) {
          maxEquity = currentEquity;
        }
        final drawdown = (maxEquity - currentEquity) / maxEquity;
        if (drawdown > maxDrawdown) {
          maxDrawdown = drawdown;
        }
        
        print('📈 $stockCode 백테스트 완료: ${stockTrades.length}건 거래, ${stockReturn.toStringAsFixed(0)}원 수익');
      } catch (e) {
        print('❌ $stockCode 백테스트 실패: $e');
      }
    }
    
    // 성과 분석
    final totalReturn = currentEquity - initialEquity;
    final totalReturnPercent = (totalReturn / initialEquity) * 100;
    final winningTrades = trades.where((t) => t.pnl > 0).length;
    final losingTrades = trades.where((t) => t.pnl < 0).length;
    final winRate = trades.isNotEmpty ? (winningTrades / trades.length) * 100.0 : 0.0;
    
    final performance = {
      'sharpe_ratio': _calculateSharpeRatio(trades),
      'avg_trade_return': trades.isNotEmpty ? trades.map((t) => t.pnl).reduce((a, b) => a + b) / trades.length : 0,
      'max_consecutive_losses': _calculateMaxConsecutiveLosses(trades),
    };
    
    return BacktestResult(
      initialEquity: initialEquity,
      finalEquity: currentEquity,
      totalReturn: totalReturn,
      totalReturnPercent: totalReturnPercent,
      totalTrades: trades.length,
      winningTrades: winningTrades,
      losingTrades: losingTrades,
      winRate: winRate,
      maxDrawdown: maxDrawdown,
      trades: trades,
      performance: performance,
    );
  }

  /// 실제 API 데이터를 사용한 백테스트 실행
  Future<Map<String, dynamic>> runBacktestWithRealData(
    InvestmentStyle style,
    List<Map<String, dynamic>> watchlistData,
    double initialCapital,
  ) async {
    print('🤖 실제 API 데이터 백테스트 시작: ${style.name} 스타일');
    
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
      final to = DateTime.now();
      final from = to.subtract(const Duration(days: 30));
      
      final result = await run(
        universe: stockCodes,
        from: from,
        to: to,
        initialEquity: initialCapital,
      );
      
      return {
        'totalTrades': result.totalTrades,
        'winRate': result.winRate,
        'totalReturn': result.totalReturn,
        'totalReturnPercent': result.totalReturnPercent,
        'maxDrawdown': result.maxDrawdown,
        'finalEquity': result.finalEquity,
        'winningTrades': result.winningTrades,
        'losingTrades': result.losingTrades,
        'sharpeRatio': result.performance['sharpe_ratio'],
        'avgTradeReturn': result.performance['avg_trade_return'],
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
  
  Future<List<TradeRecord>> _backtestStock({
    required String stockCode,
    required DateTime from,
    required DateTime to,
    required double initialCapital,
  }) async {
    final trades = <TradeRecord>[];
    double currentCapital = initialCapital;
    bool hasPosition = false;
    double entryPrice = 0;
    int positionSize = 0;
    
    // 실제 API에서 가격 데이터 가져오기
    List<double> priceHistory = [];
    try {
      // 나스닥 종목인지 확인
      final isNasdaq = RegExp(r'^[A-Z]{1,5}$').hasMatch(stockCode);
      
      if (isNasdaq) {
        print('🇺🇸 나스닥 종목 데이터 조회: $stockCode');
        final chartData = await unifiedApiService.getOverseasDailyChart(
          symbol: stockCode,
          exchangeCode: 'NAS',
          count: 100,
        );
        if (chartData.isNotEmpty) {
          priceHistory = chartData.map((data) => data['close'] as double).toList();
          print('✅ 나스닥 데이터 조회 성공: ${priceHistory.length}개');
        } else {
          print('❌ 나스닥 데이터 조회 실패: 빈 데이터');
          return trades;
        }
      } else {
        print('🇰🇷 국내 종목 데이터 조회: $stockCode');
        // ✅ API 직접 호출 비활성화 - Firestore 구독 사용
        print('🔍 [current 보호] Backtester에서 API 직접 호출 비활성화');
        // final chartData = await unifiedApiService.getDailyChart(stockCode, count: 100);
        final chartData = <Map<String, dynamic>>[];
        if (chartData.isNotEmpty) {
          priceHistory = chartData.map((data) => data['close'] as double).toList();
          print('✅ 국내 데이터 조회 성공: ${priceHistory.length}개');
        } else {
          print('❌ 국내 데이터 조회 실패: 빈 데이터');
          return trades;
        }
      }
    } catch (e) {
      print('❌ API 데이터 조회 실패: $e');
      return trades;
    }
    
    for (int i = 30; i < priceHistory.length; i++) {
      final currentPrice = priceHistory[i];
      final historicalPrices = priceHistory.sublist(0, i + 1);
      
      // 전략 신호 생성
      final decision = await strategy.decide(stockCode);
      
      if (decision.signal == TradeSignalType.buy && !hasPosition) {
        // 매수 신호
        final sizing = risk.sizePosition(
          entryPrice: currentPrice,
          atr: _calculateAtr(historicalPrices),
        );
        
        if (sizing.quantity > 0 && sizing.quantity * currentPrice <= currentCapital) {
          hasPosition = true;
          entryPrice = currentPrice;
          positionSize = sizing.quantity;
          currentCapital -= sizing.quantity * currentPrice;
          
          trades.add(TradeRecord(
            stockCode: stockCode,
            entryTime: DateTime.now().subtract(Duration(days: priceHistory.length - i)),
            entryPrice: currentPrice,
            quantity: sizing.quantity,
            side: 'buy',
            exitTime: null,
            exitPrice: null,
            pnl: 0,
            status: 'open',
          ));
        }
      } else if (decision.signal == TradeSignalType.sell && hasPosition) {
        // 매도 신호
        final pnl = (currentPrice - entryPrice) * positionSize;
        currentCapital += positionSize * currentPrice;
        
        // 마지막 거래 업데이트
        if (trades.isNotEmpty) {
          final lastTrade = trades.last;
          trades[trades.length - 1] = TradeRecord(
            stockCode: lastTrade.stockCode,
            entryTime: lastTrade.entryTime,
            entryPrice: lastTrade.entryPrice,
            quantity: lastTrade.quantity,
            side: lastTrade.side,
            exitTime: DateTime.now().subtract(Duration(days: priceHistory.length - i)),
            exitPrice: currentPrice,
            pnl: pnl,
            status: 'closed',
          );
        }
        
        hasPosition = false;
        entryPrice = 0;
        positionSize = 0;
      }
    }
    
    // 미결 포지션 정리
    if (hasPosition && trades.isNotEmpty) {
      final lastPrice = priceHistory.last;
      final lastTrade = trades.last;
      final pnl = (lastPrice - entryPrice) * positionSize;
      
      trades[trades.length - 1] = TradeRecord(
        stockCode: lastTrade.stockCode,
        entryTime: lastTrade.entryTime,
        entryPrice: lastTrade.entryPrice,
        quantity: lastTrade.quantity,
        side: lastTrade.side,
        exitTime: DateTime.now(),
        exitPrice: lastPrice,
        pnl: pnl,
        status: 'closed',
      );
    }
    
    return trades;
  }
  

  
  double _calculateAtr(List<double> prices, {int period = 14}) {
    if (prices.length < period + 1) return 0;
    
    double sum = 0;
    for (int i = prices.length - period; i < prices.length; i++) {
      sum += (prices[i] - prices[i - 1]).abs();
    }
    
    return sum / period;
  }
  
     double _calculateSharpeRatio(List<TradeRecord> trades) {
     if (trades.isEmpty) return 0;
     
     final returns = trades.map((t) => t.pnl).toList();
     final mean = returns.reduce((a, b) => a + b) / returns.length;
     final variance = returns.map((r) => (r - mean) * (r - mean)).reduce((a, b) => a + b) / returns.length;
     final stdDev = sqrt(variance);
     
     return stdDev > 0 ? mean / stdDev : 0;
   }
   
   int _calculateMaxConsecutiveLosses(List<TradeRecord> trades) {
     if (trades.isEmpty) return 0;
     
     int maxConsecutive = 0;
     int currentConsecutive = 0;
     
     for (final trade in trades) {
       if (trade.pnl < 0) {
         currentConsecutive++;
         if (currentConsecutive > maxConsecutive) {
           maxConsecutive = currentConsecutive;
         }
       } else {
         currentConsecutive = 0;
       }
     }
     
     return maxConsecutive;
   }
 }
