const express = require('express');

const { getAdmin } = require('../firebase_admin');
const { requireSelfOrStaff } = require('../middleware/auth');
const { logAudit } = require('../utils/audit');

const router = express.Router();

function toIso(val) {
  if (!val) return null;
  if (val instanceof Date) return val.toISOString();
  if (typeof val.toDate === 'function') {
    const d = val.toDate();
    return d instanceof Date ? d.toISOString() : null;
  }
  try {
    const d = new Date(val);
    return Number.isNaN(d.getTime()) ? null : d.toISOString();
  } catch (_) {
    return null;
  }
}

// GET /api/users/:id
router.get(
  '/:id',
  requireSelfOrStaff((req) => req.params.id),
  async (req, res) => {
    try {
      const uid = (req.params.id || '').toString();
      const admin = getAdmin();
      const db = admin.firestore();
      const snap = await db.collection('users').doc(uid).get();
      if (!snap.exists) return res.status(404).json({ error: 'User not found' });
      const d = snap.data() || {};
      return res.json({
        id: uid,
        email: d.email || null,
        displayName: d.displayName || d.display_name || null,
        phone: d.phone || null,
        address: d.address || null,
        household: Array.isArray(d.household) ? d.household : [],
        uploaded_ids: Array.isArray(d.uploaded_ids) ? d.uploaded_ids : [],
        privacy_consent_log: Array.isArray(d.privacy_consent_log)
          ? d.privacy_consent_log
          : [],
        createdAt: toIso(d.createdAt) || toIso(d.created_at) || null,
        updatedAt: toIso(d.updatedAt) || toIso(d.updated_at) || null,
      });
    } catch (error) {
      console.error('User get error:', error);
      return res.status(500).json({ error: 'user_get_failed' });
    }
  },
);

// PUT /api/users/:id
router.put(
  '/:id',
  requireSelfOrStaff((req) => req.params.id),
  async (req, res) => {
    try {
      const uid = (req.params.id || '').toString();
      const body = req.body || {};

      const patch = {
        updated_at: new Date(),
      };

      if (body.displayName != null) patch.displayName = body.displayName.toString();
      if (body.phone != null) patch.phone = body.phone.toString();
      if (body.address != null) patch.address = body.address;

      if (Array.isArray(body.household)) {
        patch.household = body.household.slice(0, 20);
      }

      if (Array.isArray(body.uploaded_ids)) {
        patch.uploaded_ids = body.uploaded_ids.slice(0, 20);
      }

      if (body.privacy_consent != null) {
        patch.privacy_consent = body.privacy_consent === true;
        patch.privacy_consent_log = [
          {
            at: new Date().toISOString(),
            value: patch.privacy_consent,
          },
        ];
      }

      const admin = getAdmin();
      const db = admin.firestore();
      await db.collection('users').doc(uid).set(patch, { merge: true });

      // Sync household data to households collection for admin/staff visibility
      console.log('[Sync] Checking household sync:', { hasHousehold: Array.isArray(body.household), count: body.household?.length });
      if (Array.isArray(body.household) && body.household.length > 0) {
        console.log('[Sync] Starting household sync for user:', uid);
        await syncUserHouseholdToCollection(db, uid, body.household, body);
      } else {
        console.log('[Sync] No household data to sync');
      }

      await logAudit(req, {
        action: 'User Profile Updated',
        resourceType: 'user',
        resourceId: uid,
        newValues: patch,
      });

      return res.json({ ok: true });
    } catch (error) {
      console.error('User update error:', error);
      return res.status(500).json({ error: 'user_update_failed' });
    }
  },
);

// Helper: Sync user profile household data to households collection
async function syncUserHouseholdToCollection(db, uid, householdMembers, body) {
  try {
    // Check if user already has a linked household
    const userSnap = await db.collection('users').doc(uid).get();
    const userData = userSnap.data() || {};
    let householdId = userData.linkedHouseholdId;

    // Get first member as head of family info
    const headMember = householdMembers[0] || {};
    const familyName = headMember.lastName || body.displayName || 'Unknown Family';
    const address = body.address || headMember.address || '';
    const barangay = body.barangay || headMember.barangay || 'Unknown';
    const phone = body.phone || headMember.contactNumber || '';

    if (householdId) {
      // Update existing household
      const householdRef = db.collection('households').doc(householdId);
      const householdSnap = await householdRef.get();

      if (householdSnap.exists) {
        await householdRef.update({
          familyName: familyName,
          address: address,
          barangay: barangay,
          contactNumber: phone,
          updatedAt: new Date(),
        });
        console.log('[Sync] Updated household:', householdId);
      } else {
        householdId = null; // Create new if not found
      }
    }

    if (!householdId) {
      // Create new household
      const docRef = db.collection('households').doc();
      householdId = docRef.id;

      // Generate household ID like HH-2024-001
      const now = new Date();
      const year = now.getFullYear();
      const countSnap = await db.collection('households')
        .where('householdId', '>=', `HH-${year}-`)
        .where('householdId', '<', `HH-${year + 1}-`)
        .get();
      const sequence = (countSnap.size + 1).toString().padStart(3, '0');
      const generatedId = `HH-${year}-${sequence}`;

      await docRef.set({
        id: householdId,
        householdId: generatedId,
        familyName: familyName,
        headOfFamilyId: uid,
        address: address,
        barangay: barangay,
        city: body.city || '',
        province: body.province || '',
        zipCode: body.zipCode || '',
        contactNumber: phone,
        email: body.email || '',
        isArchived: false,
        registeredAt: new Date(),
        updatedAt: null,
      });

      // Link household to user
      await db.collection('users').doc(uid).update({
        linkedHouseholdId: householdId,
      });

      console.log('[Sync] Created household:', householdId, generatedId);
    }

    // Sync members to household_members collection (not subcollection)
    for (const member of householdMembers) {
      const memberId = member.id || db.collection('household_members').doc().id;
      
      // Parse name from user profile format (name, relationship, birthDate)
      const fullName = member.name || '';
      const nameParts = fullName.split(' ');
      const firstName = nameParts[0] || '';
      const lastName = nameParts.length > 1 ? nameParts.slice(1).join(' ') : '';
      
      await db.collection('household_members').doc(memberId).set({
        id: memberId,
        householdId: householdId,
        firstName: firstName,
        lastName: lastName,
        fullName: fullName,
        role: member.relationship || 'Member',
        gender: member.gender || 'Male',
        civilStatus: member.civilStatus || 'Single',
        birthDate: member.birthDate || null,
        contactNumber: member.contactNumber || '',
        isActive: true,
        dateAdded: member.dateAdded ? new Date(member.dateAdded) : new Date(),
        updatedAt: new Date(),
      }, { merge: true });
      
      console.log('[Sync] Saved member:', memberId, fullName);
    }

    console.log('[Sync] Synced', householdMembers.length, 'members to household:', householdId);
  } catch (err) {
    console.error('[Sync] Error syncing household:', err);
    // Don't throw - allow profile update to succeed even if sync fails
  }
}

// POST /api/users/:id/export
router.post(
  '/:id/export',
  requireSelfOrStaff((req) => req.params.id),
  async (req, res) => {
    try {
      const uid = (req.params.id || '').toString();
      const admin = getAdmin();
      const db = admin.firestore();

      const userSnap = await db.collection('users').doc(uid).get();
      if (!userSnap.exists) return res.status(404).json({ error: 'User not found' });

      const reqSnap = await db
        .collection('requests')
        .where('created_by_uid', '==', uid)
        .limit(500)
        .get();

      const exportPayload = {
        user: { id: uid, ...(userSnap.data() || {}) },
        requests: reqSnap.docs.map((d) => ({ id: d.id, ...(d.data() || {}) })),
        generated_at: new Date().toISOString(),
      };

      const json = Buffer.from(JSON.stringify(exportPayload, null, 2), 'utf8').toString('base64');
      const downloadUrl = `data:application/json;base64,${json}`;

      await logAudit(req, {
        action: 'User Data Export Generated',
        resourceType: 'user_export',
        resourceId: uid,
      });

      return res.json({
        ok: true,
        file: {
          name: `user_export_${uid}.json`,
          mime: 'application/json',
          download_url: downloadUrl,
        },
      });
    } catch (error) {
      console.error('User export error:', error);
      return res.status(500).json({ error: 'user_export_failed' });
    }
  },
);

module.exports = router;
