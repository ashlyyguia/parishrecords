const admin = require('firebase-admin');
const path = require('path');

// Initialize with service account
const serviceAccount = require(path.join(__dirname, '../../holyparish-af472-firebase-adminsdk-fbsvc-5a570c992d.json'));
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

async function fixAll() {
  console.log('Fixing households...');
  const households = await db.collection('households').get();
  let count = 0;
  const batch = db.batch();
  
  for (const doc of households.docs) {
    const data = doc.data();
    const updates = {};
    if (!data.userId && data.created_by) updates.userId = data.created_by;
    if (!data.created_by && data.userId) updates.created_by = data.userId;
    if (Object.keys(updates).length > 0) {
      batch.update(doc.ref, updates);
      count++;
      if (count % 400 === 0) {
        await batch.commit();
        console.log(`  Updated ${count} households`);
      }
    }
  }
  if (count % 400 !== 0) await batch.commit();
  console.log(`Fixed ${count} households`);
  
  console.log('Fixing household_members...');
  const members = await db.collection('household_members').get();
  let mcount = 0;
  const mbatch = db.batch();
  
  for (const doc of members.docs) {
    const data = doc.data();
    const updates = {};
    if (!data.userId && data.created_by) updates.userId = data.created_by;
    if (!data.created_by && data.userId) updates.created_by = data.userId;
    if (Object.keys(updates).length > 0) {
      mbatch.update(doc.ref, updates);
      mcount++;
      if (mcount % 400 === 0) {
        await mbatch.commit();
        console.log(`  Updated ${mcount} members`);
      }
    }
  }
  if (mcount % 400 !== 0) await mbatch.commit();
  console.log(`Fixed ${mcount} members`);
  console.log('Done!');
  process.exit(0);
}

fixAll().catch(e => { console.error(e); process.exit(1); });
