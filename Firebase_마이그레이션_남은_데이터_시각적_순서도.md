# 🔄 Firebase 마이그레이션 남은 데이터 시각적 순서도

## 📊 현재 마이그레이션 현황

### ✅ **이미 마이그레이션 완료**
```
SQLite → Firebase
├── stock_master → stock_master/{symbol} ✅
├── watchlist → users/{uid}/watchlist/{symbol} ✅  
├── holdings → users/{uid}/holdings/{symbol} ✅
├── chart_data → charts/{symbol} ✅
└── current_price → prices/{symbol} ✅
```

### 🚨 **아직 마이그레이션 필요한 데이터**

## 📋 SQLite 테이블 마이그레이션

### 1️⃣ **analysis_results** → `analysis/{symbol}`
```
로컬 SQLite 테이블:
├── stock_code (PK)
├── stock_name, market
├── current_price, prev_close
├── 기술적 지표 (20개+)
│   ├── rsi, macd, macd_signal
│   ├── sma20, sma50
│   ├── bollinger_upper/middle/lower
│   ├── stochastic_k, stochastic_d
│   ├── vwap, vix
│   └── 고급 지표들...
├── 신호 및 결과
│   ├── signal (BUY/SELL/HOLD)
│   ├── comprehensive_score
│   ├── confidence (0.0~1.0)
│   ├── target_price
│   └── reason
└── 메타데이터
    ├── investment_style
    ├── met_conditions/total_conditions
    ├── analysis_date
    └── created_at/updated_at

Firebase 구조:
analysis/{symbol}
├── basic_info: {stock_name, market, current_price, prev_close}
├── technical_indicators: {rsi, macd, sma20, ...}
├── signals: {signal, score, confidence, target_price}
├── metadata: {style, conditions, analysis_date}
└── timestamps: {created_at, updated_at}
```

### 2️⃣ **ai_recommendations** → `recommendations/{symbol}`
```
로컬 SQLite 테이블:
├── stock_code (PK)
├── stock_name, market
├── current_price, prev_close, change_rate
├── AI 분석 결과
│   ├── signal_strength (0.0~1.0)
│   ├── confidence_score (0.0~1.0)
│   ├── target_price
│   └── recommendation_reason
└── 추천 상태
    ├── is_recommended, is_notified
    ├── recommended_at
    └── created_at

Firebase 구조:
recommendations/{symbol}
├── stock_info: {name, market, price, change_rate}
├── ai_analysis: {signal_strength, confidence, target_price, reason}
├── status: {is_recommended, is_notified}
└── timestamps: {recommended_at, created_at}
```

### 3️⃣ **trade_history** → `users/{uid}/trades/{tradeId}`
```
로컬 SQLite 테이블:
├── id (PK)
├── stock_code, stock_name, market
├── 거래 정보
│   ├── order_type (BUY/SELL)
│   ├── quantity, price, total_amount
│   ├── order_date, order_time
│   └── profit_loss, profit_rate
└── 메타데이터
    ├── trade_reason, investment_style
    ├── met_conditions/total_conditions
    ├── is_auto_trade
    └── created_at

Firebase 구조:
users/{uid}/trades/{tradeId}
├── trade_info: {stock_code, name, market, type, quantity, price}
├── financial: {total_amount, profit_loss, profit_rate}
├── metadata: {reason, style, conditions, is_auto}
├── timing: {order_date, order_time}
└── created_at
```

### 4️⃣ **investment_styles** → `users/{uid}/investment_styles`
```
로컬 SQLite 테이블:
├── id (PK)
├── style_name, style_description
├── 매수/매도 임계값
│   ├── buy_threshold, sell_threshold
│   ├── confidence_threshold
│   └── volume_threshold
└── 메타데이터
    ├── is_active, is_default
    └── created_at/updated_at

Firebase 구조:
users/{uid}/investment_styles/{styleId}
├── style_info: {name, description}
├── thresholds: {buy, sell, confidence, volume}
├── status: {is_active, is_default}
└── timestamps: {created_at, updated_at}
```

### 5️⃣ **notification_history** → `users/{uid}/notifications/{notificationId}`
```
로컬 SQLite 테이블:
├── id (PK)
├── notification_type, title, message
├── stock_code, stock_name
├── notification_data (JSON)
├── is_read, is_sent
└── created_at

Firebase 구조:
users/{uid}/notifications/{notificationId}
├── notification: {type, title, message}
├── stock_info: {code, name}
├── data: {notification_data}
├── status: {is_read, is_sent}
└── created_at
```

## 📱 SharedPreferences 마이그레이션

### 🔑 **API 설정** → `users/{uid}/settings/api_config`
```
SharedPreferences 키들:
├── api_app_key
├── api_app_secret  
├── api_account_no
├── api_is_real
└── auto_trading_enabled

Firebase 구조:
users/{uid}/settings/api_config
├── credentials: {app_key, app_secret, account_no}
├── mode: {is_real, auto_trading_enabled}
└── updated_at
```

### ⚙️ **앱 설정** → `users/{uid}/settings/app_config`
```
SharedPreferences 키들:
├── demo_mode
├── current_investment_style
├── allow_off_hours_trading
├── allow_off_hours_buy_order
└── recommended_stocks_background_enabled

Firebase 구조:
users/{uid}/settings/app_config
├── trading: {demo_mode, off_hours_trading, off_hours_buy}
├── features: {background_recommendations}
├── style: {current_investment_style}
└── updated_at
```

### 🕐 **상태/진행상황** → `users/{uid}/status/`
```
SharedPreferences 키들:
├── auto_trading_last_update
├── app_start_time
├── last_processed_index
├── last_processed_market
├── calculated_stocks_count
├── total_stocks_count
├── market_progress_${market}
├── background_service_running
└── trading_pause_until

Firebase 구조:
users/{uid}/status/
├── auto_trading: {last_update, pause_until}
├── app: {start_time, background_running}
├── processing: {last_index, last_market, calculated_count, total_count}
└── market_progress: {kospi, kosdaq, nasdaq, nyse}
```

### 📊 **데이터 캐시** → `users/{uid}/cache/`
```
SharedPreferences 키들:
├── recommended_stocks_data
├── symbol_store_map_v1
├── trade_status_${symbol}
└── auto_trading_notification_shown

Firebase 구조:
users/{uid}/cache/
├── recommended_stocks: {data, last_update}
├── symbol_store: {symbol_map}
├── trade_status: {symbol: status}
└── notifications: {auto_trading_shown}
```

## 🎯 마이그레이션 우선순위

### 1️⃣ **높은 우선순위 (즉시 필요)**
- `analysis_results` → 분석 결과 실시간 동기화
- `ai_recommendations` → AI 추천 실시간 동기화
- API 설정 → 사용자 설정 동기화

### 2️⃣ **중간 우선순위 (1주일 내)**
- `trade_history` → 거래 내역 백업
- `investment_styles` → 투자 스타일 동기화
- 앱 설정 → 사용자 경험 개선

### 3️⃣ **낮은 우선순위 (2주일 내)**
- `notification_history` → 알림 히스토리
- 데이터 캐시 → 성능 최적화
- 상태/진행상황 → 모니터링

## 🔧 마이그레이션 구현 계획

### Phase 1: 핵심 데이터 마이그레이션
```dart
// 1. analysis_results 마이그레이션
await _migrateAnalysisResults(database, uid);

// 2. ai_recommendations 마이그레이션  
await _migrateAiRecommendations(database, uid);

// 3. API 설정 마이그레이션
await _migrateApiSettings(uid);
```

### Phase 2: 거래/설정 데이터 마이그레이션
```dart
// 4. trade_history 마이그레이션
await _migrateTradeHistory(database, uid);

// 5. investment_styles 마이그레이션
await _migrateInvestmentStyles(database, uid);

// 6. 앱 설정 마이그레이션
await _migrateAppSettings(uid);
```

### Phase 3: 캐시/상태 데이터 마이그레이션
```dart
// 7. notification_history 마이그레이션
await _migrateNotificationHistory(database, uid);

// 8. 데이터 캐시 마이그레이션
await _migrateDataCache(uid);

// 9. 상태/진행상황 마이그레이션
await _migrateStatusData(uid);
```

## 📈 예상 마이그레이션 데이터량

| 데이터 타입 | 예상 건수 | 크기 (MB) | 우선순위 |
|------------|----------|----------|----------|
| analysis_results | 1,000~5,000 | 50~250 | 높음 |
| ai_recommendations | 100~500 | 5~25 | 높음 |
| trade_history | 500~2,000 | 25~100 | 중간 |
| investment_styles | 5~20 | 1~5 | 중간 |
| notification_history | 1,000~10,000 | 10~100 | 낮음 |
| SharedPreferences | 50~100개 키 | 1~5 | 중간 |

**총 예상 데이터량: 100~500MB**

## 🚀 마이그레이션 완료 후 정리 작업

### 1️⃣ **로컬 데이터 정리**
- SQLite 테이블 삭제 (analysis_results, ai_recommendations 등)
- SharedPreferences 키 정리
- 로컬 캐시 정리

### 2️⃣ **Firebase 최적화**
- 인덱스 설정
- 보안 규칙 설정
- 데이터 압축

### 3️⃣ **앱 코드 업데이트**
- Repository 클래스 Firebase 연동
- 실시간 동기화 구현
- 오프라인 지원

---

**💡 핵심 포인트:**
- **단계적 마이그레이션**: 우선순위에 따라 단계별 진행
- **데이터 무결성**: 마이그레이션 전후 데이터 검증
- **성능 최적화**: Firebase 인덱스 및 보안 규칙 설정
- **사용자 경험**: 마이그레이션 중 서비스 중단 최소화
