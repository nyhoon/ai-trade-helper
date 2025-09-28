# Firebase Functions NOT_FOUND 오류 해결 순서도

## 🔍 문제 분석

### 현재 상황
- Firebase Functions는 정상 배포됨 (asia-northeast3 리전)
- 배포된 함수: `ensureChartAndAnalyze`, `getStockData`, `getMultipleStockData`, `refreshStockData`, `getStockDataStatus`
- 오류 발생: `[firebase_functions/not-found] NOT_FOUND`

### 문제 원인
1. **함수 시그니처 불일치**: `ensureChartAndAnalyze` 함수가 `uid` 파라미터를 받지 않음
2. **존재하지 않는 함수 호출**: `getCurrentPrice` 함수가 배포되지 않음
3. **함수 매개변수 불일치**: 클라이언트와 서버 간 파라미터 구조 차이

## 🛠️ 해결 방안

### 1단계: 함수 시그니처 수정
```typescript
// functions/src/index.ts 수정
export const ensureChartAndAnalyze = functions.https.onCall({
  region: 'asia-northeast3'
}, async (data: any, context: any) => {
  try {
    const { symbol, uid, market } = data; // uid 파라미터 추가
    
    if (!symbol) {
      return { success: false, error: 'symbol is required' };
    }
    
    if (!uid) {
      return { success: false, error: 'uid is required' };
    }
    
    console.log(`📊 차트 데이터 생성 및 분석 요청: ${symbol} (uid: ${uid}, market: ${market})`);
    
    // StockDataService 호출 시 uid 전달
    const result = await StockDataService.ensureChartAndAnalyze(symbol, uid, market);
    
    return {
      success: true,
      data: result
    };
  } catch (error) {
    console.error('❌ 차트 데이터 생성 및 분석 실패:', error);
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
});
```

### 2단계: getCurrentPrice 함수 추가
```typescript
// functions/src/index.ts에 추가
export const getCurrentPrice = functions.https.onCall({
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
    
    console.log(`💰 현재가 조회 요청: ${symbol} (uid: ${uid})`);
    
    const result = await StockDataService.getCurrentPrice(symbol, uid);
    
    return {
      success: true,
      data: result
    };
  } catch (error) {
    console.error('❌ 현재가 조회 실패:', error);
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
});
```

### 3단계: StockDataService 메서드 추가
```typescript
// functions/src/stock_data_service.ts에 추가
export class StockDataService {
  // ... 기존 메서드들 ...
  
  /**
   * 현재가 데이터 조회
   */
  static async getCurrentPrice(symbol: string, uid: string) {
    try {
      console.log(`💰 현재가 데이터 조회 시작: ${symbol}`);
      
      // KIS API를 통한 현재가 조회
      const kisProxy = new KISProxy();
      const currentPriceData = await kisProxy.getCurrentPrice(symbol);
      
      if (currentPriceData) {
        // Firestore에 저장
        await this.saveCurrentPriceData(symbol, currentPriceData, uid);
        
        return {
          success: true,
          data: currentPriceData
        };
      } else {
        return {
          success: false,
          error: '현재가 데이터를 가져올 수 없습니다.'
        };
      }
    } catch (error) {
      console.error(`❌ 현재가 데이터 조회 실패: ${symbol}`, error);
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error'
      };
    }
  }
  
  /**
   * 차트 데이터 생성 및 분석 (uid 파라미터 추가)
   */
  static async ensureChartAndAnalyze(symbol: string, uid: string, market: string = 'NASDAQ') {
    try {
      console.log(`📊 차트 데이터 생성 및 분석 시작: ${symbol} (uid: ${uid}, market: ${market})`);
      
      // 1. 차트 데이터 생성
      const chartData = await this.ensureChartData(symbol);
      
      // 2. 분석 데이터 계산
      const analysis = await this.calculateAnalysis(symbol, chartData, null, uid);
      
      // 3. 결과 저장
      await this.saveAnalysisData(symbol, analysis, uid);
      
      return {
        success: true,
        data: {
          chartData,
          analysis,
          lastUpdated: new Date().toISOString()
        }
      };
    } catch (error) {
      console.error(`❌ 차트 데이터 생성 및 분석 실패: ${symbol}`, error);
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error'
      };
    }
  }
}
```

## 🚀 배포 및 테스트

### 1. Firebase Functions 재배포
```bash
cd functions
firebase deploy --only functions
```

### 2. 함수 목록 확인
```bash
firebase functions:list
```

### 3. 로그 확인
```bash
firebase functions:log
```

## 📋 검증 체크리스트

- [ ] `ensureChartAndAnalyze` 함수에 `uid` 파라미터 추가
- [ ] `getCurrentPrice` 함수 추가 및 배포
- [ ] `StockDataService`에 `getCurrentPrice` 메서드 구현
- [ ] `StockDataService.ensureChartAndAnalyze`에 `uid` 파라미터 추가
- [ ] Firebase Functions 재배포
- [ ] 클라이언트에서 함수 호출 테스트
- [ ] 오류 로그 확인 및 해결

## 🎯 예상 결과

수정 후 다음과 같은 결과를 기대할 수 있습니다:

1. **NOT_FOUND 오류 해결**: 모든 함수가 정상적으로 호출됨
2. **현재가 조회 성공**: `getCurrentPrice` 함수를 통한 정상적인 현재가 조회
3. **차트 분석 성공**: `ensureChartAndAnalyze` 함수를 통한 정상적인 차트 데이터 생성 및 분석
4. **앱 초기화 성공**: 스플래시 화면에서 필수 데이터 로딩 완료

## 🔧 추가 개선사항

1. **에러 핸들링 강화**: 더 구체적인 오류 메시지 제공
2. **로깅 개선**: 디버깅을 위한 상세한 로그 추가
3. **성능 최적화**: 함수 호출 최적화 및 캐싱 전략
4. **모니터링**: Firebase Functions 모니터링 및 알림 설정
