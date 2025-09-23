import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/widgets/gradient_app_bar.dart';
import '../../core/trading/investment_style_manager.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  final InvestmentStyleManager _styleManager = InvestmentStyleManager();
  
  bool _buySignalEnabled = true;
  bool _sellSignalEnabled = true;
  bool _tradeExecutionEnabled = true;
  bool _buyFailureEnabled = true;
  bool _sellFailureEnabled = true;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _buySignalEnabled = prefs.getBool('buy_signal_enabled') ?? true;
        _sellSignalEnabled = prefs.getBool('sell_signal_enabled') ?? true;
        _tradeExecutionEnabled = prefs.getBool('trade_execution_enabled') ?? true;
        _buyFailureEnabled = prefs.getBool('buy_failure_enabled') ?? true;
        _sellFailureEnabled = prefs.getBool('sell_failure_enabled') ?? true;
        _soundEnabled = prefs.getBool('sound_enabled') ?? true;
        _vibrationEnabled = prefs.getBool('vibration_enabled') ?? true;
      });
    } catch (e) {
      print('❌ 설정 로드 실패: $e');
    }
  }

  Future<void> _saveSetting(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (e) {
      print('❌ 설정 저장 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(
        title: '알림 설정',
        colors: _styleManager.getGradientColors(),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('시그널 알림', Icons.trending_up),
            _buildSwitchTile(
              '매수 시그널 알림',
              '매수 기회 감지 시 알림',
              _buySignalEnabled,
              (value) {
                setState(() => _buySignalEnabled = value);
                _saveSetting('buy_signal_enabled', value);
              },
              Colors.red,
            ),
            _buildSwitchTile(
              '매도 시그널 알림',
              '매도 기회 감지 시 알림',
              _sellSignalEnabled,
              (value) {
                setState(() => _sellSignalEnabled = value);
                _saveSetting('sell_signal_enabled', value);
              },
              Colors.blue,
            ),
            const SizedBox(height: 24),
            
            _buildSectionHeader('거래 알림', Icons.account_balance_wallet),
            _buildSwitchTile(
              '거래 실행 알림',
              '실제 매수/매도 실행 시 알림',
              _tradeExecutionEnabled,
              (value) {
                setState(() => _tradeExecutionEnabled = value);
                _saveSetting('trade_execution_enabled', value);
              },
              Colors.green,
            ),
            _buildSwitchTile(
              '매수 실패 알림',
              '매수 주문 실패 시 알림',
              _buyFailureEnabled,
              (value) {
                setState(() => _buyFailureEnabled = value);
                _saveSetting('buy_failure_enabled', value);
              },
              Colors.orange,
            ),
            _buildSwitchTile(
              '매도 실패 알림',
              '매도 주문 실패 시 알림',
              _sellFailureEnabled,
              (value) {
                setState(() => _sellFailureEnabled = value);
                _saveSetting('sell_failure_enabled', value);
              },
              Colors.deepOrange,
            ),
            const SizedBox(height: 24),
            
            _buildSectionHeader('알림 방식', Icons.notifications),
            _buildSwitchTile(
              '소리 알림',
              '알림 시 소리 재생',
              _soundEnabled,
              (value) {
                setState(() => _soundEnabled = value);
                _saveSetting('sound_enabled', value);
              },
              Colors.purple,
            ),
            _buildSwitchTile(
              '진동 알림',
              '알림 시 진동 발생',
              _vibrationEnabled,
              (value) {
                setState(() => _vibrationEnabled = value);
                _saveSetting('vibration_enabled', value);
              },
              Colors.indigo,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: _styleManager.getThemeColor()),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _styleManager.getThemeColor(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile(String title, String subtitle, bool value, ValueChanged<bool> onChanged, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: SwitchListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        value: value,
        onChanged: onChanged,
        activeColor: color,
        secondary: Icon(Icons.circle, color: color, size: 12),
      ),
    );
  }
}
