import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

// Initialize Admin SDK
try {
  admin.initializeApp();
} catch (e) {
  // no-op if already initialized
}

const db = admin.firestore();
const messaging = admin.messaging();

type Target =
  | { type: "all" }
  | { type: "role"; role: "admin" | "staff" | "volunteer" }
  | { type: "user"; uid: string };

interface Payload {
  title: string;
  body: string;
  data?: Record<string, string>;
  archive?: boolean;
}

export const sendNotification = functions.https.onCall(async (data: any, context: any) => {
  const auth = context.auth;
  if (!auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
  }

  const { target, payload } = ((data as any) || {}) as { target: Target; payload: Payload };
  if (!payload?.title || !payload?.body || !target) {
    throw new functions.https.HttpsError('invalid-argument', "Missing 'target' or 'payload.title'/'payload.body'.");
  }

  // Authorization: only admin may send
  const senderUid = auth.uid!;
  const senderDoc = await db.collection("users").doc(senderUid).get();
  const senderRole = (senderDoc.data()?.role ?? "staff").toString();
  if (senderRole !== "admin") {
    throw new functions.https.HttpsError('permission-denied', 'Only admin can send notifications.');
  }

  // Resolve target UIDs
  let uids: string[] = [];
  if (target.type === "all") {
    const snap = await db.collection("users").select().get();
    uids = snap.docs.map((d) => d.id);
  } else if (target.type === "role") {
    const snap = await db.collection("users").where("role", "==", target.role).select().get();
    uids = snap.docs.map((d) => d.id);
  } else if (target.type === "user") {
    uids = [target.uid];
  }

  // Collect tokens and mirror to Firestore notifications
  const tokens: string[] = [];
  const batch = db.batch();
  const createdAt = admin.firestore.FieldValue.serverTimestamp();

  for (const uid of uids) {
    const ref = db.collection("users").doc(uid);
    const doc = await ref.get();
    const tokenMap = (doc.data()?.fcmTokens ?? {}) as Record<string, unknown>;
    const userTokens = Object.keys(tokenMap);
    tokens.push(...userTokens);

    const nRef = db.collection("notifications").doc();
    batch.set(nRef, {
      title: payload.title,
      body: payload.body,
      createdAt,
      read: false,
      archived: payload.archive === true,
      userId: uid,
      data: payload.data ?? {},
    });
  }

  // Send FCM
  const uniqueTokens = Array.from(new Set(tokens)).filter(Boolean) as string[];
  if (uniqueTokens.length > 0) {
    const message: admin.messaging.MulticastMessage = {
      tokens: uniqueTokens,
      notification: { title: payload.title, body: payload.body },
      data: payload.data ?? {},
      android: { priority: "high" },
      apns: { payload: { aps: { sound: "default" } } },
      webpush: { headers: { Urgency: "high" } },
    };
    try {
      await messaging.sendEachForMulticast(message);
    } catch (e) {
      console.error("FCM send error:", e);
    }
  }

  await batch.commit();
  return { ok: true, count: uids.length, tokens: uniqueTokens.length };
});

// Admin-only: create a staff user with a temporary password
export const createStaff = functions.https.onCall(async (data: any, context: any) => {
  const auth = context.auth;
  if (!auth) throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');

  const { email, displayName } = ((data as any) || {}) as { email?: string; displayName?: string };
  if (!email || typeof email !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', "Missing or invalid 'email'.");
  }

  // Authorization: only admin may create staff
  const senderUid = auth.uid!;
  const senderDoc = await db.collection('users').doc(senderUid).get();
  const senderRole = (senderDoc.data()?.role ?? 'staff').toString();
  if (senderRole !== 'admin') {
    throw new functions.https.HttpsError('permission-denied', 'Only admin can create staff accounts.');
  }

  // Generate a temporary password
  const tempPassword = Math.random().toString(36).slice(-10) + 'A1!';

  // Create Auth user
  let userRecord: admin.auth.UserRecord;
  try {
    userRecord = await admin.auth().createUser({
      email,
      password: tempPassword,
      displayName: displayName || undefined,
      emailVerified: false,
      disabled: false,
    });
  } catch (e: any) {
    throw new functions.https.HttpsError('internal', 'Failed to create user', e?.message);
  }

  // Seed Firestore user profile
  const uid = userRecord.uid;
  await db.collection('users').doc(uid).set({
    id: uid,
    email,
    displayName: displayName || null,
    role: 'staff',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    emailVerified: false,
  }, { merge: true });

  // Audit log
  await db.collection('logs').add({
    action: 'user_create_staff',
    details: `uid=${uid} email=${email}`,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { ok: true, uid, tempPassword };
});

// REST API backed by Cassandra
export { api } from './api';
