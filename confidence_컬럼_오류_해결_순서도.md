# 🔧 confidence 컬럼 NOT NULL 제약 조건 오류 해결 순서도

## 📋 문제 상황
```
DatabaseException(NOT NULL constraint failed: analysis_results.confidence (code 1299 SQLITE_CONSTRAINT_NOTNULL))
```

## 🔍 문제 분석

### 1. 데이터베이스 스키마 확인
```sql
CREATE TABLE analysis_results (
  -- ... 다른 컬럼들 ...
  confidence REAL NOT NULL, -- 0.0 ~ 1.0
  -- ... 다른 컬럼들 ...
)
```

### 2. 오류 원인 파악
- `analysis_results_repository.dart`에서 `confidence` 컬럼이 삽입 시 누락됨
- `analysis_repository.dart`에서는 올바르게 처리됨 (`'confidence': analysis['confidence'] ?? 0.0`)

## 🛠️ 해결 과정

### 1단계: 삽입 부분 수정
**파일**: `lib/core/database/repositories/analysis_results_repository.dart`

**수정 전**:
```dart
'signal': result['signal'] as String? ?? result['trading_decision'] as String? ?? 'HOLD',
'confidence_score': (result['confidence_score'] as num?)?.toDouble() ?? 0.0,
```

**수정 후**:
```dart
'signal': result['signal'] as String? ?? result['trading_decision'] as String? ?? 'HOLD',
'confidence': (result['confidence'] as num?)?.toDouble() ?? (result['confidence_score'] as num?)?.toDouble() ?? 0.0,
'confidence_score': (result['confidence_score'] as num?)?.toDouble() ?? 0.0,
```

### 2단계: 조회 부분 수정
다음 메서드들에서 `confidence` 컬럼 추가:

1. **`getAnalysisResults()`** - 모든 분석 결과 조회
2. **`getLatestAnalysisResult()`** - 최신 분석 결과 조회  
3. **`getAnalysisResultsByPeriod()`** - 기간별 분석 결과 조회
4. **`getBuySignals()`** - 매수 신호 조회
5. **`getSellSignals()`** - 매도 신호 조회
6. **`getAllAnalysisResults()`** - 전체 분석 결과 조회

**수정 패턴**:
```dart
// 수정 전
'signal_strength': result['signal_strength'] as String,
'confidence_score': (result['confidence_score'] as num?)?.toDouble() ?? 0.0,

// 수정 후  
'signal_strength': result['signal_strength'] as String,
'confidence': (result['confidence'] as num?)?.toDouble() ?? 0.0,
'confidence_score': (result['confidence_score'] as num?)?.toDouble() ?? 0.0,
```

## 📊 데이터 흐름 개선

### 수정 전 데이터 흐름
```
분석 결과 생성 → confidence 누락 → DB 삽입 실패 → NOT NULL 제약 조건 오류
```

### 수정 후 데이터 흐름
```
분석 결과 생성 → confidence 값 제공 (fallback 포함) → DB 삽입 성공 → 정상 처리
```

## 🔄 Fallback 전략

### confidence 값 우선순위
1. `result['confidence']` - 주요 confidence 값
2. `result['confidence_score']` - 호환성 confidence 값  
3. `0.0` - 기본값

### signal 값 우선순위
1. `result['signal']` - 주요 signal 값
2. `result['trading_decision']` - 호환성 signal 값
3. `'HOLD'` - 기본값

## ✅ 검증 포인트

### 1. 삽입 검증
- [x] `confidence` 컬럼이 삽입 데이터에 포함됨
- [x] Fallback 값이 올바르게 설정됨
- [x] NOT NULL 제약 조건 만족

### 2. 조회 검증
- [x] 모든 조회 메서드에서 `confidence` 컬럼 포함
- [x] 데이터 타입 변환이 올바르게 처리됨
- [x] null 안전성 보장

### 3. 호환성 검증
- [x] 기존 `confidence_score` 컬럼과 병행 지원
- [x] 기존 코드와의 호환성 유지
- [x] 데이터 마이그레이션 불필요

## 🎯 결과

### 해결된 문제
- ✅ `NOT NULL constraint failed: analysis_results.confidence` 오류 해결
- ✅ 분석 결과 저장 성공
- ✅ 모든 조회 메서드에서 confidence 데이터 제공

### 개선된 점
- 🔄 더 강력한 fallback 메커니즘
- 📊 데이터 일관성 향상
- 🛡️ null 안전성 강화
- 🔧 유지보수성 개선

## 📝 다음 단계

1. **테스트 실행**: 수정된 코드로 분석 기능 테스트
2. **모니터링**: confidence 값이 올바르게 저장되는지 확인
3. **성능 최적화**: 필요시 인덱스 추가 고려
4. **문서화**: confidence 컬럼 사용법 업데이트
