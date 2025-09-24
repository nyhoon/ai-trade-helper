import * as admin from 'firebase-admin';
import { KISProxy } from './kis_proxy';

/**
 * 차트 데이터 서비스
 * Firestore에서 차트 데이터를 조회하고 관리
 */
export class ChartDataService {
  
  /**
   * 차트 데이터 조회
   * @param symbol 종목코드
   * @param days 조회할 일수 (기본값: 100)
   * @returns 차트 데이터 배열
   */
  static async getChartData(symbol: string, days: number = 100): Promise<any[]> {
    try {
      console.log(`📊 차트 데이터 조회: ${symbol} (${days}일)`);
      
      // 1) subcollection daily 우선
      const dailySnap = await admin.firestore()
        .collection('charts').doc(symbol).collection('daily')
        .orderBy('date_ts', 'desc').limit(days).get();
      if (!dailySnap.empty) {
        const rows = dailySnap.docs.map(d => d.data());
        console.log(`✅ 차트 데이터 조회 완료(daily): ${symbol} (${rows.length}개)`);
        return rows.map(r => ({
          date: r.date,
          open: r.open, high: r.high, low: r.low, close: r.close,
          volume: r.volume, trade_amount: r.trade_amount,
        }));
      }

      // 2) 레거시 doc.data / doc.ohlcv 폴백
      const legacyDoc = await admin.firestore().collection('charts').doc(symbol).get();
      if (!legacyDoc.exists) {
        console.log(`⚠️ 차트 데이터 없음: ${symbol}`);
        return [];
      }
      const legacy = legacyDoc.data() as any;
      const arr = Array.isArray(legacy?.data) ? legacy.data
        : (Array.isArray(legacy?.ohlcv) ? legacy.ohlcv : []);
      if (!Array.isArray(arr) || arr.length === 0) return [];

      const normalized = arr.map((it: any) => ({
        date: it.date ?? it.d,
        open: (it.open ?? it.o) as number,
        high: (it.high ?? it.h) as number,
        low: (it.low ?? it.l) as number,
        close: (it.close ?? it.c) as number,
        volume: (it.volume ?? it.v) as number,
        trade_amount: it.trade_amount ?? it.t,
      })).filter((it: any) => !!it.date);

      // 최신 우선 정렬 후 days 만큼
      const sorted = normalized.sort((a: any, b: any) => new Date(b.date).getTime() - new Date(a.date).getTime())
        .slice(0, days);

      // best-effort: daily 서브컬렉션에 이식(비동기)
      try { await this.saveChartData(symbol, sorted); } catch (_) {}

      console.log(`✅ 차트 데이터 조회 완료(legacy): ${symbol} (${sorted.length}개)`);
      return sorted;
      
    } catch (error) {
      console.error(`❌ 차트 데이터 조회 실패: ${symbol}`, error);
      return [];
    }
  }

  /**
   * 차트 데이터 확보 보장: 부족하면 KIS에서 받아와 저장 후 재조회
   */
  static async ensureChartData(symbol: string, days: number = 100): Promise<any[]> {
    const cur = await this.getChartData(symbol, days);
    if (Array.isArray(cur) && cur.length >= days) return cur;
    try {
      const fetched = await KISProxy.fetchDailyChart(symbol, days);
      if (Array.isArray(fetched) && fetched.length > 0) {
        await this.saveChartData(symbol, fetched);
      }
    } catch (e) {
      console.error(`❌ KIS 차트 확보 실패: ${symbol}`, e);
    }
    return await this.getChartData(symbol, days);
  }

  /**
   * 현재가 데이터 조회
   * @param symbol 종목코드
   * @returns 현재가 데이터
   */
  static async getCurrentPrice(symbol: string): Promise<any> {
    try {
      console.log(`💰 현재가 데이터 조회: ${symbol}`);
      
      const doc = await admin.firestore()
        .collection('prices')
        .doc(symbol)
        .get();
      
      if (!doc.exists) {
        console.log(`⚠️ 현재가 데이터 없음: ${symbol}`);
        return null;
      }
      
      const data = doc.data();
      console.log(`✅ 현재가 데이터 조회 완료: ${symbol}`);
      return data;
      
    } catch (error) {
      console.error(`❌ 현재가 데이터 조회 실패: ${symbol}`, error);
      return null;
    }
  }

  /**
   * 현재가 확보 보장: 없거나 오래되면 KIS에서 받아와 저장
   */
  static async ensureCurrentPrice(symbol: string, freshnessMs: number = 60_000): Promise<any> {
    const cur = await this.getCurrentPrice(symbol);
    const now = Date.now();
    const ts = (cur?.timestamp as number) ?? 0;
    if (cur && now - ts < freshnessMs) return cur;
    try {
      const fetched = await KISProxy.fetchCurrentPrice(symbol);
      if (fetched) {
        await this.saveCurrentPrice(symbol, fetched);
      }
    } catch (e) {
      console.error(`❌ KIS 현재가 확보 실패: ${symbol}`, e);
    }
    return await this.getCurrentPrice(symbol);
  }

  /**
   * 여러 종목의 차트 데이터 조회
   * @param symbols 종목코드 배열
   * @param days 조회할 일수
   * @returns 종목별 차트 데이터 맵
   */
  static async getMultipleChartData(symbols: string[], days: number = 100): Promise<Record<string, any[]>> {
    try {
      console.log(`📊 다중 차트 데이터 조회: ${symbols.length}개 종목`);
      
      const results: Record<string, any[]> = {};
      
      // 병렬로 모든 종목의 차트 데이터 조회
      const promises = symbols.map(async (symbol) => {
        const chartData = await this.getChartData(symbol, days);
        return { symbol, chartData };
      });
      
      const chartDataResults = await Promise.all(promises);
      
      // 결과를 맵으로 변환
      chartDataResults.forEach(({ symbol, chartData }) => {
        results[symbol] = chartData;
      });
      
      console.log(`✅ 다중 차트 데이터 조회 완료: ${Object.keys(results).length}개 종목`);
      return results;
      
    } catch (error) {
      console.error('❌ 다중 차트 데이터 조회 실패:', error);
      return {};
    }
  }

  /**
   * 차트 데이터 저장
   * @param symbol 종목코드
   * @param chartData 차트 데이터
   */
  static async saveChartData(symbol: string, chartData: any[]): Promise<void> {
    try {
      console.log(`💾 차트 데이터 저장: ${symbol} (${chartData.length}개)`);
      const col = admin.firestore().collection('charts').doc(symbol);
      // daily subcollection 저장
      const batch = admin.firestore().batch();
      for (const b of chartData) {
        const date: string = b.date ?? b.d;
        if (!date) continue;
        const ref = col.collection('daily').doc(date);
        const dateTs = parseInt((date as string).replace(/-/g, ''));
        batch.set(ref, {
          stock_code: symbol,
          date,
          date_ts: isNaN(dateTs) ? null : dateTs,
          open: b.open ?? b.o ?? 0,
          high: b.high ?? b.h ?? 0,
          low: b.low ?? b.l ?? 0,
          close: b.close ?? b.c ?? 0,
          volume: b.volume ?? b.v ?? 0,
          trade_amount: b.trade_amount ?? b.t ?? null,
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }
      await batch.commit();

      // 요약 문서 업데이트(선택)
      await col.set({
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        count: chartData.length,
      }, { merge: true });

      console.log(`✅ 차트 데이터 저장 완료: ${symbol}`);
      
    } catch (error) {
      console.error(`❌ 차트 데이터 저장 실패: ${symbol}`, error);
      throw error;
    }
  }

  /**
   * 현재가 데이터 저장
   * @param symbol 종목코드
   * @param priceData 현재가 데이터
   */
  static async saveCurrentPrice(symbol: string, priceData: any): Promise<void> {
    try {
      console.log(`💾 현재가 데이터 저장: ${symbol}`);
      
      await admin.firestore()
        .collection('prices')
        .doc(symbol)
        .set({
          ...priceData,
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });
      
      console.log(`✅ 현재가 데이터 저장 완료: ${symbol}`);
      
    } catch (error) {
      console.error(`❌ 현재가 데이터 저장 실패: ${symbol}`, error);
      throw error;
    }
  }
}
