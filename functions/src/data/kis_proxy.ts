import * as admin from 'firebase-admin';

/**
 * KIS API 프록시 (간단 버전)
 * - Secret Manager/Firestore에서 자격/토큰을 읽어와 호출하는 자리는 TODO로 표시
 * - 실제 HTTP 호출부는 프로젝트 환경에 맞게 연동 필요
 */
export class KISProxy {
  static async fetchDailyChart(symbol: string, days: number = 100): Promise<any[]> {
    // TODO: 실제 KIS 호출 구현
    console.log(`(stub) KIS fetchDailyChart: ${symbol}, days=${days}`);
    return [];
  }

  static async fetchCurrentPrice(symbol: string): Promise<any> {
    // TODO: 실제 KIS 호출 구현
    console.log(`(stub) KIS fetchCurrentPrice: ${symbol}`);
    return null;
  }
}


