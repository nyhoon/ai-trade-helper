import 'package:flutter/material.dart';
import 'dart:async';
import '../../core/remote/analysis_functions_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/data/recommended_stocks_data.dart';
import '../../core/ai/ai_recommendation_service.dart';
import '../../core/data/app_data_manager.dart';
import '../../features/analysis/usecases/top_stocks_usecase.dart';
import '../../features/analysis/models/top_stocks_state.dart';
import '../../features/analysis/viewmodels/top_stocks_viewmodel.dart';
import '../../core/api/unified_stock_service.dart';
import '../../core/analysis/unified_analysis_service.dart';
import '../../core/trading/investment_style_manager.dart';
import '../../core/database/repositories/top_stocks_repository.dart';
import '../../core/data/freshness_manager.dart';
import '../../core/utils/stock_filter_utils.dart';
import '../../core/trading/market_time_validator.dart';
import 'widgets/freshness_indicator.dart';
import '../../core/remote/remote_kis_service.dart';

/// 실시간 추천종목 화면
/// 나스닥, 코스피, 코스닥 각각 상위 10개 종목을 실시간으로 표시
class RecommendedStocksScreen extends StatefulWidget {
  const RecommendedStocksScreen({super.key});

  @override
  State<RecommendedStocksScreen> createState() => _RecommendedStocksScreenState();
}

class _RecommendedStocksScreenState extends State<RecommendedStocksScreen> with WidgetsBindingObserver {
  final AnalysisFunctionsService _functions = AnalysisFunctionsService();
  final TopStocksUseCase _topStocksUseCase = TopStocksUseCase();
  final TopStocksViewModel _topStocksViewModel = TopStocksViewModel();
  // 서버 이전에 따라 로컬 백그라운드 계산 제거. 컴파일 안전을 위해 최소 필드만 유지
  bool _isBackgroundServiceEnabled = false;
  bool _isBackgroundServiceRunning = false;
  double _calculationProgress = 0.0;
  String _currentMarket = '';
  String _currentStock = '';
  int _processedCount = 0;
  int _totalCount = 0;
  int _progressTick = 0;
  int _freshnessMinutes = 5;

  
  // MVI 패턴 상태 관리
  TopStocksViewState _currentState = const TopStocksViewState();
  StreamSubscription<TopStocksViewState>? _stateSubscription;
  StreamSubscription<TopStocksSideEffect>? _sideEffectSubscription;
  
  // 시장별 상위 종목 데이터
  Map<String, List<TopStockItem>> _marketTopStocks = {
    'NASDAQ': [],  // 나스닥
    'KOSPI': [],   // 코스피
    'KOSDAQ': [],  // 코스닥
  };
  
  bool _isLoading = true;
  Set<String> _watchlistCodes = {};
  
  // 서비스 상태(서버 동기화 기준)
  String _serviceStatus = '초기화 중...';
  bool _isServiceRunning = false;
  int _calculatedStocksCount = 0;
  String _lastUpdateTime = '';
  String? _errorMessage;
  Timer? _autoRefreshTimer;
  Timer? _serviceStatusTimer;
  bool _serviceStatusMonitorStarted = false;
  
  // 로컬 데이터 조회 상태
  bool _isLoadingLocalData = false;
  int _localDataProgress = 0;
  int _localDataTotal = 0;
  String _currentLoadingTask = '';
  
  // 거래대금 설정
  double _minTradingAmount = 1000000000; // 10억원
  final List<double> _tradingAmountOptions = [
    100000000,    // 1억원
    500000000,    // 5억원
    1000000000,   // 10억원
    5000000000,   // 50억원
    10000000000,  // 100억원
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeScreenFast();
    _prefetchTopCandidates();
  }

// 아래는 컴파일 안전을 위한 더미 클래스. 서버 이전 후 제거 대상

  /// 시장별 즉시 스캔 버튼 묶음
  Widget _buildMarketScanButtons() {
    final ButtonStyle style = OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: BorderSide(color: Colors.white.withOpacity(0.5)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    );
    return Row(
      children: [
        OutlinedButton(
          onPressed: () => _startMarketScan('KOSDAQ'),
          style: style,
          child: const Text('코스닥 스캔'),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: () => _startMarketScan('KOSPI'),
          style: style,
          child: const Text('코스피 스캔'),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: () => _startMarketScan('NASDAQ'),
          style: style,
          child: const Text('나스닥 스캔'),
        ),
      ],
    );
  }
  
  /// 시장별 스캔 시작
  Future<void> _startMarketScan(String market) async {
    try {
      setState(() {
        _serviceStatus = '$market 시장 스캔 시작...';
        _isServiceRunning = true;
      });
      
      // 스캔 시작 전 상태 표시
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$market 시장 전체 종목 분석을 시작합니다...'),
          duration: const Duration(seconds: 2),
        ),
      );
      
      // 서버 Top-N은 시장단위 스캔 없이 제공. 필요 시 서버 확장 예정.
      
      setState(() {
        _serviceStatus = '$market 시장 스캔 완료';
        _isServiceRunning = false;
        _lastUpdateTime = DateTime.now().toString().substring(11, 19);
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$market 시장 분석이 완료되었습니다'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      setState(() {
        _serviceStatus = '$market 시장 스캔 실패';
        _isServiceRunning = false;
        _errorMessage = e.toString();
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$market 시장 스캔 실패: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _sideEffectSubscription?.cancel();
    _topStocksViewModel.dispose();
    _autoRefreshTimer?.cancel();
    _serviceStatusTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    // 화면 이탈 시 스캔 중지로 다른 탭/화면 성능 보호
    try {
      if (_isBackgroundServiceEnabled && _isBackgroundServiceRunning) {
        // 서버 이전으로 로컬 백그라운드 서비스 비활성화
        setState(() {
          _isBackgroundServiceRunning = false;
        });
      }
    } catch (_) {}
    // 추천 화면 이탈 시: 409개 중 관심/보유 제외 임시 데이터 정리
    // 서버 이전으로 로컬 AI 서비스 비활성화
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _serviceStatusTimer?.cancel();
      // 앱 비활성화/다른 화면 전환 시 스캔 일시 중지
      try {
        if (_isBackgroundServiceRunning) {
          // 서버 이전으로 로컬 백그라운드 서비스 비활성화
          setState(() {
            _isBackgroundServiceRunning = false;
          });
        }
      } catch (_) {}
    } else if (state == AppLifecycleState.resumed) {
      _startServiceStatusMonitoring();
    }
  }

  /// 빠른 화면 초기화 (최소한의 작업만)
  Future<void> _initializeScreenFast() async {
    try {
      print('🚀 추천종목 화면 빠른 초기화 시작...');
      
      // 즉시 로딩 완료로 표시
      if (mounted) {
        setState(() {
          _isLoading = false;
          _serviceStatus = '준비 완료';
        });
      }
      
      // 백그라운드에서 나머지 작업 수행
      _initializeInBackground();
      
    } catch (e) {
      print('❌ 빠른 초기화 실패: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 백그라운드 초기화 (사용자 경험에 영향 없음)
  Future<void> _initializeInBackground() async {
    try {
      print('🔄 서버 Top-N 초기화 시작...');
      if (mounted) {
        setState(() {
          _marketTopStocks = {
            'NASDAQ': [],
            'KOSPI': [],
            'KOSDAQ': [],
          };
        });
      }
      _startAutoRefreshTimer();
    } catch (e) {
      print('❌ 초기화 실패: $e');
    }
  }
  /// 5분마다 화면 자동 새로고침 (시장 점수/순위 동기화)
  void _startAutoRefreshTimer() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      if (!mounted || _isLoading) return;
      try {
        await _prefetchTopCandidates();
        await _refreshMarketTopStocks();
      } catch (_) {}
    });
  }

  /// 상위 후보 N개 종목의 차트/현재가/분석을 서버에서 먼저 보장
  Future<void> _prefetchTopCandidates({int count = 10}) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'debug-user';
      final symbols = <String>{};
      try {
        final watchlist = await AppDataManager.instance.getWatchlistWithScores();
        for (final it in watchlist.take(count)) {
          final code = it['stock_code'] ?? it['stockCode'];
          if (code is String && code.isNotEmpty) symbols.add(code);
        }
      } catch (_) {}
      try {
        final holdings = await AppDataManager.instance.loadAllHoldings();
        for (final it in holdings.take(count)) {
          final code = it['pdno'] ?? it['stockCode'] ?? it['stock_code'];
          if (code is String && code.isNotEmpty) symbols.add(code);
        }
      } catch (_) {}
      if (symbols.isEmpty) return;
      final limited = symbols.take(count).toList();
      print('🔄 [추천] 상위 후보 프리보장 시작: ${limited.length}개');
      const int concurrency = 5;
      for (int i = 0; i < limited.length; i += concurrency) {
        final batch = limited.sublist(i, (i + concurrency).clamp(0, limited.length));
        await Future.wait(batch.map((code) async {
          try {
            final ok = await RemoteKisService.instance.ensureChartAndAnalyze(uid: uid, symbol: code);
            print('✅ [추천] ensureChartAndAnalyze: $code = $ok');
            await FirebaseFirestore.instance
              .collection('stocks').doc(code)
              .get(const GetOptions(source: Source.server));
          } catch (e) {
            print('⚠️ [추천] 프리보장 실패: $code - $e');
          }
        }));
      }
      print('✅ [추천] 상위 후보 프리보장 완료');
    } catch (e) {
      print('⚠️ [추천] 상위 후보 프리보장 중 오류: $e');
    }
  }

  // 백그라운드 서비스는 서버 이전으로 제거됨

  /// 백그라운드에서 서비스 초기화 (서버 이전으로 축소)
  Future<void> _initializeServiceInBackground() async {
    try {
      setState(() {
        _serviceStatus = '서버 데이터 동기화 중...';
      });
      await _loadMarketTopStocksParallel();
      setState(() {
        _isLoading = false;
        _isServiceRunning = false;
        _serviceStatus = '준비 완료';
      });
    } catch (e) {
      print('❌ 서버 데이터 동기화 실패: $e');
      setState(() {
        _isLoading = false;
        _serviceStatus = '동기화 실패';
        _errorMessage = e.toString();
      });
    }
  }

  /// 백그라운드에서 백그라운드 서비스 설정 (서버 이전으로 비활성화)
  Future<void> _setupBackgroundServiceInBackground() async {
    // 서버 이전으로 로컬 백그라운드 서비스 비활성화
    if (mounted) {
      setState(() {
        _isBackgroundServiceEnabled = false;
        _isBackgroundServiceRunning = false;
      });
    }
    print('ℹ️ 서버 이전으로 로컬 백그라운드 서비스 비활성화됨');
  }

  /// 시장별 상위 종목 로드 (병렬 처리)
  Future<void> _loadMarketTopStocksParallel() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // 3개 시장을 병렬로 처리
      final futures = [
        _topStocksUseCase.getTopStocksByMarket(
          market: 'NASDAQ',
          limit: 10,
          minScore: 0.3,
        ),
        _topStocksUseCase.getTopStocksByMarket(
          market: 'KOSPI',
          limit: 10,
          minScore: 0.3,
        ),
        _topStocksUseCase.getTopStocksByMarket(
          market: 'KOSDAQ',
          limit: 10,
          minScore: 0.3,
        ),
      ];

      final results = await Future.wait(futures);
      final nasdaqStocks = results[0];
      final kospiStocks = results[1];
      final kosdaqStocks = results[2];

      if (mounted) {
        setState(() {
          // 비어있는 결과는 기존 화면을 덮어쓰지 않음 (캐시 기반 초기 Top10 유지)
          if (nasdaqStocks.isNotEmpty) {
          _marketTopStocks['NASDAQ'] = nasdaqStocks.map((stock) => TopStockItem.fromMap(stock)).toList();
          }
          if (kospiStocks.isNotEmpty) {
          _marketTopStocks['KOSPI'] = kospiStocks.map((stock) => TopStockItem.fromMap(stock)).toList();
          }
          if (kosdaqStocks.isNotEmpty) {
          _marketTopStocks['KOSDAQ'] = kosdaqStocks.map((stock) => TopStockItem.fromMap(stock)).toList();
          }
          _isLoading = false;
          _totalCount = _marketTopStocks['NASDAQ']!.length + _marketTopStocks['KOSPI']!.length + _marketTopStocks['KOSDAQ']!.length;
          _processedCount = 0;
        });
      }
      // 보이는 Top10 신선도 검사 후 필요 시 재계산 (관심/보유와 일치성 확보)
      await _refreshTopVisibleScores();

      print('📊 시장별 상위 종목 로드 완료 (병렬 처리):');
      print('   - 나스닥: ${_marketTopStocks['NASDAQ']!.length}개');
      print('   - 코스피: ${_marketTopStocks['KOSPI']!.length}개');
      print('   - 코스닥: ${_marketTopStocks['KOSDAQ']!.length}개');

    } catch (e) {
      print('❌ 시장별 상위 종목 로드 실패: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('상위 종목 로드 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// MVI 패턴 설정
  Future<void> _setupMVI() async {
    // 상태 스트림 구독
    _stateSubscription = _topStocksViewModel.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _currentState = state;
        });
      }
    });
    
    // 사이드 이펙트 스트림 구독
    _sideEffectSubscription = _topStocksViewModel.sideEffectStream.listen((sideEffect) {
      if (mounted) {
        _handleSideEffect(sideEffect);
      }
    });
  }


  /// 백그라운드 서비스 토글
  Future<void> _toggleBackgroundService() async {
    try {
      print('🔄 백그라운드 서비스 토글 시작...');
      
      // UI 상태를 먼저 업데이트 (낙관적 업데이트)
      final previousState = _isBackgroundServiceEnabled;
      setState(() {
        _isBackgroundServiceEnabled = !_isBackgroundServiceEnabled;
      });
      
        // 서버 이전으로 로컬 백그라운드 서비스 비활성화
        // await _backgroundService.toggleService().timeout(
        //   const Duration(seconds: 10),
        //   onTimeout: () {
        //     print('⚠️ 백그라운드 서비스 토글 타임아웃');
        //     throw TimeoutException('백그라운드 서비스 토글 타임아웃', const Duration(seconds: 10));
        //   },
        // );
      
      // 실제 상태 확인 및 업데이트
      setState(() {
        _isBackgroundServiceEnabled = false; // 서버 이전으로 비활성화
        _isBackgroundServiceRunning = false; // 서버 이전으로 비활성화
      });
      
      print('✅ 백그라운드 서비스 토글 완료: enabled=$_isBackgroundServiceEnabled, running=$_isBackgroundServiceRunning');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isBackgroundServiceEnabled 
                ? '백그라운드 계산이 시작되었습니다' 
                : '백그라운드 계산이 중지되었습니다'
            ),
            backgroundColor: _isBackgroundServiceEnabled ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ 백그라운드 서비스 토글 실패: $e');
      
      // 실패 시 이전 상태로 롤백
      setState(() {
        _isBackgroundServiceEnabled = !_isBackgroundServiceEnabled;
        _isBackgroundServiceRunning = false; // 서버 이전으로 비활성화
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('백그라운드 서비스 토글 실패: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
  
  /// 시장별 상위 종목 업데이트
  void _updateMarketTopStocks(List<Map<String, dynamic>> topStocks) {
    // 1) 새로 들어온 목록을 시장별로 그룹핑
    final incoming = <String, List<TopStockItem>>{
      'NASDAQ': [],
      'KOSPI': [],
      'KOSDAQ': [],
    };

    for (final stock in topStocks) {
      final market = stock['market'] as String? ?? 'UNKNOWN';
      if (incoming.containsKey(market)) {
        incoming[market]!.add(TopStockItem(
          stockCode: stock['stock_code'] as String,
          stockName: stock['stock_name'] as String,
          market: market,
          score: (stock['score'] as num?)?.toDouble() ?? 0.0,
          currentPrice: (stock['current_price'] as num?)?.toDouble() ?? 0.0,
          priceChangeRate: (stock['change_rate'] as num?)?.toDouble() ?? 0.0,
          lastUpdated: DateTime.now(),
        ));
      }
    }

    // 2) 기존 목록과 병합: 새 데이터 + 기존 데이터 → 점수순 정렬 → Top10 유지
    setState(() {
      for (final key in _marketTopStocks.keys) {
        final current = List<TopStockItem>.from(_marketTopStocks[key] ?? const <TopStockItem>[]);
        final incomingList = incoming[key] ?? const <TopStockItem>[];
        if (incomingList.isEmpty && current.isNotEmpty) {
          // 새 데이터가 비어오면 기존 유지 (깜빡임 방지)
          continue;
        }
        final merged = <String, TopStockItem>{};
        // 새 데이터 우선
        for (final s in incomingList) {
          merged[s.stockCode] = s;
        }
        // 기존 데이터 보강(새 데이터에 없는 항목 유지)
        for (final s in current) {
          merged.putIfAbsent(s.stockCode, () => s);
        }
        final list = merged.values.toList()
          ..sort((a, b) => b.score.compareTo(a.score));
        _marketTopStocks[key] = list.take(10).toList();
      }
    });
  }
  
  /// 거래대금 설정 변경
  Future<void> _changeTradingAmount(double amount) async {
    try {
      // await _backgroundService.setMinTradingAmount(amount); // 서버 이전으로 비활성화
      setState(() {
        _minTradingAmount = amount;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('최소 거래대금이 ${(amount / 100000000).toStringAsFixed(1)}억원으로 설정되었습니다'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ 거래대금 설정 실패: $e');
    }
  }

  /// 가격 포맷팅 (통화별)
  String _formatPrice(double price, String market) {
    if (market == 'NASDAQ' || market == 'NYSE') {
      return '\$${price.toStringAsFixed(2)}';
    } else {
      return '${price.toStringAsFixed(0)}원';
    }
  }

  /// 기존 추천종목 데이터 로드
  Future<void> _loadExistingRecommendedStocks() async {
    try {
      print('📊 기존 추천종목 데이터 로드 시작...');
      
      setState(() {
        _isLoadingLocalData = true;
        _currentLoadingTask = '로컬 데이터 조회 중...';
        _localDataProgress = 0;
        _localDataTotal = 0;
      });
      
      // RecommendedStocksData에서 기존 데이터 가져오기
      final recommendedStocksData = RecommendedStocksData();
      final existingStocks = await recommendedStocksData.getAllStocks();
      final cachedWithScores = await recommendedStocksData.getAllStocksWithScores();
      
      setState(() {
        _localDataTotal = existingStocks.length;
        _currentLoadingTask = '로컬 데이터 조회 중... (${existingStocks.length}개 종목)';
      });
      
      if (existingStocks.isNotEmpty) {
        print('📊 기존 추천종목 발견: ${existingStocks.length}개');
        
        // 기존 데이터를 시장별로 분류하여 표시
        final marketStocks = <String, List<TopStockItem>>{
          'KOSPI': [],
          'KOSDAQ': [],
          'NASDAQ': [],
          'NYSE': [],
        };
        
        // 1) 캐시 점수가 있으면 즉시 반영하여 초기 Top10을 구성
        for (final entry in existingStocks.entries) {
          final stockCode = entry.key;
          final stockName = entry.value;
          final market = _getMarketFromSymbol(stockCode);
          final cached = cachedWithScores[stockCode];
          final double score = (cached?['score'] as num?)?.toDouble() ?? 0.0;
          final double price = (cached?['price'] as num?)?.toDouble() ?? 0.0;
          if (marketStocks.containsKey(market)) {
            marketStocks[market]!.add(TopStockItem(
              stockCode: stockCode,
              stockName: stockName,
              market: market,
              score: score,
              currentPrice: price,
              priceChangeRate: 0.0,
              lastUpdated: DateTime.now(),
            ));
          }
        }
        // 시장별로 점수 상위 10개 정렬/절단 후 즉시 반영
        for (final key in marketStocks.keys) {
          marketStocks[key]!.sort((a, b) => b.score.compareTo(a.score));
          marketStocks[key] = marketStocks[key]!.take(10).toList();
        }
        
        // UI에 즉시 반영
        setState(() {
          _marketTopStocks = marketStocks;
        });
        
        print('📊 기본 데이터 표시 완료, 점수 업데이트 시작...');
        
        // 점수 업데이트는 고부하이므로 제한적으로, 순차 처리 + 배치 yield로 수행
        await _incrementalScoreUpdate(existingStocks, marketStocks);
        // 초기 Top10도 신선도 검사 후 빠르게 최신화
        await _refreshTopVisibleScores();
      } else {
        print('📊 기존 추천종목 데이터 없음');
      }
      
      setState(() {
        _isLoadingLocalData = false;
        _currentLoadingTask = '';
        _localDataProgress = 0;
        _localDataTotal = 0;
        // 로컬 데이터 조회 완료 후 백그라운드 분석 시작
        if (_isBackgroundServiceEnabled) {
          _serviceStatus = '백그라운드 분석 시작...';
        }
      });
    } catch (e) {
      print('❌ 기존 추천종목 데이터 로드 실패: $e');
      setState(() {
        _isLoadingLocalData = false;
        _currentLoadingTask = '';
        _localDataProgress = 0;
        _localDataTotal = 0;
        // 로컬 데이터 조회 실패 시에도 백그라운드 분석 시작
        if (_isBackgroundServiceEnabled) {
          _serviceStatus = '백그라운드 분석 시작...';
        }
      });
    }
  }

  /// 점수 업데이트(순차 처리 + 배치 yield + Top10 유지)
  Future<void> _incrementalScoreUpdate(Map<String, String> existingStocks, Map<String, List<TopStockItem>> marketStocks) async {
    try {
      final recommendedStocksData = RecommendedStocksData();
      final stockEntries = existingStocks.entries.toList();
      const int batchSize = 1; // 한 종목 처리마다 즉시 화면 반영
      int processed = 0;

      // 시장별 Top10을 효율적으로 유지하기 위해 정렬을 매 배치마다 전체가 아닌 삽입 정렬 방식으로 제한
      for (int i = 0; i < stockEntries.length; i += batchSize) {
        final batch = stockEntries.skip(i).take(batchSize);
        for (final entry in batch) {
          final stockCode = entry.key;
          final market = _getMarketFromSymbol(stockCode);
          final marketList = marketStocks[market];
          if (marketList == null) continue;

          // 1) 점수 캐시 우선 조회
          double score = 0.0;
          try {
            final scoreResult = await recommendedStocksData.getStockScore(stockCode);
            if (scoreResult != null && scoreResult is Map<String, dynamic>) {
              final comprehensiveScore = scoreResult['comprehensiveScore'];
              final simpleScore = scoreResult['score'];
              if (comprehensiveScore is num) score = comprehensiveScore.toDouble();
              else if (simpleScore is num) score = simpleScore.toDouble();
            }
          } catch (_) {}

          // 2) 기존 리스트에서 해당 항목 업데이트 (없으면 기본 항목 추가)
          final idx = marketList.indexWhere((e) => e.stockCode == stockCode);
          if (idx != -1) {
            marketList[idx] = TopStockItem(
              stockCode: marketList[idx].stockCode,
              stockName: marketList[idx].stockName,
              market: market,
              score: score,
              currentPrice: marketList[idx].currentPrice,
              priceChangeRate: marketList[idx].priceChangeRate,
              lastUpdated: DateTime.now(),
            );
          } else {
            marketList.add(TopStockItem(
              stockCode: stockCode,
              stockName: existingStocks[stockCode] ?? stockCode,
              market: market,
              score: score,
              currentPrice: 0.0,
              priceChangeRate: 0.0,
              lastUpdated: DateTime.now(),
            ));
          }
        }

        processed += batch.length;
        _processedCount = processed;
        
        // 로컬 데이터 조회 진행률 업데이트
        if (mounted) {
          setState(() {
            _localDataProgress = processed;
            _currentLoadingTask = '로컬 데이터 점수 업데이트 중... ($processed/${existingStocks.length})';
          });
        }
        
        // 시장별 Top10 유지(부분 정렬) + 변경된 시장만 업데이트 → 깜빡임 최소화
        final updatedMarkets = <String, List<TopStockItem>>{};
        for (final key in marketStocks.keys) {
          marketStocks[key]!.sort((a, b) => b.score.compareTo(a.score));
          final trimmed = marketStocks[key]!.take(10).toList();
          final previous = _marketTopStocks[key] ?? const <TopStockItem>[];
          if (!_topEquals(previous, trimmed)) {
            updatedMarkets[key] = trimmed;
          }
        }

        if (updatedMarkets.isNotEmpty && mounted) {
          setState(() {
            for (final entry in updatedMarkets.entries) {
              _marketTopStocks[entry.key] = entry.value;
            }
          });
        } else {
          // 변경이 없더라도 진행률은 주기적으로 갱신(깜빡임 방지 위해 과도한 setState 회피)
          _progressTick++;
          if (_progressTick % 20 == 0 && mounted) {
            setState(() {});
          }
        }

        // 배치 사이 짧게 yield (DB/메인스레드 부하 완화)
        if (i + batchSize < stockEntries.length) {
          await Future.delayed(const Duration(milliseconds: 100)); // 30ms → 100ms로 증가 (DB 락 방지)
        }
        print('📊 점수 업데이트 중: $processed/${existingStocks.length}');
      }

      print('✅ 기존 추천종목 점수 업데이트 완료');
    } catch (e) {
      print('❌ 점수 업데이트 실패: $e');
    }
  }

  bool _topEquals(List<TopStockItem> a, List<TopStockItem> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].stockCode != b[i].stockCode) return false;
      final sa = double.tryParse(a[i].score.toStringAsFixed(3)) ?? a[i].score;
      final sb = double.tryParse(b[i].score.toStringAsFixed(3)) ?? b[i].score;
      if (sa != sb) return false;
    }
    return true;
  }

  /// 보이는 Top10의 점수 신선도 검사 후, 신선도 초과 항목은 새로고침 로직과 동일하게 즉시 재계산
  Future<void> _refreshTopVisibleScores() async {
    try {
      final now = DateTime.now();
      final codesToRefresh = <String>[];
      for (final market in ['NASDAQ', 'KOSPI', 'KOSDAQ']) {
        final list = _marketTopStocks[market] ?? const <TopStockItem>[];
        for (final item in list) {
          if (now.difference(item.lastUpdated).inMinutes >= _freshnessMinutes) {
            codesToRefresh.add(item.stockCode);
          }
        }
      }
      if (codesToRefresh.isEmpty) return;

      // 순차로 부담을 줄이되, 적은 수이므로 빠르게 처리
      for (final code in codesToRefresh) {
        // 다이얼로그 새로고침과 동일 입력 준비
        // Firestore 구독으로 대체되므로 직접 API 호출 비활성화
        print('📊 [추천종목] 직접 API 호출 비활성화 - Firestore 구독 사용: $code');
        final priceData = null;
        final cached = AppDataManager.instance.getCachedStockData(code);
        double currentPrice = ((priceData?['currentPrice'] as num?)?.toDouble())
          ?? (cached['currentPrice'] as num?)?.toDouble()
          ?? (cached['prpr'] as num?)?.toDouble()
          ?? 0.0;
        double prevClose = ((priceData?['prevClose'] as num?)?.toDouble())
          ?? (cached['prevClose'] as num?)?.toDouble()
          ?? (cached['stck_prdy_clpr'] as num?)?.toDouble()
          ?? currentPrice;
        final volume = ((priceData?['volume'] as num?)?.toDouble())
          ?? (cached['volume'] as num?)?.toDouble()
          ?? (cached['acml_vol'] as num?)?.toDouble()
          ?? 0.0;
        final high = ((priceData?['highPrice'] as num?)?.toDouble())
          ?? (cached['high'] as num?)?.toDouble()
          ?? currentPrice;
        final low = ((priceData?['lowPrice'] as num?)?.toDouble())
          ?? (cached['low'] as num?)?.toDouble()
          ?? currentPrice;
        final open = ((priceData?['openPrice'] as num?)?.toDouble())
          ?? (cached['open'] as num?)?.toDouble()
          ?? currentPrice;

        // 분석탭과 동일한 방식: SQL DB 우선, API 폴백
        try {
          // 1. SQL DB에서 차트 데이터 먼저 확인
          final historicalRepo = AppDataManager.instance.historicalDataRepo;
          final localChartData = await historicalRepo.getRecentBars(code, limit: 100);
          
          if (localChartData.isNotEmpty) {
            // SQL DB에 데이터가 있으면 사용
            AppDataManager.instance.cacheChartData(code, localChartData);
            print('📊 [추천종목] SQL DB에서 차트 데이터 사용: $code (${localChartData.length}개)');
          } else {
            // SQL DB에 없으면 API 호출
            // Firestore 구독으로 대체되므로 직접 API 호출 비활성화
            print('📊 [추천종목] 차트 데이터 API 호출 비활성화 - Firestore 구독 사용: $code');
            final chart = <Map<String, dynamic>>[];
            if (chart.isNotEmpty) {
              AppDataManager.instance.cacheChartData(code, chart);
              print('📊 [추천종목] API에서 차트 데이터 사용: $code (${chart.length}개)');
            }
          }
        } catch (_) {}

        final analysis = await UnifiedAnalysisService.instance.analyzeStock(code, days: 100);
        if (analysis == null) continue;
        final score = (analysis['comprehensiveScore'] as num?)?.toDouble() ?? 0.0;
        final priceForCache = (analysis['currentPrice'] as num?)?.toDouble() ?? currentPrice;
        await RecommendedStocksData().updateStockScore(code, score, metadata: {
          'price': priceForCache,
          'market': _getMarketFromSymbol(code),
          'timestamp': DateTime.now().toIso8601String(),
        });

        // 화면 반영
        for (final entry in _marketTopStocks.entries) {
          final idx = entry.value.indexWhere((e) => e.stockCode == code);
          if (idx != -1) {
            entry.value[idx] = TopStockItem(
              stockCode: entry.value[idx].stockCode,
              stockName: entry.value[idx].stockName,
              market: entry.key,
              score: score,
              currentPrice: priceForCache,
              priceChangeRate: entry.value[idx].priceChangeRate,
              lastUpdated: DateTime.now(),
            );
            entry.value.sort((a, b) => b.score.compareTo(a.score));
            _marketTopStocks[entry.key] = entry.value.take(10).toList();
          }
        }
        if (mounted) setState(() {});
      }
    } catch (e) {
      // ignore
    }
  }

  /// 종목코드로 시장 판별 (단일화)
  String _getMarketFromSymbol(String symbol) {
    return MarketTimeValidator.instance.getMarketFromSymbol(symbol);
  }
  
  /// 거래대금 설정 다이얼로그 표시
  void _showTradingAmountDialog() {
    double tempAmount = _minTradingAmount;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('최소 거래대금 설정'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('분석할 종목의 최소 거래대금을 설정하세요.'),
              const SizedBox(height: 16),
              ..._tradingAmountOptions.map((amount) => ListTile(
                title: Text('${(amount / 100000000).toStringAsFixed(1)}억원'),
                subtitle: Text('${(amount / 1000000000).toStringAsFixed(1)}천억원'),
                leading: Radio<double>(
                  value: amount,
                  groupValue: tempAmount,
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() {
                        tempAmount = value;
                      });
                    }
                  },
                ),
              )).toList(),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () async {
                await _changeTradingAmount(tempAmount);
                Navigator.of(context).pop();
                
                // 백그라운드 서비스 재시작
                if (_isBackgroundServiceEnabled) {
                  // await _backgroundService.stopService(); // 서버 이전으로 비활성화
                  await Future.delayed(const Duration(seconds: 1));
                  // await _backgroundService.startService(); // 서버 이전으로 비활성화
                }
              },
              child: const Text('확인'),
            ),
          ],
        ),
      ),
    );
  }

  /// 사이드 이펙트 처리
  void _handleSideEffect(TopStocksSideEffect sideEffect) {
    switch (sideEffect.runtimeType) {
      case ShowErrorToastSideEffect:
        final errorEffect = sideEffect as ShowErrorToastSideEffect;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorEffect.message),
            backgroundColor: Colors.red,
          ),
        );
        break;
      case ShowSuccessToastSideEffect:
        final successEffect = sideEffect as ShowSuccessToastSideEffect;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successEffect.message),
            backgroundColor: Colors.green,
          ),
        );
        break;
      case NavigateToStockDetailSideEffect:
        final navEffect = sideEffect as NavigateToStockDetailSideEffect;
        // 종목 상세 화면으로 네비게이션 (필요시 구현)
        print('종목 상세 화면으로 이동: ${navEffect.stockCode}');
        break;
    }
  }


  /// 관심종목 코드 로드
  Future<void> _loadWatchlistCodes() async {
    try {
      final watchlist = await AppDataManager.instance.watchlistRepository.getWatchlist();
      _watchlistCodes = watchlist.map((item) => item['stock_code'] as String).toSet();
    } catch (e) {
      print('❌ 관심종목 로드 실패: $e');
    }
  }


  /// 시장별 상위 종목 새로고침
  Future<void> _refreshMarketTopStocks() async {
    try {
      setState(() {
        _isLoading = true;
        _serviceStatus = '데이터 새로고침 중...';
      });
      
      await _loadMarketTopStocksFromServer();
      
      setState(() {
        _isLoading = false;
        _serviceStatus = '서버 점수 동기화 완료';
        _lastUpdateTime = DateTime.now().toString().substring(11, 19);
      });
      
    } catch (e) {
      print('❌ 시장별 상위 종목 새로고침 실패: $e');
      setState(() {
        _isLoading = false;
        _serviceStatus = '새로고침 실패';
        _errorMessage = e.toString();
      });
    }
  }
  
  /// 실시간 서비스 상태 모니터링 시작
  void _startServiceStatusMonitoring() {
    if (_serviceStatusMonitorStarted) return;
    _serviceStatusMonitorStarted = true;
    _serviceStatusTimer?.cancel();
    _serviceStatusTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      try {
        final serviceStatus = _topStocksUseCase.getServiceStatus();
        final isRunning = serviceStatus['isRunning'] as bool? ?? false;
        final calculatedCount = serviceStatus['calculatedStocksCount'] as int? ?? 0;
        
        setState(() {
          _isServiceRunning = isRunning;
          _calculatedStocksCount = calculatedCount;
          if (isRunning) {
            _serviceStatus = '실시간 점수 계산 중 (${calculatedCount}개 종목)';
          } else {
            _serviceStatus = '서비스 중지됨';
          }
        });
      } catch (e) {
        print('❌ 서비스 상태 모니터링 실패: $e');
      }
    });
  }

  Future<void> _loadMarketTopStocksFromServer() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    // 서버에서 상위 10개 추천만 제공하므로, 시장 필터 없이 단일 목록을 먼저 표시
    final items = await _functions.getTopRecommendations(uid: uid, limit: 10);
    // 화면 구조 유지 위해 모두 NASDAQ 섹션에 배치(후속 단계에서 시장별 분리 가능)
    setState(() {
      _marketTopStocks['NASDAQ'] = items
          .map((e) => TopStockItem(
                stockCode: (e['symbol'] ?? e['id'] ?? '') as String,
                stockName: (e['name'] ?? e['stockName'] ?? '') as String? ?? '',
                market: 'NASDAQ',
                score: (e['comprehensiveScore'] as num?)?.toDouble() ?? 0.0,
                currentPrice: (e['currentPrice'] as num?)?.toDouble() ?? 0.0,
                lastUpdated: DateTime.now(),
              ))
          .toList();
      _marketTopStocks['KOSPI'] = [];
      _marketTopStocks['KOSDAQ'] = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading 
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    _serviceStatus,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.symmetric(horizontal: 32),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red[200]!),
                      ),
                      child: Text(
                        '오류: $_errorMessage',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red[700],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _refreshMarketTopStocks,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 헤더 정보
                    _buildHeaderSection(),
                    
                    // 나스닥 상위 종목
                    _buildMarketSection('🇺🇸 나스닥 상위 10개', 'NASDAQ', _marketTopStocks['NASDAQ']!),
                    
                    const SizedBox(height: 16),
                    
                    // 코스피 상위 종목
                    _buildMarketSection('🇰🇷 코스피 상위 10개', 'KOSPI', _marketTopStocks['KOSPI']!),

                    const SizedBox(height: 16),

                    // 코스닥 상위 종목
                    _buildMarketSection('🇰🇷 코스닥 상위 10개', 'KOSDAQ', _marketTopStocks['KOSDAQ']!),
                    
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  /// 헤더 섹션
  Widget _buildHeaderSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      margin: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[600]!, Colors.blue[400]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📊 실시간 상위 점수 종목',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '나스닥, 코스피, 코스닥 각각 상위 10개 종목을 실시간으로 추천합니다',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          const SizedBox(height: 12),
          // 실시간 상태 표시
          _buildServiceStatusRow(),
          const SizedBox(height: 8),
          // 백그라운드 서비스 스위치
          _buildBackgroundServiceSwitch(),
          const SizedBox(height: 8),
          // 시장별 즉시 스캔 버튼
          _buildMarketScanButtons(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// 백그라운드 서비스 스위치
  Widget _buildBackgroundServiceSwitch() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(
            _isBackgroundServiceEnabled ? Icons.auto_awesome : Icons.auto_awesome_outlined,
            color: _isBackgroundServiceEnabled ? Colors.amber : Colors.white70,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '백그라운드 계산',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (_isBackgroundServiceRunning) ...[
                  const SizedBox(height: 2),
                  Text(
                    '진행률: ${(_calculationProgress * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white70,
                    ),
                  ),
                  if (_currentMarket.isNotEmpty && _currentStock.isNotEmpty) ...[
                    Text(
                      '현재: $_currentMarket - $_currentStock',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white70,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
                const SizedBox(height: 4),
                Text(
                  '최소 거래대금: ${(_minTradingAmount / 100000000).toStringAsFixed(1)}억원',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Switch(
                value: _isBackgroundServiceEnabled,
                onChanged: (value) {
                  // 중복 클릭 방지
                  if (_isBackgroundServiceEnabled != value) {
                    _toggleBackgroundService();
                  }
                },
                activeColor: Colors.amber,
                activeTrackColor: Colors.amber.withOpacity(0.3),
                inactiveThumbColor: Colors.white70,
                inactiveTrackColor: Colors.white.withOpacity(0.2),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _showTradingAmountDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.settings,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '설정',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 서비스 상태 표시 행
  Widget _buildServiceStatusRow() {
    Color statusColor;
    IconData statusIcon;
    
    if (_errorMessage != null) {
      statusColor = Colors.red[300]!;
      statusIcon = Icons.error_outline;
    } else if (_isServiceRunning) {
      statusColor = Colors.green[300]!;
      statusIcon = Icons.check_circle_outline;
    } else {
      statusColor = Colors.orange[300]!;
      statusIcon = Icons.pause_circle_outline;
    }
    
    return Row(
      children: [
        Icon(statusIcon, color: statusColor, size: 16),
        const SizedBox(width: 6),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            _isLoadingLocalData ? _currentLoadingTask : _serviceStatus,
            style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w500),
          ),
          // 로컬 데이터 조회 중일 때
          if (_isLoadingLocalData && _localDataTotal > 0) ...[
            const SizedBox(height: 2),
            Text(
              '로컬 데이터 조회: $_localDataProgress/$_localDataTotal개  (${(_localDataTotal > 0 ? (_localDataProgress / _localDataTotal * 100) : 0).toStringAsFixed(1)}%)',
              style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.8)),
            ),
          ],
          // 백그라운드 서비스가 실행 중일 때만 진행률 표시 (로컬 데이터 조회와 분리)
          if (_isBackgroundServiceRunning && !_isLoadingLocalData && (_processedCount >= 0 || _totalCount > 0)) ...[
            const SizedBox(height: 2),
            Text(
              '백그라운드 분석 진행: $_processedCount/$_totalCount개  (${(_calculationProgress * 100).toStringAsFixed(1)}%)',
              style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.8)),
            ),
            if (_currentMarket.isNotEmpty || _currentStock.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                '현재 처리: ${_currentMarket.isEmpty ? '-' : _currentMarket}  ${_currentStock.isEmpty ? '' : '- ' + _currentStock}',
                style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.8)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ])),
        if (_lastUpdateTime.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(
            '마지막 업데이트: $_lastUpdateTime',
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
        ],
      ],
    );
  }

  /// 시장별 섹션
  Widget _buildMarketSection(String title, String market, List<TopStockItem> stocks) {
    // 개별주만 필터링 (거래대금 필터는 DB where에서 처리)
    final filteredStocks = _filterIndividualStocks(stocks);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 시장 제목
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            decoration: BoxDecoration(
              color: market == 'US' 
                ? Colors.green[50] 
                : (market == 'KOSPI' ? Colors.orange[50] : Colors.purple[50]),
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(
                color: market == 'US' 
                  ? Colors.green[300]! 
                  : (market == 'KOSPI' ? Colors.orange[300]! : Colors.purple[300]!),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: market == 'US' ? Colors.green[700] : Colors.orange[700],
                  ),
                ),
                const Spacer(),
                // 시장별 전체 신선도 표시
                if (stocks.isNotEmpty) ...[
                  FreshnessSummaryIndicator(
                    summary: DataFreshnessManager.getFreshnessSummary(
                      stockDataTime: stocks.map((s) => s.lastUpdated).reduce((a, b) => a.isBefore(b) ? a : b),
                    ),
                    fontSize: 10,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  ),
                  const SizedBox(width: 8),
                ],
                // 수동 새로고침 버튼
                IconButton(
                  onPressed: () => _refreshSingleMarketTopStocks(market),
                  tooltip: '해당 시장 새로고침',
                  icon: Icon(
                    Icons.refresh,
                    size: 18,
                    color: market == 'US'
                      ? Colors.green[700]
                      : (market == 'KOSPI' ? Colors.orange[700] : Colors.purple[700]),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  decoration: BoxDecoration(
                    color: market == 'US' ? Colors.green[100] : Colors.orange[100],
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: Text(
                    '${stocks.length}개',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: market == 'US' 
                        ? Colors.green[700] 
                        : (market == 'KOSPI' ? Colors.orange[700] : Colors.purple[700]),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          
          // 종목 리스트
          if (filteredStocks.isEmpty)
            Container(
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      _isServiceRunning ? Icons.hourglass_empty : Icons.inbox,
                      size: 48,
                      color: _isServiceRunning ? Colors.blue : Colors.grey,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isServiceRunning 
                          ? '점수 계산 중입니다...'
                          : '상위 점수 종목이 없습니다',
                      style: TextStyle(
                        color: _isServiceRunning ? Colors.blue : Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (_isServiceRunning) ...[
                      const SizedBox(height: 4),
                      Text(
                        '잠시만 기다려주세요',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            ...filteredStocks.asMap().entries.map((entry) {
              final index = entry.key;
              final stock = entry.value;
              return _buildStockItem(stock, index + 1, market);
            }).toList(),
        ],
      ),
    );
  }

  /// 국내주식만 개별주 필터링 (코스피/코스닥만, 나스닥은 필터링 없음)
  List<TopStockItem> _filterIndividualStocks(List<TopStockItem> stocks) {
    return stocks.where((stock) {
      // 국내주식(코스피/코스닥)만 개별주 필터링
      if (stock.market == 'KOSPI' || stock.market == 'KOSDAQ') {
        if (StockFilterUtils.isNonIndividualStockByName(stock.stockName)) {
          print('🚫 국내 ETF/ETN/펀드 제외: ${stock.stockName} (${stock.stockCode})');
          return false;
        }
      }
      // 해외주식(나스닥/뉴욕)은 필터링 없이 포함
      return true;
    }).toList();
  }

  /// 국내시장 거래대금 필터(표시 단계). 해외는 필터 미적용.
  bool _passesTradingAmountFilter(TopStockItem stock) {
    if (!(stock.market == 'KOSPI' || stock.market == 'KOSDAQ')) return true;
    final cached = AppDataManager.instance.getCachedStockData(stock.stockCode);
    final double? price = (cached['currentPrice'] as num?)?.toDouble()
        ?? (cached['prpr'] as num?)?.toDouble();
    final double? volume = (cached['volume'] as num?)?.toDouble()
        ?? (cached['acml_vol'] as num?)?.toDouble();
    if (price == null || volume == null) return false;
    final double tradingAmount = price * volume;
    return tradingAmount >= _minTradingAmount;
  }

  /// 단일 시장 상위 종목만 새로고침
  Future<void> _refreshSingleMarketTopStocks(String market) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$market 상위 종목 새로고침 중...'),
          duration: const Duration(seconds: 1),
        ),
      );

      final result = await _topStocksUseCase.getTopStocksByMarket(
        market: market,
        limit: 10,
        minScore: 0.3,
      );
      if (result.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _marketTopStocks[market] = result.map((stock) => TopStockItem.fromMap(stock)).toList();
          _lastUpdateTime = DateTime.now().toString().substring(11, 19);
        });
      }

      // 보이는 Top10 신선도 검사 및 빠른 최신화
      await _refreshTopVisibleScores();

      // 배경 점수 재계산 트리거가 필요하면 다음 라인을 사용 (무거움)
      // await _backgroundService.scanMarketOnce(market); // 서버 이전으로 비활성화

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$market 상위 종목이 갱신되었습니다'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$market 새로고침 실패: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// 종목 아이템
  Widget _buildStockItem(TopStockItem stock, int rank, String market) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8.0),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: InkWell(
          onTap: () => _onStockTap(stock),
          borderRadius: BorderRadius.circular(8.0),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                // 순위
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _getRankColor(rank),
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                  child: Center(
                    child: Text(
                      '$rank',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                
                // 종목 정보
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              stock.stockName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // 신선도 표시 추가
                          FreshnessIndicator(
                            lastUpdated: stock.lastUpdated,
                            fontSize: 9,
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                            decoration: BoxDecoration(
                              color: market == 'US' 
                                ? Colors.green[100] 
                                : (market == 'KOSPI' ? Colors.orange[100] : Colors.purple[100]),
                              borderRadius: BorderRadius.circular(4.0),
                            ),
                            child: Text(
                              stock.stockCode,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: market == 'US' 
                                  ? Colors.green[700] 
                                  : (market == 'KOSPI' ? Colors.orange[700] : Colors.purple[700]),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            _formatPrice(stock.currentPrice, stock.market),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (stock.priceChangeRate != 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                              decoration: BoxDecoration(
                                color: stock.priceChangeRate > 0 ? Colors.red[50] : Colors.blue[50],
                                borderRadius: BorderRadius.circular(4.0),
                              ),
                              child: Text(
                                '${stock.priceChangeRate > 0 ? '+' : ''}${stock.priceChangeRate.toStringAsFixed(2)}%',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: stock.priceChangeRate > 0 ? Colors.red[600] : Colors.blue[600],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // 점수
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      decoration: BoxDecoration(
                        color: _getScoreColor(stock.score),
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: Text(
                        stock.scoreGrade, // 등급 배지 유지 (A+~C 등)
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${stock.score.toStringAsFixed(3)}점',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 순위별 색상
  Color _getRankColor(int rank) {
    if (rank <= 3) return Colors.amber[600]!;
    if (rank <= 5) return Colors.blue[600]!;
    return Colors.grey[600]!;
  }

  /// 점수별 색상
  Color _getScoreColor(double score) {
    if (score >= 0.7) return Colors.green[600]!;
    if (score >= 0.5) return Colors.orange[600]!;
    return Colors.red[600]!;
  }

  /// 종목 탭 처리
  void _onStockTap(TopStockItem stock) {
    _showStockActionDialog(stock);
  }

  /// 종목 액션 다이얼로그: 점수 새로고침/관심종목 추가
  void _showStockActionDialog(TopStockItem stock) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('${stock.stockName} (${stock.stockCode})'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('현재 점수: ${stock.score.toStringAsFixed(3)}'),
              const SizedBox(height: 8),
              Text('마켓: ${stock.market}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                // 관심종목 추가
                try {
                  await AppDataManager.instance.watchlistRepository.addToWatchlist(
                    stockCode: stock.stockCode,
                    stockName: stock.stockName,
                  );
                  if (mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('관심종목에 추가되었습니다')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('관심종목 추가 실패: $e')),
                    );
                  }
                }
              },
              child: const Text('관심종목 추가'),
            ),
            ElevatedButton(
              onPressed: () async {
                // 단일 종목 점수 재계산 트리거: API 최신 데이터 수집 → UnifiedAnalysis 분석 → 캐시 저장 → UI 즉시 갱신
                try {
                  // 로딩 오버레이 표시
                  bool loaderShown = false;
                  try {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => const Center(child: CircularProgressIndicator()),
                    );
                    loaderShown = true;
                  } catch (_) {}
                  // 1) 분석탭과 완전히 동일한 데이터 수집 로직 사용 (실시간 API 우선)
                  // Firestore 구독으로 대체되므로 직접 API 호출 비활성화
                  print('📊 [추천종목] 직접 API 호출 비활성화 - Firestore 구독 사용: ${stock.stockCode}');
                  final Map<String, dynamic>? priceData = null;
                  final cached = AppDataManager.instance.getCachedStockData(stock.stockCode);
                  
                  // 분석탭과 동일한 데이터 추출 (API 우선, 캐시 폴백)
                  double currentPrice = ((priceData?['currentPrice'] as num?)?.toDouble())
                    ?? (cached['currentPrice'] as num?)?.toDouble()
                    ?? (cached['prpr'] as num?)?.toDouble()
                    ?? 0.0;
                  double prevClose = ((priceData?['prevClose'] as num?)?.toDouble())
                    ?? (cached['prevClose'] as num?)?.toDouble()
                    ?? (cached['stck_prdy_clpr'] as num?)?.toDouble()
                    ?? currentPrice;
                  final double volume = ((priceData?['volume'] as num?)?.toDouble())
                    ?? (cached['volume'] as num?)?.toDouble()
                    ?? (cached['acml_vol'] as num?)?.toDouble()
                    ?? 0.0;
                  final double high = ((priceData?['highPrice'] as num?)?.toDouble())
                    ?? (cached['high'] as num?)?.toDouble()
                    ?? currentPrice;
                  final double low = ((priceData?['lowPrice'] as num?)?.toDouble())
                    ?? (cached['low'] as num?)?.toDouble()
                    ?? currentPrice;
                  final double open = ((priceData?['openPrice'] as num?)?.toDouble())
                    ?? (cached['open'] as num?)?.toDouble()
                    ?? currentPrice;
                  
                  // 분석탭과 동일한 차트 데이터 수집: SQL DB 우선, API 폴백
                  try {
                    // 1. SQL DB에서 차트 데이터 먼저 확인
                    final historicalRepo = AppDataManager.instance.historicalDataRepo;
                    final localChartData = await historicalRepo.getRecentBars(stock.stockCode, limit: 100);
                    
                    if (localChartData.isNotEmpty) {
                      // SQL DB에 데이터가 있으면 사용
                      AppDataManager.instance.cacheChartData(stock.stockCode, localChartData);
                      print('📊 [추천종목] SQL DB에서 차트 데이터 사용: ${stock.stockCode} (${localChartData.length}개)');
                    } else {
                      // SQL DB에 없으면 API 호출
                      // Firestore 구독으로 대체되므로 직접 API 호출 비활성화
                      print('📊 [추천종목] 차트 데이터 API 호출 비활성화 - Firestore 구독 사용: ${stock.stockCode}');
                      final chartData = <Map<String, dynamic>>[];
                      if (chartData.isNotEmpty) {
                        AppDataManager.instance.cacheChartData(stock.stockCode, chartData);
                        print('📊 [추천종목] API에서 차트 데이터 사용: ${stock.stockCode} (${chartData.length}개)');
                      }
                    }
                  } catch (_) {}
                  
                  // 분석탭과 동일한 캐시 업데이트
                  try {
                    // 🔄 거래량 덮어쓰기 방지 - volume 제외하고 업데이트
                    AppDataManager.instance.updateCurrentPrice(stock.stockCode, {
                      'currentPrice': currentPrice,
                      'prevClose': prevClose,
                      // 'volume': volume,  // ← 거래량 덮어쓰기 방지
                      'high': high,
                      'low': low,
                      'open': open,
                      'timestamp': DateTime.now().toIso8601String(),
                    });
                  } catch (_) {}

                  // 분석탭과 동일한 해외/특수 케이스 보정
                  if (currentPrice == 0.0 || prevClose == 0.0) {
                    try {
                      final cachedChart = AppDataManager.instance.getCachedChartData(stock.stockCode);
                      if (cachedChart.isNotEmpty) {
                        final lastClose = (cachedChart.last['close'] as num?)?.toDouble() ?? 0.0;
                        if (lastClose > 0) {
                          currentPrice = currentPrice == 0.0 ? lastClose : currentPrice;
                          prevClose = prevClose == 0.0 ? lastClose : prevClose;
                        }
                      }
                    } catch (_) {}
                  }

                  // 차트 데이터는 이미 위에서 처리됨 (백그라운드 서비스와 동일한 로직)

                  // 3) 분석탭과 동일한 UnifiedAnalysis 호출
                  final analysisResult = await UnifiedAnalysisService.instance.analyzeStock(
                    stock.stockCode,
                    days: 100,
                  );
                  if (analysisResult != null) {
                    final score = (analysisResult['comprehensiveScore'] as num?)?.toDouble() ?? 0.0;
                    final double priceForCache = (analysisResult['currentPrice'] as num?)?.toDouble() ?? currentPrice;

                    // 4) 서버가 점수/TopN 저장을 담당. 클라이언트 저장은 수행하지 않음.
                    await RecommendedStocksData().updateStockScore(stock.stockCode, score, metadata: {
                      'price': priceForCache,
                      'market': stock.market,
                      'timestamp': DateTime.now().toIso8601String(),
                    });
                    // 5) SQL에서 재조회 후 UI 갱신(레이스 제거)
                    try {
                      // 서버 전환: 로컬 top_stocks 재조회 제거
                      final reloaded = null;
                      final double uiScore = score;
                      final double uiPrice = priceForCache;
                      if (mounted) setState(() {
                        for (final entry in _marketTopStocks.entries) {
                          final idx = entry.value.indexWhere((e) => e.stockCode == stock.stockCode);
                          if (idx != -1) {
                            entry.value[idx] = TopStockItem(
                              stockCode: stock.stockCode,
                              stockName: stock.stockName,
                              market: stock.market,
                              score: uiScore,
                              currentPrice: uiPrice,
                              priceChangeRate: stock.priceChangeRate,
                              lastUpdated: DateTime.now(),
                            );
                            entry.value.sort((a, b) => b.score.compareTo(a.score));
                            _marketTopStocks[entry.key] = entry.value.take(10).toList();
                          }
                        }
                      });
                    } catch (_) {}

                    // 성공 안내
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('점수 새로고침 완료: ${score.toStringAsFixed(3)}')),
                      );
                    }
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('점수 새로고침 실패: 분석 결과 없음')),
                      );
                    }
                  }
                } catch (e) {
                  // ignore: avoid_print
                  print('단일 종목 재계산 실패: $e');
                } finally {
                  // 로딩 오버레이 닫기
                  try {
                    Navigator.of(context, rootNavigator: true).pop();
                  } catch (_) {}
                  if (mounted) Navigator.of(context).pop();
                }
              },
              child: const Text('점수 새로고침'),
            ),
          ],
        );
      },
    );
  }
}


