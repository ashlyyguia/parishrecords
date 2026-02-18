const express = require('express');
const { v4: uuidv4 } = require('uuid');

const { getAdmin } = require('../firebase_admin');
const { requireAdmin, requireStaff } = require('../middleware/auth');

const router = express.Router();

function requireAuth(req, res, next) {
  const uid = req.user && req.user.uid ? req.user.uid.toString() : null;
  if (!uid) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  return next();
}

function toIso(val) {
  if (!val) return null;
  if (val instanceof Date) return val.toISOString();
  if (typeof val.toDate === 'function') {
    const d = val.toDate();
    return d instanceof Date ? d.toISOString() : null;
  }
  try {
    const d = new Date(val);
    return Number.isNaN(d.getTime()) ? null : d.toISOString();
  } catch (_) {
    return null;
  }
}

function normalizeNotificationDoc(doc) {
  const data = doc.data() || {};
  const archived = data.archived === true || data.type === 'archived';
  return {
    id: doc.id,
    user_id: data.user_id || null,
    title: data.title || '',
    body: data.body || data.message || '',
    type: data.type || (archived ? 'archived' : 'normal'),
    read: data.read === true,
    archived,
    createdAt: toIso(data.created_at) || toIso(data.createdAt) || null,
    created_at: toIso(data.created_at) || null,
  };
}

router.get('/', requireAuth, async (req, res) => {
  try {
    const admin = getAdmin();
    const db = admin.firestore();

    const limit = Math.min(parseInt(req.query.limit, 10) || 100, 300);

    const uid = req.user && req.user.uid ? req.user.uid.toString() : null;
    const isAdmin = req.user && req.user.admin === true;
    const filterUserId = req.query.user_id ? req.query.user_id.toString() : null;

    // Default behavior:
    // - non-admin: return only broadcast (user_id null) + user-scoped (user_id == uid)
    // - admin: can optionally filter by user_id; otherwise returns latest notifications
    let docs = [];
    if (!isAdmin) {
      if (!uid) {
        return res.status(401).json({ error: 'Unauthorized' });
      }
      const [broadcastSnap, userSnap] = await Promise.all([
        db
          .collection('notifications')
          .where('user_id', '==', null)
          .orderBy('created_at', 'desc')
          .limit(limit)
          .get(),
        db
          .collection('notifications')
          .where('user_id', '==', uid)
          .orderBy('created_at', 'desc')
          .limit(limit)
          .get(),
      ]);
      docs = [...broadcastSnap.docs, ...userSnap.docs]
        .sort((a, b) => {
          const aTime = toIso((a.data() || {}).created_at) || '';
          const bTime = toIso((b.data() || {}).created_at) || '';
          return bTime.localeCompare(aTime);
        })
        .slice(0, limit);
    } else if (filterUserId) {
      const snap = await db
        .collection('notifications')
        .where('user_id', '==', filterUserId)
        .orderBy('created_at', 'desc')
        .limit(limit)
        .get();
      docs = snap.docs;
    } else {
      const snap = await db
        .collection('notifications')
        .orderBy('created_at', 'desc')
        .limit(limit)
        .get();
      docs = snap.docs;
    }

    const rows = docs.map(normalizeNotificationDoc);

    return res.json({ rows, count: rows.length });
  } catch (error) {
    console.error('Get notifications error:', error);
    return res.status(500).json({ error: 'Failed to fetch notifications' });
  }
});

router.post('/', requireAdmin, async (req, res) => {
  try {
    const admin = getAdmin();
    const db = admin.firestore();

    const { title, body, user_id: userIdRaw } = req.body || {};
    if (!title || !body) {
      return res.status(400).json({ error: 'Missing title or body' });
    }

    const userId = userIdRaw ? userIdRaw.toString() : null;

    const id = uuidv4();
    const now = new Date();

    await db.collection('notifications').doc(id).set({
      title: title.toString(),
      body: body.toString(),
      type: 'normal',
      read: false,
      archived: false,
      user_id: userId,
      created_at: now,
      expires_at: null,
      created_by_uid: req.user && req.user.uid ? req.user.uid.toString() : null,
      created_by_email: req.user && req.user.email ? req.user.email.toString() : null,
    });

    return res.status(201).json({
      id,
      title,
      body,
      type: 'normal',
      read: false,
      user_id: userId,
      created_at: now.toISOString(),
    });
  } catch (error) {
    console.error('Create notification error:', error);
    return res.status(500).json({ error: 'Failed to create notification' });
  }
});

router.patch('/:id/read', requireAuth, async (req, res) => {
  try {
    const { id } = req.params;
    const { read } = req.body || {};

    if (typeof read !== 'boolean') {
      return res.status(400).json({ error: 'Invalid read value' });
    }

    const admin = getAdmin();
    const db = admin.firestore();

    await db.collection('notifications').doc(id).set(
      {
        read,
        updated_at: new Date(),
      },
      { merge: true },
    );

    return res.json({ message: 'Notification read state updated' });
  } catch (error) {
    console.error('Update notification read error:', error);
    return res.status(500).json({ error: 'Failed to update notification read state' });
  }
});

router.patch('/:id/archive', requireStaff, async (req, res) => {
  try {
    const { id } = req.params;
    const { archived } = req.body || {};

    if (typeof archived !== 'boolean') {
      return res.status(400).json({ error: 'Invalid archived value' });
    }

    const admin = getAdmin();
    const db = admin.firestore();

    await db.collection('notifications').doc(id).set(
      {
        archived,
        type: archived ? 'archived' : 'normal',
        updated_at: new Date(),
      },
      { merge: true },
    );

    return res.json({ message: 'Notification archive state updated' });
  } catch (error) {
    console.error('Update notification archive error:', error);
    return res.status(500).json({ error: 'Failed to update notification archive state' });
  }
});

router.post('/bulk/read', requireStaff, async (req, res) => {
  try {
    const ids = (req.body && Array.isArray(req.body.ids)) ? req.body.ids : [];
    const read = req.body && typeof req.body.read === 'boolean' ? req.body.read : null;
    if (!Array.isArray(ids) || ids.length === 0 || read === null) {
      return res.status(400).json({ error: 'ids (array) and read (boolean) are required' });
    }

    const admin = getAdmin();
    const db = admin.firestore();
    const uid = req.user && req.user.uid ? req.user.uid.toString() : null;
    const isAdmin = req.user && req.user.admin === true;

    const batch = db.batch();
    let allowedCount = 0;
    for (const rawId of ids.slice(0, 200)) {
      const id = rawId ? rawId.toString() : '';
      if (!id) continue;
      const ref = db.collection('notifications').doc(id);
      if (!isAdmin) {
        const doc = await ref.get();
        if (!doc.exists) continue;
        const owner = (doc.data() || {}).user_id || null;
        if (owner && uid && owner.toString() !== uid) continue;
      }
      batch.set(ref, { read, updated_at: new Date() }, { merge: true });
      allowedCount += 1;
    }

    await batch.commit();
    return res.json({ ok: true, updated: allowedCount });
  } catch (error) {
    console.error('Bulk read update error:', error);
    return res.status(500).json({ error: 'Failed to bulk update notifications' });
  }
});

router.post('/bulk/archive', requireStaff, async (req, res) => {
  try {
    const ids = (req.body && Array.isArray(req.body.ids)) ? req.body.ids : [];
    const archived = req.body && typeof req.body.archived === 'boolean' ? req.body.archived : null;
    if (!Array.isArray(ids) || ids.length === 0 || archived === null) {
      return res.status(400).json({ error: 'ids (array) and archived (boolean) are required' });
    }

    const admin = getAdmin();
    const db = admin.firestore();
    const uid = req.user && req.user.uid ? req.user.uid.toString() : null;
    const isAdmin = req.user && req.user.admin === true;

    const batch = db.batch();
    let allowedCount = 0;
    for (const rawId of ids.slice(0, 200)) {
      const id = rawId ? rawId.toString() : '';
      if (!id) continue;
      const ref = db.collection('notifications').doc(id);
      if (!isAdmin) {
        const doc = await ref.get();
        if (!doc.exists) continue;
        const owner = (doc.data() || {}).user_id || null;
        if (owner && uid && owner.toString() !== uid) continue;
      }
      batch.set(ref, { archived, type: archived ? 'archived' : 'normal', updated_at: new Date() }, { merge: true });
      allowedCount += 1;
    }

    await batch.commit();
    return res.json({ ok: true, updated: allowedCount });
  } catch (error) {
    console.error('Bulk archive update error:', error);
    return res.status(500).json({ error: 'Failed to bulk update notifications' });
  }
});

router.delete('/:id', requireAdmin, async (req, res) => {
  try {
    const { id } = req.params;
    const admin = getAdmin();
    const db = admin.firestore();

    await db.collection('notifications').doc(id).delete();

    return res.json({ message: 'Notification deleted successfully' });
  } catch (error) {
    console.error('Delete notification error:', error);
    return res.status(500).json({ error: 'Failed to delete notification' });
  }
});

module.exports = router;
