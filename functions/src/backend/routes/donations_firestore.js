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

async function notifyFinanceAndAdmin(db, payload) {
  const {
    donationId,
    title = 'New online donation',
    body,
    type = 'online_donation',
    route = '/donations',
    createdByUid = 'system',
  } = payload;
  if (!donationId || !body) return;
  try {
    const now = new Date();
    await db.collection('notifications').add({
      title,
      body,
      audience: ['finance', 'admin'],
      type,
      route,
      resource_id: donationId,
      created_at: now,
      created_by_uid: createdByUid,
    });
    await db.collection('donations').doc(donationId).set(
      { finance_notified: true },
      { merge: true }
    );
  } catch (err) {
    console.warn('[Donations API] Finance notify failed:', err.message);
  }
}

function formatAmount(amount) {
  const n = parseNumber(amount);
  return n > 0 ? `₱${n.toFixed(2)}` : 'amount pending in app';
}

function paymentChannelLabel(paymentMethod) {
  if (paymentMethod === 'gcash') return 'GCash';
  if (paymentMethod === 'maya') return 'Maya';
  if (paymentMethod === 'gotyme') return 'GoTyme';
  return paymentMethod || 'online';
}

async function notifyDonationRecord(db, payload) {
  const {
    donationId,
    amount,
    donorName,
    paymentMethod,
    donationType,
    campaign,
    certificateType,
    source,
    createdByUid,
  } = payload;

  const name = donorName || 'Donor';
  const campaignNorm = (campaign || '').toString().trim().toLowerCase();
  const sourceNorm = (source || '').toString().trim().toLowerCase();

  if (campaignNorm === 'certificate') {
    const cert = (certificateType || 'Certificate').toString().trim();
    const method = (paymentMethod || 'cash').toString();
    await notifyFinanceAndAdmin(db, {
      donationId,
      title: 'Certificate fee recorded',
      body: `${name} — ${formatAmount(amount)} for ${cert} (${method})`,
      type: 'certificate_fee',
      route: '/certificate-fees',
      createdByUid,
    });
    return;
  }

  if (sourceNorm === 'online' || payload.online === true) {
    const channel = paymentChannelLabel(paymentMethod);
    await notifyFinanceAndAdmin(db, {
      donationId,
      title: 'New online donation',
      body: `${name} — ${formatAmount(amount)} via ${channel} (${donationType || 'Donation'})`,
      type: 'online_donation',
      route: '/donations',
      createdByUid,
    });
    return;
  }

  const camp = (campaign || 'General').toString();
  const method = (paymentMethod || 'cash').toString();
  await notifyFinanceAndAdmin(db, {
    donationId,
    title: 'Cash donation recorded',
    body: `${name} — ${formatAmount(amount)} in-person ${method} (${camp})`,
    type: 'cash_donation',
    route: '/donations',
    createdByUid,
  });
}

// POST /api/donations/online
router.post('/online', requireAuth, async (req, res) => {
  try {
    const uid = req.user?.uid?.toString();
    if (!uid) return res.status(401).json({ error: 'Unauthorized' });

    const body = req.body || {};
    const amount = parseNumber(body.amount);
    if (!(amount > 0)) {
      return res.status(400).json({ error: 'Invalid amount' });
    }

    const donationType = (body.donation_type || body.campaign || 'General')
      .toString()
      .trim();
    const paymentMethod = (body.payment_method || body.method || 'gcash')
      .toString()
      .trim()
      .toLowerCase();
    const donorName = (body.donor_name || '').toString().trim();
    const donorEmail = (body.donor_email || '').toString().trim();
    const donorPhone = (body.donor_phone || '').toString().trim();
    const donorMessage =
      body.donor_message != null ? body.donor_message.toString().trim() : '';

    const admin = getAdmin();
    const db = admin.firestore();
    const ref = db.collection('donations').doc();
    const now = new Date();

    await ref.set({
      amount,
      method: paymentMethod,
      campaign: donationType,
      donation_type: donationType,
      payment_method: paymentMethod,
      donor_name: donorName,
      donor_email: donorEmail,
      donor_phone: donorPhone,
      ...(donorMessage ? { donor_message: donorMessage } : {}),
      anonymous: body.anonymous === true,
      donor_id: uid,
      reconciled: false,
      source: 'online',
      online: true,
      status: 'pending_verification',
      qr_transfer_confirmed: true,
      qr_transfer_confirmed_at: now,
      created_at: now,
      updated_at: now,
    });

    await notifyDonationRecord(db, {
      donationId: ref.id,
      amount,
      donorName,
      paymentMethod,
      donationType,
      source: 'online',
      online: true,
      createdByUid: uid,
    });

    await logAudit(req, {
      action: 'Online Donation Recorded',
      resourceType: 'donation',
      resourceId: ref.id,
      newValues: { amount, paymentMethod, donationType },
    });

    return res.json({ ok: true, donation_id: ref.id });
  } catch (error) {
    console.error('Online donation create error:', error);
    return res.status(500).json({ error: 'online_donation_create_failed' });
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
      source: body.source != null ? body.source.toString().trim() : 'manual_cash',
      created_at: now,
      updated_at: now,
    });

    await notifyDonationRecord(db, {
      donationId: ref.id,
      amount,
      donorName: anonymous ? 'Anonymous' : (donorName || 'Donor'),
      paymentMethod: method,
      campaign,
      certificateType: body.certificate_type || body.certificateType,
      source: body.source != null ? body.source.toString().trim() : 'manual_cash',
      createdByUid: uid,
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
