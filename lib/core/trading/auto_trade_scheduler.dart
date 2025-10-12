import 'dart:async';
import '../data/app_data_manager.dart';
import 'auto_trader.dart';
import 'strategy_engine.dart';
import 'risk_manager.dart';
import '../bot/telegram_bot_service.dart';
import 'trade_logger.dart';

class AutoTradeScheduler {
  final AutoTrader trader;

  Timer? _timer;
  final List<String> _symbols = <String>[]; // 6자리 국내/해외 심볼 혼합 가능
  final Map<String, List<double>> _history = {};

  AutoTradeScheduler()
      : trader = AutoTrader(
          kis: kis,
          telegram: TelegramBotService(
            botToken: 'your_bot_token_here',
            chatId: 'your_chat_id_here',
          ),
          logger: TradeLogger(),
          strategy: StrategyEngine(),
          risk: const RiskManager(accountEquity: 10_000_000),
        );

  void setUniverse(List<String> symbols) {
    _symbols
      ..clear()
      ..addAll(symbols);
  }

  void start({Duration interval = const Duration(seconds: 30)}) {
    stop();
    _timer = Timer.periodic(interval, (_) => _tickOnce());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tickOnce() async {
    if (_symbols.isEmpty) {
      print('⚠️ 자동매매 심볼이 설정되지 않았습니다.');
      return;
    }
    
    print('🤖 자동매매 틱 시작 - ${_symbols.length}개 심볼 모니터링 중...');
    
    for (final code in _symbols) {
      try {
        print('📊 $code 가격 조회 중...');
        
        // ✅ API 직접 호출 비활성화 - Firestore 구독 사용
        print('🔍 [current 보호] AutoTradeScheduler에서 API 직접 호출 비활성화');
        // final quote = await KisUnifiedApiService().getStockPrice(code);
        final quote = null;
        final double price = (quote?['currentPrice'] as num?)?.toDouble() ?? 0.0;
        final String name = (quote?['stockName'] as String?) ?? code;
        final String market = (quote?['market'] as String?) ?? 'UNKNOWN';
        
        if (price <= 0) {
          print('⚠️ $code 가격 정보 없음, 건너뜀');
          continue;
        }

        final list = _history.putIfAbsent(code, () => <double>[]);
        list.add(price);
        if (list.length > 300) list.removeAt(0);

        print('📈 자동거래 틱: $code ($name) - $market - ${price.toStringAsFixed(2)}');
        
        // 자동매매 실행 (새로운 7가지 동적 지표 시스템 사용)
        await trader.tick(stockCode: code, stockName: name);
        
        print('✅ $code 처리 완료');
        
      } catch (e) {
        print('❌ $code 처리 실패: $e');
        // 개별 심볼 실패는 무시하고 다음으로 진행
      }
      
      // 레이트 리밋 보호 (더 긴 간격)
      await Future.delayed(const Duration(milliseconds: 500));
    }
    
    print('🤖 자동매매 틱 완료');
  }
}


