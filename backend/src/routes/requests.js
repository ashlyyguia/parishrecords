const express = require('express');
const { getAdmin } = require('../firebase_admin');
const { verifyFirebaseToken, requireSelfOrStaff } = require('../middleware/auth');

const router = express.Router();

// GET /api/requests - Get user's requests
router.get('/', verifyFirebaseToken, async (req, res) => {
  try {
    const uid = req.user?.uid;
    if (!uid) {
      return res.status(401).json({ error: 'Not authenticated' });
    }

    const admin = getAdmin();
    const db = admin.firestore();

    const limit = Math.min(parseInt(req.query.limit || '50', 10) || 50, 100);

    const snap = await db
      .collection('requests')
      .where('created_by_uid', '==', uid)
      .limit(limit)
      .get();

    const requests = snap.docs.map((doc) => {
      const data = doc.data() || {};
      return {
        request_id: doc.id,
        request_type: data.request_type || null,
        requester_name: data.requester_name || null,
        status: data.status || 'pending',
        requested_at: data.requested_at?.toDate?.()?.toISOString?.() || null,
        processed_at: data.processed_at?.toDate?.()?.toISOString?.() || null,
        record_id: data.record_id || null,
        ...data,
      };
    });

    return res.json({ rows: requests });
  } catch (error) {
    console.error('Get requests error:', error);
    return res.status(500).json({ error: 'Requests list failed' });
  }
});

// GET /api/requests/:id - Get single request
router.get('/:id', verifyFirebaseToken, async (req, res) => {
  try {
    const requestId = req.params.id;
    const uid = req.user?.uid;

    const admin = getAdmin();
    const db = admin.firestore();

    const doc = await db.collection('requests').doc(requestId).get();

    if (!doc.exists) {
      return res.status(404).json({ error: 'Request not found' });
    }

    const data = doc.data();
    // Check ownership
    if (data.created_by_uid !== uid && req.user.role !== 'admin' && req.user.role !== 'staff') {
      return res.status(403).json({ error: 'Access denied' });
    }

    return res.json({
      row: {
        request_id: doc.id,
        ...data,
        requested_at: data.requested_at?.toDate?.()?.toISOString?.() || null,
      }
    });
  } catch (error) {
    console.error('Get request error:', error);
    return res.status(500).json({ error: 'Request fetch failed' });
  }
});

// POST /api/requests - Create new request
router.post('/', verifyFirebaseToken, async (req, res) => {
  try {
    const uid = req.user?.uid;
    if (!uid) {
      return res.status(401).json({ error: 'Not authenticated' });
    }

    const admin = getAdmin();
    const db = admin.firestore();

    const {
      request_type,
      requester_name,
      requester_contact,
      purpose,
      notes,
    } = req.body;

    if (!request_type || !requester_name) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    const docRef = db.collection('requests').doc();
    const requestData = {
      request_id: docRef.id,
      created_by_uid: uid,
      request_type,
      requester_name,
      requester_contact: requester_contact || null,
      purpose: purpose || null,
      notes: notes || null,
      status: 'pending',
      requested_at: admin.firestore.FieldValue.serverTimestamp(),
      processed_at: null,
      processed_by: null,
    };

    await docRef.set(requestData);

    return res.status(201).json({
      success: true,
      request: {
        ...requestData,
        requested_at: new Date().toISOString(),
      },
    });
  } catch (error) {
    console.error('Create request error:', error);
    return res.status(500).json({ error: 'Failed to create request' });
  }
});

// POST /api/requests/:id/cancel - Cancel request
router.post('/:id/cancel', verifyFirebaseToken, async (req, res) => {
  try {
    const requestId = req.params.id;
    const uid = req.user?.uid;

    const admin = getAdmin();
    const db = admin.firestore();

    const doc = await db.collection('requests').doc(requestId).get();

    if (!doc.exists) {
      return res.status(404).json({ error: 'Request not found' });
    }

    const data = doc.data();
    if (data.created_by_uid !== uid && req.user.role !== 'admin' && req.user.role !== 'staff') {
      return res.status(403).json({ error: 'Access denied' });
    }

    await db.collection('requests').doc(requestId).update({
      status: 'cancelled',
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });

    return res.json({ success: true, message: 'Request cancelled' });
  } catch (error) {
    console.error('Cancel request error:', error);
    return res.status(500).json({ error: 'Failed to cancel request' });
  }
});

module.exports = router;
