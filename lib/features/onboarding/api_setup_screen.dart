import 'package:flutter/material.dart';
import 'dart:io';
import '../../core/config/api_config.dart';
import '../../core/utils/formatters.dart';

class ApiSetupScreen extends StatefulWidget {
  const ApiSetupScreen({super.key});

  @override
  State<ApiSetupScreen> createState() => _ApiSetupScreenState();
}

class _ApiSetupScreenState extends State<ApiSetupScreen> {
  final _appKeyController = TextEditingController();
  final _appSecretController = TextEditingController();
  final _accountNoController = TextEditingController();
  bool _isLoading = false;
  bool _isValid = false;

  @override
  void initState() {
    super.initState();
    _loadExistingConfig();
    _validateInputs();
  }

  @override
  void dispose() {
    _appKeyController.dispose();
    _appSecretController.dispose();
    _accountNoController.dispose();
    super.dispose();
  }

  /// 기존 설정 로드
  Future<void> _loadExistingConfig() async {
    try {
      final config = ApiConfig.instance;
      if (config.isValid) {
        _appKeyController.text = config.appKey ?? '';
        _appSecretController.text = config.appSecret ?? '';
        _accountNoController.text = config.accountNo ?? '';
        setState(() {
          _isValid = true;
        });
      }
    } catch (e) {
      print('기존 설정 로드 실패: $e');
    }
  }

  /// 입력값 검증
  void _validateInputs() {
    final isValid = _appKeyController.text.trim().isNotEmpty &&
                   _appSecretController.text.trim().isNotEmpty &&
                   _accountNoController.text.trim().isNotEmpty;
    
    setState(() {
      _isValid = isValid;
    });
  }

  /// 설정 저장 및 앱 시작
  Future<void> _saveAndContinue() async {
    if (!_isValid) {
      _showErrorDialog('모든 필드를 입력해주세요.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final config = ApiConfig.instance;
      await config.saveConfig(
        appKey: _appKeyController.text.trim(),
        appSecret: _appSecretController.text.trim(),
        accountNo: _accountNoController.text.trim(),
      );

      // 성공 시 메인 화면으로 이동
      Navigator.of(context).pushReplacementNamed('/main');
    } catch (e) {
      _showErrorDialog('설정 저장에 실패했습니다.\n오류: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 오류 다이얼로그 표시
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('오류'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // 뒤로가기 방지
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF3B5BA9),
                Color(0xFF2E4A8C),
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 헤더
                  const SizedBox(height: 40),
                  const Icon(
                    Icons.api,
                    color: Colors.white,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'KIS API 설정',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '앱 사용을 위해 KIS API 키를 설정해주세요.',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 40),

                  // 설정 폼
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                                                     children: [

                            // 앱 키 입력
                            const Text(
                              '앱 키 (App Key)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _appKeyController,
                              onChanged: (_) => _validateInputs(),
                              decoration: const InputDecoration(
                                hintText: '앱 키를 입력하세요',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // 앱 시크릿 입력
                            const Text(
                              '앱 시크릿 (App Secret)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _appSecretController,
                              onChanged: (_) => _validateInputs(),
                              decoration: const InputDecoration(
                                hintText: '앱 시크릿을 입력하세요',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                              obscureText: true,
                            ),
                            const SizedBox(height: 16),

                            // 계좌번호 입력
                            const Text(
                              '계좌번호',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _accountNoController,
                              onChanged: (_) => _validateInputs(),
                              decoration: const InputDecoration(
                                hintText: '계좌번호를 입력하세요 (예: 12345678-01)',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // 안내 메시지
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue.withOpacity(0.3)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.info_outline, color: Colors.blue, size: 20),
                                  SizedBox(width: 8),
                                  Expanded(
                                                                       child: Text(
                                     'KIS Developers에서 발급받은 API 키를 입력해주세요.',
                                     style: TextStyle(
                                       fontSize: 12,
                                       color: Colors.blue,
                                     ),
                                   ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 32),

                            // 시작 버튼
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: _isValid && !_isLoading ? _saveAndContinue : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF3B5BA9),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: _isLoading
                                    ? const CircularProgressIndicator(color: Colors.white)
                                    : const Text(
                                        '앱 시작하기',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
