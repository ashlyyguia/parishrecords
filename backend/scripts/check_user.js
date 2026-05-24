const admin = require('firebase-admin');
const path = require('path');
const serviceAccount = require(path.join(__dirname, '../../holyparish-af472-firebase-adminsdk-fbsvc-5a570c992d.json'));
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

async function check() {
  const uid = process.argv[2] || 'p'; // Default to first user found
  
  console.log('Checking users for linked households...\n');
  const users = await db.collection('users').get();
  
  for (const u of users.docs) {
    const userData = u.data();
    const linkedId = userData.linkedHouseholdId;
    console.log(`User: ${u.id} (${userData.email || 'no email'})`);
    console.log(`  linkedHouseholdId: ${linkedId || 'NOT SET'}`);
    
    if (linkedId) {
      const hh = await db.collection('households').doc(linkedId).get();
      if (!hh.exists) {
        console.log(`  ❌ Household ${linkedId} DOES NOT EXIST`);
      } else {
        const hData = hh.data();
        console.log(`  ✅ Household exists`);
        console.log(`     userId: ${hData.userId || 'MISSING'}`);
        console.log(`     created_by: ${hData.created_by || 'MISSING'}`);
        if (hData.userId && hData.userId !== u.id) {
          console.log(`  ⚠️  WRONG OWNER! Should be ${u.id}`);
        }
      }
    }
    console.log('');
  }
  process.exit(0);
}

check().catch(e => { console.error(e); process.exit(1); });
