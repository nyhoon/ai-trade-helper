import '../../data/app_data_manager.dart';
import '../../database/repositories/trade_history_repository.dart';
import '../investment_style_manager.dart';
import '../../api/kis_unified_api_service.dart';

class TrackOrderStatusUseCase {
  final TradeHistoryRepository _tradeRepo = TradeHistoryRepository();
  final InvestmentStyleManager _styleManager = InvestmentStyleManager();

  Future<void> execute() async {
    try {
      print('🔍 주문 상태 추적 시작');
      
      // ✅ API 직접 호출 비활성화 - Firestore 구독 사용
      print('🔍 [current 보호] TrackOrderStatusUseCase에서 API 직접 호출 비활성화');
      // final pending = await KisUnifiedApiService().getOverseasPendingOrders();
      final pending = <Map<String, dynamic>>[];
      if (pending == null || pending.isEmpty) {
        print('📋 대기 중인 주문이 없습니다.');
        return;
      }

      print('📋 대기 주문 ${pending.length}건 확인 중...');

      for (final order in pending) {
        await _processOrder(order);
      }
    } catch (e) {
      print('❌ 주문 상태 추적 실패: $e');
    }
  }

  Future<void> _processOrder(Map<String, dynamic> order) async {
    try {
      final orderNo = order['orderNo'] as String? ?? '';
      final status = (order['status'] as String?)?.toLowerCase() ?? '';
      final isBuy = ((order['side'] ?? order['orderType'] ?? '') as String).contains('매수');
      final code = order['stockCode'] as String? ?? '';
      final name = order['stockName'] as String? ?? code;
      final qty = (order['quantity'] as num?)?.toInt() ?? 0;
      final executedQty = (order['executedQty'] as num?)?.toInt() ?? 0;
      final price = (order['price'] as num?)?.toDouble() ?? 0.0;
      final orderDate = order['orderDate'] as String? ?? '';
      final orderTime = order['orderTime'] as String? ?? '';

      print('📊 주문 상태 확인: $code (${isBuy ? '매수' : '매도'}) - $status');

      // 체결 완료된 주문 처리
      if (status.contains('체결') || status.contains('완료')) {
        await _recordExecutedOrder(
          orderNo: orderNo,
          code: code,
          name: name,
          isBuy: isBuy,
          qty: qty,
          executedQty: executedQty,
          price: price,
          orderDate: orderDate,
          orderTime: orderTime,
          status: status,
        );
      }
      // 부분 체결된 주문 처리
      else if (status.contains('부분') && executedQty > 0) {
        await _recordPartialExecution(
          orderNo: orderNo,
          code: code,
          name: name,
          isBuy: isBuy,
          totalQty: qty,
          executedQty: executedQty,
          price: price,
          orderDate: orderDate,
          orderTime: orderTime,
          status: status,
        );
      }
      // 대기 중인 주문은 로그만 출력
      else if (status.contains('대기')) {
        print('⏳ 주문 대기 중: $code ${isBuy ? '매수' : '매도'} $qty주 @ $price');
      }
      // 기타 상태 (취소, 실패 등)
      else {
        print('⚠️ 주문 상태 변경: $code - $status');
      }
    } catch (e) {
      print('❌ 주문 처리 실패: $e');
    }
  }

  Future<void> _recordExecutedOrder({
    required String orderNo,
    required String code,
    required String name,
    required bool isBuy,
    required int qty,
    required int executedQty,
    required double price,
    required String orderDate,
    required String orderTime,
    required String status,
  }) async {
    final now = DateTime.now();
    final finalQty = executedQty > 0 ? executedQty : qty;
    final finalAmount = finalQty * price;

    await _tradeRepo.createTable();
          await _tradeRepo.insertTradeHistory(
        stockCode: code,
        stockName: name,
        orderType: isBuy ? '매수' : '매도',
        quantity: finalQty,
        price: price,
        totalAmount: finalAmount,
        orderDate: orderDate.isNotEmpty ? orderDate : '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}',
        orderTime: orderTime.isNotEmpty ? orderTime : '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
        tradeReason: '체결완료_${_styleManager.currentStyle.name}_${status}',
        investmentStyle: _styleManager.currentStyle.name,
        isAutoTrade: true,
      );

    print('✅ 체결 완료 기록: $code ${isBuy ? '매수' : '매도'} $finalQty주 @ $price (주문번호: $orderNo)');
  }

  Future<void> _recordPartialExecution({
    required String orderNo,
    required String code,
    required String name,
    required bool isBuy,
    required int totalQty,
    required int executedQty,
    required double price,
    required String orderDate,
    required String orderTime,
    required String status,
  }) async {
    final now = DateTime.now();
    final finalAmount = executedQty * price;

    await _tradeRepo.createTable();
          await _tradeRepo.insertTradeHistory(
        stockCode: code,
        stockName: name,
        orderType: isBuy ? '매수' : '매도',
        quantity: executedQty,
        price: price,
        totalAmount: finalAmount,
        orderDate: orderDate.isNotEmpty ? orderDate : '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}',
        orderTime: orderTime.isNotEmpty ? orderTime : '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
        tradeReason: '부분체결_${_styleManager.currentStyle.name}_${executedQty}/${totalQty}',
        investmentStyle: _styleManager.currentStyle.name,
        isAutoTrade: true,
      );

    print('🔄 부분 체결 기록: $code ${isBuy ? '매수' : '매도'} $executedQty/$totalQty주 @ $price (주문번호: $orderNo)');
  }
}


