// 거래탭에서 통합 서비스 사용 예시

import 'package:flutter/material.dart';
import '../core/services/integrated_stock_service.dart';

class TradingScreenWithIntegratedService extends StatefulWidget {
  @override
  _TradingScreenWithIntegratedServiceState createState() => _TradingScreenWithIntegratedServiceState();
}

class _TradingScreenWithIntegratedServiceState extends State<TradingScreenWithIntegratedService> {
  String _selectedStockCode = '005930';
  String _selectedStockName = '삼성전자';
  
  // 통합 데이터
  Map<String, dynamic>? _stockData;
  Map<String, dynamic>? _currentPrice;
  List<Map<String, dynamic>> _chartData = [];
  Map<String, dynamic>? _analysis;
  
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadStockData();
  }

  /// 통합 서비스를 사용한 종목 데이터 로딩
  Future<void> _loadStockData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      print('📊 통합 서비스로 종목 데이터 로딩: $_selectedStockCode');
      
      // 🚀 단일 호출로 모든 데이터 조회
      final stockData = await IntegratedStockService.getStockData(_selectedStockCode);
      
      if (stockData != null) {
        setState(() {
          _stockData = stockData;
          _currentPrice = IntegratedStockService.extractCurrentPrice(stockData);
          _chartData = IntegratedStockService.extractChartData(stockData);
          _analysis = IntegratedStockService.extractAnalysis(stockData);
        });
        
        print('✅ 통합 데이터 로딩 완료:');
        print('  - 현재가: ${_currentPrice?['currentPrice']}');
        print('  - 거래량: ${IntegratedStockService.extractLatestVolume(stockData)}');
        print('  - 분석점수: ${_analysis?['comprehensiveScore']}');
        print('  - 차트데이터: ${_chartData.length}개');
      } else {
        setState(() {
          _errorMessage = '데이터를 불러올 수 없습니다.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '데이터 로딩 실패: $e';
      });
      print('❌ 통합 데이터 로딩 실패: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 데이터 새로고침
  Future<void> _refreshData() async {
    print('🔄 데이터 새로고침 시작: $_selectedStockCode');
    
    final refreshedData = await IntegratedStockService.refreshStockData(_selectedStockCode);
    
    if (refreshedData != null) {
      setState(() {
        _stockData = refreshedData;
        _currentPrice = IntegratedStockService.extractCurrentPrice(refreshedData);
        _chartData = IntegratedStockService.extractChartData(refreshedData);
        _analysis = IntegratedStockService.extractAnalysis(refreshedData);
      });
      print('✅ 데이터 새로고침 완료');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('거래탭 - 통합 서비스'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _isLoading ? null : _refreshData,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, size: 64, color: Colors.red),
            SizedBox(height: 16),
            Text(_errorMessage, style: TextStyle(fontSize: 16)),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadStockData,
              child: Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    if (_stockData == null) {
      return Center(child: Text('데이터가 없습니다.'));
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStockInfo(),
          SizedBox(height: 20),
          _buildCurrentPriceInfo(),
          SizedBox(height: 20),
          _buildAnalysisInfo(),
          SizedBox(height: 20),
          _buildChartInfo(),
        ],
      ),
    );
  }

  Widget _buildStockInfo() {
    final stockInfo = IntegratedStockService.extractStockInfo(_stockData);
    
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '종목 정보',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('종목코드: ${stockInfo?['symbol'] ?? _selectedStockCode}'),
            Text('종목명: ${stockInfo?['name'] ?? _selectedStockName}'),
            Text('시장: ${stockInfo?['market'] ?? 'KOSPI'}'),
            Text('섹터: ${stockInfo?['sector'] ?? 'Unknown'}'),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentPriceInfo() {
    if (_currentPrice == null) return Container();

    final currentPrice = _currentPrice!['currentPrice'] as num? ?? 0.0;
    final change = _currentPrice!['change'] as num? ?? 0.0;
    final changeRate = _currentPrice!['changeRate'] as num? ?? 0.0;
    final volume = IntegratedStockService.extractLatestVolume(_stockData);
    final latestDate = IntegratedStockService.extractLatestDate(_stockData);

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '현재가 정보',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${currentPrice.toStringAsFixed(0)}원',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                SizedBox(width: 8),
                Text(
                  '${change >= 0 ? '+' : ''}${change.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: change >= 0 ? Colors.red : Colors.blue,
                    fontSize: 16,
                  ),
                ),
                Text(
                  ' (${changeRate >= 0 ? '+' : ''}${changeRate.toStringAsFixed(2)}%)',
                  style: TextStyle(
                    color: change >= 0 ? Colors.red : Colors.blue,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text('거래량: ${volume.toStringAsFixed(0)}'),
            Text('거래일: $latestDate'),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisInfo() {
    if (_analysis == null) return Container();

    final comprehensiveScore = _analysis!['comprehensiveScore'] as num? ?? 0.0;
    final signal = _analysis!['signal'] as String? ?? 'HOLD';
    final indicators = _analysis!['indicators'] as Map<String, dynamic>? ?? {};

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '분석 정보',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('종합 점수: ${comprehensiveScore.toStringAsFixed(3)}'),
            Text('거래 신호: $signal'),
            SizedBox(height: 8),
            Text('기술 지표:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('RSI: ${indicators['rsi']?.toStringAsFixed(2) ?? 'N/A'}'),
            Text('MA5: ${indicators['ma5']?.toStringAsFixed(0) ?? 'N/A'}'),
            Text('MA20: ${indicators['ma20']?.toStringAsFixed(0) ?? 'N/A'}'),
            Text('거래량 비율: ${indicators['volumeRatio']?.toStringAsFixed(2) ?? 'N/A'}'),
          ],
        ),
      ),
    );
  }

  Widget _buildChartInfo() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '차트 정보',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('차트 데이터: ${_chartData.length}개'),
            if (_chartData.isNotEmpty) ...[
              SizedBox(height: 8),
              Text('최신 데이터:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('날짜: ${_chartData.first['date']}'),
              Text('종가: ${_chartData.first['close']}'),
              Text('거래량: ${_chartData.first['volume']}'),
            ],
          ],
        ),
      ),
    );
  }
}

// 사용 예시
void main() {
  runApp(MaterialApp(
    home: TradingScreenWithIntegratedService(),
  ));
}
