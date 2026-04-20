const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

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

  const serviceAccountPaths = [
    // Project root (where the service account file actually is)
    path.join(process.cwd(), '..', 'holyparish-af472-firebase-adminsdk-fbsvc-5a570c992d.json'),
    path.join(process.cwd(), 'holyparish-af472-firebase-adminsdk-fbsvc-5a570c992d.json'),
    // Common fallback paths
    path.join(__dirname, '..', '..', 'holyparish-af472-firebase-adminsdk-fbsvc-5a570c992d.json'),
    path.join(__dirname, '../serviceAccountKey.json'),
    path.join(process.cwd(), 'serviceAccountKey.json'),
  ];

  let serviceAccount = null;
  let usedPath = null;

  for (const servicePath of serviceAccountPaths) {
    try {
      if (fs.existsSync(servicePath)) {
        serviceAccount = require(servicePath);
        usedPath = servicePath;
        console.log('Firebase Admin initialized with service account from:', servicePath);
        break;
      }
    } catch (e) {
      // Try next path
    }
  }

  return serviceAccount;
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
    // Try to initialize without service account (uses Application Default Credentials)
    console.log('Firebase Admin initializing with Application Default Credentials...');
    admin.initializeApp({
      projectId: projectId || 'holyparish-af472',
    });
  }

  initialized = true;
}

function getAdmin() {
  try {
    // Check if Firebase Admin is already initialized
    init();
    return admin;
  } catch (error) {
    console.error('Failed to initialize Firebase Admin:', error);
    throw error;
  }
}

module.exports = {
  getAdmin,
};
