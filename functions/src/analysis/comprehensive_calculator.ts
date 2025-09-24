import { VolumeCalculator } from './volume_calculator';
import { RSICalculator } from './rsi_calculator';
import { MACDCalculator } from './macd_calculator';
import { BollingerCalculator } from './bollinger_calculator';
import { MovingAverageCalculator } from './moving_average_calculator';
import { VWAPCalculator } from './vwap_calculator';
import { ADXCalculator } from './adx_calculator';

/**
 * 종합 지표 점수 계산기
 * 7개 지표의 점수를 종합하여 최종 점수를 계산하고, 매매 실행 기준을 판단
 */
export class ComprehensiveIndicatorCalculator {
  
  /// 지표별 가중치 정의
  private static readonly INDICATOR_WEIGHTS = {
    volume: 0.20,    // 거래량 (20%)
    rsi: 0.20,       // RSI (20%)
    macd: 0.20,      // MACD (20%)
    bollinger: 0.15, // 볼린저밴드 (15%)
    movingAverage: 0.15, // 이동평균선 (15%)
    vwap: 0.05,      // VWAP (5%)
    adx: 0.05,       // ADX (5%)
  };

  /**
   * 종합 지표 점수 계산
   * 
   * @param params 분석에 필요한 데이터
   * @returns 종합 점수와 분석 결과
   */
  static async calculateComprehensiveScore(params: {
    symbol: string;
    chartData: any[];
    currentPrice: any;
    currentTime: string;
    buyThreshold?: number;
    sellThreshold?: number;
  }): Promise<AnalysisResult> {
    try {
      console.log('🎯 종합 지표 점수 계산 시작:', params.symbol);
      
      // 1. 각 지표별 점수 계산 (병렬 실행)
      const [
        volumeScore,
        rsiScore,
        macdScore,
        bollingerScore,
        movingAverageScore,
        vwapScore,
        adxScore
      ] = await Promise.all([
        VolumeCalculator.calculate(params),
        RSICalculator.calculate(params),
        MACDCalculator.calculate(params),
        BollingerCalculator.calculate(params),
        MovingAverageCalculator.calculate(params),
        VWAPCalculator.calculate(params),
        ADXCalculator.calculate(params)
      ]);
      
      // 2. 가중 평균으로 종합 점수 계산
      const comprehensiveScore = this.calculateWeightedAverage({
        volume: volumeScore,
        rsi: rsiScore,
        macd: macdScore,
        bollinger: bollingerScore,
        movingAverage: movingAverageScore,
        vwap: vwapScore,
        adx: adxScore
      });
      
      // 3. 매매 실행 기준 판단
      const tradingDecision = this.determineTradingDecision(
        comprehensiveScore, 
        params.buyThreshold || 0.6, 
        params.sellThreshold || -0.6
      );
      
      // 4. 신호 강도 분석
      const signalStrength = this.analyzeSignalStrength(comprehensiveScore);
      
      // 5. 상세 분석 결과 생성
      const result: AnalysisResult = {
        symbol: params.symbol,
        comprehensiveScore,
        tradingDecision,
        signalStrength,
        individualScores: {
          volume: volumeScore,
          rsi: rsiScore,
          macd: macdScore,
          bollinger: bollingerScore,
          movingAverage: movingAverageScore,
          vwap: vwapScore,
          adx: adxScore
        },
        analysis: {
          volume: { score: volumeScore, weight: this.INDICATOR_WEIGHTS.volume },
          rsi: { score: rsiScore, weight: this.INDICATOR_WEIGHTS.rsi },
          macd: { score: macdScore, weight: this.INDICATOR_WEIGHTS.macd },
          bollinger: { score: bollingerScore, weight: this.INDICATOR_WEIGHTS.bollinger },
          movingAverage: { score: movingAverageScore, weight: this.INDICATOR_WEIGHTS.movingAverage },
          vwap: { score: vwapScore, weight: this.INDICATOR_WEIGHTS.vwap },
          adx: { score: adxScore, weight: this.INDICATOR_WEIGHTS.adx }
        },
        timestamp: Date.now()
      };
      
      console.log('✅ 종합 지표 점수 계산 완료:', params.symbol, comprehensiveScore);
      return result;
      
    } catch (error) {
      console.error('❌ 종합 지표 점수 계산 실패:', error);
      throw error;
    }
  }

  /**
   * 가중 평균 계산
   */
  private static calculateWeightedAverage(scores: Record<string, number>): number {
    let weightedSum = 0;
    let totalWeight = 0;
    
    for (const [indicator, score] of Object.entries(scores)) {
      const weight = this.INDICATOR_WEIGHTS[indicator as keyof typeof this.INDICATOR_WEIGHTS];
      weightedSum += score * weight;
      totalWeight += weight;
    }
    
    return totalWeight > 0 ? weightedSum / totalWeight : 0;
  }

  /**
   * 매매 실행 기준 판단
   */
  private static determineTradingDecision(
    score: number, 
    buyThreshold: number, 
    sellThreshold: number
  ): string {
    if (score >= buyThreshold) {
      return 'BUY';
    } else if (score <= sellThreshold) {
      return 'SELL';
    } else {
      return 'HOLD';
    }
  }

  /**
   * 신호 강도 분석
   */
  private static analyzeSignalStrength(score: number): string {
    const absScore = Math.abs(score);
    
    if (absScore >= 0.8) {
      return '매우 강한 신호';
    } else if (absScore >= 0.6) {
      return '강한 신호';
    } else if (absScore >= 0.4) {
      return '보통 신호';
    } else if (absScore >= 0.2) {
      return '약한 신호';
    } else {
      return '매우 약한 신호';
    }
  }
}

/**
 * 분석 결과 인터페이스
 */
export interface AnalysisResult {
  symbol: string;
  comprehensiveScore: number;
  tradingDecision: string;
  signalStrength: string;
  individualScores: Record<string, number>;
  analysis: Record<string, { score: number; weight: number }>;
  timestamp: number;
}
