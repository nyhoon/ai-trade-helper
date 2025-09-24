/**
 * Import function triggers from their respective submodules:
 *
 * import {onCall} from "firebase-functions/v2/https";
 * import {onDocumentWritten} from "firebase-functions/v2/firestore";
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

import {setGlobalOptions} from "firebase-functions";
import {onCall} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {ComprehensiveIndicatorCalculator} from "./analysis/comprehensive_calculator";
import {ChartDataService} from "./data/chart_data_service";

// Start writing functions
// https://firebase.google.com/docs/functions/typescript

// For cost control, you can set the maximum number of containers that can be
// running at the same time. This helps mitigate the impact of unexpected
// traffic spikes by instead downgrading performance. This limit is a
// per-function limit. You can override the limit for each function using the
// `maxInstances` option in the function's options, e.g.
// `onRequest({ maxInstances: 5 }, (req, res) => { ... })`.
// NOTE: setGlobalOptions does not apply to functions using the v1 API. V1
// functions should each use functions.runWith({ maxInstances: 10 }) instead.
// In the v1 API, each function can only serve one request per container, so
// this will be the maximum concurrent request count.
setGlobalOptions({ maxInstances: 10 });

// Firebase Admin 초기화 (중복 초기화 방지)
try {
  if (admin.apps.length === 0) {
    admin.initializeApp();
  }
} catch (_) {
  // no-op
}

// 단일 종목 분석
export const analyzeStock = onCall<{ symbol: string; days?: number; buyThreshold?: number; sellThreshold?: number }>(
  { region: "asia-northeast3", memory: "256MiB", timeoutSeconds: 60 },
  async (request) => {
    const symbol = request.data?.symbol;
    const days = request.data?.days ?? 100;
    const buyThreshold = request.data?.buyThreshold;
    const sellThreshold = request.data?.sellThreshold;

    if (!symbol) {
      throw new Error("symbol is required");
    }

    const [chartData, currentPrice] = await Promise.all([
      ChartDataService.ensureChartData(symbol, 100),
      ChartDataService.ensureCurrentPrice(symbol),
    ]);

    const now = new Date();
    const currentTime = now.toTimeString().slice(0, 5);

    const result = await ComprehensiveIndicatorCalculator.calculateComprehensiveScore({
      symbol,
      chartData,
      currentPrice,
      currentTime,
      buyThreshold,
      sellThreshold,
    });

    // 결과를 Firestore에 저장 (선택)
    await admin.firestore().collection("analysis").doc(symbol).set(result, { merge: true });

    return result;
  }
);

// 차트 프록시(100일 보장)
export const getDailyChart = onCall<{ symbol: string; days?: number }>(
  { region: "asia-northeast3", memory: "256MiB", timeoutSeconds: 60 },
  async (request) => {
    const symbol = request.data?.symbol;
    const days = request.data?.days ?? 100;
    if (!symbol) throw new Error("symbol is required");
    const rows = await ChartDataService.ensureChartData(symbol, Math.max(1, Math.min(500, days)));
    return { symbol, count: rows.length, items: rows };
  }
);

// 현재가 프록시(최신 보장)
export const getCurrentPrice = onCall<{ symbol: string }>(
  { region: "asia-northeast3", memory: "256MiB", timeoutSeconds: 60 },
  async (request) => {
    const symbol = request.data?.symbol;
    if (!symbol) throw new Error("symbol is required");
    const price = await ChartDataService.ensureCurrentPrice(symbol);
    if (!price) return { symbol, hasData: false };
    return { symbol, hasData: true, data: price };
  }
);

// 다중 종목 분석
export const analyzeMultipleStocks = onCall<{ symbols: string[]; days?: number }>(
  { region: "asia-northeast3", memory: "256MiB", timeoutSeconds: 60 },
  async (request) => {
    const symbols = request.data?.symbols ?? [];
    const days = request.data?.days ?? 100;
    if (!Array.isArray(symbols) || symbols.length === 0) {
      throw new Error("symbols must be a non-empty array");
    }

    const chartDataMap = await ChartDataService.getMultipleChartData(symbols, 100);
    const now = new Date();
    const currentTime = now.toTimeString().slice(0, 5);

    const results = await Promise.all(
      symbols.map(async (symbol) => {
        const chartData = chartDataMap[symbol] ?? await ChartDataService.ensureChartData(symbol, 100);
        const currentPrice = await ChartDataService.ensureCurrentPrice(symbol);
        if (!Array.isArray(chartData) || chartData.length < 60 || !currentPrice) {
          return null;
        }
        const result = await ComprehensiveIndicatorCalculator.calculateComprehensiveScore({
          symbol,
          chartData,
          currentPrice,
          currentTime,
        });
        await admin.firestore().collection("analysis").doc(symbol).set(result, { merge: true });
        return result;
      })
    );

    const filtered = results.filter((r) => r !== null);
    return { count: filtered.length, results: filtered };
  }
);

// 관심종목 일괄 분석
export const analyzeWatchlist = onCall<{ uid: string; days?: number }>(
  { region: "asia-northeast3", memory: "512MiB", timeoutSeconds: 120 },
  async (request) => {
    const uid = request.data?.uid;
    const days = request.data?.days ?? 100;
    if (!uid) throw new Error("uid is required");

    const watchlistSnap = await admin.firestore()
      .collection("users").doc(uid)
      .collection("watchlist").get();
    const symbols = watchlistSnap.docs.map(d => d.id).filter(Boolean);
    const chartDataMap = await ChartDataService.getMultipleChartData(symbols, days);
    const now = new Date();
    const currentTime = now.toTimeString().slice(0, 5);

    const results = await Promise.all(symbols.map(async (symbol) => {
      const chartData = chartDataMap[symbol] ?? await ChartDataService.ensureChartData(symbol, 100);
      const currentPrice = await ChartDataService.ensureCurrentPrice(symbol);
      if (!Array.isArray(chartData) || chartData.length < 60 || !currentPrice) {
        return null;
      }
      const result = await ComprehensiveIndicatorCalculator.calculateComprehensiveScore({
        symbol, chartData, currentPrice, currentTime,
      });
      await admin.firestore().collection("users").doc(uid)
        .collection("analysis").doc(symbol).set(result, { merge: true });
      return result;
    }));

    const filtered = results.filter((r) => r !== null);
    return { count: filtered.length, results: filtered };
  }
);

// 보유종목 일괄 분석
export const analyzeHoldings = onCall<{ uid: string; days?: number }>(
  { region: "asia-northeast3", memory: "512MiB", timeoutSeconds: 120 },
  async (request) => {
    const uid = request.data?.uid;
    const days = request.data?.days ?? 100;
    if (!uid) throw new Error("uid is required");

    const holdingsSnap = await admin.firestore()
      .collection("users").doc(uid)
      .collection("holdings").get();
    const symbols = holdingsSnap.docs.map(d => d.id).filter(Boolean);
    const chartDataMap = await ChartDataService.getMultipleChartData(symbols, days);
    const now = new Date();
    const currentTime = now.toTimeString().slice(0, 5);

    const results = await Promise.all(symbols.map(async (symbol) => {
      const chartData = chartDataMap[symbol] ?? await ChartDataService.ensureChartData(symbol, 100);
      const currentPrice = await ChartDataService.ensureCurrentPrice(symbol);
      if (!Array.isArray(chartData) || chartData.length < 60 || !currentPrice) {
        return null;
      }
      const result = await ComprehensiveIndicatorCalculator.calculateComprehensiveScore({
        symbol, chartData, currentPrice, currentTime,
      });
      await admin.firestore().collection("users").doc(uid)
        .collection("analysis").doc(symbol).set(result, { merge: true });
      return result;
    }));

    const filtered = results.filter((r) => r !== null);
    return { count: filtered.length, results: filtered };
  }
);

// 상위 추천 N개 반환
export const getTopRecommendations = onCall<{ uid: string; limit?: number }>(
  { region: "asia-northeast3", memory: "256MiB", timeoutSeconds: 60 },
  async (request) => {
    const uid = request.data?.uid;
    const limit = Math.max(1, Math.min(100, request.data?.limit ?? 10));
    if (!uid) throw new Error("uid is required");

    const analysisSnap = await admin.firestore()
      .collection("users").doc(uid)
      .collection("analysis").get();
    const items = analysisSnap.docs.map(d => ({ id: d.id, ...(d.data() as any) }))
      .filter(r => typeof r.comprehensiveScore === "number")
      .filter(r => {
        try {
          const ind = r.individualScores || {};
          const sumAbs = Object.values(ind).reduce((acc: number, v: any) => acc + Math.abs(Number(v || 0)), 0);
          return sumAbs > 0.01;
        } catch (_) { return false; }
      });
    items.sort((a, b) => (b.comprehensiveScore ?? 0) - (a.comprehensiveScore ?? 0));
    const top = items.slice(0, limit);

    await admin.firestore().collection("users").doc(uid)
      .collection("recommendations").doc("top10").set({
        updatedAt: Date.now(),
        limit,
        items: top,
      }, { merge: true });

    // 시장별 Top10 저장 (가능한 경우)
    // 시장 정보는 stock_master/{symbol}.market 또는 prices/{symbol}.market에서 조회
    const markets: Record<string, any[]> = {};
    for (const it of top) {
      let market: string | undefined = it.market;
      if (!market) {
        const m1 = await admin.firestore().collection('stock_master').doc(it.id).get();
        market = (m1.data() as any)?.market;
        if (!market) {
          const p1 = await admin.firestore().collection('prices').doc(it.id).get();
          market = (p1.data() as any)?.market;
        }
      }
      if (!market) continue;
      if (!markets[market]) markets[market] = [];
      markets[market].push(it);
    }

    const recCol = admin.firestore().collection('users').doc(uid).collection('recommendations').doc('markets');
    const batch = admin.firestore().batch();
    const nowTs = Date.now();
    for (const [market, list] of Object.entries(markets)) {
      const ordered = [...list].sort((a, b) => (b.comprehensiveScore ?? 0) - (a.comprehensiveScore ?? 0)).slice(0, limit);
      batch.set(recCol.collection(String(market)).doc('top10'), { updatedAt: nowTs, limit, items: ordered }, { merge: true });
    }
    await batch.commit();

    return { count: top.length, items: top, markets: Object.keys(markets) };
  }
);
