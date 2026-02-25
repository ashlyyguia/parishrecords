const express = require('express');

const { getAdmin } = require('../firebase_admin');
const { logAudit } = require('../utils/audit');

const router = express.Router();

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

function normalizeSacramentDoc(doc) {
  const d = doc.data() || {};
  return {
    id: doc.id,
    owner_uid: d.owner_uid || d.owner_id || null,
    type: d.type || null,
    title: d.title || d.text || d.name || null,
    date: toIso(d.date) || null,
    image_ref: d.image_ref || null,
    certificate_url: d.certificate_url || null,
    created_at: toIso(d.created_at) || toIso(d.date) || null,
    updated_at: toIso(d.updated_at) || null,
    qr_verify_url: d.qr_verify_url || null,
  };
}

function requireOwner(req, res, next) {
  const uid = req.user && req.user.uid ? req.user.uid.toString() : null;
  const ownerId = req.query.owner_id ? req.query.owner_id.toString() : null;
  if (!uid) return res.status(401).json({ error: 'Unauthorized' });
  if (!ownerId) return res.status(400).json({ error: 'Missing owner_id' });
  const isAdmin = req.user && req.user.admin === true;
  const role = req.user && req.user.role;
  const isStaff = role === 'staff' || role === 'admin' || isAdmin;
  if (ownerId !== uid && !isStaff) {
    return res.status(403).json({ error: 'Forbidden' });
  }
  return next();
}

// GET /api/sacraments?owner_id=UID
router.get('/', requireOwner, async (req, res) => {
  try {
    const ownerId = req.query.owner_id.toString();
    const limit = Math.min(parseInt(req.query.limit || '30', 10) || 30, 200);

    const admin = getAdmin();
    const db = admin.firestore();

    let snap;
    try {
      snap = await db
        .collection('records')
        .where('owner_uid', '==', ownerId)
        .orderBy('created_at', 'desc')
        .limit(limit)
        .get();
    } catch (_) {
      // If composite index is missing, fall back to no orderBy.
      snap = await db
        .collection('records')
        .where('owner_uid', '==', ownerId)
        .limit(limit)
        .get();
    }

    const rows = snap.docs.map(normalizeSacramentDoc);
    return res.json({ rows });
  } catch (error) {
    console.error('Sacraments list error:', error);
    return res.status(500).json({ error: 'sacraments_list_failed' });
  }
});

// POST /api/sacraments/:id/correction
router.post('/:id/correction', async (req, res) => {
  try {
    const uid = req.user && req.user.uid ? req.user.uid.toString() : null;
    if (!uid) return res.status(401).json({ error: 'Unauthorized' });

    const id = (req.params.id || '').toString();
    if (!id) return res.status(400).json({ error: 'Missing sacrament id' });

    const message = (req.body?.message || '').toString();

    const admin = getAdmin();
    const db = admin.firestore();

    const ref = db.collection('correction_tickets').doc();
    await ref.set({
      created_at: new Date(),
      created_by_uid: uid,
      record_id: id,
      message,
      status: 'open',
    });

    await logAudit(req, {
      action: 'Sacrament Correction Requested',
      resourceType: 'correction_ticket',
      resourceId: ref.id,
      newValues: { record_id: id },
    });

    return res.json({ ok: true, ticket_id: ref.id });
  } catch (error) {
    console.error('Sacrament correction error:', error);
    return res.status(500).json({ error: 'sacrament_correction_failed' });
  }
});

module.exports = router;
