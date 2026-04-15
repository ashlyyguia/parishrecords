const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '..', '.env') });

const { getAdmin } = require('../src/firebase_admin');

async function main() {
  const email = process.argv[2];
  const role = process.argv[3] || 'staff'; // Default to staff, can be 'staff', 'finance', or 'admin'

  if (!email) {
    console.error('Usage: node promote_staff_by_email.js <email> [role]');
    console.error('  role can be: staff, finance, or admin (default: staff)');
    process.exit(1);
  }

  if (!['staff', 'finance', 'admin'].includes(role)) {
    console.error('Error: role must be one of: staff, finance, admin');
    process.exit(1);
  }

  const admin = getAdmin();

  try {
    const user = await admin.auth().getUserByEmail(email);
    const existingClaims = user.customClaims || {};

    // Build claims based on role
    const roleClaims = {
      admin: role === 'admin',
      staff: role === 'staff' || role === 'admin',
      finance: role === 'finance' || role === 'admin',
      role: role, // Add role as a string claim too
    };

    await admin.auth().setCustomUserClaims(user.uid, {
      ...existingClaims,
      ...roleClaims,
    });

    // Update Firestore user document
    await admin
      .firestore()
      .collection('users')
      .doc(user.uid)
      .set(
        {
          id: user.uid,
          email: user.email || email,
          displayName: user.displayName || email.split('@')[0],
          role: role,
          emailVerified: Boolean(user.emailVerified),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

    console.log(`✅ Promoted ${email} to ${role}.`);
    console.log(`   uid: ${user.uid}`);
    console.log(`   claims: ${JSON.stringify(roleClaims)}`);
    console.log(`   Next: User must log out and log back in to refresh their token.`);
  } catch (err) {
    console.error(`❌ Failed to promote ${email}: ${err.message}`);
    process.exit(1);
  }
}

main();
