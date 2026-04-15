const admin = require('firebase-admin');
const fs = require('fs');

let initialized = false;

function resolveProjectId(serviceAccount) {
  if (serviceAccount && serviceAccount.project_id) return serviceAccount.project_id;
  return (
    process.env.FIREBASE_PROJECT_ID ||
    process.env.GCLOUD_PROJECT ||
    process.env.GOOGLE_CLOUD_PROJECT ||
    null
  );
}

function loadServiceAccountFromEnv() {
  const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (serviceAccountJson) {
    return JSON.parse(serviceAccountJson);
  }

  const serviceAccountPath =
    process.env.FIREBASE_SERVICE_ACCOUNT_PATH || process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (serviceAccountPath) {
    const raw = fs.readFileSync(serviceAccountPath, 'utf8');
    return JSON.parse(raw);
  }

  return null;
}

function init() {
  if (initialized) return;

  const serviceAccount = loadServiceAccountFromEnv();
  const projectId = resolveProjectId(serviceAccount);

  if (serviceAccount) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId: projectId || undefined,
    });
  } else {
    admin.initializeApp({
      projectId: projectId || undefined,
    });
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
