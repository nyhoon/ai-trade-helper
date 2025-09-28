# Functions 통합 리팩토링 계획

## 🔍 현재 문제점

### 1. 복잡한 Functions 구조
```
현재 Functions:
├── ensure_chart_and_analyze (차트 + 분석)
├── getDailyChart (차트 조회)
├── getCurrentPrice (현재가 조회)
├── analyzeStock (분석)
└── 기타 여러 Functions...
```

### 2. 중복 데이터 문제
```
Firestore 구조 (현재):
├── charts/{symbol}/daily/{date} (차트 데이터)
├── prices/{symbol} (현재가 데이터)
├── users/{uid}/analysis/{symbol} (분석 데이터)
└── 기타 여러 컬렉션...
```

### 3. 비효율적인 호출
- 거래탭: `getCurrentPrice()` → `getDailyChart()` → `analyzeStock()`
- 분석탭: `ensure_chart_and_analyze()` → `getCurrentPrice()`
- 추천탭: `getDailyChart()` → `analyzeStock()`

## 🚀 통합 방안

### 1. 단일 통합 Functions
```typescript
// 새로운 통합 Functions
export const getStockData = functions.https.onCall(async (data, context) => {
  const { symbol, uid } = data;
  
  // 1. 종목 기본 정보 조회/생성
  const stockInfo = await getOrCreateStockInfo(symbol);
  
  // 2. 차트 데이터 조회/업데이트
  const chartData = await ensureChartData(symbol);
  
  // 3. 현재가 데이터 조회/업데이트
  const currentPrice = await getCurrentPrice(symbol);
  
  // 4. 분석 데이터 계산/업데이트
  const analysis = await calculateAnalysis(symbol, chartData, currentPrice);
  
  // 5. 통합 데이터 반환
  return {
    symbol,
    stockInfo,
    chartData,
    currentPrice,
    analysis,
    lastUpdated: new Date().toISOString()
  };
});
```

### 2. 통합 Firestore 구조
```
새로운 구조:
stocks/{symbol}/
├── info (종목 기본 정보)
├── chart (차트 데이터 - 배열)
├── current (현재가 정보)
├── analysis (분석 결과)
└── metadata (업데이트 시간 등)
```

### 3. 클라이언트 호출 단순화
```dart
// 기존 (복잡한 호출)
final priceData = await RemoteKisService.instance.getCurrentPrice(symbol);
final chartData = await RemoteKisService.instance.getDailyChart(symbol);
final analysis = await RemoteKisService.instance.analyzeStock(symbol);

// 새로운 (단일 호출)
final stockData = await RemoteKisService.instance.getStockData(symbol);
final priceData = stockData['currentPrice'];
final chartData = stockData['chartData'];
final analysis = stockData['analysis'];
```

## 🔧 구현 계획

### 1단계: 새로운 통합 Functions 구현
```typescript
// functions/src/stock_data_service.ts
export class StockDataService {
  static async getStockData(symbol: string, uid: string) {
    try {
      console.log(`📊 통합 종목 데이터 조회: ${symbol}`);
      
      // 1. 종목 기본 정보
      const stockInfo = await this.getStockInfo(symbol);
      
      // 2. 차트 데이터 (최신 100일)
      const chartData = await this.ensureChartData(symbol);
      
      // 3. 현재가 데이터
      const currentPrice = await this.getCurrentPrice(symbol);
      
      // 4. 분석 데이터
      const analysis = await this.calculateAnalysis(symbol, chartData, currentPrice);
      
      // 5. 통합 데이터 저장
      await this.saveIntegratedData(symbol, {
        stockInfo,
        chartData,
        currentPrice,
        analysis,
        lastUpdated: new Date()
      });
      
      return {
        success: true,
        data: {
          symbol,
          stockInfo,
          chartData,
          currentPrice,
          analysis
        }
      };
      
    } catch (error) {
      console.error(`❌ 통합 종목 데이터 조회 실패: ${symbol}`, error);
      return { success: false, error: error.message };
    }
  }
}
```

### 2단계: Firestore 구조 통합
```typescript
// 통합 데이터 저장
async saveIntegratedData(symbol: string, data: any) {
  const db = admin.firestore();
  const stockRef = db.collection('stocks').doc(symbol);
  
  await stockRef.set({
    info: data.stockInfo,
    chart: data.chartData,
    current: data.currentPrice,
    analysis: data.analysis,
    metadata: {
      lastUpdated: data.lastUpdated,
      version: '2.0'
    }
  }, { merge: true });
}
```

### 3단계: 클라이언트 서비스 통합
```dart
// lib/core/services/integrated_stock_service.dart
class IntegratedStockService {
  static Future<Map<String, dynamic>?> getStockData(String symbol) async {
    try {
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('getStockData');
      
      final result = await callable.call({
        'symbol': symbol,
        'uid': FirebaseAuth.instance.currentUser?.uid ?? 'debug-user',
      });
      
      if (result.data['success'] == true) {
        return result.data['data'];
      } else {
        print('❌ 통합 종목 데이터 조회 실패: ${result.data['error']}');
        return null;
      }
    } catch (e) {
      print('❌ 통합 종목 데이터 조회 실패: $e');
      return null;
    }
  }
}
```

### 4단계: 기존 코드 마이그레이션
```dart
// 거래탭에서 사용
final stockData = await IntegratedStockService.getStockData('005930');
if (stockData != null) {
  final currentPrice = stockData['currentPrice'];
  final chartData = stockData['chartData'];
  final analysis = stockData['analysis'];
  
  // UI 업데이트
  setState(() {
    _currentPrice = currentPrice['currentPrice'];
    _volume = chartData.last['volume'];
    _analysis = analysis;
  });
}
```

## 📊 예상 효과

### 1. 성능 개선
- **API 호출 횟수**: 3-4회 → 1회
- **응답 시간**: 3-5초 → 1-2초
- **데이터 일관성**: 100% 보장

### 2. 코드 단순화
- **복잡한 호출 로직** → **단일 호출**
- **중복 데이터 처리** → **통합 데이터**
- **에러 처리** → **중앙화된 에러 처리**

### 3. 유지보수성 향상
- **단일 Functions** 관리
- **통합된 데이터 구조**
- **일관된 API 인터페이스**

## 🚀 구현 순서

### 1단계: 새로운 Functions 구현
- [ ] `StockDataService` 클래스 구현
- [ ] 통합 데이터 조회 로직
- [ ] Firestore 통합 구조 설계

### 2단계: 클라이언트 서비스 구현
- [ ] `IntegratedStockService` 구현
- [ ] 기존 서비스와 호환성 유지
- [ ] 점진적 마이그레이션

### 3단계: 기존 코드 마이그레이션
- [ ] 거래탭 마이그레이션
- [ ] 분석탭 마이그레이션
- [ ] 추천탭 마이그레이션

### 4단계: 기존 Functions 정리
- [ ] 사용하지 않는 Functions 제거
- [ ] 중복 데이터 정리
- [ ] 성능 최적화

## ⚠️ 주의사항

1. **점진적 마이그레이션**: 기존 기능 유지하면서 점진적으로 전환
2. **데이터 호환성**: 기존 데이터 구조와 호환성 유지
3. **에러 처리**: 통합 Functions의 에러 처리 강화
4. **성능 모니터링**: 새로운 구조의 성능 지속적 모니터링

## 🎯 최종 목표

**단일 호출로 모든 종목 정보 획득:**
```dart
final stockData = await IntegratedStockService.getStockData('005930');
// stockData에는 차트, 현재가, 분석, 기본정보가 모두 포함
```

이렇게 하면 Functions가 깔끔해지고, 중복 데이터도 없어지고, 클라이언트 코드도 훨씬 간단해질 것 같습니다!
