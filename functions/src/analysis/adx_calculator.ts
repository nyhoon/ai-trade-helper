/**
 * ADX 동적 점수 계산기
 * ADX 값과 방향성을 고려한 동적 점수 계산
 */
export class ADXCalculator {
  
  /**
   * ADX 동적 점수 계산
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
      
      // ADX 값 추출
      const adxValue = currentPrice.adx || this.calculateADX(params.chartData);
      
      if (!adxValue) {
        console.log(`⚠️ ADX 값 없음: ${params.symbol}`);
        return 0;
      }
      
      // 1. 기본 ADX 점수 계산
      const baseScore = this.calculateBaseADXScore(adxValue);
      
      // 2. 방향성 보정
      const directionAdjustment = this.calculateDirectionAdjustment(params.chartData);
      
      // 3. 시간대별 보정
      const timeAdjustment = this.calculateTimeAdjustment(params.currentTime);
      
      // 4. 최종 점수 계산
      const finalScore = baseScore + directionAdjustment + timeAdjustment;
      
      // 5. 점수 범위 제한 (-1.0 ~ +1.0)
      const clampedScore = Math.max(-1.0, Math.min(1.0, finalScore));
      
      console.log(`📊 ADX 점수 계산 완료: ${params.symbol} = ${clampedScore.toFixed(3)} (ADX: ${adxValue.toFixed(2)})`);
      return clampedScore;
      
    } catch (error) {
      console.error('❌ ADX 점수 계산 실패:', error);
      return 0;
    }
  }

  /**
   * 기본 ADX 점수 계산
   */
  private static calculateBaseADXScore(adxValue: number): number {
    if (adxValue >= 50) {
      return 0.8; // 매우 강한 추세
    } else if (adxValue >= 40) {
      return 0.6; // 강한 추세
    } else if (adxValue >= 30) {
      return 0.4; // 보통 추세
    } else if (adxValue >= 20) {
      return 0.2; // 약한 추세
    } else if (adxValue >= 15) {
      return 0; // 중립
    } else {
      return -0.2; // 추세 없음
    }
  }

  /**
   * 방향성 보정 계산
   */
  private static calculateDirectionAdjustment(chartData: any[]): number {
    if (chartData.length < 2) return 0;
    
    const recent = chartData.slice(-2);
    const price1 = recent[0]?.close || recent[0]?.current_price || 0;
    const price2 = recent[1]?.close || recent[1]?.current_price || 0;
    
    if (price1 === 0 || price2 === 0) return 0;
    
    const priceChange = (price2 - price1) / price1;
    
    if (priceChange > 0.02) { // 2% 이상 상승
      return 0.2; // 상승 방향성 보정
    } else if (priceChange < -0.02) { // 2% 이상 하락
      return -0.2; // 하락 방향성 감점
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
   * ADX 계산 (차트 데이터에서)
   */
  private static calculateADX(chartData: any[], period: number = 14): number {
    if (chartData.length < period + 1) {
      return 25; // 기본값 (중립)
    }
    
    const prices = chartData
      .slice(-period - 1)
      .map(data => ({
        high: data.high || data.current_price,
        low: data.low || data.current_price,
        close: data.close || data.current_price
      }))
      .filter(data => data.high > 0 && data.low > 0 && data.close > 0);
    
    if (prices.length < period + 1) {
      return 25; // 기본값
    }
    
    // True Range 계산
    const trueRanges = [];
    for (let i = 1; i < prices.length; i++) {
      const tr = Math.max(
        prices[i].high - prices[i].low,
        Math.abs(prices[i].high - prices[i-1].close),
        Math.abs(prices[i].low - prices[i-1].close)
      );
      trueRanges.push(tr);
    }
    
    // Directional Movement 계산
    const plusDM = [];
    const minusDM = [];
    
    for (let i = 1; i < prices.length; i++) {
      const highDiff = prices[i].high - prices[i-1].high;
      const lowDiff = prices[i-1].low - prices[i].low;
      
      if (highDiff > lowDiff && highDiff > 0) {
        plusDM.push(highDiff);
        minusDM.push(0);
      } else if (lowDiff > highDiff && lowDiff > 0) {
        plusDM.push(0);
        minusDM.push(lowDiff);
      } else {
        plusDM.push(0);
        minusDM.push(0);
      }
    }
    
    // 평활화된 값들 계산
    const atr = this.calculateATR(trueRanges, period);
    const plusDI = this.calculateDI(plusDM, atr, period);
    const minusDI = this.calculateDI(minusDM, atr, period);
    
    // ADX 계산
    const dx = Math.abs(plusDI - minusDI) / (plusDI + minusDI) * 100;
    const adx = this.calculateSmoothDX([dx], period);
    
    return adx;
  }

  /**
   * ATR 계산
   */
  private static calculateATR(trueRanges: number[], period: number): number {
    if (trueRanges.length < period) {
      return trueRanges.reduce((sum, tr) => sum + tr, 0) / trueRanges.length;
    }
    
    return trueRanges.slice(-period).reduce((sum, tr) => sum + tr, 0) / period;
  }

  /**
   * DI 계산
   */
  private static calculateDI(dm: number[], atr: number, period: number): number {
    if (dm.length < period) {
      const sum = dm.reduce((sum, val) => sum + val, 0);
      return (sum / dm.length) / atr * 100;
    }
    
    const sum = dm.slice(-period).reduce((sum, val) => sum + val, 0);
    return (sum / period) / atr * 100;
  }

  /**
   * 평활화된 DX 계산
   */
  private static calculateSmoothDX(dxValues: number[], period: number): number {
    if (dxValues.length < period) {
      return dxValues.reduce((sum, dx) => sum + dx, 0) / dxValues.length;
    }
    
    return dxValues.slice(-period).reduce((sum, dx) => sum + dx, 0) / period;
  }
}
