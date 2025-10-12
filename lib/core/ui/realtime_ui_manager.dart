import 'dart:async';
import 'package:flutter/material.dart';
import '../data/app_data_manager.dart';
import '../database/repositories/holdings_repository.dart';
import '../database/repositories/signal_history_repository.dart';
import '../database/repositories/notification_history_repository.dart';
import '../database/repositories/trade_history_repository.dart';
import '../services/realtime_price_service.dart';
import '../database/repositories/stock_prices_repository.dart';

/// 실시간 UI 업데이트 관리자 (사일런트 리프레시)
class RealtimeUIManager {
  static final RealtimeUIManager _instance = RealtimeUIManager._internal();
  factory RealtimeUIManager() => _instance;
  RealtimeUIManager._internal();

  // Stream Controllers
  final StreamController<List<Map<String, dynamic>>> _holdingsController = 
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final StreamController<List<Map<String, dynamic>>> _signalsController = 
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final StreamController<List<Map<String, dynamic>>> _notificationsController = 
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final StreamController<List<Map<String, dynamic>>> _tradesController = 
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final StreamController<Map<String, double>> _priceUpdatesController = 
      StreamController<Map<String, double>>.broadcast();
  final StreamController<Map<String, dynamic>> _portfolioStatsController = 
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<List<Map<String, dynamic>>> _topStocksController = 
      StreamController<List<Map<String, dynamic>>>.broadcast();

  // Streams
  Stream<List<Map<String, dynamic>>> get holdingsStream => _holdingsController.stream;
  Stream<List<Map<String, dynamic>>> get signalsStream => _signalsController.stream;
  Stream<List<Map<String, dynamic>>> get notificationsStream => _notificationsController.stream;
  Stream<List<Map<String, dynamic>>> get tradesStream => _tradesController.stream;
  Stream<Map<String, double>> get priceUpdatesStream => _priceUpdatesController.stream;
  Stream<Map<String, dynamic>> get portfolioStatsStream => _portfolioStatsController.stream;
  Stream<List<Map<String, dynamic>>> get topStocksStream => _topStocksController.stream;

  // 타이머
  Timer? _updateTimer;
  bool _isInitialized = false;
  
  // 사일런트 리프레시를 위한 상태 관리
  bool _isSilentRefresh = false;
  Map<String, dynamic> _lastHoldingsData = {};
  Map<String, dynamic> _lastSignalsData = {};
  Map<String, dynamic> _lastNotificationsData = {};
  Map<String, dynamic> _lastTradesData = {};
  Map<String, dynamic> _lastTopStocksData = {};
  
  // 실시간 점수 서비스
  // final RealtimeScoreService _scoreService = RealtimeScoreService(); // Removed as per edit hint

  /// 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      print('🔄 실시간 UI 매니저 초기화 시작 (사일런트 리프레시)');
      
      // 실시간 가격 서비스 구독
      _subscribeToPriceUpdates();
      
      // 실시간 점수 서비스 구독
      // _subscribeToScoreUpdates(); // Removed as per edit hint
      
      // 주기적 업데이트 시작 (10초마다 - 사일런트)
      _startPeriodicUpdates();
      
      // 초기 데이터 로드
      await _loadInitialData();
      
      _isInitialized = true;
      print('✅ 실시간 UI 매니저 초기화 완료 (사일런트 리프레시)');
      
    } catch (e) {
      print('❌ 실시간 UI 매니저 초기화 실패: $e');
    }
  }

  /// 실시간 가격 업데이트 구독 (사일런트)
  void _subscribeToPriceUpdates() {
    AppDataManager.instance.realtimePriceService.priceStream.listen(
      (priceData) {
        final stockCode = priceData['stockCode'] as String;
        final price = priceData['price'] as double;
        
        // 가격 업데이트 브로드캐스트 (사일런트)
        _priceUpdatesController.add({stockCode: price});
        
        // 보유종목 가격 업데이트 (사일런트)
        _updateHoldingPriceSilent(stockCode, price);
        
        // 포트폴리오 통계 업데이트 (사일런트)
        _updatePortfolioStatsSilent();
      },
      onError: (error) {
        print('❌ 실시간 가격 스트림 오류: $error');
      },
    );
  }

  /// 실시간 점수 업데이트 구독 (사일런트)
  // void _subscribeToScoreUpdates() { // Removed as per edit hint
  //   _scoreService.topStocksStream.listen( // Removed as per edit hint
  //     (topStocks) { // Removed as per edit hint
  //       // 변경사항이 있을 때만 스트림 발행 (깜빡임 방지) // Removed as per edit hint
  //       if (_hasDataChanged(_lastTopStocksData, topStocks)) { // Removed as per edit hint
  //         _lastTopStocksData = _createDataSnapshot(topStocks); // Removed as per edit hint
  //         _topStocksController.add(topStocks); // Removed as per edit hint
  //         print('📊 상위 점수 종목 사일런트 업데이트: ${topStocks.length}개'); // Removed as per edit hint
  //       } // Removed as per edit hint
  //     }, // Removed as per edit hint
  //     onError: (error) { // Removed as per edit hint
  //       print('❌ 실시간 점수 스트림 오류: $error'); // Removed as per edit hint
  //     }, // Removed as per edit hint
  //   ); // Removed as per edit hint
  // } // Removed as per edit hint

  /// 주기적 업데이트 시작 (Firestore 구독으로 대체)
  void _startPeriodicUpdates() {
    // Firestore 구독으로 대체되므로 주기적 API 호출 비활성화
    print('🔄 주기적 업데이트 비활성화 - Firestore 구독 사용');
  }

  /// 초기 데이터 로드
  Future<void> _loadInitialData() async {
    try {
      await Future.wait([
        _refreshHoldingsSilent(),
        _refreshSignalsSilent(),
        _refreshNotificationsSilent(),
        _refreshTradesSilent(),
        _updatePortfolioStatsSilent(),
        _refreshTopStocksSilent(),
      ]);
    } catch (e) {
      print('❌ 초기 데이터 로드 실패: $e');
    }
  }

  /// 모든 데이터 새로고침 (사일런트)
  Future<void> _refreshAllDataSilent() async {
    try {
      // 병렬로 실행하여 성능 향상
      await Future.wait([
        _refreshHoldingsSilent(),
        _refreshSignalsSilent(),
        _refreshNotificationsSilent(),
        _refreshTradesSilent(),
        _refreshTopStocksSilent(),
      ], eagerError: false); // 개별 실패가 전체를 중단시키지 않도록
    } catch (e) {
      print('❌ 전체 데이터 새로고침 실패: $e');
    }
  }

  /// 보유종목 데이터 새로고침 (사일런트)
  Future<void> _refreshHoldingsSilent() async {
    try {
      final holdings = await AppDataManager.instance.holdingsRepository.getAllHoldings();
      
      // 변경사항이 있을 때만 스트림 발행 (깜빡임 방지)
      if (_hasDataChanged(_lastHoldingsData, holdings)) {
        _lastHoldingsData = _createDataSnapshot(holdings);
        _holdingsController.add(holdings);
        print('📊 보유종목 사일런트 업데이트: ${holdings.length}개');
      }
    } catch (e) {
      print('❌ 보유종목 새로고침 실패: $e');
    }
  }

  /// 시그널 데이터 새로고침 (사일런트)
  Future<void> _refreshSignalsSilent() async {
    try {
      final signals = await AppDataManager.instance.signalHistoryRepository.getRecentSignals(limit: 50);
      
      // 변경사항이 있을 때만 스트림 발행 (깜빡임 방지)
      if (_hasDataChanged(_lastSignalsData, signals)) {
        _lastSignalsData = _createDataSnapshot(signals);
        _signalsController.add(signals);
        print('📊 시그널 사일런트 업데이트: ${signals.length}개');
      }
    } catch (e) {
      print('❌ 시그널 새로고침 실패: $e');
    }
  }

  /// 알림 데이터 새로고침 (사일런트)
  Future<void> _refreshNotificationsSilent() async {
    try {
      final notifications = await AppDataManager.instance.notificationHistoryRepository.getRecentNotifications(limit: 50);
      
      // 변경사항이 있을 때만 스트림 발행 (깜빡임 방지)
      if (_hasDataChanged(_lastNotificationsData, notifications)) {
        _lastNotificationsData = _createDataSnapshot(notifications);
        _notificationsController.add(notifications);
        print('📊 알림 사일런트 업데이트: ${notifications.length}개');
      }
    } catch (e) {
      print('❌ 알림 새로고침 실패: $e');
    }
  }

  /// 거래 내역 새로고침 (사일런트)
  Future<void> _refreshTradesSilent() async {
    try {
      final trades = await AppDataManager.instance.tradeHistoryRepository.getRecentTrades(limit: 50);
      
      // 변경사항이 있을 때만 스트림 발행 (깜빡임 방지)
      if (_hasDataChanged(_lastTradesData, trades)) {
        _lastTradesData = _createDataSnapshot(trades);
        _tradesController.add(trades);
        print('📊 거래내역 사일런트 업데이트: ${trades.length}개');
      }
    } catch (e) {
      print('❌ 거래 내역 새로고침 실패: $e');
    }
  }

  /// 보유종목 가격 업데이트 (사일런트)
  Future<void> _updateHoldingPriceSilent(String stockCode, double newPrice) async {
    try {
      final holdings = await AppDataManager.instance.holdingsRepository.getAllHoldings();
      final holding = holdings.firstWhere(
        (h) => h['stockCode'] == stockCode,
        orElse: () => <String, dynamic>{},
      );
      
      if (holding.isNotEmpty) {
        final quantity = holding['quantity'] as int? ?? 0;
        final avgPrice = holding['avgPrice'] as double? ?? 0.0;
        
        if (quantity > 0 && avgPrice > 0) {
          final profitRate = ((newPrice - avgPrice) / avgPrice) * 100;
          final currentValue = quantity * newPrice;
          
          // DB 업데이트 (사일런트)
          await AppDataManager.instance.holdingsRepository.updateHolding(
            stockCode: stockCode,
            currentPrice: newPrice,
            profitRate: profitRate,
            currentValue: currentValue,
          );
          
          // UI 업데이트 (사일런트)
          await _refreshHoldingsSilent();
        }
      }
    } catch (e) {
      print('❌ 보유종목 가격 업데이트 실패: $stockCode - $e');
    }
  }

  /// 포트폴리오 통계 업데이트 (사일런트)
  Future<void> _updatePortfolioStatsSilent() async {
    try {
      final holdings = await AppDataManager.instance.holdingsRepository.getAllHoldings();
      
      double totalValue = 0.0;
      double totalProfit = 0.0;
      double totalCost = 0.0;
      
      for (final holding in holdings) {
        final quantity = holding['quantity'] as int? ?? 0;
        final currentPrice = holding['currentPrice'] as double? ?? 0.0;
        final avgPrice = holding['avgPrice'] as double? ?? 0.0;
        
        if (quantity > 0 && currentPrice > 0) {
          final currentValue = quantity * currentPrice;
          final costValue = quantity * avgPrice;
          
          totalValue += currentValue;
          totalCost += costValue;
          totalProfit += (currentValue - costValue);
        }
      }
      
      final profitRate = totalCost > 0 ? (totalProfit / totalCost) * 100 : 0.0;
      
      final stats = {
        'totalValue': totalValue,
        'totalProfit': totalProfit,
        'totalCost': totalCost,
        'profitRate': profitRate,
        'holdingsCount': holdings.length,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };
      
      _portfolioStatsController.add(stats);
      
    } catch (e) {
      print('❌ 포트폴리오 통계 업데이트 실패: $e');
    }
  }

  /// 데이터 변경 여부 확인 (깜빡임 방지)
  bool _hasDataChanged(Map<String, dynamic> lastData, List<Map<String, dynamic>> newData) {
    try {
      // 데이터 개수 비교
      if (lastData['count'] != newData.length) {
        return true;
      }
      
      // 주요 필드 비교 (첫 번째와 마지막 항목만)
      if (newData.isNotEmpty) {
        final firstItem = newData.first;
        final lastItem = newData.last;
        
        final lastFirstItem = lastData['first'];
        final lastLastItem = lastData['last'];
        
        if (lastFirstItem == null || lastLastItem == null) {
          return true;
        }
        
        // 주요 필드 비교 (가격, 수량, 시간 등)
        final keyFields = ['currentPrice', 'quantity', 'updatedAt', 'triggered_at', 'created_at'];
        
        for (final field in keyFields) {
          if (firstItem.containsKey(field) && lastFirstItem.containsKey(field)) {
            if (firstItem[field] != lastFirstItem[field]) {
              return true;
            }
          }
          if (lastItem.containsKey(field) && lastLastItem.containsKey(field)) {
            if (lastItem[field] != lastLastItem[field]) {
              return true;
            }
          }
        }
      }
      
      return false;
    } catch (e) {
      // 비교 실패 시 안전하게 true 반환
      return true;
    }
  }

  /// 데이터 스냅샷 생성
  Map<String, dynamic> _createDataSnapshot(List<Map<String, dynamic>> data) {
    if (data.isEmpty) {
      return {'count': 0, 'first': null, 'last': null};
    }
    
    return {
      'count': data.length,
      'first': data.first,
      'last': data.last,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  /// 특정 종목 강제 새로고침 (사일런트)
  Future<void> refreshStock(String stockCode) async {
    try {
      // 보유종목에서 해당 종목 찾아서 업데이트
      final holdings = await AppDataManager.instance.holdingsRepository.getAllHoldings();
      final holding = holdings.firstWhere(
        (h) => h['stockCode'] == stockCode,
        orElse: () => <String, dynamic>{},
      );
      
      if (holding.isNotEmpty) {
        await _refreshHoldingsSilent();
      }
      
      // 시그널에서 해당 종목 찾아서 업데이트
      await _refreshSignalsSilent();
      
    } catch (e) {
      print('❌ 종목 강제 새로고침 실패: $stockCode - $e');
    }
  }

  /// 특정 탭 데이터 새로고침 (사일런트)
  Future<void> refreshTab(String tabName) async {
    try {
      switch (tabName.toLowerCase()) {
        case 'holdings':
        case '보유종목':
          await _refreshHoldingsSilent();
          break;
        case 'signals':
        case '시그널':
          await _refreshSignalsSilent();
          break;
        case 'notifications':
        case '알림':
          await _refreshNotificationsSilent();
          break;
        case 'trades':
        case '거래내역':
          await _refreshTradesSilent();
          break;
        case 'portfolio':
        case '포트폴리오':
          await _updatePortfolioStatsSilent();
          break;
        case 'topstocks':
        case '상위점수종목':
          await _refreshTopStocksSilent();
          break;
        default:
          await _refreshAllDataSilent();
      }
    } catch (e) {
      print('❌ 탭 새로고침 실패: $tabName - $e');
    }
  }

  /// 실시간 업데이트 일시정지
  void pauseUpdates() {
    _updateTimer?.cancel();
    print('⏸️ 실시간 UI 업데이트 일시정지');
  }

  /// 실시간 업데이트 재개
  void resumeUpdates() {
    _startPeriodicUpdates();
    print('▶️ 실시간 UI 업데이트 재개');
  }

  /// 사일런트 리프레시 상태 확인
  bool get isSilentRefresh => _isSilentRefresh;

  /// 상위 점수 종목 새로고침 (사일런트)
  Future<void> _refreshTopStocksSilent() async {
    try {
      // 실시간 점수 서비스에서 상위 종목 조회
      // final topStocks = await _scoreService.getTopStocks( // Removed as per edit hint
      //   limit: 100, // Removed as per edit hint
      //   minScore: 0.3, // Removed as per edit hint
      // ); // Removed as per edit hint
      
      // 변경사항이 있을 때만 스트림 발행 (깜빡임 방지)
      // if (_hasDataChanged(_lastTopStocksData, topStocks)) { // Removed as per edit hint
      //   _lastTopStocksData = _createDataSnapshot(topStocks); // Removed as per edit hint
      //   _topStocksController.add(topStocks); // Removed as per edit hint
      //   print('📊 상위 점수 종목 사일런트 업데이트: ${topStocks.length}개'); // Removed as per edit hint
      // } // Removed as per edit hint
    } catch (e) {
      print('❌ 상위 점수 종목 새로고침 실패: $e');
    }
  }

  /// 정리
  void dispose() {
    _updateTimer?.cancel();
    // _scoreService.stop(); // Removed as per edit hint
    _holdingsController.close();
    _signalsController.close();
    _notificationsController.close();
    _tradesController.close();
    _priceUpdatesController.close();
    _portfolioStatsController.close();
    _topStocksController.close();
  }
}
