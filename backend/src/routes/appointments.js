const express = require('express');
const { getAdmin } = require('../firebase_admin');
const { verifyFirebaseToken } = require('../middleware/auth');

const router = express.Router();

// GET /api/appointments - Get user's appointments
router.get('/', verifyFirebaseToken, async (req, res) => {
  try {
    const uid = req.user?.uid;
    if (!uid) {
      return res.status(401).json({ error: 'Not authenticated' });
    }

    const admin = getAdmin();
    const db = admin.firestore();

    const limit = Math.min(parseInt(req.query.limit || '50', 10) || 50, 100);

    let query = db
      .collection('bookings')
      .where('requester_uid', '==', uid)
      .limit(limit);

    // Try to order by scheduled_for if possible
    try {
      query = query.orderBy('scheduled_for', 'asc');
    } catch (_) {
      // Ignore ordering errors
    }

    const snap = await query.get();

    const appointments = snap.docs.map((doc) => {
      const data = doc.data() || {};
      return {
        id: doc.id,
        ...data,
        scheduled_for: data.scheduled_for?.toDate?.()?.toISOString?.() || null,
        created_at: data.created_at?.toDate?.()?.toISOString?.() || null,
        updated_at: data.updated_at?.toDate?.()?.toISOString?.() || null,
      };
    });

    return res.json({ rows: appointments });
  } catch (error) {
    console.error('Get appointments error:', error);
    return res.status(500).json({ error: 'Appointments API failed' });
  }
});

// GET /api/appointments/:id - Get single appointment
router.get('/:id', verifyFirebaseToken, async (req, res) => {
  try {
    const appointmentId = req.params.id;
    const uid = req.user?.uid;

    const admin = getAdmin();
    const db = admin.firestore();

    const doc = await db.collection('bookings').doc(appointmentId).get();

    if (!doc.exists) {
      return res.status(404).json({ error: 'Appointment not found' });
    }

    const data = doc.data();
    // Check ownership
    if (data.requester_uid !== uid && req.user.role !== 'admin' && req.user.role !== 'staff') {
      return res.status(403).json({ error: 'Access denied' });
    }

    return res.json({
      id: doc.id,
      ...data,
      scheduled_for: data.scheduled_for?.toDate?.()?.toISOString?.() || null,
    });
  } catch (error) {
    console.error('Get appointment error:', error);
    return res.status(500).json({ error: 'Appointment fetch failed' });
  }
});

// POST /api/appointments - Create new appointment
router.post('/', verifyFirebaseToken, async (req, res) => {
  try {
    const uid = req.user?.uid;
    if (!uid) {
      return res.status(401).json({ error: 'Not authenticated' });
    }

    const admin = getAdmin();
    const db = admin.firestore();

    const {
      title,
      scheduled_for,
      notes,
      event_id,
    } = req.body;

    if (!title || !scheduled_for) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    const docRef = db.collection('bookings').doc();
    const appointmentData = {
      id: docRef.id,
      requester_uid: uid,
      title,
      scheduled_for: admin.firestore.Timestamp.fromDate(new Date(scheduled_for)),
      notes: notes || null,
      event_id: event_id || null,
      status: 'pending',
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: null,
    };

    await docRef.set(appointmentData);

    return res.status(201).json({
      success: true,
      appointment_id: docRef.id,
      appointment: {
        ...appointmentData,
        scheduled_for: scheduled_for,
        created_at: new Date().toISOString(),
      },
    });
  } catch (error) {
    console.error('Create appointment error:', error);
    return res.status(500).json({ error: 'Failed to create appointment' });
  }
});

// DELETE /api/appointments/:id - Cancel appointment
router.delete('/:id', verifyFirebaseToken, async (req, res) => {
  try {
    const appointmentId = req.params.id;
    const uid = req.user?.uid;

    const admin = getAdmin();
    const db = admin.firestore();

    const doc = await db.collection('bookings').doc(appointmentId).get();

    if (!doc.exists) {
      return res.status(404).json({ error: 'Appointment not found' });
    }

    const data = doc.data();
    // Check ownership
    if (data.requester_uid !== uid && req.user.role !== 'admin' && req.user.role !== 'staff') {
      return res.status(403).json({ error: 'Access denied' });
    }

    await db.collection('bookings').doc(appointmentId).delete();

    return res.json({ success: true, message: 'Appointment cancelled' });
  } catch (error) {
    console.error('Delete appointment error:', error);
    return res.status(500).json({ error: 'Failed to cancel appointment' });
  }
});

// PUT /api/appointments/:id - Update appointment
router.put('/:id', verifyFirebaseToken, async (req, res) => {
  try {
    const appointmentId = req.params.id;
    const uid = req.user?.uid;

    const admin = getAdmin();
    const db = admin.firestore();

    const doc = await db.collection('bookings').doc(appointmentId).get();

    if (!doc.exists) {
      return res.status(404).json({ error: 'Appointment not found' });
    }

    const data = doc.data();
    if (data.requester_uid !== uid && req.user.role !== 'admin' && req.user.role !== 'staff') {
      return res.status(403).json({ error: 'Access denied' });
    }

    const updates = { ...req.body };
    delete updates.id;
    delete updates.requester_uid;
    delete updates.created_at;

    if (updates.scheduled_for) {
      updates.scheduled_for = admin.firestore.Timestamp.fromDate(new Date(updates.scheduled_for));
    }

    updates.updated_at = admin.firestore.FieldValue.serverTimestamp();

    await db.collection('bookings').doc(appointmentId).update(updates);

    return res.json({ success: true, message: 'Appointment updated' });
  } catch (error) {
    console.error('Update appointment error:', error);
    return res.status(500).json({ error: 'Failed to update appointment' });
  }
});

module.exports = router;
