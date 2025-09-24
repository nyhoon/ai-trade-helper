/**
 * 이동평균 동적 점수 계산기
 * 단기/장기 이동평균선의 교차와 거리를 고려한 동적 점수 계산
 */
export class MovingAverageCalculator {
  
  /**
   * 이동평균 동적 점수 계산
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
      
      // 이동평균 값들 추출
      const sma20 = currentPrice.sma20 || this.calculateSMA(params.chartData, 20);
      const sma50 = currentPrice.sma50 || this.calculateSMA(params.chartData, 50);
      const currentPriceValue = currentPrice.current_price;
      
      if (!sma20 || !sma50 || !currentPriceValue) {
        console.log(`⚠️ 이동평균 값 없음: ${params.symbol}`);
        return 0;
      }
      
      // 1. 기본 이동평균 점수 계산
      const baseScore = this.calculateBaseMovingAverageScore(currentPriceValue, sma20, sma50);
      
      // 2. 교차 신호 보정
      const crossoverAdjustment = this.calculateCrossoverAdjustment(params.chartData);
      
      // 3. 거리 보정
      const distanceAdjustment = this.calculateDistanceAdjustment(currentPriceValue, sma20, sma50);
      
      // 4. 시간대별 보정
      const timeAdjustment = this.calculateTimeAdjustment(params.currentTime);
      
      // 5. 최종 점수 계산
      const finalScore = baseScore + crossoverAdjustment + distanceAdjustment + timeAdjustment;
      
      // 6. 점수 범위 제한 (-1.0 ~ +1.0)
      const clampedScore = Math.max(-1.0, Math.min(1.0, finalScore));
      
      console.log(`📊 이동평균 점수 계산 완료: ${params.symbol} = ${clampedScore.toFixed(3)} (SMA20: ${sma20.toFixed(2)}, SMA50: ${sma50.toFixed(2)})`);
      return clampedScore;
      
    } catch (error) {
      console.error('❌ 이동평균 점수 계산 실패:', error);
      return 0;
    }
  }

  /**
   * 기본 이동평균 점수 계산
   */
  private static calculateBaseMovingAverageScore(
    currentPrice: number,
    sma20: number,
    sma50: number
  ): number {
    // 현재가가 이동평균선 위에 있는지 확인
    const aboveSMA20 = currentPrice > sma20;
    const aboveSMA50 = currentPrice > sma50;
    
    // SMA20이 SMA50 위에 있는지 확인 (골든크로스/데드크로스)
    const sma20AboveSMA50 = sma20 > sma50;
    
    let score = 0;
    
    // 현재가 위치에 따른 점수
    if (aboveSMA20 && aboveSMA50) {
      score += 0.5; // 두 이동평균선 모두 위에 있음
    } else if (aboveSMA20) {
      score += 0.2; // SMA20 위에만 있음
    } else if (aboveSMA50) {
      score += 0.1; // SMA50 위에만 있음
    } else {
      score -= 0.3; // 두 이동평균선 모두 아래에 있음
    }
    
    // 이동평균선 교차 상태에 따른 점수
    if (sma20AboveSMA50) {
      score += 0.3; // 골든크로스 상태
    } else {
      score -= 0.3; // 데드크로스 상태
    }
    
    return score;
  }

  /**
   * 교차 신호 보정 계산
   */
  private static calculateCrossoverAdjustment(chartData: any[]): number {
    if (chartData.length < 2) return 0;
    
    chartData.slice(-2);
    const sma20_1 = this.calculateSMA(chartData.slice(0, -1), 20);
    const sma20_2 = this.calculateSMA(chartData, 20);
    const sma50_1 = this.calculateSMA(chartData.slice(0, -1), 50);
    const sma50_2 = this.calculateSMA(chartData, 50);
    
    // 골든크로스 감지 (SMA20이 SMA50을 상향 돌파)
    if (sma20_1 <= sma50_1 && sma20_2 > sma50_2) {
      return 0.4; // 골든크로스 보정
    }
    
    // 데드크로스 감지 (SMA20이 SMA50을 하향 돌파)
    if (sma20_1 >= sma50_1 && sma20_2 < sma50_2) {
      return -0.4; // 데드크로스 감점
    }
    
    return 0;
  }

  /**
   * 거리 보정 계산
   */
  private static calculateDistanceAdjustment(
    currentPrice: number,
    sma20: number,
    sma50: number
  ): number {
    const distanceFromSMA20 = Math.abs(currentPrice - sma20) / sma20;
    const distanceFromSMA50 = Math.abs(currentPrice - sma50) / sma50;
    
    let adjustment = 0;
    
    // SMA20과의 거리가 가까울 때 보정
    if (distanceFromSMA20 < 0.02) { // 2% 이내
      adjustment += 0.1;
    } else if (distanceFromSMA20 > 0.1) { // 10% 이상
      adjustment -= 0.1;
    }
    
    // SMA50과의 거리가 가까울 때 보정
    if (distanceFromSMA50 < 0.05) { // 5% 이내
      adjustment += 0.05;
    } else if (distanceFromSMA50 > 0.2) { // 20% 이상
      adjustment -= 0.05;
    }
    
    return adjustment;
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
   * SMA (단순이동평균) 계산
   */
  private static calculateSMA(chartData: any[], period: number): number {
    if (chartData.length < period) {
      // 데이터가 부족하면 사용 가능한 데이터로 계산
      const prices = chartData
        .map(data => data.close || data.current_price)
        .filter(price => price > 0);
      
      if (prices.length === 0) return 0;
      
      return prices.reduce((sum, price) => sum + price, 0) / prices.length;
    }
    
    const prices = chartData
      .slice(-period)
      .map(data => data.close || data.current_price)
      .filter(price => price > 0);
    
    if (prices.length === 0) return 0;
    
    return prices.reduce((sum, price) => sum + price, 0) / prices.length;
  }
}
