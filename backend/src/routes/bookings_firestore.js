const express = require('express');

const { getAdmin } = require('../firebase_admin');
const { requireStaff } = require('../middleware/auth');
const { logAudit } = require('../utils/audit');

const router = express.Router();
router.use(requireStaff);

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

function normalizeBookingDoc(doc) {
  const d = doc.data() || {};
  return {
    id: doc.id,
    event_id: d.event_id || null,
    requester_name: d.requester_name || null,
    requester_contact: d.requester_contact || null,
    status: d.status || 'pending',
    notes: d.notes || null,
    assigned_staff: d.assigned_staff || null,
    confirmed_at: toIso(d.confirmed_at) || null,
    created_at: toIso(d.created_at) || null,
  };
}

// GET /api/bookings?event_id=...
router.get('/', async (req, res) => {
  try {
    const admin = getAdmin();
    const db = admin.firestore();

    const eventId = req.query.event_id ? req.query.event_id.toString() : null;
    const limit = Math.min(parseInt(req.query.limit || '100', 10) || 100, 200);

    let q = db.collection('bookings').orderBy('created_at', 'desc');
    if (eventId) q = q.where('event_id', '==', eventId);

    const snap = await q.limit(limit).get();
    const rows = snap.docs.map(normalizeBookingDoc);
    return res.json({ rows });
  } catch (error) {
    console.error('Bookings list error:', error);
    return res.status(500).json({ error: 'bookings_list_failed' });
  }
});

// POST /api/bookings/:id/confirm
router.post('/:id/confirm', async (req, res) => {
  try {
    const uid = req.user && req.user.uid ? req.user.uid.toString() : null;
    if (!uid) return res.status(401).json({ error: 'Unauthorized' });

    const id = (req.params.id || '').toString();
    if (!id) return res.status(400).json({ error: 'Missing booking id' });

    const admin = getAdmin();
    const db = admin.firestore();

    await db.collection('bookings').doc(id).set(
      {
        status: 'confirmed',
        confirmed_at: new Date(),
        assigned_staff: uid,
        updated_at: new Date(),
      },
      { merge: true },
    );

    await logAudit(req, {
      action: 'Booking Confirmed',
      resourceType: 'booking',
      resourceId: id,
      newValues: { status: 'confirmed', assigned_staff: uid },
    });

    return res.json({ ok: true });
  } catch (error) {
    console.error('Booking confirm error:', error);
    return res.status(500).json({ error: 'booking_confirm_failed' });
  }
});

module.exports = router;
