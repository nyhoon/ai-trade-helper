/**
 * VWAP 동적 점수 계산기
 * VWAP와 현재가의 관계를 고려한 동적 점수 계산
 */
export class VWAPCalculator {
  
  /**
   * VWAP 동적 점수 계산
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
      
      // VWAP 값 추출
      const vwapValue = currentPrice.vwap || this.calculateVWAP(params.chartData);
      const currentPriceValue = currentPrice.current_price;
      
      if (!vwapValue || !currentPriceValue) {
        console.log(`⚠️ VWAP 값 없음: ${params.symbol}`);
        return 0;
      }
      
      // 1. 기본 VWAP 점수 계산
      const baseScore = this.calculateBaseVWAPScore(currentPriceValue, vwapValue);
      
      // 2. 거래량 보정
      const volumeAdjustment = this.calculateVolumeAdjustment(currentPrice.volume, currentPrice.averageVolume);
      
      // 3. 시간대별 보정
      const timeAdjustment = this.calculateTimeAdjustment(params.currentTime);
      
      // 4. 최종 점수 계산
      const finalScore = baseScore + volumeAdjustment + timeAdjustment;
      
      // 5. 점수 범위 제한 (-1.0 ~ +1.0)
      const clampedScore = Math.max(-1.0, Math.min(1.0, finalScore));
      
      console.log(`📊 VWAP 점수 계산 완료: ${params.symbol} = ${clampedScore.toFixed(3)} (VWAP: ${vwapValue.toFixed(2)})`);
      return clampedScore;
      
    } catch (error) {
      console.error('❌ VWAP 점수 계산 실패:', error);
      return 0;
    }
  }

  /**
   * 기본 VWAP 점수 계산
   */
  private static calculateBaseVWAPScore(currentPrice: number, vwapValue: number): number {
    const priceRatio = currentPrice / vwapValue;
    
    if (priceRatio >= 1.05) {
      return 0.8; // VWAP보다 5% 이상 높음 (강한 상승)
    } else if (priceRatio >= 1.02) {
      return 0.4; // VWAP보다 2% 이상 높음 (상승)
    } else if (priceRatio >= 1.01) {
      return 0.2; // VWAP보다 1% 이상 높음 (약한 상승)
    } else if (priceRatio >= 0.99) {
      return 0; // VWAP 근처 (중립)
    } else if (priceRatio >= 0.98) {
      return -0.2; // VWAP보다 1% 이상 낮음 (약한 하락)
    } else if (priceRatio >= 0.95) {
      return -0.4; // VWAP보다 2% 이상 낮음 (하락)
    } else {
      return -0.8; // VWAP보다 5% 이상 낮음 (강한 하락)
    }
  }

  /**
   * 거래량 보정 계산
   */
  private static calculateVolumeAdjustment(currentVolume: number, averageVolume: number): number {
    if (!currentVolume || !averageVolume || averageVolume === 0) return 0;
    
    const volumeRatio = currentVolume / averageVolume;
    
    if (volumeRatio >= 2.0) {
      return 0.2; // 거래량이 매우 높을 때 보정
    } else if (volumeRatio >= 1.5) {
      return 0.1; // 거래량이 높을 때 보정
    } else if (volumeRatio <= 0.5) {
      return -0.1; // 거래량이 낮을 때 감점
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
   * VWAP 계산 (차트 데이터에서)
   */
  private static calculateVWAP(chartData: any[]): number {
    if (chartData.length === 0) return 0;
    
    let totalVolumePrice = 0;
    let totalVolume = 0;
    
    for (const data of chartData) {
      const price = data.close || data.current_price;
      const volume = data.volume || 0;
      
      if (price > 0 && volume > 0) {
        totalVolumePrice += price * volume;
        totalVolume += volume;
      }
    }
    
    if (totalVolume === 0) return 0;
    
    return totalVolumePrice / totalVolume;
  }
}
