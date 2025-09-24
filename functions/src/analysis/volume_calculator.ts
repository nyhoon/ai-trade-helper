/**
 * 거래량 동적 점수 계산기
 * 시간대별 가중치, 거래량비율, 상승/하락일 판단, 장 시작 보정 등을 포함
 */
export class VolumeCalculator {
  
  /// 시간대별 가중치 정의
  private static readonly TIME_WEIGHTS = {
    '22:30-23:30': 1.4, // 나스닥 시작
    '23:30-05:00': 1.2, // 나스닥 본격
    '05:00-06:00': 1.5, // 나스닥 마감
    '09:00-10:00': 1.2, // 코스피 시작
    '10:00-14:00': 1.0, // 코스피 중반
    '14:00-15:30': 1.3, // 코스피 마감
    'default': 0.8,     // 기타 시간
  };

  /// 거래량비율별 점수 정의
  private static readonly VOLUME_RATIO_SCORES = {
    '≥2.0': { up: 1.0, down: -1.0 },
    '≥1.5': { up: 0.8, down: -0.8 },
    '≥1.2': { up: 0.6, down: -0.6 },
    '≥0.8': { up: 0.4, down: -0.4 },
    '<0.8': { up: 0.2, down: -0.2 },
  };

  /// 장 시작 보정이 적용되는 시간대
  private static readonly MARKET_START_TIMES = ['22:30-23:30', '09:00-10:00'];

  /**
   * 거래량 동적 점수 계산
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
      const { currentPrice, currentTime } = params;
      
      // 현재가 데이터에서 필요한 값들 추출
      const currentVolume = currentPrice.volume || 0;
      const averageVolume = currentPrice.averageVolume || currentVolume;
      const openPrice = currentPrice.open_price || currentPrice.current_price;
      
      // 1. 현재가 방향성 판단 (시가 기준)
      const isUpDay = currentPrice.current_price >= openPrice;
      
      // 2. 거래량비율 계산
      const volumeRatio = this.calculateVolumeRatio(
        currentVolume,
        averageVolume,
        currentTime
      );
      
      // 3. 기본 점수 계산
      const baseScore = this.calculateBaseScore(volumeRatio, isUpDay);
      
      // 4. 장 시작 보정 적용
      const marketStartAdjustment = this.calculateMarketStartAdjustment(
        volumeRatio,
        currentTime
      );
      
      // 5. 최종 점수 계산
      const finalScore = baseScore + marketStartAdjustment;
      
      // 6. 점수 범위 제한 (-1.0 ~ +1.0)
      const clampedScore = Math.max(-1.0, Math.min(1.0, finalScore));
      
      console.log(`📊 거래량 점수 계산 완료: ${params.symbol} = ${clampedScore.toFixed(3)}`);
      return clampedScore;
      
    } catch (error) {
      console.error('❌ 거래량 점수 계산 실패:', error);
      return 0;
    }
  }

  /**
   * 거래량비율 계산
   */
  private static calculateVolumeRatio(
    currentVolume: number,
    averageVolume: number,
    currentTime: string
  ): number {
    if (averageVolume === 0) return 1.0;
    
    const baseRatio = currentVolume / averageVolume;
    
    // 시간대별 보정 적용
    const timeWeight = this.getTimeWeight(currentTime);
    return baseRatio * timeWeight;
  }

  /**
   * 기본 점수 계산
   */
  private static calculateBaseScore(volumeRatio: number, isUpDay: boolean): number {
    const direction = isUpDay ? 'up' : 'down';
    
    if (volumeRatio >= 2.0) {
      return this.VOLUME_RATIO_SCORES['≥2.0'][direction];
    } else if (volumeRatio >= 1.5) {
      return this.VOLUME_RATIO_SCORES['≥1.5'][direction];
    } else if (volumeRatio >= 1.2) {
      return this.VOLUME_RATIO_SCORES['≥1.2'][direction];
    } else if (volumeRatio >= 0.8) {
      return this.VOLUME_RATIO_SCORES['≥0.8'][direction];
    } else {
      return this.VOLUME_RATIO_SCORES['<0.8'][direction];
    }
  }

  /**
   * 장 시작 보정 계산
   */
  private static calculateMarketStartAdjustment(
    volumeRatio: number,
    currentTime: string
  ): number {
    if (this.MARKET_START_TIMES.some(time => this.isTimeInRange(currentTime, time))) {
      // 장 시작 시간대에서는 거래량이 높을 때 추가 보정
      if (volumeRatio >= 1.5) {
        return 0.2; // 추가 보정
      }
    }
    return 0;
  }

  /**
   * 시간대별 가중치 조회
   */
  private static getTimeWeight(currentTime: string): number {
    for (const [timeRange, weight] of Object.entries(this.TIME_WEIGHTS)) {
      if (timeRange === 'default') continue;
      if (this.isTimeInRange(currentTime, timeRange)) {
        return weight;
      }
    }
    return this.TIME_WEIGHTS.default;
  }

  /**
   * 시간이 특정 범위에 속하는지 확인
   */
  private static isTimeInRange(currentTime: string, timeRange: string): boolean {
    const [start, end] = timeRange.split('-');
    const current = this.parseTime(currentTime);
    const startTime = this.parseTime(start);
    const endTime = this.parseTime(end);
    
    if (startTime <= endTime) {
      return current >= startTime && current <= endTime;
    } else {
      // 자정을 넘나드는 경우 (예: 23:30-05:00)
      return current >= startTime || current <= endTime;
    }
  }

  /**
   * 시간 문자열을 분 단위로 변환
   */
  private static parseTime(timeStr: string): number {
    const [hours, minutes] = timeStr.split(':').map(Number);
    return hours * 60 + minutes;
  }
}
