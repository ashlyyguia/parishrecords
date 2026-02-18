const express = require('express');
const { v4: uuidv4 } = require('uuid');

const { getAdmin } = require('../firebase_admin');
const { requireAdmin, requireStaff } = require('../middleware/auth');
const { logAudit } = require('../utils/audit');
const { recordMetric } = require('../utils/analytics');

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

function normalizeRecordDoc(doc) {
  const data = doc.data() || {};
  return {
    id: doc.id,
    type: data.type || null,
    text: data.text || data.name || null,
    image_ref: data.image_ref || null,
    source: data.source || data.parish_id || null,
    notes: data.notes || null,
    created_at: toIso(data.created_at) || toIso(data.date) || new Date().toISOString(),
    certificate_status: data.certificate_status || data.certificateStatus || null,
  };
}

router.get('/', async (req, res) => {
  try {
    const admin = getAdmin();
    const db = admin.firestore();

    const limit = Math.min(parseInt(req.query.limit || '50', 10) || 50, 200);
    const typeRaw = req.query.type ? req.query.type.toString().trim().toLowerCase() : null;

    let snap;
    if (typeRaw) {
      // Avoid composite indexes by not using orderBy with where(type == ...)
      snap = await db.collection('records').where('type', '==', typeRaw).limit(limit).get();
    } else {
      snap = await db.collection('records').orderBy('created_at', 'desc').limit(limit).get();
    }

    const rows = snap.docs
      .map(normalizeRecordDoc)
      .filter((r) => r && r.id)
      .sort((a, b) => {
        const aTime = a.created_at ? new Date(a.created_at).getTime() : 0;
        const bTime = b.created_at ? new Date(b.created_at).getTime() : 0;
        return bTime - aTime;
      });

    res.json({ rows, records: rows, count: rows.length });
  } catch (error) {
    console.error('Get records error:', error);
    res.status(500).json({ error: 'Failed to fetch records' });
  }
});

router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const admin = getAdmin();
    const db = admin.firestore();

    const doc = await db.collection('records').doc(id).get();
    if (!doc.exists) {
      return res.status(404).json({ error: 'Record not found' });
    }

    const row = normalizeRecordDoc(doc);

    await logAudit(req, {
      action: 'Sacrament Record Viewed',
      resourceType: `${row.type || 'record'}_record`,
      resourceId: id,
      newValues: { name: row.text },
    });

    return res.json({
      id: row.id,
      type: row.type,
      name: row.text,
      notes: row.notes,
      date: row.created_at,
      parish: row.source,
      place: null,
      certificate_status: row.certificate_status,
      created_at: row.created_at,
    });
  } catch (error) {
    console.error('Get record error:', error);
    return res.status(500).json({ error: 'Failed to fetch record' });
  }
});

router.post('/', requireStaff, async (req, res) => {
  try {
    const admin = getAdmin();
    const db = admin.firestore();

    const body = req.body || {};

    const id = (body.id || '').toString().trim() || uuidv4();
    const type = (body.type || 'baptism').toString().trim().toLowerCase();
    const text = (body.text || 'Unnamed Record').toString();
    const source = (body.source || 'default_parish').toString();
    const imageRef = body.image_ref ? body.image_ref.toString() : null;
    const notes = body.notes ? body.notes.toString() : null;
    const certificateStatus = (body.certificate_status || body.certificateStatus || 'pending').toString();

    const createdByUid = req.user && req.user.uid ? req.user.uid.toString() : null;
    const createdByEmail = req.user && req.user.email ? req.user.email.toString() : null;

    const now = new Date();

    await db.collection('records').doc(id).set(
      {
        type,
        text,
        source,
        image_ref: imageRef,
        notes,
        certificate_status: certificateStatus,
        created_at: now,
        updated_at: now,
        created_by_uid: createdByUid,
        created_by_email: createdByEmail,
        deleted_at: null,
        deleted_by: null,
        deleted_reason: null,
      },
      { merge: true },
    );

    await recordMetric('records', `${type}_created`, 1, { parishId: source });

    await logAudit(req, {
      action: 'Sacrament Record Added',
      resourceType: `${type}_record`,
      resourceId: id,
      newValues: { name: text, parishId: source },
    });

    return res.status(201).json({ message: 'Record created successfully', recordId: id });
  } catch (error) {
    console.error('Create record error:', error);
    return res.status(500).json({ error: 'Failed to create record' });
  }
});

router.put('/:id', requireStaff, async (req, res) => {
  try {
    const { id } = req.params;
    const admin = getAdmin();
    const db = admin.firestore();

    const body = req.body || {};

    const updates = {};

    if (body.type !== undefined) updates.type = body.type.toString().trim().toLowerCase();
    if (body.text !== undefined) updates.text = body.text.toString();
    if (body.source !== undefined) updates.source = body.source.toString();
    if (body.image_ref !== undefined) updates.image_ref = body.image_ref ? body.image_ref.toString() : null;
    if (body.notes !== undefined) updates.notes = body.notes ? body.notes.toString() : null;
    if (body.certificate_status !== undefined) updates.certificate_status = body.certificate_status ? body.certificate_status.toString() : null;
    if (body.certificateStatus !== undefined) updates.certificate_status = body.certificateStatus ? body.certificateStatus.toString() : null;

    updates.updated_at = new Date();

    await db.collection('records').doc(id).set(updates, { merge: true });

    await logAudit(req, {
      action: 'Sacrament Record Updated',
      resourceType: `${updates.type || 'record'}_record`,
      resourceId: id,
      newValues: { name: updates.text || null },
    });

    return res.json({ message: 'Record updated successfully' });
  } catch (error) {
    console.error('Update record error:', error);
    return res.status(500).json({ error: 'Failed to update record' });
  }
});

router.put('/:id/certificate-status', requireStaff, async (req, res) => {
  try {
    const { id } = req.params;
    const status = req.body && req.body.status ? req.body.status.toString() : null;
    if (!status) {
      return res.status(400).json({ error: 'Missing status' });
    }

    const admin = getAdmin();
    const db = admin.firestore();

    await db.collection('records').doc(id).set(
      {
        certificate_status: status,
        updated_at: new Date(),
      },
      { merge: true },
    );

    await logAudit(req, {
      action: 'Certificate Status Updated',
      resourceType: 'record',
      resourceId: id,
      newValues: { status },
    });

    return res.json({ message: 'Certificate status updated successfully' });
  } catch (error) {
    console.error('Update certificate status error:', error);
    return res.status(500).json({ error: 'Failed to update certificate status' });
  }
});

router.delete('/:id', requireAdmin, async (req, res) => {
  try {
    const { id } = req.params;
    const admin = getAdmin();
    const db = admin.firestore();

    const deletedBy =
      (req.user && (req.user.email || req.user.uid)) ||
      'admin';

    await db.collection('records').doc(id).set(
      {
        deleted_at: new Date(),
        deleted_by: deletedBy.toString(),
        deleted_reason: 'Deleted via app',
        updated_at: new Date(),
      },
      { merge: true },
    );

    await logAudit(req, {
      action: 'Sacrament Record Deleted',
      resourceType: 'record',
      resourceId: id,
      oldValues: {},
    });

    return res.json({ message: 'Record deleted successfully' });
  } catch (error) {
    console.error('Delete record error:', error);
    return res.status(500).json({ error: 'Failed to delete record' });
  }
});

module.exports = router;
