import * as functions from 'firebase-functions';
import type { UserRecord } from 'firebase-admin/auth';

import { admin, db } from '../firebase';

export const createStaff = functions.https.onCall(
  async (data: any, context: any) => {
    const auth = context.auth;
    if (!auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Authentication required.',
      );
    }

    const { email, displayName } = ((data as any) || {}) as {
      email?: string;
      displayName?: string;
    };

    if (!email || typeof email !== 'string') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        "Missing or invalid 'email'.",
      );
    }

    const senderUid = auth.uid!;
    const senderDoc = await db.collection('users').doc(senderUid).get();
    const senderRole = (senderDoc.data()?.role ?? 'staff').toString();
    if (senderRole !== 'admin') {
      throw new functions.https.HttpsError(
        'permission-denied',
        'Only admin can create staff accounts.',
      );
    }

    const tempPassword = Math.random().toString(36).slice(-10) + 'A1!';

    let userRecord: UserRecord;
    try {
      userRecord = await admin.auth().createUser({
        email,
        password: tempPassword,
        displayName: displayName || undefined,
        emailVerified: false,
        disabled: false,
      });
    } catch (e: any) {
      throw new functions.https.HttpsError(
        'internal',
        'Failed to create user',
        e?.message,
      );
    }

    const uid = userRecord.uid;
    await db
      .collection('users')
      .doc(uid)
      .set(
        {
          id: uid,
          email,
          displayName: displayName || null,
          role: 'staff',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          emailVerified: false,
        },
        { merge: true },
      );

    await db.collection('logs').add({
      action: 'user_create_staff',
      details: `uid=${uid} email=${email}`,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { ok: true, uid, tempPassword };
  },
);
