import '../analysis/unified_analysis_service.dart';
import '../data/app_data_manager.dart';
import 'investment_style_manager.dart';

enum TradeSignalType { buy, sell, hold }

class SignalReason {
  final String summary;
  final Map<String, dynamic> indicators;
  const SignalReason({required this.summary, required this.indicators});
}

class StrategyDecision {
  final TradeSignalType signal;
  final SignalReason reason;
  const StrategyDecision({required this.signal, required this.reason});
}

/// 새로운 7가지 동적 지표 시스템 기반 전략 엔진
class StrategyEngine {
  final UnifiedAnalysisService _unifiedAnalysis = UnifiedAnalysisService.instance;
  final AppDataManager _appDataManager = AppDataManager.instance;
  final InvestmentStyleManager _styleManager = InvestmentStyleManager();

  Future<StrategyDecision> decide(String stockCode) async {
    try {
      print('🤖 [StrategyEngine] $stockCode 종목 분석 시작');

      // 새로운 7가지 동적 지표 시스템으로 분석
      final analysis = await _unifiedAnalysis.analyzeStock(stockCode);
      
      if (analysis == null || analysis.isEmpty) {
        return StrategyDecision(
          signal: TradeSignalType.hold,
          reason: const SignalReason(summary: '분석 데이터 없음', indicators: {}),
        );
      }

      final signal = analysis['signal'] as String? ?? '관망';
      final comprehensiveScore = analysis['comprehensiveScore'] as double? ?? 0.0;
      final confidence = analysis['confidence'] as double? ?? 0.0;
      final targetPrice = analysis['targetPrice'] as double? ?? 0.0;
      final reason = analysis['reason'] as String? ?? '분석 완료';

      // 투자 스타일별 임계값 가져오기 (로컬DB에서만)
      final currentStyle = _styleManager.currentStyle;
      final styleParams = _styleManager.currentStyleSettings;
      final buyThreshold = styleParams?['buy_threshold'] as double?;
      final sellThreshold = styleParams?['sell_threshold'] as double?;
      
      if (buyThreshold == null || sellThreshold == null) {
        print('❌ [StrategyEngine] 투자 스타일 임계값이 설정되지 않았습니다.');
        return StrategyDecision(
          signal: TradeSignalType.hold,
          reason: const SignalReason(summary: '투자 스타일 설정 필요', indicators: {}),
        );
      }

      print('🤖 [StrategyEngine] 분석 결과:');
      print('   - 종합점수: ${comprehensiveScore.toStringAsFixed(3)}');
      print('   - 신뢰도: ${confidence.toStringAsFixed(3)}');
      print('   - 매수임계값: ${buyThreshold.toStringAsFixed(3)}');
      print('   - 매도임계값: ${sellThreshold.toStringAsFixed(3)}');

      // 매매 신호 결정
      TradeSignalType tradeSignal;
      String signalSummary;

      if (comprehensiveScore > buyThreshold && confidence > 0.5) {
        tradeSignal = TradeSignalType.buy;
        signalSummary = '7가지 동적 지표 매수 신호 (점수: ${comprehensiveScore.toStringAsFixed(3)})';
      } else if (comprehensiveScore <= sellThreshold && confidence > 0.5) {
        tradeSignal = TradeSignalType.sell;
        signalSummary = '7가지 동적 지표 매도 신호 (점수: ${comprehensiveScore.toStringAsFixed(3)})';
      } else {
        tradeSignal = TradeSignalType.hold;
        signalSummary = '관망 (점수: ${comprehensiveScore.toStringAsFixed(3)})';
      }

      final details = <String, dynamic>{
        'comprehensiveScore': comprehensiveScore,
        'confidence': confidence,
        'targetPrice': targetPrice,
        'buyThreshold': buyThreshold,
        'sellThreshold': sellThreshold,
        'currentStyle': currentStyle.toString(),
        'reason': reason,
      };

      print('🤖 [StrategyEngine] 최종 결정: $signalSummary');

      return StrategyDecision(
        signal: tradeSignal,
        reason: SignalReason(
          summary: signalSummary,
          indicators: details,
        ),
      );

    } catch (e) {
      print('❌ [StrategyEngine] 분석 실패: $e');
      return StrategyDecision(
        signal: TradeSignalType.hold,
        reason: SignalReason(summary: '분석 오류: $e', indicators: {}),
      );
    }
  }
}
