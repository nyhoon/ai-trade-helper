import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/repositories/trade_history_repository.dart';
import '../database/repositories/holdings_repository.dart';
import '../api/kis_unified_api_service.dart';
import '../data/app_data_manager.dart';

/// 거래 상태 열거형
enum TradeStatus {
  none,      // 거래 없음
  bought,    // 매수 완료
  sold,      // 매도 완료
  holding,   // 보유 중
  buyOrdered,  // 매수 주문 중
  sellOrdered  // 매도 주문 중
}

/// 거래 상태 추적 클래스
class TradeStatusTracker {
  static final TradeStatusTracker _instance = TradeStatusTracker._internal();
  factory TradeStatusTracker() => _instance;
  TradeStatusTracker._internal();

  // 종목별 거래 상태 저장
  final Map<String, TradeStatus> _tradeStates = {};
  
  // 상태 변경 알림을 위한 Stream
  final StreamController<Map<String, TradeStatus>> _statusChangeController = 
    StreamController<Map<String, TradeStatus>>.broadcast();
  Stream<Map<String, TradeStatus>> get statusChangeStream => _statusChangeController.stream;
  
  // Repository 인스턴스들
  final TradeHistoryRepository _tradeHistoryRepository = TradeHistoryRepository();
  final HoldingsRepository _holdingsRepository = HoldingsRepository();
  final KisUnifiedApiService _unifiedApiService = KisUnifiedApiService();



  /// 거래 상태 업데이트
  Future<void> updateTradeStatus(String stockCode, TradeStatus status) async {
    final previousStatus = _tradeStates[stockCode];
    
    if (previousStatus != status) {
      print('💰 거래 상태 변경: $stockCode - $previousStatus → $status');
      
      _tradeStates[stockCode] = status;
      
      // SharedPreferences에 저장
      await _saveTradeStatus(stockCode, status);
      
      // 상태 변경 알림
      _statusChangeController.add(Map.from(_tradeStates));
    }
  }

  /// 매수 완료 처리
  Future<void> markAsBought(String stockCode) async {
    await updateTradeStatus(stockCode, TradeStatus.bought);
  }

  /// 매도 완료 처리
  Future<void> markAsSold(String stockCode) async {
    await updateTradeStatus(stockCode, TradeStatus.sold);
  }

  /// 보유 중으로 표시
  Future<void> markAsHolding(String stockCode) async {
    await updateTradeStatus(stockCode, TradeStatus.holding);
  }

  /// 거래 상태 초기화
  Future<void> resetTradeStatus(String stockCode) async {
    await updateTradeStatus(stockCode, TradeStatus.none);
  }

  /// 현재 거래 상태 조회
  TradeStatus getTradeStatus(String stockCode) {
    return _tradeStates[stockCode] ?? TradeStatus.none;
  }

  /// 현재 거래 상태 조회 (별칭)
  TradeStatus getStatus(String stockCode) {
    return getTradeStatus(stockCode);
  }

  /// 주문 취소 처리
  Future<void> markAsCancelled(String stockCode) async {
    await updateTradeStatus(stockCode, TradeStatus.none);
  }

  /// 주문 체결 처리
  Future<void> markAsExecuted(String stockCode) async {
    await updateTradeStatus(stockCode, TradeStatus.bought);
  }

  /// 주문 실패 처리
  Future<void> markAsFailed(String stockCode) async {
    await updateTradeStatus(stockCode, TradeStatus.none);
  }

  /// 모든 거래 상태 조회
  Map<String, TradeStatus> getAllTradeStatuses() {
    return Map.from(_tradeStates);
  }

  /// 거래 상태에 따른 색상 반환
  static Color getStatusColor(TradeStatus status) {
    switch (status) {
      case TradeStatus.none:
        return Colors.transparent;
      case TradeStatus.bought:
        return Colors.red.withOpacity(0.2); // 투명한 빨간색
      case TradeStatus.sold:
        return Colors.blue.withOpacity(0.2); // 투명한 파란색
      case TradeStatus.holding:
        return Colors.green.withOpacity(0.2); // 투명한 초록색
      case TradeStatus.buyOrdered:
        return Colors.orange.withOpacity(0.2); // 투명한 주황색
      case TradeStatus.sellOrdered:
        return Colors.purple.withOpacity(0.2); // 투명한 보라색
    }
  }

  /// 거래 상태에 따른 텍스트 반환
  static String getStatusText(TradeStatus status) {
    switch (status) {
      case TradeStatus.none:
        return '';
      case TradeStatus.bought:
        return '매수 완료';
      case TradeStatus.sold:
        return '매도 완료';
      case TradeStatus.holding:
        return '보유 중';
      case TradeStatus.buyOrdered:
        return '매수 주문 중';
      case TradeStatus.sellOrdered:
        return '매도 주문 중';
      default:
        return '';
    }
  }

  /// 거래 상태에 따른 아이콘 반환
  static IconData getStatusIcon(TradeStatus status) {
    switch (status) {
      case TradeStatus.none:
        return Icons.circle_outlined;
      case TradeStatus.bought:
        return Icons.trending_up;
      case TradeStatus.sold:
        return Icons.trending_down;
      case TradeStatus.holding:
        return Icons.inventory;
      case TradeStatus.buyOrdered:
        return Icons.schedule;
      case TradeStatus.sellOrdered:
        return Icons.schedule;
    }
  }

  /// SharedPreferences에 거래 상태 저장
  Future<void> _saveTradeStatus(String stockCode, TradeStatus status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'trade_status_$stockCode';
      await prefs.setString(key, status.name);
    } catch (e) {
      print('❌ 거래 상태 저장 실패: $stockCode - $e');
    }
  }

  /// 거래 히스토리와 연동하여 거래 상태 동기화
  Future<void> syncTradeStatusesFromHistory() async {
    try {
      print('🔄 거래 히스토리와 상태 동기화 시작...');
      
      // 1. 거래 히스토리에서 최신 거래 정보 가져오기
      final tradeHistory = await _tradeHistoryRepository.getAllTradeHistory();
      
      // 2. 종목별로 최신 거래 상태 결정
      final Map<String, TradeStatus> newStates = {};
      
      for (final trade in tradeHistory) {
        final stockCode = trade['stockCode'] as String;
        final orderType = trade['orderType'] as String;
        final createdAt = DateTime.parse(trade['createdAt'] as String);
        
        // 이미 처리된 종목이면 더 최신 거래가 우선
        if (newStates.containsKey(stockCode)) {
          final existingTrade = tradeHistory.firstWhere(
            (t) => t['stockCode'] == stockCode && t['createdAt'] == newStates[stockCode].toString(),
          );
          final existingCreatedAt = DateTime.parse(existingTrade['createdAt'] as String);
          
          if (createdAt.isAfter(existingCreatedAt)) {
            // 더 최신 거래로 업데이트
            newStates[stockCode] = _getTradeStatusFromOrderType(orderType);
          }
        } else {
          // 새로운 종목
          newStates[stockCode] = _getTradeStatusFromOrderType(orderType);
        }
      }
      
      // 3. 현재 보유 종목과 비교하여 상태 업데이트
      await _updateStatesWithCurrentHoldings(newStates);
      
      // 4. 상태 업데이트
      _tradeStates.clear();
      _tradeStates.addAll(newStates);
      
      // 5. SharedPreferences에 저장
      for (final entry in _tradeStates.entries) {
        await _saveTradeStatus(entry.key, entry.value);
      }
      
      // 6. 상태 변경 알림
      _statusChangeController.add(Map.from(_tradeStates));
      
      print('✅ 거래 상태 동기화 완료: ${_tradeStates.length}개 종목');
    } catch (e) {
      print('❌ 거래 상태 동기화 실패: $e');
    }
  }

  /// 주문 타입에 따른 거래 상태 반환
  TradeStatus _getTradeStatusFromOrderType(String orderType) {
    switch (orderType) {
      case '매수':
        return TradeStatus.bought;
      case '매도':
        return TradeStatus.sold;
      default:
        return TradeStatus.none;
    }
  }

  /// 현재 보유 종목과 비교하여 상태 업데이트
  Future<void> _updateStatesWithCurrentHoldings(Map<String, TradeStatus> states) async {
    try {
      // ✅ API 직접 호출 비활성화 - Firestore 구독 사용
      print('🔍 [current 보호] TradeStatusTracker에서 API 직접 호출 비활성화');
      // 1. KIS API에서 현재 보유 종목 확인
      // final positions = await _unifiedApiService.getPositionsCompat();
      final positions = <Map<String, dynamic>>[];
      
      // 2. 보유 종목은 'holding' 상태로 업데이트
      for (final position in positions) {
        final stockCode = position['stockCode'] ?? position['stock_code'] ?? '';
        if (stockCode.isNotEmpty) {
          states[stockCode] = TradeStatus.holding;
        }
      }
      
      // 3. 로컬 DB에서도 보유 종목 확인
      final localHoldings = await _holdingsRepository.getHoldings();
      for (final holding in localHoldings) {
        final stockCode = holding['stock_code'] ?? holding['stockCode'] ?? '';
        if (stockCode.isNotEmpty) {
          states[stockCode] = TradeStatus.holding;
        }
      }
      
      print('📊 보유 종목 상태 업데이트 완료: ${positions.length}개');
    } catch (e) {
      print('⚠️ 보유 종목 상태 업데이트 실패: $e');
    }
  }

  /// SharedPreferences에서 거래 상태 로드
  Future<void> loadTradeStatuses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      for (final key in keys) {
        if (key.startsWith('trade_status_')) {
          final stockCode = key.substring('trade_status_'.length);
          final statusString = prefs.getString(key);
          
          if (statusString != null) {
            final status = TradeStatus.values.firstWhere(
              (e) => e.name == statusString,
              orElse: () => TradeStatus.none,
            );
            _tradeStates[stockCode] = status;
          }
        }
      }
      
      print('✅ 거래 상태 로드 완료: ${_tradeStates.length}개');
    } catch (e) {
      print('❌ 거래 상태 로드 실패: $e');
    }
  }

  /// 모든 거래 상태 초기화
  Future<void> clearAllTradeStatuses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      for (final key in keys) {
        if (key.startsWith('trade_status_')) {
          await prefs.remove(key);
        }
      }
      
      _tradeStates.clear();
      _statusChangeController.add({});
      
      print('🗑️ 모든 거래 상태 초기화 완료');
    } catch (e) {
      print('❌ 거래 상태 초기화 실패: $e');
    }
  }

  /// 특정 종목의 거래 상태 초기화
  Future<void> clearTradeStatus(String stockCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'trade_status_$stockCode';
      await prefs.remove(key);
      
      _tradeStates.remove(stockCode);
      _statusChangeController.add(Map.from(_tradeStates));
      
      print('🗑️ 거래 상태 초기화 완료: $stockCode');
    } catch (e) {
      print('❌ 거래 상태 초기화 실패: $stockCode - $e');
    }
  }

  /// 거래 히스토리 기반으로 상태 재구성
  Future<void> rebuildTradeStatuses() async {
    try {
      print('🔨 거래 상태 재구성 시작...');
      
      // 1. 기존 상태 초기화
      await clearAllTradeStatuses();
      
      // 2. 거래 히스토리에서 상태 재구성
      await syncTradeStatusesFromHistory();
      
      print('✅ 거래 상태 재구성 완료');
    } catch (e) {
      print('❌ 거래 상태 재구성 실패: $e');
    }
  }

  /// 보유 종목 자동 감지 및 상태 업데이트
  Future<void> autoDetectHoldings() async {
    try {
      print('🔍 보유 종목 자동 감지 시작...');
      
      // ✅ API 직접 호출 비활성화 - Firestore 구독 사용
      print('🔍 [current 보호] TradeStatusTracker에서 API 직접 호출 비활성화');
      // 1. KIS API에서 현재 보유 종목 확인
      // final positions = await _unifiedApiService.getPositionsCompat();
      final positions = <Map<String, dynamic>>[];
      
      // 2. 보유 종목을 'holding' 상태로 설정
      for (final position in positions) {
        final stockCode = position['stockCode'] ?? position['stock_code'] ?? '';
        if (stockCode.isNotEmpty) {
          await updateTradeStatus(stockCode, TradeStatus.holding);
          print('📊 보유 종목 감지: $stockCode');
        }
      }
      
      // 3. 로컬 DB와 동기화
      await _holdingsRepository.syncWithApi(positions);
      
      print('✅ 보유 종목 자동 감지 완료: ${positions.length}개');
    } catch (e) {
      print('❌ 보유 종목 자동 감지 실패: $e');
    }
  }

  /// 리소스 정리
  void dispose() {
    _statusChangeController.close();
  }
}
