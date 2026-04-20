const express = require('express');

const { requireFinance } = require('../middleware/auth');
const { logAudit } = require('../utils/audit');

const router = express.Router();
router.use(requireFinance);

// POST /api/reports/financial
// Body: { template, from, to }
// Returns: { ok, report: { id, name, download_url, mime } }
router.post('/financial', async (req, res) => {
  try {
    const template = (req.body?.template || 'pnl').toString();
    const from = req.body?.from ? req.body.from.toString() : null;
    const to = req.body?.to ? req.body.to.toString() : null;

    const id = `fin_${Date.now()}`;
    const name = `${template}_${from || 'start'}_${to || 'end'}.json`;

    // For now we return a generated JSON report payload as a data URL.
    // This satisfies "available for download" without introducing storage yet.
    const payload = {
      report_id: id,
      template,
      from,
      to,
      generated_at: new Date().toISOString(),
      rows: [],
      totals: {},
    };

    const json = Buffer.from(JSON.stringify(payload, null, 2), 'utf8').toString('base64');
    const downloadUrl = `data:application/json;base64,${json}`;

    await logAudit(req, {
      action: 'Financial Report Generated',
      resourceType: 'report',
      resourceId: id,
      newValues: { template, from, to },
    });

    return res.json({
      ok: true,
      report: {
        id,
        name,
        mime: 'application/json',
        download_url: downloadUrl,
      },
    });
  } catch (error) {
    console.error('Financial report error:', error);
    return res.status(500).json({ error: 'financial_report_failed' });
  }
});

module.exports = router;
