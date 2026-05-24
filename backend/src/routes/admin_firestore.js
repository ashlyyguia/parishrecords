const express = require('express');

const { getAdmin } = require('../firebase_admin');
const { verifyFirebaseToken, requireAdmin } = require('../middleware/auth');

const router = express.Router();

// Collection names for different record types
const RECORD_COLLECTIONS = [
  'baptism_records',
  'marriage_records',
  'confirmation_records',
  'funeral_records',
];

router.use(verifyFirebaseToken);
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

    // Query all record type collections
    const allRecords = [];

    for (const collection of RECORD_COLLECTIONS) {
      try {
        const snap = await db
          .collection(collection)
          .where('created_at', '>=', since)
          .orderBy('created_at', 'desc')
          .limit(limit)
          .get();

        const type = collection.replace('_records', '');
        for (const doc of snap.docs) {
          const data = doc.data() || {};
          allRecords.push({
            id: doc.id,
            type: type,
            text: data.text || null,
            image_ref: data.image_ref || null,
            source: data.source || null,
            notes: data.notes || null,
            certificate_status: data.certificate_status || null,
            created_at: toIso(data.created_at) || null,
          });
        }
      } catch (e) {
        console.error(`Error fetching from ${collection}:`, e.message);
      }
    }

    // Sort by created_at desc and limit
    allRecords.sort((a, b) => {
      const dateA = new Date(a.created_at || 0);
      const dateB = new Date(b.created_at || 0);
      return dateB - dateA;
    });

    const rows = allRecords.slice(0, limit);
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

    // Query all record type collections
    const allRecords = [];

    for (const collection of RECORD_COLLECTIONS) {
      try {
        const fetchLimit = userId ? Math.min(limit * 10, 500) : limit;
        const snap = await db
          .collection(collection)
          .orderBy('created_at', 'desc')
          .limit(fetchLimit)
          .get();

        const type = collection.replace('_records', '');
        for (const doc of snap.docs) {
          const data = doc.data() || {};

          // Filter by user_id if specified
          if (userId && (data.created_by_uid || '').toString() !== userId) {
            continue;
          }

          allRecords.push({
            id: doc.id,
            type: type,
            text: data.text || null,
            image_ref: data.image_ref || null,
            source: data.source || null,
            created_at: toIso(data.created_at) || null,
          });
        }
      } catch (e) {
        console.error(`Error fetching from ${collection}:`, e.message);
      }
    }

    // Sort by created_at desc and limit
    allRecords.sort((a, b) => {
      const dateA = new Date(a.created_at || 0);
      const dateB = new Date(b.created_at || 0);
      return dateB - dateA;
    });

    const rows = allRecords.slice(0, limit);
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
    if (data.notes !== undefined) updates.notes = data.notes ? data.notes.toString() : null;
    if (data.certificate_status !== undefined) updates.certificate_status = data.certificate_status ? data.certificate_status.toString() : null;
    updates.updated_at = new Date();

    // Try to find and update in any of the record collections
    let updated = false;
    for (const collection of RECORD_COLLECTIONS) {
      try {
        const docRef = db.collection(collection).doc(id);
        const doc = await docRef.get();
        if (doc.exists) {
          await docRef.update(updates);
          updated = true;
          break;
        }
      } catch (e) {
        // Continue to next collection
      }
    }

    if (!updated) {
      return res.status(404).json({ error: 'Record not found in any collection' });
    }

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

    // Try to find and soft-delete in any of the record collections
    let deleted = false;
    for (const collection of RECORD_COLLECTIONS) {
      try {
        const docRef = db.collection(collection).doc(id);
        const doc = await docRef.get();
        if (doc.exists) {
          await docRef.set(
            {
              deleted_at: new Date(),
              deleted_by: deletedBy.toString(),
              deleted_reason: 'Deleted via admin',
              updated_at: new Date(),
            },
            { merge: true },
          );
          deleted = true;
          break;
        }
      } catch (e) {
        // Continue to next collection
      }
    }

    if (!deleted) {
      return res.status(404).json({ error: 'Record not found in any collection' });
    }

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

    // Query all record type collections
    const recordsByType = {};
    const certificatesByStatus = {};
    let totalRecords = 0;

    for (const collection of RECORD_COLLECTIONS) {
      try {
        const snap = await db
          .collection(collection)
          .where('created_at', '>=', since)
          .get();

        const type = collection.replace('_records', '');
        recordsByType[type] = snap.size;
        totalRecords += snap.size;

        for (const doc of snap.docs) {
          const d = doc.data() || {};
          const status = (d.certificate_status || 'unknown').toString();
          certificatesByStatus[status] = (certificatesByStatus[status] || 0) + 1;
        }
      } catch (e) {
        console.error(`Error counting ${collection}:`, e.message);
      }
    }

    const usersSnap = await db.collection('users').get();
    const usersByRole = {};
    usersSnap.docs.forEach((doc) => {
      const role = ((doc.data() || {}).role || 'staff').toString();
      usersByRole[role] = (usersByRole[role] || 0) + 1;
    });

    return res.json({
      total_records_last_days: totalRecords,
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

    // Query all record type collections
    const countsByDate = {};

    for (const collection of RECORD_COLLECTIONS) {
      try {
        const snap = await db
          .collection(collection)
          .where('created_at', '>=', since)
          .get();

        for (const doc of snap.docs) {
          const d = doc.data() || {};
          const iso = toIso(d.created_at);
          if (!iso) continue;
          const key = iso.substring(0, 10);
          countsByDate[key] = (countsByDate[key] || 0) + 1;
        }
      } catch (e) {
        console.error(`Error fetching daily metrics from ${collection}:`, e.message);
      }
    }

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

// Debug endpoint to check collections
router.get('/analytics/debug', async (_req, res) => {
  try {
    const admin = getAdmin();
    const db = admin.firestore();

    const collections = ['households', 'household_members', 'sacrament_records', 'requests', 'donations', 'ocr_jobs', 'users'];
    const results = {};

    for (const coll of collections) {
      try {
        const snap = await db.collection(coll).limit(3).get();
        results[coll] = {
          exists: true,
          docCount: snap.size,
          sampleIds: snap.docs.map(d => d.id),
        };
      } catch (e) {
        results[coll] = { exists: false, error: e.message };
      }
    }

    return res.json(results);
  } catch (error) {
    return res.status(500).json({ error: error.message });
  }
});

router.get('/analytics', async (_req, res) => {
  console.log('[Analytics] Endpoint hit!');
  try {
    const admin = getAdmin();
    const db = admin.firestore();

    console.log('[Analytics] Fetching counts from Firestore...');

    // Helper to get count - tries count() first, falls back to manual count
    async function getCount(collectionName, filterFn) {
      console.log(`[Analytics] Counting ${collectionName}...`);
      try {
        // Try aggregation count first (fast but may not work in all Firestore setups)
        const query = filterFn ? filterFn(db.collection(collectionName)) : db.collection(collectionName);
        const countSnap = await query.count().get();
        const count = countSnap.data().count;
        console.log(`[Analytics] ${collectionName} count:`, count);
        return count;
      } catch (countErr) {
        console.log(`[Analytics] count() failed for ${collectionName}, using manual count:`, countErr.message);
        try {
          // Fallback: get all docs and count (slower but more reliable)
          const query = filterFn ? filterFn(db.collection(collectionName)) : db.collection(collectionName);
          const snap = await query.limit(1000).get();
          console.log(`[Analytics] ${collectionName} manual count:`, snap.size, 'docs');
          // Log first doc ID if any found
          if (snap.size > 0) {
            console.log(`[Analytics] ${collectionName} first doc:`, snap.docs[0].id);
          }
          return snap.size;
        } catch (manualErr) {
          console.log(`[Analytics] Manual count failed for ${collectionName}:`, manualErr.message);
          return 0;
        }
      }
    }

    const [
      households,
      members,
      records,
      requests,
      donations,
      ocrPending,
    ] = await Promise.all([
      getCount('households', null),
      getCount('household_members', null),
      getCount('sacrament_records', null),
      getCount('requests', q => q.where('status', '==', 'pending')),
      getCount('donations', null),
      getCount('ocr_jobs', q => q.where('status', '==', 'pending')),
    ]);

    const result = {
      households,
      parishioners: members,
      records,
      requests,
      donations,
      ocrPending,
    };

    console.log('[Analytics] Result:', result);
    return res.json(result);
  } catch (error) {
    console.error('Admin analytics error:', error);
    return res.status(500).json({ error: 'Failed to fetch analytics', details: error.message });
  }
});

// DELETE /api/admin/users/:id - Delete user using Admin SDK
router.delete('/users/:id', async (req, res) => {
  try {
    const userId = req.params.id;
    const admin = getAdmin();
    
    // Delete from Firebase Auth using Admin SDK
    await admin.auth().deleteUser(userId);
    
    // Delete from Firestore
    await admin.firestore().collection('users').doc(userId).delete();
    
    return res.json({ success: true, message: 'User deleted successfully' });
  } catch (error) {
    console.error('Delete user error:', error);
    return res.status(500).json({ error: 'Failed to delete user', details: error.message });
  }
});

module.exports = router;
