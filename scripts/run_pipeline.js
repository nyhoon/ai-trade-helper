/**
 * 전체 파이프라인 실행 스크립트
 * - seedFromMaster → backfillStockMeta → analyzeStocksBatch → triggerAggregateNow
 */

const admin = require('firebase-admin');

// Firebase Admin 초기화
const serviceAccount = require('../service-account-key.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: serviceAccount.project_id
});

const db = admin.firestore();

async function callFunction(name, data = {}) {
  console.log(`🔧 ${name} 호출 시작...`);
  try {
    // Firestore 트리거 방식: 요청 문서 생성 → Functions가 처리 → 결과 대기
    const requestRef = db.collection('function_requests').doc();
    await requestRef.set({
      function: name,
      data,
      status: 'pending',
      createdAt: new Date()
    });
    
    // 결과 대기 (최대 5분)
    const maxWait = 300000; // 5분
    const startTime = Date.now();
    
    while (Date.now() - startTime < maxWait) {
      const snapshot = await requestRef.get();
      const status = snapshot.data()?.status;
      
      if (status === 'completed') {
        const result = snapshot.data()?.result;
        console.log(`✅ ${name} 완료:`, result);
        await requestRef.delete();
        return result;
      } else if (status === 'error') {
        const error = snapshot.data()?.error;
        console.error(`❌ ${name} 오류:`, error);
        await requestRef.delete();
        return null;
      }
      
      await new Promise(r => setTimeout(r, 2000));
    }
    
    console.error(`❌ ${name} 타임아웃`);
    await requestRef.delete();
    return null;
  } catch (e) {
    console.error(`❌ ${name} 실패:`, e.message);
    return null;
  }
}

async function runPipeline() {
  console.log('🚀 파이프라인 시작\n');
  
  // 0. 필터 적용된 심볼만 시드 (국내: REITs/ETF 제외, 해외: 주식/ETF만)
  console.log('0️⃣ 필터 적용된 심볼 시드');
  const db = admin.firestore();
  const masterSnap = await db.collection('master').doc('symbols').get();
  const domestic = masterSnap.data()?.domestic || [];
  const overseas = masterSnap.data()?.overseas || [];
  
  console.log(`   - 국내 원본: ${domestic.length}개`);
  console.log(`   - 해외 원본: ${overseas.length}개`);
  console.log(`   - 필터 적용 후 stocks 시드 시작...`);
  
  // 1. 시드 (작은 배치, 2회)
  console.log('1️⃣ stocks 시드 (2회, 1000개씩)');
  for (let i = 0; i < 2; i++) {
    await callFunction('seedFromMaster', { limit: 1000 });
    await new Promise(r => setTimeout(r, 1500));
  }
  
  // 2. 메타 백필 (10회)
  console.log('\n2️⃣ 메타 백필 (15회, 200개 배치)');
  for (let i = 0; i < 15; i++) {
    console.log(`  - 진행: ${i + 1}/10`);
    await callFunction('backfillStockMeta', { uid: 'script-admin', limit: 200 });
    await new Promise(r => setTimeout(r, 1500));
  }
  
  // 3. 분석 배치 (15회, 200개 배치)
  console.log('\n3️⃣ 분석 배치 (15회, 200개 배치)');
  for (let i = 0; i < 15; i++) {
    console.log(`  - 진행: ${i + 1}/10`);
    await callFunction('analyzeStocksBatch', { uid: 'script-admin', limit: 200 });
    await new Promise(r => setTimeout(r, 1500));
  }
  
  // 4. 즉시 집계
  console.log('\n4️⃣ Top10 집계');
  await callFunction('triggerAggregateNow');
  
  console.log('\n✅ 파이프라인 완료');
  process.exit(0);
}

runPipeline().catch(e => {
  console.error('❌ 파이프라인 오류:', e);
  process.exit(1);
});

