import 'dart:async';
import '../services/local_notification_manager.dart';
import '../data/app_data_manager.dart';
import '../database/repositories/notification_history_repository.dart';
import '../data/app_data_manager.dart';
import '../trading/market_time_validator.dart';
import '../api/kis_unified_api_service.dart';
// import '../trading/auto_trading_service.dart';

/// 시그널 상태 추적 클래스
class SignalTracker {
  static final SignalTracker _instance = SignalTracker._internal();
  factory SignalTracker() => _instance;
  SignalTracker._internal();

  // 종목별 시그널 상태 저장
  final Map<String, String> _signalStates = {};
  final LocalNotificationManager _notificationManager = LocalNotificationManager();
  final NotificationHistoryRepository _notificationRepo = NotificationHistoryRepository();

  /// 시그널 업데이트
  Future<void> updateSignal(String stockCode, String stockName, String newSignal) async {
    print('🎯 시그널 업데이트 시작...');
    print('📊 시그널 정보:');
    print('   - 종목코드: $stockCode');
    print('   - 종목명: $stockName');
    print('   - 새로운 시그널: $newSignal');
    
    final previousSignal = _signalStates[stockCode];
    print('📊 이전 시그널: $previousSignal');
    
    // 시그널 변화 감지
    if (previousSignal != newSignal) {
      print('🎯 시그널 변화 감지: $stockCode ($stockName) - $previousSignal → $newSignal');
      
      // 알림 표시
      print('📱 시그널 변화 알림 표시 중...');
      await _showSignalChangeNotification(stockCode, stockName, previousSignal, newSignal);
      
      // 상태 업데이트
      _signalStates[stockCode] = newSignal;
      print('✅ 시그널 상태 업데이트 완료: $stockCode = $newSignal');
      
      // 시그널 변화 시 자동매매 실행 (거래 시간 확인)
      if (newSignal == '매수' || newSignal == '매도') {
        print('🤖 매매 시그널 감지 - 자동매매 실행 검토 중...');
        try {
          // 시장 구분 및 거래 시간 확인
          final market = MarketTimeValidator.instance.getMarketFromSymbol(stockCode);
          print('📊 시장 구분: $stockCode → $market');
          
          // 거래 시간 외 매매 신호 차단 - 임시 주석 처리
          /*
          if (MarketTimeValidator.instance.shouldBlockTradingSignal(market, newSignal == '매수' ? 'buy' : 'sell')) {
            print('⚠️ [SignalTracker] 거래 시간 외: $market 시장 $newSignal 신호 차단');
            return;
          }
          */
          
          print('🔧 [SignalTracker] 거래 시간 체크 임시 비활성화 - $market 시장 $newSignal 신호 허용');
          
          // 자동매매 상태 확인
          print('🔍 자동매매 상태 확인 중...');
          final isAutoTradingEnabled = await AppDataManager.instance.getAutoTradingStatus();
          print('🔍 시그널 변화 시 자동매매 상태 확인: enabled=$isAutoTradingEnabled');
          
          if (isAutoTradingEnabled) {
            // 자동매매는 AutoTradingCycle에서 처리하므로 여기서는 건너뜀
            print('⚠️ 시그널 변화 시 자동매매는 AutoTradingCycle에서 처리됨: $stockCode $newSignal');
          } else {
            print('⚠️ 자동매매가 비활성화되어 있어 시그널 변화 시 거래를 실행하지 않습니다.');
          }
        } catch (e) {
          print('❌ 시그널 변화 시 자동매매 실행 실패: $stockCode - $e');
          print('📊 오류 상세:');
          print('   - 오류 타입: ${e.runtimeType}');
          print('   - 오류 메시지: $e');
        }
      } else {
        print('📊 매매 시그널이 아님: $newSignal');
      }
    } else {
      print('📊 시그널 변화 없음: $stockCode - $newSignal');
    }
  }

  /// 관심종목 추가 시 초기 시그널 알림
  Future<void> onWatchlistAdded(String stockCode, String stockName, String currentSignal) async {
    print('📌 관심종목 추가 시그널 알림: $stockCode ($stockName) - $currentSignal');
    
    // 최근 1분 내에 같은 종목의 관심종목 추가 알림이 있는지 확인
    final now = DateTime.now();
    final oneMinuteAgo = now.subtract(const Duration(minutes: 1));
    
    try {
      final recentNotifications = await _notificationRepo.getNotificationsByDateRange(oneMinuteAgo, now);
      final hasRecentNotification = recentNotifications.any((notification) =>
          notification['type'] == '관심종목 추가' && 
          notification['stock_code'] == stockCode);
      
      if (hasRecentNotification) {
        print('⚠️ 최근 1분 내에 이미 관심종목 추가 알림이 있었습니다: $stockCode');
        return;
      }
    } catch (e) {
      print('⚠️ 최근 알림 확인 실패: $e');
    }
    
    // 관심종목 추가 알림 표시 (설정 확인 없이 표시 - 중요 알림)
    await _notificationManager.showNotification(
      title: '📌 관심종목 추가',
      body: '$stockName($stockCode)이(가) 관심종목에 추가되었습니다.',
    );
    
    // 알림 DB 저장
    await _notificationRepo.addNotification(
      type: '관심종목 추가',
      stockCode: stockCode,
      stockName: stockName,
      message: '관심종목에 추가됨',
    );
    
    // 현재 시그널이 있으면 시그널 알림도 표시
    if (currentSignal.isNotEmpty && currentSignal != '관망') {
      print('📊 현재 시그널 알림도 표시: $currentSignal');
      await _notificationManager.showNotification(
        title: '📊 현재 시그널',
        body: '$stockName($stockCode): $currentSignal',
      );
    }
  }

  /// 시그널 변화 알림 표시
  Future<void> _showSignalChangeNotification(
    String stockCode, 
    String stockName, 
    String? previousSignal, 
    String newSignal
  ) async {
    String title;
    String body;
    // 최신 가격/점수 보강용
    final double resolvedPrice = await _resolveCurrentPrice(stockCode);
    final double? latestScore = await _resolveLatestScore(stockCode);
    final String reasonSuffix = latestScore != null ? ' (점수: ${latestScore.toStringAsFixed(3)})' : '';

    if (previousSignal == null || previousSignal.isEmpty || previousSignal == '관망') {
      // 새로운 시그널 생성
      if (newSignal == '매수') {
        title = '🟢 매수 시그널 생성';
        body = '$stockName($stockCode): 매수 기회가 감지되었습니다$reasonSuffix.';
      } else if (newSignal == '매도') {
        title = '🔴 매도 시그널 생성';
        body = '$stockName($stockCode): 매도 기회가 감지되었습니다$reasonSuffix.';
      } else {
        return; // 관망이면 알림 안함
      }
    } else if (newSignal == '관망' || newSignal.isEmpty) {
      // 시그널 사라짐
      if (previousSignal == '매수') {
        title = '🟢 매수 시그널 해제';
        body = '$stockName($stockCode): 매수 시그널이 해제되었습니다$reasonSuffix.';
      } else if (previousSignal == '매도') {
        title = '🔴 매도 시그널 해제';
        body = '$stockName($stockCode): 매도 시그널이 해제되었습니다$reasonSuffix.';
      } else {
        return;
      }
    } else if (previousSignal != newSignal) {
      // 시그널 전환 (매수 ↔ 매도)
      if (previousSignal == '매수' && newSignal == '매도') {
        title = '🔄 시그널 전환: 매수 → 매도';
        body = '$stockName($stockCode): 매수에서 매도로 시그널이 변경되었습니다$reasonSuffix.';
      } else if (previousSignal == '매도' && newSignal == '매수') {
        title = '🔄 시그널 전환: 매도 → 매수';
        body = '$stockName($stockCode): 매도에서 매수로 시그널이 변경되었습니다$reasonSuffix.';
      } else {
        return;
      }
    } else {
      return; // 변화 없음
    }

    // 알림 표시 (시그널 변화는 설정에 따라 표시)
    if (title.contains('매수 시그널')) {
      await _notificationManager.showBuySignalNotification(
        stockCode: stockCode,
        stockName: stockName,
        reason: '시그널 변화$reasonSuffix',
        price: resolvedPrice,
      );
    } else if (title.contains('매도 시그널')) {
      await _notificationManager.showSellSignalNotification(
        stockCode: stockCode,
        stockName: stockName,
        reason: '시그널 변화$reasonSuffix',
        price: resolvedPrice,
      );
    } else {
      // 기타 알림은 설정 확인 없이 표시
      await _notificationManager.showNotification(
        title: title,
        body: body,
      );
    }
  }

  // 최신 가격 보강: 캐시 → DB → API 순서, 실패 시 0.0
  Future<double> _resolveCurrentPrice(String stockCode) async {
    try {
      // 1) 메모리 캐시
      final cached = AppDataManager.instance.getCachedStockData(stockCode);
      final nowP = (cached['currentPrice'] as num?)?.toDouble() ?? 0.0;
      final prev = (cached['prevClose'] as num?)?.toDouble() ?? 0.0;
      if (nowP > 0) return nowP;
      if (prev > 0) return prev;

      // 2) DB
      final db = await AppDataManager.instance.getRealtimeDataFromDatabase(stockCode);
      final dbNow = (db?['currentPrice'] as num?)?.toDouble() ?? 0.0;
      final dbPrev = (db?['prevClose'] as num?)?.toDouble() ?? 0.0;
      if (dbNow > 0) return dbNow;
      if (dbPrev > 0) return dbPrev;

      // 3) API (가능할 때만)
      try {
        final kis = KisUnifiedApiService();
        final Map<String, dynamic>? api = await kis.getStockPrice(stockCode);
        if (api != null) {
          final apiNow = (api['currentPrice'] as num?)?.toDouble() ?? 0.0;
          final apiPrev = (api['prevClose'] as num?)?.toDouble() ?? 0.0;
          if (apiNow > 0) return apiNow;
          if (apiPrev > 0) return apiPrev;
        }
      } catch (_) {}
    } catch (_) {}
    return 0.0;
  }

  // 최근 종합점수 보강: 분석 결과 DB에서 조회
  Future<double?> _resolveLatestScore(String stockCode) async {
    try {
      final res = await AppDataManager.instance.getLatestAnalysisResultFromDatabase(stockCode);
      if (res == null) return null;
      final score = (res['comprehensive_score'] as num?)?.toDouble() ??
          (res['confidence_score'] as num?)?.toDouble();
      if (score == null) return null;
      return score;
    } catch (_) {
      return null;
    }
  }

  /// 종목 제거 시 상태 정리
  void removeStock(String stockCode) {
    _signalStates.remove(stockCode);
    print('🗑️ 시그널 추적에서 제거: $stockCode');
  }

  /// 현재 시그널 상태 조회
  String? getCurrentSignal(String stockCode) {
    return _signalStates[stockCode];
  }

  /// 모든 시그널 상태 조회
  Map<String, String> getAllSignals() {
    return Map.from(_signalStates);
  }

  /// 시그널 통계 조회
  Map<String, int> getSignalStats() {
    final stats = <String, int>{};
    for (final signal in _signalStates.values) {
      stats[signal] = (stats[signal] ?? 0) + 1;
    }
    return stats;
  }
}
