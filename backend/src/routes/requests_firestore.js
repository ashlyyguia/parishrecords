const express = require('express');
const { v4: uuidv4 } = require('uuid');

const { getAdmin } = require('../firebase_admin');
const { requireAdmin, requireStaff } = require('../middleware/auth');
const { logAudit } = require('../utils/audit');
const { recordMetric } = require('../utils/analytics');

const router = express.Router();

function requireAuth(req, res, next) {
  const uid = req.user && req.user.uid ? req.user.uid.toString() : null;
  if (!uid) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  return next();
}

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

function normalizeRequestDoc(doc) {
  const data = doc.data() || {};
  return {
    parish_id: data.parish_id || DEFAULT_PARISH,
    request_id: doc.id,
    record_id: data.record_id || null,
    request_type: data.request_type || null,
    requester_name: data.requester_name || null,
    status: data.status || 'pending',
    requested_at: toIso(data.requested_at) || null,
    processed_at: toIso(data.processed_at) || null,
    processed_by: data.processed_by || null,
    notification_sent: data.notification_sent === true,
  };
}

router.get('/', requireAuth, async (req, res) => {
  try {
    const admin = getAdmin();
    const db = admin.firestore();

    const parishId = (req.query.parish_id || DEFAULT_PARISH).toString();
    const limit = Math.min(parseInt(req.query.limit || '50', 10) || 50, 200);

    const uid = req.user && req.user.uid ? req.user.uid.toString() : null;
    const role = req.user && req.user.role;
    const isAdmin = req.user && req.user.admin === true;
    const isStaff = role === 'staff' || role === 'admin' || isAdmin;

    const userIdFilter = req.query.user_id ? req.query.user_id.toString() : null;

    let q = db.collection('requests').where('parish_id', '==', parishId);

    if (userIdFilter) {
      if (!uid) return res.status(401).json({ error: 'Unauthorized' });
      if (userIdFilter !== uid && !isStaff) {
        return res.status(403).json({ error: 'Forbidden' });
      }
      q = q.where('created_by_uid', '==', userIdFilter);
    }

    const snap = await q.orderBy('requested_at', 'desc').limit(limit).get();

    const rows = snap.docs.map(normalizeRequestDoc);
    return res.json({ rows });
  } catch (error) {
    console.error('Get certificate requests error:', error);
    return res.status(500).json({ error: 'requests_list_failed' });
  }
});

// GET /api/requests/:id
router.get('/:id', requireAuth, async (req, res) => {
  try {
    const uid = req.user && req.user.uid ? req.user.uid.toString() : null;
    if (!uid) return res.status(401).json({ error: 'Unauthorized' });

    const role = req.user && req.user.role;
    const isAdmin = req.user && req.user.admin === true;
    const isStaff = role === 'staff' || role === 'admin' || isAdmin;

    const id = (req.params.id || '').toString();
    if (!id) return res.status(400).json({ error: 'Missing request id' });

    const admin = getAdmin();
    const db = admin.firestore();
    const snap = await db.collection('requests').doc(id).get();
    if (!snap.exists) return res.status(404).json({ error: 'Request not found' });

    const data = snap.data() || {};
    const owner = (data.created_by_uid || '').toString();
    if (owner && owner !== uid && !isStaff) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    const row = normalizeRequestDoc(snap);
    // Attach lightweight timeline (derived from timestamps)
    row.timeline = [
      {
        status: 'submitted',
        at: toIso(data.created_at) || toIso(data.requested_at) || null,
      },
      {
        status: data.status || 'pending',
        at: toIso(data.processed_at) || null,
      },
    ];

    return res.json({ row });
  } catch (error) {
    console.error('Get request detail error:', error);
    return res.status(500).json({ error: 'request_detail_failed' });
  }
});

// POST /api/requests/:id/cancel
router.post('/:id/cancel', requireAuth, async (req, res) => {
  try {
    const uid = req.user && req.user.uid ? req.user.uid.toString() : null;
    if (!uid) return res.status(401).json({ error: 'Unauthorized' });

    const id = (req.params.id || '').toString();
    if (!id) return res.status(400).json({ error: 'Missing request id' });

    const admin = getAdmin();
    const db = admin.firestore();
    const ref = db.collection('requests').doc(id);
    const snap = await ref.get();
    if (!snap.exists) return res.status(404).json({ error: 'Request not found' });

    const data = snap.data() || {};
    const owner = (data.created_by_uid || '').toString();
    if (owner && owner !== uid) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    const currentStatus = (data.status || 'pending').toString();
    if (currentStatus === 'ready' || currentStatus === 'approved') {
      return res.status(400).json({ error: 'Cannot cancel a completed request' });
    }

    await ref.set(
      {
        status: 'cancelled',
        cancelled_at: new Date(),
        updated_at: new Date(),
      },
      { merge: true },
    );

    await logAudit(req, {
      action: 'Certificate Request Cancelled',
      resourceType: 'certificate_request',
      resourceId: id,
      oldValues: { status: currentStatus },
      newValues: { status: 'cancelled' },
    });

    return res.json({ ok: true });
  } catch (error) {
    console.error('Cancel request error:', error);
    return res.status(500).json({ error: 'request_cancel_failed' });
  }
});

router.post('/', requireAuth, async (req, res) => {
  try {
    const admin = getAdmin();
    const db = admin.firestore();

    const body = req.body || {};
    const parishId = (body.parish_id || DEFAULT_PARISH).toString();
    const requestType = (body.request_type || 'baptism').toString().toLowerCase();
    const requesterName = (body.requester_name || '').toString();
    const recordId = body.record_id ? body.record_id.toString() : null;

    const requestId = uuidv4();
    const now = new Date();

    await db.collection('requests').doc(requestId).set({
      parish_id: parishId,
      request_type: requestType,
      requester_name: requesterName,
      record_id: recordId,
      status: 'pending',
      requested_at: now,
      processed_at: null,
      processed_by: null,
      notification_sent: false,
      created_by_uid: req.user && req.user.uid ? req.user.uid.toString() : null,
      created_by_email: req.user && req.user.email ? req.user.email.toString() : null,
      created_at: now,
      updated_at: now,
    });

    await recordMetric('requests', `certificate_${requestType}_created`, 1, {
      parishId,
      requestType,
    });

    await logAudit(req, {
      action: 'Certificate Request Created',
      resourceType: 'certificate_request',
      resourceId: requestId,
      newValues: { requestType, requesterName, recordId },
    });

    return res.json({ ok: true, request_id: requestId });
  } catch (error) {
    console.error('Create certificate request error:', error);
    return res.status(500).json({ error: 'requests_create_failed' });
  }
});

router.put('/:id', requireStaff, async (req, res) => {
  try {
    const requestId = req.params.id;
    const body = req.body || {};

    const admin = getAdmin();
    const db = admin.firestore();

    const parishId = (body.parish_id || DEFAULT_PARISH).toString();
    const status = body.status ? body.status.toString() : null;

    const notificationSent =
      typeof body.notification_sent === 'boolean' ? body.notification_sent : null;

    const updates = {
      parish_id: parishId,
      updated_at: new Date(),
    };

    if (status) {
      updates.status = status;
      if (status !== 'pending') {
        updates.processed_at = new Date();
        updates.processed_by =
          (req.user && (req.user.email || req.user.uid)) || null;
      }
    }

    if (notificationSent !== null) {
      updates.notification_sent = notificationSent;
    }

    await db.collection('requests').doc(requestId).set(updates, { merge: true });

    await logAudit(req, {
      action: 'Certificate Request Updated',
      resourceType: 'certificate_request',
      resourceId: requestId,
      newValues: { status, notificationSent },
    });

    if (status) {
      await recordMetric('requests', `certificate_status_${status}`, 1, {
        parishId,
        status,
      });
    }

    return res.json({ ok: true });
  } catch (error) {
    console.error('Update certificate request error:', error);
    return res.status(500).json({ error: 'requests_update_failed' });
  }
});

module.exports = router;
