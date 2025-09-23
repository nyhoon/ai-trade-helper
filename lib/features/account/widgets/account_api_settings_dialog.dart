import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/config/api_config.dart';
import '../../../core/data/app_data_manager.dart';

/// KIS API 설정 다이얼로그 위젯
class AccountApiSettingsDialog extends StatefulWidget {
  final VoidCallback? onSettingsChanged;

  const AccountApiSettingsDialog({
    super.key,
    this.onSettingsChanged,
  });

  @override
  State<AccountApiSettingsDialog> createState() => _AccountApiSettingsDialogState();
}

class _AccountApiSettingsDialogState extends State<AccountApiSettingsDialog> {
  @override
  Widget build(BuildContext context) {
    final config = ApiConfig.instance;
    
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Row(
              children: [
                const Icon(Icons.api, color: Colors.blue, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'KIS API 설정',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // 스크롤 가능한 컨텐츠
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildApiStatusCard(config),
                    const SizedBox(height: 20),
                    _buildApiSettingsForm(config),
                    const SizedBox(height: 20),
                    _buildApiActionButtons(context, config),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// API 상태 카드
  Widget _buildApiStatusCard(ApiConfig config) {
    final isValid = config.isValid;
    final isReal = config.isReal;
    
    return Card(
      color: isValid ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              isValid ? Icons.check_circle : Icons.warning,
              color: isValid ? Colors.green : Colors.orange,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isValid ? 'API 연결됨' : 'API 설정 필요',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isValid ? Colors.green : Colors.orange,
                    ),
                  ),
                  Text(
                    isReal ? '실전투자 모드' : '모의투자 모드',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// API 설정 폼
  Widget _buildApiSettingsForm(ApiConfig config) {
    final appKeyController = TextEditingController(text: config.appKey);
    final appSecretController = TextEditingController(text: config.appSecret);
    final accountNoController = TextEditingController(text: config.accountNo);
    
    return StatefulBuilder(
      builder: (context, setState) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'API 설정',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                
                // 앱 키 입력
                const Text(
                  '앱 키 (App Key)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: appKeyController,
                  decoration: const InputDecoration(
                    hintText: '앱 키를 입력하세요',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  obscureText: false,
                ),
                const SizedBox(height: 16),
                
                // 앱 시크릿 입력
                const Text(
                  '앱 시크릿 (App Secret)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: appSecretController,
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
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: accountNoController,
                  decoration: const InputDecoration(
                    hintText: '계좌번호를 입력하세요 (예: 12345678-01)',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 20),
                
                // 저장/삭제 버튼
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _saveApiSettings(
                          context,
                          appKeyController.text,
                          appSecretController.text,
                          accountNoController.text,
                        ),
                        icon: const Icon(Icons.save, size: 16),
                        label: const Text('설정 저장'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _clearApiSettings(context),
                        icon: const Icon(Icons.delete, size: 16),
                        label: const Text('설정 삭제'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// API 액션 버튼들
  Widget _buildApiActionButtons(BuildContext context, ApiConfig config) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _testApiConnection(context),
            icon: const Icon(Icons.wifi_tethering, size: 16),
            label: const Text('API 연결 테스트'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _refreshAccountData(context),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('계좌 정보 새로고침'),
          ),
        ),
      ],
    );
  }

  /// API 연결 테스트
  Future<void> _testApiConnection(BuildContext context) async {
    try {
      // 로딩 표시
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('API 연결 테스트 중...'),
            ],
          ),
        ),
      );

      // API 연결 테스트
      final result = await AppDataManager.instance.getAccountBalance();
      
      // 로딩 다이얼로그 닫기
      Navigator.of(context).pop();
      
      // 결과 표시
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('연결 테스트 결과'),
          content: Text(
            result != null ? '✅ API 연결 성공!\n계좌 정보를 정상적으로 가져왔습니다.' : '❌ API 연결 실패\n설정을 확인해주세요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    } catch (e) {
      // 로딩 다이얼로그 닫기
      Navigator.of(context).pop();
      
      // 오류 표시
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('연결 테스트 실패'),
          content: Text('API 연결에 실패했습니다.\n오류: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    }
  }

  /// API 설정 저장
  Future<void> _saveApiSettings(
    BuildContext context,
    String appKey,
    String appSecret,
    String accountNo,
  ) async {
    // 입력값 검증
    if (appKey.trim().isEmpty) {
      _showErrorDialog(context, '앱 키를 입력해주세요.');
      return;
    }
    if (appSecret.trim().isEmpty) {
      _showErrorDialog(context, '앱 시크릿을 입력해주세요.');
      return;
    }
    if (accountNo.trim().isEmpty) {
      _showErrorDialog(context, '계좌번호를 입력해주세요.');
      return;
    }

    try {
      // 현재 설정과 비교하여 변경사항 확인
      final currentConfig = ApiConfig.instance;
      final hasChanged = currentConfig.appKey != appKey.trim() ||
                        currentConfig.appSecret != appSecret.trim() ||
                        currentConfig.accountNo != accountNo.trim();

      // ApiConfig에 설정 저장
      await currentConfig.saveConfig(
        appKey: appKey.trim(),
        appSecret: appSecret.trim(),
        accountNo: accountNo.trim(),
      );

      // 설정이 변경된 경우 재시작 안내
      if (hasChanged) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('설정 저장 완료'),
            content: const Text(
              'KIS API 설정이 성공적으로 저장되었습니다.\n\n'
              '설정이 변경되었으므로 앱을 재시작하는 것을 권장합니다.\n'
              '재시작하시겠습니까?',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // 성공 다이얼로그 닫기
                  Navigator.of(context).pop(); // 설정 다이얼로그 닫기
                },
                child: const Text('나중에'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop(); // 성공 다이얼로그 닫기
                  Navigator.of(context).pop(); // 설정 다이얼로그 닫기
                  _restartApp(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                child: const Text('재시작'),
              ),
            ],
          ),
        );
      } else {
        // 설정이 변경되지 않은 경우 일반 성공 메시지
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('설정 저장 완료'),
            content: const Text('KIS API 설정이 성공적으로 저장되었습니다.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // 성공 다이얼로그 닫기
                  Navigator.of(context).pop(); // 설정 다이얼로그 닫기
                },
                child: const Text('확인'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _showErrorDialog(context, '설정 저장에 실패했습니다.\n오류: $e');
    }
  }

  /// API 설정 삭제
  Future<void> _clearApiSettings(BuildContext context) async {
    // 확인 다이얼로그 표시
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('설정 삭제'),
        content: const Text('모든 KIS API 설정을 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // ApiConfig에서 설정 삭제
        final config = ApiConfig.instance;
        await config.clearConfig();

        // 성공 메시지 표시 (재시작 안내 포함)
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('설정 삭제 완료'),
            content: const Text(
              'KIS API 설정이 삭제되었습니다.\n\n'
              '설정이 변경되었으므로 앱을 재시작하는 것을 권장합니다.\n'
              '재시작하시겠습니까?',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // 성공 다이얼로그 닫기
                  Navigator.of(context).pop(); // 설정 다이얼로그 닫기
                },
                child: const Text('나중에'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop(); // 성공 다이얼로그 닫기
                  Navigator.of(context).pop(); // 설정 다이얼로그 닫기
                  _restartApp(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                child: const Text('재시작'),
              ),
            ],
          ),
        );
      } catch (e) {
        _showErrorDialog(context, '설정 삭제에 실패했습니다.\n오류: $e');
      }
    }
  }

  /// 앱 재시작
  void _restartApp(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('앱 재시작'),
        content: const Text(
          '설정이 변경되었습니다.\n\n'
          '앱을 완전히 종료한 후 다시 실행해주세요.\n\n'
          '이렇게 하면 새로운 설정으로 모든 데이터가 새로 로드됩니다.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              // 앱 종료 (Android/iOS에서 작동)
              exit(0);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('앱 종료'),
          ),
        ],
      ),
    );
  }

  /// 오류 다이얼로그 표시
  void _showErrorDialog(BuildContext context, String message) {
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

  /// 계좌 정보 새로고침
  Future<void> _refreshAccountData(BuildContext context) async {
    Navigator.of(context).pop(); // 설정 다이얼로그 닫기
    widget.onSettingsChanged?.call(); // 콜백 호출
  }
}
