/**
 * 볼린저밴드 동적 점수 계산기
 * 볼린저밴드 위치와 거래량을 고려한 동적 점수 계산
 */
export class BollingerCalculator {
  
  /**
   * 볼린저밴드 동적 점수 계산
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
      
      // 볼린저밴드 값들 추출
      const upperBand = currentPrice.bollinger_upper || this.calculateBollingerBands(params.chartData).upper;
      const middleBand = currentPrice.bollinger_middle || this.calculateBollingerBands(params.chartData).middle;
      const lowerBand = currentPrice.bollinger_lower || this.calculateBollingerBands(params.chartData).lower;
      const currentPriceValue = currentPrice.current_price;
      
      if (!upperBand || !middleBand || !lowerBand || !currentPriceValue) {
        console.log(`⚠️ 볼린저밴드 값 없음: ${params.symbol}`);
        return 0;
      }
      
      // 1. 기본 볼린저밴드 점수 계산
      const baseScore = this.calculateBaseBollingerScore(
        currentPriceValue,
        upperBand,
        middleBand,
        lowerBand
      );
      
      // 2. 밴드 폭 보정
      const bandWidthAdjustment = this.calculateBandWidthAdjustment(upperBand, lowerBand, middleBand);
      
      // 3. 거래량 보정
      const volumeAdjustment = this.calculateVolumeAdjustment(currentPrice.volume, currentPrice.averageVolume);
      
      // 4. 시간대별 보정
      const timeAdjustment = this.calculateTimeAdjustment(params.currentTime);
      
      // 5. 최종 점수 계산
      const finalScore = baseScore + bandWidthAdjustment + volumeAdjustment + timeAdjustment;
      
      // 6. 점수 범위 제한 (-1.0 ~ +1.0)
      const clampedScore = Math.max(-1.0, Math.min(1.0, finalScore));
      
      console.log(`📊 볼린저밴드 점수 계산 완료: ${params.symbol} = ${clampedScore.toFixed(3)}`);
      return clampedScore;
      
    } catch (error) {
      console.error('❌ 볼린저밴드 점수 계산 실패:', error);
      return 0;
    }
  }

  /**
   * 기본 볼린저밴드 점수 계산
   */
  private static calculateBaseBollingerScore(
    currentPrice: number,
    upperBand: number,
    middleBand: number,
    lowerBand: number
  ): number {
    const bandWidth = upperBand - lowerBand;
    const pricePosition = (currentPrice - lowerBand) / bandWidth;
    
    if (pricePosition >= 0.95) {
      return -1.0; // 상단 밴드 근처 (과매수)
    } else if (pricePosition >= 0.8) {
      return -0.6; // 상단 밴드 위쪽 (과매수 경향)
    } else if (pricePosition >= 0.6) {
      return -0.2; // 상단 밴드 아래쪽 (약간 과매수)
    } else if (pricePosition >= 0.4) {
      return 0; // 중간 영역 (중립)
    } else if (pricePosition >= 0.2) {
      return 0.2; // 하단 밴드 위쪽 (약간 과매도)
    } else if (pricePosition >= 0.05) {
      return 0.6; // 하단 밴드 아래쪽 (과매도 경향)
    } else {
      return 1.0; // 하단 밴드 근처 (과매도)
    }
  }

  /**
   * 밴드 폭 보정 계산
   */
  private static calculateBandWidthAdjustment(
    upperBand: number,
    lowerBand: number,
    middleBand: number
  ): number {
    const bandWidth = upperBand - lowerBand;
    const relativeBandWidth = bandWidth / middleBand;
    
    if (relativeBandWidth > 0.1) {
      return 0.1; // 밴드가 넓을 때 (변동성 높음) 보정
    } else if (relativeBandWidth < 0.05) {
      return -0.1; // 밴드가 좁을 때 (변동성 낮음) 감점
    }
    
    return 0;
  }

  /**
   * 거래량 보정 계산
   */
  private static calculateVolumeAdjustment(currentVolume: number, averageVolume: number): number {
    if (!currentVolume || !averageVolume || averageVolume === 0) return 0;
    
    const volumeRatio = currentVolume / averageVolume;
    
    if (volumeRatio >= 1.5) {
      return 0.1; // 거래량이 높을 때 보정
    } else if (volumeRatio <= 0.7) {
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
   * 볼린저밴드 계산 (차트 데이터에서)
   */
  private static calculateBollingerBands(chartData: any[], period: number = 20, stdDev: number = 2): {
    upper: number;
    middle: number;
    lower: number;
  } {
    if (chartData.length < period) {
      const lastPrice = chartData[chartData.length - 1]?.close || chartData[chartData.length - 1]?.current_price || 0;
      return {
        upper: lastPrice * 1.02,
        middle: lastPrice,
        lower: lastPrice * 0.98
      };
    }
    
    const prices = chartData
      .slice(-period)
      .map(data => data.close || data.current_price)
      .filter(price => price > 0);
    
    if (prices.length < period) {
      const lastPrice = prices[prices.length - 1] || 0;
      return {
        upper: lastPrice * 1.02,
        middle: lastPrice,
        lower: lastPrice * 0.98
      };
    }
    
    // 중간선 (SMA)
    const middle = prices.reduce((sum, price) => sum + price, 0) / prices.length;
    
    // 표준편차 계산
    const variance = prices.reduce((sum, price) => sum + Math.pow(price - middle, 2), 0) / prices.length;
    const standardDeviation = Math.sqrt(variance);
    
    // 상단/하단 밴드
    const upper = middle + (standardDeviation * stdDev);
    const lower = middle - (standardDeviation * stdDev);
    
    return { upper, middle, lower };
  }
}
