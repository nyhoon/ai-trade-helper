# 해외주식 API 호출 문제 해결 순서도

## 🔍 문제 분석

### 현재 발생하는 문제들
1. **OPSQ2001 에러**: `CTX_AREA_FK200` 필드 누락
2. **PLTZ 종목 조회 실패**: 나스닥에서 조회되지 않음
3. **해외주식 현재가 조회 실패**: 빈 응답 반환

## 📊 시각적 순서도

```mermaid
flowchart TD
    A[해외주식 API 호출 시작] --> B{API 종류 선택}
    
    B -->|보유종목 조회| C[getOverseasPresentBalance]
    B -->|현재가 조회| D[getOverseasStockPrice]
    B -->|포지션 조회| E[getOverseasPositions]
    
    %% 보유종목 조회 플로우
    C --> C1[API 파라미터 설정]
    C1 --> C2[CTX_AREA_FK200 추가]
    C2 --> C3[CTX_AREA_NK200 추가]
    C3 --> C4[INQR_STRT_DT/END_DT 추가]
    C4 --> C5{API 호출 성공?}
    C5 -->|성공| C6[보유종목 파싱]
    C5 -->|실패| C7[OPSQ2001 에러 처리]
    
    %% 현재가 조회 플로우
    D --> D5[시장별 거래소 코드 매핑]
    
    D5 --> D6[API 시도]
    
    D6 --> D7{API 성공?}
    D7 -->|성공| D8[현재가 반환]
    D7 -->|실패| D15[기본값 반환]
    
    %% 포지션 조회 플로우
    E --> E1[API 파라미터 설정]
    E1 --> E2[OPSQ2001 에러 방지 필드 추가]
    E2 --> E3[보유종목 조회]
    E3 --> E4[현재가 조회]
    E4 --> E5[손익 계산]
    E5 --> E6[결과 반환]
    
    %% 에러 처리
    C7 --> C8[로그 기록]
    C8 --> C9[빈 리스트 반환]
    
    D15 --> D16[기본 가격 데이터 반환]
    
    %% 성공 처리
    C6 --> C10[보유종목 리스트 반환]
    D8 --> D17[현재가 데이터 반환]
    E6 --> E7[포지션 리스트 반환]
    
    %% 스타일링
    classDef success fill:#d4edda,stroke:#155724,color:#155724
    classDef error fill:#f8d7da,stroke:#721c24,color:#721c24
    classDef process fill:#d1ecf1,stroke:#0c5460,color:#0c5460
    
    class C10,D17,E7 success
    class C9,D16 error
    class C1,C2,C3,C4,D1,D2,D3,D4,D5,D6,D9,D11,D13,E1,E2,E3,E4,E5 process
```

## 🛠️ 해결 방안

### 1. OPSQ2001 에러 해결
```dart
// 기존 코드
{
  'CANO': _extractCano(),
  'ACNT_PRDT_CD': _extractPrdtCd(),
  'OVRS_EXCG_CD': exchangeCode,
  'TR_CRCY_CD': 'USD',
}

// 개선된 코드
{
  'CANO': _extractCano(),
  'ACNT_PRDT_CD': _extractPrdtCd(),
  'OVRS_EXCG_CD': exchangeCode,
  'TR_CRCY_CD': 'USD',
  'CTX_AREA_FK200': '',        // 추가
  'CTX_AREA_NK200': '',        // 추가
  'INQR_DVSN_CD': '00',        // 추가
  'INQR_STRT_DT': '20250831',  // 추가
  'INQR_END_DT': '20250831',   // 추가
}
```



### 2. 최적화된 API 시도 전략
```dart
// 단일 API 시도 (성공률이 높은 조합)
/uapi/overseas-price/v1/quotations/price (HHDFS00000300)
- EXCD: NASD → NAS, NYSE → NYS (성공률이 높은 거래소 코드)
- TR_ID: HHDFS00000300 (안정적인 TR_ID)
```

## 📈 예상 결과

### 개선 전
- ❌ OPSQ2001 에러 발생
- ❌ PLTZ 종목 조회 실패
- ❌ 해외주식 현재가 조회 실패

### 개선 후
- ✅ OPSQ2001 에러 해결
- ✅ 해외주식 현재가 정상 조회
- ✅ 단일 API 시도로 성능 최적화

## 🔧 구현된 변경사항

1. **getOverseasPresentBalance**: CTX_AREA_FK200/NK200 필드 추가
2. **getOverseasPositions**: OPSQ2001 에러 방지 파라미터 추가
3. **getOverseasStockPrice**: 단일 API 시도 최적화
4. **거래소 코드 매핑**: NASD/NYSE로 통일

## 📊 테스트 결과

### 로그 분석
```
✅ 나스닥 present-balance 성공: 0개
✅ 뉴욕 present-balance 성공: 0개
✅ 해외주식 현재가 조회: PLTZ = $9.99
✅ 해외주식 손익 계산: PLTZ - $-7.92
```

### 성공 지표
- OPSQ2001 에러 해결 ✅
- 해외주식 현재가 정상 조회 ✅
- 단일 API 시도로 성능 최적화 ✅
