/// KIS 통일 API 서비스 - WebSocket 관련 기능 확장
/// 
/// 실시간 데이터 수신, WebSocket 연결 관리 등 WebSocket 관련 API들을 담당
/// 
/// @author AI Assistant
/// @version 1.0.0
/// @since 2024-01-01

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'kis_unified_api_service.dart';

/// WebSocket 관련 기능 확장
extension KisUnifiedApiServiceWebSocket on KisUnifiedApiService {
  
  /// ========================================
  /// WebSocket 연결 관리
  /// ========================================
  
  /// WebSocket 연결 생성
  /// 
  /// 공식 가이드라인:
  /// - WebSocket URL: ws://ops.koreainvestment.com:21000 (개발계)
  /// - 인증 키 필요: approval_key
  Future<WebSocketChannel?> createWebSocketConnection({
    required String approvalKey,
    String wsUrl = 'ws://ops.koreainvestment.com:21000',
  }) async {
    try {
      print('🔌 [통일API] WebSocket 연결 시작: $wsUrl');
      
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      
      // 연결 확인을 위한 초기 메시지
      final initMessage = {
        'header': {
          'approval_key': approvalKey,
          'custtype': 'P', // 개인
          'tr_type': '1', // 등록
          'content-type': 'utf-8'
        },
        'body': {
          'input': {
            'tr_id': 'PINGPONG',
            'tr_key': '',
          }
        }
      };
      
      channel.sink.add(jsonEncode(initMessage));
      print('✅ [통일API] WebSocket 연결 성공');
      
      return channel;
    } catch (e) {
      print('❌ [통일API] WebSocket 연결 실패: $e');
      return null;
    }
  }
  
  /// WebSocket 연결 종료
  Future<void> closeWebSocketConnection(WebSocketChannel? channel) async {
    try {
      if (channel != null) {
        await channel.sink.close();
        print('✅ [통일API] WebSocket 연결 종료');
      }
    } catch (e) {
      print('❌ [통일API] WebSocket 연결 종료 오류: $e');
    }
  }
  
  /// ========================================
  /// 실시간 데이터 구독
  /// ========================================
  
  /// 종목 실시간 데이터 구독
  /// 
  /// 공식 가이드라인:
  /// - 국내주식: tr_id = 'H0STCNT0'
  /// - 해외주식: tr_id = 'HDFSCNT0'
  Future<bool> subscribeStockRealtimeData({
    required WebSocketChannel channel,
    required String stockCode,
    required String market, // 'DOMESTIC' or 'NASDAQ'
    required String approvalKey,
  }) async {
    try {
      print('📊 [통일API] 실시간 데이터 구독: $stockCode ($market)');
      
      final subscribeMessage = {
        'header': {
          'approval_key': approvalKey,
          'custtype': 'P', // 개인
          'tr_type': '1', // 등록
          'content-type': 'utf-8'
        },
        'body': {
          'input': {
            'tr_id': market == 'NASDAQ' ? 'HDFSCNT0' : 'H0STCNT0',
            'tr_key': stockCode,
          }
        }
      };
      
      channel.sink.add(jsonEncode(subscribeMessage));
      print('✅ [통일API] 실시간 데이터 구독 성공: $stockCode');
      
      return true;
    } catch (e) {
      print('❌ [통일API] 실시간 데이터 구독 실패: $e');
      return false;
    }
  }
  
  /// 종목 실시간 데이터 구독 해제
  Future<bool> unsubscribeStockRealtimeData({
    required WebSocketChannel channel,
    required String stockCode,
    required String market,
    required String approvalKey,
  }) async {
    try {
      print('📊 [통일API] 실시간 데이터 구독 해제: $stockCode ($market)');
      
      final unsubscribeMessage = {
        'header': {
          'approval_key': approvalKey,
          'custtype': 'P', // 개인
          'tr_type': '2', // 해제
          'content-type': 'utf-8'
        },
        'body': {
          'input': {
            'tr_id': market == 'NASDAQ' ? 'HDFSCNT0' : 'H0STCNT0',
            'tr_key': stockCode,
          }
        }
      };
      
      channel.sink.add(jsonEncode(unsubscribeMessage));
      print('✅ [통일API] 실시간 데이터 구독 해제 성공: $stockCode');
      
      return true;
    } catch (e) {
      print('❌ [통일API] 실시간 데이터 구독 해제 실패: $e');
      return false;
    }
  }
  
  /// ========================================
  /// WebSocket 메시지 처리
  /// ========================================
  
  /// WebSocket 메시지 파싱
  Map<String, dynamic>? parseWebSocketMessage(dynamic message) {
    try {
      final data = jsonDecode(message.toString());
      
      // KIS WebSocket 메시지 형식 검증
      if (data['header'] != null && data['body'] != null) {
        final header = data['header'];
        final body = data['body'];
        final trId = header['tr_id'] as String?;
        
        return {
          'header': header,
          'body': body,
          'tr_id': trId,
          'timestamp': DateTime.now().toIso8601String(),
        };
      }
      
      return null;
    } catch (e) {
      print('❌ [통일API] WebSocket 메시지 파싱 오류: $e');
      return null;
    }
  }
  
  /// 실시간 체결가 데이터 파싱
  Map<String, dynamic>? parseRealtimePriceData(Map<String, dynamic> messageData) {
    try {
      final header = messageData['header'];
      final body = messageData['body'];
      final trId = header['tr_id'] as String?;
      
      // 실시간 체결가 데이터 처리
      if (trId == 'H0STCNT0' || trId == 'HDFSCNT0') {
        final stockCode = body['mksc_shrn_iscd'] as String? ?? body['symb'] as String?;
        final priceStr = body['stck_prpr'] as String? ?? body['last'] as String? ?? '0';
        final price = double.tryParse(priceStr) ?? 0.0;
        
        if (stockCode != null && stockCode.isNotEmpty && price > 0) {
          return {
            'stockCode': stockCode,
            'currentPrice': price,
            'market': trId == 'H0STCNT0' ? 'DOMESTIC' : 'NASDAQ',
            'timestamp': DateTime.now().toIso8601String(),
            'rawData': body,
          };
        }
      }
      
      return null;
    } catch (e) {
      print('❌ [통일API] 실시간 체결가 데이터 파싱 오류: $e');
      return null;
    }
  }
  
  /// PING 메시지 처리
  bool isPingMessage(Map<String, dynamic> messageData) {
    final trId = messageData['tr_id'] as String?;
    return trId == 'PINGPONG';
  }
  
  /// PONG 메시지 전송
  Future<void> sendPongMessage(WebSocketChannel channel, String approvalKey) async {
    try {
      final pongMessage = {
        'header': {
          'approval_key': approvalKey,
          'custtype': 'P',
          'tr_type': '1',
          'content-type': 'utf-8'
        },
        'body': {
          'input': {
            'tr_id': 'PINGPONG',
            'tr_key': '',
          }
        }
      };
      
      channel.sink.add(jsonEncode(pongMessage));
    } catch (e) {
      print('❌ [통일API] PONG 메시지 전송 오류: $e');
    }
  }
  
  /// ========================================
  /// 편의 메서드들
  /// ========================================
  
  /// 다중 종목 실시간 데이터 구독
  Future<Map<String, bool>> subscribeMultipleStocks({
    required WebSocketChannel channel,
    required List<String> stockCodes,
    required String market,
    required String approvalKey,
    Duration delayBetweenSubscriptions = const Duration(milliseconds: 100),
  }) async {
    final results = <String, bool>{};
    
    for (final stockCode in stockCodes) {
      final success = await subscribeStockRealtimeData(
        channel: channel,
        stockCode: stockCode,
        market: market,
        approvalKey: approvalKey,
      );
      
      results[stockCode] = success;
      
      // KIS API 제한을 위한 딜레이
      if (delayBetweenSubscriptions.inMilliseconds > 0) {
        await Future.delayed(delayBetweenSubscriptions);
      }
    }
    
    final successCount = results.values.where((success) => success).length;
    print('✅ [통일API] 다중 종목 구독 완료: $successCount/${stockCodes.length}개 성공');
    
    return results;
  }
  
  /// WebSocket 연결 상태 확인
  bool isWebSocketConnected(WebSocketChannel? channel) {
    return channel != null && channel.closeCode == null;
  }
  
  /// WebSocket 에러 처리
  void handleWebSocketError(dynamic error) {
    print('❌ [통일API] WebSocket 에러: $error');
    
    // 에러 타입별 처리
    if (error is WebSocketException) {
      print('🔌 [통일API] WebSocket 연결 에러: ${error.message}');
    } else if (error is FormatException) {
      print('📝 [통일API] WebSocket 메시지 형식 에러: ${error.message}');
    } else {
      print('⚠️ [통일API] 알 수 없는 WebSocket 에러: $error');
    }
  }
}
