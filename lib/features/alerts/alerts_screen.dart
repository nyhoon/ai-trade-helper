import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/data/watchlist_repository.dart';
import '../../core/trading/watchlist_manager.dart' show WatchlistItem;
import '../../core/data/app_data_manager.dart';
import '../../core/widgets/gradient_app_bar.dart';
import '../../core/trading/investment_style_manager.dart';
import '../../core/trading/investment_style.dart';
import '../../core/config/api_config.dart';
import '../../core/database/repositories/notification_history_repository.dart';
import 'notification_settings_screen.dart'; // Added import for NotificationSettingsScreen
// import '../../core/trading/auto_trading_service.dart'; // Removed legacy service import

import '../../core/services/local_notification_manager.dart'; // Added for local notifications
import 'package:permission_handler/permission_handler.dart'; // Added for notification permission
import '../../core/services/trade_status_tracker.dart' show TradeStatusTracker, TradeStatus; // Added for trade status tracking

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  List<WatchlistItem> _watchlist = [];
  Map<String, Map<String, bool>> _alertSettings = {};
  List<Map<String, dynamic>> _recentNotifications = [];
  bool _isLoading = false;
  final InvestmentStyleManager _styleManager = InvestmentStyleManager();
  final NotificationHistoryRepository _notificationRepository = NotificationHistoryRepository();
  final TradeStatusTracker _tradeStatusTracker = TradeStatusTracker();
  StreamSubscription<InvestmentStyle>? _styleSubscription;
  StreamSubscription<Map<String, TradeStatus>>? _tradeStatusSubscription;
  InvestmentStyle _currentStyle = InvestmentStyle.moderate;
  bool _isAutoTradingEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadWatchlist();
    _loadRecentNotifications();
    _initializeStyleManager();
    _loadAutoTradingStatus();
    _initializeTradeStatusTracking();
  }

  Future<void> _initializeStyleManager() async {
    await _styleManager.initialize();
    _loadCurrentStyle();
    
    // 스타일 변경 리스너 등록
    _styleSubscription = _styleManager.styleStream.listen((style) {
      if (mounted) {
        setState(() {}); // UI 업데이트
      }
    });
  }

  /// 거래 상태 추적 초기화
  Future<void> _initializeTradeStatusTracking() async {
    // 거래 상태 변경 리스너 등록
    _tradeStatusSubscription = _tradeStatusTracker.statusChangeStream.listen((statuses) {
      if (mounted) {
        setState(() {}); // UI 업데이트
      }
    });
  }

  Future<void> _loadWatchlist() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final watchlistRepository = WatchlistRepository();
      final watchlistData = await watchlistRepository.getWatchlistWithStockInfo();
      final watchlist = watchlistData.map((item) => WatchlistItem(
        stockCode: item['stock_code'],
        stockName: item['stock_name'],
        addedAt: DateTime.fromMillisecondsSinceEpoch(item['added_at']),
      )).toList();
      
      setState(() {
        _watchlist = watchlist;
        
        // 각 종목별 알림 설정 초기화
        for (final stock in _watchlist) {
          _alertSettings[stock.stockCode] = {
            'buySignal': true,
            'sellSignal': true,
          };
        }
      });
    } catch (e) {
      print('Failed to load watchlist: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }



  /// 최근 알림 로드
  Future<void> _loadRecentNotifications() async {
    try {
      final notifications = await _notificationRepository.getRecentNotifications();
      
      setState(() {
        _recentNotifications = notifications.map((notification) => {
          'id': notification['id'],
          'type': notification['type'],
          'stock_code': notification['stock_code'],
          'stock_name': notification['stock_name'],
          'message': notification['message'],
          'timestamp': notification['timestamp'],
        }).toList();
      });
    } catch (e) {
      print('❌ 최근 알림 로드 실패: $e');
      setState(() {
        _recentNotifications = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 상태표시줄을 투명하게 설정하여 앱바와 연속되도록 함
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );
    
    return Scaffold(
      appBar: GradientAppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '알림',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              _getStyleIcon(_currentStyle),
              color: Colors.white,
              size: 24,
            ),
            if (_isAutoTradingEnabled) ...[
              const SizedBox(width: 8),
              const Text(
                'AI 자동매매중',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ],
        ),
        colors: _styleManager.getGradientColors(),
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services),
            onPressed: () async {
              // 중복 알림 정리
              await _cleanupDuplicateNotifications();
            },
            tooltip: '중복 알림 정리',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NotificationSettingsScreen(),
                ),
              );
            },
            tooltip: '알림 설정',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              _loadWatchlist();
              _loadRecentNotifications();
              await _tradeStatusTracker.syncTradeStatusesFromHistory();
            },
            tooltip: '새로고침',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  // 거래 상태 요약 섹션
                  _buildTradeStatusSummary(),
                  const SizedBox(height: 16),
                  // 최근 알림 섹션
                  Expanded(child: _buildRecentNotificationsSection()),
                ],
              ),
            ),
    );
  }



  /// 거래 상태 요약 섹션
  Widget _buildTradeStatusSummary() {
    final allStatuses = _tradeStatusTracker.getAllTradeStatuses();
    final boughtCount = allStatuses.values.where((status) => status == TradeStatus.bought).length;
    final soldCount = allStatuses.values.where((status) => status == TradeStatus.sold).length;
    final holdingCount = allStatuses.values.where((status) => status == TradeStatus.holding).length;
    
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: _styleManager.getThemeColor()),
                const SizedBox(width: 8),
                Text(
                  '거래 상태 요약',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _styleManager.getThemeColor(),
                  ),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatusCard(
                    '매수 완료',
                    boughtCount.toString(),
                    Colors.red,
                    Icons.trending_up,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatusCard(
                    _getSellStatusTitle(soldCount),
                    soldCount.toString(),
                    Colors.blue,
                    Icons.trending_down,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatusCard(
                    '보유 중',
                    holdingCount.toString(),
                    Colors.green,
                    Icons.inventory,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 매도 상태 제목을 동적으로 생성
  String _getSellStatusTitle(int count) {
    if (count == 0) {
      return '매도 대기';
    } else if (count == 1) {
      return '매도 1건';
    } else {
      return '매도 $count건';
    }
  }

  /// 상태 카드 위젯
  Widget _buildStatusCard(String title, String count, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            count,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// 최근 알림 섹션
  Widget _buildRecentNotificationsSection() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notifications, color: _styleManager.getThemeColor()),
                const SizedBox(width: 8),
                Text(
                  '최근 알림',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _styleManager.getThemeColor(),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_sweep),
                  onPressed: () => _showDeleteAllDialog(),
                  tooltip: '전체 삭제',
                  iconSize: 20,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_recentNotifications.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.notifications_off,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '알림이 없습니다',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '매수/매도 시그널, 익절/손절 실행 시\n실제 알림이 여기에 표시됩니다',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _recentNotifications.length,
                  itemBuilder: (context, index) {
                    final notification = _recentNotifications[index];
                    final time = DateTime.fromMillisecondsSinceEpoch(notification['timestamp']);
                    final type = notification['type'] as String? ?? '';
                    final stockName = notification['stock_name'] as String? ?? '';
                    final message = notification['message'] as String? ?? '';
                    
                    String typeIcon = '📊';
                    Color typeColor = Colors.grey;
                    
                    // 시그널 분류표에 따른 아이콘 및 색상 설정
                    if (type.contains('AI 출근')) {
                      typeIcon = '🤖';
                      typeColor = Colors.blue;
                    } else if (type.contains('매수 시그널')) {
                      typeIcon = '📈';
                      typeColor = Colors.red;
                    } else if (type.contains('매도 시그널')) {
                      typeIcon = '📉';
                      typeColor = Colors.blue;
                    } else if (type.contains('매수 성공')) {
                      typeIcon = '✅';
                      typeColor = Colors.green;
                    } else if (type.contains('매수 실패')) {
                      typeIcon = '❌';
                      typeColor = Colors.red;
                    } else if (type.contains('매수 대기')) {
                      typeIcon = '⏳';
                      typeColor = Colors.orange;
                    } else if (type.contains('매수 취소')) {
                      typeIcon = '🚫';
                      typeColor = Colors.grey;
                    } else if (type.contains('매도 성공')) {
                      typeIcon = '✅';
                      typeColor = Colors.green;
                    } else if (type.contains('매도 실패')) {
                      typeIcon = '❌';
                      typeColor = Colors.red;
                    } else if (type.contains('매도 대기')) {
                      typeIcon = '⏳';
                      typeColor = Colors.orange;
                    } else if (type.contains('매도 취소')) {
                      typeIcon = '🚫';
                      typeColor = Colors.grey;
                    } else if (type.contains('매수 기회')) {
                      typeIcon = '🎯';
                      typeColor = Colors.amber;
                    } else if (type.contains('매도 기회')) {
                      typeIcon = '🎯';
                      typeColor = Colors.purple;
                    } else if (type.contains('매수')) {
                      typeIcon = '🟢';
                      typeColor = Colors.red;
                    } else if (type.contains('매도')) {
                      typeIcon = '🔴';
                      typeColor = Colors.blue;
                    } else if (type.contains('시그널')) {
                      typeIcon = '📈';
                      typeColor = Colors.orange;
                    }
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Text(
                              typeIcon,
                              style: const TextStyle(fontSize: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _formatNotificationTime(time, stockName),
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: typeColor,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    type,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      color: typeColor.withOpacity(0.8),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _formatMessageForDisplay(message, notification['stock_code']),
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[600],
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (notification['data'] != null) ...[
                                        const SizedBox(height: 4),
                                        _buildNotificationDetails(notification['data']),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => _showDeleteConfirmation(notification),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 삭제 확인 다이얼로그
  void _showDeleteConfirmation(Map<String, dynamic> notification) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('알림 삭제'),
          content: Text('이 알림을 삭제하시겠습니까?\n\n${notification['stock_name']} ${notification['message']}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteNotification(notification);
              },
              child: const Text('삭제', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  /// 알림 삭제
  Future<void> _deleteNotification(Map<String, dynamic> notification) async {
    try {
      final notificationId = notification['id'] as int?;
      
      if (notificationId != null) {
        // 실제 데이터베이스에서 삭제
        final success = await _notificationRepository.deleteNotification(notificationId);
        
        if (success) {
          // 성공하면 리스트에서도 제거
          setState(() {
            _recentNotifications.remove(notification);
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('알림이 삭제되었습니다'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('알림 삭제에 실패했습니다'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        // 테스트 데이터인 경우 리스트에서만 제거
        setState(() {
          _recentNotifications.remove(notification);
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('테스트 알림이 삭제되었습니다'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      print('❌ 알림 삭제 오류: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('삭제 실패: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    
    if (difference.inMinutes < 1) {
      return '방금';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}분전';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}시간전';
    } else {
      return '${time.month}/${time.day} ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
    }
  }

  /// 알림 시간 표시 개선
  String _formatNotificationTime(DateTime time, String stockName) {
    final timeStr = _formatTime(time);
    
    // stockName이 비어있거나 "Unknown"인 경우 처리
    if (stockName.isEmpty || stockName == 'Unknown' || stockName == 'UNKNOWN') {
      return timeStr;
    }
    
    return '$timeStr $stockName';
  }

  /// 나스닥 종목 여부 확인
  bool _isNasdaqStock(String? stockCode) {
    if (stockCode == null) return false;
    final upperCode = stockCode.toUpperCase();
    return upperCode == 'TSLS' || upperCode == 'TSLA' || upperCode == 'AAPL' || upperCode == 'GOOGL' ||
           upperCode == 'MSFT' || upperCode == 'AMZN' || upperCode == 'META' ||
           upperCode == 'NVDA' || upperCode == 'NFLX' || upperCode == 'ADBE' ||
           upperCode == 'CRM' || upperCode == 'PYPL' || upperCode == 'INTC' ||
           upperCode == 'AMD' || upperCode == 'ORCL' || upperCode == 'CSCO' ||
           upperCode == 'QCOM' || upperCode == 'TXN' || upperCode == 'AVGO' ||
           upperCode == 'MU' || upperCode == 'ADI' || upperCode == 'LRCX' ||
           upperCode == 'KLAC' || upperCode == 'MCHP' || upperCode == 'MRVL' ||
           upperCode == 'WDC' || upperCode == 'STX' || upperCode == 'NTAP' ||
           upperCode == 'CDNS' || upperCode == 'SNPS' || upperCode == 'ANSS' ||
           upperCode == 'ADSK' || upperCode == 'CTSH' || upperCode == 'ADP' ||
           upperCode == 'PAYX' || upperCode == 'INTU' || upperCode == 'WDAY' ||
           upperCode == 'ZM' || upperCode == 'SPLK' || upperCode == 'OKTA' ||
           upperCode == 'TEAM' || upperCode == 'SHOP' || upperCode == 'SQ' ||
           upperCode == 'TWLO' || upperCode == 'DOCU' || upperCode == 'CRWD' ||
           upperCode == 'ZS' || upperCode == 'PLTR' || upperCode == 'SNOW' ||
           upperCode == 'DDOG' || upperCode == 'NET' || upperCode == 'ASAN' ||
           upperCode == 'PATH' || upperCode == 'RBLX' || upperCode == 'COIN' ||
           upperCode == 'HOOD' || upperCode == 'RIVN' || upperCode == 'LCID' ||
           upperCode == 'NIO' || upperCode == 'XPEV' || upperCode == 'LI' ||
           upperCode == 'BIDU' || upperCode == 'JD' || upperCode == 'PDD' ||
           upperCode == 'BABA' || upperCode == 'TCEHY' || upperCode == 'NPD' ||
           upperCode == 'TME' || upperCode == 'VIPS' || upperCode == 'DIDI' ||
           upperCode == 'XPEV' || upperCode == 'LI' || upperCode == 'NIO' ||
           upperCode == 'XPEV' || upperCode == 'LI' || upperCode == 'NIO';
  }

  /// 메시지를 화면 표시용으로 포맷팅 (새로운 자동매매 시스템에 맞게 개선)
  String _formatMessageForDisplay(String message, String? stockCode) {
    // 새로운 자동매매 시스템의 시그널 형식에 맞게 개선
    if (message.contains('매수 시그널')) {
      return 'AI 매수 시그널 감지 - 매수 조건 충족';
    } else if (message.contains('매도 시그널')) {
      return 'AI 매도 시그널 감지 - 매도 조건 충족';
    } else if (message.contains('매수 기회')) {
      return '매수 기회 발견 - 자동매매 OFF 상태';
    } else if (message.contains('매도 기회')) {
      return '매도 기회 발견 - 자동매매 OFF 상태';
    } else if (message.contains('매수 성공')) {
      return '매수 주문 성공 - 거래 체결 완료';
    } else if (message.contains('매도 완료')) {
      return '매도 주문 접수 - 체결 대기 중';
    } else if (message.contains('매도 성공')) {
      return '매도 주문 성공 - 거래 체결 완료';
    } else if (message.contains('매수 실패')) {
      return '매수 주문 실패 - 거래 조건 미충족';
    } else if (message.contains('매도 실패')) {
      return '매도 주문 실패 - 거래 조건 미충족';
    } else if (message.contains('부분익절')) {
      return '부분익절 실행 - 수익 실현';
    } else if (message.contains('전체익절')) {
      return '전체익절 실행 - 수익 실현';
    } else if (message.contains('손절')) {
      return '손절 주문 - 손실 제한';
    }
    
    // 나스닥 종목인 경우 원화 표기를 달러로 변환
    if (stockCode != null && _isNasdaqStock(stockCode)) {
      final pricePattern = RegExp(r'(\d+)원');
      final match = pricePattern.firstMatch(message);
      
      if (match != null) {
        final priceStr = match.group(1);
        if (priceStr != null) {
          final price = double.tryParse(priceStr);
          if (price != null) {
            // 원화를 달러로 변환 (대략적인 환율 1300원 = 1달러)
            final dollarPrice = price / 1300;
            return message.replaceFirst(pricePattern, '\$${dollarPrice.toStringAsFixed(2)}');
          }
        }
      }
    }
    
    return message;
  }

  /// 알림 상세 정보 위젯
  Widget _buildNotificationDetails(Map<String, dynamic> data) {
    final stockCode = data['stockCode'] as String? ?? '';
    final stockName = data['stockName'] as String? ?? '';
    final price = data['price'] as num?;
    final quantity = data['quantity'] as num?;
    final totalAmount = data['totalAmount'] as num?;
    final signalType = data['signalType'] as String? ?? '';
    final orderId = data['orderId'] as String?;
    final orderStatus = data['orderStatus'] as String?;
    
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (stockName.isNotEmpty)
            Row(
              children: [
                Icon(Icons.trending_up, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  stockName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          if (price != null) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.attach_money, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  '가격: ${price.toStringAsFixed(0)}원',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
          if (quantity != null) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.shopping_cart, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  '수량: ${quantity.toStringAsFixed(0)}주',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
          if (totalAmount != null) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.account_balance_wallet, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  '총액: ${totalAmount.toStringAsFixed(0)}원',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
          if (signalType.isNotEmpty) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.trending_up, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  '시그널: $signalType',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
          if (orderId != null) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.receipt, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  '주문번호: $orderId',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
          if (orderStatus != null) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  '상태: $orderStatus',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAlertSetting(
    String label,
    bool value,
    Function(bool) onChanged,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: color,
          ),
        ],
      ),
    );
  }

  Widget _buildRecentAlerts(WatchlistItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '최근 알림',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        _buildRecentAlertsList(item),
      ],
    );
  }

  Widget _buildRecentAlertsList(WatchlistItem item) {
    // 실제로는 API에서 최근 알림을 가져와야 함
    // 현재는 빈 상태로 표시
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: Column(
          children: [
            Icon(Icons.notifications_none, size: 32, color: Colors.grey),
            SizedBox(height: 8),
            Text(
              '최근 알림이 없습니다.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _updateAlertSetting(String stockCode, String settingType, bool value) {
    setState(() {
      if (_alertSettings[stockCode] == null) {
        _alertSettings[stockCode] = {};
      }
      _alertSettings[stockCode]![settingType] = value;
    });

    _showAlertMessage(stockCode, settingType, value);
  }

  void _showAlertMessage(String stockCode, String settingType, bool value) {
    final item = _watchlist.firstWhere((item) => item.stockCode == stockCode);
    final stockName = _getDisplayName(item);
    final settingName = settingType == 'buySignal' ? '매수 시그널' : '매도 시그널';
    final action = value ? '활성화' : '비활성화';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$stockName $settingName이 $action되었습니다.'),
        backgroundColor: value ? Colors.green : Colors.orange,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _getDisplayName(WatchlistItem item) {
    return item.stockName.isNotEmpty ? item.stockName : item.stockCode;
  }

  /// 알림 권한 확인 및 요청
  Future<void> _checkNotificationPermission() async {
    try {
      final status = await Permission.notification.status;
      
      if (status.isDenied) {
        final result = await Permission.notification.request();
        
        if (result.isDenied) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('알림 권한이 필요합니다. 설정에서 권한을 허용해주세요.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        } else if (result.isPermanentlyDenied) {
          // 사용자가 "다시 묻지 않음"을 선택한 경우
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('알림 권한이 영구적으로 거부되었습니다. 설정에서 수동으로 허용해주세요.'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: '설정',
                onPressed: () => openAppSettings(),
              ),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ 알림 권한 확인 실패: $e');
    }
  }

  /// 전체 알림 삭제 다이얼로그
  void _showDeleteAllDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('전체 알림 삭제'),
          content: const Text('모든 알림을 삭제하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteAllNotifications();
              },
              child: const Text('삭제', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  /// 모든 알림 삭제
  Future<void> _deleteAllNotifications() async {
    try {
      await _notificationRepository.deleteAllNotifications();
      setState(() {
        _recentNotifications = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('모든 알림이 삭제되었습니다.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('❌ 전체 알림 삭제 오류: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('삭제 실패: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// 중복 알림 정리
  Future<void> _cleanupDuplicateNotifications() async {
    try {
      print('🧹 중복 알림 정리 시작...');
      
      // 데이터베이스에서 중복 알림 정리
      await _notificationRepository.cleanupDuplicateNotifications();
      
      // UI 새로고침
      await _loadRecentNotifications();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('중복 알림이 정리되었습니다.'),
            backgroundColor: Colors.blue,
          ),
        );
      }
      
      print('✅ 중복 알림 정리 완료');
    } catch (e) {
      print('❌ 중복 알림 정리 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('중복 알림 정리 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _styleSubscription?.cancel();
    _tradeStatusSubscription?.cancel();
    super.dispose();
  }

  /// 현재 스타일 로드
  Future<void> _loadCurrentStyle() async {
    final style = await _styleManager.getCurrentStyle();
    if (mounted) {
      setState(() {
        _currentStyle = style;
      });
    }
  }

  /// 자동매매 상태 로드
  Future<void> _loadAutoTradingStatus() async {
    try {
      // ApiConfig를 통해 정확한 자동매매 상태 로드
      final isEnabled = await ApiConfig.instance.getAutoTradingEnabled();
      if (mounted) {
        setState(() {
          _isAutoTradingEnabled = isEnabled;
        });
      }
    } catch (e) {
      print('❌ 자동매매 상태 로드 실패: $e');
      // 실패 시 SharedPreferences에서 로드
      final prefs = await SharedPreferences.getInstance();
      final isEnabled = prefs.getBool('auto_trading_enabled') ?? false;
      if (mounted) {
        setState(() {
          _isAutoTradingEnabled = isEnabled;
        });
      }
    }
  }

  /// 스타일별 아이콘 반환
  IconData _getStyleIcon(InvestmentStyle style) {
    switch (style) {
      case InvestmentStyle.conservative:
        return Icons.security; // 방패 아이콘
      case InvestmentStyle.moderate:
        return Icons.balance; // 저울 아이콘
      case InvestmentStyle.aggressive:
        return Icons.trending_up; // 상승 그래프 아이콘
    }
  }

}
