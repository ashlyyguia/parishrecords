import * as admin from 'firebase-admin';

try {
  admin.initializeApp();
} catch (e) {
  // no-op if already initialized
}

const db = admin.firestore();

export { admin, db };
