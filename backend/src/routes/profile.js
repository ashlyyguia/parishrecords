const express = require('express');
const { getAdmin } = require('../firebase_admin');
const { verifyFirebaseToken, requireSelfOrStaff } = require('../middleware/auth');

const router = express.Router();

// GET /api/users/:id - Get user profile
router.get('/:id', verifyFirebaseToken, requireSelfOrStaff((req) => req.params.id), async (req, res) => {
  try {
    const uid = (req.params.id || '').toString();
    if (!uid) {
      return res.status(400).json({ error: 'Missing user id' });
    }

    const admin = getAdmin();
    const db = admin.firestore();

    // Get user document
    const userDoc = await db.collection('users').doc(uid).get();
    
    if (!userDoc.exists) {
      return res.status(404).json({ error: 'User not found' });
    }

    const userData = userDoc.data() || {};

    // Get household info if available
    let household = null;
    try {
      const householdSnap = await db
        .collection('households')
        .where('created_by_uid', '==', uid)
        .limit(1)
        .get();
      
      if (!householdSnap.empty) {
        const householdDoc = householdSnap.docs[0];
        household = {
          id: householdDoc.id,
          ...householdDoc.data(),
        };
      }
    } catch (e) {
      // Ignore household fetch errors
    }

    // Get household members if household exists
    let members = [];
    if (household) {
      try {
        const membersSnap = await db
          .collection('household_members')
          .where('householdId', '==', household.id)
          .where('isActive', '==', true)
          .get();
        
        members = membersSnap.docs.map((doc) => ({
          id: doc.id,
          ...doc.data(),
        }));
      } catch (e) {
        // Ignore members fetch errors
      }
    }

    const profile = {
      id: uid,
      email: userData.email || null,
      display_name: userData.display_name || userData.displayName || null,
      first_name: userData.first_name || null,
      last_name: userData.last_name || null,
      role: userData.role || 'parishioner',
      phone: userData.phone || null,
      address: userData.address || null,
      barangay: userData.barangay || null,
      city: userData.city || null,
      province: userData.province || null,
      zip_code: userData.zip_code || null,
      email_verified: userData.email_verified === true,
      disabled: userData.disabled === true,
      created_at: userData.created_at?.toDate?.()?.toISOString?.() || null,
      last_login: userData.last_login?.toDate?.()?.toISOString?.() || null,
      household,
      members,
      member_count: members.length,
    };

    return res.json({ profile });
  } catch (error) {
    console.error('Get profile error:', error);
    return res.status(500).json({ error: 'Profile API failed' });
  }
});

// PUT /api/users/:id - Update user profile
router.put('/:id', verifyFirebaseToken, requireSelfOrStaff((req) => req.params.id), async (req, res) => {
  try {
    const uid = (req.params.id || '').toString();
    if (!uid) {
      return res.status(400).json({ error: 'Missing user id' });
    }

    const admin = getAdmin();
    const db = admin.firestore();

    const allowedUpdates = [
      'display_name',
      'displayName',
      'first_name',
      'last_name',
      'phone',
      'address',
      'barangay',
      'city',
      'province',
      'zip_code',
    ];

    const updates = {};
    for (const key of allowedUpdates) {
      if (req.body[key] !== undefined) {
        updates[key] = req.body[key];
      }
    }

    if (Object.keys(updates).length === 0) {
      return res.status(400).json({ error: 'No valid fields to update' });
    }

    updates.updated_at = admin.firestore.FieldValue.serverTimestamp();

    await db.collection('users').doc(uid).update(updates);

    return res.json({ success: true, message: 'Profile updated' });
  } catch (error) {
    console.error('Update profile error:', error);
    return res.status(500).json({ error: 'Failed to update profile' });
  }
});

module.exports = router;
