import '../../analysis/unified_analysis_service.dart';
import '../../data/app_data_manager.dart';
import '../../database/repositories/signal_history_repository.dart';
import '../investment_style_manager.dart';
import '../../api/kis_unified_api_service.dart';

class AnalyzeSignalsUseCase {
  final UnifiedAnalysisService _unifiedAnalysis = UnifiedAnalysisService.instance;
  final SignalHistoryRepository _signalRepo = SignalHistoryRepository();
  final InvestmentStyleManager _styleManager = InvestmentStyleManager();

  Future<List<Map<String, dynamic>>> execute(List<Map<String, dynamic>> universe) async {
    print('🔍 시그널 분석 시작 - ${universe.length}개 종목');
    
    // 현재 투자 스타일 설정 로드 (임계값 기반)
    final styleParams = await _styleManager.getStyleParameters(_styleManager.currentStyle);
    final volumeCondition = (styleParams['volumeCondition'] as num?)?.toDouble();
    if (volumeCondition == null) {
      print('⚠️ 거래량 조건이 설정되지 않았습니다.');
      return [];
    }
    final buyThreshold = (styleParams['buyThreshold'] as num?)?.toDouble();
    final sellThreshold = (styleParams['sellThreshold'] as num?)?.toDouble();
    
    if (buyThreshold == null || sellThreshold == null) {
      print('⚠️ 투자 스타일 임계값이 설정되지 않았습니다.');
      return [];
    }
    
    print('📊 분석 기준 - 거래량: ${(volumeCondition * 100).toStringAsFixed(0)}%, 매수임계값: $buyThreshold, 매도임계값: $sellThreshold');

    final results = <Map<String, dynamic>>[];
    int analyzedCount = 0;
    int signalCount = 0;

    for (final stock in universe) {
      try {
        final code = stock['stockCode'] as String?;
        if (code == null || code.isEmpty) continue;
        
        analyzedCount++;
        final price = await _currentPrice(code);
        if (price <= 0) continue;
        
        final analysis = await _unifiedAnalysis.analyzeStock(code, days: 100);
        
        if (analysis != null && (analysis['signal'] == '매수' || analysis['signal'] == '매도')) {
          // 임계값 기반 시그널 분석 (종합점수 vs 임계값)
          final aggregateScore = (analysis['aggregateScore'] as num?)?.toDouble() ?? 0.0;
          final signal = analysis['signal'] as String;
          final confidence = (analysis['confidence'] as num?)?.toDouble() ?? 0.0;

          // 중복 방지: 더 정교한 dedupKey 생성
          final now = DateTime.now();
          final dayKey = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
          final hourKey = '${now.hour.toString().padLeft(2, '0')}';
          final dedupKey = '$code-${signal}-$dayKey-$hourKey';

          // 최근 동일 시그널 존재 여부 확인 (1시간 내 중복 방지)
          final oneHourAgo = now.subtract(const Duration(hours: 1));
          final recent = await _signalRepo.getSignalsByDateRange(oneHourAgo, now);
          final isDup = recent.any((row) =>
              (row['stock_code']?.toString() ?? '') == code &&
              (row['signal_type']?.toString() ?? '') == signal);
          
          if (isDup) {
            print('⚠️ $code 중복 시그널 건너뜀: $signal');
            continue;
          }

          // signal_history에 저장 (임계값 기반)
          await _signalRepo.saveSignal(
            stockCode: code,
            signalType: signal,
            signalStrength: confidence,
            price: price,
            volume: 0,
            rsi: analysis['rsi'] as double?,
            macd: analysis['macd'] as double?,
            macdSignal: analysis['macdSignal'] as double?,
            sma20: analysis['sma20'] as double?,
            sma50: analysis['sma50'] as double?,
            bollingerPosition: analysis['bbPosition']?.toString(),
            confidence: confidence,
            memo: 'AutoCycle_${_styleManager.currentStyle.name}_Threshold',
            dedupKey: dedupKey,
          );

          results.add({
            'stockCode': code,
            'stockName': stock['stockName'] ?? code,
            'signal': signal,
            'analysis': analysis,
            'currentPrice': price,
            'dedupKey': dedupKey,
            'aggregateScore': aggregateScore,
            'confidence': confidence,
            'buyThreshold': buyThreshold,
            'sellThreshold': sellThreshold,
            'volumeCondition': volumeCondition,
          });
          
          signalCount++;
          print('🎯 시그널 생성: $code $signal @ $price (종합점수: ${aggregateScore.toStringAsFixed(2)}, 임계값: ${signal == '매수' ? buyThreshold : sellThreshold})');
        }
      } catch (e) {
        print('❌ ${stock['stockCode']} 분석 실패: $e');
      }
    }
    
    print('📊 시그널 분석 완료 - 분석: $analyzedCount개, 시그널: $signalCount개');
    return results;
  }

  Future<double> _currentPrice(String stockCode) async {
    try {
      // ✅ API 직접 호출 비활성화 - Firestore 구독 사용
      print('🔍 [current 보호] AnalyzeSignalsUseCase에서 API 직접 호출 비활성화');
      return 0.0;
      // final data = await KisUnifiedApiService().getStockPrice(stockCode);
      // return (data?['currentPrice'] as num?)?.toDouble() ?? 0.0;
    } catch (e) {
      print('❌ $stockCode 가격 조회 실패: $e');
      return 0.0;
    }
  }
}


