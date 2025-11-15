import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import express from 'express';
import { Client, types as CassTypes } from 'cassandra-driver';

const app = express();
app.use(express.json());

let inited = false;
try {
  if (!inited) {
    admin.initializeApp();
    inited = true;
  }
} catch {}

const db = admin.firestore();

const CASS_CONTACT_POINTS = (process.env.CASS_CONTACT_POINTS || '').split(',').filter(Boolean);
const CASS_LOCAL_DC = process.env.CASS_LOCAL_DC || 'datacenter1';
const CASS_KEYSPACE = process.env.CASS_KEYSPACE || 'parish';
const CASS_USERNAME = process.env.CASS_USERNAME;
const CASS_PASSWORD = process.env.CASS_PASSWORD;
const DEFAULT_PARISH = process.env.PARISH_ID_DEFAULT || 'default_parish';

const cassClient = new Client({
  contactPoints: CASS_CONTACT_POINTS.length ? CASS_CONTACT_POINTS : ['127.0.0.1'],
  localDataCenter: CASS_LOCAL_DC,
  keyspace: CASS_KEYSPACE,
  credentials: CASS_USERNAME && CASS_PASSWORD ? { username: CASS_USERNAME, password: CASS_PASSWORD } : undefined as any,
});

async function ensureCassandra() {
  // will throw if not connected
  await cassClient.connect();
}

async function verifyAuth(req: any, res: any, next: any) {
  try {
    const auth = req.headers.authorization || '';
    const token = auth.startsWith('Bearer ') ? auth.substring(7) : null;
    if (!token) return res.status(401).json({ error: 'unauthenticated' });
    const decoded = await admin.auth().verifyIdToken(token);
    (req as any).uid = decoded.uid;
    next();
  } catch (e) {
    return res.status(401).json({ error: 'unauthenticated' });
  }
}

async function requireAdmin(req: any, res: any, next: any) {
  const uid = (req as any).uid;
  try {
    const doc = await db.collection('users').doc(uid).get();
    const role = (doc.data()?.role || 'staff').toString();
    if (role !== 'admin') return res.status(403).json({ error: 'forbidden' });
    next();
  } catch {
    return res.status(403).json({ error: 'forbidden' });
  }
}

function normalizeRow(r: any) {
  return {
    id: r.record_id?.toString?.() || r.id || '',
    text: r.text || r.person_name || r.groom_name || r.bride_name || '',
    source: r.source || r.parish_id || null,
    image_ref: r.image_ref || r.scanned_document_url || null,
    created_at: r.created_at || null,
    type: r.type || r._type || undefined,
  };
}

// Records list
app.get('/api/records', verifyAuth, async (req, res) => {
  try {
    await ensureCassandra();
    const parish = (req.query.parish_id as string) || DEFAULT_PARISH;
    const limit = Math.min(parseInt((req.query.limit as string) || '50', 10), 200);

    const queries = [
      {
        cql: 'SELECT parish_id, record_id, baptism_date, person_name, scanned_document_url, ocr_text, created_by, created_at FROM baptism_records WHERE parish_id = ? LIMIT ?;',
        params: [parish, limit],
        type: 'baptism',
      },
      {
        cql: 'SELECT parish_id, record_id, marriage_date, groom_name, bride_name, witness_names, scanned_document_url, ocr_text, created_by, created_at FROM marriage_records WHERE parish_id = ? LIMIT ?;',
        params: [parish, limit],
        type: 'marriage',
      },
      {
        cql: 'SELECT parish_id, record_id, confirmation_date, person_name, sponsor_names, scanned_document_url, ocr_text, created_by, created_at FROM confirmation_records WHERE parish_id = ? LIMIT ?;',
        params: [parish, limit],
        type: 'confirmation',
      },
    ];

    const results = [] as any[];
    for (const q of queries) {
      const rs = await cassClient.execute(q.cql, q.params, { prepare: true });
      for (const row of rs.rows) {
        results.push(normalizeRow({ ...row, _type: q.type }));
      }
    }

    return res.json({ rows: results });
  } catch (e: any) {
    return res.status(500).json({ error: 'list_failed', detail: e?.message });
  }
});

// Create record
app.post('/api/records', verifyAuth, async (req, res) => {
  try {
    await ensureCassandra();
    const uid = (req as any).uid as string;
    const body = req.body || {};
    const type = (body.type as string) || 'baptism';
    const text = (body.text as string) || '';
    const source = (body.source as string) || DEFAULT_PARISH;
    const image = (body.image_ref as string) || null;
    const now = new Date();
    const id = admin.firestore().collection('_').doc().id;

    if (type === 'baptism') {
      await cassClient.execute(
        'INSERT INTO baptism_records (parish_id, record_id, baptism_date, person_name, birthdate, parents, scanned_document_url, ocr_text, created_by, created_at) VALUES (?, now(), ?, ?, ?, ?, ?, ?, ?, ?);',
        [source, id, now, text, null, null, image, body.ocr_text || null, uid, now],
        { prepare: true }
      );
    } else if (type === 'marriage') {
      await cassClient.execute(
        'INSERT INTO marriage_records (parish_id, record_id, marriage_date, groom_name, bride_name, witness_names, scanned_document_url, ocr_text, created_by, created_at) VALUES (?, now(), ?, ?, ?, ?, ?, ?, ?, ?);',
        [source, id, now, body.groom_name || text, body.bride_name || '', body.witness_names || [], image, body.ocr_text || null, uid, now],
        { prepare: true }
      );
    } else if (type === 'confirmation') {
      await cassClient.execute(
        'INSERT INTO confirmation_records (parish_id, record_id, confirmation_date, person_name, sponsor_names, scanned_document_url, ocr_text, created_by, created_at) VALUES (?, now(), ?, ?, ?, ?, ?, ?, ?);',
        [source, id, now, text, body.sponsor_names || [], image, body.ocr_text || null, uid, now],
        { prepare: true }
      );
    } else {
      return res.status(400).json({ error: 'invalid_type' });
    }

    return res.json({ ok: true, id });
  } catch (e: any) {
    return res.status(500).json({ error: 'create_failed', detail: e?.message });
  }
});

async function locateRecordById(id: string) {
  const tables = [
    { name: 'baptism_records', dateCol: 'baptism_date', type: 'baptism' },
    { name: 'marriage_records', dateCol: 'marriage_date', type: 'marriage' },
    { name: 'confirmation_records', dateCol: 'confirmation_date', type: 'confirmation' },
  ];
  for (const t of tables) {
    const rs = await cassClient.execute(
      `SELECT parish_id, ${t.dateCol} as ev_date, record_id FROM ${t.name} WHERE record_id = ? ALLOW FILTERING LIMIT 1;`,
      [id],
      { prepare: true }
    );
    if (rs.first()) {
      const row = rs.first()!;
      return { table: t.name, parish_id: row['parish_id'], date: row['ev_date'], type: t.type };
    }
  }
  return null;
}

// Update record
app.put('/api/records/:id', verifyAuth, async (req, res) => {
  try {
    await ensureCassandra();
    const id = req.params.id as string;
    const data = req.body || {};
    const found = await locateRecordById(id);
    if (!found) return res.status(404).json({ error: 'not_found' });

    if (found.table === 'baptism_records') {
      await cassClient.execute(
        'UPDATE baptism_records SET person_name = COALESCE(?, person_name), scanned_document_url = COALESCE(?, scanned_document_url), ocr_text = COALESCE(?, ocr_text) WHERE parish_id = ? AND baptism_date = ? AND record_id = ?;',
        [data.text || null, data.image_ref || null, data.ocr_text || null, found.parish_id, found.date, id],
        { prepare: true }
      );
    } else if (found.table === 'marriage_records') {
      await cassClient.execute(
        'UPDATE marriage_records SET groom_name = COALESCE(?, groom_name), bride_name = COALESCE(?, bride_name), scanned_document_url = COALESCE(?, scanned_document_url), ocr_text = COALESCE(?, ocr_text) WHERE parish_id = ? AND marriage_date = ? AND record_id = ?;',
        [data.groom_name || data.text || null, data.bride_name || null, data.image_ref || null, data.ocr_text || null, found.parish_id, found.date, id],
        { prepare: true }
      );
    } else if (found.table === 'confirmation_records') {
      await cassClient.execute(
        'UPDATE confirmation_records SET person_name = COALESCE(?, person_name), scanned_document_url = COALESCE(?, scanned_document_url), ocr_text = COALESCE(?, ocr_text) WHERE parish_id = ? AND confirmation_date = ? AND record_id = ?;',
        [data.text || null, data.image_ref || null, data.ocr_text || null, found.parish_id, found.date, id],
        { prepare: true }
      );
    }

    return res.json({ ok: true });
  } catch (e: any) {
    return res.status(500).json({ error: 'update_failed', detail: e?.message });
  }
});

// Delete record
app.delete('/api/records/:id', verifyAuth, async (req, res) => {
  try {
    await ensureCassandra();
    const id = req.params.id as string;
    const found = await locateRecordById(id);
    if (!found) return res.status(404).json({ error: 'not_found' });

    if (found.table === 'baptism_records') {
      await cassClient.execute(
        'DELETE FROM baptism_records WHERE parish_id = ? AND baptism_date = ? AND record_id = ?;',
        [found.parish_id, found.date, id],
        { prepare: true }
      );
    } else if (found.table === 'marriage_records') {
      await cassClient.execute(
        'DELETE FROM marriage_records WHERE parish_id = ? AND marriage_date = ? AND record_id = ?;',
        [found.parish_id, found.date, id],
        { prepare: true }
      );
    } else if (found.table === 'confirmation_records') {
      await cassClient.execute(
        'DELETE FROM confirmation_records WHERE parish_id = ? AND confirmation_date = ? AND record_id = ?;',
        [found.parish_id, found.date, id],
        { prepare: true }
      );
    }

    return res.json({ ok: true });
  } catch (e: any) {
    return res.status(500).json({ error: 'delete_failed', detail: e?.message });
  }
});

// Admin recent
app.get('/api/admin/records/recent', verifyAuth, requireAdmin, async (req, res) => {
  try {
    await ensureCassandra();
    const parish = (req.query.parish_id as string) || DEFAULT_PARISH;
    const limit = Math.min(parseInt((req.query.limit as string) || '50', 10), 200);
    const days = Math.min(parseInt((req.query.days as string) || '7', 10), 365);
    const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);

    const results: any[] = [];
    const q1 = await cassClient.execute('SELECT parish_id, record_id, baptism_date as ev_date, person_name as text, scanned_document_url as image_ref, created_at FROM baptism_records WHERE parish_id = ? LIMIT ?;', [parish, limit], { prepare: true });
    q1.rows.forEach(r => results.push({ ...normalizeRow(r), created_at: r['created_at'], type: 'baptism' }));
    const q2 = await cassClient.execute('SELECT parish_id, record_id, marriage_date as ev_date, groom_name, bride_name, scanned_document_url as image_ref, created_at FROM marriage_records WHERE parish_id = ? LIMIT ?;', [parish, limit], { prepare: true });
    q2.rows.forEach(r => results.push({ id: r['record_id'].toString(), text: (r['groom_name']||'') + ' & ' + (r['bride_name']||''), source: parish, image_ref: r['image_ref'], created_at: r['created_at'], type: 'marriage' }));
    const q3 = await cassClient.execute('SELECT parish_id, record_id, confirmation_date as ev_date, person_name as text, scanned_document_url as image_ref, created_at FROM confirmation_records WHERE parish_id = ? LIMIT ?;', [parish, limit], { prepare: true });
    q3.rows.forEach(r => results.push({ ...normalizeRow(r), created_at: r['created_at'], type: 'confirmation' }));

    const filtered = results.filter(r => r.created_at && new Date(r.created_at) >= since);
    filtered.sort((a, b) => (new Date(b.created_at).getTime()) - (new Date(a.created_at).getTime()));
    return res.json({ rows: filtered.slice(0, limit) });
  } catch (e: any) {
    return res.status(500).json({ error: 'recent_failed', detail: e?.message });
  }
});

export const api = functions.https.onRequest(app);

// Certificate Requests
app.get('/api/requests', verifyAuth, async (req, res) => {
  try {
    await ensureCassandra();
    const parish = (req.query.parish_id as string) || DEFAULT_PARISH;
    const limit = Math.min(parseInt((req.query.limit as string) || '50', 10), 200);
    const rs = await cassClient.execute(
      'SELECT parish_id, request_id, record_id, request_type, requester_name, status, requested_at, processed_at, processed_by, notification_sent FROM certificate_requests WHERE parish_id = ? LIMIT ?;',
      [parish, limit],
      { prepare: true }
    );
    const rows = rs.rows.map(r => ({
      parish_id: r['parish_id'],
      request_id: r['request_id']?.toString?.(),
      record_id: r['record_id']?.toString?.(),
      request_type: r['request_type'],
      requester_name: r['requester_name'],
      status: r['status'],
      requested_at: r['requested_at'],
      processed_at: r['processed_at'],
      processed_by: r['processed_by'],
      notification_sent: r['notification_sent'],
    }));
    return res.json({ rows });
  } catch (e: any) {
    return res.status(500).json({ error: 'requests_list_failed', detail: e?.message });
  }
});

app.post('/api/requests', verifyAuth, async (req, res) => {
  try {
    await ensureCassandra();
    const uid = (req as any).uid as string;
    const body = req.body || {};
    const parish = (body.parish_id as string) || DEFAULT_PARISH;
    const requestId = CassTypes.Uuid.random();
    const recordId = body.record_id ? CassTypes.Uuid.fromString(body.record_id) : null;
    const now = new Date();
    await cassClient.execute(
      'INSERT INTO certificate_requests (parish_id, request_id, record_id, request_type, requester_name, status, requested_at, processed_at, processed_by, notification_sent) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [parish, requestId, recordId, (body.request_type||'baptism'), (body.requester_name||''), (body.status||'pending'), now, null, uid, false],
      { prepare: true }
    );
    return res.json({ ok: true, request_id: requestId.toString() });
  } catch (e: any) {
    return res.status(500).json({ error: 'requests_create_failed', detail: e?.message });
  }
});

app.put('/api/requests/:id', verifyAuth, async (req, res) => {
  try {
    await ensureCassandra();
    const requestId = req.params.id;
    const body = req.body || {};
    const parish = (body.parish_id as string) || DEFAULT_PARISH;
    const status = body.status as string | undefined;
    const processedAt = body.processed_at ? new Date(body.processed_at) : (status && status !== 'pending' ? new Date() : null);
    const processedBy = (req as any).uid as string;
    await cassClient.execute(
      'UPDATE certificate_requests SET status = COALESCE(?, status), processed_at = COALESCE(?, processed_at), processed_by = COALESCE(?, processed_by), notification_sent = COALESCE(?, notification_sent) WHERE parish_id = ? AND request_id = ?;',
      [status || null, processedAt, processedBy, body.notification_sent ?? null, parish, CassTypes.Uuid.fromString(requestId)],
      { prepare: true }
    );
    return res.json({ ok: true });
  } catch (e: any) {
    return res.status(500).json({ error: 'requests_update_failed', detail: e?.message });
  }
});

// Admin Logs (recent)
app.get('/api/admin/logs', verifyAuth, requireAdmin, async (req, res) => {
  try {
    await ensureCassandra();
    const parish = (req.query.parish_id as string) || DEFAULT_PARISH;
    const limit = Math.min(parseInt((req.query.limit as string) || '100', 10), 300);
    const days = Math.min(parseInt((req.query.days as string) || '7', 10), 365);
    const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
    // For simplicity, ALLOW FILTERING to get recent logs across users in this parish
    const rs = await cassClient.execute(
      'SELECT parish_id, user_id, action, target_record_id, action_time, details FROM user_audit_log WHERE parish_id = ? ALLOW FILTERING;',
      [parish],
      { prepare: true }
    );
    const rows = rs.rows
      .map(r => ({
        parish_id: r['parish_id'],
        user_id: r['user_id'],
        action: r['action'],
        target_record_id: r['target_record_id']?.toString?.(),
        action_time: r['action_time'],
        details: r['details'],
      }))
      .filter(r => r.action_time && new Date(r.action_time) >= since)
      .sort((a, b) => new Date(b.action_time).getTime() - new Date(a.action_time).getTime())
      .slice(0, limit);
    return res.json({ rows });
  } catch (e: any) {
    return res.status(500).json({ error: 'logs_list_failed', detail: e?.message });
  }
});
