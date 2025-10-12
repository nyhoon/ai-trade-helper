// import * as admin from 'firebase-admin'; // 사용하지 않음

/**
 * 7개 지표 기반 분석 엔진
 * 거래량, RSI, MACD, 볼린저밴드, 이동평균선, VWAP, ADX
 */
export class AnalysisEngine {
  
  /**
   * 종목 분석 수행
   * @param symbol 종목코드
   * @param chartData 차트 데이터 (100일)
   * @param currentPrice 현재가
   * @param uid 사용자 ID
   * @returns 분석 결과
   */
  static async analyzeStock(symbol: string, chartData: any[], currentPrice: any, uid: string) {
    try {
      console.log(`📊 [AnalysisEngine] 종목 분석 시작: ${symbol}`);
      
      // 1. 기본 지표 계산
      const indicators = this.calculateIndicators(chartData, currentPrice);
      
      // 2. 시간대별 가중치 계산
      const timeWeight = this.getTimeWeight();
      
      // 3. 7개 지표별 점수 계산
      const scores = {
        volume: this.calculateVolumeScore(indicators, timeWeight),
        rsi: this.calculateRSIScore(indicators, timeWeight),
        macd: this.calculateMACDScore(indicators, timeWeight),
        bollinger: this.calculateBollingerScore(indicators, timeWeight),
        movingAverage: this.calculateMovingAverageScore(indicators, timeWeight),
        vwap: this.calculateVWAPScore(indicators, timeWeight),
        adx: this.calculateADXScore(indicators, timeWeight)
      };
      
      // 4. 종합 점수 계산
      const totalScore = this.calculateTotalScore(scores);
      
      // 5. 추천 의견 생성
      const recommendation = this.generateRecommendation(totalScore, scores);
      
      // 6. 신뢰도 계산
      const confidence = this.calculateConfidence(scores, indicators);
      
      const result = {
        symbol,
        totalScore,
        recommendation,
        confidence,
        scores,
        indicators: {
          rsi: indicators.rsi,
          macd: indicators.macd,
          bollinger: indicators.bollinger,
          movingAverage: indicators.movingAverage,
          vwap: indicators.vwap,
          adx: indicators.adx,
          volume: indicators.volume
        },
        lastUpdated: new Date().toISOString()
      };
      
      console.log(`✅ [AnalysisEngine] 종목 분석 완료: ${symbol} (점수: ${totalScore.toFixed(3)})`);
      return result;
      
    } catch (error) {
      console.error(`❌ [AnalysisEngine] 종목 분석 실패: ${symbol}`, error);
      throw error;
    }
  }
  
  /**
   * 기본 지표 계산
   */
  private static calculateIndicators(chartData: any[], currentPrice: any) {
    if (chartData.length < 20) {
      throw new Error('차트 데이터가 부족합니다 (최소 20일 필요)');
    }
    
    // RSI 계산
    const rsi = this.calculateRSI(chartData);
    
    // MACD 계산
    const macd = this.calculateMACD(chartData);
    
    // 볼린저밴드 계산
    const bollinger = this.calculateBollingerBands(chartData);
    
    // 이동평균선 계산
    const movingAverage = this.calculateMovingAverages(chartData);
    
    // VWAP 계산
    const vwap = this.calculateVWAP(chartData);
    
    // ADX 계산
    const adx = this.calculateADX(chartData);
    
    // 거래량 분석
    const volume = this.analyzeVolume(chartData);
    
    return {
      rsi,
      macd,
      bollinger,
      movingAverage,
      vwap,
      adx,
      volume,
      currentPrice: parseFloat(currentPrice?.prpr || currentPrice?.close || 0),
      chartData
    };
  }
  
  /**
   * RSI 계산 (14일)
   */
  private static calculateRSI(chartData: any[], period: number = 14) {
    if (chartData.length < period + 1) return 50;
    
    let gains = 0;
    let losses = 0;
    
    for (let i = 1; i <= period; i++) {
      const change = chartData[i].close - chartData[i - 1].close;
      if (change > 0) gains += change;
      else losses += Math.abs(change);
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
  private static calculateMACD(chartData: any[]) {
    const ema12 = this.calculateEMA(chartData, 12);
    const ema26 = this.calculateEMA(chartData, 26);
    const macd = ema12 - ema26;
    const signal = this.calculateEMA(chartData.map((_, i) => ({ close: macd })), 9);
    
    return {
      macd,
      signal,
      histogram: macd - signal
    };
  }
  
  /**
   * 볼린저밴드 계산
   */
  private static calculateBollingerBands(chartData: any[], period: number = 20, stdDev: number = 2) {
    if (chartData.length < period) return { upper: 0, middle: 0, lower: 0 };
    
    const closes = chartData.slice(-period).map(d => d.close);
    const sma = closes.reduce((a, b) => a + b, 0) / period;
    
    const variance = closes.reduce((sum, close) => sum + Math.pow(close - sma, 2), 0) / period;
    const std = Math.sqrt(variance);
    
    return {
      upper: sma + (std * stdDev),
      middle: sma,
      lower: sma - (std * stdDev)
    };
  }
  
  /**
   * 이동평균선 계산
   */
  private static calculateMovingAverages(chartData: any[]) {
    const closes = chartData.map(d => d.close);
    
    return {
      ma5: this.calculateSMA(closes, 5),
      ma20: this.calculateSMA(closes, 20),
      ma60: this.calculateSMA(closes, 60)
    };
  }
  
  /**
   * VWAP 계산
   */
  private static calculateVWAP(chartData: any[]) {
    let totalVolume = 0;
    let totalValue = 0;
    
    for (const data of chartData) {
      const volume = data.volume || 0;
      const price = (data.high + data.low + data.close) / 3;
      totalVolume += volume;
      totalValue += price * volume;
    }
    
    return totalVolume > 0 ? totalValue / totalVolume : 0;
  }
  
  /**
   * ADX 계산
   */
  private static calculateADX(chartData: any[], period: number = 14) {
    if (chartData.length < period + 1) return 25;
    
    let plusDM = 0;
    let minusDM = 0;
    let tr = 0;
    
    for (let i = 1; i <= period; i++) {
      const high = chartData[i].high;
      const low = chartData[i].low;
      const prevHigh = chartData[i - 1].high;
      const prevLow = chartData[i - 1].low;
      
      const highDiff = high - prevHigh;
      const lowDiff = prevLow - low;
      
      if (highDiff > lowDiff && highDiff > 0) plusDM += highDiff;
      if (lowDiff > highDiff && lowDiff > 0) minusDM += lowDiff;
      
      tr += Math.max(high - low, Math.abs(high - chartData[i - 1].close), Math.abs(low - chartData[i - 1].close));
    }
    
    const plusDI = (plusDM / tr) * 100;
    const minusDI = (minusDM / tr) * 100;
    const dx = Math.abs(plusDI - minusDI) / (plusDI + minusDI) * 100;
    
    return dx;
  }
  
  /**
   * 거래량 분석
   */
  private static analyzeVolume(chartData: any[]) {
    const volumes = chartData.map(d => d.volume || 0);
    const avgVolume = volumes.reduce((a, b) => a + b, 0) / volumes.length;
    const currentVolume = volumes[volumes.length - 1];
    const volumeRatio = avgVolume > 0 ? currentVolume / avgVolume : 1;
    
    return {
      current: currentVolume,
      average: avgVolume,
      ratio: volumeRatio
    };
  }
  
  /**
   * 거래량 점수 계산
   */
  private static calculateVolumeScore(indicators: any, timeWeight: number) {
    const { volume } = indicators;
    const { ratio } = volume;
    
    let baseScore = 0;
    
    if (ratio >= 2.0) baseScore = 1.0;
    else if (ratio >= 1.5) baseScore = 0.8;
    else if (ratio >= 1.2) baseScore = 0.6;
    else if (ratio >= 0.8) baseScore = 0.4;
    else baseScore = 0.2;
    
    // 방향성 판단 (현재가 vs 이전가)
    const currentPrice = indicators.currentPrice;
    const prevPrice = indicators.chartData[indicators.chartData.length - 2]?.close || currentPrice;
    const isRising = currentPrice > prevPrice;
    
    const directionScore = isRising ? baseScore : -baseScore;
    
    // 시간대별 가중치 적용
    const timeAdjustedScore = directionScore * timeWeight;
    
    // 장 시작 보정
    const marketOpenBonus = this.getMarketOpenBonus(ratio);
    
    return timeAdjustedScore + marketOpenBonus;
  }
  
  /**
   * RSI 점수 계산
   */
  private static calculateRSIScore(indicators: any, timeWeight: number) {
    const { rsi } = indicators;
    const { volume } = indicators;
    
    let baseScore = 0;
    
    if (rsi <= 30) baseScore = 1.0;
    else if (rsi <= 35) baseScore = 0.8;
    else if (rsi <= 40) baseScore = 0.6;
    else if (rsi <= 45) baseScore = 0.4;
    else if (rsi >= 70) baseScore = -1.0;
    else if (rsi >= 65) baseScore = -0.8;
    else if (rsi >= 60) baseScore = -0.6;
    else if (rsi >= 55) baseScore = -0.4;
    
    // 거래량 동반 보정
    const volumeBonus = this.getVolumeBonus(volume.ratio);
    
    // 변동성 보정 (ATR 기반)
    const volatilityBonus = this.getVolatilityBonus(indicators);
    
    return (baseScore * timeWeight) + volumeBonus + volatilityBonus;
  }
  
  /**
   * MACD 점수 계산
   */
  private static calculateMACDScore(indicators: any, timeWeight: number) {
    const { macd } = indicators;
    const { adx } = indicators;
    const { volume } = indicators;
    
    // 추세 강도 판단
    const trendStrength = adx >= 25 ? 1.5 : 1.0;
    
    let baseScore = 0;
    
    if (macd.macd > macd.signal) {
      baseScore = 1.0; // 골든크로스
    } else if (macd.macd < macd.signal) {
      baseScore = -1.0; // 데드크로스
    } else {
      baseScore = 0; // 중립
    }
    
    // 거래량 동반 보정
    const volumeBonus = this.getVolumeBonus(volume.ratio);
    
    // 시간대별 보정
    const timeBonus = this.getTimeBonus();
    
    return (baseScore * trendStrength * timeWeight) + volumeBonus + timeBonus;
  }
  
  /**
   * 볼린저밴드 점수 계산
   */
  private static calculateBollingerScore(indicators: any, timeWeight: number) {
    const { bollinger } = indicators;
    const { volume } = indicators;
    const currentPrice = indicators.currentPrice;
    
    if (!bollinger.upper || !bollinger.lower) return 0;
    
    const bandPosition = (currentPrice - bollinger.lower) / (bollinger.upper - bollinger.lower);
    
    let baseScore = 0;
    
    if (bandPosition <= 0.05) baseScore = 1.0; // 하단터치
    else if (bandPosition <= 0.15) baseScore = 0.6; // 하단근접
    else if (bandPosition >= 0.95) baseScore = -1.0; // 상단터치
    else if (bandPosition >= 0.85) baseScore = -0.6; // 상단근접
    
    // 변동성 보정
    const volatilityBonus = this.getVolatilityBonus(indicators);
    
    // 거래량 보정
    const volumeBonus = this.getVolumeBonus(volume.ratio);
    
    return (baseScore * timeWeight) + volumeBonus + volatilityBonus;
  }
  
  /**
   * 이동평균선 점수 계산
   */
  private static calculateMovingAverageScore(indicators: any, timeWeight: number) {
    const { movingAverage } = indicators;
    const { adx } = indicators;
    const { volume } = indicators;
    // const currentPrice = indicators.currentPrice; // 사용하지 않음
    
    // 배열 상태 판단
    const isFullBullish = movingAverage.ma5 > movingAverage.ma20 && movingAverage.ma20 > movingAverage.ma60;
    const isPartialBullish = movingAverage.ma5 > movingAverage.ma20;
    const isPartialBearish = movingAverage.ma5 < movingAverage.ma20;
    const isFullBearish = movingAverage.ma5 < movingAverage.ma20 && movingAverage.ma20 < movingAverage.ma60;
    
    let baseScore = 0;
    
    if (isFullBullish) baseScore = 1.0;
    else if (isPartialBullish) baseScore = 0.6;
    else if (isPartialBearish) baseScore = -0.6;
    else if (isFullBearish) baseScore = -1.0;
    
    // 시장환경 보정
    const marketBonus = adx >= 25 ? 1.4 : 1.0;
    
    // 거래량 보정
    const volumeBonus = this.getVolumeBonus(volume.ratio);
    
    // 시간대 보정
    const timeBonus = this.getTimeBonus();
    
    return (baseScore * marketBonus * timeWeight) + volumeBonus + timeBonus;
  }
  
  /**
   * VWAP 점수 계산
   */
  private static calculateVWAPScore(indicators: any, timeWeight: number) {
    const { vwap } = indicators;
    const { volume } = indicators;
    const currentPrice = indicators.currentPrice;
    
    if (vwap === 0) return 0;
    
    const vwapRatio = (currentPrice - vwap) / vwap;
    
    let baseScore = 0;
    
    if (vwapRatio >= 0.02) baseScore = 1.0; // VWAP 상단 돌파
    else if (vwapRatio >= 0.01) baseScore = 0.6; // VWAP 근접
    else if (vwapRatio <= -0.02) baseScore = -1.0; // VWAP 하단 이탈
    else if (vwapRatio <= -0.01) baseScore = -0.6; // VWAP 근접
    else baseScore = 0; // 중립
    
    // 거래량 보정
    const volumeBonus = this.getVolumeBonus(volume.ratio);
    
    // 변동성 보정
    const volatilityBonus = this.getVolatilityBonus(indicators);
    
    return (baseScore * timeWeight) + volumeBonus + volatilityBonus;
  }
  
  /**
   * ADX 점수 계산
   */
  private static calculateADXScore(indicators: any, timeWeight: number) {
    const { adx } = indicators;
    const { volume } = indicators;
    
    let baseScore = 0;
    
    if (adx >= 25) baseScore = 1.0; // 강한 추세
    else if (adx >= 20) baseScore = 0.8; // 보통 추세
    else if (adx < 20) baseScore = -0.3; // 약한 추세
    else if (adx < 15) baseScore = -0.8; // 무추세
    
    // 거래량 보정
    const volumeBonus = this.getVolumeBonus(volume.ratio);
    
    // 변동성 보정
    const volatilityBonus = this.getVolatilityBonus(indicators);
    
    return (baseScore * timeWeight) + volumeBonus + volatilityBonus;
  }
  
  /**
   * 종합 점수 계산
   */
  private static calculateTotalScore(scores: any) {
    return (
      scores.volume * 0.2 +
      scores.rsi * 0.2 +
      scores.macd * 0.2 +
      scores.bollinger * 0.15 +
      scores.movingAverage * 0.15 +
      scores.vwap * 0.05 +
      scores.adx * 0.05
    );
  }
  
  /**
   * 추천 의견 생성
   */
  private static generateRecommendation(totalScore: number, scores: any) {
    if (totalScore >= 0.6) return 'STRONG_BUY';
    if (totalScore >= 0.3) return 'BUY';
    if (totalScore >= -0.3) return 'HOLD';
    if (totalScore >= -0.6) return 'SELL';
    return 'STRONG_SELL';
  }
  
  /**
   * 신뢰도 계산
   */
  private static calculateConfidence(scores: any, indicators: any) {
    // 거래량이 높을수록 신뢰도 증가
    const volumeConfidence = Math.min(indicators.volume.ratio / 2, 1);
    
    // 지표들의 일치도 계산
    const positiveSignals = Object.values(scores).filter((score: any) => score > 0).length;
    const totalSignals = Object.keys(scores).length;
    const agreementConfidence = positiveSignals / totalSignals;
    
    return Math.min((volumeConfidence + agreementConfidence) / 2, 1);
  }
  
  // 헬퍼 메서드들
  private static getTimeWeight() {
    const now = new Date();
    const hour = now.getHours();
    const minute = now.getMinutes();
    const time = hour * 100 + minute;
    
    // 나스닥 시작 (22:30-23:30)
    if (time >= 2230 && time <= 2330) return 1.4;
    // 나스닥 본격 (23:30-05:00)
    if (time >= 2330 || time <= 500) return 1.2;
    // 나스닥 마감 (05:00-06:00)
    if (time >= 500 && time <= 600) return 1.5;
    // 코스피 시작 (09:00-10:00)
    if (time >= 900 && time <= 1000) return 1.2;
    // 코스피 중반 (10:00-14:00)
    if (time >= 1000 && time <= 1400) return 1.0;
    // 코스피 마감 (14:00-15:30)
    if (time >= 1400 && time <= 1530) return 1.3;
    // 기타 시간
    return 0.8;
  }
  
  private static getMarketOpenBonus(volumeRatio: number) {
    const now = new Date();
    const hour = now.getHours();
    const minute = now.getMinutes();
    const time = hour * 100 + minute;
    
    // 장 시작 시간대에서 거래량이 부족할 때 보정
    if ((time >= 2230 && time <= 2330) || (time >= 900 && time <= 1000)) {
      if (volumeRatio < 0.8) return 0.3;
    }
    
    return 0;
  }
  
  private static getVolumeBonus(volumeRatio: number) {
    if (volumeRatio >= 2.0) return 0.3;
    if (volumeRatio >= 1.5) return 0.2;
    if (volumeRatio >= 1.2) return 0.1;
    if (volumeRatio < 0.8) return -0.1;
    return 0;
  }
  
  private static getVolatilityBonus(indicators: any) {
    // ATR 기반 변동성 계산 (간단한 구현)
    const recentData = indicators.chartData.slice(-5);
    let volatility = 0;
    
    for (let i = 1; i < recentData.length; i++) {
      volatility += Math.abs(recentData[i].close - recentData[i - 1].close);
    }
    
    const avgVolatility = volatility / (recentData.length - 1);
    
    if (avgVolatility > indicators.currentPrice * 0.02) return 0.2; // 높은 변동성
    if (avgVolatility > indicators.currentPrice * 0.01) return 0.1; // 보통 변동성
    return 0;
  }
  
  private static getTimeBonus() {
    const now = new Date();
    const hour = now.getHours();
    const minute = now.getMinutes();
    const time = hour * 100 + minute;
    
    if (time >= 2230 && time <= 2330) return 0.2; // 나스닥 시작
    if (time >= 2330 || time <= 500) return 0.1; // 나스닥 본격
    if (time >= 500 && time <= 600) return 0.3; // 나스닥 마감
    if (time >= 900 && time <= 1000) return 0.2; // 코스피 시작
    return 0;
  }
  
  // 기술적 지표 계산 헬퍼 메서드들
  private static calculateEMA(data: any[], period: number) {
    if (data.length < period) return 0;
    
    const multiplier = 2 / (period + 1);
    let ema = data[0].close;
    
    for (let i = 1; i < data.length; i++) {
      ema = (data[i].close * multiplier) + (ema * (1 - multiplier));
    }
    
    return ema;
  }
  
  private static calculateSMA(data: number[], period: number) {
    if (data.length < period) return 0;
    
    const sum = data.slice(-period).reduce((a, b) => a + b, 0);
    return sum / period;
  }
}
