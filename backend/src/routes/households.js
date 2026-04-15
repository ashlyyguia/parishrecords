/**
 * Household API Routes
 * Provides endpoints for household registration, member management,
 * and sacrament record linking
 */

const express = require('express');
const { getAdmin } = require('../firebase_admin');

const router = express.Router();

// Generate unique household ID
async function generateHouseholdId() {
  const now = new Date();
  const year = now.getFullYear();
  const admin = getAdmin();
  
  // Get count of households for this year
  const snapshot = await admin.firestore()
    .collection('households')
    .where('householdId', '>=', `HH-${year}-`)
    .where('householdId', '<', `HH-${year + 1}-`)
    .get();
  
  const count = snapshot.size + 1;
  const sequence = count.toString().padStart(3, '0');
  return `HH-${year}-${sequence}`;
}

// ==================== HOUSEHOLD CRUD ====================

// Create new household
router.post('/', async (req, res) => {
  try {
    const admin = getAdmin();
    const {
      familyName,
      headOfFamilyId = '',
      address,
      barangay,
      city,
      province = '',
      zipCode = '',
      contactNumber = '',
      email = '',
      notes = '',
      metadata = {}
    } = req.body;

    // Validate required fields
    if (!familyName || !address || !barangay || !city) {
      return res.status(400).json({
        error: 'Missing required fields: familyName, address, barangay, city'
      });
    }

    const householdId = await generateHouseholdId();
    const docRef = admin.firestore().collection('households').doc();
    
    const household = {
      id: docRef.id,
      householdId,
      familyName: familyName.trim(),
      headOfFamilyId,
      address: address.trim(),
      barangay: barangay.trim(),
      city: city.trim(),
      province: province.trim(),
      zipCode: zipCode.trim(),
      contactNumber: contactNumber.trim(),
      email: email.trim(),
      notes: notes.trim(),
      metadata,
      isArchived: false,
      registeredAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: null
    };

    await docRef.set(household);
    
    res.status(201).json({
      success: true,
      household: {
        ...household,
        registeredAt: new Date().toISOString()
      }
    });
  } catch (error) {
    console.error('Error creating household:', error);
    res.status(500).json({ error: 'Failed to create household' });
  }
});

// ==================== MEMBER LOOKUP (by memberId) ====================

// Get a single member by memberId
router.get('/members/:memberId', async (req, res) => {
  try {
    const admin = getAdmin();
    const { memberId } = req.params;
    const doc = await admin.firestore().collection('household_members').doc(memberId).get();
    if (!doc.exists) {
      return res.status(404).json({ error: 'Member not found' });
    }
    return res.json({
      success: true,
      member: {
        id: doc.id,
        ...doc.data(),
      },
    });
  } catch (error) {
    console.error('Error fetching member:', error);
    return res.status(500).json({ error: 'Failed to fetch member' });
  }
});

// Delete member (soft delete) by memberId
router.delete('/members/:memberId', async (req, res) => {
  try {
    const admin = getAdmin();
    const { memberId } = req.params;
    const ref = admin.firestore().collection('household_members').doc(memberId);
    const doc = await ref.get();
    if (!doc.exists) {
      return res.status(404).json({ error: 'Member not found' });
    }
    await ref.update({
      isActive: false,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return res.json({
      success: true,
      message: 'Member removed',
    });
  } catch (error) {
    console.error('Error deleting member:', error);
    return res.status(500).json({ error: 'Failed to delete member' });
  }
});

// Link sacrament record(s) to member by memberId
router.post('/members/:memberId/sacraments', async (req, res) => {
  try {
    const admin = getAdmin();
    const { memberId } = req.params;
    const {
      baptismRecordId,
      confirmationRecordId,
      marriageRecordId,
      deathRecordId,
    } = req.body || {};

    const ref = admin.firestore().collection('household_members').doc(memberId);
    const doc = await ref.get();
    if (!doc.exists) {
      return res.status(404).json({ error: 'Member not found' });
    }

    const updates = {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (baptismRecordId !== undefined) updates.baptismRecordId = baptismRecordId;
    if (confirmationRecordId !== undefined) updates.confirmationRecordId = confirmationRecordId;
    if (marriageRecordId !== undefined) updates.marriageRecordId = marriageRecordId;
    if (deathRecordId !== undefined) updates.deathRecordId = deathRecordId;

    await ref.update(updates);

    return res.json({
      success: true,
      message: 'Sacrament record linked',
    });
  } catch (error) {
    console.error('Error linking sacrament:', error);
    return res.status(500).json({ error: 'Failed to link sacrament' });
  }
});

// List members globally (across households)
router.get('/members', async (req, res) => {
  try {
    const admin = getAdmin();
    const { search = '', sacramentStatus, limit = 200 } = req.query;

    let query = admin
      .firestore()
      .collection('household_members')
      .where('isActive', '==', true)
      .orderBy('fullName')
      .limit(Number(limit) || 200);

    const snap = await query.get();
    let rows = snap.docs.map((d) => ({ id: d.id, ...d.data() }));

    const q = String(search || '').trim().toLowerCase();
    if (q) {
      rows = rows.filter((m) =>
        String(m.fullName || '').toLowerCase().includes(q),
      );
    }

    if (sacramentStatus) {
      const status = String(sacramentStatus).toLowerCase();
      rows = rows.filter((m) => {
        if (status === 'baptized') return m.baptismRecordId != null;
        if (status === 'confirmed') return m.confirmationRecordId != null;
        if (status === 'married') return m.marriageRecordId != null;
        if (status === 'dead') return m.deathRecordId != null;
        return true;
      });
    }

    return res.json({
      success: true,
      rows,
      count: rows.length,
    });
  } catch (error) {
    console.error('Error listing members:', error);
    return res.status(500).json({ error: 'Failed to list members' });
  }
});

// Get all households with filters
router.get('/', async (req, res) => {
  try {
    const admin = getAdmin();
    const { barangay, includeArchived, search, limit = 50 } = req.query;
    
    let query = admin.firestore().collection('households');
    
    // Apply filters
    if (includeArchived !== 'true') {
      query = query.where('isArchived', '==', false);
    }
    
    if (barangay) {
      query = query.where('barangay', '==', barangay);
    }
    
    query = query.orderBy('registeredAt', 'desc').limit(parseInt(limit));
    
    const snapshot = await query.get();
    let households = snapshot.docs.map(doc => ({
      id: doc.id,
      ...doc.data()
    }));
    
    // Client-side search if provided
    if (search) {
      const lowerSearch = search.toLowerCase();
      households = households.filter(h => 
        h.familyName?.toLowerCase().includes(lowerSearch) ||
        h.householdId?.toLowerCase().includes(lowerSearch) ||
        h.address?.toLowerCase().includes(lowerSearch) ||
        h.contactNumber?.includes(search)
      );
    }
    
    res.json({
      success: true,
      count: households.length,
      households
    });
  } catch (error) {
    console.error('Error fetching households:', error);
    res.status(500).json({ error: 'Failed to fetch households' });
  }
});

// ==================== BARANGAYS ====================

// Get all unique barangays
router.get('/meta/barangays', async (req, res) => {
  try {
    const admin = getAdmin();
    const snapshot = await admin.firestore()
      .collection('households')
      .where('isArchived', '==', false)
      .get();
    
    const barangays = [...new Set(
      snapshot.docs
        .map(d => d.data().barangay)
        .filter(b => b)
    )].sort();
    
    res.json({
      success: true,
      barangays
    });
  } catch (error) {
    console.error('Error fetching barangays:', error);
    res.status(500).json({ error: 'Failed to fetch barangays' });
  }
});

// Get single household
router.get('/:id', async (req, res) => {
  try {
    const admin = getAdmin();
    const { id } = req.params;
    const doc = await admin.firestore().collection('households').doc(id).get();
    
    if (!doc.exists) {
      return res.status(404).json({ error: 'Household not found' });
    }
    
    res.json({
      success: true,
      household: {
        id: doc.id,
        ...doc.data()
      }
    });
  } catch (error) {
    console.error('Error fetching household:', error);
    res.status(500).json({ error: 'Failed to fetch household' });
  }
});

// Update household
router.put('/:id', async (req, res) => {
  try {
    const admin = getAdmin();
    const { id } = req.params;
    const updates = req.body;
    
    // Remove immutable fields
    delete updates.id;
    delete updates.householdId;
    delete updates.registeredAt;
    
    updates.updatedAt = admin.firestore.FieldValue.serverTimestamp();
    
    await admin.firestore().collection('households').doc(id).update(updates);
    
    res.json({
      success: true,
      message: 'Household updated'
    });
  } catch (error) {
    console.error('Error updating household:', error);
    res.status(500).json({ error: 'Failed to update household' });
  }
});

// Archive/Unarchive household
router.patch('/:id/archive', async (req, res) => {
  try {
    const admin = getAdmin();
    const { id } = req.params;
    const { archived = true } = req.body;
    
    await admin.firestore().collection('households').doc(id).update({
      isArchived: archived,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    
    res.json({
      success: true,
      message: archived ? 'Household archived' : 'Household restored'
    });
  } catch (error) {
    console.error('Error archiving household:', error);
    res.status(500).json({ error: 'Failed to archive household' });
  }
});

// Delete household
router.delete('/:id', async (req, res) => {
  try {
    const admin = getAdmin();
    const { id } = req.params;
    
    // First delete all members
    const membersSnapshot = await admin.firestore()
      .collection('household_members')
      .where('householdId', '==', id)
      .get();
    
    const batch = admin.firestore().batch();
    membersSnapshot.docs.forEach(doc => batch.delete(doc.ref));
    batch.delete(admin.firestore().collection('households').doc(id));
    
    await batch.commit();
    
    res.json({
      success: true,
      message: 'Household and members deleted'
    });
  } catch (error) {
    console.error('Error deleting household:', error);
    res.status(500).json({ error: 'Failed to delete household' });
  }
});

// ==================== HOUSEHOLD MEMBERS ====================

// Add member to household
router.post('/:id/members', async (req, res) => {
  try {
    const admin = getAdmin();
    const { id } = req.params;
    const memberData = req.body;
    
    // Verify household exists
    const householdDoc = await admin.firestore().collection('households').doc(id).get();
    if (!householdDoc.exists) {
      return res.status(404).json({ error: 'Household not found' });
    }
    
    const docRef = admin.firestore().collection('household_members').doc();
    
    const member = {
      id: docRef.id,
      householdId: id,
      ...memberData,
      isActive: true,
      dateAdded: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: null
    };
    
    await docRef.set(member);
    
    res.status(201).json({
      success: true,
      member: {
        ...member,
        dateAdded: new Date().toISOString()
      }
    });
  } catch (error) {
    console.error('Error adding member:', error);
    res.status(500).json({ error: 'Failed to add member' });
  }
});

// Get all members of a household
router.get('/:id/members', async (req, res) => {
  try {
    const admin = getAdmin();
    const { id } = req.params;
    
    const snapshot = await admin.firestore()
      .collection('household_members')
      .where('householdId', '==', id)
      .where('isActive', '==', true)
      .orderBy('dateAdded')
      .get();
    
    const members = snapshot.docs.map(doc => ({
      id: doc.id,
      ...doc.data()
    }));
    
    res.json({
      success: true,
      count: members.length,
      members
    });
  } catch (error) {
    console.error('Error fetching members:', error);
    res.status(500).json({ error: 'Failed to fetch members' });
  }
});

// Update member
router.put('/:householdId/members/:memberId', async (req, res) => {
  try {
    const admin = getAdmin();
    const { memberId } = req.params;
    const updates = req.body;
    
    delete updates.id;
    delete updates.householdId;
    delete updates.dateAdded;
    
    updates.updatedAt = admin.firestore.FieldValue.serverTimestamp();
    
    await admin.firestore().collection('household_members').doc(memberId).update(updates);
    
    res.json({
      success: true,
      message: 'Member updated'
    });
  } catch (error) {
    console.error('Error updating member:', error);
    res.status(500).json({ error: 'Failed to update member' });
  }
});

// Delete member (soft delete)
router.delete('/:householdId/members/:memberId', async (req, res) => {
  try {
    const admin = getAdmin();
    const { memberId } = req.params;
    
    await admin.firestore().collection('household_members').doc(memberId).update({
      isActive: false,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    
    res.json({
      success: true,
      message: 'Member removed'
    });
  } catch (error) {
    console.error('Error deleting member:', error);
    res.status(500).json({ error: 'Failed to delete member' });
  }
});

// Set head of family
router.patch('/:id/head-of-family', async (req, res) => {
  try {
    const admin = getAdmin();
    const { id } = req.params;
    const { memberId } = req.body;
    
    if (!memberId) {
      return res.status(400).json({ error: 'memberId is required' });
    }
    
    await admin.firestore().collection('households').doc(id).update({
      headOfFamilyId: memberId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    
    res.json({
      success: true,
      message: 'Head of family updated'
    });
  } catch (error) {
    console.error('Error setting head of family:', error);
    res.status(500).json({ error: 'Failed to set head of family' });
  }
});

// ==================== HOUSEHOLD STATS ====================

// Get household statistics
router.get('/:id/stats', async (req, res) => {
  try {
    const admin = getAdmin();
    const { id } = req.params;
    
    // Get members
    const membersSnapshot = await admin.firestore()
      .collection('household_members')
      .where('householdId', '==', id)
      .where('isActive', '==', true)
      .get();
    
    const members = membersSnapshot.docs.map(d => d.data());
    
    const stats = {
      totalMembers: members.length,
      baptized: members.filter(m => m.baptismRecordId).length,
      confirmed: members.filter(m => m.confirmationRecordId).length,
      married: members.filter(m => m.marriageRecordId).length,
      children: members.filter(m => m.role === 'Child').length,
      adults: members.filter(m => m.role !== 'Child').length
    };
    
    res.json({
      success: true,
      stats
    });
  } catch (error) {
    console.error('Error fetching stats:', error);
    res.status(500).json({ error: 'Failed to fetch stats' });
  }
});

// ==================== SACRAMENT LINKING ====================

// Link sacrament record to member
router.post('/:householdId/members/:memberId/sacraments', async (req, res) => {
  try {
    const admin = getAdmin();
    const { memberId } = req.params;
    const { 
      baptismRecordId, 
      confirmationRecordId, 
      marriageRecordId, 
      deathRecordId 
    } = req.body;
    
    const updates = {
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    };
    
    if (baptismRecordId !== undefined) updates.baptismRecordId = baptismRecordId;
    if (confirmationRecordId !== undefined) updates.confirmationRecordId = confirmationRecordId;
    if (marriageRecordId !== undefined) updates.marriageRecordId = marriageRecordId;
    if (deathRecordId !== undefined) updates.deathRecordId = deathRecordId;
    
    await admin.firestore().collection('household_members').doc(memberId).update(updates);
    
    res.json({
      success: true,
      message: 'Sacrament record linked'
    });
  } catch (error) {
    console.error('Error linking sacrament:', error);
    res.status(500).json({ error: 'Failed to link sacrament' });
  }
});

module.exports = router;
