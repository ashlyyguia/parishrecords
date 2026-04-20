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

function normalizeJobDoc(doc) {
  const d = doc.data() || {};
  return {
    id: doc.id,
    type: d.type || null,
    title: d.title || null,
    status: d.status || null,
    assigned_to: d.assigned_to || null,
    created_by: d.created_by || null,
    book_number: d.book_number || null,
    page_number: d.page_number || null,
    notes: d.notes || null,
    locked: d.locked === true,
    mapped_fields: d.mapped_fields || null,
    created_at: toIso(d.created_at) || null,
    updated_at: toIso(d.updated_at) || null,
  };
}

router.get('/', async (req, res) => {
  try {
    const admin = getAdmin();
    const db = admin.firestore();

    const limit = Math.min(parseInt(req.query.limit || '50', 10) || 50, 200);
    const assignedTo = req.query.assigned_to ? req.query.assigned_to.toString() : null;

    let q = db.collection('ocr_jobs').orderBy('created_at', 'desc');
    if (assignedTo) {
      q = q.where('assigned_to', '==', assignedTo);
    }

    const snap = await q.limit(limit).get();
    const rows = snap.docs.map(normalizeJobDoc);
    return res.json({ rows });
  } catch (error) {
    console.error('OCR jobs list error:', error);
    return res.status(500).json({ error: 'ocr_jobs_list_failed' });
  }
});

router.post('/', async (req, res) => {
  try {
    const uid = req.user && req.user.uid ? req.user.uid.toString() : null;
    if (!uid) return res.status(401).json({ error: 'Unauthorized' });

    const body = req.body || {};
    const type = (body.type || 'baptism').toString().trim().toLowerCase();
    const title = (body.title || `${type} OCR Job`).toString();

    const admin = getAdmin();
    const db = admin.firestore();

    const now = new Date();

    const docRef = await db.collection('ocr_jobs').add({
      type,
      title,
      status: 'processing',
      assigned_to: body.assigned_to ? body.assigned_to.toString() : uid,
      created_by: uid,
      book_number: body.book_number || null,
      page_number: body.page_number || null,
      notes: body.notes || null,
      locked: false,
      mapped_fields: null,
      created_at: now,
      updated_at: now,
    });

    await logAudit(req, {
      action: 'OCR Job Created',
      resourceType: 'ocr_job',
      resourceId: docRef.id,
      newValues: { type, title },
    });

    return res.status(201).json({ ok: true, id: docRef.id });
  } catch (error) {
    console.error('OCR jobs create error:', error);
    return res.status(500).json({ error: 'ocr_jobs_create_failed' });
  }
});

router.get('/:id', async (req, res) => {
  try {
    const admin = getAdmin();
    const db = admin.firestore();

    const id = (req.params.id || '').toString();
    const doc = await db.collection('ocr_jobs').doc(id).get();
    if (!doc.exists) return res.status(404).json({ error: 'Not found' });

    return res.json(normalizeJobDoc(doc));
  } catch (error) {
    console.error('OCR job get error:', error);
    return res.status(500).json({ error: 'ocr_job_get_failed' });
  }
});

router.post('/:id/claim', async (req, res) => {
  try {
    const uid = req.user && req.user.uid ? req.user.uid.toString() : null;
    if (!uid) return res.status(401).json({ error: 'Unauthorized' });

    const admin = getAdmin();
    const db = admin.firestore();

    const id = (req.params.id || '').toString();
    if (!id) return res.status(400).json({ error: 'Missing job id' });

    await db.collection('ocr_jobs').doc(id).set(
      {
        assigned_to: uid,
        updated_at: new Date(),
      },
      { merge: true },
    );

    await logAudit(req, {
      action: 'OCR Job Claimed',
      resourceType: 'ocr_job',
      resourceId: id,
      newValues: { assigned_to: uid },
    });

    return res.json({ ok: true });
  } catch (error) {
    console.error('OCR job claim error:', error);
    return res.status(500).json({ error: 'ocr_job_claim_failed' });
  }
});

router.put('/:id/mapped_fields', async (req, res) => {
  try {
    const uid = req.user && req.user.uid ? req.user.uid.toString() : null;
    if (!uid) return res.status(401).json({ error: 'Unauthorized' });

    const id = (req.params.id || '').toString();
    const body = req.body || {};

    const admin = getAdmin();
    const db = admin.firestore();

    await db.collection('ocr_jobs').doc(id).set(
      {
        mapped_fields: body.mapped_fields || body.mappedFields || null,
        updated_at: new Date(),
      },
      { merge: true },
    );

    await logAudit(req, {
      action: 'OCR Job Fields Updated',
      resourceType: 'ocr_job',
      resourceId: id,
      newValues: { updated: true },
    });

    return res.json({ ok: true });
  } catch (error) {
    console.error('OCR job mapped fields update error:', error);
    return res.status(500).json({ error: 'ocr_job_update_failed' });
  }
});

router.post('/:id/preprocess', async (_req, res) => {
  return res.json({ ok: true, message: 'preprocess not implemented' });
});

module.exports = router;
