/**
 * MACD 동적 점수 계산기
 * MACD 값과 시그널 라인을 고려한 동적 점수 계산
 */
export class MACDCalculator {
  
  /**
   * MACD 동적 점수 계산
   * 
   * @param params 분석에 필요한 데이터
   * @returns -1.0 ~ +1.0 범위의 점수
   */
  static async calculate(params: {
    symbol: string;
    chartData: any[];
    currentPrice: any;
    currentTime: string;
  }): Promise<number> {
    try {
      const { currentPrice } = params;
      
      // MACD 값들 추출
      const macdValue = currentPrice.macd || this.calculateMACD(params.chartData);
      const signalValue = currentPrice.macd_signal || this.calculateMACDSignal(params.chartData);
      const histogram = currentPrice.macd_histogram || (macdValue - signalValue);
      
      if (macdValue === null || signalValue === null) {
        console.log(`⚠️ MACD 값 없음: ${params.symbol}`);
        return 0;
      }
      
      // 1. 기본 MACD 점수 계산
      const baseScore = this.calculateBaseMACDScore(macdValue, signalValue);
      
      // 2. 히스토그램 보정
      const histogramAdjustment = this.calculateHistogramAdjustment(histogram);
      
      // 3. 시간대별 보정
      const timeAdjustment = this.calculateTimeAdjustment(params.currentTime);
      
      // 4. 최종 점수 계산
      const finalScore = baseScore + histogramAdjustment + timeAdjustment;
      
      // 5. 점수 범위 제한 (-1.0 ~ +1.0)
      const clampedScore = Math.max(-1.0, Math.min(1.0, finalScore));
      
      console.log(`📊 MACD 점수 계산 완료: ${params.symbol} = ${clampedScore.toFixed(3)} (MACD: ${macdValue.toFixed(3)}, Signal: ${signalValue.toFixed(3)})`);
      return clampedScore;
      
    } catch (error) {
      console.error('❌ MACD 점수 계산 실패:', error);
      return 0;
    }
  }

  /**
   * 기본 MACD 점수 계산
   */
  private static calculateBaseMACDScore(macdValue: number, signalValue: number): number {
    const macdDiff = macdValue - signalValue;
    
    if (macdDiff > 0.1) {
      return 1.0; // 강한 상승 신호
    } else if (macdDiff > 0.05) {
      return 0.8; // 상승 신호
    } else if (macdDiff > 0.01) {
      return 0.4; // 약한 상승 신호
    } else if (macdDiff > -0.01) {
      return 0; // 중립
    } else if (macdDiff > -0.05) {
      return -0.4; // 약한 하락 신호
    } else if (macdDiff > -0.1) {
      return -0.8; // 하락 신호
    } else {
      return -1.0; // 강한 하락 신호
    }
  }

  /**
   * 히스토그램 보정 계산
   */
  private static calculateHistogramAdjustment(histogram: number): number {
    if (histogram > 0.05) {
      return 0.2; // 히스토그램이 강하게 상승
    } else if (histogram > 0.01) {
      return 0.1; // 히스토그램이 상승
    } else if (histogram < -0.05) {
      return -0.2; // 히스토그램이 강하게 하락
    } else if (histogram < -0.01) {
      return -0.1; // 히스토그램이 하락
    }
    
    return 0;
  }

  /**
   * 시간대별 보정 계산
   */
  private static calculateTimeAdjustment(currentTime: string): number {
    const hour = parseInt(currentTime.split(':')[0]);
    
    // 장 시작/마감 시간대에서는 보정 적용
    if ((hour >= 9 && hour <= 10) || (hour >= 14 && hour <= 15)) {
      return 0.05; // 장 시작/마감 시간대 보정
    }
    
    return 0;
  }

  /**
   * MACD 계산 (차트 데이터에서)
   */
  private static calculateMACD(chartData: any[], fastPeriod: number = 12, slowPeriod: number = 26): number {
    if (chartData.length < slowPeriod) {
      return 0; // 기본값
    }
    
    const prices = chartData
      .slice(-slowPeriod)
      .map(data => data.close || data.current_price)
      .filter(price => price > 0);
    
    if (prices.length < slowPeriod) {
      return 0; // 기본값
    }
    
    const ema12 = this.calculateEMA(prices, fastPeriod);
    const ema26 = this.calculateEMA(prices, slowPeriod);
    
    return ema12 - ema26;
  }

  /**
   * MACD 시그널 계산 (차트 데이터에서)
   */
  private static calculateMACDSignal(chartData: any[], signalPeriod: number = 9): number {
    if (chartData.length < signalPeriod) {
      return 0; // 기본값
    }
    
    const macdValues = [];
    for (let i = signalPeriod; i < chartData.length; i++) {
      const macd = this.calculateMACD(chartData.slice(0, i + 1));
      macdValues.push(macd);
    }
    
    if (macdValues.length === 0) {
      return 0; // 기본값
    }
    
    return this.calculateEMA(macdValues, signalPeriod);
  }

  /**
   * EMA (지수이동평균) 계산
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
