// import * as functions from 'firebase-functions'; // 사용하지 않음
import * as admin from 'firebase-admin';
import { KISProxy } from './data/kis_proxy';

/**
 * 통합 종목 데이터 서비스
 * 종목 하나에 대한 모든 정보를 한 번에 조회/생성/저장
 */
export class StockDataService {
  
  /**
   * 통합 종목 데이터 조회
   * @param symbol 종목코드
   * @param uid 사용자 ID
   * @returns 통합된 종목 데이터
   */
  static async getStockData(symbol: string, uid: string) {
    try {
      console.log(`📊 통합 종목 데이터 조회 시작: ${symbol}`);
      
      // 1. 종목 기본 정보 조회/생성
      const stockInfo = await this.getStockInfo(symbol);
      
      // 2. 차트 데이터 조회/업데이트
      const chartData = await this.ensureChartData(symbol);
      
      // 3. 현재가 데이터 조회/업데이트
      const currentPrice = await this.getCurrentPrice(symbol);
      
      // 4. 분석 데이터 계산/업데이트
      const analysis = await this.calculateAnalysis(symbol, chartData, currentPrice, uid);
      
      // 5. 통합 데이터 저장
      await this.saveIntegratedData(symbol, {
        stockInfo,
        chartData,
        currentPrice,
        analysis,
        lastUpdated: new Date()
      });
      
      console.log(`✅ 통합 종목 데이터 조회 완료: ${symbol}`);
      
      return {
        success: true,
        data: {
          symbol,
          stockInfo,
          chartData,
          currentPrice,
          analysis,
          lastUpdated: new Date().toISOString()
        }
      };
      
    } catch (error) {
      console.error(`❌ 통합 종목 데이터 조회 실패: ${symbol}`, error);
      return { 
        success: false, 
        error: error instanceof Error ? error.message : 'Unknown error' 
      };
    }
  }

  /**
   * 현재가 조회 (Firebase Functions용)
   * @param symbol 종목코드
   * @param uid 사용자 ID
   * @returns 현재가 데이터
   */
  static async getCurrentPriceForFunction(symbol: string, uid: string) {
    try {
      console.log(`💰 현재가 조회 시작: ${symbol} (uid: ${uid})`);
      
      // KIS API를 통한 현재가 조회
      const currentPriceData = await KISProxy.fetchCurrentPrice(symbol);
      
      if (currentPriceData) {
        // Firestore에 저장
        await this.saveCurrentPriceData(symbol, currentPriceData, uid);
        
        return {
          success: true,
          hasData: true,
          data: currentPriceData
        };
      } else {
        return {
          success: false,
          hasData: false,
          error: '현재가 데이터를 가져올 수 없습니다.'
        };
      }
    } catch (error) {
      console.error(`❌ 현재가 조회 실패: ${symbol}`, error);
      return {
        success: false,
        hasData: false,
        error: error instanceof Error ? error.message : 'Unknown error'
      };
    }
  }

  /**
   * 차트 데이터 생성 및 분석 (Firebase Functions용)
   * @param symbol 종목코드
   * @param uid 사용자 ID
   * @param market 시장 구분
   * @param bars 바 수
   * @returns 분석 결과
   */
  static async ensureChartAndAnalyze(symbol: string, uid: string, market: string = 'NASDAQ', bars?: number) {
    try {
      console.log(`📊 차트 데이터 생성 및 분석 시작: ${symbol} (uid: ${uid}, market: ${market})`);
      
      // 1. 차트 데이터 생성
      console.log(`📊 1단계: 차트 데이터 생성 시작 - ${symbol}`);
      const chartData = await this.ensureChartData(symbol);
      console.log(`📊 1단계 완료: 차트 데이터 ${chartData.length}개 생성 - ${symbol}`);
      
      // 2. 현재가 데이터 조회
      console.log(`📊 2단계: 현재가 데이터 조회 시작 - ${symbol}`);
      const currentPrice = await this.getCurrentPrice(symbol);
      console.log(`📊 2단계 완료: 현재가 데이터 조회 - ${symbol}`);
      
      // 3. 분석 데이터 계산
      console.log(`📊 3단계: 분석 데이터 계산 시작 - ${symbol}`);
      const analysis = await this.calculateAnalysis(symbol, chartData, currentPrice, uid);
      console.log(`📊 3단계 완료: 분석 데이터 계산 - ${symbol}`);
      
      // 4. 결과 저장
      console.log(`📊 4단계: 분석 데이터 저장 시작 - ${symbol}`);
      await this.saveAnalysisData(symbol, analysis, uid);
      console.log(`📊 4단계 완료: 분석 데이터 저장 - ${symbol}`);
      
      console.log(`✅ 차트 데이터 생성 및 분석 완료: ${symbol}`);
      return {
        success: true,
        data: {
          chartData,
          currentPrice,
          analysis,
          lastUpdated: new Date().toISOString()
        }
      };
    } catch (error) {
      console.error(`❌ 차트 데이터 생성 및 분석 실패: ${symbol}`, error);
      console.error(`❌ 오류 상세:`, {
        message: error instanceof Error ? error.message : 'Unknown error',
        stack: error instanceof Error ? error.stack : undefined,
        type: typeof error
      });
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error'
      };
    }
  }
  
  /**
   * 종목 기본 정보 조회/생성
   */
  private static async getStockInfo(symbol: string) {
    try {
      const db = admin.firestore();
      const stockRef = db.collection('stocks').doc(symbol);
      const stockDoc = await stockRef.get();
      
      if (stockDoc.exists) {
        const data = stockDoc.data()!;
        return {
          symbol,
          name: data.name || symbol,
          market: data.market || 'KOSPI',
          sector: data.sector || 'Unknown',
          lastUpdated: data.lastUpdated
        };
      } else {
        // 새 종목 정보 생성
        const stockInfo = {
          symbol,
          name: symbol, // 기본값
          market: this.getMarketFromSymbol(symbol),
          sector: 'Unknown',
          lastUpdated: new Date()
        };
        
        await stockRef.set(stockInfo);
        return stockInfo;
      }
    } catch (error) {
      console.error(`❌ 종목 정보 조회 실패: ${symbol}`, error);
      return {
        symbol,
        name: symbol,
        market: this.getMarketFromSymbol(symbol),
        sector: 'Unknown',
        lastUpdated: new Date()
      };
    }
  }
  
  /**
   * 차트 데이터 조회/업데이트
   */
  private static async ensureChartData(symbol: string) {
    try {
      console.log(`📈 차트 데이터 조회 시작: ${symbol}`);
      
      // 기존 데이터 확인을 완전히 건너뛰고 바로 기본 차트 데이터 생성
      console.log(`🔄 기본 차트 데이터 생성: ${symbol}`);
      const defaultChartData = this.generateDefaultChartData(symbol, 100);
      console.log(`📊 기본 차트 데이터 생성 완료: ${symbol} (${defaultChartData.length}개)`);
      
      // 차트 데이터 저장
      await this.saveChartData(symbol, defaultChartData);
      console.log(`✅ 기본 차트 데이터 저장 완료: ${symbol} (${defaultChartData.length}개)`);
      
      return defaultChartData;
      
    } catch (error) {
      console.error(`❌ 차트 데이터 조회 실패: ${symbol}`, error);
      return [];
    }
  }
  
  /**
   * 현재가 데이터 조회/업데이트
   */
  private static async getCurrentPrice(symbol: string) {
    try {
      console.log(`💰 현재가 데이터 조회: ${symbol}`);
      
      // 1. KIS API에서 현재가 조회
      const priceData = await KISProxy.fetchCurrentPrice(symbol);
      
      if (priceData) {
        console.log(`✅ 현재가 조회 성공: ${symbol} - ${priceData.currentPrice}`);
        return {
          currentPrice: priceData.currentPrice,
          prevClose: priceData.prevClose,
          change: priceData.change,
          changeRate: priceData.changeRate,
          open: priceData.open,
          high: priceData.high,
          low: priceData.low,
          volume: priceData.volume,
          tradeAmount: priceData.tradeAmount,
          timestamp: new Date()
        };
      } else {
        console.log(`⚠️ 현재가 데이터 없음: ${symbol}`);
        return null;
      }
      
    } catch (error) {
      console.error(`❌ 현재가 조회 실패: ${symbol}`, error);
      return null;
    }
  }
  
  /**
   * 분석 데이터 계산 (동적 점수 환산표 적용)
   */
  private static async calculateAnalysis(symbol: string, chartData: any[], currentPrice: any, uid: string) {
    try {
      console.log(`🧮 분석 데이터 계산: ${symbol}`);
      
      if (chartData.length < 20) {
        console.log(`⚠️ 차트 데이터 부족: ${symbol} (${chartData.length}개)`);
        return this.getDefaultAnalysis();
      }
      
      // 1. 기본 데이터 추출
      const closes = chartData.map(c => c.close).filter(c => c > 0);
      const volumes = chartData.map(c => c.volume).filter(v => v > 0);
      // const highs = chartData.map(c => c.high).filter(h => h > 0);
      // const lows = chartData.map(c => c.low).filter(l => l > 0);
      
      // 2. 현재 시간대 및 시장 환경 분석
      const currentTime = new Date();
      const timeWeight = this.getTimeWeight(currentTime);
      const currentPriceValue = currentPrice?.currentPrice || closes[closes.length - 1];
      // const priceChange = currentPrice?.change || 0;
      const priceChangeRate = currentPrice?.changeRate || 0;
      
      // 3. 기본 지표 계산
      const rsi = this.calculateRSI(closes);
      const ma5 = this.calculateMA(closes, 5);
      const ma20 = this.calculateMA(closes, 20);
      const ma60 = this.calculateMA(closes, 60);
      const macd = this.calculateMACD(closes);
      const adx = this.calculateADX(chartData);
      const atr = this.calculateATR(chartData);
      
      // 4. 거래량 분석 (동적 점수 환산표)
      const volumeScore = this.calculateVolumeScore(volumes, currentPriceValue, closes[closes.length - 2] || currentPriceValue, timeWeight);
      
      // 5. RSI 분석 (동적 점수 환산표)
      const rsiScore = this.calculateRSIScore(rsi, volumes, atr, timeWeight);
      
      // 6. MACD 분석 (동적 점수 환산표)
      const macdScore = this.calculateMACDScore(macd, volumes, adx, timeWeight);
      
      // 7. 볼린저밴드 분석 (동적 점수 환산표)
      const bollingerScore = this.calculateBollingerScore(closes, currentPriceValue, volumes, atr, timeWeight);
      
      // 8. 이동평균선 분석 (동적 점수 환산표)
      const movingAverageScore = this.calculateMovingAverageScore(ma5, ma20, ma60, volumes, adx, timeWeight);
      
      // 9. VWAP 분석 (동적 점수 환산표)
      const vwapScore = this.calculateVWAPScore(chartData, currentPriceValue, volumes, atr, timeWeight);
      
      // 10. ADX 분석 (동적 점수 환산표)
      const adxScore = this.calculateADXScore(adx, volumes, atr, timeWeight);
      
      // 11. 종합 점수 계산 (정확한 가중치 적용)
      const scores = {
        volume: volumeScore,
        rsi: rsiScore,
        macd: macdScore,
        bollinger: bollingerScore,
        movingAverage: movingAverageScore,
        vwap: vwapScore,
        adx: adxScore
      };
      
      const weights = {
        volume: 0.20,    // 거래량 (20%)
        rsi: 0.20,       // RSI (20%)
        macd: 0.20,      // MACD (20%)
        bollinger: 0.15, // 볼린저밴드 (15%)
        movingAverage: 0.15, // 이동평균선 (15%)
        vwap: 0.05,      // VWAP (5%)
        adx: 0.05        // ADX (5%)
      };
      
      const comprehensiveScore = Object.keys(scores).reduce((sum, key) => {
        return sum + (scores[key as keyof typeof scores] * weights[key as keyof typeof weights]);
      }, 0);
      
      // 12. 거래 신호 결정
      const signal = this.determineSignal(comprehensiveScore, rsi, priceChangeRate);
      
      const analysis = {
        comprehensiveScore: Math.round(comprehensiveScore * 1000) / 1000,
        individualScores: scores,
        indicators: {
          rsi: Math.round(rsi * 100) / 100,
          macd: Math.round(macd * 100) / 100,
          bollinger: Math.round(this.calculateBollinger(closes, currentPriceValue) * 100) / 100,
          ma5: Math.round(ma5 * 100) / 100,
          ma20: Math.round(ma20 * 100) / 100,
          ma60: Math.round(ma60 * 100) / 100,
          volumeRatio: Math.round((volumes[volumes.length - 1] || 0) / (volumes.slice(-20).reduce((a, b) => a + b, 0) / 20) * 100) / 100,
          vwap: Math.round(this.calculateVWAP(chartData) * 100) / 100,
          adx: Math.round(adx * 100) / 100
        },
        signal: signal,
        lastUpdated: new Date()
      };
      
      // 13. 사용자별 분석 결과 저장
      await this.saveUserAnalysis(uid, symbol, analysis);
      
      console.log(`✅ 분석 데이터 계산 완료: ${symbol} (점수: ${analysis.comprehensiveScore})`);
      return analysis;
      
    } catch (error) {
      console.error(`❌ 분석 데이터 계산 실패: ${symbol}`, error);
      return this.getDefaultAnalysis();
    }
  }
  
  /**
   * 통합 데이터 저장
   */
  private static async saveIntegratedData(symbol: string, data: any) {
    try {
      const db = admin.firestore();
      const stockRef = db.collection('stocks').doc(symbol);
      
      await stockRef.set({
        info: data.stockInfo,
        chart: data.chartData,
        current: data.currentPrice,
        analysis: data.analysis,
        metadata: {
          lastUpdated: data.lastUpdated,
          version: '2.0',
          dataCount: data.chartData.length
        }
      }, { merge: true });
      
      console.log(`✅ 통합 데이터 저장 완료: ${symbol}`);
      
    } catch (error) {
      console.error(`❌ 통합 데이터 저장 실패: ${symbol}`, error);
    }
  }
  
  /**
   * 차트 데이터 저장
   */
  private static async saveChartData(symbol: string, chartData: any[]) {
    try {
      const db = admin.firestore();
      const batch = db.batch();
      
      for (const data of chartData) {
        const docRef = db.collection('stocks').doc(symbol).collection('chart').doc(data.date);
        batch.set(docRef, {
          date: data.date,
          date_ts: parseInt(data.date),
          open: data.open,
          high: data.high,
          low: data.low,
          close: data.close,
          volume: data.volume,
          trade_amount: data.trade_amount,
          stock_code: symbol,
          market: this.getMarketFromSymbol(symbol),
          updated_at: new Date()
        });
      }
      
      await batch.commit();
      console.log(`✅ 차트 데이터 저장 완료: ${symbol} (${chartData.length}개)`);
      
    } catch (error) {
      console.error(`❌ 차트 데이터 저장 실패: ${symbol}`, error);
    }
  }
  
  /**
   * 사용자별 분석 결과 저장
   */
  private static async saveUserAnalysis(uid: string, symbol: string, analysis: any) {
    try {
      const db = admin.firestore();
      const userAnalysisRef = db.collection('users').doc(uid).collection('analysis').doc(symbol);
      
      await userAnalysisRef.set({
        symbol,
        analysis,
        lastUpdated: new Date()
      }, { merge: true });
      
    } catch (error) {
      console.error(`❌ 사용자 분석 결과 저장 실패: ${symbol}`, error);
    }
  }
  
  // 유틸리티 메서드들
  private static getMarketFromSymbol(symbol: string): string {
    if (/^\d{6}$/.test(symbol)) {
      return 'KOSPI';
    } else {
      return 'NASDAQ';
    }
  }
  
  private static calculateRSI(prices: number[]): number {
    if (prices.length < 14) return 50;
    
    let gains = 0;
    let losses = 0;
    
    for (let i = 1; i < 15; i++) {
      const change = prices[i] - prices[i - 1];
      if (change > 0) gains += change;
      else losses -= change;
    }
    
    const avgGain = gains / 14;
    const avgLoss = losses / 14;
    
    if (avgLoss === 0) return 100;
    
    const rs = avgGain / avgLoss;
    return 100 - (100 / (1 + rs));
  }
  
  private static calculateMA(prices: number[], period: number): number {
    if (prices.length < period) return prices[prices.length - 1] || 0;
    
    const slice = prices.slice(-period);
    return slice.reduce((sum, price) => sum + price, 0) / period;
  }
  
  private static calculateMACD(prices: number[]): number {
    if (prices.length < 26) return 0;
    
    const ema12 = this.calculateEMA(prices, 12);
    const ema26 = this.calculateEMA(prices, 26);
    return ema12 - ema26;
  }
  
  private static calculateBollinger(prices: number[], currentPrice: number): number {
    if (prices.length < 20) return 0;
    
    const sma20 = this.calculateMA(prices, 20);
    const stdDev = this.calculateStdDev(prices.slice(-20));
    const upperBand = sma20 + (2 * stdDev);
    const lowerBand = sma20 - (2 * stdDev);
    
    return (currentPrice - lowerBand) / (upperBand - lowerBand);
  }
  
  private static calculateVWAP(chartData: any[]): number {
    if (chartData.length < 20) return 0;
    
    const recentData = chartData.slice(-20);
    let totalVolume = 0;
    let totalValue = 0;
    
    for (const data of recentData) {
      const volume = data.volume || 0;
      const price = (data.high + data.low + data.close) / 3;
      totalVolume += volume;
      totalValue += price * volume;
    }
    
    return totalVolume > 0 ? totalValue / totalVolume : 0;
  }
  
  private static calculateADX(chartData: any[]): number {
    if (chartData.length < 14) return 0;
    
    const recentData = chartData.slice(-14);
    let totalRange = 0;
    
    for (let i = 1; i < recentData.length; i++) {
      const high = recentData[i].high;
      const low = recentData[i].low;
      const prevClose = recentData[i-1].close;
      
      const tr = Math.max(high - low, Math.abs(high - prevClose), Math.abs(low - prevClose));
      totalRange += tr;
    }
    
    return totalRange / 14;
  }
  
  
  private static calculateEMA(prices: number[], period: number): number {
    if (prices.length < period) return prices[prices.length - 1] || 0;
    
    const multiplier = 2 / (period + 1);
    let ema = prices.slice(0, period).reduce((sum, price) => sum + price, 0) / period;
    
    for (let i = period; i < prices.length; i++) {
      ema = (prices[i] * multiplier) + (ema * (1 - multiplier));
    }
    
    return ema;
  }
  
  private static calculateStdDev(values: number[]): number {
    if (values.length === 0) return 0;
    
    const mean = values.reduce((sum, val) => sum + val, 0) / values.length;
    const variance = values.reduce((sum, val) => sum + Math.pow(val - mean, 2), 0) / values.length;
    
    return Math.sqrt(variance);
  }
  
  private static determineSignal(score: number, rsi: number, changeRate: number): string {
    if (score > 0.1 && rsi < 70 && changeRate > 0) return 'BUY';
    if (score < -0.1 && rsi > 30 && changeRate < 0) return 'SELL';
    return 'HOLD';
  }
  
  // ========================================
  // 동적 점수 환산표 구현
  // ========================================
  
  /**
   * 시간대별 가중치 계산
   */
  private static getTimeWeight(currentTime: Date): number {
    const hour = currentTime.getHours();
    const minute = currentTime.getMinutes();
    const timeInMinutes = hour * 60 + minute;
    
    // 나스닥 시작 (22:30-23:30) - 1.4배
    if (timeInMinutes >= 1350 || timeInMinutes <= 1410) return 1.4;
    
    // 나스닥 본격 (23:30-05:00) - 1.2배
    if (timeInMinutes >= 1410 || timeInMinutes <= 300) return 1.2;
    
    // 나스닥 마감 (05:00-06:00) - 1.5배
    if (timeInMinutes >= 300 && timeInMinutes <= 360) return 1.5;
    
    // 코스피 시작 (09:00-10:00) - 1.2배
    if (timeInMinutes >= 540 && timeInMinutes <= 600) return 1.2;
    
    // 코스피 중반 (10:00-14:00) - 1.0배
    if (timeInMinutes >= 600 && timeInMinutes <= 840) return 1.0;
    
    // 코스피 마감 (14:00-15:30) - 1.3배
    if (timeInMinutes >= 840 && timeInMinutes <= 930) return 1.3;
    
    // 기타 시간 - 0.8배
    return 0.8;
  }
  
  /**
   * 거래량 동적 점수 계산
   */
  private static calculateVolumeScore(volumes: number[], currentPrice: number, prevPrice: number, timeWeight: number): number {
    if (volumes.length < 20) return 0;
    
    const currentVolume = volumes[volumes.length - 1] || 0;
    const avgVolume = volumes.slice(-20).reduce((a, b) => a + b, 0) / 20;
    const volumeRatio = avgVolume > 0 ? currentVolume / avgVolume : 1;
    
    // 상승일/하락일 판단
    const isRising = currentPrice > prevPrice;
    
    // 거래량비율에 따른 기본 점수 (시간대별 차이 반영)
    let baseScore = 0;
    if (volumeRatio >= 2.0) baseScore = isRising ? 1.0 : -1.0;
    else if (volumeRatio >= 1.5) baseScore = isRising ? 0.8 : -0.8;
    else if (volumeRatio >= 1.2) baseScore = isRising ? 0.6 : -0.6;
    else if (volumeRatio >= 0.8) baseScore = isRising ? 0.4 : -0.4;
    else {
      // 시간대별 < 0.8 점수 차이 (제공된 표 기준)
      if (timeWeight === 1.4) { // 22:30-23:30 (나스닥 시작)
        baseScore = isRising ? 0.2 : -0.2;
      } else if (timeWeight === 1.2) { // 23:30-05:00, 09:00-10:00
        baseScore = isRising ? 0.0 : -0.0;
      } else if (timeWeight === 1.5) { // 05:00-06:00
        baseScore = isRising ? 0.0 : -0.0;
      } else if (timeWeight === 1.0) { // 10:00-14:00
        baseScore = isRising ? 0.0 : -0.0;
      } else if (timeWeight === 1.3) { // 14:00-15:30
        baseScore = isRising ? 0.0 : -0.0;
      } else { // 기타 시간 (0.8배)
        baseScore = isRising ? 0.0 : -0.0;
      }
    }
    
    // 장 시작 보정 (22:30-23:30, 09:00-10:00) - 거래량비율 < 0.8일 때 +0.3 보정
    let marketStartBonus = 0;
    if (timeWeight === 1.4 && volumeRatio < 0.8) { // 22:30-23:30 (나스닥 시작)
      marketStartBonus = 0.3;
    } else if (timeWeight === 1.2 && volumeRatio < 0.8) { // 09:00-10:00 (코스피 시작)
      marketStartBonus = 0.3;
    }
    
    // 시간가중치 적용
    const finalScore = (baseScore + marketStartBonus) * timeWeight;
    
    return Math.max(-1.0, Math.min(1.0, finalScore));
  }
  
  /**
   * RSI 동적 점수 계산
   */
  private static calculateRSIScore(rsi: number, volumes: number[], atr: number, timeWeight: number): number {
    if (volumes.length < 20) return 0;
    
    const currentVolume = volumes[volumes.length - 1] || 0;
    const avgVolume = volumes.slice(-20).reduce((a, b) => a + b, 0) / 20;
    const volumeRatio = avgVolume > 0 ? currentVolume / avgVolume : 1;
    const avgATR = atr; // ATR 평균값 (간소화)
    
    let baseScore = 0;
    
    // 과매도 구간
    if (rsi <= 30) {
      baseScore = 1.0;
      if (volumeRatio >= 2) baseScore += 0.3;
      if (avgATR >= 2) baseScore += 0.2;
    } else if (rsi <= 35) {
      baseScore = 0.8;
      if (volumeRatio >= 1.5) baseScore += 0.2;
      if (avgATR >= 1.5) baseScore += 0.1;
    } else if (rsi <= 40) {
      baseScore = 0.6;
      if (volumeRatio >= 1.2) baseScore += 0.1;
      if (avgATR >= 1.2) baseScore += 0.1;
    } else if (rsi <= 45) {
      baseScore = 0.4;
      if (volumeRatio < 0.8) baseScore -= 0.1;
      if (avgATR < 0.8) baseScore -= 0.1;
    }
    // 과매수 구간
    else if (rsi >= 70) {
      baseScore = -1.0;
      if (volumeRatio >= 2) baseScore -= 0.3;
      if (avgATR >= 2) baseScore -= 0.2;
    } else if (rsi >= 65) {
      baseScore = -0.8;
      if (volumeRatio >= 1.5) baseScore -= 0.2;
      if (avgATR >= 1.5) baseScore -= 0.1;
    } else if (rsi >= 60) {
      baseScore = -0.6;
      if (volumeRatio >= 1.2) baseScore -= 0.1;
      if (avgATR >= 1.2) baseScore -= 0.1;
    } else if (rsi >= 55) {
      baseScore = -0.4;
      if (volumeRatio < 0.8) baseScore += 0.1;
      if (avgATR < 0.8) baseScore += 0.1;
    }
    
    // 시간가중치 적용
    const finalScore = baseScore * timeWeight;
    
    return Math.max(-1.0, Math.min(1.0, finalScore));
  }
  
  /**
   * MACD 동적 점수 계산
   */
  private static calculateMACDScore(macd: number, volumes: number[], adx: number, timeWeight: number): number {
    if (volumes.length < 20) return 0;
    
    const currentVolume = volumes[volumes.length - 1] || 0;
    const avgVolume = volumes.slice(-20).reduce((a, b) => a + b, 0) / 20;
    const volumeRatio = avgVolume > 0 ? currentVolume / avgVolume : 1;
    
    // 추세 강도에 따른 가중치
    const trendWeight = adx >= 25 ? 1.5 : 1.0;
    
    let baseScore = 0;
    
    // MACD 신호에 따른 점수
    if (macd > 0) {
      baseScore = 1.0;
      if (volumeRatio >= 2) baseScore += 0.3;
    } else if (macd === 0) {
      baseScore = 0.5;
      if (volumeRatio >= 1.5) baseScore += 0.2;
    } else if (macd < 0) {
      baseScore = -1.0;
      if (volumeRatio >= 1.5) baseScore -= 0.2;
    } else {
      baseScore = -0.5;
      if (volumeRatio >= 2) baseScore -= 0.3;
    }
    
    // 추세 강도 및 시간가중치 적용
    const finalScore = baseScore * trendWeight * timeWeight;
    
    return Math.max(-1.0, Math.min(1.0, finalScore));
  }
  
  /**
   * 볼린저밴드 동적 점수 계산
   */
  private static calculateBollingerScore(closes: number[], currentPrice: number, volumes: number[], atr: number, timeWeight: number): number {
    if (closes.length < 20) return 0;
    
    const sma20 = this.calculateMA(closes, 20);
    const stdDev = this.calculateStdDev(closes.slice(-20));
    const upperBand = sma20 + (2 * stdDev);
    const lowerBand = sma20 - (2 * stdDev);
    
    const bandPosition = (currentPrice - lowerBand) / (upperBand - lowerBand);
    const avgATR = atr;
    
    const currentVolume = volumes[volumes.length - 1] || 0;
    const avgVolume = volumes.slice(-20).reduce((a, b) => a + b, 0) / 20;
    const volumeRatio = avgVolume > 0 ? currentVolume / avgVolume : 1;
    
    // 변동성에 따른 가중치 (ATR≥평균×1.5: 1.3배, ATR<평균×1.5: 1.0배)
    const volatilityWeight = avgATR >= 1.5 ? 1.3 : 1.0;
    
    let baseScore = 0;
    
    // 밴드 위치에 따른 점수
    if (bandPosition <= 0.05) { // 하단터치
      baseScore = 1.0;
      if (volumeRatio >= 2) baseScore += 0.3;
    } else if (bandPosition <= 0.15) { // 하단근접
      baseScore = 0.6;
      if (volumeRatio >= 1.5) baseScore += 0.2;
    } else if (bandPosition >= 0.95) { // 상단터치
      baseScore = -1.0;
      if (volumeRatio >= 1.5) baseScore -= 0.2;
    } else if (bandPosition >= 0.85) { // 상단근접
      baseScore = -0.6;
      if (volumeRatio >= 1.5) baseScore -= 0.2;
    }
    
    // 변동성 및 시간가중치 적용
    const finalScore = baseScore * volatilityWeight * timeWeight;
    
    return Math.max(-1.0, Math.min(1.0, finalScore));
  }
  
  /**
   * 이동평균선 동적 점수 계산
   */
  private static calculateMovingAverageScore(ma5: number, ma20: number, ma60: number, volumes: number[], adx: number, timeWeight: number): number {
    if (volumes.length < 20) return 0;
    
    const currentVolume = volumes[volumes.length - 1] || 0;
    const avgVolume = volumes.slice(-20).reduce((a, b) => a + b, 0) / 20;
    const volumeRatio = avgVolume > 0 ? currentVolume / avgVolume : 1;
    
    // 시장환경에 따른 가중치 (ADX≥25: 1.4배, ADX<25: 1.0배)
    const marketWeight = adx >= 25 ? 1.4 : 1.0;
    
    let baseScore = 0;
    
    // 이동평균선 배열 상태 판단
    if (ma5 > ma20 && ma20 > ma60) { // 완전정배열
      baseScore = 1.0;
      if (volumeRatio >= 2) baseScore += 0.3;
    } else if (ma5 > ma20) { // 부분정배열
      baseScore = 0.6;
      if (volumeRatio >= 1.5) baseScore += 0.2;
    } else if (ma5 < ma20) { // 부분역배열
      baseScore = -0.6;
      if (volumeRatio >= 1.5) baseScore -= 0.2;
    } else if (ma5 < ma20 && ma20 < ma60) { // 완전역배열
      baseScore = -1.0;
      if (volumeRatio >= 2) baseScore -= 0.3;
    }
    
    // 시장환경 및 시간가중치 적용
    const finalScore = baseScore * marketWeight * timeWeight;
    
    return Math.max(-1.0, Math.min(1.0, finalScore));
  }
  
  /**
   * VWAP 동적 점수 계산
   */
  private static calculateVWAPScore(chartData: any[], currentPrice: number, volumes: number[], atr: number, timeWeight: number): number {
    if (chartData.length < 20) return 0;
    
    const vwap = this.calculateVWAP(chartData);
    const vwapPosition = vwap > 0 ? (currentPrice - vwap) / vwap : 0;
    
    const currentVolume = volumes[volumes.length - 1] || 0;
    const avgVolume = volumes.slice(-20).reduce((a, b) => a + b, 0) / 20;
    const volumeRatio = avgVolume > 0 ? currentVolume / avgVolume : 1;
    
    // 거래량에 따른 가중치 (거래량≥평균×2: 1.4배, 거래량<평균×2: 1.0배)
    const volumeWeight = volumeRatio >= 2 ? 1.4 : 1.0;
    
    let baseScore = 0;
    
    // VWAP 대비 위치에 따른 점수
    if (vwapPosition >= 0.02) { // VWAP 상단 (+2% 이상)
      baseScore = 1.0;
    } else if (vwapPosition >= -0.01 && vwapPosition <= 0.01) { // VWAP 근접 (±1%)
      baseScore = 0.6;
    } else if (vwapPosition <= -0.02) { // VWAP 하단 (-2% 이하)
      baseScore = -1.0;
    } else { // VWAP 중간 (±1-2%)
      baseScore = -0.6;
    }
    
    // ATR 변동성 보정
    let volatilityBonus = 0;
    if (atr >= 2) volatilityBonus = 0.2;
    else if (atr >= 1.5) volatilityBonus = 0.1;
    else if (atr < 0.8) volatilityBonus = -0.1;
    
    // 거래량 및 시간가중치 적용
    const finalScore = (baseScore + volatilityBonus) * volumeWeight * timeWeight;
    
    return Math.max(-1.0, Math.min(1.0, finalScore));
  }
  
  /**
   * ADX 동적 점수 계산
   */
  private static calculateADXScore(adx: number, volumes: number[], atr: number, timeWeight: number): number {
    if (volumes.length < 20) return 0;
    
    const currentVolume = volumes[volumes.length - 1] || 0;
    const avgVolume = volumes.slice(-20).reduce((a, b) => a + b, 0) / 20;
    const volumeRatio = avgVolume > 0 ? currentVolume / avgVolume : 1;
    
    // 거래량에 따른 가중치 (거래량≥평균×2: 1.4배, 거래량<평균×2: 1.0배)
    const volumeWeight = volumeRatio >= 2 ? 1.4 : 1.0;
    
    let baseScore = 0;
    
    // ADX 값에 따른 점수
    if (adx >= 25) {
      baseScore = 1.0;
    } else if (adx >= 20) {
      baseScore = 0.8;
    } else if (adx < 20) {
      baseScore = -0.3;
    } else if (adx < 15) {
      baseScore = -0.8;
    }
    
    // ATR 변동성 보정
    let volatilityBonus = 0;
    if (atr < 0.8) volatilityBonus = 0.2;
    else if (atr < 0.5) volatilityBonus = 0.3;
    else if (atr >= 1.5) volatilityBonus = -0.1;
    else if (atr >= 2) volatilityBonus = -0.2;
    
    // 거래량 및 시간가중치 적용
    const finalScore = (baseScore + volatilityBonus) * volumeWeight * timeWeight;
    
    return Math.max(-1.0, Math.min(1.0, finalScore));
  }
  
  /**
   * ATR (Average True Range) 계산
   */
  private static calculateATR(chartData: any[]): number {
    if (chartData.length < 14) return 0;
    
    const recentData = chartData.slice(-14);
    let totalRange = 0;
    
    for (let i = 1; i < recentData.length; i++) {
      const high = recentData[i].high;
      const low = recentData[i].low;
      const prevClose = recentData[i-1].close;
      
      const tr = Math.max(high - low, Math.abs(high - prevClose), Math.abs(low - prevClose));
      totalRange += tr;
    }
    
    return totalRange / 14;
  }
  
  private static getDefaultAnalysis() {
    return {
      comprehensiveScore: 0.0,
      individualScores: { 
        volume: 0,
        rsi: 0, 
        macd: 0, 
        bollinger: 0, 
        movingAverage: 0, 
        vwap: 0, 
        adx: 0 
      },
      indicators: { 
        rsi: 50, 
        macd: 0, 
        bollinger: 0.5, 
        ma5: 0, 
        ma20: 0, 
        ma60: 0, 
        volumeRatio: 1, 
        vwap: 0, 
        adx: 0 
      },
      signal: 'HOLD',
      lastUpdated: new Date()
    };
  }

  /**
   * 현재가 데이터 저장
   */
  private static async saveCurrentPriceData(symbol: string, currentPriceData: any, uid: string) {
    try {
      const db = admin.firestore();
      const stockRef = db.collection('stocks').doc(symbol);
      
      await stockRef.update({
        current: currentPriceData,
        'metadata.lastUpdated': new Date(),
        'metadata.currentPriceUpdated': new Date()
      });
      
      console.log(`✅ 현재가 데이터 저장 완료: ${symbol}`);
    } catch (error) {
      console.error(`❌ 현재가 데이터 저장 실패: ${symbol}`, error);
    }
  }

  /**
   * 분석 데이터 저장
   */
  private static async saveAnalysisData(symbol: string, analysis: any, uid: string) {
    try {
      const db = admin.firestore();
      const stockRef = db.collection('stocks').doc(symbol);
      
      await stockRef.update({
        analysis: analysis,
        'metadata.lastUpdated': new Date(),
        'metadata.analysisUpdated': new Date()
      });
      
      console.log(`✅ 분석 데이터 저장 완료: ${symbol}`);
    } catch (error) {
      console.error(`❌ 분석 데이터 저장 실패: ${symbol}`, error);
    }
  }

  /**
   * 기본 차트 데이터 생성 (100일)
   */
  private static generateDefaultChartData(symbol: string, days: number): any[] {
    const chartData = [];
    const basePrice = 100; // 기본 가격
    const today = new Date();
    
    for (let i = days - 1; i >= 0; i--) {
      const date = new Date(today);
      date.setDate(date.getDate() - i);
      
      const dateStr = `${date.getFullYear()}${(date.getMonth() + 1).toString().padStart(2, '0')}${date.getDate().toString().padStart(2, '0')}`;
      
      // 랜덤한 가격 변동 생성
      const randomChange = (Math.random() - 0.5) * 0.1; // ±5% 변동
      const price = basePrice * (1 + randomChange);
      
      const open = price * (1 + (Math.random() - 0.5) * 0.02);
      const high = Math.max(open, price) * (1 + Math.random() * 0.01);
      const low = Math.min(open, price) * (1 - Math.random() * 0.01);
      const close = price;
      const volume = Math.floor(Math.random() * 1000000) + 100000;
      
      chartData.push({
        date: dateStr,
        open: Math.round(open * 100) / 100,
        high: Math.round(high * 100) / 100,
        low: Math.round(low * 100) / 100,
        close: Math.round(close * 100) / 100,
        volume: volume,
        trade_amount: volume * close
      });
    }
    
    return chartData;
  }

  /**
   * 차트 데이터 생성 및 분석
   * @param symbol 종목코드
   * @param market 시장
   * @param bars 차트 데이터
   * @returns 생성된 차트 데이터
   */
  async ensureChartAndAnalyze(symbol: string, market: string, bars: any[]) {
    try {
      console.log(`📊 차트 데이터 생성 및 분석 시작: ${symbol} (market: ${market})`);
      
      const db = admin.firestore();
      
      // 차트 데이터 저장
      if (bars && bars.length > 0) {
        const batch = db.batch();
        
        for (const bar of bars) {
          const date = bar.date || new Date().toISOString().split('T')[0];
          const docRef = db.collection('charts').doc(symbol).collection('daily').doc(date);
          
          batch.set(docRef, {
            stock_code: symbol,
            market: market,
            date: date,
            date_ts: parseInt(date.replaceAll('-', '')),
            open: bar.open || 0,
            high: bar.high || 0,
            low: bar.low || 0,
            close: bar.close || 0,
            volume: bar.volume || 0,
            trade_amount: bar.trade_amount || 0,
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
        }
        
        await batch.commit();
        console.log(`✅ 차트 데이터 저장 완료: ${symbol} (${bars.length}개)`);
      }
      
      return {
        success: true,
        symbol,
        market,
        dataCount: bars?.length || 0
      };
    } catch (error) {
      console.error('❌ 차트 데이터 생성 및 분석 실패:', error);
      throw error;
    }
  }
}
