/**
 * Set processingUid in Firestore system/settings
 * Usage: node set_processing_uid.js <uid>
 */
const admin = require('firebase-admin');
const serviceAccount = require('../service-account-key.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

(async () => {
  try {
    const uid = process.argv[2];
    if (!uid) {
      console.error('Usage: node set_processing_uid.js <uid>');
      process.exit(1);
    }
    await db.collection('system').doc('settings').set({ processingUid: uid, updatedAt: new Date() }, { merge: true });
    console.log(`✅ processingUid set: ${uid}`);
    process.exit(0);
  } catch (e) {
    console.error('❌ set_processing_uid error:', e);
    process.exit(1);
  }
})();
