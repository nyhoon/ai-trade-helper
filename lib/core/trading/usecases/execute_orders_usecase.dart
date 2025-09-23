import '../../data/app_data_manager.dart';
import '../../database/repositories/trade_history_repository.dart';
import '../investment_style_manager.dart';
import '../investment_style.dart';
import 'advanced_risk_manager.dart';

class ExecuteOrdersUseCase {
  final TradeHistoryRepository _tradeRepo = TradeHistoryRepository();
  final InvestmentStyleManager _styleManager = InvestmentStyleManager();
  final AdvancedRiskManager _riskManager = AdvancedRiskManager();

  Future<void> execute(List<Map<String, dynamic>> signals) async {
    // 현재 투자 스타일 설정 로드
    final styleParams = await _styleManager.getStyleParameters(_styleManager.currentStyle);
    final positionSize = (styleParams['positionSize'] as num?)?.toDouble() ?? 0.1; // 기본값 제거, 스타일별 설정 사용
    final maxStocks = (styleParams['maxStocks'] as num?)?.toInt() ?? 5;
    
    print('📊 주문 실행 - 스타일: ${_styleManager.currentStyle}, 포지션사이즈: ${(positionSize * 100).toStringAsFixed(1)}%, 최대종목: $maxStocks');

    // 현재 보유 종목 수 확인
    final currentHoldings = await AppDataManager.instance.holdingsRepository.getAllHoldings();
    final currentStockCount = currentHoldings.length;
    
    if (currentStockCount >= maxStocks) {
      print('⚠️ 최대 보유 종목 수($maxStocks)에 도달했습니다. 매수 주문을 건너뜁니다.');
    }

    for (final s in signals) {
      final code = s['stockCode'] as String;
      final name = s['stockName'] as String? ?? code;
      final side = s['signal'] as String; // '매수' | '매도'
      final price = (s['currentPrice'] as num).toDouble();

      if (side == '매수') {
        // 매수는 AutoTradingCycle에서 처리하므로 여기서는 건너뜀
        print('⚠️ $code 매수 건너뜀: AutoTradingCycle에서 처리됨');
        continue;
      } else if (side == '매도') {
        // 매도는 AutoTradingCycle에서 처리하므로 여기서는 건너뜀
        print('⚠️ $code 매도 건너뜀: AutoTradingCycle에서 처리됨');
        continue;
      }
    }
  }

  // 매수는 AutoTradingCycle에서 처리하므로 주석 처리
  // Future<void> _buy(String code, String name, double price, double positionSize) async {
  //   // 매수 로직은 OrderProcessor로 이동됨
  // }

  // 매도는 AutoTradingCycle에서 처리하므로 주석 처리
  // Future<void> _sell(String code, String name, double price) async {
  //   // 매도 로직은 OrderProcessor로 이동됨
  // }

  Future<void> _record(Map<String, dynamic> res, String code, String name, int qty, double price, String side, double amount) async {
    final now = DateTime.now();
    final success = res['success'] as bool? ?? false;
    
    await _tradeRepo.createTable();
    await _tradeRepo.insertTradeHistory(
      stockCode: code,
      stockName: name,
      orderType: side,
      quantity: qty,
      price: price,
      totalAmount: amount,
      orderDate: '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}',
      orderTime: '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      tradeReason: 'AutoCycle_${_styleManager.currentStyle.name}',
      investmentStyle: _styleManager.currentStyle.name,
      isAutoTrade: true,
    );

    if (success) {
      print('✅ 주문 기록 완료: $code $side $qty주 @ $price');
    } else {
      print('❌ 주문 실패 기록: $code $side - ${res['message']}');
    }
  }
}


