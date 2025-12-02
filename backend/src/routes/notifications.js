const express = require('express');
const { v4: uuidv4 } = require('uuid');
const cassandraClient = require('../database/cassandra');

const router = express.Router();

let notificationsTableEnsured = false;

async function ensureNotificationsTable() {
  if (notificationsTableEnsured) return;

  await cassandraClient.execute(
    'CREATE TABLE IF NOT EXISTS notifications (id TEXT PRIMARY KEY, user_id TEXT, title TEXT, message TEXT, type TEXT, read BOOLEAN, created_at TIMESTAMP, expires_at TIMESTAMP)'
  );

  notificationsTableEnsured = true;
}

// List notifications (optionally limited)
router.get('/', async (req, res) => {
  try {
    await ensureNotificationsTable();
    const limit = Math.min(parseInt(req.query.limit, 10) || 100, 300);

    const result = await cassandraClient.execute(
      'SELECT id, user_id, title, message, type, read, created_at FROM notifications LIMIT ?',
      [limit]
    );

    const rows = (result.rows || [])
      .map((r) => {
        const createdAt = r.created_at || null;
        const archived = (r.type || '').toString() === 'archived';
        return {
          id: r.id ? r.id.toString() : undefined,
          user_id: r.user_id ? r.user_id.toString() : null,
          title: r.title || '',
          body: r.message || '',
          type: r.type || 'normal',
          read: r.read === true,
          archived,
          createdAt: createdAt instanceof Date ? createdAt.toISOString() : createdAt,
        };
      })
      .sort((a, b) => {
        const aTime = a.createdAt ? new Date(a.createdAt).getTime() : 0;
        const bTime = b.createdAt ? new Date(b.createdAt).getTime() : 0;
        return bTime - aTime;
      });

    res.json({ rows, count: rows.length });
  } catch (error) {
    console.error('Get notifications error:', error);
    res.status(500).json({ error: 'Failed to fetch notifications' });
  }
});

// Create notification
router.post('/', async (req, res) => {
  try {
    await ensureNotificationsTable();
    const { title, body } = req.body || {};

    if (!title || !body) {
      return res.status(400).json({ error: 'Missing title or body' });
    }

    const id = uuidv4();
    const now = new Date();

    await cassandraClient.execute(
      'INSERT INTO notifications (id, user_id, title, message, type, read, created_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [id, null, title.toString(), body.toString(), 'normal', false, now, null]
    );

    res.status(201).json({
      id,
      title,
      body,
      type: 'normal',
      read: false,
      created_at: now,
    });
  } catch (error) {
    console.error('Create notification error:', error);
    res.status(500).json({ error: 'Failed to create notification' });
  }
});

// Mark notification read/unread
router.patch('/:id/read', async (req, res) => {
  try {
    await ensureNotificationsTable();
    const { id } = req.params;
    const { read } = req.body || {};

    if (typeof read !== 'boolean') {
      return res.status(400).json({ error: 'Invalid read value' });
    }

    await cassandraClient.execute(
      'UPDATE notifications SET read = ? WHERE id = ?',
      [read, id]
    );

    res.json({ message: 'Notification read state updated' });
  } catch (error) {
    console.error('Update notification read error:', error);
    res.status(500).json({ error: 'Failed to update notification read state' });
  }
});

// Archive / unarchive notification (uses type column)
router.patch('/:id/archive', async (req, res) => {
  try {
    await ensureNotificationsTable();
    const { id } = req.params;
    const { archived } = req.body || {};

    if (typeof archived !== 'boolean') {
      return res.status(400).json({ error: 'Invalid archived value' });
    }

    const newType = archived ? 'archived' : 'normal';

    await cassandraClient.execute(
      'UPDATE notifications SET type = ? WHERE id = ?',
      [newType, id]
    );

    res.json({ message: 'Notification archive state updated' });
  } catch (error) {
    console.error('Update notification archive error:', error);
    res.status(500).json({ error: 'Failed to update notification archive state' });
  }
});

// Delete notification
router.delete('/:id', async (req, res) => {
  try {
    await ensureNotificationsTable();
    const { id } = req.params;

    await cassandraClient.execute(
      'DELETE FROM notifications WHERE id = ?',
      [id]
    );

    res.json({ message: 'Notification deleted successfully' });
  } catch (error) {
    console.error('Delete notification error:', error);
    res.status(500).json({ error: 'Failed to delete notification' });
  }
});

module.exports = router;
