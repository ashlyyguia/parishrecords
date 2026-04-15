const express = require('express');
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
    const days = Math.min(parseInt(req.query.days, 10) || 30, 365);
    const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);

    const query = `
      SELECT id, user_id, action, resource_type, resource_id, old_values, new_values, timestamp, ip_address, user_agent
      FROM audit_logs
      WHERE timestamp >= ?
      ALLOW FILTERING
      LIMIT ?
    `;

    const result = await cassandraClient.execute(query, [since, limit]);

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

module.exports = router;

