// import * as functions from 'firebase-functions'; // 사용하지 않음
import * as admin from 'firebase-admin';
import { KISProxy } from './data/kis_proxy';

// Firebase Admin SDK 초기화 (이중 보장)
if (!admin.apps.length) {
  admin.initializeApp();
}

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
      const chartData = await this.ensureChartData(symbol, uid);
      
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
      let currentPriceData = await KISProxy.fetchCurrentPrice(symbol, uid);
      
      // 가격 데이터 스케일 정규화 (국내주식 100에 가까운 값 방어)
      if (currentPriceData) {
        currentPriceData = this.normalizePriceScale(symbol, currentPriceData);
      }
      
      // 폴백: KIS 실패 시 최근 차트에서 현재가 복구
      if (!currentPriceData) {
        console.log(`⚠️ KIS 현재가 조회 실패 또는 데이터 없음 → 차트 기반 폴백 시도: ${symbol}`);
        currentPriceData = await this.getFallbackCurrentPriceFromChart(symbol);
        if (currentPriceData) {
          currentPriceData = this.normalizePriceScale(symbol, currentPriceData);
        }
      }

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
      // 최후 폴백: 오류 상황에서도 차트 기반 복구 시도
      try {
        const currentPriceData = await this.getFallbackCurrentPriceFromChart(symbol);
        if (currentPriceData) {
          await this.saveCurrentPriceData(symbol, currentPriceData, uid);
          return { success: true, hasData: true, data: currentPriceData };
        }
      } catch (_) {}
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
      const chartData = await this.ensureChartData(symbol, uid);
      console.log(`📊 1단계 완료: 차트 데이터 ${chartData.length}개 생성 - ${symbol}`);
      
      // 1-1. 종목 기본 정보 조회 및 저장 (문서 보강)
      try {
        const stockInfo = await this.getStockInfo(symbol);
        const db = admin.firestore();
        await db.collection('stocks').doc(symbol).set({
          symbol,
          info: stockInfo,
          // ✅ current 필드 제거 (null로 덮어쓰지 않음)
          metadata: {
            lastUpdated: new Date(),
            infoUpdated: new Date(),
          }
        }, { merge: true });
        console.log(`✅ 종목 기본 정보 저장 완료: ${symbol}`);
      } catch (e) {
        console.log(`⚠️ 종목 기본 정보 저장 실패(무시): ${symbol}`, e);
      }
      
      // 2. 현재가 데이터 조회
      console.log(`📊 2단계: 현재가 데이터 조회 시작 - ${symbol}`);
      let currentPrice = await this.getCurrentPrice(symbol, uid);
      console.log(`📊 2단계 완료: 현재가 데이터 조회 - ${symbol}`);

      // 2-1. current.volume을 차트 최신 캔들의 volume로 보강(SSOT)
      try {
        const latestCandle = chartData.length > 0 ? chartData[chartData.length - 1] : null;
        const latestVolume = latestCandle && latestCandle.volume ? Number(latestCandle.volume) : null;
        if (latestVolume && latestVolume > 0) {
          if (!currentPrice) currentPrice = {} as any;
          (currentPrice as any).volume = latestVolume;
          console.log(`📊 current.volume 보강: ${symbol} → ${latestVolume}`);
        }
      } catch (e) {
        console.log(`⚠️ current.volume 보강 스킵: ${symbol}`, e);
      }
      // 현재가 저장 (있을 때만)
      if (currentPrice) {
        await this.saveCurrentPriceData(symbol, currentPrice, uid);
      } else {
        console.log(`⚠️ 현재가 없음: ${symbol} (저장 스킵)`);
        // ✅ current 필드가 null이 되지 않도록 기존 데이터 유지
        try {
          const db = admin.firestore();
          const stockRef = db.collection('stocks').doc(symbol);
          
          // 🔍 기존 current 필드가 있는지 확인
          const existingDoc = await stockRef.get();
          const existingCurrent = existingDoc.data()?.current;
          
          if (existingCurrent && existingCurrent.currentPrice && existingCurrent.currentPrice > 0) {
            console.log(`🔍 [current 보호] 기존 current 필드 유지: ${symbol} - ${existingCurrent.currentPrice}`);
            // 기존 current 필드는 그대로 두고 metadata만 업데이트
            await stockRef.update({
              metadata: {
                lastUpdated: new Date(),
                currentPriceUpdated: new Date(),
                currentPriceStatus: 'unavailable'
              }
            });
          } else {
            console.log(`⚠️ [current 보호] 기존 current 필드도 없음: ${symbol} - metadata만 업데이트`);
            await stockRef.update({
              metadata: {
                lastUpdated: new Date(),
                currentPriceUpdated: new Date(),
                currentPriceStatus: 'unavailable'
              }
            });
          }
        } catch (e) {
          console.log(`⚠️ current 필드 업데이트 실패: ${symbol}`, e);
        }
      }
      
      // 3. 분석 데이터 계산
      console.log(`📊 3단계: 분석 데이터 계산 시작 - ${symbol}`);
      const analysis = await this.calculateAnalysis(symbol, chartData, currentPrice, uid);
      // analysis.technicalData.currentVolume도 최신으로 보강
      try {
        // ✅ 최신 데이터 사용 (차트 데이터의 첫 번째 요소가 최신)
        const latestCandle = chartData.length > 0 ? chartData[0] : null;
        const latestVolume = latestCandle && latestCandle.volume ? Number(latestCandle.volume) : null;
        if (latestVolume && latestVolume > 0) {
          (analysis as any).technicalData = (analysis as any).technicalData || {};
          (analysis as any).technicalData.currentVolume = latestVolume;
          console.log(`✅ [분석] currentVolume 보강: ${symbol} - ${latestVolume}주 (최신 데이터)`);
        }
      } catch (e) {
        console.log(`⚠️ analysis.currentVolume 보강 스킵: ${symbol}`, e);
      }
      console.log(`📊 3단계 완료: 분석 데이터 계산 - ${symbol}`);
      
      // 4. 결과 저장
      console.log(`📊 4단계: 분석 데이터 저장 시작 - ${symbol}`);
      await this.saveAnalysisData(symbol, analysis, uid);
      console.log(`📊 4단계 완료: 분석 데이터 저장 - ${symbol}`);
      
      console.log(`✅ 차트 데이터 생성 및 분석 완료: ${symbol}`);
      // 응답 크기 최소화 (Firebase Functions는 10MB 제한)
      return {
        success: true,
        data: {
          symbol,
          chartDataCount: chartData.length,
          hasCurrentPrice: !!currentPrice,
          hasAnalysis: !!analysis,
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
  static async ensureChartData(symbol: string, uid?: string) {
    try {
      console.log(`📈 차트 데이터 조회 시작: ${symbol}`);
      const db = admin.firestore();
      // 1) 기존 저장 데이터 확인 (실제 API 데이터만 사용) - 최신 데이터 우선
      const existingSnap = await db
        .collection('stocks').doc(symbol)
        .collection('chart')
        .orderBy('date_ts', 'desc' as any) // ✅ 내림차순으로 변경 (최신 데이터 우선)
        .limit(100)
        .get();
      
      if (!existingSnap.empty) {
        const rows = existingSnap.docs.map(d => d.data());
        console.log(`✅ 기존 차트 데이터 사용: ${symbol} (${rows.length}개)`);
        return rows as any[];
      }

      // 2) KIS API 시도
      console.log(`🔄 KIS 일봉 조회 시도: ${symbol}`);
      const kisBars = await KISProxy.fetchDailyChart(symbol, 100, uid);
      if (kisBars && kisBars.length > 0) {
        console.log(`✅ KIS 일봉 수신: ${symbol} (${kisBars.length}개)`);
        // ✅ 최신 데이터 우선으로 정렬 (date_ts 내림차순)
        const sortedBars = kisBars.sort((a: any, b: any) => (b.date_ts || 0) - (a.date_ts || 0));
        await this.saveChartData(symbol, sortedBars);
        return sortedBars;
      }

      // 3) 최후 폴백: 데이터 없음 (가짜 데이터 생성 완전 금지)
      console.log(`⚠️ KIS API 실패: ${symbol} - 데이터 없음`);
      return [];
      
    } catch (error) {
      console.error(`❌ 차트 데이터 조회 실패: ${symbol}`, error);
      return [];
    }
  }
  
  /**
   * 현재가 데이터 조회/업데이트
   */
  static async getCurrentPrice(symbol: string, uid?: string) {
    try {
      console.log(`💰 현재가 데이터 조회: ${symbol}`);
      
      // 1. KIS API에서 현재가 조회 (실제 데이터만)
      const priceData = await KISProxy.fetchCurrentPrice(symbol, uid);
      
      if (priceData) {
        // KISProxy 응답 필드명을 올바르게 매핑
        const currentPrice = priceData.current_price || 0;
        const open = priceData.open_price || 0;
        const high = priceData.high_price || 0;
        const low = priceData.low_price || 0;
        const volume = priceData.volume || 0;
        
        // ✅ prevClose를 차트 데이터에서 직접 계산 (KIS API prev_close 필드 신뢰하지 않음)
        let prevClose = priceData.prev_close || 0;
        try {
          const db = admin.firestore();
          
          // 1. chart 컬렉션에서 조회
          const chartSnap = await db.collection('stocks').doc(symbol).collection('chart')
            .orderBy('date_ts', 'desc' as any)
            .limit(2)
            .get();
          
          if (chartSnap.docs.length >= 2) {
            prevClose = Number(chartSnap.docs[1].data().close) || prevClose;
            console.log(`✅ [현재가] prevClose 차트 컬렉션에서 계산: ${symbol} - ${prevClose}`);
          } else {
            // 2. chart 필드에서 조회 (차트 데이터가 chart 컬렉션이 아닌 chart 필드에 있는 경우)
            const stockDoc = await db.collection('stocks').doc(symbol).get();
            if (stockDoc.exists) {
              const chartData = stockDoc.data()?.chart;
              if (Array.isArray(chartData) && chartData.length >= 2) {
                prevClose = Number(chartData[1].close) || prevClose;
                console.log(`✅ [현재가] prevClose chart 필드에서 계산: ${symbol} - ${prevClose}`);
              }
            }
          }
        } catch (e) {
          console.log(`⚠️ [현재가] prevClose 차트 데이터 조회 실패: ${symbol} - ${e}`);
        }
        
        // change와 changeRate 계산
        const change = currentPrice - prevClose;
        const changeRate = prevClose !== 0 ? ((currentPrice - prevClose) / prevClose) * 100 : 0;
        
        // tradeAmount 계산 (거래대금 = 현재가 × 거래량)
        const tradeAmount = currentPrice * volume;
        
        console.log(`✅ 현재가 조회 성공: ${symbol} - ${currentPrice}`);
        console.log(`🔍 [현재가] 계산된 값들: prevClose=${prevClose}, change=${change}, changeRate=${changeRate}, tradeAmount=${tradeAmount}`);
        
        return {
          currentPrice,
          prevClose,
          change,
          changeRate,
          open,
          high,
          low,
          volume,
          tradeAmount,
          timestamp: new Date()
        };
      } else {
        console.log(`⚠️ KIS API 현재가 조회 실패: ${symbol} - 차트 데이터에서 복구 시도`);
        // 차트 데이터에서 현재가 복구 시도
        const fallbackData = await this.getFallbackCurrentPriceFromChart(symbol);
        if (fallbackData) {
          console.log(`✅ 차트 데이터에서 현재가 복구 성공: ${symbol}`);
          return fallbackData;
        }
        return null;
      }
      
    } catch (error) {
      console.error(`❌ 현재가 조회 실패: ${symbol}`, error);
      // 오류 시에도 차트 데이터에서 복구 시도
      try {
        const fallbackData = await this.getFallbackCurrentPriceFromChart(symbol);
        if (fallbackData) {
          console.log(`✅ 오류 후 차트 데이터에서 현재가 복구 성공: ${symbol}`);
          return fallbackData;
        }
      } catch (fallbackError) {
        console.error(`❌ 차트 데이터 복구도 실패: ${symbol}`, fallbackError);
      }
      return null;
    }
  }

  /**
   * Firestore 최신 차트 1개로 현재가 정보를 복구
   */
  private static async getFallbackCurrentPriceFromChart(symbol: string): Promise<any | null> {
    try {
      const db = admin.firestore();
      const snap = await db.collection('stocks').doc(symbol).collection('chart')
        .orderBy('date_ts', 'desc' as any) // TS 타입 회피
        .limit(1)
        .get();
      if (snap.empty) {
        console.log(`⚠️ 차트 폴백 실패: 최신 데이터 없음 - ${symbol}`);
        return null;
      }
      const d = snap.docs[0].data() as any;
      const currentPrice = Number(d.close ?? d.open ?? 0) || 0;
      let prevClose = currentPrice;
      try {
        const prevSnap = await db.collection('stocks').doc(symbol).collection('chart')
          .orderBy('date_ts', 'desc' as any)
          .limit(2)
          .get();
        if (prevSnap.docs.length >= 2) {
          prevClose = Number(prevSnap.docs[1].data().close ?? currentPrice) || currentPrice;
        }
      } catch (_) {}
      const result = {
        currentPrice,
        prevClose,
        change: currentPrice - prevClose,
        changeRate: prevClose !== 0 ? ((currentPrice - prevClose) / prevClose) * 100 : 0,
        open: Number(d.open ?? currentPrice) || currentPrice,
        high: Number(d.high ?? currentPrice) || currentPrice,
        low: Number(d.low ?? currentPrice) || currentPrice,
        volume: Number(d.volume ?? 0) || 0, // ✅ 차트 데이터의 거래량 사용 (최신 데이터)
        tradeAmount: currentPrice * volume, // 거래대금 = 현재가 × 거래량
        timestamp: new Date()
      };
      console.log(`✅ 차트 기반 현재가 폴백 성공: ${symbol} - ${result.currentPrice}`);
      return result;
    } catch (e) {
      console.error(`❌ 차트 기반 현재가 폴백 실패: ${symbol}`, e);
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
      
      // 1. 기본 데이터 추출 (차트 데이터 순서 확인)
      // chartData[0]이 최신 데이터인지 확인
      console.log(`🔍 [RSI 디버그] 차트 데이터 순서 확인: ${symbol}`);
      console.log(`🔍 [RSI 디버그] chartData[0] 날짜: ${chartData[0]?.date || 'N/A'}`);
      console.log(`🔍 [RSI 디버그] chartData[1] 날짜: ${chartData[1]?.date || 'N/A'}`);
      console.log(`🔍 [RSI 디버그] chartData[2] 날짜: ${chartData[2]?.date || 'N/A'}`);
      
      const closes = chartData.map(c => c.close).filter(c => c > 0);
      const volumes = chartData.map(c => c.volume).filter(v => v > 0);
      // const highs = chartData.map(c => c.high).filter(h => h > 0);
      // const lows = chartData.map(c => c.low).filter(l => l > 0);
      
      // 2. 현재 시간대 및 시장 환경 분석
      const currentTime = new Date();
      const timeWeight = this.getTimeWeight(currentTime);
      const currentPriceValue = currentPrice?.currentPrice || closes[0];
      // const priceChange = currentPrice?.change || 0;
      const priceChangeRate = currentPrice?.changeRate || 0;
      
      // 3. 기본 지표 계산
      const rsi = this.calculateRSI(closes);
      const ma5 = this.calculateMA(closes, 5);
      const ma20 = this.calculateMA(closes, 20);
      const ma60 = this.calculateMA(closes, 60);
      const macdData = this.calculateMACD(closes);
      const macd = macdData.macd;
      const adx = this.calculateADX(chartData);
      const atr = this.calculateATR(chartData);
      
      // 4. 거래량 분석 (동적 점수 환산표)
      const volumeScore = this.calculateVolumeScore(volumes, currentPriceValue, closes[1] || currentPriceValue, timeWeight);
      
      // 5. RSI 분석 (동적 점수 환산표)
      const rsiScore = this.calculateRSIScore(rsi, volumes, atr, timeWeight);
      
      // 6. MACD 분석 (동적 점수 환산표)
      const macdScore = this.calculateMACDScore(macdData.histogram, volumes, adx, timeWeight);
      
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
      
      // 기술적 지표 실제값 계산
      const bbData = this.calculateBollinger(closes, currentPriceValue);
      const vwapValue = this.calculateVWAP(chartData);
      // ✅ 최신 거래량 사용 (차트 데이터의 첫 번째 요소가 최신)
      const currentVolume = volumes[0] || 0; // 첫 번째 요소가 최신 데이터
      const avgVolume = volumes.slice(0, 20).reduce((a, b) => a + b, 0) / 20; // 최신 20일 평균
      // prevClose: 전일 종가 (차트 데이터에서 두 번째 데이터, 1번째 인덱스)
      let prevClose = currentPriceValue;
      if (closes.length >= 2) {
        prevClose = closes[1]; // 두 번째 데이터 (어제 종가)
        console.log(`📊 [분석] prevClose 계산: ${symbol} - 어제: ${prevClose}, 오늘: ${currentPriceValue}`);
      } else if (closes.length >= 1) {
        // 차트 데이터가 1개만 있으면 현재가를 사용 (fallback)
        prevClose = currentPriceValue;
        console.log(`⚠️ [분석] prevClose 계산: ${symbol} - 차트 데이터 1개만 있음, 현재가 사용: ${prevClose}`);
      } else {
        // 차트 데이터가 없으면 현재가를 사용 (fallback)
        prevClose = currentPriceValue;
        console.log(`⚠️ [분석] prevClose 계산: ${symbol} - 차트 데이터 없음, 현재가 사용: ${prevClose}`);
      }
      // openPrice: 시가 (차트 데이터에서 첫 번째 데이터의 open 값)
      const openPrice = currentPrice?.open || (chartData.length > 0 ? chartData[0].open : currentPriceValue) || currentPriceValue;
      
      const analysis = {
        comprehensiveScore: Math.round(comprehensiveScore * 1000) / 1000,
        individualScores: scores,
        indicators: {
          rsi: Math.round(rsi * 100) / 100,
          macd: Math.round(macd * 100) / 100,
          bollinger: Math.round(bbData.position * 100) / 100,
          ma5: Math.round(ma5 * 100) / 100,
          ma20: Math.round(ma20 * 100) / 100,
          ma60: Math.round(ma60 * 100) / 100,
          volumeRatio: Math.round((volumes[0] || 0) / (volumes.slice(0, 20).reduce((a, b) => a + b, 0) / 20) * 100) / 100, // ✅ 최신 데이터 사용
          vwap: Math.round(vwapValue * 100) / 100,
          adx: Math.round(adx * 100) / 100
        },
        // 클라이언트에서 사용할 실제값 데이터
        technicalData: {
          rsi: Math.round(rsi * 100) / 100,
          macd: Math.round(macdData.macd * 100) / 100,
          signal: Math.round(macdData.signal * 100) / 100, // ✅ MACD 신호선 (9일 EMA)
          histogram: Math.round(macdData.histogram * 100) / 100, // ✅ MACD 히스토그램
          bbUpper: Math.round(bbData.upper * 100) / 100,
          bbMiddle: Math.round(bbData.middle * 100) / 100,
          bbLower: Math.round(bbData.lower * 100) / 100,
          ma5: Math.round(ma5 * 100) / 100,
          ma20: Math.round(ma20 * 100) / 100,
          ma60: Math.round(ma60 * 100) / 100,
          vwap: Math.round(vwapValue * 100) / 100,
          adx: Math.round(adx * 100) / 100,
          currentVolume: currentVolume,
          avgVolume: Math.round(avgVolume),
          currentPrice: Math.round(currentPriceValue * 100) / 100,
          openPrice: Math.round(openPrice * 100) / 100,
          prevClose: Math.round(prevClose * 100) / 100
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
      
      // chart 데이터를 리스트로 저장 (전체 차트 데이터)
      const chartDataList = data.chartData && data.chartData.length > 0 ? data.chartData : [];
      
      // 🔍 current 필드 보호: null이면 기존 데이터 유지
      const updateData: any = {
        info: data.stockInfo,
        chart: chartDataList, // ✅ 전체 차트 데이터를 리스트로 저장
        analysis: data.analysis,
        metadata: {
          lastUpdated: data.lastUpdated,
          version: '2.0',
          dataCount: data.chartData.length
        }
      };
      
      // current 필드는 유효한 경우에만 업데이트
      if (data.currentPrice && data.currentPrice.currentPrice && data.currentPrice.currentPrice > 0) {
        updateData.current = data.currentPrice;
        console.log(`✅ [saveIntegratedData] current 필드 업데이트: ${symbol} - ${data.currentPrice.currentPrice}`);
      } else {
        console.log(`🔍 [saveIntegratedData] current 필드 보호: ${symbol} - 기존 데이터 유지`);
      }
      
      await stockRef.set(updateData, { merge: true });
      
      console.log(`✅ 통합 데이터 저장 완료: ${symbol} (차트 데이터 ${chartDataList.length}개)`);
      
    } catch (error) {
      console.error(`❌ 통합 데이터 저장 실패: ${symbol}`, error);
    }
  }
  
  /**
   * 차트 데이터 저장
   */
  private static async saveChartData(symbol: string, chartData: any[]) {
    try {
      // 빈 차트 데이터는 저장하지 않음 (기존 데이터 보호)
      if (!chartData || chartData.length === 0) {
        console.log(`⚠️ 차트 데이터 비어있음 (저장 건너뜀): ${symbol}`);
        return;
      }
      
      // 유효한 데이터만 필터링 (date와 숫자형 가격 필수)
      const validData = chartData.filter(data => {
        if (!data || !data.date) return false;
        const close = Number(data.close ?? data.clos ?? 0);
        const open = Number(data.open ?? 0);
        const high = Number(data.high ?? 0);
        const low = Number(data.low ?? 0);
        return isFinite(close) && isFinite(open) && isFinite(high) && isFinite(low);
      });
      
      if (validData.length === 0) {
        console.log(`⚠️ 유효한 차트 데이터 없음 (저장 건너뜀): ${symbol}`);
        return;
      }
      
      const db = admin.firestore();
      const batch = db.batch();
      
      for (const data of validData) {
        const docRef = db.collection('stocks').doc(symbol).collection('chart').doc(data.date);
        batch.set(docRef, {
          date: data.date,
          date_ts: parseInt(data.date),
          open: Number(data.open ?? 0),
          high: Number(data.high ?? 0),
          low: Number(data.low ?? 0),
          close: Number(data.close ?? data.clos ?? 0),
          volume: Number(data.volume ?? data.tvol ?? 0),
          trade_amount: (data.current_price || 0) * (data.volume || 0), // 거래대금 = 현재가 × 거래량
          stock_code: symbol,
          market: this.getMarketFromSymbol(symbol),
          updated_at: new Date()
        });
      }
      
      await batch.commit();
      console.log(`✅ 차트 데이터 저장 완료: ${symbol} (${validData.length}/${chartData.length}개)`);
      
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
    // 5-6자리 숫자는 국내주식 (KOSPI/KOSDAQ)
    if (/^\d{5,6}$/.test(symbol)) {
      return 'KOSPI';
    } else {
      return 'NASDAQ';
    }
  }

  /**
   * 가격 데이터 스케일 정규화
   * 국내주식이 해외주식 스케일(100에 가까운 값)로 잘못 저장되는 것을 방지
   */
  private static normalizePriceScale(symbol: string, priceData: any): any {
    try {
      const isDomestic = /^\d{5,6}$/.test(symbol);
      
      if (!isDomestic) {
        // 해외주식은 그대로 반환
        return priceData;
      }

      // 국내주식 스케일 검증 및 수정
      const currentPrice = Number(priceData.current_price) || 0;
      const openPrice = Number(priceData.open_price) || 0;
      const prevClose = Number(priceData.prev_close) || 0;
      const highPrice = Number(priceData.high_price) || 0;
      const lowPrice = Number(priceData.low_price) || 0;

      // 100에 가까운 값이면 100배로 스케일 조정 (달러 → 원)
      const scaleFactor = this.determineScaleFactor(currentPrice, openPrice, prevClose, highPrice, lowPrice);
      
      if (scaleFactor > 1) {
        console.log(`🔧 [가격 스케일 정규화] ${symbol}: ${scaleFactor}배 스케일 조정 적용`);
        
        return {
          ...priceData,
          current_price: Math.round(currentPrice * scaleFactor),
          open_price: Math.round(openPrice * scaleFactor),
          prev_close: Math.round(prevClose * scaleFactor),
          high_price: Math.round(highPrice * scaleFactor),
          low_price: Math.round(lowPrice * scaleFactor),
          normalized: true,
          scale_factor: scaleFactor
        };
      }

      return priceData;
    } catch (error) {
      console.error(`❌ 가격 스케일 정규화 실패: ${symbol}`, error);
      return priceData;
    }
  }

  /**
   * 스케일 팩터 결정 (100에 가까운 값 감지)
   */
  private static determineScaleFactor(...prices: number[]): number {
    const validPrices = prices.filter(p => p > 0);
    if (validPrices.length === 0) return 1;

    const avgPrice = validPrices.reduce((sum, p) => sum + p, 0) / validPrices.length;
    
    // 평균 가격이 50-200 범위면 100배 스케일 조정 필요
    if (avgPrice >= 50 && avgPrice <= 200) {
      return 100;
    }
    
    // 평균 가격이 5-20 범위면 1000배 스케일 조정 필요 (센트 단위)
    if (avgPrice >= 5 && avgPrice <= 20) {
      return 1000;
    }

    return 1;
  }
  
  private static calculateRSI(prices: number[]): number {
    if (prices.length < 15) return 50; // 최소 15개 데이터 필요 (14일 + 1일)
    
    // ✅ TradingView 표준 RSI 계산 방식 (완전 수정)
    // 데이터를 과거부터 현재까지 순서로 정렬 (최신이 0번째이므로 뒤집기)
    const sortedPrices = [...prices].reverse();
    
    // 🔍 RSI 디버그 로그 - 데이터 순서 확인
    console.log(`🔍 [RSI 디버그] prices[0-4]: ${prices.slice(0, 5).join(', ')}`);
    console.log(`🔍 [RSI 디버그] sortedPrices[0-4]: ${sortedPrices.slice(0, 5).join(', ')}`);
    console.log(`🔍 [RSI 디버그] sortedPrices[10-14]: ${sortedPrices.slice(10, 15).join(', ')}`);
    
    // 1. 가격 변화 계산 (오늘 - 어제)
    // sortedPrices[0] = 과거, sortedPrices[1] = 어제, sortedPrices[2] = 오늘
    const changes: number[] = [];
    for (let i = 1; i < sortedPrices.length; i++) {
      changes.push(sortedPrices[i] - sortedPrices[i - 1]); // 오늘 - 어제
    }
    
    console.log(`🔍 [RSI 디버그] changes[0-4]: ${changes.slice(0, 5).join(', ')}`);
    console.log(`🔍 [RSI 디버그] changes[10-14]: ${changes.slice(10, 15).join(', ')}`);
    
    // 2. 상승/하락 분리
    const gains: number[] = changes.map(change => change >= 0 ? change : 0);
    const losses: number[] = changes.map(change => change < 0 ? -change : 0);
    
    console.log(`🔍 [RSI 디버그] gains[0-4]: ${gains.slice(0, 5).join(', ')}`);
    console.log(`🔍 [RSI 디버그] losses[0-4]: ${losses.slice(0, 5).join(', ')}`);
    console.log(`🔍 [RSI 디버그] gains[10-14]: ${gains.slice(10, 15).join(', ')}`);
    console.log(`🔍 [RSI 디버그] losses[10-14]: ${losses.slice(10, 15).join(', ')}`);
    
    // 3. RMA 계산 (Relative Moving Average) - 지수이동평균
    // 첫 번째 RMA는 단순 평균 (최신 14개 데이터 사용)
    const recentGains = gains.slice(-14); // 최신 14개
    const recentLosses = losses.slice(-14); // 최신 14개
    
    let avgGain = recentGains.reduce((sum, gain) => sum + gain, 0) / 14;
    let avgLoss = recentLosses.reduce((sum, loss) => sum + loss, 0) / 14;
    
    console.log(`🔍 [RSI 디버그] recentGains: ${recentGains.join(', ')}`);
    console.log(`🔍 [RSI 디버그] recentLosses: ${recentLosses.join(', ')}`);
    console.log(`🔍 [RSI 디버그] 초기 avgGain: ${avgGain}, avgLoss: ${avgLoss}`);
    
    // 4. RMA 스무딩 (14일 이후) - Wilder's Smoothing
    for (let i = 14; i < gains.length; i++) {
      avgGain = (avgGain * 13 + gains[i]) / 14;
      avgLoss = (avgLoss * 13 + losses[i]) / 14;
    }
    
    console.log(`🔍 [RSI 디버그] 최종 avgGain: ${avgGain}, avgLoss: ${avgLoss}`);
    
    if (avgLoss === 0) return 100;
    
    const rs = avgGain / avgLoss;
    const rsi = 100 - (100 / (1 + rs));
    
    console.log(`🔍 [RSI 디버그] rs: ${rs}, rsi: ${rsi}`);
    
    return rsi;
  }
  
  private static calculateMA(prices: number[], period: number): number {
    if (prices.length < period) return prices[prices.length - 1] || 0;
    
    // ✅ 최신 period개 데이터 사용 (0번째부터 period-1번째까지)
    const slice = prices.slice(0, period);
    return slice.reduce((sum, price) => sum + price, 0) / period;
  }
  
  private static calculateMACD(prices: number[]): { macd: number, signal: number, histogram: number } {
    if (prices.length < 26) return { macd: 0, signal: 0, histogram: 0 };
    
    // ✅ TradingView 표준 MACD 계산 방식 (완전 재작성)
    // 데이터를 과거부터 현재까지 순서로 정렬 (최신이 0번째이므로 뒤집기)
    const sortedPrices = [...prices].reverse();
    
    // 🔍 MACD 디버그 로그 - 데이터 순서 확인
    console.log(`🔍 [MACD 디버그] prices[0-4]: ${prices.slice(0, 5).join(', ')}`);
    console.log(`🔍 [MACD 디버그] sortedPrices[0-4]: ${sortedPrices.slice(0, 5).join(', ')}`);
    
    // 1. 전체 기간에 대한 MACD Line 값들을 순차적으로 계산
    const macdValues: number[] = [];
    for (let i = 25; i < sortedPrices.length; i++) {
      const ema12AtI = this.calculateEMATraditional(sortedPrices.slice(0, i + 1), 12);
      const ema26AtI = this.calculateEMATraditional(sortedPrices.slice(0, i + 1), 26);
      macdValues.push(ema12AtI - ema26AtI);
    }
    
    // 2. 최신 MACD Line (현재값)
    const macdLine = macdValues[macdValues.length - 1] || 0;
    
    // 3. Signal Line = MACD Line의 9일 EMA
    const signalLine = macdValues.length >= 9 ? 
      this.calculateEMATraditional(macdValues, 9) : macdLine;
    
    // 4. MACD Histogram = MACD Line - Signal Line
    const histogram = macdLine - signalLine;
    
    // 🔍 MACD 디버그 로그
    console.log(`🔍 [MACD 디버그] MACD Values 길이: ${macdValues.length}`);
    console.log(`🔍 [MACD 디버그] MACD Values[마지막 5개]: ${macdValues.slice(-5).join(', ')}`);
    console.log(`🔍 [MACD 디버그] MACD Line: ${macdLine}`);
    console.log(`🔍 [MACD 디버그] Signal Line: ${signalLine}`);
    console.log(`🔍 [MACD 디버그] Histogram: ${histogram}`);
    
    return {
      macd: Math.round(macdLine * 1000) / 1000, // 소수점 3자리 반올림
      signal: Math.round(signalLine * 1000) / 1000,
      histogram: Math.round(histogram * 1000) / 1000
    };
  }
  
  private static calculateBollinger(prices: number[], currentPrice: number): { upper: number, middle: number, lower: number, position: number } {
    if (prices.length < 20) return { upper: 0, middle: 0, lower: 0, position: 0 };
    
    const sma20 = this.calculateMA(prices, 20);
    // ✅ 최신 20개 데이터 사용 (0번째부터 19번째까지)
    const stdDev = this.calculateStdDev(prices.slice(0, 20));
    const upperBand = sma20 + (2 * stdDev);
    const lowerBand = sma20 - (2 * stdDev);
    const position = (currentPrice - lowerBand) / (upperBand - lowerBand);
    
    return {
      upper: upperBand,
      middle: sma20,
      lower: lowerBand,
      position: position
    };
  }
  
  private static calculateVWAP(chartData: any[]): number {
    if (chartData.length < 20) return 0;
    
    // ✅ 최신 20개 데이터 사용 (0번째부터 19번째까지)
    const recentData = chartData.slice(0, 20);
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
    if (chartData.length < 15) return 0; // 최소 15개 데이터 필요 (14일 + 1일)
    
    // ✅ TradingView 표준 ADX 계산 방식
    // 1. +DM, -DM, TR 계산
    const dmPlus: number[] = [];
    const dmMinus: number[] = [];
    const tr: number[] = [];
    
    for (let i = 1; i < chartData.length; i++) {
      const current = chartData[i];
      const previous = chartData[i - 1];
      
      const highDiff = current.high - previous.high;
      const lowDiff = previous.low - current.low;
      
      // +DM 계산
      if (highDiff > lowDiff && highDiff > 0) {
        dmPlus.push(highDiff);
      } else {
        dmPlus.push(0);
      }
      
      // -DM 계산
      if (lowDiff > highDiff && lowDiff > 0) {
        dmMinus.push(lowDiff);
      } else {
        dmMinus.push(0);
      }
      
      // TR 계산
      const tr1 = current.high - current.low;
      const tr2 = Math.abs(current.high - previous.close);
      const tr3 = Math.abs(current.low - previous.close);
      tr.push(Math.max(tr1, tr2, tr3));
    }
    
    // 2. 14일 평활화된 +DM, -DM, TR 계산
    let smoothDMPlus = dmPlus.slice(0, 14).reduce((sum, dm) => sum + dm, 0) / 14;
    let smoothDMMinus = dmMinus.slice(0, 14).reduce((sum, dm) => sum + dm, 0) / 14;
    let smoothTR = tr.slice(0, 14).reduce((sum, t) => sum + t, 0) / 14;
    
    // 3. 14일 이후 평활화
    for (let i = 14; i < dmPlus.length; i++) {
      smoothDMPlus = (smoothDMPlus * 13 + dmPlus[i]) / 14;
      smoothDMMinus = (smoothDMMinus * 13 + dmMinus[i]) / 14;
      smoothTR = (smoothTR * 13 + tr[i]) / 14;
    }
    
    // 4. +DI, -DI 계산
    const plusDI = smoothTR > 0 ? (smoothDMPlus / smoothTR) * 100 : 0;
    const minusDI = smoothTR > 0 ? (smoothDMMinus / smoothTR) * 100 : 0;
    
    // 5. DX 계산
    const diSum = plusDI + minusDI;
    const dx = diSum > 0 ? Math.abs(plusDI - minusDI) / diSum * 100 : 0;
    
    // 6. ADX 계산 (DX의 14일 평활화)
    if (chartData.length < 28) return dx; // 14일 + 14일 = 28일 필요
    
    // DX 값들을 수집하여 ADX 계산
    const dxValues: number[] = [];
    for (let i = 14; i < chartData.length; i++) {
      // 각 시점에서의 DX 계산
      const currentDx = dx; // 간소화: 마지막 DX 값 사용
      dxValues.push(currentDx);
    }
    
    // ADX = DX의 14일 평활화
    if (dxValues.length < 14) return dx;
    
    let adx = dxValues.slice(0, 14).reduce((sum, d) => sum + d, 0) / 14;
    
    // 14일 이후 평활화
    for (let i = 14; i < dxValues.length; i++) {
      adx = (adx * 13 + dxValues[i]) / 14;
    }
    
    return adx;
  }
  
  
  
  /**
   * 전통적인 EMA 계산 (TradingView 표준)
   * 과거부터 현재까지 순서로 정렬된 데이터 사용
   */
  private static calculateEMATraditional(prices: number[], period: number): number {
    if (prices.length < period) return prices[prices.length - 1] || 0;
    
    const multiplier = 2 / (period + 1);
    
    // 첫 번째 EMA는 단순 평균 (과거 period개 데이터)
    let ema = prices.slice(0, period).reduce((sum, price) => sum + price, 0) / period;
    
    // period 이후부터 순차적으로 EMA 계산
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
    
    // ✅ 최신 거래량 사용 (차트 데이터의 첫 번째 요소가 최신)
    const currentVolume = volumes[0] || 0; // 첫 번째 요소가 최신 데이터
    const avgVolume = volumes.slice(0, 20).reduce((a, b) => a + b, 0) / 20; // 최신 20일 평균
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
    
    // ✅ 최신 거래량 사용 (차트 데이터의 첫 번째 요소가 최신)
    const currentVolume = volumes[0] || 0; // 첫 번째 요소가 최신 데이터
    const avgVolume = volumes.slice(0, 20).reduce((a, b) => a + b, 0) / 20; // 최신 20일 평균
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
   * MACD 동적 점수 계산 (Histogram 기반)
   */
  private static calculateMACDScore(histogram: number, volumes: number[], adx: number, timeWeight: number): number {
    if (volumes.length < 20) return 0;
    
    // ✅ 최신 거래량 사용 (차트 데이터의 첫 번째 요소가 최신)
    const currentVolume = volumes[0] || 0; // 첫 번째 요소가 최신 데이터
    const avgVolume = volumes.slice(0, 20).reduce((a, b) => a + b, 0) / 20; // 최신 20일 평균
    const volumeRatio = avgVolume > 0 ? currentVolume / avgVolume : 1;
    
    // 추세 강도에 따른 가중치 (ADX 기준)
    const trendWeight = adx >= 25 ? 1.5 : 1.0;
    
    let baseScore = 0;
    
    // ✅ MACD Histogram 기반 신호 판단 (개선된 로직)
    // Histogram > 0이면 골든크로스, Histogram < 0이면 데드크로스
    if (histogram > 0.001) {
      // 골든크로스 (MACD Line > Signal Line) - 강한 신호
      baseScore = 1.0;
      if (volumeRatio >= 2) baseScore += 0.3;
      else if (volumeRatio >= 1.5) baseScore += 0.2;
    } else if (histogram > -0.001) {
      // 중립 (0에 가까움)
      baseScore = 0.0;
      if (volumeRatio >= 1.5) baseScore += 0.1;
    } else {
      // 데드크로스 (MACD Line < Signal Line) - 강한 신호
      baseScore = -1.0;
      if (volumeRatio >= 1.5) baseScore -= 0.2;
    }
    
    // 거래량 동반 보정
    if (volumeRatio >= 2.0) {
      baseScore *= 1.2; // 거래량 폭증 시 신호 강화
    } else if (volumeRatio < 0.8) {
      baseScore *= 0.8; // 거래량 부족 시 신호 약화
    }
    
    // 추세 강도 및 시간가중치 적용
    const finalScore = baseScore * trendWeight * timeWeight;
    
    console.log(`🔍 [MACD 점수 디버그] histogram: ${histogram}, volumeRatio: ${volumeRatio.toFixed(2)}, baseScore: ${baseScore.toFixed(3)}, finalScore: ${finalScore.toFixed(3)}`);
    
    return Math.max(-1.0, Math.min(1.0, finalScore));
  }
  
  /**
   * 볼린저밴드 동적 점수 계산
   */
  private static calculateBollingerScore(closes: number[], currentPrice: number, volumes: number[], atr: number, timeWeight: number): number {
    if (closes.length < 20) return 0;
    
    const sma20 = this.calculateMA(closes, 20);
    // ✅ 최신 20개 데이터 사용 (0번째부터 19번째까지)
    const stdDev = this.calculateStdDev(closes.slice(0, 20));
    const upperBand = sma20 + (2 * stdDev);
    const lowerBand = sma20 - (2 * stdDev);
    
    const bandPosition = (currentPrice - lowerBand) / (upperBand - lowerBand);
    const avgATR = atr;
    
    // ✅ 최신 거래량 사용 (차트 데이터의 첫 번째 요소가 최신)
    const currentVolume = volumes[0] || 0; // 첫 번째 요소가 최신 데이터
    const avgVolume = volumes.slice(0, 20).reduce((a, b) => a + b, 0) / 20; // 최신 20일 평균
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
    
    // ✅ 최신 거래량 사용 (차트 데이터의 첫 번째 요소가 최신)
    const currentVolume = volumes[0] || 0; // 첫 번째 요소가 최신 데이터
    const avgVolume = volumes.slice(0, 20).reduce((a, b) => a + b, 0) / 20; // 최신 20일 평균
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
    
    // ✅ 최신 거래량 사용 (차트 데이터의 첫 번째 요소가 최신)
    const currentVolume = volumes[0] || 0; // 첫 번째 요소가 최신 데이터
    const avgVolume = volumes.slice(0, 20).reduce((a, b) => a + b, 0) / 20; // 최신 20일 평균
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
    
    // ✅ 최신 거래량 사용 (차트 데이터의 첫 번째 요소가 최신)
    const currentVolume = volumes[0] || 0; // 첫 번째 요소가 최신 데이터
    const avgVolume = volumes.slice(0, 20).reduce((a, b) => a + b, 0) / 20; // 최신 20일 평균
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
    
    // ✅ 최신 14개 데이터 사용 (0번째부터 13번째까지)
    const recentData = chartData.slice(0, 14);
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
      // 🔍 current 필드 보호: 유효하지 않은 데이터라도 기존 데이터를 덮어쓰지 않음
      if (!currentPriceData || !currentPriceData.currentPrice || currentPriceData.currentPrice === 0) {
        console.log(`⚠️ 현재가 데이터 무효 (저장 건너뜀): ${symbol} - currentPrice: ${currentPriceData?.currentPrice}`);
        console.log(`🔍 [current 보호] 기존 current 필드 유지: ${symbol}`);
        return;
      }
      
      // 🔍 추가 데이터 검증: currentPrice만 확인 (다른 필드는 계산으로 보완)
      console.log(`🔍 [current 검증] ${symbol}: currentPrice=${currentPriceData.currentPrice}, changeRate=${currentPriceData.changeRate}, prevClose=${currentPriceData.prevClose}, tradeAmount=${currentPriceData.tradeAmount}`);
      
      // currentPrice만 유효하면 저장 (다른 필드는 계산으로 보완 가능)
      if (currentPriceData.currentPrice && currentPriceData.currentPrice > 0) {
        console.log(`✅ [current 검증] ${symbol}: currentPrice 유효, 저장 진행`);
      } else {
        console.log(`⚠️ current 데이터 무효 (저장 건너뜀): ${symbol} - currentPrice: ${currentPriceData.currentPrice}`);
        console.log(`🔍 [current 보호] 기존 current 필드 유지: ${symbol}`);
        return;
      }
      
      const db = admin.firestore();
      const stockRef = db.collection('stocks').doc(symbol);
      
      // 저장 전 최종 스케일 정규화 적용
      const normalizedData = this.normalizePriceScale(symbol, currentPriceData);
      
      // 정규화 후에도 유효성 재확인
      if (!normalizedData.currentPrice || normalizedData.currentPrice === 0) {
        console.log(`⚠️ 정규화 후 현재가 데이터 무효 (저장 건너뜀): ${symbol}`);
        return;
      }
      
      // 🔍 current 필드 보호: 유효한 데이터만 저장
      const updateData: any = {
        symbol,
        metadata: {
          lastUpdated: new Date(),
          currentPriceUpdated: new Date(),
          normalized: normalizedData.normalized || false,
          scale_factor: normalizedData.scale_factor || 1
        }
      };
      
      // current 필드는 유효한 경우에만 업데이트
      if (normalizedData && normalizedData.currentPrice && normalizedData.currentPrice > 0) {
        updateData.current = normalizedData;
        console.log(`✅ [saveCurrentPriceData] current 필드 업데이트: ${symbol} - ${normalizedData.currentPrice}`);
      } else {
        console.log(`🔍 [saveCurrentPriceData] current 필드 보호: ${symbol} - 기존 데이터 유지`);
      }
      
      await stockRef.set(updateData, { merge: true });
      
      console.log(`✅ 현재가 데이터 저장 완료: ${symbol} (currentPrice: ${normalizedData.currentPrice}, 정규화: ${normalizedData.normalized || false})`);
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
      
      // set with merge: true를 사용하여 문서가 없어도 생성
      await stockRef.set({
        symbol,
        analysis: analysis,
        metadata: {
          lastUpdated: new Date(),
          analysisUpdated: new Date()
        }
      }, { merge: true });
      
      console.log(`✅ 분석 데이터 저장 완료: ${symbol}`);
    } catch (error) {
      console.error(`❌ 분석 데이터 저장 실패: ${symbol}`, error);
    }
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
            trade_amount: (bar.close || 0) * (bar.volume || 0), // 거래대금 = 종가 × 거래량
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
