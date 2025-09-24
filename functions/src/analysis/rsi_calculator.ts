/**
 * RSI 동적 점수 계산기
 * RSI 값과 거래량, ATR을 고려한 동적 점수 계산
 */
export class RSICalculator {
  
  /**
   * RSI 동적 점수 계산
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
      
      // RSI 값 추출
      const rsiValue = currentPrice.rsi || this.calculateRSI(params.chartData);
      
      if (rsiValue === null || rsiValue === undefined) {
        console.log(`⚠️ RSI 값 없음: ${params.symbol}`);
        return 0;
      }
      
      // 거래량 정보
      const currentVolume = currentPrice.volume || 0;
      const averageVolume = currentPrice.averageVolume || currentVolume;
      
      // ATR 정보
      const currentATR = currentPrice.atr || 0;
      const averageATR = currentPrice.averageATR || currentATR;
      
      // 1. 기본 RSI 점수 계산
      const baseScore = this.calculateBaseRSIScore(rsiValue);
      
      // 2. 거래량 보정
      const volumeAdjustment = this.calculateVolumeAdjustment(currentVolume, averageVolume);
      
      // 3. ATR 보정
      const atrAdjustment = this.calculateATRAdjustment(currentATR, averageATR);
      
      // 4. 시간대별 보정
      const timeAdjustment = this.calculateTimeAdjustment(params.currentTime);
      
      // 5. 최종 점수 계산
      const finalScore = baseScore + volumeAdjustment + atrAdjustment + timeAdjustment;
      
      // 6. 점수 범위 제한 (-1.0 ~ +1.0)
      const clampedScore = Math.max(-1.0, Math.min(1.0, finalScore));
      
      console.log(`📊 RSI 점수 계산 완료: ${params.symbol} = ${clampedScore.toFixed(3)} (RSI: ${rsiValue.toFixed(2)})`);
      return clampedScore;
      
    } catch (error) {
      console.error('❌ RSI 점수 계산 실패:', error);
      return 0;
    }
  }

  /**
   * 기본 RSI 점수 계산
   */
  private static calculateBaseRSIScore(rsiValue: number): number {
    if (rsiValue >= 80) {
      return -1.0; // 매우 과매수
    } else if (rsiValue >= 70) {
      return -0.8; // 과매수
    } else if (rsiValue >= 60) {
      return -0.4; // 약간 과매수
    } else if (rsiValue >= 40) {
      return 0; // 중립
    } else if (rsiValue >= 30) {
      return 0.4; // 약간 과매도
    } else if (rsiValue >= 20) {
      return 0.8; // 과매도
    } else {
      return 1.0; // 매우 과매도
    }
  }

  /**
   * 거래량 보정 계산
   */
  private static calculateVolumeAdjustment(currentVolume: number, averageVolume: number): number {
    if (averageVolume === 0) return 0;
    
    const volumeRatio = currentVolume / averageVolume;
    
    if (volumeRatio >= 2.0) {
      return 0.2; // 거래량이 매우 높을 때 추가 보정
    } else if (volumeRatio >= 1.5) {
      return 0.1; // 거래량이 높을 때 보정
    } else if (volumeRatio <= 0.5) {
      return -0.1; // 거래량이 낮을 때 감점
    }
    
    return 0;
  }

  /**
   * ATR 보정 계산
   */
  private static calculateATRAdjustment(currentATR: number, averageATR: number): number {
    if (averageATR === 0) return 0;
    
    const atrRatio = currentATR / averageATR;
    
    if (atrRatio >= 1.5) {
      return 0.1; // 변동성이 높을 때 보정
    } else if (atrRatio <= 0.7) {
      return -0.1; // 변동성이 낮을 때 감점
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
   * RSI 계산 (차트 데이터에서)
   */
  private static calculateRSI(chartData: any[], period: number = 14): number {
    if (chartData.length < period + 1) {
      return 50; // 기본값
    }
    
    const prices = chartData
      .slice(-period - 1)
      .map(data => data.close || data.current_price)
      .filter(price => price > 0);
    
    if (prices.length < period + 1) {
      return 50; // 기본값
    }
    
    let gains = 0;
    let losses = 0;
    
    for (let i = 1; i < prices.length; i++) {
      const change = prices[i] - prices[i - 1];
      if (change > 0) {
        gains += change;
      } else {
        losses += Math.abs(change);
      }
    }
    
    const avgGain = gains / period;
    const avgLoss = losses / period;
    
    if (avgLoss === 0) {
      return 100; // 모든 날이 상승
    }
    
    const rs = avgGain / avgLoss;
    const rsi = 100 - (100 / (1 + rs));
    
    return rsi;
  }
}
