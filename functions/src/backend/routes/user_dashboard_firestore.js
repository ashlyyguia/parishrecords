const express = require('express');

const { getAdmin } = require('../firebase_admin');
const { requireSelfOrStaff } = require('../middleware/auth');

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

function normalizeRequestDoc(doc) {
  const data = doc.data() || {};
  return {
    request_id: doc.id,
    request_type: data.request_type || null,
    requester_name: data.requester_name || null,
    status: data.status || 'pending',
    requested_at: toIso(data.requested_at) || null,
    processed_at: toIso(data.processed_at) || null,
    record_id: data.record_id || null,
  };
}

function normalizeAppointmentDoc(doc) {
  const d = doc.data() || {};
  return {
    id: doc.id,
    status: d.status || 'pending',
    scheduled_for: toIso(d.scheduled_for) || toIso(d.starts_at) || null,
    notes: d.notes || null,
    event_id: d.event_id || null,
  };
}

function normalizeSacramentDoc(doc) {
  const d = doc.data() || {};
  return {
    id: doc.id,
    type: d.type || null,
    title: d.title || d.text || d.name || null,
    date: toIso(d.date) || null,
    image_ref: d.image_ref || null,
    certificate_url: d.certificate_url || null,
  };
}

// GET /api/users/:id/dashboard
router.get(
  '/:id/dashboard',
  requireSelfOrStaff((req) => req.params.id),
  async (req, res) => {
    try {
      const uid = (req.params.id || '').toString();
      if (!uid) return res.status(400).json({ error: 'Missing user id' });

      const admin = getAdmin();
      const db = admin.firestore();

      const requestsSnap = await db
        .collection('requests')
        .where('created_by_uid', '==', uid)
        .orderBy('requested_at', 'desc')
        .limit(5)
        .get();

      let apptSnap;
      try {
        apptSnap = await db
          .collection('bookings')
          .where('requester_uid', '==', uid)
          .where('scheduled_for', '>=', new Date())
          .limit(5)
          .get();
      } catch (_) {
        apptSnap = await db
          .collection('bookings')
          .where('requester_uid', '==', uid)
          .limit(5)
          .get();
      }

      const sacSnap = await db
        .collection('records')
        .where('owner_uid', '==', uid)
        .limit(6)
        .get();

      return res.json({
        requests: requestsSnap.docs.map(normalizeRequestDoc),
        appointments: apptSnap.docs.map(normalizeAppointmentDoc),
        sacraments: sacSnap.docs.map(normalizeSacramentDoc),
      });
    } catch (error) {
      console.error('User dashboard error:', error);
      return res.status(500).json({ error: 'user_dashboard_failed' });
    }
  },
);

module.exports = router;
