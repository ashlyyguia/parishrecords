const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '..', '.env') });

const { getAdmin } = require('../src/firebase_admin');

async function main() {
  const email = process.argv[2];
  const role = process.argv[3];

  if (!email || !role) {
    console.error('Usage: node update_user_role.js <email> <role>');
    console.error('  role can be: parishioner, staff, finance, or admin');
    process.exit(1);
  }

  const validRoles = ['parishioner', 'staff', 'finance', 'admin'];
  if (!validRoles.includes(role)) {
    console.error(`Error: role must be one of: ${validRoles.join(', ')}`);
    process.exit(1);
  }

  const admin = getAdmin();

  try {
    const user = await admin.auth().getUserByEmail(email);

    // Update Firestore user document
    await admin
      .firestore()
      .collection('users')
      .doc(user.uid)
      .set(
        {
          role: role,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

    console.log(`✅ Updated ${email} role to ${role} in Firestore.`);
    console.log(`   uid: ${user.uid}`);
    console.log(`   Next: User must log out and log back in to see changes.`);
  } catch (err) {
    console.error(`❌ Failed to update ${email}: ${err.message}`);
    process.exit(1);
  }
}

main();
