import 'dart:async';
import '../models/top_stocks_state.dart';
import '../usecases/top_stocks_usecase.dart';

/// 상위 점수 종목 ViewModel (MVI 패턴)
/// Action을 받아 Change를 생성하고, Change를 ViewState로 변환
class TopStocksViewModel {
  final TopStocksUseCase _useCase;
  
  // 상태 관리
  TopStocksViewState _currentState = const TopStocksViewState();
  final StreamController<TopStocksViewState> _stateController = 
      StreamController<TopStocksViewState>.broadcast();
  final StreamController<TopStocksSideEffect> _sideEffectController = 
      StreamController<TopStocksSideEffect>.broadcast();
  
  // 스트림 구독 관리
  StreamSubscription<Map<String, dynamic>>? _scoreStreamSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _topStocksStreamSubscription;
  
  TopStocksViewModel({TopStocksUseCase? useCase}) 
      : _useCase = useCase ?? TopStocksUseCase();

  // 스트림 getter
  Stream<TopStocksViewState> get stateStream => _stateController.stream;
  Stream<TopStocksSideEffect> get sideEffectStream => _sideEffectController.stream;
  TopStocksViewState get currentState => _currentState;

  /// Action 처리 (Middleware 역할)
  Future<void> handleAction(TopStocksAction action) async {
    try {
      switch (action.runtimeType) {
        case LoadTopStocksAction:
          await _handleLoadTopStocks(action as LoadTopStocksAction);
          break;
        case RefreshTopStocksAction:
          await _handleRefreshTopStocks(action as RefreshTopStocksAction);
          break;
        case ChangeMarketFilterAction:
          _handleChangeMarketFilter(action as ChangeMarketFilterAction);
          break;
        case ChangeScoreThresholdAction:
          _handleChangeScoreThreshold(action as ChangeScoreThresholdAction);
          break;
        case ChangeDisplayLimitAction:
          _handleChangeDisplayLimit(action as ChangeDisplayLimitAction);
          break;
        case SubscribeToScoreStreamAction:
          await _handleSubscribeToScoreStream();
          break;
        case UnsubscribeFromScoreStreamAction:
          _handleUnsubscribeFromScoreStream();
          break;
        default:
          print('⚠️ 알 수 없는 Action: ${action.runtimeType}');
      }
    } catch (e) {
      print('❌ Action 처리 실패: $e');
      _emitChange(TopStocksErrorChange(e.toString()));
    }
  }

  /// 상위 점수 종목 로드 처리
  Future<void> _handleLoadTopStocks(LoadTopStocksAction action) async {
    _emitChange(TopStocksLoadingChange());
    
    try {
      final stocks = await _useCase.getTopStocks(
        limit: action.limit,
        minScore: action.minScore,
        market: action.market,
        useCache: action.useCache,
      );
      
      final topStockItems = stocks.map((stock) => TopStockItem.fromMap(stock)).toList();
      
      _emitChange(TopStocksLoadedChange(
        topStocks: topStockItems,
        lastUpdated: DateTime.now(),
      ));
      
    } catch (e) {
      _emitChange(TopStocksErrorChange(e.toString()));
    }
  }

  /// 상위 점수 종목 새로고침 처리
  Future<void> _handleRefreshTopStocks(RefreshTopStocksAction action) async {
    _emitChange(TopStocksRefreshingChange());
    
    try {
      final stocks = await _useCase.getTopStocks(
        limit: action.limit,
        minScore: action.minScore,
        market: action.market,
        useCache: false, // 새로고침 시 캐시 사용 안함
      );
      
      final topStockItems = stocks.map((stock) => TopStockItem.fromMap(stock)).toList();
      
      _emitChange(TopStocksRefreshedChange(
        topStocks: topStockItems,
        lastUpdated: DateTime.now(),
      ));
      
    } catch (e) {
      _emitChange(TopStocksErrorChange(e.toString()));
    }
  }

  /// 시장 필터 변경 처리
  void _handleChangeMarketFilter(ChangeMarketFilterAction action) {
    _emitChange(MarketFilterChangedChange(action.market));
  }

  /// 점수 임계값 변경 처리
  void _handleChangeScoreThreshold(ChangeScoreThresholdAction action) {
    _emitChange(ScoreThresholdChangedChange(action.threshold));
  }

  /// 표시 제한 변경 처리
  void _handleChangeDisplayLimit(ChangeDisplayLimitAction action) {
    _emitChange(DisplayLimitChangedChange(action.limit));
  }

  /// 실시간 점수 스트림 구독 처리
  Future<void> _handleSubscribeToScoreStream() async {
    try {
      // 기존 구독 해제
      _handleUnsubscribeFromScoreStream();
      
      // 점수 스트림 구독
      _scoreStreamSubscription = _useCase.getScoreStream().listen(
        (scoreData) {
          final stockCode = scoreData['stockCode'] as String;
          final score = scoreData['score'] as double;
          final currentPrice = scoreData['currentPrice'] as double;
          
          // 현재 상태에서 해당 종목 찾기
          final currentStocks = _currentState.topStocks;
          final stockIndex = currentStocks.indexWhere(
            (stock) => stock.stockCode == stockCode
          );
          
          if (stockIndex != -1) {
            // 기존 종목 업데이트
            final updatedStock = currentStocks[stockIndex].copyWith(
              score: score,
              currentPrice: currentPrice,
              lastUpdated: DateTime.now(),
            );
            
            _emitChange(RealtimeScoreUpdateChange(updatedStock));
          }
        },
        onError: (error) {
          print('❌ 실시간 점수 스트림 오류: $error');
        },
      );
      
      // 상위 종목 스트림 구독
      _topStocksStreamSubscription = _useCase.getTopStocksStream().listen(
        (topStocks) {
          final topStockItems = topStocks.map((stock) => TopStockItem.fromMap(stock)).toList();
          
          _emitChange(TopStocksLoadedChange(
            topStocks: topStockItems,
            lastUpdated: DateTime.now(),
          ));
        },
        onError: (error) {
          print('❌ 실시간 상위 종목 스트림 오류: $error');
        },
      );
      
      print('✅ 실시간 점수 스트림 구독 시작');
      
    } catch (e) {
      print('❌ 실시간 점수 스트림 구독 실패: $e');
    }
  }

  /// 실시간 점수 스트림 구독 해제 처리
  void _handleUnsubscribeFromScoreStream() {
    _scoreStreamSubscription?.cancel();
    _topStocksStreamSubscription?.cancel();
    _scoreStreamSubscription = null;
    _topStocksStreamSubscription = null;
    print('⏹️ 실시간 점수 스트림 구독 해제');
  }

  /// Change를 ViewState로 변환 (Reducer 역할)
  void _emitChange(TopStocksChange change) {
    switch (change.runtimeType) {
      case TopStocksLoadingChange:
        _currentState = _currentState.copyWith(
          isLoading: true,
          error: null,
        );
        break;
        
      case TopStocksLoadedChange:
        final loadedChange = change as TopStocksLoadedChange;
        _currentState = _currentState.copyWith(
          topStocks: loadedChange.topStocks,
          isLoading: false,
          isRefreshing: false,
          error: null,
          lastUpdated: loadedChange.lastUpdated,
        );
        break;
        
      case TopStocksErrorChange:
        final errorChange = change as TopStocksErrorChange;
        _currentState = _currentState.copyWith(
          isLoading: false,
          isRefreshing: false,
          error: errorChange.error,
        );
        _emitSideEffect(ShowErrorToastSideEffect(errorChange.error));
        break;
        
      case TopStocksRefreshingChange:
        _currentState = _currentState.copyWith(
          isRefreshing: true,
          error: null,
        );
        break;
        
      case TopStocksRefreshedChange:
        final refreshedChange = change as TopStocksRefreshedChange;
        _currentState = _currentState.copyWith(
          topStocks: refreshedChange.topStocks,
          isLoading: false,
          isRefreshing: false,
          error: null,
          lastUpdated: refreshedChange.lastUpdated,
        );
        _emitSideEffect(ShowSuccessToastSideEffect('상위 점수 종목이 새로고침되었습니다.'));
        break;
        
      case MarketFilterChangedChange:
        final filterChange = change as MarketFilterChangedChange;
        _currentState = _currentState.copyWith(
          selectedMarket: filterChange.market,
        );
        break;
        
      case ScoreThresholdChangedChange:
        final thresholdChange = change as ScoreThresholdChangedChange;
        _currentState = _currentState.copyWith(
          minScoreThreshold: thresholdChange.threshold,
        );
        break;
        
      case DisplayLimitChangedChange:
        final limitChange = change as DisplayLimitChangedChange;
        _currentState = _currentState.copyWith(
          displayLimit: limitChange.limit,
        );
        break;
        
      case RealtimeScoreUpdateChange:
        final updateChange = change as RealtimeScoreUpdateChange;
        final updatedStocks = List<TopStockItem>.from(_currentState.topStocks);
        final stockIndex = updatedStocks.indexWhere(
          (stock) => stock.stockCode == updateChange.updatedStock.stockCode
        );
        
        if (stockIndex != -1) {
          updatedStocks[stockIndex] = updateChange.updatedStock;
          // 점수 기준으로 재정렬
          updatedStocks.sort((a, b) => b.score.compareTo(a.score));
          
          _currentState = _currentState.copyWith(
            topStocks: updatedStocks,
            lastUpdated: DateTime.now(),
          );
        }
        break;
        
      default:
        print('⚠️ 알 수 없는 Change: ${change.runtimeType}');
    }
    
    _stateController.add(_currentState);
  }

  /// SideEffect 발행
  void _emitSideEffect(TopStocksSideEffect sideEffect) {
    _sideEffectController.add(sideEffect);
  }

  /// 종목 상세 화면으로 네비게이션
  void navigateToStockDetail(String stockCode, String stockName) {
    _emitSideEffect(NavigateToStockDetailSideEffect(
      stockCode: stockCode,
      stockName: stockName,
    ));
  }

  /// 초기화
  Future<void> initialize() async {
    try {
      await _useCase.initializeData();
      print('✅ TopStocksViewModel 초기화 완료');
    } catch (e) {
      print('❌ TopStocksViewModel 초기화 실패: $e');
      _emitChange(TopStocksErrorChange(e.toString()));
    }
  }

  /// 정리
  void dispose() {
    _handleUnsubscribeFromScoreStream();
    _stateController.close();
    _sideEffectController.close();
    print('🗑️ TopStocksViewModel 정리 완료');
  }
}

/// TopStockItem 확장 (copyWith 메서드 추가)
extension TopStockItemCopyWith on TopStockItem {
  TopStockItem copyWith({
    String? stockCode,
    String? stockName,
    String? market,
    double? score,
    double? currentPrice,
    double? priceChange,
    double? priceChangeRate,
    int? volume,
    double? volumeRatio,
    int? rank,
    DateTime? lastUpdated,
  }) {
    return TopStockItem(
      stockCode: stockCode ?? this.stockCode,
      stockName: stockName ?? this.stockName,
      market: market ?? this.market,
      score: score ?? this.score,
      currentPrice: currentPrice ?? this.currentPrice,
      priceChange: priceChange ?? this.priceChange,
      priceChangeRate: priceChangeRate ?? this.priceChangeRate,
      volume: volume ?? this.volume,
      volumeRatio: volumeRatio ?? this.volumeRatio,
      rank: rank ?? this.rank,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}
