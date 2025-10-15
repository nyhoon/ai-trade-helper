import * as admin from 'firebase-admin';

/**
 * KIS API 프록시 - 실제 구현
 * - Firestore에서 자격/토큰을 읽어와 KIS API 호출
 * - v2: Firestore 기반 토큰 캐싱 추가
 */
export class KISProxy {
  // 토큰 캐시 (메모리 + Firestore 이중 캐싱)
  private static tokenCache: { token: string; expiresAt: number } | null = null;
  
  /**
   * Firestore에서 API 자격 정보 조회
   */
  private static async getApiCredentials(uid?: string): Promise<{appKey: string, appSecret: string, account: string}> {
    try {
      // 0) system/settings.processingUid 우선 적용 (서버 자율 실행 보장)
      try {
        const sysSnap = await admin.firestore().collection('system').doc('settings').get();
        const procUid = sysSnap.exists ? (sysSnap.data() as any)?.processingUid : null;
        if (!uid && procUid && typeof procUid === 'string') {
          uid = procUid;
          console.log(`🔍 [KISProxy] processingUid 사용: ${uid}`);
        }
      } catch (_) {}

      // 특정 사용자의 API 설정 조회 (uid가 제공된 경우)
      if (uid) {
        console.log(`🔍 [KISProxy] 특정 사용자 API 설정 조회: ${uid}`);
        console.log(`🔍 [KISProxy] Firestore 인스턴스 확인: ${admin.firestore() ? 'OK' : 'FAIL'}`);
        
        // 상위 문서 존재 여부와 관계없이 바로 서브컬렉션 조회
        const settingsDoc = await admin.firestore()
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('api')
          .get();
          
        console.log(`🔍 [KISProxy] API 설정 문서 존재: ${settingsDoc.exists}`);
        console.log(`🔍 [KISProxy] API 설정 문서 ID: ${settingsDoc.id}`);
        console.log(`🔍 [KISProxy] API 설정 문서 데이터:`, settingsDoc.data());
        
        if (settingsDoc.exists) {
          const settings = settingsDoc.data();
          console.log(`🔍 [KISProxy] API 설정 데이터:`, settings);
          
          if (settings?.appKey && settings?.appSecret && settings?.accountNo) {
            console.log('✅ [KISProxy] 특정 사용자 API 자격 정보 조회 성공');
            return {
              appKey: settings.appKey,
              appSecret: settings.appSecret,
              account: settings.accountNo
            };
          } else {
            console.log('⚠️ [KISProxy] API 설정 데이터가 불완전함:', {
              hasAppKey: !!settings?.appKey,
              hasAppSecret: !!settings?.appSecret,
              hasAccountNo: !!settings?.accountNo
            });
          }
        } else {
          console.log(`⚠️ [KISProxy] 사용자 ${uid}의 API 설정 문서가 존재하지 않음`);
          // 🔁 폴백: processingUid로 재조회 시도 (uid가 있으나 자격 없을 때도 처리)
          try {
            const sysSnap = await admin.firestore().collection('system').doc('settings').get();
            const procUid = sysSnap.exists ? (sysSnap.data() as any)?.processingUid : null;
            if (procUid && procUid !== uid) {
              console.log(`🔁 [KISProxy] processingUid로 재조회: ${procUid}`);
              return await this.getApiCredentials(procUid);
            }
          } catch (_) {}
        }
      }
      
      // 폴백: 모든 사용자 API 설정 조회
      console.log('🔍 [KISProxy] 모든 사용자 API 설정 조회 시도');
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
      
      console.log('⚠️ [KISProxy] API 설정을 찾을 수 없음 - 환경 변수에서 조회 시도');
      
      // 환경 변수에서 KIS API 자격 정보 조회
      const envAppKey = process.env.KIS_APP_KEY;
      const envAppSecret = process.env.KIS_APP_SECRET;
      const envAccount = process.env.KIS_ACCOUNT_NO;
      
      if (envAppKey && envAppSecret && envAccount) {
        console.log('✅ [KISProxy] 환경 변수에서 API 자격 정보 조회 성공');
        return {
          appKey: envAppKey,
          appSecret: envAppSecret,
          account: envAccount
        };
      }
      
      console.log('❌ [KISProxy] API 자격 정보를 찾을 수 없음 - KIS API 호출 불가');
      throw new Error('KIS API 자격 정보가 설정되지 않았습니다. 환경 변수 또는 Firestore에 API 키를 설정해주세요.');
    } catch (error) {
      console.error('❌ API 자격 정보 조회 실패:', error);
      throw error;
    }
  }

  /**
   * 해외 주식 기본/검색 정보 조회 (overseas search-info)
   * - 해외주식구분코드(ovrs_stck_dvsn_cd) 추출용
   * - 01: 주식, 02: Warrant, 03: ETF, 04: 우선주
   */
  static async fetchOverseasSearchInfo(symbol: string, exchangeCode: string = 'NAS', uid?: string): Promise<{
    ovrs_stck_dvsn_cd?: string;
    exchangeCode?: string;
    raw?: any;
  } | null> {
    try {
      // 해외 심볼 판별: 영문 대문자 1~6자 (간단 가드)
      if (!/^[A-Z.]{1,6}$/.test(symbol)) {
        return null;
      }

      const token = await this.getAccessToken(uid);
      const credentials = await this.getApiCredentials(uid);

      const url = `https://openapi.koreainvestment.com:9443/uapi/overseas-price/v1/quotations/search-info?AUTH=&EXCD=${encodeURIComponent(exchangeCode)}&SYMB=${encodeURIComponent(symbol)}`;
      const response = await fetch(url, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'authorization': `Bearer ${token}`,
          'appkey': credentials.appKey,
          'appsecret': credentials.appSecret,
          'tr_id': 'HHDFS76200200',
        },
      });

      if (!response.ok) {
        const txt = await response.text();
        console.log(`⚠️ [KISProxy] overseas search-info 실패 ${symbol}: ${response.status} ${txt.substring(0, 300)}`);
        return null;
      }

      const data = await response.json() as any;
      const out = data.output || data.output1 || data || {};
      const typeCode = out.ovrs_stck_dvsn_cd || out.OVRS_STCK_DVSN_CD || '';

      return { ovrs_stck_dvsn_cd: typeCode || undefined, exchangeCode, raw: out };
    } catch (e) {
      console.log(`⚠️ [KISProxy] overseas search-info 예외 ${symbol}:`, e);
      return null;
    }
  }

  /**
   * 해외 주식 검색정보 조회 (EXCD 순회 폴백)
   * - 기본 순서: NAS → NYS → HKS
   */
  static async fetchOverseasSearchInfoWithFallback(symbol: string, exchanges: string[] = ['NAS','NYS','HKS'], uid?: string) {
    for (const ex of exchanges) {
      const res = await this.fetchOverseasSearchInfo(symbol, ex, uid);
      if (res && res.ovrs_stck_dvsn_cd) {
        return res;
      }
    }
    return null;
  }

  /**
   * 국내 주식 기본/검색 정보 조회 (search-stock-info)
   * - REITs/ETF 구분 코드(reits_kind_cd, etf_dvsn_cd) 수집용
   */
  static async fetchDomesticSearchInfo(symbol: string, uid?: string): Promise<{
    reits_kind_cd?: string;
    etf_dvsn_cd?: string;
    raw?: any;
  } | null> {
    try {
      // 국내주식 코드만 처리 (5~6자리 숫자)
      if (!/^\d{5,6}$/.test(symbol)) {
        return null;
      }

      const token = await this.getAccessToken(uid);
      const credentials = await this.getApiCredentials(uid);

      const url = `https://openapi.koreainvestment.com:9443/uapi/domestic-stock/v1/quotations/search-stock-info?PDNO=${symbol}`;
      const response = await fetch(url, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'authorization': `Bearer ${token}`,
          'appkey': credentials.appKey,
          'appsecret': credentials.appSecret,
          'tr_id': 'CTPF1604R',
        },
      });

      if (!response.ok) {
        const txt = await response.text();
        console.log(`⚠️ [KISProxy] search-stock-info 실패 ${symbol}: ${response.status} ${txt.substring(0, 300)}`);
        return null;
      }

      const data = await response.json() as any;
      // 응답 구조 가드: output 또는 output1 등 다양한 케이스 대비
      const out = data.output || data.output1 || data || {};
      const reits = out.reits_kind_cd || out.REITS_KIND_CD || '';
      const etf = out.etf_dvsn_cd || out.ETF_DVSN_CD || '';

      return { reits_kind_cd: reits || undefined, etf_dvsn_cd: etf || undefined, raw: out };
    } catch (e) {
      console.log(`⚠️ [KISProxy] search-stock-info 예외 ${symbol}:`, e);
      return null;
    }
  }

  /**
   * KIS API 토큰 발급 (Firestore 캐싱 적용)
   */
  private static async getAccessToken(uid?: string): Promise<string> {
    try {
      // 1. 메모리 캐시된 토큰이 있고 유효하면 재사용
      if (this.tokenCache && this.tokenCache.expiresAt > Date.now()) {
        console.log(`✅ [KISProxy] 메모리 캐시된 토큰 재사용 (만료: ${new Date(this.tokenCache.expiresAt).toISOString()})`);
        return this.tokenCache.token;
      }
      
      // 2. Firestore에서 토큰 조회 (uid 여부와 관계없이 항상 시도)
      try {
        const tokenDoc = await admin.firestore()
          .collection('system')
          .doc('kis_token')
          .get();
          
        if (tokenDoc.exists) {
          const tokenData = tokenDoc.data();
          console.log(`🔍 [KISProxy] Firestore 토큰 데이터:`, {
            exists: true,
            hasToken: !!tokenData?.token,
            expiresAt: tokenData?.expiresAt,
            now: Date.now(),
            isValid: tokenData?.expiresAt > Date.now()
          });
          
          if (tokenData && tokenData.token && tokenData.expiresAt > Date.now()) {
            console.log(`✅ [KISProxy] Firestore 캐시된 토큰 재사용 (만료: ${new Date(tokenData.expiresAt).toISOString()})`);
            // 메모리 캐시에도 저장
            this.tokenCache = {
              token: tokenData.token,
              expiresAt: tokenData.expiresAt,
            };
            return tokenData.token;
          } else {
            console.log(`⚠️ [KISProxy] Firestore 토큰 만료됨 (새로 발급 필요)`);
          }
        } else {
          console.log(`⚠️ [KISProxy] Firestore 토큰 문서 없음 (새로 발급 필요)`);
        }
      } catch (e) {
        console.log(`⚠️ [KISProxy] Firestore 토큰 조회 실패 (새로 발급):`, e);
      }
      
      console.log(`🔐 [KISProxy] 새 토큰 발급 시작 (캐시 없음 또는 만료)`);
      
      const credentials = await this.getApiCredentials(uid);
      
      console.log(`🔐 [KISProxy] AppKey: ${credentials.appKey.substring(0, 10)}...`);
      
      const requestBody = {
        grant_type: 'client_credentials',
        appkey: credentials.appKey,
        appsecret: credentials.appSecret,
      };
      
      const response = await fetch('https://openapi.koreainvestment.com:9443/oauth2/tokenP', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(requestBody),
      });

      console.log(`🔐 [KISProxy] 응답 상태: ${response.status}`);
      
      const responseText = await response.text();

      if (!response.ok) {
        console.log(`❌ [KISProxy] 토큰 발급 실패:`, responseText);
        throw new Error(`토큰 발급 실패: ${response.status} - ${responseText}`);
      }

      const data = JSON.parse(responseText) as any;
      
      if (data.access_token) {
        // KIS API 토큰은 24시간 유효 (안전하게 23시간으로 설정)
        const expiresAt = Date.now() + 23 * 60 * 60 * 1000; // 23시간
        
        // 3. 메모리 캐싱
        this.tokenCache = {
          token: data.access_token,
          expiresAt: expiresAt,
        };
        
        // 4. Firestore 캐싱
        try {
          await admin.firestore()
            .collection('system')
            .doc('kis_token')
            .set({
              token: data.access_token,
              expiresAt: expiresAt,
              updatedAt: Date.now(),
              issuedAt: new Date().toISOString(),
            });
          console.log(`✅ [KISProxy] 토큰 발급 성공 (메모리 + Firestore 캐싱, 23시간 유효)`);
          console.log(`✅ [KISProxy] 토큰 만료 시각: ${new Date(expiresAt).toISOString()}`);
        } catch (e) {
          console.log(`⚠️ [KISProxy] Firestore 토큰 저장 실패 (메모리 캐시만 사용):`, e);
          console.log(`✅ [KISProxy] 토큰 발급 성공 (메모리 캐싱만, 23시간 유효)`);
        }
        
        return data.access_token;
      } else {
        throw new Error(`토큰 발급 실패: access_token 없음 - ${responseText}`);
      }
    } catch (error) {
      console.error('❌ KIS 토큰 발급 실패:', error);
      throw error;
    }
  }

  /**
   * 국내주식 현재가 조회
   */
  static async fetchCurrentPrice(symbol: string, uid?: string): Promise<any> {
    try {
      console.log(`🔍 KIS 현재가 조회 시작: ${symbol}`);
      
      const token = await this.getAccessToken(uid);
      const credentials = await this.getApiCredentials(uid);
      
      // 국내주식 판별 (5-6자리 숫자)
      const isDomestic = /^\d{5,6}$/.test(symbol);
      
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
          const errorText = await response.text();
          console.log(`❌ [KISProxy] 국내주식 현재가 조회 실패: ${response.status}`, errorText);
          throw new Error(`국내주식 현재가 조회 실패: ${response.status}`);
        }

        const data = await response.json() as any;
        console.log(`🔍 [KISProxy] 국내주식 현재가 API 응답:`, JSON.stringify(data).substring(0, 500));
        const output = data.output || {};
        console.log(`🔍 [KISProxy] output.stck_prpr: ${output.stck_prpr}, output.acml_vol: ${output.acml_vol}`);
        
        return {
          symbol,
          current_price: Number(output.stck_prpr) || 0,
          prev_close: Number(output.stck_prdy_clpr) || 0,
          open_price: Number(output.stck_oprc) || 0,
          high_price: Number(output.stck_hgpr) || 0,
          low_price: Number(output.stck_lwpr) || 0,
          volume: Number(output.acml_vol) || 0,
          trade_amount: Number(output.acc_trdval) || 0, // 누적 거래대금
          timestamp: Date.now(),
          market: 'KOSPI',
        };
      } else {
        // 해외주식 현재가 조회 (1호가 API) - exchangeCode 우선, 없으면 순회 폴백
        let exchangeCode: string | null = null;
        try {
          const metaSnap = await admin.firestore().collection('stocks').doc(symbol).get();
          exchangeCode = (metaSnap.data()?.meta?.exchangeCode || metaSnap.data()?.info?.meta?.exchangeCode || null) as string | null;
        } catch (_) {}

        const exchangeCandidates = exchangeCode ? [exchangeCode] : ['NAS','NYS','HKS'];

        let lastErrorText = '';
        let response: any = null;
        for (const ex of exchangeCandidates) {
          const tryResp = await fetch(`https://openapi.koreainvestment.com:9443/uapi/overseas-price/v1/quotations/inquire-asking-price?AUTH=&EXCD=${ex}&SYMB=${symbol}`, {
          method: 'GET',
          headers: {
            'Content-Type': 'application/json',
            'authorization': `Bearer ${token}`,
            'appkey': credentials.appKey,
            'appsecret': credentials.appSecret,
            'tr_id': 'HHDFS76200100', // 1호가 API TR_ID
          },
        });
          if (!tryResp.ok) {
            lastErrorText = await tryResp.text();
            console.log(`⚠️ [KISProxy] 해외 현재가 실패(${ex}): ${tryResp.status} ${lastErrorText.substring(0,300)}`);
            continue;
          }
          response = tryResp;
          exchangeCode = ex;
          break;
        }

        if (!response) {
          console.log(`❌ [KISProxy] 해외주식 현재가 조회 실패(전 거래소 실패): ${lastErrorText.substring(0,300)}`);
          throw new Error('해외주식 현재가 조회 실패: all exchanges');
        }

        const data = await response.json() as any;
        console.log(`🔍 [KISProxy] 해외주식 현재가 API 응답 (${symbol}):`, JSON.stringify(data).substring(0, 800));
        const output1 = data.output1 || {};
        console.log(`🔍 [KISProxy] output1 keys: ${Object.keys(output1).join(', ')}`);
        console.log(`🔍 [KISProxy] output1.last: ${output1.last}, output1.bidp: ${output1.bidp}, output1.askp: ${output1.askp}`);
        
        // 1호가 API의 경우 output1 (현재가), output2 (매수호가), output3 (매도호가) 사용
        const currentPrice = Number(output1.last) || Number(output1.bidp) || Number(output1.askp) || 0;
        const prevClose = Number(output1.base) || 0;
        // 메타에 exchangeCode 없으면 저장 보강
        try {
          const docRef = admin.firestore().collection('stocks').doc(symbol);
          await docRef.set({ meta: { exchangeCode, metaUpdated: new Date() } }, { merge: true });
        } catch (_) {}
        
        return {
          symbol,
          current_price: currentPrice,
          prev_close: prevClose,
          open_price: Number(output1.open) || 0,
          high_price: Number(output1.high) || 0,
          low_price: Number(output1.low) || 0,
          volume: Number(output1.tvol) || Number(output1.volume) || 0,
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
  static async fetchDailyChart(symbol: string, days: number = 100, uid?: string): Promise<any[]> {
    try {
      console.log(`🔍 KIS 차트 조회 시작: ${symbol}, days=${days}`);
      
      // 실제 KIS API 호출 시도
      const token = await this.getAccessToken(uid);
      const credentials = await this.getApiCredentials(uid);
      
      // 국내주식 판별 (5-6자리 숫자)
      const isDomestic = /^\d{5,6}$/.test(symbol);
      
      if (isDomestic) {
        // 국내주식 일봉 조회 (기간별시세 API)
        const response = await fetch(`https://openapi.koreainvestment.com:9443/uapi/domestic-stock/v1/quotations/inquire-daily-itemchartprice?FID_COND_MRKT_DIV_CODE=J&FID_INPUT_ISCD=${symbol}&FID_INPUT_DATE_1=${this.getDateString(-days)}&FID_INPUT_DATE_2=${this.getDateString(0)}&FID_PERIOD_DIV_CODE=D&FID_ORG_ADJ_PRC=0`, {
          method: 'GET',
          headers: {
            'Content-Type': 'application/json',
            'authorization': `Bearer ${token}`,
            'appkey': credentials.appKey,
            'appsecret': credentials.appSecret,
            'tr_id': 'FHKST03010100',
          },
        });

        if (!response.ok) {
          const errorText = await response.text();
          console.log(`❌ [KISProxy] 국내주식 차트 조회 실패: ${response.status}`, errorText);
          throw new Error(`국내주식 차트 조회 실패: ${response.status}`);
        }

        const data = await response.json() as any;
        console.log(`🔍 [KISProxy] 국내주식 차트 API 응답 (${symbol}):`, JSON.stringify(data).substring(0, 800));
        console.log(`🔍 [KISProxy] rt_cd: ${data.rt_cd}, msg_cd: ${data.msg_cd}, msg1: ${data.msg1}`);
        const items = data.output2 || [];
        console.log(`🔍 [KISProxy] 국내주식 차트 데이터 개수: ${items.length}`);
        
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
        // 해외주식 일봉 조회 (NASDAQ) - 최신 데이터 우선
        const response = await fetch(`https://openapi.koreainvestment.com:9443/uapi/overseas-price/v1/quotations/dailyprice?AUTH=&EXCD=NAS&SYMB=${symbol}&GUBN=0&BYMD=${this.getDateString(0)}&MODP=1`, {
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
          const errorText = await response.text();
          console.log(`❌ [KISProxy] 해외주식 차트 조회 실패: ${response.status}`, errorText);
          throw new Error(`해외주식 차트 조회 실패: ${response.status}`);
        }

        const data = await response.json() as any;
        console.log(`🔍 [KISProxy] 해외주식 차트 API 응답 (${symbol}):`, JSON.stringify(data).substring(0, 800));
        console.log(`🔍 [KISProxy] rt_cd: ${data.rt_cd}, msg_cd: ${data.msg_cd}, msg1: ${data.msg1}`);
        const items = data.output2 || [];
        console.log(`🔍 [KISProxy] 해외주식 차트 데이터 개수: ${items.length}`);
        
        // 첫 번째 아이템의 키들 확인
        if (items.length > 0) {
          console.log(`🔍 [KISProxy] 해외주식 차트 첫 번째 아이템 키들: ${Object.keys(items[0]).join(', ')}`);
          console.log(`🔍 [KISProxy] 해외주식 차트 첫 번째 아이템: ${JSON.stringify(items[0])}`);
        }
        
        return items.map((item: any) => ({
          date: item.xymd,
          date_ts: parseInt(item.xymd),
          open: Number(item.open) || 0,
          high: Number(item.high) || 0,
          low: Number(item.low) || 0,
          close: Number(item.clos || item.last) || 0,  // clos 우선, 없으면 last
          volume: Number(item.tvol) || 0,
          market: 'NASDAQ',
          stock_code: symbol,
        }));
      }
    } catch (error) {
      console.error(`❌ KIS 차트 조회 실패: ${symbol}`, error);
      return [];
    }
  }

  private static getDateString(daysOffset: number): string {
    const date = new Date();
    date.setDate(date.getDate() + daysOffset);
    return date.toISOString().slice(0, 10).replace(/-/g, '');
  }
}


