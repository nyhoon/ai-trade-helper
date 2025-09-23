# 해외 종목 데이터 로드 순서도

## 🔄 해외 종목 데이터 로드 프로세스

```mermaid
flowchart TD
    A[스플래시 화면 시작] --> B[AppDataManager 초기화]
    B --> C[해외 보유종목 로드 시작]
    
    C --> D{나스닥 보유종목 조회}
    D --> E[getOverseasPresentBalance 시도 1]
    E --> F{성공?}
    F -->|성공| G[데이터 파싱]
    F -->|실패| H[getOverseasPositions 시도 2]
    H --> I{성공?}
    I -->|성공| G
    I -->|실패| J[빈 배열 반환]
    
    G --> K{데이터 있음?}
    K -->|있음| L[종목 정보 추출]
    K -->|없음| M[다른 파라미터 조합 시도]
    M --> N[미국 국가코드 840 사용]
    N --> O{성공?}
    O -->|성공| L
    O -->|실패| P[외화 구분코드 02 사용]
    P --> Q{성공?}
    Q -->|성공| L
    Q -->|실패| J
    
    L --> R[뉴욕 보유종목 조회]
    R --> S[getOverseasPresentBalance 시도 1]
    S --> T{성공?}
    T -->|성공| U[데이터 파싱]
    T -->|실패| V[getOverseasPositions 시도 2]
    V --> W{성공?}
    W -->|성공| U
    W -->|실패| X[빈 배열 반환]
    
    U --> Y{데이터 있음?}
    Y -->|있음| Z[종목 정보 추출]
    Y -->|없음| AA[다른 파라미터 조합 시도]
    AA --> BB[미국 국가코드 840 사용]
    BB --> CC{성공?}
    CC -->|성공| Z
    CC -->|실패| DD[외화 구분코드 02 사용]
    DD --> EE{성공?}
    EE -->|성공| Z
    EE -->|실패| X
    
    Z --> FF[나스닥 + 뉴욕 데이터 병합]
    FF --> GG[해외 종목 상세 정보 출력]
    GG --> HH[로드 완료]
    
    J --> FF
    X --> FF
    
    style A fill:#e1f5fe
    style HH fill:#c8e6c9
    style J fill:#ffcdd2
    style X fill:#ffcdd2
```

## 📊 API 파라미터 조합 시도 순서

### 1차 시도: 기본 파라미터
```json
{
  "CANO": "계좌번호",
  "ACNT_PRDT_CD": "상품코드",
  "OVRS_EXCG_CD": "NASD/NYSE",
  "NATN_CD": "000",
  "WCRC_FRCR_DVSN_CD": "01",
  "TR_MKET_CD": "00",
  "INQR_DVSN_CD": "00",
  "INQR_STRT_DT": "현재날짜",
  "INQR_END_DT": "현재날짜",
  "PRDT_TYPE_CD": "01"
}
```

### 2차 시도: 미국 국가코드
```json
{
  "NATN_CD": "840"  // 미국 국가코드
}
```

### 3차 시도: 외화 구분코드
```json
{
  "WCRC_FRCR_DVSN_CD": "02"  // 외화
}
```

## 🔍 문제 해결 방법

### 현재 상황
- **API 응답**: `{output: [], rt_cd: 0, msg1: "조회할 내용이 없습니다"}`
- **원인**: 해외 종목이 실제로 없거나, API 파라미터가 올바르지 않음

### 개선 사항
1. **다중 파라미터 시도**: 3가지 다른 파라미터 조합으로 시도
2. **API 메서드 전환**: present-balance → positions API로 fallback
3. **상세 로깅**: 각 시도마다 상세한 로그 출력
4. **안정성 강화**: 에러 발생 시에도 앱이 중단되지 않도록 처리

## ✅ 예상 결과

개선 후 다음과 같은 로그가 출력될 것입니다:

```
🌍 해외 present-balance 조회 시작: NASD
🌍 해외 present-balance 시도 1/3
📊 해외 present-balance 응답: {output: [], rt_cd: 0, msg1: "조회할 내용이 없습니다"}
⚠️ 해외 present-balance 시도 1: 데이터 없음
🌍 해외 present-balance 시도 2/3
📊 해외 present-balance 응답: {output: [], rt_cd: 0, msg1: "조회할 내용이 없습니다"}
⚠️ 해외 present-balance 시도 2: 데이터 없음
🌍 해외 present-balance 시도 3/3
📊 해외 present-balance 응답: {output: [], rt_cd: 0, msg1: "조회할 내용이 없습니다"}
⚠️ 해외 present-balance 시도 3: 데이터 없음
⚠️ 모든 해외 present-balance 시도 실패
🇺🇸 나스닥 보유종목 로드 시도 2: getOverseasPositions
🌍 해외 positions 조회 시작: NASD
...
ℹ️ 해외 보유종목이 없습니다. (정상적인 상황일 수 있음)
```

## 🎯 결론

이 개선으로 해외 종목이 실제로 없는 경우에도 안정적으로 처리되며, 향후 해외 종목을 보유하게 되면 자동으로 로드될 것입니다.
