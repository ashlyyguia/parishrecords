// One-time bootstrap for the first admin account on a fresh project.
// Usage:
//   node backend/scripts/bootstrap_admin.js <email> <password> <path-to-serviceAccountKey.json>
//
// Creates (or updates) the Firebase Auth user, marks the email verified,
// sets an `admin` custom claim, and writes the users/{uid} Firestore doc
// with role=admin so the app grants full access on first login.

const admin = require('firebase-admin');

const [, , email, password, keyPath] = process.argv;

if (!email || !password || !keyPath) {
  console.error('Usage: node bootstrap_admin.js <email> <password> <serviceAccountKey.json>');
  process.exit(1);
}

const serviceAccount = require(require('path').resolve(keyPath));

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: serviceAccount.project_id,
});

async function main() {
  const auth = admin.auth();
  const db = admin.firestore();

  // Create or fetch the auth user.
  let user;
  try {
    user = await auth.getUserByEmail(email);
    await auth.updateUser(user.uid, { password, emailVerified: true });
    console.log(`Updated existing auth user: ${user.uid}`);
  } catch (e) {
    if (e.code === 'auth/user-not-found') {
      user = await auth.createUser({ email, password, emailVerified: true });
      console.log(`Created auth user: ${user.uid}`);
    } else {
      throw e;
    }
  }

  // Grant admin via custom claims.
  await auth.setCustomUserClaims(user.uid, { admin: true, role: 'admin' });
  console.log('Set custom claims: { admin: true, role: "admin" }');

  // Write the Firestore profile doc with admin role.
  await db.collection('users').doc(user.uid).set(
    {
      id: user.uid,
      email,
      displayName: 'Administrator',
      role: 'admin',
      emailVerified: true,
      verificationCodeVerified: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      lastLogin: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  console.log(`Wrote users/${user.uid} with role=admin`);

  console.log(`\nDone. Log in at https://holyparish.web.app with ${email}`);
  process.exit(0);
}

main().catch((err) => {
  console.error('Bootstrap failed:', err);
  process.exit(1);
});
