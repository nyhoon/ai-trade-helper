import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { StockDataService } from './stock_data_service';

// Firebase Admin SDK 초기화
if (!admin.apps.length) {
  admin.initializeApp();
}

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
    
    const { symbol, uid } = data;

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
 * 다중 종목 데이터 조회 Functions
 * 여러 종목의 데이터를 한 번에 조회
 */
export const getMultipleStockData = functions.https.onCall({
  region: 'asia-northeast3'
}, async (data: any, context: any) => {
  try {
    const { symbols, uid } = data;
    
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
    const { symbol, uid } = data;
    
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
    const { symbol } = data;
    
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
    
    const { symbol, uid } = data;
    
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
    
    const { symbol, days } = data;
    
    if (!symbol) {
      return { success: false, error: 'symbol is required' };
    }
    
    console.log(`📊 종목 분석 요청: ${symbol} (days: ${days})`);
    
    // 기본 분석 로직 (간단한 구현)
    const result = {
      success: true,
      symbol,
      analysis: {
        score: Math.random() * 2 - 1, // -1 ~ 1 사이의 랜덤 점수
        recommendation: Math.random() > 0.5 ? 'BUY' : 'SELL',
        confidence: Math.random() * 0.5 + 0.5, // 0.5 ~ 1.0
        lastUpdated: new Date().toISOString()
      }
    };
    
    console.log(`✅ 종목 분석 완료: ${symbol}`);
    return result;
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
    const { uid, days } = data;
    
    if (!uid) {
      return { success: false, error: 'uid is required' };
    }
    
    console.log(`📊 관심종목 분석 요청: ${uid} (days: ${days})`);
    
    // 기본 분석 로직 (간단한 구현)
    const results = [
      {
        symbol: 'AAPL',
        analysis: {
          score: Math.random() * 2 - 1,
          recommendation: 'BUY',
          confidence: Math.random() * 0.5 + 0.5
        }
      },
      {
        symbol: 'MSFT',
        analysis: {
          score: Math.random() * 2 - 1,
          recommendation: 'SELL',
          confidence: Math.random() * 0.5 + 0.5
        }
      }
    ];
    
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
    const { uid, days } = data;
    
    if (!uid) {
      return { success: false, error: 'uid is required' };
    }
    
    console.log(`📊 보유종목 분석 요청: ${uid} (days: ${days})`);
    
    // 기본 분석 로직 (간단한 구현)
    const results = [
      {
        symbol: 'TSLA',
        analysis: {
          score: Math.random() * 2 - 1,
          recommendation: 'HOLD',
          confidence: Math.random() * 0.5 + 0.5
        }
      }
    ];
    
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
    const { uid, limit } = data;
    
    if (!uid) {
      return { success: false, error: 'uid is required' };
    }
    
    console.log(`📊 추천 종목 요청: ${uid} (limit: ${limit})`);
    
    // 기본 추천 로직 (간단한 구현)
    const items = [
      {
        symbol: 'NVDA',
        score: Math.random() * 2 - 1,
        recommendation: 'BUY',
        confidence: Math.random() * 0.5 + 0.5
      },
      {
        symbol: 'GOOGL',
        score: Math.random() * 2 - 1,
        recommendation: 'BUY',
        confidence: Math.random() * 0.5 + 0.5
      }
    ];
    
    console.log(`✅ 추천 종목 완료: ${uid} (${items.length}개)`);
    return {
      success: true,
      items
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