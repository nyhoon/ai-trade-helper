import * as functions from 'firebase-functions';
import { onDocumentUpdated, onDocumentWritten } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as admin from 'firebase-admin';
import { AnalysisEngine } from './analysis_engine';
import { StockDataService } from './stock_data_service';

// Firebase Admin SDK 초기화
if (!admin.apps.length) {
  admin.initializeApp();
}
// Firestore undefined 필드 저장 방지 (운영 안전)
try {
  admin.firestore().settings({ ignoreUndefinedProperties: true } as any);
} catch (_) {}

/**
 * 통합 종목 데이터 조회 Functions
 * 종목 하나에 대한 모든 정보를 한 번에 조회/생성/저장
 */
export const getStockData = functions.https.onCall({
  region: 'asia-northeast3'
}, async (data: any, context: any) => {
  try {
    // 인증 체크 (선택적)
    if (!context.auth) {
      console.log('⚠️ 인증되지 않은 사용자, 익명 사용자로 처리');
    } else {
      console.log(`✅ 인증된 사용자: ${context.auth.uid}`);
    }
    
    const actualData = (data?.data) ?? data;
    const { symbol, uid } = actualData;

    if (!symbol) {
      return { success: false, error: 'symbol is required' };
    }
    
    if (!uid) {
      return { success: false, error: 'uid is required' };
    }
    
    console.log(`📊 통합 종목 데이터 조회 요청: ${symbol} (uid: ${uid})`);
    
    const result = await StockDataService.getStockData(symbol, uid);
    
    console.log(`✅ 통합 종목 데이터 조회 완료: ${symbol}`);
    return result;
    
  } catch (error) {
    console.error('❌ 통합 종목 데이터 조회 실패:', error);
    return { 
      success: false, 
      error: error instanceof Error ? error.message : 'Unknown error' 
    };
  }
});

/**
 * 심볼 시드 주입: 기본 마켓 대표 심볼들을 stocks 컬렉션에 생성
 */
export const seedStocks = functions.https.onCall({
  region: 'asia-northeast3'
}, async (data: any, context: any) => {
  try {
    const db = admin.firestore();
    const defaults = [
      // 국내 상위 예시
      '005930','000660','035420','035720','068270','051910','207940','006400','105560','000270',
      // 해외 상위 예시
      'AAPL','MSFT','GOOGL','AMZN','TSLA','NVDA','META','NFLX','AMD','AVGO'
    ];
    let created = 0;
    for (const symbol of defaults) {
      const ref = db.collection('stocks').doc(symbol);
      const doc = await ref.get();
      if (!doc.exists) {
        await ref.set({ symbol, createdAt: new Date() }, { merge: true });
        created += 1;
      }
    }
    return { success: true, created };
  } catch (e) {
    return { success: false, error: e instanceof Error ? e.message : 'Unknown error' };
  }
});

/**
 * master/symbols 설정: 국내/해외 심볼 배열 저장
 */
export const setMasterSymbols = functions.https.onCall({
  region: 'asia-northeast3'
}, async (data: any) => {
  try {
    const actual = (data?.data) ?? data ?? {};
    const domestic = Array.isArray(actual.domestic) ? actual.domestic : [];
    const overseas = Array.isArray(actual.overseas) ? actual.overseas : [];
    const db = admin.firestore();
    await db.collection('master').doc('symbols').set({
      domestic,
      overseas,
      updatedAt: new Date(),
    }, { merge: true });
    return { success: true, domestic: domestic.length, overseas: overseas.length };
  } catch (e) {
    return { success: false, error: e instanceof Error ? e.message : 'Unknown error' };
  }
});

/**
 * master/symbols 기반으로 stocks 시드
 */
export const seedFromMaster = functions.https.onCall({
  region: 'asia-northeast3'
}, async (data: any) => {
  try {
    const { limit = 1000 } = (data?.data) ?? data ?? {};
    const db = admin.firestore();
    const master = await db.collection('master').doc('symbols').get();
    const domestic: string[] = (master.exists ? (master.data()?.domestic as string[]) : []) || [];
    const overseas: string[] = (master.exists ? (master.data()?.overseas as string[]) : []) || [];
    const all = [...domestic, ...overseas];
    const slice = all.slice(0, Number(limit) || 1000);
    let created = 0;
    for (const s of slice) {
      await db.collection('stocks').doc(s).set({ symbol: s, createdAt: new Date() }, { merge: true });
      created += 1;
    }
    return { success: true, created };
  } catch (e) {
    return { success: false, error: e instanceof Error ? e.message : 'Unknown error' };
  }
});

/**
 * 다중 종목 데이터 조회 Functions
 * 여러 종목의 데이터를 한 번에 조회
 */
export const getMultipleStockData = functions.https.onCall({
  region: 'asia-northeast3'
}, async (data: any, context: any) => {
  try {
    const actualData = (data?.data) ?? data;
    const { symbols, uid } = actualData;
    
    if (!symbols || !Array.isArray(symbols)) {
      return { success: false, error: 'symbols array is required' };
    }
    
    if (!uid) {
      return { success: false, error: 'uid is required' };
    }
    
    console.log(`📊 다중 종목 데이터 조회 요청: ${symbols.length}개 종목 (uid: ${uid})`);
    
    const results = [];
    
    // 순차 처리로 API 제한 방지
    for (const symbol of symbols) {
      try {
        console.log(`📊 종목 데이터 조회: ${symbol}`);
        const result = await StockDataService.getStockData(symbol, uid);
        results.push({ symbol, ...result });
        
        // API 제한 방지를 위한 딜레이
        await new Promise(resolve => setTimeout(resolve, 100));
        
    } catch (error) {
        console.error(`❌ 종목 데이터 조회 실패: ${symbol}`, error);
        results.push({ 
          symbol,
          success: false, 
          error: error instanceof Error ? error.message : 'Unknown error' 
        });
      }
    }
    
    console.log(`✅ 다중 종목 데이터 조회 완료: ${results.length}개 결과`);
    return { success: true, results };
    
  } catch (error) {
    console.error('❌ 다중 종목 데이터 조회 실패:', error);
    return { 
      success: false, 
      error: error instanceof Error ? error.message : 'Unknown error' 
    };
  }
});

/**
 * 종목 데이터 새로고침 Functions
 * 기존 데이터를 무시하고 최신 데이터로 강제 업데이트
 */
export const refreshStockData = functions.https.onCall({
  region: 'asia-northeast3'
}, async (data: any, context: any) => {
  try {
    const actualData = (data?.data) ?? data;
    const { symbol, uid } = actualData;
    
    if (!symbol) {
      return { success: false, error: 'symbol is required' };
    }
    
    if (!uid) {
      return { success: false, error: 'uid is required' };
    }
    
    console.log(`🔄 종목 데이터 새로고침 요청: ${symbol} (uid: ${uid})`);
    
    // 기존 데이터 무시하고 최신 데이터로 강제 업데이트
    const result = await StockDataService.getStockData(symbol, uid);
    
    console.log(`✅ 종목 데이터 새로고침 완료: ${symbol}`);
    return result;
    
  } catch (error) {
    console.error('❌ 종목 데이터 새로고침 실패:', error);
    return { 
      success: false, 
      error: error instanceof Error ? error.message : 'Unknown error' 
    };
  }
});

/**
 * 종목 데이터 상태 확인 Functions
 * 특정 종목의 데이터 상태를 확인
 */
export const getStockDataStatus = functions.https.onCall({
  region: 'asia-northeast3'
}, async (data: any, context: any) => {
  try {
    const actualData = (data?.data) ?? data;
    const { symbol } = actualData;
    
    if (!symbol) {
      return { success: false, error: 'symbol is required' };
    }
    
    console.log(`📊 종목 데이터 상태 확인: ${symbol}`);
    
    const admin = require('firebase-admin');
    const db = admin.firestore();
    const stockRef = db.collection('stocks').doc(symbol);
    const stockDoc = await stockRef.get();
    
    if (!stockDoc.exists) {
      return { 
        success: true, 
        status: 'not_found',
        message: '종목 데이터가 존재하지 않습니다.'
      };
    }
    
    const stockData = stockDoc.data()!;
    const metadata = stockData.metadata || {};
    
    return {
      success: true,
      status: 'found',
      data: {
        symbol,
        lastUpdated: metadata.lastUpdated,
        version: metadata.version,
        dataCount: metadata.dataCount,
        hasChart: !!data.chart,
        hasCurrent: !!data.current,
        hasAnalysis: !!data.analysis
      }
    };
    
  } catch (error) {
    console.error('❌ 종목 데이터 상태 확인 실패:', error);
    return { 
      success: false, 
      error: error instanceof Error ? error.message : 'Unknown error' 
    };
  }
});


/**
 * 차트 데이터 생성 및 분석 Functions
 * 차트 데이터를 생성하고 분석을 수행
 */
export const ensureChartAndAnalyze = functions.https.onCall({
  region: 'asia-northeast3'
}, async (data: any, context: any) => {
  try {
    // 인증 체크 (선택적)
    if (!context.auth) {
      console.log('⚠️ 인증되지 않은 사용자, 익명 사용자로 처리');
    } else {
      console.log(`✅ 인증된 사용자: ${context.auth.uid}`);
    }
    
    console.log('🔍 [ensureChartAndAnalyze] data 타입:', typeof data);
    console.log('🔍 [ensureChartAndAnalyze] data 키들:', Object.keys(data || {}));
    console.log('🔍 [ensureChartAndAnalyze] data가 null인가?', data === null);
    console.log('🔍 [ensureChartAndAnalyze] data가 undefined인가?', data === undefined);
    
    // Firebase Functions v2에서는 실제 데이터가 data.data에 있음
    const actualData = data?.data || data;
    console.log('🔍 [ensureChartAndAnalyze] actualData 타입:', typeof actualData);
    console.log('🔍 [ensureChartAndAnalyze] actualData 키들:', Object.keys(actualData || {}));
    console.log('🔍 [ensureChartAndAnalyze] data.data 존재 여부:', !!data?.data);
    console.log('🔍 [ensureChartAndAnalyze] data.data 타입:', typeof data?.data);
    console.log('🔍 [ensureChartAndAnalyze] data.data 키들:', Object.keys(data?.data || {}));
    
    // 순환 참조 방지를 위해 안전한 JSON 변환
    try {
      const safeData = {
        symbol: actualData?.symbol,
        uid: actualData?.uid,
        market: actualData?.market,
        bars: actualData?.bars
      };
      console.log('🔍 [ensureChartAndAnalyze] 안전한 데이터:', JSON.stringify(safeData, null, 2));
    } catch (e) {
      console.log('🔍 [ensureChartAndAnalyze] 데이터 변환 실패:', e instanceof Error ? e.message : String(e));
    }
    
    const { symbol, uid, market, bars } = actualData;
    
    console.log('🔍 [ensureChartAndAnalyze] 파싱된 값들:');
    console.log('  - symbol:', symbol, '(타입:', typeof symbol, ')');
    console.log('  - uid:', uid, '(타입:', typeof uid, ')');
    console.log('  - market:', market, '(타입:', typeof market, ')');
    console.log('  - bars:', bars, '(타입:', typeof bars, ')');
    
    if (!symbol) {
      console.log('❌ [ensureChartAndAnalyze] symbol이 없음:', symbol);
      return { success: false, error: 'symbol is required' };
    }
    
    if (!uid) {
      return { success: false, error: 'uid is required' };
    }
    
    console.log(`📊 차트 데이터 생성 및 분석 요청: ${symbol} (uid: ${uid}, market: ${market})`);
    console.log(`📊 bars 데이터: ${bars ? 'provided' : 'not provided'}`);
    
    try {
      const result = await StockDataService.ensureChartAndAnalyze(symbol, uid, market, bars);
      console.log(`✅ 차트 데이터 생성 및 분석 성공: ${symbol}`);
      return {
        success: true,
        data: result
      };
    } catch (serviceError) {
      console.error(`❌ StockDataService.ensureChartAndAnalyze 실패: ${symbol}`, serviceError);
      return {
        success: false,
        error: serviceError instanceof Error ? serviceError.message : 'StockDataService error'
      };
    }
  } catch (error) {
    console.error('❌ 차트 데이터 생성 및 분석 실패:', error);
    console.error('❌ 오류 상세:', {
      message: error instanceof Error ? error.message : 'Unknown error',
      stack: error instanceof Error ? error.stack : undefined,
      type: typeof error
    });
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
});

/**
 * 현재가 조회 Functions
 * 종목의 현재가 정보를 조회
 */
export const getCurrentPrice = functions.https.onCall({
  region: 'asia-northeast3'
}, async (data: any, context: any) => {
  try {
    // 인증 체크 (선택적)
    if (!context.auth) {
      console.log('⚠️ 인증되지 않은 사용자, 익명 사용자로 처리');
    } else {
      console.log(`✅ 인증된 사용자: ${context.auth.uid}`);
    }
    
    const actualData = (data?.data) ?? data;
    const { symbol, uid } = actualData;
    
    if (!symbol) {
      return { success: false, error: 'symbol is required' };
    }
    
    if (!uid) {
      return { success: false, error: 'uid is required' };
    }
    
    console.log(`💰 현재가 조회 요청: ${symbol} (uid: ${uid})`);
    
    const result = await StockDataService.getCurrentPriceForFunction(symbol, uid);
    
    return result;
  } catch (error) {
    console.error('❌ 현재가 조회 실패:', error);
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
});

/**
 * 종목 분석 Functions
 * 단일 종목에 대한 분석 수행
 */
export const analyzeStock = functions.https.onCall({
  region: 'asia-northeast3'
}, async (data: any, context: any) => {
  try {
    // 인증 체크 (선택적)
    if (!context.auth) {
      console.log('⚠️ 인증되지 않은 사용자, 익명 사용자로 처리');
    } else {
      console.log(`✅ 인증된 사용자: ${context.auth.uid}`);
    }
    
    const { symbol, days = 100 } = data;
    
    if (!symbol) {
      return { success: false, error: 'symbol is required' };
    }
    
    console.log(`📊 종목 분석 요청: ${symbol} (days: ${days})`);
    
    // 1. 차트 데이터 조회
    const chartData = await StockDataService.ensureChartData(symbol);
    if (!chartData || chartData.length === 0) {
      return { success: false, error: '차트 데이터를 조회할 수 없습니다' };
    }
    
    // 2. 현재가 조회
    const currentPrice = await StockDataService.getCurrentPrice(symbol);
    
    // 3. 7개 지표 기반 분석 수행
    const analysis = await AnalysisEngine.analyzeStock(symbol, chartData, currentPrice, context.auth?.uid || 'anonymous');
    
    console.log(`✅ 종목 분석 완료: ${symbol} (점수: ${analysis.totalScore.toFixed(3)})`);
    return {
      success: true,
      symbol,
      analysis
    };
  } catch (error) {
    console.error('❌ 종목 분석 실패:', error);
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
});

/**
 * 관심종목 분석 Functions
 * 사용자의 관심종목들을 일괄 분석
 */
export const analyzeWatchlist = functions.https.onCall({
  region: 'asia-northeast3'
}, async (data: any, context: any) => {
  try {
    const { uid, days = 100 } = data;
    
    if (!uid) {
      return { success: false, error: 'uid is required' };
    }
    
    console.log(`📊 관심종목 분석 요청: ${uid} (days: ${days})`);
    
    // 1. Firestore에서 관심종목 조회
    const db = admin.firestore();
    const watchlistRef = db.collection('users').doc(uid).collection('watchlist');
    const watchlistSnap = await watchlistRef.get();
    
    if (watchlistSnap.empty) {
      return { success: true, results: [] };
    }
    
    // 2. 각 관심종목에 대해 분석 수행
    const results = [];
    for (const doc of watchlistSnap.docs) {
      const symbol = doc.id;
      try {
        const chartData = await StockDataService.ensureChartData(symbol);
        const currentPrice = await StockDataService.getCurrentPrice(symbol);
        
        if (chartData && chartData.length > 0) {
          const analysis = await AnalysisEngine.analyzeStock(symbol, chartData, currentPrice, uid);
          results.push({
            symbol,
            analysis
          });
        }
      } catch (error) {
        console.error(`❌ 관심종목 분석 실패: ${symbol}`, error);
      }
    }
    
    console.log(`✅ 관심종목 분석 완료: ${uid} (${results.length}개)`);
    return {
      success: true,
      results
    };
  } catch (error) {
    console.error('❌ 관심종목 분석 실패:', error);
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
});

/**
 * 보유종목 분석 Functions
 * 사용자의 보유종목들을 일괄 분석
 */
export const analyzeHoldings = functions.https.onCall({
  region: 'asia-northeast3'
}, async (data: any, context: any) => {
  try {
    const { uid, days = 100 } = data;
    
    if (!uid) {
      return { success: false, error: 'uid is required' };
    }
    
    console.log(`📊 보유종목 분석 요청: ${uid} (days: ${days})`);
    
    // 1. Firestore에서 보유종목 조회
    const db = admin.firestore();
    const holdingsRef = db.collection('users').doc(uid).collection('holdings');
    const holdingsSnap = await holdingsRef.get();
    
    if (holdingsSnap.empty) {
      return { success: true, results: [] };
    }
    
    // 2. 각 보유종목에 대해 분석 수행
    const results = [];
    for (const doc of holdingsSnap.docs) {
      const symbol = doc.id;
      try {
        const chartData = await StockDataService.ensureChartData(symbol);
        const currentPrice = await StockDataService.getCurrentPrice(symbol);
        
        if (chartData && chartData.length > 0) {
          const analysis = await AnalysisEngine.analyzeStock(symbol, chartData, currentPrice, uid);
          results.push({
            symbol,
            analysis
          });
        }
      } catch (error) {
        console.error(`❌ 보유종목 분석 실패: ${symbol}`, error);
      }
    }
    
    console.log(`✅ 보유종목 분석 완료: ${uid} (${results.length}개)`);
    return {
      success: true,
      results
    };
  } catch (error) {
    console.error('❌ 보유종목 분석 실패:', error);
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
});

/**
 * 추천 종목 Functions
 * 상위 추천 종목들을 조회
 */
export const getTopRecommendations = functions.https.onCall({
  region: 'asia-northeast3'
}, async (data: any, context: any) => {
  try {
    const { uid, limit = 10, minTradeAmount } = data;
    
    if (!uid) {
      return { success: false, error: 'uid is required' };
    }
    
    console.log(`📊 추천 종목 요청: ${uid} (limit: ${limit})`);
    
    // 1. 인기 종목 리스트 (실제로는 더 많은 종목을 분석)
    const popularStocks = ['AAPL', 'MSFT', 'GOOGL', 'AMZN', 'TSLA', 'NVDA', 'META', 'NFLX', 'PLTZ', 'NVD'];
    
    // 2. 각 종목에 대해 분석 수행
    const results = [];
    for (const symbol of popularStocks) {
      try {
        const chartData = await StockDataService.ensureChartData(symbol);
        const currentPrice = await StockDataService.getCurrentPrice(symbol);
        
        if (chartData && chartData.length > 0) {
          const analysis = await AnalysisEngine.analyzeStock(symbol, chartData, currentPrice, uid);
          results.push({
            symbol,
            score: analysis.totalScore,
            recommendation: analysis.recommendation,
            confidence: analysis.confidence,
            analysis
          });
        }
      } catch (error) {
        console.error(`❌ 추천종목 분석 실패: ${symbol}`, error);
      }
    }
    
    // 2-1. 해외는 주식(01)과 ETF(03)만 허용: 메타에 따라 필터링
    let filtered = results.filter((item: any) => {
      const meta = item?.analysis?.meta || item?.meta || {};
      const typeCode = (meta.ovrs_stck_dvsn_cd || '').toString();
      // 해외 심볼 규칙으로 간단 판별 (영문 대문자)
      const isOverseas = /^[A-Z.]{1,6}$/.test(item.symbol || '');
      if (!isOverseas) return true; // 국내는 그대로 통과 (국내 필터는 기존 로직 elsewhere)
      if (!typeCode) return true;   // 메타 없으면 일단 통과
      return typeCode === '01' || typeCode === '03';
    });

    // 2-2. 거래대금 필터(옵션)
    if (typeof minTradeAmount === 'number' && !Number.isNaN(minTradeAmount)) {
      filtered = filtered.filter((item: any) => Number(item.tradeAmount || item?.current?.tradeAmount || 0) >= Number(minTradeAmount));
    }

    // 3. 점수순으로 정렬하고 상위 N개 반환
    filtered.sort((a: any, b: any) => b.score - a.score);
    const topResults = filtered.slice(0, limit);
    
    console.log(`✅ 추천 종목 완료: ${uid} (${topResults.length}개)`);
    return {
      success: true,
      items: topResults
    };
  } catch (error) {
    console.error('❌ 추천 종목 실패:', error);
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
});

/**
 * 메타 백필 실행 Functions (배치)
 * - stocks 컬렉션에서 최대 N개 문서를 가져와 메타를 채움
 */
export const backfillStockMeta = functions.https.onCall({
  region: 'asia-northeast3'
}, async (data: any, context: any) => {
  try {
    const { uid, limit = 500 } = (data?.data) ?? data ?? {};
    const result = await StockDataService.backfillAllMeta(uid, Number(limit) || 500);
    return { success: true, ...result };
  } catch (e) {
    return { success: false, error: e instanceof Error ? e.message : 'Unknown error' };
  }
});

/**
 * 분석 배치 실행 Functions
 */
export const analyzeStocksBatch = functions.https.onCall({
  region: 'asia-northeast3'
}, async (data: any, context: any) => {
  try {
    const { uid = 'system-batch', limit = 300 } = (data?.data) ?? data ?? {};
    const result = await StockDataService.analyzeBatch(Number(limit) || 300, uid);
    return { success: true, ...result };
  } catch (e) {
    return { success: false, error: e instanceof Error ? e.message : 'Unknown error' };
  }
});

/**
 * 즉시 집계 실행 Functions (Top10)
 */
export const triggerAggregateNow = functions.https.onCall({
  region: 'asia-northeast3'
}, async () => {
  try {
    const db = admin.firestore();
    const snap = await db.collection('stocks').orderBy('analysis.comprehensiveScore', 'desc' as any).limit(800).get();
    const rows = snap.docs.map(d => ({ id: d.id, ...(d.data() as any) }));

    const markets = ['KOSPI', 'KOSDAQ', 'NASDAQ'];
    for (const market of markets) {
      const top = rows
        .filter(r => {
          const marketStr = (r.info?.market || r.market || '').toString().toUpperCase();
          if (market === 'KOSPI') return marketStr.startsWith('KOSPI');
          if (market === 'KOSDAQ') return marketStr.startsWith('KOSDAQ');
          if (market === 'NASDAQ') return marketStr.startsWith('NAS');
          return false;
        })
        // 국내 REITs/ETF 제외
        .filter(r => {
          const isDomestic = ['KOSPI','KOSDAQ'].includes(market);
          if (!isDomestic) return true;
          const reits = (r.meta?.reits_kind_cd || r.info?.meta?.reits_kind_cd || '').toString();
          const etf = (r.meta?.etf_dvsn_cd || r.info?.meta?.etf_dvsn_cd || '').toString();
          return !(reits && reits !== '0') && !(etf && etf !== '0');
        })
        // 해외 주식/ETF만 포함
        .filter(r => {
          const isOverseas = market === 'NASDAQ';
          if (!isOverseas) return true;
          const typeCode = (r.meta?.ovrs_stck_dvsn_cd || r.info?.meta?.ovrs_stck_dvsn_cd || '').toString();
          if (!typeCode) return true;
          return typeCode === '01' || typeCode === '03';
        })
        .filter(r => typeof r.analysis?.comprehensiveScore === 'number')
        .sort((a, b) => (b.analysis.comprehensiveScore || 0) - (a.analysis.comprehensiveScore || 0))
        .slice(0, 10)
        .map(r => ({
          symbol: r.id,
          score: r.analysis.comprehensiveScore,
          tradeAmount: Number(r.current?.tradeAmount ?? 0),
          currentPrice: Number(r.current?.currentPrice ?? r.current?.current_price ?? 0),
          market: (r.info?.market || r.market || '').toString(),
          name: (r.info?.name || r.name || r.id || '').toString(),
          updatedAt: new Date(),
        }));

      await db.collection('top').doc(market).set({ items: top, updatedAt: new Date() }, { merge: true });
    }
    return { success: true };
  } catch (e) {
    return { success: false, error: e instanceof Error ? e.message : 'Unknown error' };
  }
});

// =============================
// 스케줄러: 자동 메타 백필/분석 실행
// =============================

export const scheduleBackfillMeta = onSchedule({ schedule: 'every 30 minutes', region: 'asia-northeast3' }, async () => {
  try {
    console.log('⏰ scheduleBackfillMeta start');
    await StockDataService.backfillAllMeta('system-scheduler', 800);
    console.log('✅ scheduleBackfillMeta done');
  } catch (e) {
    console.error('❌ scheduleBackfillMeta error', e);
  }
});

export const scheduleAnalyzeBatch = onSchedule({ schedule: 'every 30 minutes', region: 'asia-northeast3' }, async () => {
  try {
    console.log('⏰ scheduleAnalyzeBatch start');
    await StockDataService.analyzeBatch(800, 'system-scheduler');
    console.log('✅ scheduleAnalyzeBatch done');
  } catch (e) {
    console.error('❌ scheduleAnalyzeBatch error', e);
  }
});

/**
 * 통합 파이프라인 스케줄러
 * - 순서: 메타 백필 → 분석 배치 → Top10 집계
 * - 단일 잡으로 천천히 계속 쌓이는 형태
 */
export const schedulePipeline = onSchedule({ schedule: 'every 15 minutes', region: 'asia-northeast3' }, async () => {
  try {
    console.log('⏰ schedulePipeline start');
    await StockDataService.backfillAllMeta('system-pipeline', 600);
    await StockDataService.analyzeBatch(600, 'system-pipeline');

    // 집계 실행 (동일 로직 재사용)
    const db = admin.firestore();
    const snap = await db.collection('stocks').orderBy('analysis.comprehensiveScore', 'desc' as any).limit(800).get();
    const rows = snap.docs.map(d => ({ id: d.id, ...(d.data() as any) }));

    const markets = ['KOSPI', 'KOSDAQ', 'NASDAQ'];
    for (const market of markets) {
      const top = rows
        .filter(r => {
          const marketStr = (r.info?.market || r.market || '').toString().toUpperCase();
          if (market === 'KOSPI') return marketStr.startsWith('KOSPI');
          if (market === 'KOSDAQ') return marketStr.startsWith('KOSDAQ');
          if (market === 'NASDAQ') return marketStr.startsWith('NAS');
          return false;
        })
        .filter(r => {
          const isDomestic = ['KOSPI','KOSDAQ'].includes(market);
          if (!isDomestic) return true;
          const reits = (r.meta?.reits_kind_cd || r.info?.meta?.reits_kind_cd || '').toString();
          const etf = (r.meta?.etf_dvsn_cd || r.info?.meta?.etf_dvsn_cd || '').toString();
          return !(reits && reits !== '0') && !(etf && etf !== '0');
        })
        .filter(r => {
          const isOverseas = market === 'NASDAQ';
          if (!isOverseas) return true;
          const typeCode = (r.meta?.ovrs_stck_dvsn_cd || r.info?.meta?.ovrs_stck_dvsn_cd || '').toString();
          if (!typeCode) return true;
          return typeCode === '01' || typeCode === '03';
        })
        .filter(r => typeof r.analysis?.comprehensiveScore === 'number')
        .sort((a, b) => (b.analysis.comprehensiveScore || 0) - (a.analysis.comprehensiveScore || 0))
        .slice(0, 10)
        .map(r => ({
          symbol: r.id,
          score: r.analysis.comprehensiveScore,
          tradeAmount: Number(r.current?.tradeAmount ?? 0),
          currentPrice: Number(r.current?.currentPrice ?? r.current?.current_price ?? 0),
          market: (r.info?.market || r.market || '').toString(),
          name: (r.info?.name || r.name || r.id || '').toString(),
          updatedAt: new Date(),
        }));

      await db.collection('top').doc(market).set({ items: top, updatedAt: new Date() }, { merge: true });
    }
    console.log('✅ schedulePipeline done');
  } catch (e) {
    console.error('❌ schedulePipeline error', e);
  }
});

/**
 * =============================
 * 큐 기반 단일 종목 처리 워커
 * - queue/symbols 에서 심볼을 1~3개 꺼내 원자 처리(ensureChartAndAnalyze)
 * - 락/백오프/재시도 지원
 * =============================
 */
type QueueItem = {
  symbol: string;
  uid?: string;
  priority?: number;
  retries?: number;
  nextRunAt?: FirebaseFirestore.Timestamp;
  done?: boolean;
  createdAt?: FirebaseFirestore.Timestamp;
  updatedAt?: FirebaseFirestore.Timestamp;
};

async function acquireLock(db: FirebaseFirestore.Firestore, symbol: string, ttlMs: number = 5 * 60_000) {
  const lockRef = db.collection('locks').doc(`q_${symbol}`);
  const now = Date.now();
  const expiresAt = now + ttlMs;
  const snap = await lockRef.get();
  const cur = snap.data() as any;
  if (cur && cur.expiresAt && cur.expiresAt > now) {
    return false;
  }
  await lockRef.set({ symbol, acquiredAt: now, expiresAt, updatedAt: new Date() }, { merge: true });
  return true;
}

async function releaseLock(db: FirebaseFirestore.Firestore, symbol: string) {
  try {
    await db.collection('locks').doc(`q_${symbol}`).delete();
  } catch (_) {}
}

function calcBackoffMs(retries: number) {
  const base = 30_000; // 30s
  const factor = 1.5;
  const ms = Math.min(base * Math.pow(factor, Math.max(0, retries)), 10 * 60_000); // 최대 10분
  return Math.floor(ms);
}

async function shouldSkipByFilter(db: FirebaseFirestore.Firestore, symbol: string) {
  // 이미 메타가 존재하면 필터 적용
  try {
    const doc = await db.collection('stocks').doc(symbol).get();
    const data = doc.data() as any;
    const meta = data?.meta || data?.info?.meta || {};
    // 국내 코드
    if (/^\d{5,6}$/.test(symbol)) {
      const reits = (meta.reits_kind_cd || '').toString();
      const etf = (meta.etf_dvsn_cd || '').toString();
      if ((reits && reits !== '0') || (etf && etf !== '0')) return true;
      return false;
    }
    // 해외 코드
    if (/^[A-Z.]{1,6}$/.test(symbol)) {
      const typeCode = (meta.ovrs_stck_dvsn_cd || '').toString();
      if (!typeCode) return false; // 메타 없으면 일단 진행해 메타 채움
      return !(typeCode === '01' || typeCode === '03');
    }
    return true;
  } catch (_) {
    return false;
  }
}

export const processQueueSymbols = onSchedule({ schedule: 'every 1 minutes', region: 'asia-northeast3' }, async () => {
  const db = admin.firestore();
  const nowTs = admin.firestore.Timestamp.fromDate(new Date());
  try {
    console.log('⏰ processQueueSymbols start');
    // nextRunAt <= now, done != true
    // 인덱스 없이 동작하도록 done 필터는 코드에서 처리
    const snap = await db.collection('queue').doc('symbols').collection('items')
      .where('nextRunAt', '<=', nowTs)
      .orderBy('nextRunAt', 'asc')
      .limit(10)
      .get();

    if (snap.empty) {
      console.log('ℹ️ queue empty');
      return;
    }

    // 관심종목(보유) 경로와 동일한 자격으로 호출하기 위해 처리용 uid를 확보
    let processingUid: string | null = null;
    try {
      const sys = await db.collection('system').doc('settings').get();
      processingUid = (sys.exists ? (sys.data() as any)?.processingUid : null) || null;
      if (!processingUid) {
        // users 컬렉션에서 API 설정 보유 사용자 1명 찾기 (관심/보유와 동일한 권한 사용)
        const usersSnap = await db.collection('users').get();
        for (const u of usersSnap.docs) {
          const s = await u.ref.collection('settings').doc('api').get();
          if (s.exists && (s.data() as any)?.appKey && (s.data() as any)?.appSecret) {
            processingUid = u.id;
            break;
          }
        }
      }
      // 시스템에 processingUid 자동 보정(비어있을 때만)
      if (processingUid) {
        await db.collection('system').doc('settings').set({ processingUid, updatedAt: new Date() }, { merge: true });
      }
    } catch (e) {
      console.log('⚠️ processingUid 탐색 실패(폴백 null)', e);
      processingUid = null;
    }

    for (const doc of snap.docs) {
      const item = doc.data() as QueueItem;
      const symbol = item.symbol;
      if (!symbol) {
        await doc.ref.delete();
        continue;
      }
      if (item.done === true) {
        continue;
      }

      if (!(await acquireLock(db, symbol))) {
        continue;
      }

      try {
        const skip = await shouldSkipByFilter(db, symbol);
        if (skip) {
          await doc.ref.set({ done: true, updatedAt: new Date(), reason: 'filtered' } as any, { merge: true });
          await releaseLock(db, symbol);
          continue;
        }

        // 멀티 유저: 큐 항목 uid 우선, 없으면 processingUid 폴백
        const effectiveUid = (item.uid && typeof item.uid === 'string') ? item.uid : (processingUid || 'queue-worker');
        console.log(`🚚 processing: ${symbol} (uid=${effectiveUid})`);
        await StockDataService.ensureChartAndAnalyze(symbol, effectiveUid);

        // 성공 여부 검증: chart 또는 current가 존재해야 성공으로 간주
        const afterDoc = await db.collection('stocks').doc(symbol).get();
        const afterData = afterDoc.data() as any;
        const hasChart = Array.isArray(afterData?.chart) && afterData.chart.length > 0;
        const hasCurrent = !!afterData?.current && Number(afterData?.current?.currentPrice || afterData?.current?.current_price || 0) > 0;
        if (hasChart || hasCurrent) {
          await doc.ref.set({ done: true, updatedAt: new Date(), reason: 'ok' } as any, { merge: true });
          console.log(`✅ done: ${symbol} (chart=${hasChart}, current=${hasCurrent})`);
          await releaseLock(db, symbol);
        } else {
          throw new Error('post-check failed: no chart/current');
        }
      } catch (e) {
        const retries = (item.retries || 0) + 1;
        const nextRunAt = new Date(Date.now() + calcBackoffMs(retries));
        await doc.ref.set({ retries, nextRunAt, updatedAt: new Date(), error: (e as Error).message, done: false } as any, { merge: true });
        await releaseLock(db, symbol);
      }
    }
    console.log('✅ processQueueSymbols done');
  } catch (e) {
    console.error('❌ processQueueSymbols error', e);
  }
});

/** 큐 적재: master/symbols에서 가져와 queue/symbols/items로 넣기 */
export const enqueueFromMaster = functions.https.onCall({ region: 'asia-northeast3' }, async (data: any) => {
  try {
    const { limit = 2000, priority = 1, uid } = (data?.data) ?? data ?? {};
    const db = admin.firestore();
    const master = await db.collection('master').doc('symbols').get();
    const domestic: string[] = (master.exists ? (master.data()?.domestic as string[]) : []) || [];
    const overseas: string[] = (master.exists ? (master.data()?.overseas as string[]) : []) || [];
    const all = [...domestic, ...overseas];
    let enq = 0;
    for (const s of all.slice(0, Number(limit) || 2000)) {
      const ref = db.collection('queue').doc('symbols').collection('items').doc(s);
      const snap = await ref.get();
      if (snap.exists && (snap.data() as any)?.done !== true) continue;
      await ref.set({ symbol: s, uid, priority, retries: 0, nextRunAt: new Date(), done: false, createdAt: new Date(), updatedAt: new Date() });
      enq += 1;
    }
    return { success: true, enqueued: enq };
  } catch (e) {
    return { success: false, error: e instanceof Error ? e.message : 'Unknown error' };
  }
});

/** 큐 적재: 임의 리스트 */
export const enqueueSymbols = functions.https.onCall({ region: 'asia-northeast3' }, async (data: any) => {
  try {
    const { symbols = [], priority = 5, uid } = (data?.data) ?? data ?? {};
    const db = admin.firestore();
    let enq = 0;
    for (const s of symbols as string[]) {
      if (!s) continue;
      const ref = db.collection('queue').doc('symbols').collection('items').doc(s);
      await ref.set({ symbol: s, uid, priority, retries: 0, nextRunAt: new Date(), done: false, createdAt: new Date(), updatedAt: new Date() });
      enq += 1;
    }
    return { success: true, enqueued: enq };
  } catch (e) {
    return { success: false, error: e instanceof Error ? e.message : 'Unknown error' };
  }
});

/**
 * API 자격증명 저장 Functions
 * 사용자의 API 키, 시크릿, 계좌번호를 서버에 저장
 */
export const saveApiCredentials = functions.https.onCall({
  region: 'asia-northeast3'
}, async (data: any, context: any) => {
  try {
    // 인증 체크 (선택적)
    if (!context.auth) {
      console.log('⚠️ 인증되지 않은 사용자, 익명 사용자로 처리');
    } else {
      console.log(`✅ 인증된 사용자: ${context.auth.uid}`);
    }
    
    const { uid, appKey, appSecret, accountNo } = data;
    
    if (!uid) {
      return { success: false, error: 'uid is required' };
    }
    
    if (!appKey) {
      return { success: false, error: 'appKey is required' };
    }
    
    if (!appSecret) {
      return { success: false, error: 'appSecret is required' };
    }
    
    if (!accountNo) {
      return { success: false, error: 'accountNo is required' };
    }
    
    console.log(`🔐 API 자격증명 저장 요청: ${uid}`);
    
    // Firestore에 API 자격증명 저장
    const admin = require('firebase-admin');
    const db = admin.firestore();
    
    await db.collection('users').doc(uid).collection('settings').doc('api').set({
      appKey,
      appSecret,
      accountNo,
      lastUpdated: new Date().toISOString(),
    }, { merge: true });
    
    console.log(`✅ API 자격증명 저장 완료: ${uid}`);
    // 처리용 UID 최신 사용자로 항상 갱신 (latest-wins)
    try {
      const sysRef = db.collection('system').doc('settings');
      await sysRef.set({ processingUid: uid, updatedAt: new Date() }, { merge: true });
      console.log(`✅ processingUid 최신 사용자로 갱신: ${uid}`);
    } catch (e) {
      console.log('⚠️ processingUid 갱신 실패(무시):', e);
    }
    return {
      success: true,
      ok: true,
      message: 'API 자격증명이 성공적으로 저장되었습니다.'
    };
    
  } catch (error) {
    console.error('❌ API 자격증명 저장 실패:', error);
    return {
      success: false,
      ok: false,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
});

/**
 * 처리용 UID 설정 (관심/보유와 동일 자격으로 워커 실행)
 * - system/settings.processingUid 에 저장
 */
export const setProcessingUid = functions.https.onCall({ region: 'asia-northeast3' }, async (data: any) => {
  try {
    const { uid } = (data?.data) ?? data ?? {};
    if (!uid || typeof uid !== 'string') {
      return { success: false, error: 'uid is required' };
    }
    const db = admin.firestore();
    await db.collection('system').doc('settings').set({ processingUid: uid, updatedAt: new Date() }, { merge: true });
    return { success: true, processingUid: uid };
  } catch (e) {
    return { success: false, error: e instanceof Error ? e.message : 'Unknown error' };
  }
});

/**
 * 시스템 설정 변경 시(특히 processingUid 설정 직후) 큐를 자동 시드
 */
export const onSystemSettingsChanged = onDocumentWritten({ document: 'system/settings', region: 'asia-northeast3' }, async (event) => {
  try {
    const db = admin.firestore();
    const after = event.data?.after?.data() as any;
    const processingUid = after?.processingUid;
    if (!processingUid) return;

    // 큐가 비어 있으면 마스터에서 자동 시드 (최대 3000)
    const pendingSnap = await db.collection('queue').doc('symbols').collection('items')
      .where('done', '==', false).limit(1).get();
    if (!pendingSnap.empty) return;

    const master = await db.collection('master').doc('symbols').get();
    const domestic: string[] = (master.exists ? (master.data()?.domestic as string[]) : []) || [];
    const overseas: string[] = (master.exists ? (master.data()?.overseas as string[]) : []) || [];
    const all = [...domestic, ...overseas].slice(0, 3000);
    const batch = db.batch();
    for (const s of all) {
      const ref = db.collection('queue').doc('symbols').collection('items').doc(String(s));
      batch.set(ref, { symbol: String(s), priority: 1, retries: 0, nextRunAt: new Date(), done: false, createdAt: new Date(), updatedAt: new Date() }, { merge: true });
    }
    await batch.commit();
    console.log(`✅ queue auto-seeded from master: ${all.length}`);
  } catch (e) {
    console.error('❌ onSystemSettingsChanged failed', e);
  }
});

/**
 * 큐 보충 스케줄러: 큐가 비어있으면 주기적으로 자동 시드
 */
export const scheduleEnqueueIfEmpty = onSchedule({ schedule: 'every 10 minutes', region: 'asia-northeast3' }, async () => {
  try {
    const db = admin.firestore();
    const pendingSnap = await db.collection('queue').doc('symbols').collection('items')
      .where('done', '==', false).limit(1).get();
    if (!pendingSnap.empty) return;

    const master = await db.collection('master').doc('symbols').get();
    if (!master.exists) {
      console.log('ℹ️ master/symbols not found, skip enqueue');
      return;
    }
    const domestic: string[] = (master.data()?.domestic as string[]) || [];
    const overseas: string[] = (master.data()?.overseas as string[]) || [];
    const all = [...domestic, ...overseas].slice(0, 3000);
    const batch = db.batch();
    for (const s of all) {
      const ref = db.collection('queue').doc('symbols').collection('items').doc(String(s));
      batch.set(ref, { symbol: String(s), priority: 1, retries: 0, nextRunAt: new Date(), done: false, createdAt: new Date(), updatedAt: new Date() }, { merge: true });
    }
    await batch.commit();
    console.log(`✅ scheduleEnqueueIfEmpty queued: ${all.length}`);
  } catch (e) {
    console.error('❌ scheduleEnqueueIfEmpty error', e);
  }
});

/**
 * Firestore 트리거: stocks/{symbol} 문서 변경 시 자동 분석 보장
 * - current 또는 chart 변경 시에만 실행 (analysis 변경 루프 방지)
 */
export const onStockDocumentChanged = onDocumentUpdated({ document: 'stocks/{symbol}', region: 'asia-northeast3' }, async (event) => {
    try {
      const symbol = event.params.symbol as string;
      const before = event.data?.before?.data() || {} as any;
      const after = event.data?.after?.data() || {} as any;
      const beforeCurrent = JSON.stringify(before?.current || {});
      const afterCurrent = JSON.stringify(after?.current || {});
      const beforeChart = JSON.stringify(before?.chart || []);
      const afterChart = JSON.stringify(after?.chart || []);

      const currentChanged = beforeCurrent !== afterCurrent;
      const chartChanged = beforeChart !== afterChart;

      // analysis 갱신만 있을 때는 스킵 (루프 방지)
      if (!currentChanged && !chartChanged) {
        return null;
      }

      // 간단한 분산 스로틀: 최근 60초 내 실행되었으면 스킵
      const db = admin.firestore();
      const lockRef = db.collection('locks').doc(`analyze_${symbol}`);
      const now = Date.now();
      const lockSnap = await lockRef.get();
      const nextAllowedAt = Number(lockSnap.data()?.nextAllowedAt || 0);
      if (nextAllowedAt && now < nextAllowedAt) {
        console.log(`⏱️ [onStockDocumentChanged] throttle skip: ${symbol}`);
        return;
      }
      await lockRef.set({ nextAllowedAt: now + 60_000, updatedAt: new Date() }, { merge: true });

      console.log(`🔔 [onStockDocumentChanged] ${symbol} changed (current:${currentChanged}, chart:${chartChanged}) → 분석 보장`);
      // 시스템 트리거 uid 사용
      await StockDataService.ensureChartAndAnalyze(symbol, 'system-trigger');
      return;
    } catch (e) {
      console.error('❌ onStockDocumentChanged 실패', e);
      return;
    }
  });

/**
 * Firestore 트리거: 사용자의 보유 변경 시 해당 종목만 분석 보장
 */
export const onUserHoldingsChanged = onDocumentWritten({ document: 'users/{uid}/holdings/{symbol}', region: 'asia-northeast3' }, async (event) => {
    try {
      const symbol = event.params.symbol as string;
      const uid = event.params.uid as string;
      console.log(`🔔 [onUserHoldingsChanged] uid=${uid}, symbol=${symbol} → 분석 보장`);
      await StockDataService.ensureChartAndAnalyze(symbol, uid);
      return;
    } catch (e) {
      console.error('❌ onUserHoldingsChanged 실패', e);
      return;
    }
  });

/**
 * 스케줄러: 5분마다 시장별 Top10 집계 및 저장 (top/{market}/items)
 */
export const aggregateTop10 = onSchedule({ schedule: 'every 5 minutes', region: 'asia-northeast3' }, async () => {
  try {
    const db = admin.firestore();
    // 상위 후보 넉넉히 수집 (클라이언트에서 사용자별 거래대금 필터 적용)
    const snap = await db.collection('stocks').orderBy('analysis.comprehensiveScore', 'desc' as any).limit(800).get();
    const rows = snap.docs.map(d => ({ id: d.id, ...(d.data() as any) }));

    const markets = ['KOSPI', 'KOSDAQ', 'NASDAQ'];
    for (const market of markets) {
      const top = rows
        .filter(r => (r.info?.market || r.market || '').toString().toUpperCase().includes(market.substring(0, 3)))
        // 국내 시장의 경우 REITs/ETF 제외 (meta.reits_kind_cd, meta.etf_dvsn_cd)
        .filter(r => {
          const isDomestic = ['KOSPI','KOSDAQ'].includes(market);
          if (!isDomestic) return true;
          const reits = (r.meta?.reits_kind_cd || r.info?.meta?.reits_kind_cd || '').toString();
          const etf = (r.meta?.etf_dvsn_cd || r.info?.meta?.etf_dvsn_cd || '').toString();
          return !(reits && reits !== '0') && !(etf && etf !== '0');
        })
        // 해외 시장의 경우 주식(01), ETF(03)만 포함
        .filter(r => {
          const isOverseas = market === 'NASDAQ';
          if (!isOverseas) return true;
          const typeCode = (r.meta?.ovrs_stck_dvsn_cd || r.info?.meta?.ovrs_stck_dvsn_cd || '').toString();
          if (!typeCode) return true; // 메타 없으면 통과(백필 전 호환)
          return typeCode === '01' || typeCode === '03';
        })
        .filter(r => typeof r.analysis?.comprehensiveScore === 'number')
        .sort((a, b) => (b.analysis.comprehensiveScore || 0) - (a.analysis.comprehensiveScore || 0))
        .slice(0, 10)
        .map(r => ({ symbol: r.id, score: r.analysis.comprehensiveScore, tradeAmount: Number(r.current?.tradeAmount ?? 0), updatedAt: new Date() }));

      await db.collection('top').doc(market).set({ items: top, updatedAt: new Date() }, { merge: true });
      console.log(`✅ [aggregateTop10] ${market} 저장: ${top.length}개`);
    }
  } catch (e) {
    console.error('❌ aggregateTop10 실패', e);
  }
});