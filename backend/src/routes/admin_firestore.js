const express = require('express');

const { getAdmin } = require('../firebase_admin');
const { requireAdmin } = require('../middleware/auth');

const router = express.Router();

router.use(requireAdmin);

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

function dateKey(d) {
  try {
    return d.toISOString().substring(0, 10);
  } catch (_) {
    return null;
  }
}

const DEFAULT_SETTINGS = {
  language: 'en',
  timezone: 'UTC',
  notify: true,
  auto_backup: false,
};

router.get('/settings', async (_req, res) => {
  try {
    const admin = getAdmin();
    const db = admin.firestore();

    const doc = await db.collection('settings').doc('global').get();
    if (!doc.exists) {
      return res.json(DEFAULT_SETTINGS);
    }

    const data = doc.data() || {};
    return res.json({
      language: data.language || DEFAULT_SETTINGS.language,
      timezone: data.timezone || DEFAULT_SETTINGS.timezone,
      notify: data.notify !== undefined ? !!data.notify : DEFAULT_SETTINGS.notify,
      auto_backup:
        data.auto_backup !== undefined
          ? !!data.auto_backup
          : (data.autoBackup !== undefined ? !!data.autoBackup : DEFAULT_SETTINGS.auto_backup),
    });
  } catch (error) {
    console.error('Admin settings fetch error:', error);
    return res.status(500).json({ error: 'Failed to fetch settings' });
  }
});

router.put('/settings', async (req, res) => {
  try {
    const admin = getAdmin();
    const db = admin.firestore();

    const body = req.body || {};

    const language = (body.language || DEFAULT_SETTINGS.language).toString();
    const timezone = (body.timezone || DEFAULT_SETTINGS.timezone).toString();
    const notify = body.notify !== undefined ? !!body.notify : DEFAULT_SETTINGS.notify;
    const autoBackup = body.auto_backup !== undefined ? !!body.auto_backup : !!body.autoBackup;

    await db.collection('settings').doc('global').set(
      {
        language,
        timezone,
        notify,
        auto_backup: autoBackup,
        updated_at: new Date(),
      },
      { merge: true },
    );

    return res.json({
      message: 'Settings updated successfully',
      settings: {
        language,
        timezone,
        notify,
        auto_backup: autoBackup,
      },
    });
  } catch (error) {
    console.error('Admin settings update error:', error);
    return res.status(500).json({ error: 'Failed to save settings' });
  }
});

router.get('/records/recent', async (req, res) => {
  try {
    const admin = getAdmin();
    const db = admin.firestore();

    const limit = Math.min(parseInt(req.query.limit, 10) || 100, 300);
    const days = Math.min(parseInt(req.query.days, 10) || 7, 3650);
    const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);

    const snap = await db
      .collection('records')
      .where('created_at', '>=', since)
      .orderBy('created_at', 'desc')
      .limit(limit)
      .get();

    const rows = snap.docs.map((doc) => {
      const data = doc.data() || {};
      return {
        id: doc.id,
        type: data.type || null,
        text: data.text || null,
        image_ref: data.image_ref || null,
        source: data.source || null,
        notes: data.notes || null,
        certificate_status: data.certificate_status || null,
        created_at: toIso(data.created_at) || null,
      };
    });

    return res.json({ rows, count: rows.length });
  } catch (error) {
    console.error('Admin recent records error:', error);
    return res.status(500).json({ error: 'Failed to fetch recent records' });
  }
});

router.get('/records', async (req, res) => {
  try {
    const admin = getAdmin();
    const db = admin.firestore();

    const limit = Math.min(parseInt(req.query.limit, 10) || 50, 200);
    const userId = req.query.user_id ? req.query.user_id.toString() : null;

    // Avoid composite index requirements (where(created_by_uid==X) + orderBy(created_at)).
    // Instead, query by created_at and filter in memory.
    const fetchLimit = userId ? Math.min(limit * 10, 500) : limit;
    const snap = await db
      .collection('records')
      .orderBy('created_at', 'desc')
      .limit(fetchLimit)
      .get();

    let docs = snap.docs;
    if (userId) {
      docs = docs.filter((d) => {
        const data = d.data() || {};
        return (data.created_by_uid || '').toString() === userId;
      });
    }
    docs = docs.slice(0, limit);

    const rows = docs.map((doc) => {
      const data = doc.data() || {};
      return {
        id: doc.id,
        type: data.type || null,
        text: data.text || null,
        image_ref: data.image_ref || null,
        source: data.source || null,
        created_at: toIso(data.created_at) || null,
      };
    });

    return res.json({ rows, count: rows.length });
  } catch (error) {
    console.error('Admin records list error:', error);
    return res.status(500).json({ error: 'Failed to fetch records' });
  }
});

router.put('/records/:id', async (req, res) => {
  try {
    const id = (req.params.id || '').toString();
    if (!id) {
      return res.status(400).json({ error: 'Missing record id' });
    }

    const admin = getAdmin();
    const db = admin.firestore();

    const data = req.body || {};
    const updates = {};
    if (data.text !== undefined) updates.text = data.text.toString();
    if (data.source !== undefined) updates.source = data.source.toString();
    if (data.image_ref !== undefined) updates.image_ref = data.image_ref ? data.image_ref.toString() : null;
    updates.updated_at = new Date();

    await db.collection('records').doc(id).set(updates, { merge: true });

    return res.json({ message: 'Record updated successfully', id });
  } catch (error) {
    console.error('Admin record update error:', error);
    return res.status(500).json({ error: 'Failed to update record' });
  }
});

router.delete('/records/:id', async (req, res) => {
  try {
    const id = (req.params.id || '').toString();
    if (!id) {
      return res.status(400).json({ error: 'Missing record id' });
    }

    const admin = getAdmin();
    const db = admin.firestore();

    const deletedBy =
      (req.user && (req.user.email || req.user.uid)) ||
      'admin';

    await db.collection('records').doc(id).set(
      {
        deleted_at: new Date(),
        deleted_by: deletedBy.toString(),
        deleted_reason: 'Deleted via admin',
        updated_at: new Date(),
      },
      { merge: true },
    );

    return res.json({ message: 'Record deleted successfully' });
  } catch (error) {
    console.error('Admin record delete error:', error);
    return res.status(500).json({ error: 'Failed to delete record' });
  }
});

router.get('/summary', async (req, res) => {
  try {
    const admin = getAdmin();
    const db = admin.firestore();

    const days = Math.min(parseInt(req.query.days, 10) || 7, 365);
    const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);

    const recordsSnap = await db
      .collection('records')
      .where('created_at', '>=', since)
      .get();

    const recordsByType = {};
    const certificatesByStatus = {};

    recordsSnap.docs.forEach((doc) => {
      const d = doc.data() || {};
      const type = (d.type || 'unknown').toString();
      const status = (d.certificate_status || 'unknown').toString();
      recordsByType[type] = (recordsByType[type] || 0) + 1;
      certificatesByStatus[status] = (certificatesByStatus[status] || 0) + 1;
    });

    const usersSnap = await db.collection('users').get();
    const usersByRole = {};
    usersSnap.docs.forEach((doc) => {
      const role = ((doc.data() || {}).role || 'staff').toString();
      usersByRole[role] = (usersByRole[role] || 0) + 1;
    });

    return res.json({
      total_records_last_days: recordsSnap.size,
      records_by_type: recordsByType,
      certificates_by_status: certificatesByStatus,
      total_users: usersSnap.size,
      users_by_role: usersByRole,
      generated_at: new Date().toISOString(),
    });
  } catch (error) {
    console.error('Admin summary error:', error);
    return res.status(500).json({ error: 'Failed to generate summary' });
  }
});

router.get('/metrics/records/daily', async (req, res) => {
  try {
    const admin = getAdmin();
    const db = admin.firestore();

    const days = Math.min(parseInt(req.query.days, 10) || 14, 365);
    const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);

    const snap = await db
      .collection('records')
      .where('created_at', '>=', since)
      .get();

    const countsByDate = {};
    snap.docs.forEach((doc) => {
      const d = doc.data() || {};
      const iso = toIso(d.created_at);
      if (!iso) return;
      const key = iso.substring(0, 10);
      countsByDate[key] = (countsByDate[key] || 0) + 1;
    });

    const daysArr = [];
    for (let i = days - 1; i >= 0; i--) {
      const d = new Date(Date.now() - i * 24 * 60 * 60 * 1000);
      const key = dateKey(d);
      daysArr.push({ date: key, total: countsByDate[key] || 0 });
    }

    return res.json({ days: daysArr });
  } catch (error) {
    console.error('Admin daily metrics error:', error);
    return res.status(500).json({ error: 'Failed to fetch daily metrics' });
  }
});

router.get('/analytics', async (_req, res) => {
  return res.json({ rows: [], count: 0 });
});

router.get('/logs', async (req, res) => {
  try {
    const admin = getAdmin();
    const db = admin.firestore();

    const limit = Math.min(parseInt(req.query.limit, 10) || 100, 500);
    const days = Math.min(parseInt(req.query.days, 10) || 7, 365);
    const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);

    const resourceIdFilter = req.query.resource_id
      ? req.query.resource_id.toString()
      : null;

    // Avoid composite index requirements when adding resource_id filter.
    const fetchLimit = resourceIdFilter ? Math.min(limit * 10, 1000) : limit;

    const snap = await db
      .collection('audit_logs')
      .where('timestamp', '>=', since)
      .orderBy('timestamp', 'desc')
      .limit(fetchLimit)
      .get();

    let docs = snap.docs;
    if (resourceIdFilter) {
      docs = docs.filter((d) => {
        const data = d.data() || {};
        return (data.resource_id || '').toString() === resourceIdFilter;
      });
    }
    docs = docs.slice(0, limit);

    const rows = docs.map((doc) => {
      const d = doc.data() || {};
      const detailsParts = [];
      if (d.resource_type) detailsParts.push(`${d.resource_type}`);
      if (d.resource_id) detailsParts.push(`#${d.resource_id}`);
      if (d.action) detailsParts.push(`→ ${d.action}`);
      const changeSummary =
        d.new_values && d.old_values
          ? ` ${d.old_values} → ${d.new_values}`
          : (d.new_values || d.old_values || '');

      return {
        id: doc.id,
        user_id: d.user_id || null,
        action: d.action || null,
        details: `${detailsParts.join(' ')}${changeSummary}`.trim(),
        action_time: toIso(d.timestamp) || null,
        resource_type: d.resource_type || null,
        resource_id: d.resource_id || null,
        old_values: d.old_values || null,
        new_values: d.new_values || null,
        ip_address: d.ip_address || null,
        user_agent: d.user_agent || null,
      };
    });

    return res.json({ rows, count: rows.length });
  } catch (error) {
    console.error('Admin logs fetch error:', error);
    return res.status(500).json({ error: 'Failed to fetch audit logs' });
  }
});

router.post('/logs', async (req, res) => {
  try {
    const admin = getAdmin();
    const db = admin.firestore();

    const body = req.body || {};

    const id = body.id ? body.id.toString() : null;
    const userId = (body.user_id || body.userId || '').toString();
    const action = (body.action || '').toString();
    const resourceType = body.resource_type || body.resourceType || null;
    const resourceId = body.resource_id || body.resourceId || null;
    const oldValues = body.old_values || body.oldValues || null;
    const newValues = body.new_values || body.newValues || null;

    const tsRaw = body.timestamp || body.action_time;
    const timestamp = tsRaw ? new Date(tsRaw) : new Date();

    if (!userId || !action) {
      return res.status(400).json({ error: 'Missing user_id or action' });
    }

    const docRef = id ? db.collection('audit_logs').doc(id) : db.collection('audit_logs').doc();

    await docRef.set({
      user_id: userId,
      action,
      resource_type: resourceType,
      resource_id: resourceId ? resourceId.toString() : null,
      old_values: oldValues && typeof oldValues === 'object' ? JSON.stringify(oldValues) : oldValues,
      new_values: newValues && typeof newValues === 'object' ? JSON.stringify(newValues) : newValues,
      timestamp,
      ip_address: req.ip || null,
      user_agent: req.get('user-agent') || null,
    });

    return res.json({ ok: true, id: docRef.id });
  } catch (error) {
    console.error('Admin log create error:', error);
    return res.status(500).json({ error: 'Failed to create audit log' });
  }
});

router.delete('/logs/:id', async (req, res) => {
  try {
    const id = (req.params.id || '').toString();
    if (!id) {
      return res.status(400).json({ error: 'Missing log id' });
    }

    const admin = getAdmin();
    const db = admin.firestore();

    await db.collection('audit_logs').doc(id).delete();

    return res.json({ message: 'Log deleted successfully' });
  } catch (error) {
    console.error('Admin log delete error:', error);
    return res.status(500).json({ error: 'Failed to delete log' });
  }
});

router.patch('/users/:id/role', async (req, res) => {
  try {
    const uid = (req.params.id || '').toString();
    const role = (req.body && req.body.role ? req.body.role.toString() : '').toString();

    if (!uid) {
      return res.status(400).json({ error: 'Missing user id' });
    }

    if (!['admin', 'staff'].includes(role)) {
      return res.status(400).json({ error: 'Invalid role' });
    }

    const admin = getAdmin();

    await admin.firestore().collection('users').doc(uid).set(
      { role },
      { merge: true },
    );

    const user = await admin.auth().getUser(uid);
    const claims = user.customClaims || {};
    if (role === 'admin') {
      claims.admin = true;
    } else {
      delete claims.admin;
    }
    await admin.auth().setCustomUserClaims(uid, claims);

    return res.json({ ok: true });
  } catch (error) {
    console.error('Admin update user role error:', error);
    return res.status(500).json({ error: 'Failed to update user role' });
  }
});

router.patch('/users/:id/status', async (req, res) => {
  try {
    const uid = (req.params.id || '').toString();
    const disabled = req.body ? req.body.disabled : undefined;

    if (!uid) {
      return res.status(400).json({ error: 'Missing user id' });
    }

    if (typeof disabled !== 'boolean') {
      return res.status(400).json({ error: 'Invalid disabled value' });
    }

    const admin = getAdmin();
    await admin.auth().updateUser(uid, { disabled });
    await admin.firestore().collection('users').doc(uid).set(
      { disabled },
      { merge: true },
    );

    return res.json({ ok: true });
  } catch (error) {
    console.error('Admin update user status error:', error);
    return res.status(500).json({ error: 'Failed to update user status' });
  }
});

router.get('/users/health', async (_req, res) => {
  try {
    const admin = getAdmin();
    const db = admin.firestore();

    await db.collection('users').limit(1).get();
    return res.json({ ok: true });
  } catch (error) {
    console.error('Admin users health error:', error);
    return res.status(500).json({ ok: false, error: 'Failed to query users collection' });
  }
});

router.post('/users/sync', async (_req, res) => {
  try {
    const admin = getAdmin();
    const db = admin.firestore();

    const snap = await db.collection('users').get();
    return res.json({ total: snap.size });
  } catch (error) {
    console.error('Admin users sync error:', error);
    return res.status(500).json({ error: 'Failed to compute users total' });
  }
});

module.exports = router;
