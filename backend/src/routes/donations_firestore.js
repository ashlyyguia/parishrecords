const express = require('express');

const { getAdmin } = require('../firebase_admin');
const { requireFinance } = require('../middleware/auth');
const { logAudit } = require('../utils/audit');

const router = express.Router();

function requireAuth(req, res, next) {
  const uid = req.user && req.user.uid ? req.user.uid.toString() : null;
  if (!uid) return res.status(401).json({ error: 'Unauthorized' });
  return next();
}

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

function parseNumber(val) {
  if (val == null) return 0;
  if (typeof val === 'number') return val;
  const n = Number(val);
  return Number.isFinite(n) ? n : 0;
}

function normalizeDonationDoc(doc) {
  const d = doc.data() || {};
  return {
    id: doc.id,
    date: toIso(d.date) || toIso(d.created_at) || null,
    donor_name: d.donor_name || null,
    donor_id: d.donor_id || null,
    anonymous: d.anonymous === true,
    amount: parseNumber(d.amount),
    method: d.method || null,
    campaign: d.campaign || null,
    reconciled: d.reconciled === true,
    reconciled_at: toIso(d.reconciled_at) || null,
    receipt_url: d.receipt_url || null,
    created_at: toIso(d.created_at) || null,
    updated_at: toIso(d.updated_at) || null,
  };
}

// GET /api/donations?limit=10
router.get('/', requireFinance, async (req, res) => {
  try {
    const admin = getAdmin();
    const db = admin.firestore();

    const limit = Math.min(parseInt(req.query.limit || '200', 10) || 200, 500);

    const snap = await db
      .collection('donations')
      .orderBy('created_at', 'desc')
      .limit(limit)
      .get();

    const rows = snap.docs.map(normalizeDonationDoc);
    return res.json({ rows });
  } catch (error) {
    console.error('Donations list error:', error);
    return res.status(500).json({ error: 'donations_list_failed' });
  }
});

// POST /api/donations
// Body: { amount, method, campaign, donor_name, anonymous }
router.post('/', requireAuth, async (req, res) => {
  try {
    const uid = req.user && req.user.uid ? req.user.uid.toString() : null;
    if (!uid) return res.status(401).json({ error: 'Unauthorized' });

    const body = req.body || {};
    const amount = parseNumber(body.amount);
    if (!(amount > 0)) {
      return res.status(400).json({ error: 'Invalid amount' });
    }

    const anonymous = body.anonymous === true;
    const donorName = anonymous ? null : (body.donor_name || '').toString().trim();

    const method = (body.method || 'cash').toString().trim().toLowerCase();
    const campaign = body.campaign != null ? body.campaign.toString().trim() : null;

    const admin = getAdmin();
    const db = admin.firestore();

    const ref = db.collection('donations').doc();
    const now = new Date();

    await ref.set({
      amount,
      method,
      campaign,
      anonymous,
      donor_name: donorName,
      donor_id: uid,
      reconciled: false,
      created_at: now,
      updated_at: now,
    });

    await logAudit(req, {
      action: 'Donation Created',
      resourceType: 'donation',
      resourceId: ref.id,
      newValues: { amount, method, campaign, anonymous },
    });

    return res.json({ ok: true, donation_id: ref.id });
  } catch (error) {
    console.error('Donation create error:', error);
    return res.status(500).json({ error: 'donation_create_failed' });
  }
});

// PUT /api/donations/:id/reconcile
router.put('/:id/reconcile', requireFinance, async (req, res) => {
  try {
    const uid = req.user && req.user.uid ? req.user.uid.toString() : null;
    if (!uid) return res.status(401).json({ error: 'Unauthorized' });

    const id = (req.params.id || '').toString();
    if (!id) return res.status(400).json({ error: 'Missing donation id' });

    const admin = getAdmin();
    const db = admin.firestore();

    const ref = db.collection('donations').doc(id);
    const snap = await ref.get();
    if (!snap.exists) return res.status(404).json({ error: 'Donation not found' });

    const current = snap.data() || {};
    const currentReconciled = current.reconciled === true;

    let reconciled;
    if (typeof req.body?.reconciled === 'boolean') {
      reconciled = req.body.reconciled;
    } else {
      reconciled = !currentReconciled;
    }

    await ref.set(
      {
        reconciled,
        reconciled_at: reconciled ? new Date() : null,
        reconciled_by: reconciled ? uid : null,
        updated_at: new Date(),
      },
      { merge: true },
    );

    await logAudit(req, {
      action: 'Donation Reconciled',
      resourceType: 'donation',
      resourceId: id,
      oldValues: { reconciled: currentReconciled },
      newValues: { reconciled },
    });

    return res.json({ ok: true, reconciled });
  } catch (error) {
    console.error('Donation reconcile error:', error);
    return res.status(500).json({ error: 'donation_reconcile_failed' });
  }
});

module.exports = router;
