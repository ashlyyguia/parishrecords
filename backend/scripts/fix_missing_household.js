const admin = require('firebase-admin');
const path = require('path');
const serviceAccount = require(path.join(__dirname, '../../holyparish-af472-firebase-adminsdk-fbsvc-5a570c992d.json'));
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

async function fix() {
  const userId = 'HLXRDBHHpANKOmbGDGUDNdkhuOD3';
  const householdId = 'frmjmQEhsW29ylNzUDn8';
  const userEmail = 'gonzagaprincess552@gmail.com';
  
  console.log(`Creating missing household for user ${userEmail}...`);
  
  // Create the household document with proper ownership
  await db.collection('households').doc(householdId).set({
    userId: userId,
    created_by: userId,
    familyName: userEmail.split('@')[0], // Use email prefix as family name
    address: '',
    barangay: '',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    isArchived: false,
    memberCount: 0,
    sacramentCount: 0
  });
  
  console.log(`✅ Created household ${householdId} with userId=${userId}`);
  console.log('Done! The user should now be able to access their household.');
  process.exit(0);
}

fix().catch(e => { console.error(e); process.exit(1); });
