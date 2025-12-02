const express = require('express');
const { v4: uuidv4 } = require('uuid');
const cassandraClient = require('../database/cassandra');
const { logAudit } = require('../utils/audit');

const router = express.Router();

// Default parish ID (fallback if none provided by client)
const DEFAULT_PARISH = process.env.PARISH_ID_DEFAULT || 'default_parish';

// Primary certificate_requests table now lives in the `parish_records` keyspace
// alongside the other parish_* tables.
const TABLE = 'parish_records.certificate_requests';

// Parish_records per-type request tables (see schema.cql)
const PARISH_RECORDS_REQUEST_TABLES = {
  baptism: 'parish_records.baptism_request',
  marriage: 'parish_records.marriage_request',
  confirmation: 'parish_records.confirmation_request',
  death: 'parish_records.death_request',
};

async function ensureMainTable() {
  await cassandraClient.execute(
    `CREATE TABLE IF NOT EXISTS ${TABLE} (parish_id TEXT, request_id TEXT, record_id TEXT, request_type TEXT, requester_name TEXT, status TEXT, requested_at TIMESTAMP, processed_at TIMESTAMP, processed_by TEXT, notification_sent BOOLEAN, PRIMARY KEY (parish_id, request_id))`
  );
}

async function listRequestsByType(req, res, requestType) {
  try {
    await ensureMainTable();
    const parishId = (req.query.parish_id || DEFAULT_PARISH).toString();
    const limit = Math.min(parseInt(req.query.limit || '50', 10), 200);

    const result = await cassandraClient.execute(
      `SELECT parish_id, request_id, record_id, request_type, requester_name, status, requested_at, processed_at, processed_by, notification_sent FROM ${TABLE} WHERE parish_id = ? LIMIT ?`,
      [parishId, limit]
    );

    const rows = result.rows.map((r) => ({
      parish_id: r.parish_id,
      request_id: r.request_id?.toString?.() || null,
      record_id: r.record_id?.toString?.() || null,
      request_type: r.request_type,
      requester_name: r.requester_name,
      status: r.status,
      requested_at: r.requested_at,
      processed_at: r.processed_at,
      processed_by: r.processed_by,
      notification_sent: r.notification_sent,
    }));

    const filtered = rows.filter(
      (r) => (r.request_type || '').toLowerCase() === requestType
    );

    res.json({ rows: filtered });
  } catch (error) {
    console.error('Get certificate requests by type error:', error);
    res.status(500).json({ error: 'requests_list_by_type_failed' });
  }
}

// GET /api/requests
// Lists certificate requests for a parish, similar to the legacy Cloud
// Functions implementation.
router.get('/', async (req, res) => {
  try {
    await ensureMainTable();
    const parishId = (req.query.parish_id || DEFAULT_PARISH).toString();
    const limit = Math.min(parseInt(req.query.limit || '50', 10), 200);

    const result = await cassandraClient.execute(
      `SELECT parish_id, request_id, record_id, request_type, requester_name, status, requested_at, processed_at, processed_by, notification_sent FROM ${TABLE} WHERE parish_id = ? LIMIT ?`,
      [parishId, limit]
    );

    const rows = result.rows.map((r) => ({
      parish_id: r.parish_id,
      request_id: r.request_id?.toString?.() || null,
      record_id: r.record_id?.toString?.() || null,
      request_type: r.request_type,
      requester_name: r.requester_name,
      status: r.status,
      requested_at: r.requested_at,
      processed_at: r.processed_at,
      processed_by: r.processed_by,
      notification_sent: r.notification_sent,
    }));

    res.json({ rows });
  } catch (error) {
    console.error('Get certificate requests error:', error);
    res.status(500).json({ error: 'requests_list_failed' });
  }
});

router.get('/baptism', (req, res) => listRequestsByType(req, res, 'baptism'));

router.get('/marriage', (req, res) => listRequestsByType(req, res, 'marriage'));

router.get('/confirmation', (req, res) =>
  listRequestsByType(req, res, 'confirmation')
);

router.get('/death', (req, res) => listRequestsByType(req, res, 'death'));

// POST /api/requests
// Creates a new certificate request entry. This is called from the
// CertificateRequestFormScreen via RequestsRepository.create().
router.post('/', async (req, res) => {
  try {
    await ensureMainTable();
    const body = req.body || {};
    const parishId = (body.parish_id || DEFAULT_PARISH).toString();
    const requestType = (body.request_type || 'baptism').toString();
    const requesterName = (body.requester_name || '').toString();
    const recordId = body.record_id ? body.record_id.toString() : null;

    const requestId = uuidv4();
    const now = new Date();

    await cassandraClient.execute(
      `INSERT INTO ${TABLE} (parish_id, request_id, record_id, request_type, requester_name, status, requested_at, processed_at, processed_by, notification_sent) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        parishId,
        requestId,
        recordId,
        requestType,
        requesterName,
        'pending',
        now,
        null,
        null,
        false,
      ]
    );

    const requestTypeKey = requestType.toLowerCase();

    // Mirror into parish_records.<type>_request tables for analytics/records linkage
    const parishRecordsTable = PARISH_RECORDS_REQUEST_TABLES[requestTypeKey];
    if (parishRecordsTable) {
      await cassandraClient.execute(
        `INSERT INTO ${parishRecordsTable} (parish_id, id, record_id, requester_name, status, requested_at, processed_at, processed_by, notification_sent) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          parishId,
          requestId,
          recordId,
          requesterName,
          'pending',
          now,
          null,
          null,
          false,
        ]
      );
    }

    // Audit: Certificate Request Created
    await logAudit(req, {
      action: 'Certificate Request Created',
      resourceType: 'certificate_request',
      resourceId: requestId,
      newValues: { requestType, requesterName, recordId },
    });

    res.json({ ok: true, request_id: requestId });
  } catch (error) {
    console.error('Create certificate request error:', error);
    res.status(500).json({ error: 'requests_create_failed' });
  }
});

// PUT /api/requests/:id
// Updates status / notification flags for a certificate request.
router.put('/:id', async (req, res) => {
  try {
    await ensureMainTable();
    const requestId = req.params.id;
    const body = req.body || {};
    const parishId = (body.parish_id || DEFAULT_PARISH).toString();
    const status = body.status ? body.status.toString() : null;
    const notificationSent =
      typeof body.notification_sent === 'boolean'
        ? body.notification_sent
        : null;

    const fields = [];
    const params = [];

    if (status) {
      fields.push('status = ?');
      params.push(status);
    }

    // Auto-set processed_at when status moves out of pending
    if (status && status !== 'pending') {
      fields.push('processed_at = ?');
      params.push(new Date());
    }

    if (notificationSent !== null) {
      fields.push('notification_sent = ?');
      params.push(notificationSent);
    }

    if (fields.length === 0) {
      return res.status(400).json({ error: 'No fields to update' });
    }

    // WHERE primary key
    params.push(parishId, requestId);

    const query = `UPDATE ${TABLE} SET ${fields.join(', ')} WHERE parish_id = ? AND request_id = ?`;
    await cassandraClient.execute(query, params);

    // Determine audit action based on status
    let action = 'Certificate Request Updated';
    if (status === 'approved') {
      action = 'Certificate Request Approved';
    } else if (status === 'rejected') {
      action = 'Certificate Request Rejected';
    } else if (status === 'released') {
      action = 'Certificate Request Marked as Released';
    } else if (status === 'printed') {
      action = 'Certificate Request Printed';
    }

    await logAudit(req, {
      action,
      resourceType: 'certificate_request',
      resourceId: requestId,
      newValues: { status, notificationSent },
    });

    res.json({ ok: true });
  } catch (error) {
    console.error('Update certificate request error:', error);
    res.status(500).json({ error: 'requests_update_failed' });
  }
});

module.exports = router;
