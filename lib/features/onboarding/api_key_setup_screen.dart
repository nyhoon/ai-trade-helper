import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/api_config.dart';
import '../../core/data/app_data_manager.dart';
import '../splash/splash_screen.dart';

class ApiKeySetupScreen extends StatefulWidget {
  const ApiKeySetupScreen({super.key});

  @override
  State<ApiKeySetupScreen> createState() => _ApiKeySetupScreenState();
}

class _ApiKeySetupScreenState extends State<ApiKeySetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _appKeyController = TextEditingController();
  final _appSecretController = TextEditingController();
  final _accountNoController = TextEditingController();
  
  bool _isLoading = false;
  bool _obscureAppSecret = true;


  @override
  void initState() {
    super.initState();
    _loadExistingConfig();
    
    // 웹에서 버튼 이벤트 처리를 위한 디버그 로그
    print('🌐 API 키 설정 화면 초기화 완료');
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
    final config = ApiConfig.instance;
    if (config.isValid) {
      _appKeyController.text = config.appKey ?? '';
      _appSecretController.text = config.appSecret ?? '';
      _accountNoController.text = config.accountNo ?? '';

    }
  }

  /// API 키 설정 저장
  Future<void> _saveApiConfig() async {
    print('🌐 저장 버튼 클릭됨!');
    
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      print('🔍 API 설정 저장 시작...');
      
      // 웹 환경에서 데이터베이스 초기화 (안전한 방식)
      try {
        await AppDataManager.instance.initialize();
        print('✅ AppDataManager 초기화 완료');
      } catch (e) {
        print('⚠️ AppDataManager 초기화 실패, 계속 진행: $e');
      }
      
      // 1. API 설정 저장
      await ApiConfig.instance.saveConfig(
        appKey: _appKeyController.text.trim(),
        appSecret: _appSecretController.text.trim(),
        accountNo: _accountNoController.text.trim(),
        isReal: true,
      );
      await ApiConfig.instance.initialize();

      // 2. 저장 후 즉시 검증
      final config = ApiConfig.instance;
      print('🔍 저장 후 API 설정 검증:');
      print('   - isValid: ${config.isValid}');
      print('   - appKey: ${config.appKey?.substring(0, config.appKey!.length > 10 ? 10 : config.appKey!.length)}...');
      print('   - accountNo: ${config.accountNo}');

      // 3. SharedPreferences에서 직접 확인
      final prefs = await SharedPreferences.getInstance();
      final savedAppKey = prefs.getString('api_app_key');
      final savedAppSecret = prefs.getString('api_app_secret');
      final savedAccountNo = prefs.getString('api_account_no');
      
      print('🔍 SharedPreferences 저장 확인:');
      print('   - appKey: ${savedAppKey?.substring(0, savedAppKey!.length > 10 ? 10 : savedAppKey.length)}...');
      print('   - accountNo: $savedAccountNo');

      // 4. 데모 모드 플래그 해제 (실제 API 키 입력 시)
      await prefs.setBool('demo_mode', false);

      // 5. 앱 데이터 매니저 재초기화 (새로운 API 키로)
      await AppDataManager.instance.initialize();

      if (mounted) {
        // 성공 메시지 표시
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('API 설정이 저장되었습니다.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // 3초 후 스플래시 화면으로 이동
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const SplashScreen()),
            );
          }
        });
      }
    } catch (e) {
      print('❌ API 설정 저장 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('API 설정 저장 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// API 키 복사
  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label이 클립보드에 복사되었습니다.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// API 설정 건너뛰기 (데모 모드)
  Future<void> _skipApiSetup() async {
    print('🌐 데모 모드 버튼 클릭됨!');
    
    setState(() {
      _isLoading = true;
    });

    try {
      // 웹 환경에서 데이터베이스 초기화 (안전한 방식)
      try {
        await AppDataManager.instance.initialize();
        print('✅ AppDataManager 초기화 완료');
      } catch (e) {
        print('⚠️ AppDataManager 초기화 실패, 계속 진행: $e');
      }
      
      // 데모용 더미 API 설정 저장
      await ApiConfig.instance.saveConfig(
        appKey: 'demo_app_key_1234567890',
        appSecret: 'demo_app_secret_1234567890',
        accountNo: '12345678-01',
        isReal: false, // 모의계좌로 설정
      );
      await ApiConfig.instance.initialize();

      // 데모 모드 플래그 저장
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('demo_mode', true);

      if (mounted) {
        // 성공 메시지 표시
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('데모 모드로 앱을 실행합니다.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );

        // 2초 후 스플래시 화면으로 이동
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const SplashScreen()),
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('데모 모드 설정 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('API 키 설정'),
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue[600]),
                        const SizedBox(width: 8),
                        Text(
                          'KIS API 키 설정',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[800],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '한국투자증권 API를 사용하기 위해 App Key, App Secret, 계좌번호를 입력해주세요.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'API 키는 안전하게 저장되며, 앱에서만 사용됩니다.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '실제 API 키를 입력하면 데모 모드가 자동으로 해제됩니다.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 32),
              
              // App Key 입력
              Text(
                'App Key',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _appKeyController,
                decoration: InputDecoration(
                  hintText: '한국투자증권 App Key를 입력하세요',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () => _copyToClipboard(_appKeyController.text, 'App Key'),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'App Key를 입력해주세요';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 24),
              
              // App Secret 입력
              Text(
                'App Secret',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _appSecretController,
                obscureText: _obscureAppSecret,
                decoration: InputDecoration(
                  hintText: '한국투자증권 App Secret을 입력하세요',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(_obscureAppSecret ? Icons.visibility : Icons.visibility_off),
                        onPressed: () {
                          setState(() {
                            _obscureAppSecret = !_obscureAppSecret;
                          });
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        onPressed: () => _copyToClipboard(_appSecretController.text, 'App Secret'),
                      ),
                    ],
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'App Secret을 입력해주세요';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 24),
              
              // 계좌번호 입력
              Text(
                '계좌번호',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _accountNoController,
                decoration: InputDecoration(
                  hintText: '계좌번호를 입력하세요 (예: 12345678-01)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () => _copyToClipboard(_accountNoController.text, '계좌번호'),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '계좌번호를 입력해주세요';
                  }
                  if (!RegExp(r'^\d{8}-\d{2}$').hasMatch(value.trim())) {
                    return '올바른 계좌번호 형식을 입력해주세요 (예: 12345678-01)';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 24),
              
              // 실계좌/모의계좌 선택
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '계좌 유형',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),

                  ],
                ),
              ),
              
              const SizedBox(height: 32),
              
              // 저장 버튼
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveApiConfig,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        '설정 저장',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // 건너뛰기 버튼 (데모 모드)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: _isLoading ? null : _skipApiSetup,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey[600],
                    side: BorderSide(color: Colors.grey[400]!),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    '건너뛰기 (데모 모드)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // 도움말
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.help_outline, color: Colors.orange[600]),
                        const SizedBox(width: 8),
                        Text(
                          'API 키 발급 방법',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[800],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '1. 한국투자증권 Open API 신청\n'
                      '2. App Key와 App Secret 발급\n'
                      '3. 계좌번호 확인 (12345678-01 형식)\n'
                      '4. 위 정보를 입력하고 저장',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // 데모 모드 안내
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.play_circle_outline, color: Colors.green[600]),
                        const SizedBox(width: 8),
                        Text(
                          '데모 모드',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.green[800],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'API 키 없이도 앱의 기능을 구경할 수 있습니다.\n'
                      '데모 데이터로 거래 화면, 차트, 분석 기능을 체험해보세요.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
