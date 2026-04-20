const express = require('express');

const { getAdmin } = require('../firebase_admin');
const { requireFinance } = require('../middleware/auth');
const { logAudit } = require('../utils/audit');

const router = express.Router();
router.use(requireFinance);

function parseNumber(val) {
  if (val == null) return 0;
  if (typeof val === 'number') return val;
  const n = Number(val);
  return Number.isFinite(n) ? n : 0;
}

function toYmd(d) {
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd}`;
}

// GET /api/finance/overview?days=7|30|90
router.get('/overview', async (req, res) => {
  try {
    const admin = getAdmin();
    const db = admin.firestore();

    const daysRaw = parseInt(req.query.days || '30', 10) || 30;
    const days = [7, 30, 90].includes(daysRaw) ? daysRaw : 30;

    const now = new Date();
    const start = new Date(now);
    start.setDate(start.getDate() - (days - 1));
    start.setHours(0, 0, 0, 0);

    // Recent donations + totals
    const donationsSnap = await db
      .collection('donations')
      .where('created_at', '>=', start)
      .orderBy('created_at', 'asc')
      .get();

    const totalsByDay = new Map();
    let totalAmount = 0;
    for (const doc of donationsSnap.docs) {
      const d = doc.data() || {};
      const createdAt = d.created_at && typeof d.created_at.toDate === 'function'
        ? d.created_at.toDate()
        : (d.created_at instanceof Date ? d.created_at : new Date(d.created_at || Date.now()));

      const key = toYmd(createdAt);
      const amt = parseNumber(d.amount);
      totalAmount += amt;
      totalsByDay.set(key, (totalsByDay.get(key) || 0) + amt);
    }

    // Sparkline points (ensure every day exists)
    const sparkline = [];
    for (let i = 0; i < days; i++) {
      const dt = new Date(start);
      dt.setDate(start.getDate() + i);
      const key = toYmd(dt);
      sparkline.push({
        date: key,
        amount: totalsByDay.get(key) || 0,
      });
    }

    // Outstanding pledges (optional collection)
    let outstandingPledges = 0;
    try {
      const pledgesSnap = await db
        .collection('pledges')
        .where('status', '==', 'outstanding')
        .limit(500)
        .get();
      outstandingPledges = pledgesSnap.size;
    } catch (_) {
      // If pledges collection doesn't exist yet, treat as 0
      outstandingPledges = 0;
    }

    // Quick reconcile alerts = unreconciled donations in last 30 days
    const unreconciledSnap = await db
      .collection('donations')
      .where('created_at', '>=', start)
      .where('reconciled', '==', false)
      .limit(50)
      .get();

    const monthlyTotals = {
      month: `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`,
      total_amount: totalAmount,
      donations_count: donationsSnap.size,
    };

    return res.json({
      days,
      recent_donations_count: donationsSnap.size,
      outstanding_pledges: outstandingPledges,
      quick_reconcile_alerts: unreconciledSnap.size,
      sparkline,
      monthly_totals: monthlyTotals,
    });
  } catch (error) {
    console.error('Finance overview error:', error);
    return res.status(500).json({ error: 'finance_overview_failed' });
  }
});

// POST /api/finance/bank_import
// Body: { rows: [{date, amount, description, reference}] }
router.post('/bank_import', async (req, res) => {
  try {
    const uid = req.user && req.user.uid ? req.user.uid.toString() : null;
    if (!uid) return res.status(401).json({ error: 'Unauthorized' });

    const rows = Array.isArray(req.body?.rows) ? req.body.rows : null;
    if (!rows || rows.length === 0) {
      return res.status(400).json({ error: 'Missing rows' });
    }

    const admin = getAdmin();
    const db = admin.firestore();

    const importRef = db.collection('bank_imports').doc();
    const cleanRows = rows.slice(0, 2000).map((r) => ({
      date: r?.date || null,
      amount: parseNumber(r?.amount),
      description: r?.description || null,
      reference: r?.reference || null,
    }));

    await importRef.set({
      created_at: new Date(),
      created_by: uid,
      row_count: cleanRows.length,
      rows: cleanRows,
    });

    await logAudit(req, {
      action: 'Bank Import Created',
      resourceType: 'bank_import',
      resourceId: importRef.id,
      newValues: { row_count: cleanRows.length },
    });

    return res.json({ ok: true, import_id: importRef.id, row_count: cleanRows.length });
  } catch (error) {
    console.error('Bank import error:', error);
    return res.status(500).json({ error: 'bank_import_failed' });
  }
});

// POST /api/finance/reconcile
// Body: { matches: [{ donation_id, bank_row }] }
router.post('/reconcile', async (req, res) => {
  try {
    const uid = req.user && req.user.uid ? req.user.uid.toString() : null;
    if (!uid) return res.status(401).json({ error: 'Unauthorized' });

    const matches = Array.isArray(req.body?.matches) ? req.body.matches : null;
    if (!matches || matches.length === 0) {
      return res.status(400).json({ error: 'Missing matches' });
    }

    const admin = getAdmin();
    const db = admin.firestore();

    const batch = db.batch();
    const applied = [];

    for (const m of matches.slice(0, 500)) {
      const donationId = (m?.donation_id || '').toString();
      if (!donationId) continue;

      const ref = db.collection('donations').doc(donationId);
      batch.set(ref, {
        reconciled: true,
        reconciled_at: new Date(),
        reconciled_by: uid,
        reconcile_match: m?.bank_row || null,
        updated_at: new Date(),
      }, { merge: true });
      applied.push(donationId);
    }

    await batch.commit();

    await logAudit(req, {
      action: 'Finance Reconcile',
      resourceType: 'donation',
      resourceId: null,
      newValues: { reconciled_count: applied.length },
    });

    return res.json({ ok: true, reconciled_count: applied.length, reconciled_ids: applied });
  } catch (error) {
    console.error('Finance reconcile error:', error);
    return res.status(500).json({ error: 'finance_reconcile_failed' });
  }
});

module.exports = router;
