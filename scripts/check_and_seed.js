/**
 * Check and seed: ensure processingUid exists; ensure queue has pending items
 */
const admin = require('firebase-admin');
const path = require('path');

const serviceAccount = require('../service-account-key.json');
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

async function ensureProcessingUid() {
  const sysRef = db.collection('system').doc('settings');
  const sysSnap = await sysRef.get();
  let processingUid = sysSnap.exists ? sysSnap.data()?.processingUid : null;
  if (processingUid) {
    console.log(`processingUid OK: ${processingUid}`);
    return processingUid;
  }
  // find first user with API credentials
  const usersSnap = await db.collection('users').get();
  for (const u of usersSnap.docs) {
    const apiSnap = await u.ref.collection('settings').doc('api').get();
    if (apiSnap.exists && apiSnap.data()?.appKey && apiSnap.data()?.appSecret) {
      processingUid = u.id;
      break;
    }
  }
  if (!processingUid) {
    console.log('⚠️ No user with API credentials found. Skipping set.');
    return null;
  }
  await sysRef.set({ processingUid, updatedAt: new Date() }, { merge: true });
  console.log(`✅ processingUid set to: ${processingUid}`);
  return processingUid;
}

async function ensureQueueSeed(max = 3000) {
  const pending = await db
    .collection('queue').doc('symbols').collection('items')
    .where('done', '==', false).limit(1).get();
  if (!pending.empty) {
    console.log('queue has pending items. skip seed.');
    return 0;
  }
  const master = await db.collection('master').doc('symbols').get();
  if (!master.exists) {
    console.log('⚠️ master/symbols not found. Upload symbols first.');
    return 0;
  }
  const domestic = master.data()?.domestic || [];
  const overseas = master.data()?.overseas || [];
  const all = [...domestic, ...overseas].slice(0, max);
  if (all.length === 0) {
    console.log('⚠️ master lists empty.');
    return 0;
  }
  const batch = db.batch();
  for (const s of all) {
    const ref = db.collection('queue').doc('symbols').collection('items').doc(String(s));
    batch.set(ref, { symbol: String(s), priority: 1, retries: 0, nextRunAt: new Date(), done: false, createdAt: new Date(), updatedAt: new Date() }, { merge: true });
  }
  await batch.commit();
  console.log(`✅ seeded queue with ${all.length} items.`);
  return all.length;
}

(async () => {
  try {
    await ensureProcessingUid();
    await ensureQueueSeed(3000);
    process.exit(0);
  } catch (e) {
    console.error('❌ check_and_seed error:', e);
    process.exit(1);
  }
})();
