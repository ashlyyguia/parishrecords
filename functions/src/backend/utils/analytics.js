const { getAdmin } = require('../firebase_admin');

// Helper to truncate a JS Date to a UTC date-only value.
function toDateOnlyUtc(d) {
  const dt = d instanceof Date ? new Date(d.getTime()) : new Date();
  dt.setUTCHours(0, 0, 0, 0);
  return dt;
}

function safeDocId(s) {
  return (s || '')
    .toString()
    .replace(/[^a-zA-Z0-9_-]/g, '_')
    .slice(0, 250);
}

/**
 * Record a simple numeric metric into the analytics table.
 *
 * - date: truncated to UTC day
 * - metric_type: e.g. 'records', 'requests', 'attachments'
 * - metric_name: e.g. 'baptism_created', 'certificate_request_baptism'
 * - delta: how much to add (default 1)
 * - metadata: optional JSON-serialisable object
 */
async function recordMetric(metricType, metricName, delta = 1, metadata = null) {
  const date = toDateOnlyUtc(new Date());
  const metricTypeStr = (metricType || 'general').toString();
  const metricNameStr = (metricName || 'unknown').toString();

  try {
    const admin = getAdmin();
    const db = admin.firestore();

    const dateKey = date.toISOString().substring(0, 10);
    const docId = safeDocId(`${dateKey}_${metricTypeStr}_${metricNameStr}`);

    const payload = {
      date: dateKey,
      metric_type: metricTypeStr,
      metric_name: metricNameStr,
      value: admin.firestore.FieldValue.increment(delta),
      updated_at: new Date(),
    };

    if (metadata !== null && metadata !== undefined) {
      payload.metadata = metadata;
    }

    await db.collection('analytics').doc(docId).set(payload, { merge: true });
  } catch (err) {
    console.error('Analytics recordMetric failed', metricType, metricName, err);
  }
}

module.exports = {
  recordMetric,
};
