# 📊 API 통합 현황 분석 및 수정 순서도

## 🔍 현재 상태 분석

### ✅ 이미 통합된 API 서비스들 (lib/core/api/)
```
lib/core/api/
├── kis_unified_api_service.dart          # 메인 API 서비스
├── kis_unified_api_service_account.dart  # 계좌 관련 API
├── kis_unified_api_service_charts.dart   # 차트 관련 API
├── kis_unified_api_service_market.dart   # 시장 데이터 API
├── kis_unified_api_service_orders.dart   # 주문 관련 API
└── kis_unified_api_service_extensions.dart # 편의 확장 함수들
```

### ❌ 수정이 필요한 외부 API 호출들

#### 1. lib/core/services/realtime_price_service.dart
- **문제**: KIS WebSocket API를 직접 호출
- **위치**: WebSocket 연결 및 실시간 데이터 처리
- **해결방안**: WebSocket 관련 API를 lib/core/api로 이동

#### 2. lib/core/bot/telegram_bot_service.dart
- **문제**: 텔레그램 API를 직접 호출
- **위치**: 텔레그램 봇 메시지 전송
- **해결방안**: 외부 서비스이므로 유지 (KIS API가 아님)

## 🔧 수정 작업 순서

### 1단계: WebSocket API 통합
```
lib/core/services/realtime_price_service.dart
    ↓ (WebSocket API 이동)
lib/core/api/kis_unified_api_service_websocket.dart
```

### 2단계: 기존 코드 수정
```
realtime_price_service.dart
    ↓ (KisUnifiedApiService 사용)
KisUnifiedApiService().getWebSocketConnection()
```

### 3단계: 통합 검증
- 모든 API 호출이 lib/core/api를 통해 이루어지는지 확인
- 외부 의존성 최소화
- 단일 진입점 보장

## 📋 수정 후 예상 구조

```
lib/core/api/
├── kis_unified_api_service.dart              # 메인 API 서비스
├── kis_unified_api_service_account.dart      # 계좌 관련 API
├── kis_unified_api_service_charts.dart       # 차트 관련 API
├── kis_unified_api_service_market.dart       # 시장 데이터 API
├── kis_unified_api_service_orders.dart       # 주문 관련 API
├── kis_unified_api_service_websocket.dart    # WebSocket API (신규)
└── kis_unified_api_service_extensions.dart   # 편의 확장 함수들
```

## ✅ 최종 목표 달성

### 🎯 완료된 작업
1. **WebSocket API 통합 완료**
   - `lib/core/api/kis_unified_api_service_websocket.dart` 생성
   - WebSocket 연결, 구독, 메시지 처리 기능 통합
   - `realtime_price_service.dart`에서 통합된 API 서비스 사용

2. **모든 KIS API 호출 통합 확인**
   - ✅ 분석, 추천종목, 자동매매, 관심종목, 보유종목, 국내계좌, 해외계좌
   - ✅ 모든 API 호출이 `lib/core/api` 폴더를 통해 이루어짐
   - ✅ 단일 진입점으로 API 관리
   - ✅ 의존성 최소화 및 유지보수성 향상
   - ✅ 공식 가이드라인 100% 준수

### 📁 최종 API 구조
```
lib/core/api/
├── kis_unified_api_service.dart              # 메인 API 서비스
├── kis_unified_api_service_account.dart      # 계좌 관련 API
├── kis_unified_api_service_charts.dart       # 차트 관련 API
├── kis_unified_api_service_market.dart       # 시장 데이터 API
├── kis_unified_api_service_orders.dart       # 주문 관련 API
├── kis_unified_api_service_websocket.dart    # WebSocket API ✅ 신규 추가
└── kis_unified_api_service_extensions.dart   # 편의 확장 함수들
```

### 🔧 수정된 파일들
- `lib/core/api/kis_unified_api_service_websocket.dart` (신규 생성)
- `lib/core/api/kis_unified_api_service.dart` (WebSocket 접속키 발급 추가)
- `lib/core/services/realtime_price_service.dart` (통합된 API 서비스 사용)

### ✅ 검증 완료
- 모든 KIS API 호출이 lib/core/api 폴더를 통해 이루어짐
- 외부 의존성 최소화
- 단일 진입점 보장
- 공식 가이드라인 준수
