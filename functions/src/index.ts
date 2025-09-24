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
      ChartDataService.getChartData(symbol, days),
      ChartDataService.getCurrentPrice(symbol),
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

// 다중 종목 분석
export const analyzeMultipleStocks = onCall<{ symbols: string[]; days?: number }>(
  { region: "asia-northeast3", memory: "256MiB", timeoutSeconds: 60 },
  async (request) => {
    const symbols = request.data?.symbols ?? [];
    const days = request.data?.days ?? 100;
    if (!Array.isArray(symbols) || symbols.length === 0) {
      throw new Error("symbols must be a non-empty array");
    }

    const chartDataMap = await ChartDataService.getMultipleChartData(symbols, days);
    const now = new Date();
    const currentTime = now.toTimeString().slice(0, 5);

    const results = await Promise.all(
      symbols.map(async (symbol) => {
        const chartData = chartDataMap[symbol] ?? [];
        const currentPrice = await ChartDataService.getCurrentPrice(symbol);
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

    return { count: results.length, results };
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
      const chartData = chartDataMap[symbol] ?? [];
      const currentPrice = await ChartDataService.getCurrentPrice(symbol);
      const result = await ComprehensiveIndicatorCalculator.calculateComprehensiveScore({
        symbol, chartData, currentPrice, currentTime,
      });
      await admin.firestore().collection("users").doc(uid)
        .collection("analysis").doc(symbol).set(result, { merge: true });
      return result;
    }));

    return { count: results.length, results };
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
      const chartData = chartDataMap[symbol] ?? [];
      const currentPrice = await ChartDataService.getCurrentPrice(symbol);
      const result = await ComprehensiveIndicatorCalculator.calculateComprehensiveScore({
        symbol, chartData, currentPrice, currentTime,
      });
      await admin.firestore().collection("users").doc(uid)
        .collection("analysis").doc(symbol).set(result, { merge: true });
      return result;
    }));

    return { count: results.length, results };
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
      .filter(r => typeof r.comprehensiveScore === "number");
    items.sort((a, b) => (b.comprehensiveScore ?? 0) - (a.comprehensiveScore ?? 0));
    const top = items.slice(0, limit);

    await admin.firestore().collection("users").doc(uid)
      .collection("recommendations").doc("top10").set({
        updatedAt: Date.now(),
        limit,
        items: top,
      }, { merge: true });

    return { count: top.length, items: top };
  }
);
