const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '..', '.env') });

const { getAdmin } = require('../src/firebase_admin');

async function main() {
  const email = process.argv[2] || 'admin@gmail.com';
  const admin = getAdmin();

  const user = await admin.auth().getUserByEmail(email);
  const existingClaims = user.customClaims || {};

  await admin.auth().setCustomUserClaims(user.uid, {
    ...existingClaims,
    admin: true,
  });

  await admin
    .firestore()
    .collection('users')
    .doc(user.uid)
    .set(
      {
        id: user.uid,
        email: user.email || email,
        displayName: user.displayName || 'Administrator',
        role: 'admin',
        emailVerified: Boolean(user.emailVerified),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

  process.stdout.write(
    `✅ Promoted ${email} to admin.\n` +
      `- uid: ${user.uid}\n` +
      `Next: log out + log back in (or reinstall app) to refresh the token.\n`,
  );
}

main().catch((err) => {
  process.stderr.write(`❌ Failed to promote admin: ${err && err.message ? err.message : String(err)}\n`);
  process.stderr.write(
    'Make sure FIREBASE_SERVICE_ACCOUNT_JSON is set in backend/.env (or ADC is configured).\n',
  );
  process.exit(1);
});
