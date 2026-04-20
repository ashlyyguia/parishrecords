const admin = require('firebase-admin');

let initialized = false;

function init() {
  if (initialized) return;

  const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (serviceAccountJson) {
    const serviceAccount = JSON.parse(serviceAccountJson);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
  } else {
    admin.initializeApp();
  }

  initialized = true;
}

function getAdmin() {
  init();
  return admin;
}

module.exports = {
  getAdmin,
};
