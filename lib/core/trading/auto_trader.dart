import '../api/kis_unified_api_service.dart';
import '../bot/telegram_bot_service.dart';
import 'indicator_calculator.dart';
import 'strategy_engine.dart';
import 'risk_manager.dart';
import 'trade_logger.dart';
import '../alerts/alert_manager.dart';
import 'market_time_validator.dart';

class AutoTrader {
  final KisUnifiedApiService unifiedApiService;
  final TelegramBotService telegram;
  final TradeLogger logger;
  final StrategyEngine strategy;
  final RiskManager risk;

  AutoTrader({
    required this.unifiedApiService,
    required this.telegram,
    required this.logger,
    required this.strategy,
    required this.risk,
  });

  Future<void> tick({required String stockCode, required String stockName}) async {
    // 시장 구분 (MarketTimeValidator 사용)
    final market = MarketTimeValidator.instance.getMarketFromSymbol(stockCode);
    print('📊 시장 구분: $stockCode → $market');

    // 거래 시간 외 매매 신호 차단 - 임시 주석 처리
    /*
    if (MarketTimeValidator.instance.shouldBlockTradingSignal(market, 'buy') || 
        MarketTimeValidator.instance.shouldBlockTradingSignal(market, 'sell')) {
      print('⚠️ [AutoTrader] 거래 시간 외: $market 시장 매매 신호 차단');
      return;
    }
    */
    
    print('🔧 [AutoTrader] 거래 시간 체크 임시 비활성화 - $market 시장 매매 신호 허용');

    final decision = await strategy.decide(stockCode);
    if (decision.signal == TradeSignalType.hold) return;

    // 현재가 가져오기
    final currentPriceData = await AppDataManager.instance.getCachedStockData(stockCode);
    final entry = currentPriceData['currentPrice'] as double? ?? 0.0;
    
    if (entry <= 0) {
      print('⚠️ [AutoTrader] 현재가 데이터 없음: $stockCode');
      return;
    }
    // 간단한 포지션 사이징 (ATR 대신 고정 비율 사용)
    final sizing = risk.sizePosition(entryPrice: entry, atr: entry * 0.02); // 2% 변동성 가정
    if (sizing.quantity <= 0) return;

    final side = decision.signal == TradeSignalType.buy ? 'buy' : 'sell';
    final res = await kis.executeOrderWithConfirmation(
      stockCode: stockCode,
      orderType: side,
      quantity: sizing.quantity,
      price: entry,
      confirmationTimeout: const Duration(minutes: 5),
    );

    final status = res['orderStatus'] == 'EXECUTED' ? 'success' : 'failed';
    // 텔레그램 전송: 초기화 예외는 무시
    try {
      await telegram.initialize();
      await telegram.sendTradeNotification(
      stockCode: stockCode,
      stockName: stockName,
        orderType: side,
        quantity: sizing.quantity,
        price: entry,
        status: status,
      );
    } catch (_) {}

    // 시그널 로그 저장
    await TradeLogger.logSignal(TradeSignal(
      stockCode: stockCode,
      stockName: stockName,
      signalType: side,
      timestamp: DateTime.now(),
      indicators: decision.reason.indicators,
      reason: decision.reason.summary,
      currentPrice: entry,
      targetPrice: side == 'buy' ? entry * 1.08 : null, // 매수 시 +8% 목표가
      stopLoss: side == 'buy' ? '${(entry * 0.95).round()}원' : null, // 매수 시 -5% 손절
      takeProfit: side == 'buy' ? '${(entry * 1.08).round()}원' : null, // 매수 시 +8% 익절
    ));

    // 관심종목 시그널 알림 업데이트
    await _updateSignalAlert(stockCode, side, entry);

    // 기존 TradeRecord 로깅은 제거 (새로운 TradeSignal 로깅으로 대체)
    print('🤖 [AutoTrader] $side signal executed for $stockName ($stockCode)');
  }



  Future<void> _updateSignalAlert(String stockCode, String signalType, double price) async {
    try {
      final alertType = signalType == 'buy' ? AlertType.buySignal : AlertType.sellSignal;
      final alertId = '${stockCode}_${signalType}_signal';
      
      // 해당 알림 설정 찾기
      final alerts = await AlertManager.getAlerts();
      final alertIndex = alerts.indexWhere((a) => a.id == alertId);
      
      if (alertIndex != -1) {
        final alert = alerts[alertIndex];
        
        if (alert.isEnabled) {
          // 알림 마지막 발생 시간 업데이트
          final updatedAlert = alert.copyWith(lastTriggered: DateTime.now());
          await AlertManager.updateAlert(updatedAlert);
          
          print('🤖 [알림 업데이트] $stockCode $signalType 시그널 알림 업데이트');
        }
      }
    } catch (e) {
      print('Failed to update signal alert: $e');
    }
  }
}
