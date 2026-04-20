const express = require('express');

const { getAdmin } = require('../firebase_admin');
const { requireAdmin } = require('../middleware/auth');

const router = express.Router();

function toIso(val) {
  if (!val) return null;
  if (val instanceof Date) return val.toISOString();
  if (typeof val.toDate === 'function') {
    const d = val.toDate();
    return d instanceof Date ? d.toISOString() : null;
  }
  return null;
}

function normalizeUserDoc(doc) {
  const data = doc.data() || {};
  return {
    id: doc.id,
    email: data.email || null,
    display_name: data.display_name || data.displayName || null,
    role: data.role || 'staff',
    created_at: toIso(data.created_at) || null,
    last_login: toIso(data.last_login) || null,
    email_verified: data.email_verified === true,
    disabled: data.disabled === true,
  };
}

router.get('/', requireAdmin, async (req, res) => {
  try {
    const admin = getAdmin();
    const db = admin.firestore();

    const limit = Math.min(parseInt(req.query.limit || '100', 10) || 100, 200);
    const roleFilter = req.query.role ? req.query.role.toString().trim().toLowerCase() : null;

    let query = db.collection('users').limit(limit);
    if (roleFilter) {
      query = query.where('role', '==', roleFilter);
    }

    const snap = await query.get();
    const rows = snap.docs.map(normalizeUserDoc);

    return res.json({ rows, count: rows.length });
  } catch (error) {
    console.error('Get users error:', error);
    return res.status(500).json({ error: 'Failed to fetch users', details: error.message || String(error) });
  }
});

router.delete('/:id', requireAdmin, async (req, res) => {
  try {
    const uid = (req.params.id || '').toString();
    if (!uid) {
      return res.status(400).json({ error: 'Missing user id' });
    }

    const admin = getAdmin();
    const db = admin.firestore();

    await db.collection('users').doc(uid).delete();

    try {
      await admin.auth().deleteUser(uid);
    } catch (err) {
      console.error('Warning: failed to delete Firebase Auth user', uid, err);
    }

    return res.json({ message: 'User deleted successfully' });
  } catch (error) {
    console.error('Delete user error:', error);
    return res.status(500).json({ error: 'Failed to delete user', details: error.message || String(error) });
  }
});

module.exports = router;
