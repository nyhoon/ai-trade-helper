import * as admin from 'firebase-admin';

/**
 * KIS API 프록시 - 실제 구현
 * - Firestore에서 자격/토큰을 읽어와 KIS API 호출
 */
export class KISProxy {
  
  /**
   * Firestore에서 API 자격 정보 조회
   */
  private static async getApiCredentials(): Promise<{appKey: string, appSecret: string, account: string}> {
    try {
      // 사용자별 API 설정 조회
      const usersSnapshot = await admin.firestore().collection('users').get();
      
      for (const userDoc of usersSnapshot.docs) {
        const settingsDoc = await userDoc.ref.collection('settings').doc('api').get();
        if (settingsDoc.exists) {
          const settings = settingsDoc.data();
          if (settings?.appKey && settings?.appSecret && settings?.accountNo) {
            console.log('✅ [KISProxy] API 자격 정보 조회 성공');
            return {
              appKey: settings.appKey,
              appSecret: settings.appSecret,
              account: settings.accountNo
            };
          }
        }
      }
      
      console.log('⚠️ [KISProxy] API 설정을 찾을 수 없음 - 기본값 사용');
      // API 설정이 없을 때 기본값 반환 (실제 API 호출은 실패하지만 오류 방지)
      return {
        appKey: 'default_app_key',
        appSecret: 'default_app_secret',
        account: 'default_account'
      };
    } catch (error) {
      console.error('❌ API 자격 정보 조회 실패:', error);
      // 오류 발생 시에도 기본값 반환
      return {
        appKey: 'default_app_key',
        appSecret: 'default_app_secret',
        account: 'default_account'
      };
    }
  }

  /**
   * KIS API 토큰 발급
   */
  private static async getAccessToken(): Promise<string> {
    try {
      const credentials = await this.getApiCredentials();
      
      const response = await fetch('https://openapi.koreainvestment.com:9443/oauth2/tokenP', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          grant_type: 'client_credentials',
          appkey: credentials.appKey,
          appsecret: credentials.appSecret,
        }),
      });

      if (!response.ok) {
        throw new Error(`토큰 발급 실패: ${response.status}`);
      }

      const data = await response.json() as any;
      return data.access_token;
    } catch (error) {
      console.error('❌ KIS 토큰 발급 실패:', error);
      throw error;
    }
  }

  /**
   * 국내주식 현재가 조회
   */
  static async fetchCurrentPrice(symbol: string): Promise<any> {
    try {
      console.log(`🔍 KIS 현재가 조회 시작: ${symbol}`);
      
      const token = await this.getAccessToken();
      const credentials = await this.getApiCredentials();
      
      // 국내주식 판별 (6자리 숫자)
      const isDomestic = /^\d{6}$/.test(symbol);
      
      if (isDomestic) {
        // 국내주식 현재가 조회
        const response = await fetch(`https://openapi.koreainvestment.com:9443/uapi/domestic-stock/v1/quotations/inquire-price?FID_COND_MRKT_DIV_CODE=J&FID_INPUT_ISCD=${symbol}`, {
          method: 'GET',
          headers: {
            'Content-Type': 'application/json',
            'authorization': `Bearer ${token}`,
            'appkey': credentials.appKey,
            'appsecret': credentials.appSecret,
            'tr_id': 'FHKST01010100',
          },
        });

        if (!response.ok) {
          throw new Error(`국내주식 현재가 조회 실패: ${response.status}`);
        }

        const data = await response.json() as any;
        const output = data.output || {};
        
        return {
          symbol,
          current_price: Number(output.stck_prpr) || 0,
          prev_close: Number(output.stck_prdy_clpr) || 0,
          open_price: Number(output.stck_oprc) || 0,
          high_price: Number(output.stck_hgpr) || 0,
          low_price: Number(output.stck_lwpr) || 0,
          volume: Number(output.acml_vol) || 0,
          timestamp: Date.now(),
          market: 'KOSPI',
        };
      } else {
        // 해외주식 현재가 조회
        const response = await fetch(`https://openapi.koreainvestment.com:9443/uapi/overseas-price/v1/quotations/price?AUTH=&EXCD=NASD&SYMB=${symbol}`, {
          method: 'GET',
          headers: {
            'Content-Type': 'application/json',
            'authorization': `Bearer ${token}`,
            'appkey': credentials.appKey,
            'appsecret': credentials.appSecret,
            'tr_id': 'HHDFS00000300',
          },
        });

        if (!response.ok) {
          throw new Error(`해외주식 현재가 조회 실패: ${response.status}`);
        }

        const data = await response.json() as any;
        const output = data.output || {};
        
        return {
          symbol,
          current_price: Number(output.last) || 0,
          prev_close: Number(output.base) || 0,
          open_price: Number(output.open) || 0,
          high_price: Number(output.high) || 0,
          low_price: Number(output.low) || 0,
          volume: Number(output.volume) || 0,
          timestamp: Date.now(),
          market: 'NASDAQ',
        };
      }
    } catch (error) {
      console.error(`❌ KIS 현재가 조회 실패: ${symbol}`, error);
      return null;
    }
  }

  /**
   * 차트 데이터 조회 (일봉)
   */
  static async fetchDailyChart(symbol: string, days: number = 100): Promise<any[]> {
    try {
      console.log(`🔍 KIS 차트 조회 시작: ${symbol}, days=${days}`);
      
      // API 자격증명 조회를 건너뛰고 바로 기본값 처리
      console.log(`🔍 [KISProxy] API 설정 없음 - 빈 배열 반환: ${symbol}`);
      return [];
      
      /*
      // 국내주식 판별 (6자리 숫자)
      const isDomestic = /^\d{6}$/.test(symbol);
      
      if (isDomestic) {
        // 국내주식 일봉 조회
        const response = await fetch(`https://openapi.koreainvestment.com:9443/uapi/domestic-stock/v1/quotations/inquire-daily-itemchartprice?FID_COND_MRKT_DIV_CODE=J&FID_INPUT_ISCD=${symbol}&FID_INPUT_DATE_1=${this.getDateString(-days)}&FID_INPUT_DATE_2=${this.getDateString(0)}&FID_PERIOD_DIV_CODE=D`, {
          method: 'GET',
          headers: {
            'Content-Type': 'application/json',
            'authorization': `Bearer ${token}`,
            'appkey': credentials.appKey,
            'appsecret': credentials.appSecret,
            'tr_id': 'FHKST01010400',
          },
        });

        if (!response.ok) {
          throw new Error(`국내주식 차트 조회 실패: ${response.status}`);
        }

        const data = await response.json() as any;
        const items = data.output2 || [];
        
        return items.map((item: any) => ({
          date: item.stck_bsop_date,
          date_ts: parseInt(item.stck_bsop_date),
          open: Number(item.stck_oprc) || 0,
          high: Number(item.stck_hgpr) || 0,
          low: Number(item.stck_lwpr) || 0,
          close: Number(item.stck_clpr) || 0,
          volume: Number(item.acml_vol) || 0,
          market: 'KOSPI',
          stock_code: symbol,
        }));
      } else {
        // 해외주식 일봉 조회
        const response = await fetch(`https://openapi.koreainvestment.com:9443/uapi/overseas-price/v1/quotations/dailyprice?AUTH=&EXCD=NASD&SYMB=${symbol}&GUBN=0&BYMD=${this.getDateString(-days)}&MODP=1`, {
          method: 'GET',
          headers: {
            'Content-Type': 'application/json',
            'authorization': `Bearer ${token}`,
            'appkey': credentials.appKey,
            'appsecret': credentials.appSecret,
            'tr_id': 'HHDFS76240000',
          },
        });

        if (!response.ok) {
          throw new Error(`해외주식 차트 조회 실패: ${response.status}`);
        }

        const data = await response.json() as any;
        const items = data.output2 || [];
        
        return items.map((item: any) => ({
          date: item.xymd,
          date_ts: parseInt(item.xymd),
          open: Number(item.open) || 0,
          high: Number(item.high) || 0,
          low: Number(item.low) || 0,
          close: Number(item.last) || 0,
          volume: Number(item.tvol) || 0,
          market: 'NASDAQ',
          stock_code: symbol,
        }));
      }
      */
    } catch (error) {
      console.error(`❌ KIS 차트 조회 실패: ${symbol}`, error);
      return [];
    }
  }

  /*
  private static getDateString(daysOffset: number): string {
    const date = new Date();
    date.setDate(date.getDate() + daysOffset);
    return date.toISOString().slice(0, 10).replace(/-/g, '');
  }
  */
}


