import '../data/app_data_manager.dart';
import '../api/kis_unified_api_service.dart';
import '../database/repositories/trade_history_repository.dart';
import '../database/repositories/notification_history_repository.dart';
import '../services/local_notification_manager.dart';
import 'signal_types.dart';
import 'investment_style_manager.dart';
import 'market_time_validator.dart';

/// 주문 처리기 (매수/매도 주문 실행 및 관리)
class OrderProcessor {
  static final OrderProcessor _instance = OrderProcessor._internal();
  factory OrderProcessor() => _instance;
  OrderProcessor._internal();

  // 의존성 주입
  final AppDataManager _appDataManager = AppDataManager.instance;
  final KisUnifiedApiService _unifiedApiService = KisUnifiedApiService();
  final TradeHistoryRepository _tradeHistoryRepo = TradeHistoryRepository();
  final NotificationHistoryRepository _notificationRepo = NotificationHistoryRepository();
  final LocalNotificationManager _notificationManager = LocalNotificationManager();
  final InvestmentStyleManager _styleManager = InvestmentStyleManager();

  /// 매수 주문 처리
  Future<SignalData?> processBuyOrder(SignalData signal) async {
    try {
      print('💰 매수 주문 처리 시작: ${signal.stockCode}');
      print('   - 종목명: ${signal.stockName}');
      print('   - 현재가: ${signal.price}원');
      print('   - 시그널 이유: ${signal.reason}');
      print('   - 시장: ${signal.market}');
      print('   - 자동매매 여부: ${signal.isAutoTrade}');
      
      // 0. 정규장 시간 체크 (실제 주문 전) - 임시 주석 처리
      /*
      final market = MarketTimeValidator.instance.getMarketFromSymbol(signal.stockCode);
      final tradingInfo = MarketTimeValidator.instance.getCurrentTradingInfo(market);
      print('📊 정규장 시간 체크 (주문): ${tradingInfo['status']} (${tradingInfo['reason']})');
      
      // 정규장 시간 외 매수 주문 시도 허용 여부 확인
      final shouldAllowBuy = await MarketTimeValidator.instance.shouldAllowBuyOrder(market);
      if (!shouldAllowBuy) {
        print('❌ 정규장 시간 외 - 매수 주문 차단');
        return _createFailedSignal(signal, SignalType.buyFailed, '정규장 시간 외');
      }
      
      print('✅ 정규장 시간 체크 통과 - 매수 주문 진행');
      */
      
      print('🔧 정규장 시간 체크 임시 비활성화 - 매수 주문 진행');
      
      // 1. 보유종목 확인 (중복 매수 방지 - 완화)
      final holdings = await _appDataManager.getHoldingsFromDatabase();
      print('📊 현재 보유종목 수: ${holdings.length}개');
      
      final existingHolding = holdings.firstWhere(
        (h) => h['stock_code'] == signal.stockCode || h['stockCode'] == signal.stockCode,
        orElse: () => <String, dynamic>{},
      );
      
      if (existingHolding.isNotEmpty) {
        print('ℹ️ 이미 보유 중인 종목: ${signal.stockCode} (${existingHolding['quantity']}주)');
        // 보유 중이어도 추가 매수 허용 (알림 목적)
      }
      
      // 2. 최대 보유 종목 수 확인
      final styleParams = await _styleManager.getStyleParameters(_styleManager.currentStyle);
      final maxStocks = (styleParams['maxStocks'] as num?)?.toInt();
      if (maxStocks == null) {
        print('❌ 최대 보유 종목 수가 설정되지 않았습니다.');
        return _createFailedSignal(signal, SignalType.buyFailed, '최대 종목 수 설정 필요');
      }
      print('📊 최대 보유 종목 수: $maxStocks개');
      
      if (holdings.length >= maxStocks) {
        // 이미 보유 중인 종목이면 추가 매수 허용
        if (existingHolding.isNotEmpty) {
          print('ℹ️ 최대 보유 종목 수 도달했지만 이미 보유 중인 종목: ${signal.stockCode} - 추가 매수 허용');
        } else {
          print('❌ 최대 보유 종목 수 초과: ${holdings.length}/${maxStocks}');
          return _createFailedSignal(signal, SignalType.buyFailed, '최대 보유 종목 수 초과');
        }
      }
      
      // 3. 계좌 정보 조회
      print('💰 계좌 잔고 조회 중...');
      final accountInfo = await _appDataManager.getAccountBalance();
      print('💰 계좌 데이터: $accountInfo');
      
      if (accountInfo == null) {
        print('❌ 계좌 정보 조회 실패');
        return _createFailedSignal(signal, SignalType.buyFailed, '계좌 정보 조회 실패');
      }
      
      // 4. 주문가능금액 확인
      final availableAmount = _getAvailableAmount(accountInfo);
      print('💰 주문가능금액: ${availableAmount.toStringAsFixed(0)}원');
      
      if (availableAmount <= 0) {
        print('❌ 주문가능금액 부족: $availableAmount');
        return _createFailedSignal(signal, SignalType.buyFailed, '주문가능금액 부족');
      }
      
      // 5. 투자 스타일 설정 로드
      print('📊 스타일 파라미터: $styleParams');
      final positionSize = (styleParams['positionSize'] as num?)?.toDouble();
      if (positionSize == null) {
        print('⚠️ 투자 비율이 설정되지 않았습니다.');
        return _createFailedSignal(signal, SignalType.buyFailed, '투자 비율 설정 필요');
      }
      
      print('📊 매수 투자 스타일 설정 로드:');
      print('   - 스타일: ${_styleManager.currentStyle.name}');
      print('   - 투자 비율: ${(positionSize * 100).toStringAsFixed(1)}%');
      print('   - 주문가능금액: ${availableAmount.toStringAsFixed(0)}원');
      print('   - 계산된 주문금액: ${(availableAmount * positionSize).toStringAsFixed(0)}원');
      print('   - 현재 보유 종목: ${holdings.length}개/${maxStocks}개');
      
      // 6. 주문 금액 계산
      final orderAmount = availableAmount * positionSize;
      final quantity = _calculateBuyQuantity(orderAmount, signal.price);
      
      print('📊 주문 수량 계산:');
      print('   - 주문금액: ${orderAmount.toStringAsFixed(0)}원');
      print('   - 현재가: ${signal.price.toStringAsFixed(2)}원');
      print('   - 계산된 수량: $quantity주');
      
      if (quantity <= 0) {
        print('❌ 주문 수량 계산 실패: $quantity');
        return _createFailedSignal(signal, SignalType.buyFailed, '주문 수량 계산 실패');
      }
      
      // 7. 최소 주문 단위 확인
      if (!_validateMinimumOrder(quantity, signal.price, signal.market)) {
        print('❌ 최소 주문 단위 미달');
        return _createFailedSignal(signal, SignalType.buyFailed, '최소 주문 단위 미달');
      }
      
      print('📊 매수 조건 분석:');
      print('   - 종목코드: ${signal.stockCode}');
      print('   - 종목명: ${signal.stockName}');
      print('   - 현재가: ${signal.price.toStringAsFixed(2)}');
      print('   - 주문 수량: $quantity주');
      print('   - 주문 금액: ${orderAmount.toStringAsFixed(0)}원');
      print('   - 매수 사유: AI 매수 시그널');
      
      // 8. 매수 주문 실행
      print('🚀 매수 주문 실행 시작...');
      final orderResult = await _executeBuyOrder(signal, quantity);
      if (orderResult == null) {
        print('❌ 매수 주문 실행 실패');
        return _createFailedSignal(signal, SignalType.buyFailed, '주문 실행 실패');
      }
      
      print('✅ 매수 주문 접수 성공: $orderResult');
      
      // 9. 주문 상태 DB 저장
      await _saveOrderToDatabase(signal, quantity, orderAmount, orderResult);
      
      // 9-1. 주문 체결 상태 확인 (실제 거래 성공 여부)
      final orderStatus = await _checkOrderExecutionStatus(orderResult['orderId']);
      print('🔍 매수 주문 체결 상태 확인: ${orderResult['orderId']}');
      print('   📊 체결 상태: $orderStatus');
      
      // 10. 주문 결과 알림 (체결 상태에 따라 다르게)
      await _sendOrderNotification(signal, quantity, orderAmount, orderResult, orderStatus);
      
      // 11. 성공 시그널 반환
      return SignalData(
        type: SignalType.buyPending,
        stockCode: signal.stockCode,
        stockName: signal.stockName,
        price: signal.price,
        quantity: quantity,
        totalAmount: orderAmount,
        reason: '매수 주문 실행: ${quantity}주 @ ${signal.price.toStringAsFixed(2)} (AI 매수 시그널)',
        timestamp: DateTime.now(),
        analysis: signal.analysis,
        orderId: orderResult['orderId'],
        orderStatus: '주문 대기',
        isAutoTrade: true,
        market: signal.market,
      );
      
    } catch (e) {
      print('❌ 매수 주문 처리 실패: $e');
      return _createFailedSignal(signal, SignalType.buyFailed, '매수 주문 처리 실패: $e');
    }
  }

  /// 매도 주문 처리
  Future<SignalData?> processSellOrder(SignalData signal) async {
    try {
      print('💰 매도 주문 처리 시작: ${signal.stockCode}');
      
      // 1. 보유종목 조회 (더 엄격한 검증)
      final holdings = await _appDataManager.getHoldingsFromDatabase();
      final holding = holdings.firstWhere(
        (h) => h['stock_code'] == signal.stockCode || h['stockCode'] == signal.stockCode,
        orElse: () => <String, dynamic>{},
      );
      
      if (holding.isEmpty) {
        print('❌ 보유종목 없음: ${signal.stockCode}');
        return _createFailedSignal(signal, SignalType.sellFailed, '보유종목 없음');
      }
      
      // 2. 매도 가능 수량 확인 (더 엄격한 검증)
      final availableQuantity = (holding['quantity'] as num?)?.toInt() ?? 0;
      if (availableQuantity <= 0) {
        print('❌ 매도 가능 수량 없음: $availableQuantity');
        return _createFailedSignal(signal, SignalType.sellFailed, '매도 가능 수량 없음');
      }
      
      // 3. 투자 스타일 설정 로드 (부분익절 로직 통합)
      final styleParams = await _styleManager.getStyleParameters(_styleManager.currentStyle);
          final partialProfit = (styleParams['partialProfit'] as num?)?.toDouble();
    final fullProfit = (styleParams['fullProfit'] as num?)?.toDouble();
    final stopLoss = (styleParams['stopLoss'] as num?)?.toDouble();
    final partialProfitRatio = (styleParams['partialProfitRatio'] as num?)?.toDouble();
    
    if (partialProfit == null || fullProfit == null || stopLoss == null || partialProfitRatio == null) {
      print('⚠️ 익절/손절 설정이 완료되지 않았습니다.');
      return _createFailedSignal(signal, SignalType.sellFailed, '익절/손절 설정 필요');
    }
      
      print('📊 매도 투자 스타일 설정 로드:');
      print('   - 스타일: ${_styleManager.currentStyle.name}');
      print('   - 보유 수량: $availableQuantity주');
      print('   - 부분익절: ${partialProfit.toStringAsFixed(1)}%');
      print('   - 전체익절: ${fullProfit.toStringAsFixed(1)}%');
      print('   - 손절: ${stopLoss.toStringAsFixed(1)}%');
      print('   - 부분익절 비율: ${partialProfitRatio.toStringAsFixed(1)}%');
      
      // 4. 수익률 계산 및 매도 비율 결정
      final avgPrice = (holding['avgPrice'] as num?)?.toDouble() ?? 0.0;
      final profitRate = avgPrice > 0 ? ((signal.price - avgPrice) / avgPrice) * 100 : 0.0;
      
      double sellRatio = 1.0; // 기본값: 전체 매도
      String sellReason = 'AI 매도 시그널';
      
      if (profitRate >= fullProfit) {
        // 전체익절 조건 충족
        sellRatio = 1.0;
        sellReason = '전체익절 (${profitRate.toStringAsFixed(1)}% ≥ ${fullProfit.toStringAsFixed(1)}%)';
      } else if (profitRate >= partialProfit) {
        // 부분익절 조건 충족
        sellRatio = partialProfitRatio / 100.0;
        sellReason = '부분익절 (${profitRate.toStringAsFixed(1)}% ≥ ${partialProfit.toStringAsFixed(1)}%, ${(sellRatio * 100).toStringAsFixed(0)}% 매도)';
      } else if (profitRate <= stopLoss) {
        // 손절 조건 충족
        sellRatio = 1.0;
        sellReason = '손절 (${profitRate.toStringAsFixed(1)}% ≤ ${stopLoss.toStringAsFixed(1)}%)';
      } else {
        // 일반 매도 시그널 (AI 분석 기반)
        sellRatio = 1.0;
        sellReason = 'AI 매도 시그널';
      }
      
      // 5. 매도 수량 계산
      final sellQuantity = (availableQuantity * sellRatio).round();
      if (sellQuantity <= 0) {
        print('❌ 매도 수량 계산 실패: $sellQuantity');
        return _createFailedSignal(signal, SignalType.sellFailed, '매도 수량 계산 실패');
      }
      
      // 6. 최소 매도 수량 확인
      if (!_validateMinimumSellQuantity(sellQuantity, signal.market)) {
        print('❌ 최소 매도 수량 미달');
        return _createFailedSignal(signal, SignalType.sellFailed, '최소 매도 수량 미달');
      }
      
      print('📊 매도 조건 분석:');
      print('   - 평균단가: ${avgPrice.toStringAsFixed(2)}');
      print('   - 현재가: ${signal.price.toStringAsFixed(2)}');
      print('   - 수익률: ${profitRate.toStringAsFixed(1)}%');
      print('   - 매도 비율: ${(sellRatio * 100).toStringAsFixed(0)}%');
      print('   - 매도 수량: $sellQuantity주');
      print('   - 매도 사유: $sellReason');
      
      // 7. 매도 주문 실행
      final orderResult = await _executeSellOrder(signal, sellQuantity);
      if (orderResult == null) {
        return _createFailedSignal(signal, SignalType.sellFailed, '주문 실행 실패');
      }
      
      // 주문 성공 여부 확인 추가
      if (orderResult['success'] == false) {
        final errorMessage = orderResult['message'] ?? '주문 실패';
        print('❌ 매도 주문 실패: $errorMessage');
        return _createFailedSignal(signal, SignalType.sellFailed, errorMessage);
      }
      
      // 8. 주문 상태 DB 저장
      final orderAmount = sellQuantity * signal.price;
      await _saveOrderToDatabase(signal, sellQuantity, orderAmount, orderResult);
      
      // 8-1. 주문 체결 상태 확인 (실제 거래 성공 여부)
      final orderStatus = await _checkOrderExecutionStatus(orderResult['orderId']);
      print('🔍 매도 주문 체결 상태 확인: ${orderResult['orderId']}');
      print('   📊 체결 상태: $orderStatus');
      
      // 9. 주문 결과 알림 (체결 상태에 따라 다르게)
      await _sendOrderNotification(signal, sellQuantity, orderAmount, orderResult, orderStatus);
      
      // 10. 성공 시그널 반환 (실패가 아닌 경우만)
      return SignalData(
        type: SignalType.sellPending,
        stockCode: signal.stockCode,
        stockName: signal.stockName,
        price: signal.price,
        quantity: sellQuantity,
        totalAmount: orderAmount,
        reason: '매도 주문 실행: ${sellQuantity}주 @ ${signal.price.toStringAsFixed(2)} (${sellReason})',
        timestamp: DateTime.now(),
        analysis: signal.analysis,
        orderId: orderResult['orderId'],
        orderStatus: '주문 대기',
        isAutoTrade: true,
        market: signal.market,
      );
      
    } catch (e) {
      print('❌ 매도 주문 처리 실패: $e');
      return _createFailedSignal(signal, SignalType.sellFailed, '매도 주문 처리 실패: $e');
    }
  }

  /// 주문 체결 상태 확인 (실제 거래 성공 여부)
  Future<String> _checkOrderExecutionStatus(String? orderId) async {
    try {
      if (orderId == null || orderId.isEmpty) {
        print('⚠️ 주문 ID가 없어서 체결 상태 확인 불가');
        return '주문 ID 없음';
      }
      
      print('🔍 주문 체결 상태 확인 시작: $orderId');
      
      // KIS API에서 주문 상태 조회
      final orderStatus = await _unifiedApiService.checkOverseasOrderExecution(orderId);
      if (orderStatus != null) {
        final status = orderStatus['status'] ?? '알 수 없음';
        final executedQuantity = orderStatus['executedQuantity'] ?? 0;
        final totalQuantity = orderStatus['totalQuantity'] ?? 0;
        
        print('📊 주문 상태 조회 결과:');
        print('   - 상태: $status');
        print('   - 체결 수량: $executedQuantity');
        print('   - 총 주문 수량: $totalQuantity');
        
        // 체결 완료 여부 판단
        if (status == '체결완료' && executedQuantity >= totalQuantity) {
          return '체결완료';
        } else if (status == '주문접수' || status == '주문확인') {
          return '주문접수';
        } else if (status == '주문취소' || status == '주문거부') {
          return '주문실패';
        } else {
          return status;
        }
      }
      
      // API 조회 실패 시 기본값
      print('⚠️ 주문 상태 조회 실패, 기본값 사용');
      return '확인불가';
      
    } catch (e) {
      print('❌ 주문 체결 상태 확인 중 오류: $e');
      return '오류발생';
    }
  }

  /// 주문가능금액 조회
  double _getAvailableAmount(Map<String, dynamic> accountInfo) {
    try {
      print('🔍 주문가능금액 조회 시작...');
      print('🔍 accountInfo 키들: ${accountInfo.keys.toList()}');
      
      // 1. 직접 accountInfo에서 주문가능금액 찾기
      final available = (accountInfo['availableBalance'] as num?)?.toDouble() ?? 
                       (accountInfo['ordAbleAmt'] as num?)?.toDouble() ?? 
                       (accountInfo['ord_able_amt'] as num?)?.toDouble() ?? 
                       (accountInfo['availableAmount'] as num?)?.toDouble() ?? 
                       (accountInfo['balance'] as num?)?.toDouble() ?? 
                       (accountInfo['dncaTotAmt'] as num?)?.toDouble();
      
      if (available != null && available > 0) {
        print('💰 주문가능금액: ${available.toStringAsFixed(0)}원');
        return available;
      }
      
      // 2. 중첩된 accountInfo 구조에서 찾기
      final accountData = accountInfo['accountInfo'];
      if (accountData is Map<String, dynamic>) {
        print('🔍 중첩된 accountInfo 키들: ${accountData.keys.toList()}');
        
        final nestedAvailable = (accountData['availableBalance'] as num?)?.toDouble() ?? 
                               (accountData['ordAbleAmt'] as num?)?.toDouble() ?? 
                               (accountData['ord_able_amt'] as num?)?.toDouble() ?? 
                               (accountData['availableAmount'] as num?)?.toDouble() ?? 
                               (accountData['balance'] as num?)?.toDouble() ?? 
                               (accountData['dncaTotAmt'] as num?)?.toDouble();
        
        if (nestedAvailable != null && nestedAvailable > 0) {
          print('💰 중첩된 accountInfo에서 주문가능금액: ${nestedAvailable.toStringAsFixed(0)}원');
          return nestedAvailable;
        }
      }
      
      print('⚠️ 주문가능금액을 찾을 수 없음, 기본값 사용');
      return 1000000.0; // 100만원
    } catch (e) {
      print('❌ 주문가능금액 조회 실패: $e');
      return 0.0;
    }
  }

  /// 매수 수량 계산
  int _calculateBuyQuantity(double orderAmount, double price) {
    if (price <= 0) return 0;
    
    // 수수료를 고려한 수량 계산 (수수료 0.015% 가정)
    const commission = 0.00015;
    final maxQuantity = (orderAmount / (price * (1 + commission))).floor();
    
    return maxQuantity;
  }

  /// 최소 주문 단위 확인
  bool _validateMinimumOrder(int quantity, double price, String? market) {
    if (quantity <= 0 || price <= 0) return false;
    
    final orderAmount = quantity * price;
    
    // 시장별 최소 주문 금액
    double minAmount;
    switch (market) {
      case 'NASDAQ':
      case 'NYSE':
        minAmount = 1.0; // 1달러
        break;
      case 'KOSPI':
      case 'KOSDAQ':
        minAmount = 10000.0; // 1만원
        break;
      default:
        minAmount = 10000.0; // 기본 1만원
    }
    
    return orderAmount >= minAmount;
  }

  /// 최소 매도 수량 확인
  bool _validateMinimumSellQuantity(int quantity, String? market) {
    if (quantity <= 0) return false;
    
    // 시장별 최소 매도 수량
    int minQuantity;
    switch (market) {
      case 'NASDAQ':
      case 'NYSE':
        minQuantity = 1; // 1주
        break;
      case 'KOSPI':
      case 'KOSDAQ':
        minQuantity = 1; // 1주
        break;
      default:
        minQuantity = 1; // 기본 1주
    }
    
    return quantity >= minQuantity;
  }

  /// 매수 주문 실행
  Future<Map<String, dynamic>?> _executeBuyOrder(SignalData signal, int quantity) async {
    try {
      print('📈 매수 주문 실행 시작: ${signal.stockCode} ${quantity}주 @ ${signal.price}');
      print('   - 시장: ${signal.market}');
      print('   - 종목코드: ${signal.stockCode}');
      print('   - 종목명: ${signal.stockName}');
      print('   - 주문수량: $quantity주');
      print('   - 주문가격: ${signal.price}원');
      print('   - 총 주문금액: ${(quantity * signal.price).toStringAsFixed(0)}원');
      
      // 시장별 주문 실행 및 체결 확인
      Map<String, dynamic>? orderResult;
      
      switch (signal.market) {
        case 'NASDAQ':
        case 'NYSE':
          print('🌍 해외주식 매수 주문 실행 및 체결 확인: ${signal.stockCode}');
          orderResult = await _unifiedApiService.executeOverseasOrder(
            symbol: signal.stockCode,
            orderType: 'BUY',
            quantity: quantity,
            price: signal.price,
          );
          break;
        case 'KOSPI':
        case 'KOSDAQ':
          print('🇰🇷 국내주식 매수 주문 실행 및 체결 확인: ${signal.stockCode}');
          orderResult = await _unifiedApiService.executeOverseasOrder(
            symbol: signal.stockCode,
            orderType: 'BUY',
            quantity: quantity,
            price: signal.price,
          );
          break;
        default:
          print('❌ 지원하지 않는 시장: ${signal.market}');
          return null;
      }
      
      if (orderResult != null) {
        final orderId = orderResult['orderId'] ?? orderResult['orderNo'] ?? '';
        final orderStatus = orderResult['orderStatus'] ?? 'UNKNOWN';
        final executedQuantity = orderResult['executedQuantity'] ?? 0;
        
        print('📊 매수 주문 결과:');
        print('   - 주문번호: $orderId');
        print('   - 주문상태: $orderStatus');
        print('   - 체결수량: $executedQuantity');
        print('   - 성공여부: ${orderResult['success']}');
        print('   - 메시지: ${orderResult['message']}');
        
        // 체결 상태에 따른 처리
        switch (orderStatus) {
          case 'EXECUTED':
            print('🎉 매수 주문이 성공적으로 체결되었습니다!');
            print('   - 체결수량: ${executedQuantity}주');
            print('   - 체결가격: ${orderResult['executedPrice']}원');
            return orderResult;
            
          case 'PARTIAL':
            print('⚠️ 매수 주문이 부분적으로 체결되었습니다.');
            print('   - 체결수량: ${executedQuantity}주');
            print('   - 남은수량: ${orderResult['remainingQuantity']}주');
            return orderResult;
            
          case 'FAILED':
            print('❌ 매수 주문이 실패했습니다.');
            print('   - 실패사유: ${orderResult['message']}');
            return null;
            
          case 'TIMEOUT':
            print('⏰ 매수 주문 체결 확인 시간이 초과되었습니다.');
            print('   - 주문번호: $orderId (수동 확인 필요)');
            return orderResult;
            
          default:
            print('❓ 알 수 없는 주문 상태: $orderStatus');
            return orderResult;
        }
      } else {
        print('❌ 매수 주문 실패: API에서 null 반환');
        return null;
      }
      
    } catch (e) {
      print('❌ 매수 주문 실행 실패: $e');
      print('   - 오류 스택: ${StackTrace.current}');
      return null;
    }
  }

  /// 매도 주문 실행
  Future<Map<String, dynamic>?> _executeSellOrder(SignalData signal, int quantity) async {
    try {
      print('📉 매도 주문 실행: ${signal.stockCode} ${quantity}주 @ ${signal.price}');
      
      // 시장별 주문 실행 및 체결 확인
      Map<String, dynamic>? orderResult;
      
      switch (signal.market) {
        case 'NASDAQ':
        case 'NYSE':
          print('🌍 해외주식 매도 주문 실행 및 체결 확인: ${signal.stockCode}');
          orderResult = await _unifiedApiService.executeOverseasOrder(
            symbol: signal.stockCode,
            orderType: 'SELL',
            quantity: quantity,
            price: signal.price,
          );
          break;
        case 'KOSPI':
        case 'KOSDAQ':
          print('🇰🇷 국내주식 매도 주문 실행 및 체결 확인: ${signal.stockCode}');
          orderResult = await _unifiedApiService.executeOverseasOrder(
            symbol: signal.stockCode,
            orderType: 'SELL',
            quantity: quantity,
            price: signal.price,
          );
          break;
        default:
          print('❌ 지원하지 않는 시장: ${signal.market}');
          return null;
      }
      
      if (orderResult != null) {
        final orderId = orderResult['orderId'] ?? orderResult['orderNo'] ?? '';
        final orderStatus = orderResult['orderStatus'] ?? 'UNKNOWN';
        final executedQuantity = orderResult['executedQuantity'] ?? 0;
        
        print('📊 매도 주문 결과:');
        print('   - 주문번호: $orderId');
        print('   - 주문상태: $orderStatus');
        print('   - 체결수량: $executedQuantity');
        print('   - 성공여부: ${orderResult['success']}');
        print('   - 메시지: ${orderResult['message']}');
        
        // 체결 상태에 따른 처리
        switch (orderStatus) {
          case 'EXECUTED':
            print('🎉 매도 주문이 성공적으로 체결되었습니다!');
            print('   - 체결수량: ${executedQuantity}주');
            print('   - 체결가격: ${orderResult['executedPrice']}원');
            return orderResult;
            
          case 'PARTIAL':
            print('⚠️ 매도 주문이 부분적으로 체결되었습니다.');
            print('   - 체결수량: ${executedQuantity}주');
            print('   - 남은수량: ${orderResult['remainingQuantity']}주');
            return orderResult;
            
          case 'FAILED':
            print('❌ 매도 주문이 실패했습니다.');
            print('   - 실패사유: ${orderResult['message']}');
            return null;
            
          case 'TIMEOUT':
            print('⏰ 매도 주문 체결 확인 시간이 초과되었습니다.');
            print('   - 주문번호: $orderId (수동 확인 필요)');
            return orderResult;
            
          default:
            print('❓ 알 수 없는 주문 상태: $orderStatus');
            return orderResult;
        }
      } else {
        // 서버에서 반환한 오류 메시지 확인
        final errorMessage = orderResult?['message'] ?? '알 수 없는 오류';
        final rtCd = orderResult?['rt_cd'] ?? '';
        
        print('❌ 매도 주문 실패: $errorMessage (rt_cd: $rtCd)');
        
        // 장 운영시간 외 오류 체크
        if (errorMessage.contains('장 운영시간') || 
            errorMessage.contains('거래시간') ||
            errorMessage.contains('장 마감') ||
            rtCd == 'EGW00123' || // 장 운영시간 외
            rtCd == 'EGW00124') { // 장 마감 후
          print('❌ 장 운영시간 외 주문 시도: $errorMessage');
          return {
            'success': false,
            'error': '장 운영시간 외',
            'message': '장 운영시간이 아니어서 주문이 실패했습니다.',
            'rt_cd': rtCd,
            'original_message': errorMessage,
          };
        }
        
        return orderResult; // 기타 오류는 원본 응답 반환
      }
    } catch (e) {
      print('❌ 매도 주문 실행 실패: $e');
      return null;
    }
  }

  /// 주문 DB 저장
  Future<void> _saveOrderToDatabase(
    SignalData signal,
    int quantity,
    double orderAmount,
    Map<String, dynamic> orderResult,
  ) async {
    try {
      await _tradeHistoryRepo.insertTradeHistory(
        stockCode: signal.stockCode,
        stockName: signal.stockName,
        orderType: signal.type == SignalType.buySignal ? '매수' : '매도',
        quantity: quantity,
        price: signal.price,
        totalAmount: orderAmount,
        orderDate: DateTime.now().toString().substring(0, 10),
        orderTime: DateTime.now().toString().substring(11, 16),
        isAutoTrade: true,
      );
      
      print('💾 주문 DB 저장 완료: ${orderResult['orderId']}');
    } catch (e) {
      print('❌ 주문 DB 저장 실패: $e');
    }
  }

  /// 주문 알림 발송
  Future<void> _sendOrderNotification(
    SignalData signal,
    int quantity,
    double orderAmount,
    Map<String, dynamic> orderResult,
    String orderStatus,
  ) async {
    try {
      // 주문 상태 확인
      final orderStatus = orderResult['orderStatus'] as String? ?? 'UNKNOWN';
      
      if (orderStatus == 'FAILED') {
        // 주문 실패 시 오류 알림
        final errorMessage = orderResult['message'] ?? '주문 실패';
        final originalMessage = orderResult['original_message'] ?? '';
        
        String notificationBody = '${signal.stockName} (${signal.stockCode}): $errorMessage';
        if (originalMessage.isNotEmpty) {
          notificationBody += '\n서버 오류: $originalMessage';
        }
        
        final failureTitle = signal.type == SignalType.buySignal ? '❌ 매수 주문 실패' : '❌ 매도 주문 실패';
        final failureType = signal.type == SignalType.buySignal ? '매수 주문 실패' : '매도 주문 실패';
        
        await _notificationManager.showNotification(
          title: failureTitle,
          body: notificationBody,
        );
        
        // 실패 알림 DB 저장
        await _notificationRepo.addNotification(
          type: failureType,
          stockCode: signal.stockCode,
          stockName: signal.stockName,
          message: notificationBody,
        );
        return;
      }
      
      // 주문 성공 시 정상 알림 (체결 상태에 따라 다르게)
      String title;
      String message = '${signal.stockName} (${signal.stockCode}): ${quantity}주 @ ${signal.price.toStringAsFixed(2)}';
      
      // 주문 상태에 따른 알림 처리
      final executedQuantity = orderResult['executedQuantity'] as int? ?? 0;
      
      switch (orderStatus) {
        case 'EXECUTED':
          title = signal.type == SignalType.buySignal ? '✅ 매수 체결 완료' : '✅ 매도 체결 완료';
          message += ' (체결 완료: ${executedQuantity}주)';
          break;
          
        case 'PARTIAL':
          final remainingQty = orderResult['remainingQuantity'] as int? ?? 0;
          title = signal.type == SignalType.buySignal ? '⚠️ 매수 부분 체결' : '⚠️ 매도 부분 체결';
          message += ' (부분 체결: ${executedQuantity}주, 남은 ${remainingQty}주)';
          break;
          
        case 'FAILED':
          title = signal.type == SignalType.buySignal ? '❌ 매수 주문 실패' : '❌ 매도 주문 실패';
          message += ' (주문 실패)';
          break;
          
        case 'TIMEOUT':
          title = signal.type == SignalType.buySignal ? '⏰ 매수 체결 확인 대기' : '⏰ 매도 체결 확인 대기';
          message += ' (체결 확인 대기 중)';
          break;
          
        case 'PENDING':
          title = signal.type == SignalType.buySignal ? '📋 매수 주문 접수' : '📋 매도 주문 접수';
          message += ' (주문 접수 완료)';
          break;
          
        default:
          title = signal.type == SignalType.buySignal ? '⏳ 매수 주문 처리중' : '⏳ 매도 주문 처리중';
          message += ' ($orderStatus)';
      }
      
      // 매도인 경우 이유와 기준 퍼센트 추가
      if (signal.type == SignalType.sellSignal && signal.reason != null && signal.reason!.isNotEmpty) {
        String reasonText = '';
        final reason = signal.reason!;
        
        if (reason.contains('부분익절') || reason.contains('전체익절') || reason.contains('손절')) {
          try {
            // 현재 투자 스타일 설정에서 기준 퍼센트 조회
            final styleManager = InvestmentStyleManager();
            final currentStyle = await styleManager.getCurrentStyle();
            final styleParams = await styleManager.getStyleParameters(currentStyle);
            
            if (reason.contains('손절')) {
              final stopLoss = (styleParams['stopLoss'] as num?)?.toDouble() ?? 0.0;
              reasonText = ' (손절 실행: ${stopLoss.abs().toStringAsFixed(1)}% 기준)';
            } else if (reason.contains('부분익절')) {
              final partialProfit = (styleParams['partialProfit'] as num?)?.toDouble() ?? 0.0;
              reasonText = ' (부분익절 실행: ${partialProfit.toStringAsFixed(1)}% 기준)';
            } else if (reason.contains('전체익절')) {
              final fullProfit = (styleParams['fullProfit'] as num?)?.toDouble() ?? 0.0;
              reasonText = ' (전체익절 실행: ${fullProfit.toStringAsFixed(1)}% 기준)';
            }
          } catch (e) {
            print('⚠️ 매도 기준 퍼센트 조회 실패: $e');
            // 기본 텍스트 사용
            if (reason.contains('손절')) {
              reasonText = ' (손절 실행)';
            } else if (reason.contains('부분익절')) {
              reasonText = ' (부분익절 실행)';
            } else if (reason.contains('전체익절')) {
              reasonText = ' (전체익절 실행)';
            }
          }
        } else if (reason.contains('기술적') || reason.contains('종합점수')) {
          reasonText = ' (기술적 매도)';
        } else {
          reasonText = ' ($reason)';
        }
        
        message += reasonText;
      }
      
      // 푸시 알림 발송
      await _notificationManager.showNotification(
        title: title,
        body: message,
      );
      
      // 알림 DB 저장
      await _notificationRepo.addNotification(
        type: signal.type.name,
        stockCode: signal.stockCode,
        stockName: signal.stockName,
        message: message,
        market: MarketTimeValidator.instance.getMarketFromSymbol(signal.stockCode),
      );
      
      print('📱 주문 알림 발송 완료: ${orderResult['orderId']}');
    } catch (e) {
      print('❌ 주문 알림 발송 실패: $e');
    }
  }

  /// 실패 시그널 생성
  SignalData _createFailedSignal(SignalData originalSignal, SignalType failedType, String reason) {
    return SignalData(
      type: failedType,
      stockCode: originalSignal.stockCode,
      stockName: originalSignal.stockName,
      price: originalSignal.price,
      reason: reason,
      timestamp: DateTime.now(),
      analysis: originalSignal.analysis,
      isAutoTrade: true,
      market: originalSignal.market,
    );
  }

  /// 주문 상태 확인
  Future<SignalData?> checkOrderStatus(String orderId, SignalData originalSignal) async {
    try {
      print('🔍 주문 상태 확인: $orderId');
      
      // KIS API로 주문 상태 조회
      final orderStatus = await _unifiedApiService.checkOverseasOrderExecution(orderId);
      if (orderStatus == null) {
        print('❌ 주문 상태 조회 실패: $orderId');
        return null;
      }
      
      final status = orderStatus['status'] as String? ?? '';
      final executedQuantity = (orderStatus['executedQuantity'] as num?)?.toInt() ?? 0;
      final executedPrice = (orderStatus['executedPrice'] as num?)?.toDouble() ?? 0.0;
      
      // 상태별 시그널 타입 결정
      SignalType signalType;
      String orderStatusText;
      
      switch (status.toUpperCase()) {
        case 'FILLED':
        case 'COMPLETED':
          signalType = originalSignal.type == SignalType.buySignal ? SignalType.buySuccess : SignalType.sellSuccess;
          orderStatusText = '체결 완료';
          break;
        case 'REJECTED':
        case 'CANCELLED':
          signalType = originalSignal.type == SignalType.buySignal ? SignalType.buyFailed : SignalType.sellFailed;
          orderStatusText = '주문 실패';
          break;
        case 'PENDING':
        case 'PARTIAL':
          signalType = originalSignal.type == SignalType.buySignal ? SignalType.buyPending : SignalType.sellPending;
          orderStatusText = '체결 대기';
          break;
        default:
          signalType = originalSignal.type == SignalType.buySignal ? SignalType.buyPending : SignalType.sellPending;
          orderStatusText = '주문 대기';
      }
      
      // 시그널 생성
      return SignalData(
        type: signalType,
        stockCode: originalSignal.stockCode,
        stockName: originalSignal.stockName,
        price: executedPrice > 0 ? executedPrice : originalSignal.price,
        quantity: executedQuantity > 0 ? executedQuantity : originalSignal.quantity,
        totalAmount: executedQuantity > 0 && executedPrice > 0 ? executedQuantity * executedPrice : originalSignal.totalAmount,
        reason: '주문 상태: $orderStatusText',
        timestamp: DateTime.now(),
        analysis: originalSignal.analysis,
        orderId: orderId,
        orderStatus: orderStatusText,
        isAutoTrade: true,
        market: originalSignal.market,
      );
      
    } catch (e) {
      print('❌ 주문 상태 확인 실패: $e');
      return null;
    }
  }
}
