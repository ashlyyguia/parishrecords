const express = require('express');

const { getAdmin } = require('../firebase_admin');
const { requireStaff } = require('../middleware/auth');

const router = express.Router();
router.use(requireStaff);

const DEFAULT_PARISH = process.env.PARISH_ID_DEFAULT || 'default_parish';

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

function startOfDay(d) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0);
}

function endOfDay(d) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59, 999);
}

function normalizeEventDoc(doc) {
  const d = doc.data() || {};
  return {
    id: doc.id,
    parish_id: d.parish_id || DEFAULT_PARISH,
    title: d.title || null,
    type: d.type || null,
    starts_at: toIso(d.starts_at || d.start_time || d.startsAt) || null,
    ends_at: toIso(d.ends_at || d.end_time || d.endsAt) || null,
    location: d.location || null,
    status: d.status || 'scheduled',
    created_at: toIso(d.created_at) || null,
  };
}

// GET /api/events?date=today|YYYY-MM-DD&parish_id=...
router.get('/', async (req, res) => {
  try {
    const admin = getAdmin();
    const db = admin.firestore();

    const parishId = (req.query.parish_id || DEFAULT_PARISH).toString();
    const dateParam = (req.query.date || 'today').toString();

    let day = new Date();
    if (dateParam !== 'today') {
      const parsed = new Date(`${dateParam}T00:00:00`);
      if (!Number.isNaN(parsed.getTime())) day = parsed;
    }

    const from = startOfDay(day);
    const to = endOfDay(day);

    const snap = await db
      .collection('events')
      .where('parish_id', '==', parishId)
      .where('starts_at', '>=', from)
      .where('starts_at', '<=', to)
      .orderBy('starts_at', 'asc')
      .limit(200)
      .get();

    const rows = snap.docs.map(normalizeEventDoc);
    return res.json({
      parish_id: parishId,
      date: dateParam,
      rows,
    });
  } catch (error) {
    console.error('Events list error:', error);
    return res.status(500).json({ error: 'events_list_failed' });
  }
});

module.exports = router;
