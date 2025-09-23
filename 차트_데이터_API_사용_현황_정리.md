# 📊 차트 데이터 API 사용 현황 정리

## 🎯 목적
PLTZ(나스닥) 종목의 차트 데이터가 제대로 로딩되지 않는 문제를 해결하기 위해 앱 전체의 차트 데이터 API 사용 현황을 정리

---

## 📋 차트 데이터 API 호출 위치별 정리

| **위치** | **파일** | **함수/메소드** | **국내 API** | **해외 API** | **용도** | **문제점** |
|---------|---------|---------------|------------|------------|---------|-----------|
| **1. 스플래시 화면** | `splash_screen.dart` | `_loadChartDataForStock()` | ❌ 없음 | `getDailyChart()` (통합) | 초기 차트 데이터 로딩 | ✅ 통합 API 사용 |
| **2. 분석탭 데이터 로딩** | `unified_stock_data_manager.dart` | `_getChartData()` | `getDomesticDailyChart()` | `getOverseasDailyChart()` (분리) | 분석탭 진입 시 차트 조회 | ⚠️ 직접 분리 호출 |
| **3. 자동매매 분석** | `auto_trading_cycle.dart` | 자동매매 루프 | ❌ 없음 | `getDailyChart()` (통합) | 자동매매 시 차트 분석 | ✅ 통합 API 사용 |
| **4. 실시간 업데이트** | `realtime_update_service.dart` | `_updateChartData()` | `loadStockData()` (간접) | `loadStockData()` (간접) | 실시간 차트 업데이트 | ⚠️ 간접 호출 |
| **5. 통합 분석 서비스** | `unified_analysis_service.dart` | `_getTechnicalIndicators()` | `getDomesticDailyChart()` | `getOverseasDailyChart()` (분리) | 기술적 지표 계산 | ⚠️ 직접 분리 호출 |
| **6. AI 추천 서비스** | `ai_recommendation_service.dart` | `_collectChartDataForStock()` | `_fetchDomesticDailyChartData()` | `getOverseasDailyChart()` (분리) | AI 추천 종목 데이터 수집 | ⚠️ 직접 분리 호출 |
| **7. 증분 데이터 매니저** | `incremental_data_manager.dart` | `_loadChartDataForStock()` | `getDomesticDailyChart()` | `getOverseasDailyChart()` (분리) | 증분 데이터 업데이트 | ⚠️ 직접 분리 호출 |

---

## 🔍 API 호출 방식 분석

### ✅ **통합 API 사용 (권장)**
```dart
// 자동으로 국내/해외 판별하여 적절한 API 호출
chartData = await unifiedApiService.getDailyChart(stockCode, count: 60);
```
**사용 위치**: 스플래시 화면, 자동매매 시스템

### ⚠️ **분리 API 직접 호출 (문제 원인)**
```dart
// 국내/해외를 수동으로 판별하여 각각 다른 API 호출
if (_isNasdaqStock(stockCode)) {
  apiData = await _unifiedApiService.getOverseasDailyChart(
    symbol: stockCode,
    exchangeCode: 'NAS',  // 👈 하드코딩된 exchangeCode
    count: 100,
  );
} else {
  apiData = await _unifiedApiService.getDomesticDailyChart(
    stockCode: stockCode,
    count: 100,
  );
}
```
**문제점**: `exchangeCode` 하드코딩, 일관성 부족

---

## 🎯 주요 문제점

### **1. API 호출 방식의 일관성 부족**
- **스플래시**: `getDailyChart()` (통합) ✅
- **분석탭**: `getOverseasDailyChart()` (분리) ❌
- **자동매매**: `getDailyChart()` (통합) ✅

### **2. ExchangeCode 하드코딩**
```dart
exchangeCode: 'NAS'  // 👈 PLTZ는 실제로 다른 exchangeCode가 필요할 수 있음
```

### **3. 로그 분석 결과**
- **국내 종목**: 완벽한 차트 데이터 + 기술적 지표
- **PLTZ**: `technicalData` 모든 값이 null

---

## 🔧 해결 방안

### **1단계: 분석탭 API 통합화**
`unified_stock_data_manager.dart`의 `_getChartData()` 함수를 통합 API로 변경:

```dart
// 변경 전 (분리)
if (_isNasdaqStock(stockCode)) {
  apiData = await _unifiedApiService.getOverseasDailyChart(...);
} else {
  apiData = await _unifiedApiService.getDomesticDailyChart(...);
}

// 변경 후 (통합)
apiData = await _unifiedApiService.getDailyChart(stockCode, count: 100);
```

### **2단계: unified_analysis_service.dart 통합화**
기술적 지표 계산에서도 통합 API 사용

### **3단계: 모든 분리 호출 제거**
앱 전체에서 분리된 API 호출을 통합 API로 교체

---

## 📊 현재 PLTZ 문제 상황

### **로그 분석**
```
🔍 [PLTZ Debug] technicalData 내용:
  - currentVolume: 0
  - avgVolume: null  
  - volumeHistory length: 0
  - volume from API: 0
```

### **원인 추정**
1. **분석탭에서 `getOverseasDailyChart()` 직접 호출**
2. **`exchangeCode: 'NAS'` 하드코딩으로 인한 PLTZ 데이터 미스매치**
3. **통합 API의 자동 판별 로직 미사용**

---

## ✅ 즉시 실행할 수정사항

1. `unified_stock_data_manager.dart` → 통합 API 사용
2. `unified_analysis_service.dart` → 통합 API 사용  
3. `ai_recommendation_service.dart` → 통합 API 사용
4. `incremental_data_manager.dart` → 통합 API 사용

**목표**: 모든 곳에서 `getDailyChart()` 통합 API만 사용하여 일관성 확보
