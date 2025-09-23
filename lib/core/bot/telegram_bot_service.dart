import 'dart:convert';
import 'package:http/http.dart' as http;

class TelegramBotService {
  final String botToken;
  final String chatId;
  bool _isInitialized = false;

  TelegramBotService({
    required this.botToken,
    required this.chatId,
  });

  Future<void> initialize() async {
    if (botToken.isEmpty || botToken == 'your_bot_token_here') {
      throw Exception('텔레그램 봇 토큰이 설정되지 않았습니다.');
    }
    
    if (chatId.isEmpty || chatId == 'your_chat_id_here') {
      throw Exception('텔레그램 채팅 ID가 설정되지 않았습니다.');
    }

    try {
      // 봇 정보 확인
      final response = await http.get(
        Uri.parse('https://api.telegram.org/bot$botToken/getMe'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ok'] == true) {
          _isInitialized = true;
          print('텔레그램 봇 초기화 완료: ${data['result']['username']}');
        } else {
          throw Exception('텔레그램 봇 토큰이 유효하지 않습니다.');
        }
      } else {
        throw Exception('텔레그램 봇 연결 실패: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('텔레그램 봇 초기화 실패: $e');
    }
  }

  Future<bool> sendMessage(String message) async {
    if (!_isInitialized) {
      throw Exception('텔레그램 봇이 초기화되지 않았습니다.');
    }

    try {
      final response = await http.post(
        Uri.parse('https://api.telegram.org/bot$botToken/sendMessage'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'chat_id': chatId,
          'text': message,
          'parse_mode': 'HTML',
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['ok'] == true;
      } else {
        throw Exception('메시지 전송 실패: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('메시지 전송 실패: $e');
    }
  }

  Future<bool> sendAlert({
    required String stockCode,
    required String stockName,
    required String signal,
    required String reason,
    double? price,
    double? targetPrice,
  }) async {
    final message = '''
🚨 <b>AI 트레이딩 알림</b>

📈 <b>종목:</b> $stockName ($stockCode)
🎯 <b>시그널:</b> $signal
${price != null ? '💰 <b>현재가:</b> ${price.toStringAsFixed(0)}원' : ''}
${targetPrice != null ? '🎯 <b>목표가:</b> ${targetPrice.toStringAsFixed(0)}원' : ''}
📝 <b>사유:</b> $reason

⏰ ${DateTime.now().toString().substring(0, 19)}
''';

    return await sendMessage(message);
  }

  Future<bool> sendTradeNotification({
    required String stockCode,
    required String stockName,
    required String orderType,
    required int quantity,
    required double price,
    required String status,
  }) async {
    final message = '''
📊 <b>거래 알림</b>

📈 <b>종목:</b> $stockName ($stockCode)
🔄 <b>주문:</b> $orderType
📦 <b>수량:</b> ${quantity}주
💰 <b>가격:</b> ${price.toStringAsFixed(0)}원
✅ <b>상태:</b> $status

⏰ ${DateTime.now().toString().substring(0, 19)}
''';

    return await sendMessage(message);
  }

  void dispose() {
    _isInitialized = false;
  }
}
