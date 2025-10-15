# 관리 스크립트

서버 전량 분석/집계를 위한 관리 스크립트 모음입니다.

## 사전 준비

1. Firebase 서비스 계정 키 다운로드
   - Firebase 콘솔 > 프로젝트 설정 > 서비스 계정
   - "새 비공개 키 생성" 클릭
   - 다운로드한 JSON 파일을 `service-account-key.json`으로 이름 변경 후 프로젝트 루트에 배치

2. 스크립트 의존성 설치
```bash
cd scripts
npm install
```

## 실행 순서

### 1단계: 마스터 심볼 업로드
```bash
npm run upload-symbols
```
- `assets/stock_info/*.zip`에서 심볼 추출
- Firestore `master/symbols` 문서에 국내/해외 심볼 배열 저장
- 약 8,000~10,000개 심볼 업로드

### 2단계: 전체 파이프라인 실행
```bash
npm run run-pipeline
```
- seedFromMaster (3회)
- backfillStockMeta (10회)
- analyzeStocksBatch (10회)
- triggerAggregateNow (1회)
- 전체 약 30~60분 소요

## 이후

- 서버 스케줄러가 자동으로 계속 실행됩니다
  - 15분마다: schedulePipeline (메타/분석/집계 통합)
  - 5분마다: aggregateTop10 (Top10 갱신)
- 앱은 `top/{KOSPI|KOSDAQ|NASDAQ}` 문서만 구독하면 됩니다

## 주의사항

- `service-account-key.json`은 절대 Git에 커밋하지 마세요 (.gitignore 등록)
- Functions 리전은 `asia-northeast3`입니다
- KIS API 자격(appKey/appSecret/accountNo)이 Firestore `users/{uid}/settings/api`에 저장되어 있어야 합니다

