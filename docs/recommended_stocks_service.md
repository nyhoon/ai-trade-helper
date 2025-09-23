# 추천종목 서비스 (Recommended Stocks Service)

## 개요

추천종목 서비스는 트레이딩 앱에서 사용할 수 있는 추천종목들을 관리하는 시스템입니다. 미국 주식(NASDAQ, NYSE)과 한국 주식(KOSPI, KOSDAQ)을 모두 지원하며, MVI 패턴과 클린아키텍처 원칙을 준수하여 설계되었습니다.

## 아키텍처

### MVI 패턴 적용

```
Intent (사용자 액션) → Model (상태 변경) → View (UI 렌더링)
    ↓                      ↓                    ↓
Action (추가/제거/검색) → Change (데이터 변경) → ViewState (화면 상태)
    ↓                      ↓                    ↓
SideEffect (네비게이션, 알림) → Reducer (상태 변환) → UI 업데이트
```

### 클린아키텍처 계층 구조

```
Presentation Layer (UI)
    ↓
Domain Layer (UseCase)
    ↓
Data Layer (Repository + Data Source)
    ↓
Infrastructure Layer (Database, SharedPreferences)
```

## 주요 구성 요소

### 1. RecommendedStocksData (Data Layer)
- **위치**: `lib/core/data/recommended_stocks_data.dart`
- **역할**: 추천종목 데이터의 메모리 관리 및 SharedPreferences 저장
- **특징**: 
  - 싱글톤 패턴으로 구현
  - 기본 추천종목 데이터 포함 (미국 150개, 한국 200개)
  - 시장별 분류 (US/KR) 자동 감지

### 2. RecommendedStocksUseCase (Domain Layer)
- **위치**: `lib/core/trading/usecases/recommended_stocks_usecase.dart`
- **역할**: 비즈니스 로직 처리 및 데이터 유효성 검증
- **기능**:
  - 추천종목 CRUD 작업
  - 데이터 검증 및 정제
  - 에러 처리 및 예외 상황 관리

### 3. RecommendedStocksRepository (Data Layer)
- **위치**: `lib/core/database/repositories/recommended_stocks_repository.dart`
- **역할**: 데이터베이스 연동 및 영구 저장소 관리
- **특징**:
  - SQLite 데이터베이스 사용
  - 트랜잭션 지원
  - 메모리와 데이터베이스 동기화

### 4. RecommendedStocksService (Service Layer)
- **위치**: `lib/core/services/recommended_stocks_service.dart`
- **역할**: 전체 시스템의 조율 및 비즈니스 로직 통합
- **기능**:
  - 서비스 초기화 및 상태 관리
  - 데이터 동기화 및 백업/복원
  - 에러 처리 및 로깅

### 5. RecommendedStocksScreen (Presentation Layer)
- **위치**: `lib/features/trading/recommended_stocks_screen.dart`
- **역할**: 사용자 인터페이스 및 상호작용
- **기능**:
  - 추천종목 목록 표시
  - 검색 및 필터링
  - 종목 추가/제거
  - 시장별 분류 표시

## 기본 추천종목 데이터

### 미국 주식 (150개)
- **기술주**: AAPL, MSFT, GOOGL, TSLA, NVDA, META, AMZN
- **바이오**: GILD, REGN, BIIB, VRTX, ALNY, SRPT
- **금융**: ADP, FICO, JKHY, VRSK, GPN
- **소비재**: COST, PEP, SBUX, LULU, CMG
- **에너지**: EOG, APA, GPOR, XEL, AEP

### 한국 주식 (200개)
- **KOSPI (150개)**:
  - 대형주: 삼성전자, SK하이닉스, NAVER, 삼성바이오로직스
  - 자동차: 현대차, 기아, 현대모비스
  - 화학: LG화학, 롯데케미칼, SK
  - 금융: KB금융, 신한지주, 삼성증권

- **KOSDAQ (50개)**:
  - IT: 카카오, 엔씨소프트, 컴투스, 위메이드
  - 바이오: 셀트리온헬스케어, 셀트리온제약, 유니테스트
  - 게임: 넥슨코리아, 넥슨, 컴투스

## 주요 기능

### 1. 추천종목 관리
- **추가**: 새로운 종목을 추천종목 목록에 추가
- **제거**: 기존 종목을 추천종목 목록에서 제거
- **수정**: 종목명 수정 및 업데이트
- **일괄 처리**: 여러 종목을 한 번에 추가/제거

### 2. 검색 및 필터링
- **전문 검색**: 종목 심볼 또는 이름으로 검색
- **시장별 필터**: 미국/한국 주식 분류
- **실시간 검색**: 타이핑 시 실시간 결과 표시

### 3. 데이터 동기화
- **메모리 ↔ 데이터베이스**: 자동 동기화
- **백업/복원**: 데이터 백업 및 복원 기능
- **상태 모니터링**: 동기화 상태 확인

### 4. 통계 및 분석
- **종목 개수**: 전체/미국/한국별 종목 수
- **업데이트 이력**: 마지막 수정 시간 추적
- **시장별 분포**: 각 시장의 종목 비율

## 사용 방법

### 1. 서비스 초기화
```dart
final service = RecommendedStocksService();
await service.initialize();
```

### 2. 추천종목 조회
```dart
// 전체 조회
final allStocks = await service.getAllRecommendedStocks();

// 시장별 조회
final usStocks = await service.getRecommendedStocksByMarket('us');
final krStocks = await service.getRecommendedStocksByMarket('korea');
```

### 3. 추천종목 추가
```dart
final success = await service.addRecommendedStock('AAPL', 'Apple Inc');
```

### 4. 추천종목 검색
```dart
final results = await service.searchRecommendedStocks('Apple');
```

### 5. 통계 정보 조회
```dart
final stats = await service.getRecommendedStocksStatistics();
print('전체: ${stats['total']}개');
print('미국: ${stats['us']}개');
print('한국: ${stats['korea']}개');
```

## 데이터 구조

### 메모리 데이터 구조
```dart
Map<String, String> stocks = {
  'AAPL': 'Apple Inc',
  '005930': '삼성전자',
  // ... 더 많은 종목들
};
```

### 데이터베이스 테이블 구조
```sql
CREATE TABLE recommended_stocks (
  symbol TEXT PRIMARY KEY,           -- 종목 심볼
  name TEXT NOT NULL,                -- 종목명
  market TEXT NOT NULL,              -- 시장 (US/KR)
  added_date TEXT NOT NULL,          -- 추가 날짜
  last_updated TEXT NOT NULL,        -- 마지막 수정 날짜
  is_active INTEGER DEFAULT 1        -- 활성 상태
);
```

## 에러 처리

### 1. 데이터 유효성 검증
- **빈 값 검사**: 심볼과 이름이 비어있지 않은지 확인
- **형식 검사**: 한국 주식은 6자리 숫자, 미국 주식은 알파벳 조합
- **중복 검사**: 이미 존재하는 심볼인지 확인

### 2. 예외 상황 처리
- **네트워크 오류**: 오프라인 상태에서도 로컬 데이터 사용
- **데이터베이스 오류**: 메모리 데이터로 폴백
- **저장소 오류**: SharedPreferences 실패 시 메모리만 사용

### 3. 사용자 피드백
- **성공 메시지**: 작업 완료 시 확인 메시지
- **에러 메시지**: 실패 시 구체적인 에러 내용 표시
- **로딩 표시**: 데이터 처리 중 진행 상태 표시

## 성능 최적화

### 1. 메모리 관리
- **지연 로딩**: 필요할 때만 데이터 로드
- **캐싱**: 자주 사용되는 데이터 메모리에 유지
- **가비지 컬렉션**: 불필요한 객체 자동 정리

### 2. 데이터베이스 최적화
- **인덱스**: 심볼과 시장별 인덱스 생성
- **트랜잭션**: 일괄 작업 시 트랜잭션 사용
- **쿼리 최적화**: 효율적인 SQL 쿼리 작성

### 3. UI 성능
- **ListView.builder**: 대량 데이터 효율적 렌더링
- **상태 관리**: 불필요한 리빌드 방지
- **비동기 처리**: UI 블로킹 방지

## 확장성

### 1. 새로운 시장 추가
- **유럽 시장**: EU, UK 등 추가 가능
- **아시아 시장**: 일본, 중국 등 추가 가능
- **신흥 시장**: 인도, 브라질 등 추가 가능

### 2. 추가 기능
- **분류 시스템**: 섹터별, 업종별 분류
- **랭킹 시스템**: 인기도, 거래량 기반 랭킹
- **알림 시스템**: 특정 종목 추가/제거 시 알림

### 3. 데이터 소스 확장
- **API 연동**: 실시간 시장 데이터 연동
- **외부 파일**: CSV, Excel 파일에서 데이터 가져오기
- **클라우드 동기화**: 여러 기기 간 데이터 동기화

## 테스트

### 1. 단위 테스트
- **UseCase 테스트**: 비즈니스 로직 검증
- **Repository 테스트**: 데이터 접근 계층 검증
- **Service 테스트**: 서비스 통합 검증

### 2. 통합 테스트
- **데이터 흐름 테스트**: 전체 시스템 데이터 흐름 검증
- **에러 처리 테스트**: 예외 상황 처리 검증
- **성능 테스트**: 대량 데이터 처리 성능 검증

### 3. UI 테스트
- **위젯 테스트**: 개별 UI 컴포넌트 검증
- **통합 UI 테스트**: 전체 화면 동작 검증
- **사용자 시나리오 테스트**: 실제 사용 시나리오 검증

## 결론

추천종목 서비스는 MVI 패턴과 클린아키텍처 원칙을 준수하여 설계된 견고하고 확장 가능한 시스템입니다. 사용자 친화적인 인터페이스와 함께 강력한 데이터 관리 기능을 제공하며, 향후 다양한 시장과 기능을 추가할 수 있는 유연한 구조를 가지고 있습니다.

이 서비스를 통해 트레이딩 앱 사용자들은 효율적으로 추천종목을 관리하고, 시장별로 분류된 종목 정보를 쉽게 찾아볼 수 있습니다.
