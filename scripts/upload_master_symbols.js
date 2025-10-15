/**
 * master/symbols 업로드 스크립트
 * - assets/stock_info/*.zip 압축 해제 후 심볼 추출
 * - Firestore master/symbols 문서에 저장
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const AdmZip = require('adm-zip');

// Firebase Admin 초기화
const serviceAccount = require('../service-account-key.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

/**
 * zip 파일에서 심볼 추출 (국내: KOSPI/KOSDAQ)
 */
function extractDomesticSymbols(zipPath) {
  const symbols = [];
  try {
    const zip = new AdmZip(zipPath);
    const entries = zip.getEntries();
    
    for (const entry of entries) {
      if (!entry.isDirectory) {
        const content = entry.getData().toString('utf-8');
        const lines = content.split('\n');
        
        for (const line of lines) {
          // 국내 종목코드는 6자리 숫자 (앞 0 포함)
          const match = line.match(/^(\d{6})/);
          if (match) {
            symbols.push(match[1]);
          }
        }
      }
    }
  } catch (e) {
    console.log(`⚠️ ${path.basename(zipPath)} 처리 실패:`, e.message);
  }
  return symbols;
}

/**
 * zip 파일에서 심볼 추출 (해외: NASDAQ/NYSE)
 * 포맷: US\t22\tNAS\t...\tAAPL\t... (탭 구분, 5번째 필드가 심볼)
 */
function extractOverseasSymbols(zipPath) {
  const symbols = [];
  try {
    const zip = new AdmZip(zipPath);
    const entries = zip.getEntries();
    
    for (const entry of entries) {
      if (!entry.isDirectory) {
        const content = entry.getData().toString('utf-8');
        const lines = content.split('\n');
        
        for (const line of lines) {
          const trimmed = line.trim();
          if (!trimmed) continue;
          
          // 탭으로 분리 후 5번째 필드 (인덱스 4)
          const parts = trimmed.split('\t');
          if (parts.length >= 5) {
            const symbol = parts[4].trim();
            // 영문 대문자 1~6자 검증
            if (symbol && /^[A-Z][A-Z.]{0,5}$/.test(symbol)) {
              symbols.push(symbol);
            }
          }
        }
      }
    }
  } catch (e) {
    console.log(`⚠️ ${path.basename(zipPath)} 처리 실패:`, e.message);
  }
  return [...new Set(symbols)]; // 중복 제거
}

async function uploadMasterSymbols() {
  console.log('📂 심볼 파일 읽기 시작...');
  
  const stockInfoDir = path.join(__dirname, '..', 'assets', 'stock_info');
  
  // 국내 심볼
  const kospiSymbols = extractDomesticSymbols(path.join(stockInfoDir, 'kospi_code.mst.zip'));
  const kosdaqSymbols = extractDomesticSymbols(path.join(stockInfoDir, 'kosdaq_code.mst.zip'));
  const domestic = [...new Set([...kospiSymbols, ...kosdaqSymbols])];
  
  // 해외 심볼
  const nasSymbols = extractOverseasSymbols(path.join(stockInfoDir, 'nasmst.cod.zip'));
  const nysSymbols = extractOverseasSymbols(path.join(stockInfoDir, 'nysmst.cod.zip'));
  const overseas = [...new Set([...nasSymbols, ...nysSymbols])];
  
  console.log(`✅ 국내 심볼: ${domestic.length}개`);
  console.log(`✅ 해외 심볼: ${overseas.length}개`);
  console.log(`✅ 총 심볼: ${domestic.length + overseas.length}개`);
  
  // Firestore 업로드
  console.log('📤 Firestore 업로드 시작...');
  await db.collection('master').doc('symbols').set({
    domestic,
    overseas,
    updatedAt: new Date(),
    totalCount: domestic.length + overseas.length
  });
  
  console.log('✅ master/symbols 업로드 완료');
  process.exit(0);
}

uploadMasterSymbols().catch(e => {
  console.error('❌ 오류:', e);
  process.exit(1);
});

