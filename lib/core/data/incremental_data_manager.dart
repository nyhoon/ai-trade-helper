import 'dart:async';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../database/repositories/historical_data_repository.dart';
import '../database/repositories/current_price_repository.dart';
import '../api/kis_unified_api_service.dart';

/// 증분 데이터 매니저 - 100일 로딩 후 3-4일 갱신
class IncrementalDataManager {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final HistoricalDataRepository _historicalDataRepo = HistoricalDataRepository();
  final CurrentPriceRepository _currentPriceRepo = CurrentPriceRepository();
  
  KisUnifiedApiService? _unifiedApiService;
  Timer? _updateTimer;
  bool _isInitialized = false;

  /// 초기화 여부
  bool get isInitialized => _isInitialized;

  /// 초기화
  Future<void> initialize({KisUnifiedApiService? unifiedApiService}) async {
    if (_isInitialized) return;
    
    _unifiedApiService = unifiedApiService;
    _isInitialized = true;
    
    print('🔄 증분 데이터 매니저 초기화 완료');
  }

  /// 관심종목과 보유종목의 초기 데이터 로딩 (100일)
  Future<void> loadInitialData() async {
    if (!_isInitialized) {
      throw Exception('증분 데이터 매니저가 초기화되지 않았습니다.');
    }

    print('📊 초기 데이터 로딩 시작 (100일)...');

    try {
      // 1. 활성 종목 목록 조회
      final activeStocks = await _getActiveStocks();
      if (activeStocks.isEmpty) {
        print('⚠️ 활성 종목이 없습니다.');
        return;
      }

      print('📈 ${activeStocks.length}개 종목의 초기 데이터 로딩 중...');

      // 2. 각 종목별로 100일 차트 데이터 로딩
      for (final stock in activeStocks) {
        await _loadStockInitialData(stock['stock_code'], stock['market']);
        
        // API 호출 제한 방지를 위한 딜레이
        await Future.delayed(const Duration(milliseconds: 100));
      }

      // 3. 현재가 데이터 로딩
      await _loadCurrentPriceData(activeStocks);

      // 4. 동기화 상태 업데이트
      await _dbHelper.updateSyncStatus('chart');
      await _dbHelper.updateSyncStatus('price');

      print('✅ 초기 데이터 로딩 완료');
    } catch (e) {
      print('❌ 초기 데이터 로딩 실패: $e');
      rethrow;
    }
  }

  /// 증분 업데이트 시작 (1분마다)
  Future<void> startIncrementalUpdate() async {
    if (!_isInitialized) {
      throw Exception('증분 데이터 매니저가 초기화되지 않았습니다.');
    }

    print('🔄 증분 업데이트 시작 (1분마다)...');

    // 기존 타이머 정리
    _updateTimer?.cancel();

    // 1분마다 증분 업데이트 실행
    _updateTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      await _performIncrementalUpdate();
    });
  }

  /// 증분 업데이트 중지
  void stopIncrementalUpdate() {
    _updateTimer?.cancel();
    _updateTimer = null;
    print('⏹️ 증분 업데이트 중지');
  }

  /// 증분 업데이트 수행
  Future<void> _performIncrementalUpdate() async {
    try {
      print('🔄 증분 업데이트 실행 중...');

      // 1. 활성 종목 목록 조회
      final activeStocks = await _getActiveStocks();
      if (activeStocks.isEmpty) return;

      // 2. 각 종목별로 최신 3-4일 데이터만 업데이트
      for (final stock in activeStocks) {
        await _updateStockIncrementalData(stock['stock_code'], stock['market']);
        
        // API 호출 제한 방지를 위한 딜레이
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // 3. 현재가 데이터 업데이트
      await _updateCurrentPriceData(activeStocks);

      // 4. 동기화 상태 업데이트
      await _dbHelper.updateSyncStatus('chart');
      await _dbHelper.updateSyncStatus('price');

      print('✅ 증분 업데이트 완료');
    } catch (e) {
      print('❌ 증분 업데이트 실패: $e');
    }
  }

  /// 활성 종목 목록 조회
  Future<List<Map<String, dynamic>>> _getActiveStocks() async {
    final db = await _dbHelper.database;

    final result = await db.rawQuery('''
      SELECT DISTINCT stock_code, market FROM (
        SELECT stock_code, market FROM watchlist WHERE is_active = 1
        UNION
        SELECT stock_code, market FROM holdings
      )
    ''');

    return result;
  }

  /// 특정 종목의 초기 데이터 로딩 (100일)
  Future<void> _loadStockInitialData(String stockCode, String market) async {
    try {
      // 1. 최신 날짜 확인
      final latestDate = await _historicalDataRepo.getLatestDate(stockCode);
      
      // 2. 100일 전 날짜 계산
      final endDate = latestDate ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
      final startDate = DateFormat('yyyy-MM-dd').format(
        DateTime.now().subtract(const Duration(days: 100))
      );

      // 3. API에서 차트 데이터 조회 (@api/ 확장 파일의 메서드 사용)
      if (_unifiedApiService != null) {
        final chartData = await _unifiedApiService!.getDomesticDailyChart(stockCode: stockCode, count: 100);
        
        if (chartData.isNotEmpty) {
          print('📊 $stockCode 초기 데이터 로딩: ${chartData.length}개 데이터');
          
          // API 응답 데이터 상세 로깅
          for (int i = 0; i < chartData.length; i++) {
            final item = chartData[i];
            print('  [$i] 날짜: ${item['date']}, 거래량: ${item['volume']}, 종가: ${item['close']}');
          }
          
          // 4. DB에 저장 (개선된 날짜 변환 로직 사용)
          final bars = chartData.map((e) {
            final originalDate = e['date']?.toString() ?? '';
            final formattedDate = _formatDateForStorage(originalDate);
            
            print('  - 원본 날짜: $originalDate → 변환된 날짜: $formattedDate');
            
            return {
              'date': formattedDate,
              'open': (e['open'] ?? 0.0).toDouble(),
              'high': (e['high'] ?? 0.0).toDouble(),
              'low': (e['low'] ?? 0.0).toDouble(),
              'close': (e['close'] ?? 0.0).toDouble(),
              'volume': (e['volume'] ?? 0).toInt(),
            };
          }).toList();

          await _historicalDataRepo.upsertDailyBars(
            stockCode: stockCode,
            market: market,
            bars: bars,
            keepDays: 100,
          );
          print('📊 $stockCode: ${bars.length}일 차트 데이터 로딩 완료');
        }
      }
    } catch (e) {
      print('⚠️ $stockCode 초기 데이터 로딩 실패: $e');
    }
  }

  /// 특정 종목의 증분 데이터 업데이트 (7일 범위로 확장)
  Future<void> _updateStockIncrementalData(String stockCode, String market) async {
    try {
      // 1. 최신 날짜 확인
      final latestDate = await _historicalDataRepo.getLatestDate(stockCode);
      if (latestDate == null) {
        // 데이터가 없으면 초기 로딩 수행
        await _loadStockInitialData(stockCode, market);
        return;
      }

      // 2. 최신 날짜로부터 7일 전까지 업데이트 (4일 → 7일로 확장)
      final latestDateTime = DateFormat('yyyy-MM-dd').parse(latestDate);
      final updateStartDate = DateFormat('yyyy-MM-dd').format(
        latestDateTime.subtract(const Duration(days: 7)) // 4 → 7로 변경
      );
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      print('📊 $stockCode 증분 업데이트: $updateStartDate ~ $today (최신: $latestDate)');

      // 3. API에서 최신 데이터 조회 (count를 늘려서 충분한 데이터 확보)
      if (_unifiedApiService != null) {
        // @api/ 확장 파일의 메서드 사용
        final chartData = await _unifiedApiService!.getDomesticDailyChart(stockCode: stockCode, count: 20); // 10 → 20으로 증가
        
        if (chartData.isNotEmpty) {
          print('📊 $stockCode API 응답: ${chartData.length}개 데이터');
          
          // API 응답 데이터 상세 로깅
          for (int i = 0; i < chartData.length; i++) {
            final item = chartData[i];
            print('  [$i] 날짜: ${item['date']}, 거래량: ${item['volume']}, 종가: ${item['close']}');
          }
          
          // 4. 최신 데이터만 필터링하여 저장 (통일된 방식 사용)
          final newData = chartData.where((data) {
            final dataDate = data['date'] ?? '';
            return dataDate.compareTo(updateStartDate) >= 0;
          }).toList();

          print('📊 $stockCode 필터링 후: ${newData.length}개 신규 데이터');

          if (newData.isNotEmpty) {
            // 개선된 날짜 변환 로직
            final bars = newData.map((e) {
              final originalDate = e['date']?.toString() ?? '';
              final formattedDate = _formatDateForStorage(originalDate);
              
              print('  - 원본 날짜: $originalDate → 변환된 날짜: $formattedDate');
              
              return {
                'date': formattedDate,
                'open': (e['open'] ?? 0.0).toDouble(),
                'high': (e['high'] ?? 0.0).toDouble(),
                'low': (e['low'] ?? 0.0).toDouble(),
                'close': (e['close'] ?? 0.0).toDouble(),
                'volume': (e['volume'] ?? 0).toInt(),
              };
            }).toList();

            await _historicalDataRepo.upsertDailyBars(
              stockCode: stockCode,
              market: market,
              bars: bars,
              keepDays: 100,
            );
            print('📈 $stockCode: ${bars.length}일 증분 업데이트 완료');
          } else {
            print('⚠️ $stockCode: 신규 데이터 없음 (이미 최신 상태)');
          }
        }
      }
    } catch (e) {
      print('⚠️ $stockCode 증분 업데이트 실패: $e');
    }
  }

  /// 개선된 날짜 변환 로직
  String _formatDateForStorage(dynamic dateValue) {
    if (dateValue == null) return '';
    
    String dateStr = dateValue.toString();
    
    // 이미 yyyyMMdd 형식인 경우
    if (dateStr.length == 8 && RegExp(r'^\d{8}$').hasMatch(dateStr)) {
      return dateStr;
    }
    
    // yyyy-MM-dd 형식인 경우
    if (dateStr.contains('-')) {
      return dateStr.replaceAll('-', '');
    }
    
    // 다른 형식인 경우 DateTime으로 파싱 시도
    try {
      final date = DateTime.parse(dateStr);
      return '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    } catch (e) {
      print('❌ 날짜 파싱 실패: $dateStr - $e');
      return '';
    }
  }

  /// 현재가 데이터 로딩
  Future<void> _loadCurrentPriceData(List<Map<String, dynamic>> stocks) async {
    try {
      if (_unifiedApiService == null) return;

      final priceDataList = <Map<String, dynamic>>[];

      for (final stock in stocks) {
        try {
          final stockCode = stock['stock_code'] as String;
          final market = stock['market'] as String;

          // API에서 현재가 조회 (@api/ 확장 파일의 메서드 사용)
          final priceData = await _unifiedApiService!.getStockPrice(stockCode);
          
          if (priceData != null) {
            priceDataList.add({
              'stock_code': stockCode,
              'market': market,
              'current_price': priceData['current_price'] ?? 0.0,
              'prev_close': priceData['prev_close'] ?? 0.0,
              'change_amount': priceData['change_amount'] ?? 0.0,
              'change_rate': priceData['change_rate'] ?? 0.0,
              'volume': priceData['volume'] ?? 0,
              'trade_amount': priceData['trade_amount'] ?? 0.0,
              'high_price': priceData['high_price'] ?? 0.0,
              'low_price': priceData['low_price'] ?? 0.0,
              'open_price': priceData['open_price'] ?? 0.0,
              'market_cap': priceData['market_cap'],
              'per': priceData['per'],
              'pbr': priceData['pbr'],
            });
          }

          // API 호출 제한 방지를 위한 딜레이
          await Future.delayed(const Duration(milliseconds: 50));
        } catch (e) {
          print('⚠️ ${stock['stock_code']} 현재가 조회 실패: $e');
        }
      }

      if (priceDataList.isNotEmpty) {
        await _currentPriceRepo.insertMultipleCurrentPrice(priceDataList);
        print('💰 ${priceDataList.length}개 종목 현재가 데이터 로딩 완료');
      }
    } catch (e) {
      print('❌ 현재가 데이터 로딩 실패: $e');
    }
  }

  /// 현재가 데이터 업데이트
  Future<void> _updateCurrentPriceData(List<Map<String, dynamic>> stocks) async {
    try {
      if (_unifiedApiService == null) return;

      final priceDataList = <Map<String, dynamic>>[];

      for (final stock in stocks) {
        try {
          final stockCode = stock['stock_code'] as String;
          final market = stock['market'] as String;

          // API에서 현재가 조회 (@api/ 확장 파일의 메서드 사용)
          final priceData = await _unifiedApiService!.getStockPrice(stockCode);
          
          if (priceData != null) {
            priceDataList.add({
              'stock_code': stockCode,
              'market': market,
              'current_price': priceData['current_price'] ?? 0.0,
              'prev_close': priceData['prev_close'] ?? 0.0,
              'change_amount': priceData['change_amount'] ?? 0.0,
              'change_rate': priceData['change_rate'] ?? 0.0,
              'volume': priceData['volume'] ?? 0,
              'trade_amount': priceData['trade_amount'] ?? 0.0,
              'high_price': priceData['high_price'] ?? 0.0,
              'low_price': priceData['low_price'] ?? 0.0,
              'open_price': priceData['open_price'] ?? 0.0,
              'market_cap': priceData['market_cap'],
              'per': priceData['per'],
              'pbr': priceData['pbr'],
            });
          }

          // API 호출 제한 방지를 위한 딜레이
          await Future.delayed(const Duration(milliseconds: 30));
        } catch (e) {
          print('⚠️ ${stock['stock_code']} 현재가 업데이트 실패: $e');
        }
      }

      if (priceDataList.isNotEmpty) {
        await _currentPriceRepo.insertMultipleCurrentPrice(priceDataList);
        print('💰 ${priceDataList.length}개 종목 현재가 업데이트 완료');
      }
    } catch (e) {
      print('❌ 현재가 데이터 업데이트 실패: $e');
    }
  }

  /// 단일 종목 현재가 데이터 로딩 (공개 API)
  Future<void> loadCurrentPriceData(String stockCode, String market) async {
    if (!_isInitialized) {
      throw Exception('증분 데이터 매니저가 초기화되지 않았습니다.');
    }

    final stocks = [
      {
        'stock_code': stockCode,
        'market': market,
      }
    ];
    await _loadCurrentPriceData(stocks);
  }

  /// 특정 종목 추가 시 데이터 로딩
  Future<void> loadStockData(String stockCode, String market) async {
    if (!_isInitialized) {
      throw Exception('증분 데이터 매니저가 초기화되지 않았습니다.');
    }

    print('📊 $stockCode 데이터 로딩 시작...');

    try {
      // 1. 초기 차트 데이터 로딩
      await _loadStockInitialData(stockCode, market);

      // 2. 현재가 데이터 로딩
      final stocks = [{'stock_code': stockCode, 'market': market}];
      await _loadCurrentPriceData(stocks);

      print('✅ $stockCode 데이터 로딩 완료');
    } catch (e) {
      print('❌ $stockCode 데이터 로딩 실패: $e');
      rethrow;
    }
  }

  /// 특정 종목 제거 시 데이터 정리
  Future<void> cleanupStockData(String stockCode) async {
    if (!_isInitialized) {
      throw Exception('증분 데이터 매니저가 초기화되지 않았습니다.');
    }

    print('🧹 $stockCode 데이터 정리 시작...');

    try {
      // 1. 차트 데이터 삭제
      await _historicalDataRepo.deleteByStockCode(stockCode);

      // 2. 현재가 데이터 삭제
      await _currentPriceRepo.deleteCurrentPrice(stockCode);

      print('✅ $stockCode 데이터 정리 완료');
    } catch (e) {
      print('❌ $stockCode 데이터 정리 실패: $e');
      rethrow;
    }
  }

  /// 데이터 동기화 상태 조회
  Future<Map<String, dynamic>> getSyncStatus() async {
    final syncStatus = await _dbHelper.getSyncStatus();
    // 차트 데이터 통계는 HistoricalDataRepository에서 처리
    final chartStats = {'total_stocks': 0, 'total_records': 0, 'avg_records_per_stock': 0.0};
    final priceStats = await _currentPriceRepo.getCurrentPriceStats();

    return {
      'sync_status': syncStatus,
      'chart_stats': chartStats,
      'price_stats': priceStats,
      'is_initialized': _isInitialized,
      'is_running': _updateTimer != null,
    };
  }

  /// 데이터 정리 실행
  Future<void> cleanupData() async {
    if (!_isInitialized) {
      throw Exception('증분 데이터 매니저가 초기화되지 않았습니다.');
    }

    print('🧹 데이터 정리 시작...');

    try {
      // 1. 비활성 종목의 차트 데이터 정리
      // 비활성 차트 데이터 정리는 HistoricalDataRepository에서 처리
      final chartDeleted = 0;
      print('📊 비활성 종목 차트 데이터 정리: $chartDeleted개 삭제');

      // 2. 오래된 현재가 데이터 정리
      final priceDeleted = await _currentPriceRepo.cleanupOldCurrentPrice();
      print('💰 오래된 현재가 데이터 정리: $priceDeleted개 삭제');

      // 3. DB 최적화
      await _dbHelper.optimizeDatabase();

      print('✅ 데이터 정리 완료');
    } catch (e) {
      print('❌ 데이터 정리 실패: $e');
      rethrow;
    }
  }

  /// 리소스 정리
  void dispose() {
    stopIncrementalUpdate();
    _isInitialized = false;
    print('🗑️ 증분 데이터 매니저 리소스 정리 완료');
  }
}
