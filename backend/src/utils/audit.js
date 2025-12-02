const { v4: uuidv4 } = require('uuid');
const cassandraClient = require('../database/cassandra');

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
  const effectiveUserId = (userId || (req.user && req.user.userId) || '').toString();
  if (!effectiveUserId) {
    // Still log the action but with a placeholder user
    // to avoid dropping important events.
  }

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
    await cassandraClient.execute(
      'INSERT INTO audit_logs (id, user_id, action, resource_type, resource_id, old_values, new_values, timestamp, ip_address, user_agent) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        effectiveUserId || 'system',
        action,
        resourceType,
        resourceId ? resourceId.toString() : null,
        oldValStr,
        newValStr,
        now,
        ipAddress,
        userAgent,
      ]
    );
  } catch (err) {
    console.error('Failed to write audit log:', action, resourceType, resourceId, err);
  }
}

module.exports = {
  logAudit,
};
