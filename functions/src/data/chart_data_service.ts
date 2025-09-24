import * as admin from 'firebase-admin';

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
      
      const doc = await admin.firestore()
        .collection('charts')
        .doc(symbol)
        .get();
      
      if (!doc.exists) {
        console.log(`⚠️ 차트 데이터 없음: ${symbol}`);
        return [];
      }
      
      const data = doc.data();
      if (!data || !data.data) {
        console.log(`⚠️ 차트 데이터 형식 오류: ${symbol}`);
        return [];
      }
      
      // 최신 데이터부터 정렬하고 요청된 일수만큼 반환
      const chartData = Array.isArray(data.data) ? data.data : [];
      const sortedData = chartData
        .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime())
        .slice(0, days);
      
      console.log(`✅ 차트 데이터 조회 완료: ${symbol} (${sortedData.length}개)`);
      return sortedData;
      
    } catch (error) {
      console.error(`❌ 차트 데이터 조회 실패: ${symbol}`, error);
      return [];
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
      
      await admin.firestore()
        .collection('charts')
        .doc(symbol)
        .set({
          data: chartData,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          count: chartData.length
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
