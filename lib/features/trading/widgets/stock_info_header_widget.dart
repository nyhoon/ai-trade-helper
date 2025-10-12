import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/data/app_data_manager.dart';
import '../../../core/trading/investment_style_manager.dart';
import '../../../core/remote/remote_kis_service.dart';

/// 주식 정보 헤더 위젯
class StockInfoHeaderWidget extends StatelessWidget {
  final String stockCode;
  final String stockName;
  final Map<String, dynamic> stockData;
  final VoidCallback? onFavoriteTap;
  final VoidCallback? onSearchTap;
  final VoidCallback? onListTap;

  const StockInfoHeaderWidget({
    Key? key,
    required this.stockCode,
    required this.stockName,
    required this.stockData,
    this.onFavoriteTap,
    this.onSearchTap,
    this.onListTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('stocks')
          .doc(stockCode)
          .snapshots(),
      builder: (context, snapshot) {
        print('🔍 [StockInfoHeader] StreamBuilder 상태: ${snapshot.connectionState}');
        print('🔍 [StockInfoHeader] StreamBuilder 오류: ${snapshot.error}');
        print('🔍 [StockInfoHeader] StreamBuilder 데이터 존재: ${snapshot.data != null}');
        
        if (snapshot.connectionState == ConnectionState.waiting) {
          print('⏳ [StockInfoHeader] Firestore 로딩 중...');
          return _buildLoadingWidget();
        }
        
        if (snapshot.hasError) {
          print('❌ [StockInfoHeader] Firestore 구독 오류: ${snapshot.error}');
          return _buildStockInfoWidget({}, stockData);
        }
        
        final doc = snapshot.data;
        Map<String, dynamic> firestoreData = {};
        
        if (doc != null && doc.exists) {
          try {
            final data = doc.data()! as Map<String, dynamic>;
            print('🔍 [StockInfoHeader] Firestore 원본 데이터: $data');
            print('🔍 [StockInfoHeader] Firestore 데이터 키들: ${data.keys.toList()}');
            
            // current 데이터 안전하게 처리
            Map<String, dynamic>? current;
            if (data['current'] != null) {
              if (data['current'] is Map<String, dynamic>) {
                current = data['current'] as Map<String, dynamic>;
                print('🔍 [StockInfoHeader] current 데이터 추출 성공: $current');
              } else {
                print('⚠️ [StockInfoHeader] current 필드가 Map이 아님: ${data['current'].runtimeType}');
              }
            } else {
              print('⚠️ [StockInfoHeader] current 필드가 null입니다');
            }
            
                   // chart 데이터 안전하게 처리 (List 또는 Map 모두 지원)
                   Map<String, dynamic>? chart;
                   if (data['chart'] != null) {
                     if (data['chart'] is Map<String, dynamic>) {
                       chart = data['chart'] as Map<String, dynamic>;
                       print('🔍 [StockInfoHeader] chart 데이터 추출 성공(Map): $chart');
                     } else if (data['chart'] is List<dynamic>) {
                       // List인 경우 첫 번째 요소(최신 데이터) 사용
                       final chartList = data['chart'] as List<dynamic>;
                       if (chartList.isNotEmpty) {
                         chart = chartList.first as Map<String, dynamic>;
                         print('🔍 [StockInfoHeader] chart 데이터 추출 성공(List 첫 번째): $chart');
                         print('🔍 [StockInfoHeader] chart List 길이: ${chartList.length}');
                         print('🔍 [StockInfoHeader] 최신 차트 날짜: ${chart['date']}');
                       } else {
                         print('⚠️ [StockInfoHeader] chart List가 비어있습니다');
                       }
                     } else {
                       print('⚠️ [StockInfoHeader] chart 필드가 Map도 List도 아님: ${data['chart'].runtimeType}');
                     }
                   } else {
                     print('⚠️ [StockInfoHeader] chart 필드가 null입니다');
                   }
            
            // chart 데이터를 우선하고 current 데이터를 보조로 사용
            firestoreData = {
              ...?current,  // current 데이터 (기본)
              ...?chart,    // chart 데이터 (우선) - 최신 거래량 등
            };
            
            print('🔍 [StockInfoHeader] Firestore 구독 데이터: $firestoreData');
            print('🔍 [StockInfoHeader] current 데이터: $current');
            print('🔍 [StockInfoHeader] chart 데이터: $chart');
          } catch (e) {
            print('❌ [StockInfoHeader] Firestore 데이터 파싱 오류: $e');
            firestoreData = {};
          }
        } else {
          print('❌ [StockInfoHeader] Firestore 문서가 존재하지 않습니다: $stockCode');
        }
        
        return _buildStockInfoWidget(firestoreData, stockData);
      },
    );
  }
  
  Widget _buildLoadingWidget() {
    return Container(
      height: 120,
      child: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
  
  Widget _buildStockInfoWidget(Map<String, dynamic> firestoreData, Map<String, dynamic> stockData) {
    // 🔍 current 필드 안의 데이터를 읽어야 함
    final currentData = stockData['current'] as Map<String, dynamic>? ?? {};
    print('🔍 [StockInfoHeader] currentData: $currentData');
    
    // 🔍 Firestore 데이터 우선 사용 (chart 데이터 우선)
    final currentPrice = _toDouble(firestoreData['currentPrice']) ?? 
                         _toDouble(firestoreData['close']) ?? 
                         _toDouble(currentData['currentPrice']) ?? 
                         _toDouble(stockData['currentPrice']) ?? 
                         _toDouble(stockData['prpr']) ?? 0.0;
    
    // 전일종가 계산 (chart의 close를 전일종가로 사용)
    double prevClose = _toDouble(firestoreData['prevClose']) ?? 
                       _toDouble(currentData['prevClose']) ?? 
                       _toDouble(stockData['prevClose']) ?? 
                       _toDouble(stockData['stck_prdy_clpr']) ?? 0.0;
    
    // prevClose가 0이면 chart의 close를 전일종가로 사용
    if (prevClose == 0) {
      prevClose = _toDouble(firestoreData['close']) ?? 0.0;
      print('🔍 [StockInfoHeader] prevClose가 0이므로 chart close를 전일종가로 사용: $prevClose');
    }
    
    print('🔍 [StockInfoHeader] 최종 현재가: $currentPrice');
    print('🔍 [StockInfoHeader] 전일종가: $prevClose');
    
    // Functions에서 diff, rate 필드를 저장하지 않으므로 계산
    final change = currentPrice - prevClose;
    double finalChangeRate = 0.0;
    
    print('🔍 [StockInfoHeader] 등락률 계산 시작: $stockCode');
    print('🔍 [StockInfoHeader] 현재가: $currentPrice, 전일종가: $prevClose, 변동: $change');
    
    // prevClose가 0이면 등락률 계산 불가
    if (prevClose > 0) {
      finalChangeRate = (change / prevClose) * 100.0;
      print('✅ [StockInfoHeader] 등락률 계산 성공: ${finalChangeRate.toStringAsFixed(2)}%');
    } else {
      print('⚠️ [StockInfoHeader] 전일종가가 0이므로 등락률 계산 불가: $stockCode');
      // 전일종가가 0이면 현재가를 기준으로 임시 계산 (정확하지 않음)
      if (currentPrice > 0) {
        finalChangeRate = 0.0; // 정확한 계산 불가
        print('⚠️ [StockInfoHeader] 전일종가 없음 - 등락률을 0%로 설정');
      }
    }
    
    // 🔍 Firestore 데이터 우선 사용 (current + chart)
    final openPrice = _toDouble(firestoreData['open']) ?? 
                     _toDouble(currentData['open']) ?? 
                     _toDouble(stockData['open']) ?? 
                     _toDouble(stockData['openPrice']) ?? 
                     _toDouble(stockData['stck_oprc']) ?? 0.0;
    final highPrice = _toDouble(firestoreData['high']) ?? 
                     _toDouble(currentData['high']) ?? 
                     _toDouble(stockData['high']) ?? 
                     _toDouble(stockData['highPrice']) ?? 
                     _toDouble(stockData['stck_hgpr']) ?? 0.0;
    final lowPrice = _toDouble(firestoreData['low']) ?? 
                    _toDouble(currentData['low']) ?? 
                    _toDouble(stockData['low']) ?? 
                    _toDouble(stockData['lowPrice']) ?? 
                    _toDouble(stockData['stck_lwpr']) ?? 0.0;
    // 🔍 거래량 데이터 소스 우선순위: chart > current > stockData
    double volume = 0.0;
    
    // 1순위: chart 데이터 (최신)
    if (firestoreData['volume'] != null) {
      volume = _toDouble(firestoreData['volume']);
      print('🔍 [StockInfoHeader] chart 거래량 사용: $volume');
    }
    // 2순위: current 데이터
    else if (currentData['volume'] != null) {
      volume = _toDouble(currentData['volume']);
      print('🔍 [StockInfoHeader] current 거래량 사용: $volume');
    }
    // 3순위: stockData (과거 데이터)
    else {
      volume = _toDouble(stockData['volume']) ?? 0.0;
      print('⚠️ [StockInfoHeader] stockData 거래량 사용 (과거 데이터): $volume');
    }
    
    print('🔍 [StockInfoHeader] 거래량 데이터 소스 확인:');
    print('🔍 [StockInfoHeader] Firestore 거래량: ${firestoreData['volume']}');
    print('🔍 [StockInfoHeader] currentData 거래량: ${currentData['volume']}');
    print('🔍 [StockInfoHeader] stockData 거래량: ${stockData['volume']}');
    print('🔍 [StockInfoHeader] 최종 거래량: $volume');
    
    // 거래량이 0이거나 과거 데이터면 Firestore Functions 호출 시도 (비동기, 빈도 제한)
    if (volume == 0 || (stockData['volume'] != null && volume == _toDouble(stockData['volume']))) {
      print('⚠️ [StockInfoHeader] 거래량이 0이거나 과거 데이터입니다. Firestore Functions 호출 시도...');
      print('⚠️ [StockInfoHeader] 현재 거래량: $volume, stockData 거래량: ${stockData['volume']}');
      RemoteKisService.instance.ensureChartAndAnalyze(
        uid: 'debug-user',
        symbol: stockCode,
      ).then((success) {
        if (success) {
          print('✅ [StockInfoHeader] Firestore Functions 호출 완료: $stockCode');
        } else {
          print('⏸️ [StockInfoHeader] Firestore Functions 호출 건너뜀 (빈도 제한): $stockCode');
        }
      }).catchError((e) {
        print('❌ [StockInfoHeader] Firestore Functions 호출 실패: $e');
      });
    }
    final market = (stockData['market']?.toString().toUpperCase() ?? '');
    final exchange = (stockData['exchange']?.toString().toUpperCase() ?? '');
    final bool isNasdaq = _isNasdaqStock(stockCode) || market == 'NASDAQ' || exchange == 'NAS';
    
    // 가격이 0인 경우 캐시에서 확인
    double finalCurrentPrice = currentPrice;
    if (finalCurrentPrice <= 0) {
      final cachedData = AppDataManager.instance.getCachedPrice(stockCode);
      if (cachedData != null) {
        final cachedPrice = _toDouble(cachedData['prpr']);
        if (cachedPrice > 0) {
          finalCurrentPrice = cachedPrice;
          print('🔍 [StockInfoHeader] 캐시에서 가격 복구: $finalCurrentPrice');
        }
      }
    }
    
    print('🔍 [StockInfoHeader] 최종 현재가: $finalCurrentPrice');
    print('🔍 [StockInfoHeader] 최종 거래량: $volume');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 종목명과 액션 버튼들
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 종목명 (전체 표시)
                    Text(
                      stockName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 4),
                    // 종목 코드만 표시
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getMarketColor(stockCode).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _getMarketColor(stockCode).withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        stockCode,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _getMarketColor(stockCode),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onFavoriteTap,
                icon: Icon(
                  AppDataManager.instance.isInWatchlist(stockCode)
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: AppDataManager.instance.isInWatchlist(stockCode)
                      ? Colors.red
                      : Colors.grey,
                ),
              ),
              IconButton(
                onPressed: onSearchTap,
                icon: const Icon(Icons.search),
              ),
              IconButton(
                onPressed: onListTap,
                icon: const Icon(Icons.list),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // 현재가와 변동률
          Row(
            children: [
              Expanded(
                child: Text(
                  isNasdaq ? '\$${_formatNumber(finalCurrentPrice, decimals: 2)}' : '${_formatNumber(finalCurrentPrice)}원',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: change >= 0 ? Colors.red.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${change >= 0 ? '+' : ''}${isNasdaq ? _formatNumber(change, decimals: 2) : _formatNumber(change)} (${finalChangeRate >= 0 ? '+' : ''}${finalChangeRate.toStringAsFixed(2)}%)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: change >= 0 ? Colors.red : Colors.blue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // 전일 종가
          Text(
            isNasdaq
                ? '전일: \$${_formatNumber(_toDouble(stockData['prev_close']) ?? _toDouble(stockData['stck_prdy_clpr']), decimals: 2)}'
                : '전일: ${_formatNumber(_toDouble(stockData['prev_close']) ?? _toDouble(stockData['stck_prdy_clpr']))}원',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),
          
          // 시가, 고가, 저가, 거래량
          Row(
            children: [
              Expanded(
                child: _buildInfoItem('시가', isNasdaq ? '\$${_formatNumber(openPrice, decimals: 2)}' : '${_formatNumber(openPrice)}원'),
              ),
              Expanded(
                child: _buildInfoItem('고가', isNasdaq ? '\$${_formatNumber(highPrice, decimals: 2)}' : '${_formatNumber(highPrice)}원', Colors.red),
              ),
              Expanded(
                child: _buildInfoItem('저가', isNasdaq ? '\$${_formatNumber(lowPrice, decimals: 2)}' : '${_formatNumber(lowPrice)}원', Colors.blue),
              ),
              Expanded(
                child: _buildInfoItem('거래량', _formatNumber(volume)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, [Color? valueColor]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: valueColor ?? Colors.black,
          ),
        ),
      ],
    );
  }

  /// 개선된 거래량 데이터 조회 로직 (종목별 정확한 데이터)
  double _getCurrentVolume(String stockCode, Map<String, dynamic> currentData, Map<String, dynamic> stockData) {
    print('🔍 [StockInfoHeader] 거래량 조회 시작: $stockCode');
    
    // 1. current 필드에서 우선 읽기 (Functions에서 저장하는 필드명)
    double volume = _toDouble(currentData['volume']) ?? 
                    _toDouble(stockData['volume']) ?? 
                    _toDouble(stockData['tvol']) ?? 
                    _toDouble(stockData['acml_vol']) ?? 0.0;
    
    if (volume > 0) {
      print('🔍 [StockInfoHeader] 현재 데이터 거래량 사용: $volume (tvol/acml_vol/volume)');
      return volume;
    }
    
    // 2. 캐시된 데이터에서 해당 종목의 거래량 확인
      final cachedData = AppDataManager.instance.getCachedStockData(stockCode);
    volume = _toDouble(cachedData['tvol']) ?? 
             _toDouble(cachedData['acml_vol']) ?? 
             _toDouble(cachedData['volume']) ?? 0.0;
      
      if (volume > 0) {
      print('🔍 [StockInfoHeader] 캐시 데이터 거래량 사용: $volume');
      return volume;
    }
    
    // 3. 차트 데이터에서 해당 종목의 최신 거래량 확인
        try {
          final cachedChart = AppDataManager.instance.getCachedChartData(stockCode);
          if (cachedChart.isNotEmpty) {
        // 최신 거래일 데이터 확인 (오늘 우선, 없으면 최신)
            final today = DateTime.now();
            final todayStr = '${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';
            
            // 오늘 날짜 데이터 우선 확인
            for (final chartData in cachedChart.reversed) {
              final chartDate = chartData['date']?.toString() ?? '';
              if (chartDate == todayStr) {
                final chartVol = _toDouble(chartData['volume']);
                if (chartVol > 0) {
                  volume = chartVol;
              print('🔍 [StockInfoHeader] 오늘 차트 거래량 사용: $volume (날짜: $chartDate)');
              return volume;
                }
              }
            }
            
            // 오늘 데이터가 없으면 최신 데이터 사용
              final last = cachedChart.last;
              final chartVol = _toDouble(last['volume']);
              if (chartVol > 0) {
                volume = chartVol;
                print('🔍 [StockInfoHeader] 최신 거래량 사용: $volume');
            }
          }
        } catch (e) {
          print('❌ [StockInfoHeader] 거래량 조회 실패: $e');
    }
    
    return volume;
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  String _formatNumber(dynamic value, {int decimals = 0}) {
    if (value == null) return decimals > 0 ? '0.${'0' * decimals}' : '0';
    final num = double.tryParse(value.toString()) ?? 0.0;
    final fixed = num.toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    if (decimals == 0) return intPart;
    final frac = parts.length > 1 ? parts[1] : ''.padRight(decimals, '0');
    return '$intPart.$frac';
  }

  bool _isNasdaqStock(String stockCode) {
    return stockCode.length <= 5 &&
           stockCode == stockCode.toUpperCase() &&
           !RegExp(r'^\d+$').hasMatch(stockCode);
  }

  Color _getMarketColor(String stockCode) {
    if (_isNasdaqStock(stockCode)) {
      return Colors.green; // 해외주식 (나스닥)
    } else if (stockCode.startsWith('0') || stockCode.startsWith('1')) {
      return Colors.orange; // 코스닥
    } else {
      return Colors.blue; // 코스피
    }
  }

  String _getInvestmentStyleText() {
    try {
      final styleManager = InvestmentStyleManager();
      final style = styleManager.currentStyle;
      switch (style.toString()) {
        case 'InvestmentStyle.conservative':
          return '안정적';
        case 'InvestmentStyle.moderate':
          return '일반적';
        case 'InvestmentStyle.aggressive':
          return '공격적';
        default:
          return '일반적';
      }
    } catch (e) {
      return '일반적';
    }
  }

  Color _getInvestmentStyleColor() {
    try {
      final styleManager = InvestmentStyleManager();
      final style = styleManager.currentStyle;
      switch (style.toString()) {
        case 'InvestmentStyle.conservative':
          return Colors.blue; // 안정적 - 파란색
        case 'InvestmentStyle.moderate':
          return Colors.green; // 일반적 - 초록색
        case 'InvestmentStyle.aggressive':
          return Colors.red; // 공격적 - 빨간색
        default:
          return Colors.green;
      }
    } catch (e) {
      return Colors.green;
    }
  }
}
