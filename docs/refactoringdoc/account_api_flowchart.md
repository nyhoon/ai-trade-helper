# 계좌 API 데이터 흐름도

## 📊 계좌 API 구조 시각화

### 🏗️ 전체 API 구조도

```mermaid
graph TB
    A[KisUnifiedApiService<br/>메인 API 서비스] --> B[KisUnifiedApiServiceAccount<br/>계좌 전용 확장]
    A --> C[KisUnifiedApiServiceExtensions<br/>편의성 확장]
    A --> D[KisUnifiedApiServiceOrders<br/>주문 관련 확장]
    A --> E[KisUnifiedApiServiceCharts<br/>차트 관련 확장]
    A --> F[KisUnifiedApiServiceMarket<br/>시장 데이터 확장]
    A --> G[KisUnifiedApiServiceWebSocket<br/>WebSocket 확장]
    
    B --> H[국내 계좌 API]
    B --> I[해외 계좌 API]
    B --> J[주문가능금액 API]
    B --> K[거래 내역 API]
    
    C --> L[통합 계좌 정보]
    C --> M[호환성 메서드]
    C --> N[편의성 함수]
```

### 🔄 계좌 데이터 흐름도

```mermaid
sequenceDiagram
    participant UI as 사용자 인터페이스
    participant UC as UseCase
    participant API as KisUnifiedApiService
    participant ACC as Account Extension
    participant EXT as Extensions
    participant KIS as KIS API 서버
    
    UI->>UC: 계좌 정보 요청
    UC->>API: getDomesticAccountBalance()
    API->>ACC: 국내 계좌 잔고 조회
    ACC->>KIS: /uapi/domestic-stock/v1/trading/inquire-balance
    KIS-->>ACC: 국내 계좌 데이터
    ACC-->>API: 국내 계좌 정보
    API-->>UC: 국내 계좌 정보
    
    UC->>API: getOverseasAccountBalance()
    API->>ACC: 해외 계좌 잔고 조회
    ACC->>KIS: /uapi/overseas-stock/v1/trading/inquire-balance
    KIS-->>ACC: 해외 계좌 데이터
    ACC-->>API: 해외 계좌 정보
    API-->>UC: 해외 계좌 정보
    
    UC->>API: getUnifiedAccountInfo()
    API->>EXT: 통합 계좌 정보 조회
    EXT->>API: 국내 + 해외 계좌 통합
    API-->>UC: 통합 계좌 정보
    UC-->>UI: 최종 계좌 정보 표시
```

### 📋 계좌 API 분류도

```mermaid
mindmap
  root((계좌 API))
    국내 계좌
      잔고 조회
        getDomesticAccountBalance
        TR ID: TTTC8434R
        응답: output1, output2
      주문가능금액
        getDomesticOrderableAmount
        TR ID: TTTC8908R
        응답: output
    해외 계좌
      잔고 조회
        getOverseasAccountBalance
        TR ID: TTTS3012R
        응답: output1, output2
      주문가능금액
        getOverseasOrderableAmount
        TR ID: TTTS3007R
        응답: output
      결제기준잔고
        getOverseasPaymentStandardBalance
        TR ID: TTTS3012R
        응답: output2
      현재잔고
        getOverseasPresentBalance
        TR ID: TTTS3012R
        응답: output1
    거래 내역
      체결내역
        getOverseasExecutions
        TR ID: TTTS3015R
        응답: output1
      기간별 거래내역
        getOverseasPeriodTransactions
        TR ID: TTTS3016R
        응답: output1
    호환성 메서드
      보유종목
        getPositionsCompat
        getOverseasHoldingsCompat
      체결내역
        getOverseasExecutionsCompat
      결제준비금
        getOverseasPaymentStandardBalanceCompat
```

### 🔧 에러 처리 및 재시도 로직

```mermaid
flowchart TD
    A[API 호출 시작] --> B{토큰 유효성 확인}
    B -->|유효| C[API 요청 실행]
    B -->|만료| D[토큰 갱신]
    D --> C
    
    C --> E{응답 상태 확인}
    E -->|성공| F[데이터 반환]
    E -->|500 오류| G{재시도 횟수 확인}
    E -->|토큰 만료| H[토큰 갱신 후 재시도]
    E -->|기타 오류| I[에러 로그 및 null 반환]
    
    G -->|재시도 가능| J[2초 대기]
    J --> C
    G -->|재시도 불가| I
    
    H --> C
    
    F --> K[로깅 및 완료]
    I --> K
```

### 📊 데이터 구조도

```mermaid
erDiagram
    DOMESTIC_ACCOUNT {
        string cano "계좌번호 앞8자리"
        string acnt_prdt_cd "계좌번호 뒤2자리"
        array holdings "보유종목 목록"
        array account_info "계좌 정보"
    }
    
    OVERSEAS_ACCOUNT {
        string cano "계좌번호 앞8자리"
        string acnt_prdt_cd "계좌번호 뒤2자리"
        string ovrs_excg_cd "해외거래소코드"
        string tr_crcy_cd "거래통화코드"
        array holdings "보유종목 목록"
        array cash_balance "현금잔고"
    }
    
    HOLDING {
        string pdno "종목코드"
        string prdt_name "종목명"
        int hldg_qty "보유수량"
        double prpr "현재가"
        double evlu_amt "평가금액"
        double evlu_pfls_amt "평가손익"
        double evlu_pfls_rt "평가손익률"
    }
    
    ORDERABLE_AMOUNT {
        double nrcvb_buy_amt "주문가능금액"
        double ord_psbl_cash "주문가능현금"
        double ord_psbl_sbst "주문가능대용"
        double ord_psbl_loan "주문가능대출"
    }
    
    DOMESTIC_ACCOUNT ||--o{ HOLDING : contains
    OVERSEAS_ACCOUNT ||--o{ HOLDING : contains
    DOMESTIC_ACCOUNT ||--|| ORDERABLE_AMOUNT : has
    OVERSEAS_ACCOUNT ||--|| ORDERABLE_AMOUNT : has
```

### 🚀 성능 최적화 전략

```mermaid
graph LR
    A[API 호출] --> B{캐시 확인}
    B -->|캐시 있음| C[캐시 데이터 반환]
    B -->|캐시 없음| D[API 서버 요청]
    D --> E{응답 성공?}
    E -->|성공| F[데이터 캐싱]
    E -->|실패| G{재시도 가능?}
    G -->|가능| H[재시도]
    G -->|불가능| I[에러 반환]
    H --> D
    F --> J[데이터 반환]
    C --> J
    I --> K[로깅]
    J --> L[UI 업데이트]
```

### 📈 모니터링 및 로깅

```mermaid
graph TB
    A[API 호출] --> B[요청 로깅]
    B --> C[타이머 시작]
    C --> D[API 실행]
    D --> E[응답 로깅]
    E --> F[타이머 종료]
    F --> G[성능 메트릭 기록]
    G --> H[에러 발생 시 에러 로깅]
    H --> I[알림 발송]
    
    subgraph "로깅 정보"
        J[요청 URL]
        K[파라미터]
        L[응답 데이터]
        M[실행 시간]
        N[에러 메시지]
    end
    
    B --> J
    B --> K
    E --> L
    F --> M
    H --> N
```

## 📝 주요 특징

### 1. 모듈화된 구조
- **계좌 전용 확장**: 계좌 관련 API만 별도 파일로 분리
- **편의성 확장**: 호환성 메서드 및 편의 함수 제공
- **명확한 책임 분리**: 각 확장 파일의 역할이 명확

### 2. 공식 가이드라인 준수
- **TR ID 정확성**: KIS 공식 TR ID 사용
- **파라미터 표준화**: 공식 파라미터명 사용
- **응답 필드 정확성**: 공식 응답 필드 구조 준수

### 3. 강화된 에러 처리
- **재시도 로직**: 500 오류 시 자동 재시도
- **토큰 관리**: 토큰 만료 시 자동 갱신
- **상세한 로깅**: 디버깅을 위한 상세 로그

### 4. 호환성 보장
- **기존 코드 지원**: 호환성 메서드로 기존 코드 지원
- **점진적 마이그레이션**: 단계적 전환 가능
- **안정성**: 기존 기능에 영향 없음

---

**작성일**: 2025년 1월 6일  
**작성자**: AI Assistant  
**버전**: 1.0
