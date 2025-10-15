/**
 * Enqueue from master/symbols to queue/symbols/items
 */
const admin = require('firebase-admin');
const path = require('path');

const serviceAccount = require('../service-account-key.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function enqueueFromMasterDirect(limit = 3000, priority = 1) {
  const masterRef = db.collection('master').doc('symbols');
  const masterSnap = await masterRef.get();
  if (!masterSnap.exists) {
    console.error('master/symbols not found. Run upload-symbols first.');
    process.exit(1);
  }
  const domestic = masterSnap.data().domestic || [];
  const overseas = masterSnap.data().overseas || [];
  const all = [...domestic, ...overseas];
  let enq = 0;
  for (const s of all.slice(0, Number(limit) || 3000)) {
    if (!s) continue;
    const ref = db.collection('queue').doc('symbols').collection('items').doc(String(s));
    const snap = await ref.get();
    if (snap.exists && snap.data()?.done !== true) continue;
    await ref.set({ symbol: String(s), priority, retries: 0, nextRunAt: new Date(), done: false, createdAt: new Date(), updatedAt: new Date() }, { merge: true });
    enq++;
  }
  console.log(`✅ enqueued ${enq} items to queue/symbols/items`);
}

(async () => {
  const args = process.argv.slice(2);
  const limitArg = Number(args[0] || '3000');
  const priorityArg = Number(args[1] || '1');
  await enqueueFromMasterDirect(limitArg, priorityArg);
  process.exit(0);
})();
