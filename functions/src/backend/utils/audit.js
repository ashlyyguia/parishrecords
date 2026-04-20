const { v4: uuidv4 } = require('uuid');
const { getAdmin } = require('../firebase_admin');

/**
 * Write an entry into the audit_logs table.
 *
 * @param {object} req - Express request (used for IP and user-agent when available).
 * @param {object} opts
 * @param {string} [opts.userId] - Acting user ID (falls back to req.user.userId if missing).
 * @param {string} opts.action - Descriptive action name (e.g., "Baptism Record Updated").
 * @param {string} [opts.resourceType] - High-level resource type (e.g., "user", "certificate_request", "baptism_record").
 * @param {string} [opts.resourceId] - ID of the resource operated on.
 * @param {object|string|null} [opts.oldValues] - Optional JSON of previous state.
 * @param {object|string|null} [opts.newValues] - Optional JSON of new state.
 */
async function logAudit(req, {
  userId,
  action,
  resourceType = null,
  resourceId = null,
  oldValues = null,
  newValues = null,
}) {
  if (!action) return;

  const id = uuidv4();
  const effectiveUserId = (userId || (req.user && req.user.uid) || '').toString();

  const now = new Date();
  const ipAddress = req.ip || null;
  const userAgent = req.get && req.get('user-agent') ? req.get('user-agent') : null;

  const oldValStr =
    oldValues && typeof oldValues === 'object'
      ? JSON.stringify(oldValues)
      : (oldValues || null);
  const newValStr =
    newValues && typeof newValues === 'object'
      ? JSON.stringify(newValues)
      : (newValues || null);

  try {
    const admin = getAdmin();
    const db = admin.firestore();

    await db.collection('audit_logs').doc(id).set({
      user_id: effectiveUserId || 'system',
      action,
      resource_type: resourceType,
      resource_id: resourceId ? resourceId.toString() : null,
      old_values: oldValStr,
      new_values: newValStr,
      timestamp: now,
      ip_address: ipAddress,
      user_agent: userAgent,
    });
  } catch (err) {
    console.error('Failed to write audit log:', action, resourceType, resourceId, err);
  }
}

module.exports = {
  logAudit,
};
