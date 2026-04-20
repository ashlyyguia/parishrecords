import * as admin from 'firebase-admin';

let initialized = false;

function init(): void {
  if (initialized) return;

  // Firebase Functions automatically initializes Firebase Admin
  if (!admin.apps.length) {
    admin.initializeApp();
  }

  initialized = true;
}

function getAdmin(): typeof admin {
  init();
  return admin;
}

// Initialize immediately for direct admin usage
init();

export {
  getAdmin,
  admin,
};
