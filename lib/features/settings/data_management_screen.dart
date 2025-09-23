import 'package:flutter/material.dart';
import '../../core/services/data_management_service.dart';

/// 데이터 관리 화면
class DataManagementScreen extends StatefulWidget {
  const DataManagementScreen({super.key});

  @override
  State<DataManagementScreen> createState() => _DataManagementScreenState();
}

class _DataManagementScreenState extends State<DataManagementScreen> {
  final DataManagementService _dataService = DataManagementService.instance;
  Map<String, int> _databaseStats = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadDatabaseStats();
  }

  /// 데이터베이스 통계 로드
  Future<void> _loadDatabaseStats() async {
    setState(() => _isLoading = true);
    try {
      final stats = await _dataService.getDatabaseStats();
      setState(() {
        _databaseStats = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('통계 로드 실패: $e');
    }
  }

  /// 데이터 정리 실행
  Future<void> _cleanupData() async {
    setState(() => _isLoading = true);
    try {
      await _dataService.forceCleanup();
      await _loadDatabaseStats();
      _showSnackBar('데이터 정리 완료');
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('데이터 정리 실패: $e');
    }
  }

  /// 데이터베이스 최적화 실행
  Future<void> _optimizeDatabase() async {
    setState(() => _isLoading = true);
    try {
      await _dataService.forceOptimize();
      await _loadDatabaseStats();
      _showSnackBar('데이터베이스 최적화 완료');
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('데이터베이스 최적화 실패: $e');
    }
  }

  /// 특정 테이블 정리
  Future<void> _cleanupTable(String tableName, {int? daysToKeep}) async {
    setState(() => _isLoading = true);
    try {
      final deletedCount = await _dataService.cleanupTable(tableName, daysToKeep: daysToKeep);
      await _loadDatabaseStats();
      _showSnackBar('$tableName 테이블에서 $deletedCount개 데이터 삭제 완료');
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('테이블 정리 실패: $e');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('데이터 관리'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 데이터베이스 통계
                  _buildStatsCard(),
                  const SizedBox(height: 16),
                  
                  // 자동 정리 정책
                  _buildAutoCleanupCard(),
                  const SizedBox(height: 16),
                  
                  // 수동 정리 옵션
                  _buildManualCleanupCard(),
                  const SizedBox(height: 16),
                  
                  // 테이블별 정리
                  _buildTableCleanupCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildStatsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📊 데이터베이스 통계',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ..._databaseStats.entries.map((entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_getTableDisplayName(entry.key)),
                  Text('${entry.value}개', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            )),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('총 데이터 수'),
                Text(
                  '${_databaseStats.values.fold(0, (sum, count) => sum + count)}개',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoCleanupCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🔄 자동 정리 정책',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildPolicyItem('실시간 데이터', '7일 후 자동 삭제'),
            _buildPolicyItem('분석 결과', '30일 후 자동 삭제'),
            _buildPolicyItem('시그널 히스토리', '90일 후 자동 삭제'),
            _buildPolicyItem('알림 히스토리', '30일 후 자동 삭제'),
            _buildPolicyItem('포트폴리오 성과', '1년 후 자동 삭제'),
            const SizedBox(height: 8),
            const Text(
              '💡 매일 자정에 자동으로 오래된 데이터를 정리합니다.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualCleanupCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🧹 수동 정리',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _cleanupData,
                    icon: const Icon(Icons.cleaning_services),
                    label: const Text('데이터 정리'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _optimizeDatabase,
                    icon: const Icon(Icons.speed),
                    label: const Text('DB 최적화'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableCleanupCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🗂️ 테이블별 정리',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildTableCleanupItem('realtime_data', '실시간 데이터', 7),
            _buildTableCleanupItem('analysis_results', '분석 결과', 30),
            _buildTableCleanupItem('signal_history', '시그널 히스토리', 90),
            _buildTableCleanupItem('notification_history', '알림 히스토리', 30),
            _buildTableCleanupItem('portfolio_performance', '포트폴리오 성과', 365),
          ],
        ),
      ),
    );
  }

  Widget _buildPolicyItem(String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.schedule, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(child: Text(title)),
          Text(description, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildTableCleanupItem(String tableName, String displayName, int defaultDays) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(displayName)),
          Text('${_databaseStats[tableName] ?? 0}개'),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => _cleanupTable(tableName, daysToKeep: defaultDays),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            child: const Text('정리'),
          ),
        ],
      ),
    );
  }

  String _getTableDisplayName(String tableName) {
    switch (tableName) {
      case 'stocks': return '종목 정보';
      case 'watchlist': return '관심종목';
      case 'holdings': return '보유종목';
      case 'realtime_data': return '실시간 데이터';
      case 'historical_data': return '히스토리 데이터';
      case 'analysis_results': return '분석 결과';
      case 'trade_history': return '거래 내역';
      case 'investment_styles': return '투자 스타일';
      case 'signal_history': return '시그널 히스토리';
      case 'portfolio_performance': return '포트폴리오 성과';
      case 'notification_history': return '알림 히스토리';
      case 'api_config': return 'API 설정';
      default: return tableName;
    }
  }
}
