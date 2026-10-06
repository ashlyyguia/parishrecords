// One-time seeding of initial accounts on a fresh project.
// Usage:
//   node backend/scripts/seed_users.js <path-to-serviceAccountKey.json>
//
// Edit the USERS array below to taste. For each entry it creates (or updates)
// the Firebase Auth user, marks the email verified, sets role custom claims,
// and writes the users/{uid} Firestore doc so the app grants the right access.

const path = require('path');
const admin = require('firebase-admin');

const USERS = [
  { email: 'ashlyguiaaa@gmail.com', password: 'ashly123', role: 'admin', displayName: 'Administrator' },
  { email: 'jovieamores88@gmail.com', password: 'jovie123', role: 'staff', displayName: 'Staff' },
  { email: 'gonzagaprince919@gmail.com', password: 'prince123', role: 'finance', displayName: 'Finance' },
  { email: 'hotdogbunsssssss@gmail.com', password: 'arado123', role: 'parishioner', displayName: 'Parishioner' },
];

const keyPath = process.argv[2];
if (!keyPath) {
  console.error('Usage: node seed_users.js <serviceAccountKey.json>');
  process.exit(1);
}

const serviceAccount = require(path.resolve(keyPath));
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: serviceAccount.project_id,
});

async function seedUser({ email, password, role, displayName }) {
  const auth = admin.auth();
  const db = admin.firestore();

  let user;
  try {
    user = await auth.getUserByEmail(email);
    await auth.updateUser(user.uid, { password, emailVerified: true });
    console.log(`  updated auth user ${email} (${user.uid})`);
  } catch (e) {
    if (e.code === 'auth/user-not-found') {
      user = await auth.createUser({ email, password, emailVerified: true });
      console.log(`  created auth user ${email} (${user.uid})`);
    } else {
      throw e;
    }
  }

  const claims = { role };
  if (role === 'admin') claims.admin = true;
  await auth.setCustomUserClaims(user.uid, claims);

  await db.collection('users').doc(user.uid).set(
    {
      id: user.uid,
      email,
      displayName,
      role,
      emailVerified: true,
      verificationCodeVerified: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      lastLogin: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  console.log(`  wrote users/${user.uid} role=${role}`);
}

async function main() {
  for (const u of USERS) {
    console.log(`Seeding ${u.role}: ${u.email}`);
    await seedUser(u);
  }
  console.log('\nAll users seeded. Log in at https://holyparish.web.app');
  process.exit(0);
}

main().catch((err) => {
  console.error('Seeding failed:', err);
  process.exit(1);
});
