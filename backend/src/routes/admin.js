const express = require('express');
const { v4: uuidv4 } = require('uuid');
const cassandraClient = require('../database/cassandra');

const router = express.Router();

const DEFAULT_SETTINGS = {
  language: 'en',
  timezone: 'UTC',
  notify: true,
  auto_backup: false,
};

async function loadSettingsFromDb() {
  const result = await cassandraClient.execute(
    'SELECT key, value FROM settings'
  );

  const settings = { ...DEFAULT_SETTINGS };

  result.rows.forEach((row) => {
    const key = row.key;
    const value = row.value;
    if (!key) {
      return;
    }
    switch (key) {
      case 'language':
        settings.language = value || DEFAULT_SETTINGS.language;
        break;
      case 'timezone':
        settings.timezone = value || DEFAULT_SETTINGS.timezone;
        break;
      case 'notify':
        settings.notify =
          value === true ||
          value === 'true' ||
          value === 1 ||
          value === '1';
        break;
      case 'auto_backup':
        settings.auto_backup =
          value === true ||
          value === 'true' ||
          value === 1 ||
          value === '1';
        break;
      default:
        break;
    }
  });

  return settings;
}

router.get('/settings', async (req, res) => {
  try {
    const settings = await loadSettingsFromDb();
    res.json(settings);
  } catch (error) {
    console.error('Admin settings fetch error:', error);
    res.status(500).json({ error: 'Failed to fetch settings' });
  }
});

router.put('/settings', async (req, res) => {
  try {
    const {
      language = DEFAULT_SETTINGS.language,
      timezone = DEFAULT_SETTINGS.timezone,
      notify = DEFAULT_SETTINGS.notify,
      auto_backup = DEFAULT_SETTINGS.auto_backup,
    } = req.body || {};

    const timestamp = new Date();
    const updates = [
      { key: 'language', value: language },
      { key: 'timezone', value: timezone },
      { key: 'notify', value: notify ? 'true' : 'false' },
      { key: 'auto_backup', value: auto_backup ? 'true' : 'false' },
    ];

    await Promise.all(
      updates.map(({ key, value }) =>
        cassandraClient.execute(
          'INSERT INTO settings (key, value, updated_at) VALUES (?, ?, ?)',
          [key, value, timestamp]
        )
      )
    );

    res.json({
      message: 'Settings updated successfully',
      settings: {
        language,
        timezone,
        notify: !!notify,
        auto_backup: !!auto_backup,
      },
    });
  } catch (error) {
    console.error('Admin settings update error:', error);
    res.status(500).json({ error: 'Failed to save settings' });
  }
});

router.get('/logs', async (req, res) => {
  try {
    const limit = Math.min(parseInt(req.query.limit, 10) || 100, 500);
    const resourceIdFilter = req.query.resource_id
      ? req.query.resource_id.toString()
      : null;

    let result;
    if (resourceIdFilter) {
      const query = `
        SELECT id, user_id, action, resource_type, resource_id, old_values, new_values, timestamp, ip_address, user_agent
        FROM audit_logs
        WHERE resource_id = ?
        LIMIT ?
      `;
      result = await cassandraClient.execute(query, [resourceIdFilter, limit]);
    } else {
      const query = `
        SELECT id, user_id, action, resource_type, resource_id, old_values, new_values, timestamp, ip_address, user_agent
        FROM audit_logs
        LIMIT ?
      `;
      result = await cassandraClient.execute(query, [limit]);
    }

    const rows = result.rows.map((row) => {
      const detailsParts = [];
      if (row.resource_type) {
        detailsParts.push(`${row.resource_type}`);
      }
      if (row.resource_id) {
        detailsParts.push(`#${row.resource_id}`);
      }
      if (row.action) {
        detailsParts.push(`→ ${row.action}`);
      }
      const changeSummary =
        row.new_values && row.old_values
          ? ` ${row.old_values} → ${row.new_values}`
          : row.new_values || row.old_values || '';

      return {
        id: row.id ? row.id.toString() : null,
        user_id: row.user_id ? row.user_id.toString() : null,
        action: row.action,
        details: `${detailsParts.join(' ')}${changeSummary}`.trim(),
        action_time: row.timestamp,
        resource_type: row.resource_type,
        resource_id: row.resource_id ? row.resource_id.toString() : null,
        old_values: row.old_values,
        new_values: row.new_values,
        ip_address: row.ip_address,
        user_agent: row.user_agent,
      };
    });

    res.json({
      rows,
      count: rows.length,
    });
  } catch (error) {
    console.error('Admin logs fetch error:', error);
    res.status(500).json({ error: 'Failed to fetch audit logs' });
  }
});

router.post('/logs', async (req, res) => {
  try {
    const body = req.body || {};

    const id = body.id || uuidv4();
    const userId = (body.user_id || body.userId || '').toString();
    const action = (body.action || '').toString();
    const resourceType =
      body.resource_type || body.resourceType || null;
    const resourceId =
      body.resource_id || body.resourceId || null;
    const oldValues =
      body.old_values || body.oldValues || null;
    const newValues =
      body.new_values || body.newValues || null;

    const tsRaw = body.timestamp || body.action_time;
    const timestamp = tsRaw ? new Date(tsRaw) : new Date();
    const ipAddress = req.ip;
    const userAgent = req.get('user-agent') || null;

    if (!userId || !action) {
      return res.status(400).json({ error: 'Missing user_id or action' });
    }

    await cassandraClient.execute(
      'INSERT INTO audit_logs (id, user_id, action, resource_type, resource_id, old_values, new_values, timestamp, ip_address, user_agent) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        userId,
        action,
        resourceType,
        resourceId,
        oldValues,
        newValues,
        timestamp,
        ipAddress,
        userAgent,
      ]
    );

    res.json({ ok: true, id });
  } catch (error) {
    console.error('Admin log create error:', error);
    res.status(500).json({ error: 'Failed to create audit log' });
  }
});

router.delete('/logs/:id', async (req, res) => {
  try {
    const { id } = req.params;
    if (!id) {
      return res.status(400).json({ error: 'Missing log id' });
    }

    await cassandraClient.execute(
      'DELETE FROM audit_logs WHERE id = ?',
      [id]
    );

    res.json({ message: 'Log deleted successfully' });
  } catch (error) {
    console.error('Admin log delete error:', error);
    res.status(500).json({ error: 'Failed to delete log' });
  }
});

// Recent records for admin (backed by records_by_type)
router.get('/records/recent', async (req, res) => {
  try {
    const limit = Math.min(parseInt(req.query.limit, 10) || 100, 1000);
    const days = Math.min(parseInt(req.query.days, 10) || 7, 3650);
    const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);

    const result = await cassandraClient.execute(
      'SELECT type, parish_id, id, name, date, place, certificate_status, created_at FROM records_by_type',
      [],
    );

    const allRows = result.rows.map((r) => ({
      id: r.id ? r.id.toString() : null,
      type: r.type,
      text: r.name,
      image_ref: null,
      source: r.parish_id || null,
      notes: null,
      certificate_status: r.certificate_status || null,
      created_at: r.created_at || r.date || new Date(),
    }));

    const filtered = allRows
      .filter((r) => r.created_at && r.created_at >= since)
      .sort((a, b) => b.created_at - a.created_at)
      .slice(0, limit);

    res.json({
      rows: filtered,
      count: filtered.length,
    });
  } catch (error) {
    console.error('Admin recent records error:', error);
    res.status(500).json({ error: 'Failed to fetch recent records' });
  }
});

router.put('/records/:id', async (req, res) => {
  try {
    const { id } = req.params;
    if (!id) {
      return res.status(400).json({ error: 'Missing record id' });
    }

    const metaResult = await cassandraClient.execute(
      'SELECT type, parish_id, name, created_at FROM records_by_type WHERE id = ? ALLOW FILTERING',
      [id],
    );
    if (metaResult.rows.length === 0) {
      return res.status(404).json({ error: 'Record not found' });
    }

    const meta = metaResult.rows[0];
    const recordType = (meta.type || 'baptism').toString();
    const createdAt = meta.created_at;
    const currentParish = (meta.parish_id || '').toString();
    const currentName = meta.name || 'Unnamed Record';

    const nextName = (req.body.text || req.body.name || currentName).toString();
    const nextParish = (req.body.source || currentParish || 'default_parish').toString();

    await cassandraClient.execute(
      'UPDATE records_by_type SET name = ?, parish_id = ? WHERE type = ? AND created_at = ? AND id = ?',
      [nextName, nextParish, recordType, createdAt, id],
    );

    res.json({
      message: 'Record updated successfully',
      id,
      name: nextName,
      parish_id: nextParish,
    });
  } catch (error) {
    console.error('Admin record update error:', error);
    res.status(500).json({ error: 'Failed to update record' });
  }
});

// Simple summary for admin dashboard (backed by records_by_type)
router.get('/summary', async (req, res) => {
  try {
    const days = Math.min(parseInt(req.query.days, 10) || 7, 365);
    const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);

    const result = await cassandraClient.execute(
      'SELECT type, certificate_status, created_at FROM records_by_type',
      [],
    );

    const rows = result.rows.filter(
      (r) => r.created_at && r.created_at >= since,
    );
    const totalRecordsLastDays = rows.length;

    const recordsByType = {};
    const certificatesByStatus = {};

    rows.forEach((r) => {
      const type = (r.type || 'unknown').toString();
      recordsByType[type] = (recordsByType[type] || 0) + 1;

      const status = (r.certificate_status || 'unknown').toString();
      certificatesByStatus[status] = (certificatesByStatus[status] || 0) + 1;
    });

    // User counts
    const usersTotalResult = await cassandraClient.execute(
      'SELECT COUNT(*) AS count FROM users'
    );
    const totalUsers = usersTotalResult.rows[0].count.toNumber();

    const usersByRole = {};
    const usersByRoleResult = await cassandraClient.execute(
      'SELECT role, COUNT(*) AS count FROM users GROUP BY role'
    );
    usersByRoleResult.rows.forEach((row) => {
      const role = (row.role || 'unknown').toString();
      usersByRole[role] = row.count.toNumber();
    });

    res.json({
      total_records_last_days: totalRecordsLastDays,
      records_by_type: recordsByType,
      certificates_by_status: certificatesByStatus,
      total_users: totalUsers,
      users_by_role: usersByRole,
      generated_at: new Date().toISOString(),
    });
  } catch (error) {
    console.error('Admin summary error:', error);
    res.status(500).json({ error: 'Failed to generate summary' });
  }
});

// Daily records metrics for charts (backed by records_by_type)
router.get('/metrics/records/daily', async (req, res) => {
  try {
    const days = Math.min(parseInt(req.query.days, 10) || 14, 365);
    const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);

    // Aggregate counts per date from records_by_type
    const result = await cassandraClient.execute(
      'SELECT date FROM records_by_type WHERE date >= ? ALLOW FILTERING',
      [since],
    );

    const countsByDate = {};
    result.rows.forEach((row) => {
      const d = row.date;
      if (!d) return;
      const key = d.toISOString().substring(0, 10);
      countsByDate[key] = (countsByDate[key] || 0) + 1;
    });

    // Ensure we return all days in the window, even with zero
    const daysArr = [];
    for (let i = days - 1; i >= 0; i--) {
      const d = new Date(Date.now() - i * 24 * 60 * 60 * 1000);
      const key = d.toISOString().substring(0, 10);
      daysArr.push({
        date: key,
        total: countsByDate[key] || 0,
      });
    }

    res.json({ days: daysArr });
  } catch (error) {
    console.error('Admin daily metrics error:', error);
    res.status(500).json({ error: 'Failed to fetch daily metrics' });
  }
});

// Lightweight health check for users table
router.get('/users/health', async (req, res) => {
  try {
    await cassandraClient.execute('SELECT id FROM users LIMIT 1');
    res.json({ ok: true });
  } catch (error) {
    console.error('Admin users health error:', error);
    res.status(500).json({ ok: false, error: 'Failed to query users table' });
  }
});

// Simple users "sync" placeholder – currently just reports total users
router.post('/users/sync', async (req, res) => {
  try {
    const result = await cassandraClient.execute(
      'SELECT COUNT(*) AS count FROM users'
    );
    const total = result.rows[0].count.toNumber();
    res.json({ total });
  } catch (error) {
    console.error('Admin users sync error:', error);
    res.status(500).json({ error: 'Failed to compute users total' });
  }
});

// One-time maintenance: backfill notes JSON in records_by_type for existing records
let recordsByTypeNotesEnsured = false;
async function ensureRecordsByTypeNotesColumn() {
  // In this deployment the notes column already exists; avoid ALTER TABLE at runtime.
  if (recordsByTypeNotesEnsured) return;
  recordsByTypeNotesEnsured = true;
}

async function buildNotesForRecord(summaryRow) {
  const type = (summaryRow.type || '').toString();
  const parishId = (summaryRow.parish_id || 'default_parish').toString();
  const id = summaryRow.id ? summaryRow.id.toString() : null;

  if (!id || !type) return null;

  // Helper to format JS Date to ISO yyyy-MM-dd
  const fmtDate = (d) => {
    if (!d || !(d instanceof Date)) return null;
    try {
      return d.toISOString().substring(0, 10);
    } catch (_) {
      return null;
    }
  };

  if (type === 'baptism') {
    const result = await cassandraClient.execute(
      'SELECT * FROM baptism_records WHERE parish_id = ? AND id = ?',
      [parishId, id],
    );
    if (!result.rows.length) return null;
    const row = result.rows[0];

    const registry = {
      registryNo: row.registry_number || null,
      bookNo: row.book_number || null,
      pageNo: row.page_number || null,
      lineNo: row.line_number || null,
    };

    const child = {
      fullName: row.name || null,
      dateOfBirth: fmtDate(row.date_of_birth),
      placeOfBirth: row.place_of_birth || null,
      gender: row.gender || null,
      address: null,
      legitimacy: null,
    };

    const parents = {
      father: row.father_name || null,
      mother: row.mother_name || null,
      marriageInfo: null,
    };

    const godparents = {
      godfather1: row.godfather_name || null,
      godmother1: row.godmother_name || null,
      godfather2: null,
      godmother2: null,
    };

    const baptism = {
      date: fmtDate(row.date_of_baptism || row.date),
      time: row.time_of_baptism || null,
      place: row.place || null,
      minister: row.minister_name || null,
    };

    const metadata = {
      remarks: null,
      certificateIssued: false,
      staffName: null,
      dateEncoded: summaryRow.created_at || null,
      recordId: id,
    };

    return {
      registry,
      child,
      parents,
      godparents,
      baptism,
      metadata,
      attachments: [],
    };
  }

  if (type === 'marriage') {
    const result = await cassandraClient.execute(
      'SELECT * FROM marriage_records WHERE parish_id = ? AND id = ?',
      [parishId, id],
    );
    if (!result.rows.length) return null;
    const row = result.rows[0];

    const marriage = {
      date: fmtDate(row.date),
      place: row.place || null,
      officiant: row.officiant_name || null,
      licenseNumber: null,
    };

    const groom = {
      fullName: row.groom_name || null,
      ageOrDob: row.groom_age_or_dob || null,
      civilStatus: row.groom_civil_status || null,
      religion: row.groom_religion || null,
      address: row.groom_address || null,
      father: null,
      mother: null,
    };

    const bride = {
      fullName: row.bride_name || null,
      ageOrDob: null,
      civilStatus: null,
      religion: null,
      address: null,
      father: null,
      mother: null,
    };

    const witnesses = {
      witness1: row.witness1_name || null,
      witness2: row.witness2_name || null,
    };

    const meta = {
      recordId: id,
      bookNo: row.book_number || null,
      pageNo: row.page_number || null,
      lineNo: row.line_number || null,
      createdAt: summaryRow.created_at || null,
      dateEncoded: summaryRow.created_at || null,
    };

    return {
      marriage,
      groom,
      bride,
      witnesses,
      remarks: row.remarks || null,
      attachments: [],
      meta,
    };
  }

  if (type === 'confirmation') {
    const result = await cassandraClient.execute(
      'SELECT * FROM confirmation_records WHERE parish_id = ? AND id = ?',
      [parishId, id],
    );
    if (!result.rows.length) return null;
    const row = result.rows[0];

    const confirmand = {
      fullName: row.name || null,
      // age_or_dob may already be an ISO date or a free-form text; preserve as-is
      dateOfBirth: row.age_or_dob || null,
      placeOfBirth: row.place_of_birth || null,
      address: row.address || null,
    };

    const parents = {
      father: row.father_name || null,
      mother: row.mother_name || null,
    };

    const sponsor = {
      fullName: row.sponsor_name || null,
      relationship: null,
    };

    const confirmation = {
      date: fmtDate(row.date),
      place: row.place || null,
      officiant: row.minister_name || null,
    };

    const meta = {
      recordId: id,
      registryNo: row.registry_number || null,
      bookNo: row.book_number || null,
      pageNo: row.page_number || null,
      lineNo: row.line_number || null,
      createdAt: summaryRow.created_at || null,
      dateEncoded: summaryRow.created_at || null,
    };

    return {
      confirmand,
      parents,
      sponsor,
      confirmation,
      remarks: row.remarks || null,
      attachments: [],
      meta,
    };
  }

  if (type === 'death' || type === 'funeral') {
    const result = await cassandraClient.execute(
      'SELECT * FROM death_records WHERE parish_id = ? AND id = ?',
      [parishId, id],
    );
    if (!result.rows.length) return null;
    const row = result.rows[0];

    const deceased = {
      fullName: row.name || null,
      gender: row.gender || null,
      age: row.age_or_dob || null,
      dateOfBirth: fmtDate(row.date_of_birth),
      // In this schema, `date` is used as the main record date (date of death)
      dateOfDeath: fmtDate(row.date),
      placeOfDeath: row.place_of_death || null,
      causeOfDeath: row.cause_of_death || null,
      civilStatus: row.civil_status || null,
      address: row.address || null,
    };

    const family = {
      father: row.father_name || null,
      mother: row.mother_name || null,
      spouse: row.spouse_name || null,
    };

    const representative = {
      name: row.informant_name || null,
      relationship: row.informant_relation || null,
    };

    const burial = {
      date: fmtDate(row.burial_date),
      place: row.burial_place || null,
      officiant: row.minister_name || null,
    };

    const meta = {
      recordId: id,
      registryNo: row.registry_number || null,
      bookNo: row.book_number || null,
      pageNo: row.page_number || null,
      lineNo: row.line_number || null,
      createdAt: summaryRow.created_at || null,
      dateEncoded: summaryRow.created_at || null,
    };

    return {
      deceased,
      family,
      representative,
      burial,
      remarks: null,
      attachments: [],
      meta,
    };
  }

  return null;
}

router.post('/records/backfill-notes', async (req, res) => {
  try {
    await ensureRecordsByTypeNotesColumn();

    // Optional body.limit to cap how many missing rows to process in one call
    const rawLimit = req.body && req.body.limit;
    const limit = Math.min(parseInt(rawLimit, 10) || 500, 5000);

    const result = await cassandraClient.execute(
      'SELECT type, parish_id, id, name, date, place, certificate_status, created_at, notes FROM records_by_type',
      [],
    );

    const missing = result.rows.filter((r) => !r.notes);
    let processed = 0;

    for (const row of missing) {
      if (processed >= limit) break;
      const notesObj = await buildNotesForRecord(row);
      if (!notesObj) continue;

      const notesJson = JSON.stringify(notesObj);

      await cassandraClient.execute(
        'UPDATE records_by_type SET notes = ? WHERE type = ? AND created_at = ? AND id = ?',
        [
          notesJson,
          row.type,
          row.created_at,
          row.id,
        ],
      );

      processed += 1;
    }

    res.json({
      message: 'Backfill completed',
      processed,
      totalMissing: missing.length,
    });
  } catch (error) {
    console.error('Admin backfill notes error:', error);
    res.status(500).json({ error: 'Failed to backfill notes' });
  }
});

module.exports = router;

