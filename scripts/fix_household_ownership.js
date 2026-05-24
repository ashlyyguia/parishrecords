/**
 * Script to fix household ownership data
 * Populates missing userId on households and householdId on household_members
 * Run with: node scripts/fix_household_ownership.js
 */

const admin = require('firebase-admin');
const serviceAccount = require('../holyparish-af472-firebase-adminsdk-fbsvc-5a570c992d.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function fixHouseholds() {
  console.log('Fetching all households...');
  const householdsSnap = await db.collection('households').get();
  console.log(`Found ${householdsSnap.size} households`);

  const batch = db.batch();
  let updateCount = 0;

  for (const doc of householdsSnap.docs) {
    const data = doc.data();
    const updates = {};

    // Check if userId is missing but created_by exists
    if (!data.userId && data.created_by) {
      updates.userId = data.created_by;
      console.log(`  Household ${doc.id}: Adding userId = ${data.created_by}`);
    }

    // Also ensure created_by is set if userId exists
    if (!data.created_by && data.userId) {
      updates.created_by = data.userId;
      console.log(`  Household ${doc.id}: Adding created_by = ${data.userId}`);
    }

    if (Object.keys(updates).length > 0) {
      batch.update(doc.ref, updates);
      updateCount++;

      // Firestore batch limit is 500
      if (updateCount >= 400) {
        console.log('Committing batch...');
        await batch.commit();
        console.log(`Updated ${updateCount} households`);
        updateCount = 0;
      }
    }
  }

  if (updateCount > 0) {
    console.log('Committing final batch...');
    await batch.commit();
    console.log(`Updated ${updateCount} households`);
  }

  console.log(`\nHousehold fix complete. Updated ${updateCount} documents.`);
}

async function fixHouseholdMembers() {
  console.log('\nFetching all household members...');
  const membersSnap = await db.collection('household_members').get();
  console.log(`Found ${membersSnap.size} household members`);

  const batch = db.batch();
  let updateCount = 0;

  for (const doc of membersSnap.docs) {
    const data = doc.data();
    const updates = {};

    // Check if userId is missing but created_by exists
    if (!data.userId && data.created_by) {
      updates.userId = data.created_by;
      console.log(`  Member ${doc.id}: Adding userId = ${data.created_by}`);
    }

    // Also ensure created_by is set if userId exists
    if (!data.created_by && data.userId) {
      updates.created_by = data.userId;
      console.log(`  Member ${doc.id}: Adding created_by = ${data.userId}`);
    }

    if (Object.keys(updates).length > 0) {
      batch.update(doc.ref, updates);
      updateCount++;

      if (updateCount >= 400) {
        console.log('Committing batch...');
        await batch.commit();
        console.log(`Updated ${updateCount} members`);
        updateCount = 0;
      }
    }
  }

  if (updateCount > 0) {
    console.log('Committing final batch...');
    await batch.commit();
    console.log(`Updated ${updateCount} members`);
  }

  console.log(`\nHousehold members fix complete.`);
}

async function main() {
  try {
    await fixHouseholds();
    await fixHouseholdMembers();
    console.log('\n✅ All fixes complete!');
    process.exit(0);
  } catch (e) {
    console.error('Error:', e);
    process.exit(1);
  }
}

main();
