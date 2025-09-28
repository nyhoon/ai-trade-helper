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
      
      // 5. 실제 기술적 지표 값들 계산
      const technicalData = await this.calculateTechnicalData(params);
      
      // 6. 상세 분석 결과 생성
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
        technicalData,
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

  /**
   * 실제 기술적 지표 값들 계산
   */
  private static async calculateTechnicalData(params: {
    symbol: string;
    chartData: any[];
    currentPrice: any;
    currentTime: string;
  }): Promise<any> {
    try {
      const { chartData, currentPrice } = params;
      
      // 차트 데이터에서 가격 추출
      const prices = chartData
        .slice(-60) // 최근 60일
        .map(data => data.close || data.current_price)
        .filter(price => price > 0);
      
      const volumes = chartData
        .slice(-60)
        .map(data => data.volume || 0)
        .filter(vol => vol > 0);
      
      if (prices.length < 20) {
        console.log(`⚠️ 차트 데이터 부족: ${params.symbol} (${prices.length}개)`);
        return {};
      }
      
      // RSI 계산
      const rsi = this.calculateRSI(prices);
      
      // MACD 계산
      const macd = this.calculateMACD(prices);
      const macdSignal = this.calculateMACDSignal(prices);
      const macdHistogram = macd - macdSignal;
      
      // 볼린저밴드 계산
      const bollinger = this.calculateBollingerBands(prices);
      
      // 이동평균 계산
      const ma5 = this.calculateMA(prices, 5);
      const ma20 = this.calculateMA(prices, 20);
      const ma60 = this.calculateMA(prices, 60);
      
      // VWAP 계산
      const vwap = this.calculateVWAP(chartData.slice(-20));
      
      // ADX 계산
      const adx = this.calculateADX(chartData.slice(-20));
      
      // 거래량 정보 (실시간 데이터 우선)
      const currentVolume = currentPrice.volume || volumes[volumes.length - 1] || 0;
      const avgVolume = volumes.length > 0 ? volumes.reduce((a, b) => a + b, 0) / volumes.length : currentVolume;
      
      // 실시간 가격 데이터 우선 사용
      const realTimePrice = currentPrice.currentPrice || currentPrice.current_price || prices[prices.length - 1];
      const realTimeOpen = currentPrice.open || currentPrice.open_price || chartData[chartData.length - 1]?.open;
      const realTimeHigh = currentPrice.high || currentPrice.high_price || chartData[chartData.length - 1]?.high;
      const realTimeLow = currentPrice.low || currentPrice.low_price || chartData[chartData.length - 1]?.low;
      
      return {
        rsi,
        macd,
        signal: macdSignal,
        histogram: macdHistogram,
        bbUpper: bollinger.upper,
        bbMiddle: bollinger.middle,
        bbLower: bollinger.lower,
        ma5,
        ma20,
        ma60,
        vwap,
        adx,
        currentVolume,
        avgVolume,
        currentPrice: realTimePrice,
        openPrice: realTimeOpen,
        highPrice: realTimeHigh,
        lowPrice: realTimeLow,
        previousPrice: prices.length >= 2 ? prices[prices.length - 2] : prices[prices.length - 1]
      };
      
    } catch (error) {
      console.error('❌ 기술적 지표 값 계산 실패:', error);
      return {};
    }
  }

  /**
   * RSI 계산
   */
  private static calculateRSI(prices: number[], period: number = 14): number {
    if (prices.length < period + 1) return 50;
    
    let gains = 0;
    let losses = 0;
    
    for (let i = 1; i <= period; i++) {
      const change = prices[i] - prices[i - 1];
      if (change > 0) {
        gains += change;
      } else {
        losses += Math.abs(change);
      }
    }
    
    const avgGain = gains / period;
    const avgLoss = losses / period;
    
    if (avgLoss === 0) return 100;
    
    const rs = avgGain / avgLoss;
    return 100 - (100 / (1 + rs));
  }

  /**
   * MACD 계산
   */
  private static calculateMACD(prices: number[], fastPeriod: number = 12, slowPeriod: number = 26): number {
    if (prices.length < slowPeriod) return 0;
    
    const ema12 = this.calculateEMA(prices.slice(-slowPeriod), fastPeriod);
    const ema26 = this.calculateEMA(prices.slice(-slowPeriod), slowPeriod);
    
    return ema12 - ema26;
  }

  /**
   * MACD 시그널 계산
   */
  private static calculateMACDSignal(prices: number[], signalPeriod: number = 9): number {
    if (prices.length < signalPeriod + 26) return 0;
    
    const macdValues = [];
    for (let i = 26; i < prices.length; i++) {
      const macd = this.calculateMACD(prices.slice(0, i + 1));
      macdValues.push(macd);
    }
    
    if (macdValues.length < signalPeriod) return 0;
    
    return this.calculateEMA(macdValues.slice(-signalPeriod), signalPeriod);
  }

  /**
   * 볼린저밴드 계산
   */
  private static calculateBollingerBands(prices: number[], period: number = 20, stdDev: number = 2): any {
    if (prices.length < period) {
      const lastPrice = prices[prices.length - 1] || 0;
      return { upper: lastPrice * 1.02, middle: lastPrice, lower: lastPrice * 0.98 };
    }
    
    const recentPrices = prices.slice(-period);
    const sma = recentPrices.reduce((a, b) => a + b, 0) / period;
    
    const variance = recentPrices.reduce((sum, price) => sum + Math.pow(price - sma, 2), 0) / period;
    const stdDeviation = Math.sqrt(variance);
    
    return {
      upper: sma + (stdDeviation * stdDev),
      middle: sma,
      lower: sma - (stdDeviation * stdDev)
    };
  }

  /**
   * 이동평균 계산
   */
  private static calculateMA(prices: number[], period: number): number {
    if (prices.length < period) return prices[prices.length - 1] || 0;
    
    const recentPrices = prices.slice(-period);
    return recentPrices.reduce((a, b) => a + b, 0) / period;
  }

  /**
   * VWAP 계산
   */
  private static calculateVWAP(chartData: any[]): number {
    if (chartData.length === 0) return 0;
    
    let totalVolume = 0;
    let totalValue = 0;
    
    for (const data of chartData) {
      const price = (data.high + data.low + data.close) / 3; // 전형가
      const volume = data.volume || 0;
      
      totalValue += price * volume;
      totalVolume += volume;
    }
    
    return totalVolume > 0 ? totalValue / totalVolume : 0;
  }

  /**
   * ADX 계산 (간단한 버전)
   */
  private static calculateADX(chartData: any[]): number {
    if (chartData.length < 14) return 0;
    
    // 간단한 ADX 계산 (실제로는 더 복잡함)
    let totalRange = 0;
    let totalVolume = 0;
    
    for (const data of chartData) {
      const range = (data.high || 0) - (data.low || 0);
      const volume = data.volume || 0;
      
      totalRange += range;
      totalVolume += volume;
    }
    
    if (totalVolume === 0) return 0;
    
    const avgRange = totalRange / chartData.length;
    const avgVolume = totalVolume / chartData.length;
    
    // 간단한 ADX 근사값
    return Math.min(50, (avgRange / avgVolume) * 100);
  }

  /**
   * EMA 계산
   */
  private static calculateEMA(prices: number[], period: number): number {
    if (prices.length === 0) return 0;
    
    const multiplier = 2 / (period + 1);
    let ema = prices[0];
    
    for (let i = 1; i < prices.length; i++) {
      ema = (prices[i] * multiplier) + (ema * (1 - multiplier));
    }
    
    return ema;
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
  technicalData?: any;
  timestamp: number;
}
