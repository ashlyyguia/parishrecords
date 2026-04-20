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

function requireOwner(req, res, next) {
  const uid = req.user && req.user.uid ? req.user.uid.toString() : null;
  if (!uid) return res.status(401).json({ error: 'Unauthorized' });
  const userId = req.query.user_id ? req.query.user_id.toString() : null;
  if (!userId) return res.status(400).json({ error: 'Missing user_id' });

  const isAdmin = req.user && req.user.admin === true;
  const role = req.user && req.user.role;
  const isStaff = role === 'staff' || role === 'admin' || isAdmin;

  if (userId !== uid && !isStaff) return res.status(403).json({ error: 'Forbidden' });
  return next();
}

function normalizeBookingDoc(doc) {
  const d = doc.data() || {};
  return {
    id: doc.id,
    event_id: d.event_id || null,
    requester_uid: d.requester_uid || d.requester_id || d.created_by_uid || null,
    requester_name: d.requester_name || null,
    requester_contact: d.requester_contact || null,
    status: d.status || 'pending',
    notes: d.notes || null,
    scheduled_for: toIso(d.scheduled_for) || toIso(d.starts_at) || null,
    created_at: toIso(d.created_at) || null,
    updated_at: toIso(d.updated_at) || null,
  };
}

// POST /api/appointments
// Body: { scheduled_for, notes, requester_name, requester_contact }
router.post('/', async (req, res) => {
  try {
    const uid = req.user && req.user.uid ? req.user.uid.toString() : null;
    if (!uid) return res.status(401).json({ error: 'Unauthorized' });

    const body = req.body || {};
    const scheduledFor = body.scheduled_for ? new Date(body.scheduled_for) : null;
    if (!scheduledFor || Number.isNaN(scheduledFor.getTime())) {
      return res.status(400).json({ error: 'Invalid scheduled_for' });
    }

    const requesterName = body.requester_name != null ? body.requester_name.toString() : null;
    const requesterContact = body.requester_contact != null ? body.requester_contact.toString() : null;
    const notes = body.notes != null ? body.notes.toString() : null;

    const admin = getAdmin();
    const db = admin.firestore();

    const ref = db.collection('bookings').doc();
    const now = new Date();

    await ref.set({
      requester_uid: uid,
      requester_name: requesterName,
      requester_contact: requesterContact,
      notes,
      status: 'pending',
      scheduled_for: scheduledFor,
      created_at: now,
      updated_at: now,
    });

    await logAudit(req, {
      action: 'Appointment Created',
      resourceType: 'appointment',
      resourceId: ref.id,
      newValues: { scheduled_for: scheduledFor.toISOString() },
    });

    return res.json({ ok: true, appointment_id: ref.id });
  } catch (error) {
    console.error('Appointment create error:', error);
    return res.status(500).json({ error: 'appointment_create_failed' });
  }
});

// GET /api/appointments?user_id=UID
router.get('/', requireOwner, async (req, res) => {
  try {
    const userId = req.query.user_id.toString();
    const limit = Math.min(parseInt(req.query.limit || '50', 10) || 50, 200);

    const admin = getAdmin();
    const db = admin.firestore();

    // Use bookings collection as appointments.
    let q = db.collection('bookings').where('requester_uid', '==', userId);

    // Optional upcoming=true
    if (req.query.upcoming === 'true') {
      q = q.where('scheduled_for', '>=', new Date());
    }

    const snap = await q.limit(limit).get();
    const rows = snap.docs.map(normalizeBookingDoc);
    return res.json({ rows });
  } catch (error) {
    console.error('Appointments list error:', error);
    return res.status(500).json({ error: 'appointments_list_failed' });
  }
});

// PUT /api/appointments/:id
router.put('/:id', async (req, res) => {
  try {
    const uid = req.user && req.user.uid ? req.user.uid.toString() : null;
    if (!uid) return res.status(401).json({ error: 'Unauthorized' });

    const id = (req.params.id || '').toString();
    if (!id) return res.status(400).json({ error: 'Missing appointment id' });

    const body = req.body || {};
    const scheduledFor = body.scheduled_for ? new Date(body.scheduled_for) : null;
    const notes = body.notes != null ? body.notes.toString() : null;
    const status = body.status != null ? body.status.toString() : null;

    const admin = getAdmin();
    const db = admin.firestore();

    const ref = db.collection('bookings').doc(id);
    const snap = await ref.get();
    if (!snap.exists) return res.status(404).json({ error: 'Appointment not found' });

    const data = snap.data() || {};
    const owner = (data.requester_uid || data.requester_id || data.created_by_uid || '').toString();

    const isAdmin = req.user && req.user.admin === true;
    const role = req.user && req.user.role;
    const isStaff = role === 'staff' || role === 'admin' || isAdmin;

    if (owner !== uid && !isStaff) return res.status(403).json({ error: 'Forbidden' });

    const patch = { updated_at: new Date() };
    if (scheduledFor && !Number.isNaN(scheduledFor.getTime())) patch.scheduled_for = scheduledFor;
    if (notes !== null) patch.notes = notes;
    if (status) patch.status = status;

    await ref.set(patch, { merge: true });

    await logAudit(req, {
      action: 'Appointment Updated',
      resourceType: 'appointment',
      resourceId: id,
      newValues: patch,
    });

    return res.json({ ok: true });
  } catch (error) {
    console.error('Appointment update error:', error);
    return res.status(500).json({ error: 'appointment_update_failed' });
  }
});

module.exports = router;
