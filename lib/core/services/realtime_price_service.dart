import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../data/app_data_manager.dart';
import '../database/repositories/stock_prices_repository.dart';
import '../analysis/unified_analysis_service.dart';
import '../trading/investment_style.dart';
import '../trading/investment_style_manager.dart';
import '../trading/market_time_validator.dart';
import '../api/kis_unified_api_service.dart';
import '../api/kis_unified_api_service_websocket.dart';

class RealtimePriceService {
  static final RealtimePriceService _instance = RealtimePriceService._internal();
  factory RealtimePriceService() => _instance;
  RealtimePriceService._internal();

  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  Timer? _fallbackPriceTimer; // 폴백 현재가 조회 타이머
  bool _isConnected = false;
  bool _isConnecting = false;
  
  final StockPricesRepository _priceRepo = StockPricesRepository();
  // UnifiedAnalysisService는 필요할 때만 참조 (순환 참조 방지)
  UnifiedAnalysisService get _unifiedAnalysis => UnifiedAnalysisService.instance;
  final InvestmentStyleManager _styleManager = InvestmentStyleManager();
  
  // 실시간 가격 스트림
  final StreamController<Map<String, dynamic>> _priceController = 
      StreamController<Map<String, dynamic>>.broadcast();
  
  Stream<Map<String, dynamic>> get priceStream => _priceController.stream;
  
  /// 가격 저장소 접근용 getter
  StockPricesRepository get priceRepo => _priceRepo;
  
  // 가격 변동 임계값 (1% 이상 변동 시 시그널 재분석)
  static const double _priceChangeThreshold = 0.01; // 1%
  
  // 마지막 가격 저장
  final Map<String, double> _lastPrices = {};
  
  // 마지막 시그널 시간 저장 (중복 방지용)
  final Map<String, DateTime> _lastSignalTimes = {};
  
  // 연결된 종목 목록
  final Set<String> _subscribedStocks = <String>{};

  /// 실시간 가격 서비스 시작
  Future<void> start() async {
    if (_isConnected || _isConnecting) return;
    
    try {
      _isConnecting = true;
      print('🔌 실시간 가격 서비스 시작...');
      
      // 정규장 시간 체크
      final now = DateTime.now();
      final weekday = now.weekday; // 1=월요일, 7=일요일
      final hour = now.hour;
      
      // 정규장 시간 체크 (지표 표시는 항상 허용, 매매 시그널만 제한)
      bool isTradingTime = false;
      
      // 국내주식 거래시간 체크
      if (MarketTimeValidator.instance.isTradingTime('KOSPI') || 
          MarketTimeValidator.instance.isTradingTime('KOSDAQ')) {
        isTradingTime = true;
      }
      
      // 나스닥 거래시간 체크
      if (MarketTimeValidator.instance.isTradingTime('NASDAQ')) {
        isTradingTime = true;
      }
      
      if (!isTradingTime) {
        final tradingInfo = MarketTimeValidator.instance.getCurrentTradingInfo('KOSPI');
        print('⏰ 정규장 시간 외 - 지표 표시는 계속, 매매 시그널만 제한 (${tradingInfo['currentTime']} - ${tradingInfo['reason']})');
        // 정규장 시간 외에도 지표 데이터는 계속 업데이트
      }
      
      // 투자스타일 매니저 초기화
      await _styleManager.initialize();
      
      // 관심종목 및 보유종목 가져오기
      final watchlist = await AppDataManager.instance.getWatchlist();
      final holdings = await AppDataManager.instance.holdingsRepository.getHoldings();
      
      final allStocks = <String>{};
      for (final stock in watchlist) {
        final stockCode = stock['stockCode'] as String? ?? stock['stock_code'] as String?;
        if (stockCode != null && stockCode.isNotEmpty) {
          allStocks.add(stockCode);
        }
      }
      for (final stock in holdings) {
        final stockCode = stock['stockCode'] as String? ?? stock['stock_code'] as String?;
        if (stockCode != null && stockCode.isNotEmpty) {
          allStocks.add(stockCode);
        }
      }
      
      if (allStocks.isEmpty) {
        print('⚠️ 실시간 가격 구독할 종목이 없습니다.');
        return;
      }
      
      // WebSocket 연결 시도
      try {
        await _connectWebSocket();
        
        // 종목 구독
        await _subscribeStocks(allStocks);
        
        // 하트비트 시작
        _startHeartbeat();
        
        print('✅ WebSocket 실시간 가격 서비스 시작 완료 (${allStocks.length}개 종목)');
      } catch (e) {
        print('⚠️ WebSocket 연결 실패, 폴백 타이머로 전환: $e');
        // WebSocket 실패 시 폴백 타이머 시작
        _startFallbackPriceTimer(allStocks);
      }
      
    } catch (e) {
      print('❌ 실시간 가격 서비스 시작 실패: $e');
      _scheduleReconnect();
    } finally {
      _isConnecting = false;
    }
  }

  /// WebSocket 연결
  Future<void> _connectWebSocket() async {
    try {
      // KIS API WebSocket 접속키 발급
      final accessKey = await _getWebSocketAccessKey();
      if (accessKey == null) {
        throw Exception('WebSocket 접속키 발급 실패');
      }
      
      // 통합된 API 서비스를 통해 WebSocket 연결 생성
      final unifiedApiService = KisUnifiedApiService();
      _channel = await unifiedApiService.createWebSocketConnection(
        approvalKey: accessKey,
      );
      
      if (_channel == null) {
        throw Exception('WebSocket 연결 생성 실패');
      }
      
      _isConnected = true;
      print('🔌 KIS WebSocket 연결 성공 (통합 API 서비스 사용)');
      
      // 메시지 리스너
      _channel!.stream.listen(
        (message) => _handleWebSocketMessage(message),
        onError: (error) {
          print('❌ WebSocket 오류: $error');
          unifiedApiService.handleWebSocketError(error);
          _handleDisconnection();
        },
        onDone: () {
          print('🔌 WebSocket 연결 종료');
          _handleDisconnection();
        },
      );
      
    } catch (e) {
      print('❌ WebSocket 연결 실패: $e');
      throw e;
    }
  }

  /// KIS WebSocket 접속키 발급
  Future<String?> _getWebSocketAccessKey() async {
    try {
      // 통합된 API 서비스를 통해 WebSocket 접속키 발급
      final unifiedApiService = KisUnifiedApiService();
      final response = await unifiedApiService.getWebSocketAccessToken();
      final approvalKey = response?['approval_key'] as String?;
      
      if (approvalKey == null || approvalKey.isEmpty) {
        print('⚠️ WebSocket 접속키가 비어있음');
        return null;
      }
      
      print('✅ WebSocket 접속키 발급 성공 (통합 API 서비스 사용)');
      return approvalKey;
    } catch (e) {
      print('❌ WebSocket 접속키 발급 실패: $e');
      return null;
    }
  }

  /// 종목 구독
  Future<void> _subscribeStocks(Set<String> stocks) async {
    if (!_isConnected || _channel == null) return;
    
    try {
      final unifiedApiService = KisUnifiedApiService();
      final approvalKey = await _getWebSocketAccessKey();
      
      if (approvalKey == null) {
        print('⚠️ WebSocket 접속키 없음, 종목 구독 건너뜀');
        return;
      }
      
      // 통합된 API 서비스를 통해 다중 종목 구독
      final domesticStocks = stocks.where((code) => _getMarketType(code) == 'DOMESTIC').toList();
      final nasdaqStocks = stocks.where((code) => _getMarketType(code) == 'NASDAQ').toList();
      
      // 국내주식 구독
      if (domesticStocks.isNotEmpty) {
        final approvalKey = await _getWebSocketAccessKey();
        if (approvalKey != null) {
          final results = await unifiedApiService.subscribeMultipleStocks(
            channel: _channel!,
            stockCodes: domesticStocks,
            market: 'KOREA',
            approvalKey: approvalKey,
          );
        
          for (final entry in results.entries) {
            if (entry.value) {
              _subscribedStocks.add(entry.key);
              // 초기 가격 저장
              final currentPrice = await _getCurrentPrice(entry.key);
              if (currentPrice > 0) {
                _lastPrices[entry.key] = currentPrice;
              }
            }
          }
        }
      }
      
      // 나스닥 종목 구독
      if (nasdaqStocks.isNotEmpty) {
        final approvalKey = await _getWebSocketAccessKey();
        if (approvalKey != null) {
          final results = await unifiedApiService.subscribeMultipleStocks(
            channel: _channel!,
            stockCodes: nasdaqStocks,
            market: 'NASDAQ',
            approvalKey: approvalKey,
          );
        
          for (final entry in results.entries) {
            if (entry.value) {
              _subscribedStocks.add(entry.key);
              // 초기 가격 저장
              final currentPrice = await _getCurrentPrice(entry.key);
              if (currentPrice > 0) {
                _lastPrices[entry.key] = currentPrice;
              }
            }
          }
        }
      }
      
      print('📊 ${stocks.length}개 종목 KIS WebSocket 구독 완료 (통합 API 서비스 사용)');
      
    } catch (e) {
      print('❌ 종목 구독 실패: $e');
    }
  }

  /// WebSocket 메시지 처리
  void _handleWebSocketMessage(dynamic message) {
    try {
      final unifiedApiService = KisUnifiedApiService();
      
      // 통합된 API 서비스를 통해 메시지 파싱
      final messageData = unifiedApiService.parseWebSocketMessage(message);
      if (messageData == null) {
        return;
      }
      
      // PING 메시지 처리
      if (unifiedApiService.isPingMessage(messageData)) {
        _handlePingMessage();
        return;
      }
      
      // 실시간 체결가 데이터 처리
      final priceData = unifiedApiService.parseRealtimePriceData(messageData);
      if (priceData != null) {
        final stockCode = priceData['stockCode'] as String;
        final price = priceData['currentPrice'] as double;
        final timestamp = DateTime.now();
        
        // 가격 업데이트
        _updatePrice(stockCode, price, timestamp);
        
        // 가격 변동 체크
        _checkPriceChange(stockCode, price);
      }
      
    } catch (e) {
      print('❌ WebSocket 메시지 처리 실패: $e');
    }
  }
  
  /// PING 메시지 처리 (비동기)
  void _handlePingMessage() {
    _sendPong().catchError((e) {
      print('❌ PONG 메시지 전송 실패: $e');
    });
  }

  /// 가격 업데이트
  Future<void> _updatePrice(String stockCode, double price, DateTime timestamp) async {
    try {
      // DB에 가격 저장
      await _priceRepo.savePrice(
        stockCode: stockCode,
        price: price,
        timestamp: timestamp,
      );
      
      // 스트림으로 가격 전송
      _priceController.add({
        'stockCode': stockCode,
        'price': price,
        'timestamp': timestamp,
      });
      
      // 보유종목 업데이트
      await _updateHoldingPrice(stockCode, price);
      
    } catch (e) {
      print('❌ 가격 업데이트 실패: $stockCode - $e');
    }
  }

  /// 가격 변동 체크 및 시그널 재분석
  Future<void> _checkPriceChange(String stockCode, double currentPrice) async {
    try {
      final lastPrice = _lastPrices[stockCode];
      if (lastPrice == null || lastPrice <= 0) {
        _lastPrices[stockCode] = currentPrice;
        return;
      }
      
      // 가격 변동률 계산
      final priceChange = (currentPrice - lastPrice) / lastPrice;
      
      // 임계값 이상 변동 시 시그널 재분석
      if (priceChange.abs() >= _priceChangeThreshold) {
        print('📈 가격 변동 감지: $stockCode ${(priceChange * 100).toStringAsFixed(2)}%');
        
        // 시그널 재분석
        await _reanalyzeSignals(stockCode, currentPrice);
        
        // 알림 발송
        await _sendPriceChangeNotification(stockCode, currentPrice, priceChange);
      }
      
      _lastPrices[stockCode] = currentPrice;
      
    } catch (e) {
      print('❌ 가격 변동 체크 실패: $stockCode - $e');
    }
  }

  /// 시그널 재분석 (투자스타일 파라미터 적용)
  Future<void> _reanalyzeSignals(String stockCode, double currentPrice) async {
    try {
      // 자동매매 상태 확인 (시그널 분석은 계속 실행)
      final isAutoTradingEnabled = await AppDataManager.instance.getAutoTradingStatus();
      print('📊 실시간 시그널 분석 시작: $stockCode (자동매매: ${isAutoTradingEnabled ? "ON" : "OFF"})');
      
      // 자동매매가 OFF이면 시그널 분석만 하고 거래는 하지 않음
      if (!isAutoTradingEnabled) {
        print('⚠️ 자동매매 OFF - 시그널 분석만 수행 (거래 없음)');
      }
      
      // 현재 투자스타일 파라미터 가져오기
      final currentStyle = _styleManager.currentStyle;
      final styleParams = await _styleManager.getStyleParameters(currentStyle);
      
      print('📊 실시간 시그널 재분석 ($stockCode):');
      print('   - 투자스타일: ${_getStyleName(currentStyle)}');
      print('   - 매수 임계값: ${styleParams['buyThreshold']}');
      print('   - 매도 임계값: ${styleParams['sellThreshold']}');
      
      // AI 분석 서비스로 시그널 재분석 (투자스타일 파라미터 적용)
      final analysis = await _unifiedAnalysis.analyzeStock(
        stockCode,
        currentPrice: currentPrice,
        prevClose: _lastPrices[stockCode] ?? currentPrice,
        volume: 0,
        highPrice: currentPrice,
        lowPrice: currentPrice,
        openPrice: currentPrice,
      );
      
      // 실시간 시그널은 AutoTradingCycle에서 처리하므로 여기서는 건너뜀
      // if (analysis != null && (analysis['signal'] == '매수' || analysis['signal'] == '매도')) {
      //   // 실시간 시그널 로직은 AutoTradingCycle으로 이동됨
      // }
      
    } catch (e) {
      print('❌ 시그널 재분석 실패: $stockCode - $e');
    }
  }

  /// 실시간 시그널 저장
  Future<void> _saveRealtimeSignal(String stockCode, Map<String, dynamic> analysis, double price) async {
    try {
      final signalRepo = AppDataManager.instance.signalHistoryRepository;
      
      await signalRepo.saveSignal(
        stockCode: stockCode,
        signalType: analysis['signal']?.toString() ?? '정보',
        signalStrength: (analysis['confidence'] as num?)?.toDouble() ?? 0.0,
        price: price,
        volume: 0.0,
        confidence: (analysis['confidence'] as num?)?.toDouble() ?? 0.0,
        memo: 'Realtime_${analysis['investmentStyle'] ?? ''}',
      );
      
    } catch (e) {
      print('❌ 실시간 시그널 저장 실패: $stockCode - $e');
    }
  }

  /// 보유종목 가격 업데이트
  Future<void> _updateHoldingPrice(String stockCode, double price) async {
    try {
      final holdingsRepo = AppDataManager.instance.holdingsRepository;
      final holding = await holdingsRepo.getHolding(stockCode);
      
      if (holding != null) {
        final quantity = holding['quantity'] as int? ?? 0;
        final avgPrice = holding['avgPrice'] as double? ?? 0.0;
        
        if (quantity > 0 && avgPrice > 0) {
          final profitRate = ((price - avgPrice) / avgPrice) * 100;
          final currentValue = price * quantity;
          
          await holdingsRepo.updateHolding(
            stockCode: stockCode,
            currentPrice: price,
            profitRate: profitRate,
            currentValue: currentValue,
            updatedAt: DateTime.now(),
          );
        }
      }
      
    } catch (e) {
      print('❌ 보유종목 가격 업데이트 실패: $stockCode - $e');
    }
  }

  /// 가격 변동 알림 발송 (옵션)
  Future<void> _sendPriceChangeNotification(String stockCode, double currentPrice, double priceChange) async {
    try {
      // 선택적으로 로컬 알림 연동 가능
    } catch (e) {
      // 무시
    }
  }

  // 실시간 시그널 알림 발송은 AutoTradingCycle에서 처리하므로 주석 처리
  // /// 실시간 시그널 알림 발송
  // Future<void> _sendRealtimeSignalNotification(String stockCode, Map<String, dynamic> analysis, double price) async {
  //   // 실시간 시그널 알림 발송 로직은 AutoTradingCycle으로 이동됨
  // }

  /// 현재 가격 조회
  Future<double> _getCurrentPrice(String stockCode) async {
    try {
      final data = await KisUnifiedApiService().getStockPrice(stockCode);
      return (data?['currentPrice'] as num?)?.toDouble() ?? 0.0;
    } catch (e) {
      print('❌ 현재 가격 조회 실패: $stockCode - $e');
      return 0.0;
    }
  }

  /// 종목명 조회
  Future<String> _getStockName(String stockCode) async {
    try {
      final info = AppDataManager.instance.getStockInfo(stockCode);
      final stockName = info?['stockName'];
      if (stockName != null && stockName is String && stockName.isNotEmpty) {
        return stockName;
      }
      return stockCode;
    } catch (e) {
      print('❌ 종목명 조회 실패: $stockCode - $e');
      return stockCode;
    }
  }

  /// 시장 타입 판별
  String _getMarketType(String stockCode) {
    if (RegExp(r'^[A-Z]{1,6}$').hasMatch(stockCode)) {
      return 'NASDAQ';
    } else if (stockCode.startsWith('005') || stockCode.startsWith('000')) {
      return 'KOSPI';
    } else {
      return 'KOSDAQ';
    }
  }

  /// 하트비트 시작
  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isConnected) {
        _sendHeartbeat();
      }
    });
  }

  /// PONG 응답 전송 (통합된 API 서비스 사용)
  Future<void> _sendPong() async {
    if (_isConnected && _channel != null) {
      final unifiedApiService = KisUnifiedApiService();
      final approvalKey = await _getWebSocketAccessKey();
      
      if (approvalKey != null) {
        await unifiedApiService.sendPongMessage(_channel!, approvalKey);
      }
    }
  }

  /// 하트비트 전송 (사용 안함 - KIS는 PING/PONG 방식)
  void _sendHeartbeat() {
    // KIS WebSocket에서는 서버에서 PING을 보내고 클라이언트가 PONG으로 응답
    // 별도 하트비트 불필요
  }

  /// 연결 해제 처리
  void _handleDisconnection() {
    _isConnected = false;
    _scheduleReconnect();
  }

  /// 재연결 스케줄링
  void _scheduleReconnect() {
    if (_reconnectTimer != null) return;
    
    _reconnectTimer = Timer(const Duration(seconds: 5), () async {
      _reconnectTimer = null;
      if (!_isConnected && !_isConnecting) {
        print('🔄 실시간 가격 서비스 재연결 시도...');
        await start();
      }
    });
  }

  /// 서비스 중지
  Future<void> stop() async {
    try {
      _isConnected = false;
      _isConnecting = false;
      
      _heartbeatTimer?.cancel();
      _reconnectTimer?.cancel();
      _fallbackPriceTimer?.cancel(); // 폴백 타이머 중지
      
      // 통합된 API 서비스를 통해 WebSocket 연결 종료
      final unifiedApiService = KisUnifiedApiService();
      await unifiedApiService.closeWebSocketConnection(_channel);
      _channel = null;
      
      _subscribedStocks.clear();
      _lastPrices.clear();
      
      print('🛑 실시간 가격 서비스 중지');
      
    } catch (e) {
      print('❌ 실시간 가격 서비스 중지 실패: $e');
    }
  }

  /// 연결 상태 확인
  bool get isConnected => _isConnected;
  
  /// 구독 중인 종목 수
  int get subscribedCount => _subscribedStocks.length;
  
  /// 스트림 해제
  void dispose() {
    _priceController.close();
  }

  /// 폴백 현재가 조회 타이머 시작 (5초마다)
  void _startFallbackPriceTimer(Set<String> stocks) {
    _fallbackPriceTimer?.cancel();
    _fallbackPriceTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        print('📊 폴백 현재가 조회 시작 (${stocks.length}개 종목)');
        
        for (final stockCode in stocks) {
          try {
            await _updatePriceFromApi(stockCode);
            
            // API 호출 간격 조절 (KIS API 제한 고려)
            await Future.delayed(const Duration(milliseconds: 200));
          } catch (e) {
            print('⚠️ 폴백 현재가 조회 실패: $stockCode - $e');
          }
        }
        
        print('✅ 폴백 현재가 조회 완료');
      } catch (e) {
        print('❌ 폴백 현재가 조회 실패: $e');
      }
    });
    
    print('🔄 폴백 현재가 조회 타이머 시작 (5초 간격)');
  }

  /// API를 통한 현재가 조회 및 업데이트
  Future<void> _updatePriceFromApi(String stockCode) async {
    try {
      final unifiedApiService = KisUnifiedApiService();
      final isNasdaq = RegExp(r'^[A-Z]{1,5}$').hasMatch(stockCode);
      
      Map<String, dynamic>? priceData;
      if (isNasdaq) {
        priceData = await unifiedApiService.getOverseasCurrentPrice(stockCode);
      } else {
        priceData = await unifiedApiService.getDomesticCurrentPrice(stockCode);
      }
      
      if (priceData != null && priceData.isNotEmpty) {
        final currentPrice = (priceData['currentPrice'] ?? 0.0).toDouble();
        if (currentPrice > 0) {
          final timestamp = DateTime.now();
          
          // 가격 업데이트
          await _updatePrice(stockCode, currentPrice, timestamp);
          
          // 가격 변동 체크
          _checkPriceChange(stockCode, currentPrice);
          
          print('📊 폴백 현재가 업데이트: $stockCode -> $currentPrice');
        }
      }
    } catch (e) {
      print('❌ API 현재가 조회 실패: $stockCode - $e');
    }
  }

  /// 투자스타일 이름 반환
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
}
