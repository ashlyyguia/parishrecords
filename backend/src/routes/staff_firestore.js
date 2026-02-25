const express = require('express');

const { getAdmin } = require('../firebase_admin');
const { requireStaff } = require('../middleware/auth');

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

router.get('/worktray', async (req, res) => {
  try {
    const uid = req.user && req.user.uid ? req.user.uid.toString() : null;
    if (!uid) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const admin = getAdmin();
    const db = admin.firestore();

    const parishId = (req.query.parish_id || process.env.PARISH_ID_DEFAULT || 'default_parish').toString();

    // Pending requests (parish-scoped)
    const requestsSnap = await db
      .collection('requests')
      .where('parish_id', '==', parishId)
      .where('status', '==', 'pending')
      .limit(200)
      .get();

    // Assigned OCR jobs
    const ocrSnap = await db
      .collection('ocr_jobs')
      .where('assigned_to', '==', uid)
      .orderBy('created_at', 'desc')
      .limit(50)
      .get();

    const ocrJobs = ocrSnap.docs.map((doc) => {
      const d = doc.data() || {};
      return {
        id: doc.id,
        type: d.type || null,
        title: d.title || null,
        status: d.status || null,
        assigned_to: d.assigned_to || null,
        created_at: toIso(d.created_at) || null,
      };
    });

    return res.json({
      generated_at: new Date().toISOString(),
      parish_id: parishId,
      pending_requests: requestsSnap.size,
      assigned_ocr_jobs: ocrJobs,
      schedule_today: [],
    });
  } catch (error) {
    console.error('Staff worktray error:', error);
    return res.status(500).json({ error: 'staff_worktray_failed' });
  }
});

module.exports = router;
