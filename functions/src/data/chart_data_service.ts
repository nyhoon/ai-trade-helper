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
    try {
      // 기존 로직 유지: 먼저 오늘 캔들 보강 시도 후 최종 조회 반환

      // KST 오늘 날짜 생성 (yyyyMMdd)
      const now = new Date();
      const kst = new Date(now.getTime() + (9 * 60 * 60 * 1000));
      const yyyy = kst.getUTCFullYear();
      const mm = String(kst.getUTCMonth() + 1).padStart(2, '0');
      const dd = String(kst.getUTCDate()).padStart(2, '0');
      const today = `${yyyy}${mm}${dd}`;

      // charts/{symbol}/daily/{today}가 없고 prices/{symbol}이 있으면 임시 캔들 생성/업데이트
      const db = admin.firestore();
      const dailyRef = db.collection('charts').doc(symbol).collection('daily').doc(today);
      const todaySnap = await dailyRef.get();

      const priceSnap = await db.collection('prices').doc(symbol).get();
      const price = priceSnap.exists ? (priceSnap.data() as any) : null;

      if (!todaySnap.exists && price) {
        const open = Number(price.open ?? price.open_price ?? 0) || 0;
        const high = Number(price.high ?? price.high_price ?? 0) || 0;
        const low = Number(price.low ?? price.low_price ?? 0) || 0;
        const close = Number(price.currentPrice ?? price.current_price ?? price.prpr ?? 0) || 0;
        const volume = Number(price.volume ?? 0) || 0;

        const doc = {
          date: today,
          date_ts: Number(today),
          open,
          high,
          low,
          close,
          volume,
          market: price.market ?? undefined,
          stock_code: symbol,
          updated_at: Date.now(),
        } as any;
        await dailyRef.set(doc, { merge: true });
      } else if (todaySnap.exists && price) {
        // 장중 갱신: 고가/저가/종가/거래량을 최신 prices로 보강
        const update: any = {};
        if (price.high != null || price.high_price != null) update.high = Number(price.high ?? price.high_price) || 0;
        if (price.low != null || price.low_price != null) update.low = Number(price.low ?? price.low_price) || 0;
        if (price.currentPrice != null || price.current_price != null || price.prpr != null) update.close = Number(price.currentPrice ?? price.current_price ?? price.prpr) || 0;
        if (price.volume != null) update.volume = Number(price.volume) || 0;
        if (Object.keys(update).length) {
          update.updated_at = Date.now();
          await dailyRef.set(update, { merge: true });
        }
      }

      // 최신 데이터 재조회 (today 반영)
      return await this.getChartData(symbol, days);
    } catch (e) {
      console.error('ensureChartData 실패:', e);
      return await this.getChartData(symbol, days);
    }
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
      
      if (doc.exists) {
        const data = doc.data();
        console.log(`✅ 현재가 데이터 조회 완료(prices): ${symbol}`);
        return data;
      }

      // charts/{symbol}/daily 최신 1건을 현재가로 변환하는 폴백
      console.log(`ℹ️ prices 미존재 → charts/daily 폴백 시도: ${symbol}`);
      const latestDaily = await admin.firestore()
        .collection('charts').doc(symbol).collection('daily')
        .orderBy('date_ts', 'desc')
        .limit(1)
        .get();

      if (!latestDaily.empty) {
        const latest = latestDaily.docs[0].data() as any;
        
        // 전일 데이터 조회 (최신 2개 데이터)
        const twoLatest = await admin.firestore()
          .collection('charts').doc(symbol).collection('daily')
          .orderBy('date_ts', 'desc')
          .limit(2)
          .get();
        
        let prevClose = latest?.close;
        if (twoLatest.docs.length >= 2) {
          const prevDay = twoLatest.docs[1].data() as any;
          prevClose = prevDay?.close || latest?.close;
        }
        
        const fallback = {
          symbol,
          // 서버 표준은 snake_case 유지. 클라이언트에서 camelCase로 매핑함
          current_price: Number(latest?.close ?? 0) || 0,
          prev_close: Number(prevClose ?? 0) || 0,
          open_price: Number(latest?.open ?? 0) || 0,
          high_price: Number(latest?.high ?? 0) || 0,
          low_price: Number(latest?.low ?? 0) || 0,
          volume: Number(latest?.volume ?? 0) || 0,
          timestamp: Number(latest?.date_ts ?? 0) || 0,
          market: latest?.market ?? undefined,
          stock_name: latest?.stock_name ?? undefined,
        } as any;

        console.log(`✅ 현재가 데이터 조회 완료(charts 폴백): ${symbol}`);
        return fallback;
      }

      console.log(`⚠️ 현재가/차트 데이터 모두 없음: ${symbol}`);
      return null;
      
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
