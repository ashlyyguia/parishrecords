import * as admin from 'firebase-admin';
import { getApps } from 'firebase-admin/app';
import * as path from 'path';

// Initialize Firebase Admin with explicit credentials
if (getApps().length === 0) {
  const serviceAccount = require(path.join(__dirname, '../../../holyparish-af472-firebase-adminsdk-fbsvc-d4def93728.json'));
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: 'holyparish-af472',
  });
}

const db = admin.firestore();
const auth = admin.auth();

// Users to update - pass as JSON array via USERS_TO_UPDATE env var or command line
// Example: USERS_TO_UPDATE='[{"email":"a@b.com","role":"admin"}]' npx ts-node update_user_roles.ts
// Or: npx ts-node update_user_roles.ts '[{"email":"a@b.com","role":"admin"}]'
function getUsersToUpdate(): Array<{ email: string; role: string }> {
  const fromEnv = process.env.USERS_TO_UPDATE;
  const fromArg = process.argv[2];
  const json = fromArg || fromEnv;
  if (!json) {
    console.error('❌ No users provided. Set USERS_TO_UPDATE env var or pass JSON array as argument:');
    console.error('Example: USERS_TO_UPDATE=\'[{"email":"a@b.com","role":"admin"}]\' npx ts-node update_user_roles.ts');
    console.error('   or: npx ts-node update_user_roles.ts \'[{"email":"a@b.com","role":"admin"}]\'');
    process.exit(1);
  }
  try {
    const parsed = JSON.parse(json);
    if (!Array.isArray(parsed) || parsed.length === 0) {
      throw new Error('Expected non-empty array');
    }
    for (const u of parsed) {
      if (!u.email || !u.role) {
        throw new Error('Each user must have email and role');
      }
    }
    return parsed;
  } catch (e: any) {
    console.error('❌ Invalid JSON format:', e.message);
    process.exit(1);
  }
}

const usersToUpdate = getUsersToUpdate();

async function updateUserRoles() {
  for (const user of usersToUpdate) {
    try {
      // Find user by email in Auth
      let userRecord;
      try {
        userRecord = await auth.getUserByEmail(user.email);
        console.log(`Found user: ${user.email} with UID: ${userRecord.uid}`);
      } catch (e: any) {
        console.log(`User not found in Auth: ${user.email}, creating...`);
        // Create user if doesn't exist
        userRecord = await auth.createUser({
          email: user.email,
          emailVerified: false,
        });
        console.log(`Created user: ${user.email} with UID: ${userRecord.uid}`);
      }

      const uid = userRecord.uid;

      // Update custom claims
      await auth.setCustomUserClaims(uid, { role: user.role });
      console.log(`Set custom claims for ${user.email}: role=${user.role}`);

      // Update Firestore user document
      await db.collection('users').doc(uid).set({
        id: uid,
        email: user.email,
        role: user.role,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      console.log(`Updated Firestore for ${user.email}: role=${user.role}`);

      console.log(`✅ Successfully updated ${user.email} to role: ${user.role}\n`);
    } catch (error: any) {
      console.error(`❌ Failed to update ${user.email}:`, error.message);
    }
  }
}

updateUserRoles()
  .then(() => {
    console.log('\n✨ All users updated!');
    process.exit(0);
  })
  .catch((error) => {
    console.error('\n❌ Error:', error);
    process.exit(1);
  });
