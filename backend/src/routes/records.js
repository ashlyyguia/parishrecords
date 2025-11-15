const express = require('express');
const { v4: uuidv4 } = require('uuid');
const cassandraClient = require('../database/cassandra');

const router = express.Router();

// Get all records
router.get('/', async (req, res) => {
  try {
    const { limit = 50, type } = req.query;
    
    let query = 'SELECT * FROM records';
    let params = [];
    
    if (type) {
      query += ' WHERE type = ? ALLOW FILTERING';
      params.push(type);
    }
    
    query += ` LIMIT ${parseInt(limit)}`;
    
    const result = await cassandraClient.execute(query, params);
    
    res.json({
      records: result.rows,
      count: result.rows.length
    });

  } catch (error) {
    console.error('Get records error:', error);
    res.status(500).json({ error: 'Failed to fetch records' });
  }
});

// Get record by ID
router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    
    const result = await cassandraClient.execute(
      'SELECT * FROM records WHERE id = ?',
      [id]
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Record not found' });
    }
    
    res.json(result.rows[0]);

  } catch (error) {
    console.error('Get record error:', error);
    res.status(500).json({ error: 'Failed to fetch record' });
  }
});

// Create new record
router.post('/', async (req, res) => {
  try {
    const {
      type,
      name,
      dateOfEvent,
      placeOfEvent,
      notes,
      certificateStatus = 'pending'
    } = req.body;

    const recordId = uuidv4();
    const now = new Date();

    // Insert into main records table
    await cassandraClient.execute(
      'INSERT INTO records (id, type, name, date_of_event, place_of_event, notes, certificate_status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [recordId, type, name, dateOfEvent, placeOfEvent, notes, certificateStatus, now, now]
    );

    // Insert into specific record type table based on type
    if (type === 'baptism' && req.body.baptismData) {
      await insertBaptismRecord(recordId, req.body.baptismData);
    } else if (type === 'marriage' && req.body.marriageData) {
      await insertMarriageRecord(recordId, req.body.marriageData);
    } else if (type === 'confirmation' && req.body.confirmationData) {
      await insertConfirmationRecord(recordId, req.body.confirmationData);
    } else if (type === 'death' && req.body.deathData) {
      await insertDeathRecord(recordId, req.body.deathData);
    }

    res.status(201).json({
      message: 'Record created successfully',
      recordId
    });

  } catch (error) {
    console.error('Create record error:', error);
    res.status(500).json({ error: 'Failed to create record' });
  }
});

// Update record
router.put('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { name, dateOfEvent, placeOfEvent, notes, certificateStatus } = req.body;

    await cassandraClient.execute(
      'UPDATE records SET name = ?, date_of_event = ?, place_of_event = ?, notes = ?, certificate_status = ?, updated_at = ? WHERE id = ?',
      [name, dateOfEvent, placeOfEvent, notes, certificateStatus, new Date(), id]
    );

    res.json({ message: 'Record updated successfully' });

  } catch (error) {
    console.error('Update record error:', error);
    res.status(500).json({ error: 'Failed to update record' });
  }
});

// Delete record
router.delete('/:id', async (req, res) => {
  try {
    const { id } = req.params;

    await cassandraClient.execute(
      'DELETE FROM records WHERE id = ?',
      [id]
    );

    res.json({ message: 'Record deleted successfully' });

  } catch (error) {
    console.error('Delete record error:', error);
    res.status(500).json({ error: 'Failed to delete record' });
  }
});

// Get baptism records
router.get('/baptism/all', async (req, res) => {
  try {
    const result = await cassandraClient.execute('SELECT * FROM baptism_records LIMIT 100');
    res.json(result.rows);
  } catch (error) {
    console.error('Get baptism records error:', error);
    res.status(500).json({ error: 'Failed to fetch baptism records' });
  }
});

// Helper functions for specific record types
async function insertBaptismRecord(recordId, data) {
  const {
    registryNo, bookNo, pageNo, lineNo, childName, childGender,
    dateOfBirth, placeOfBirth, fatherName, motherName,
    godfatherName, godmotherName, ministerName, dateOfBaptism,
    placeOfBaptism, certificateIssued = false
  } = data;

  await cassandraClient.execute(
    `INSERT INTO baptism_records 
     (id, registry_no, book_no, page_no, line_no, child_name, child_gender, 
      date_of_birth, place_of_birth, father_name, mother_name, 
      godfather_name, godmother_name, minister_name, date_of_baptism, 
      place_of_baptism, certificate_issued, created_at) 
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [recordId, registryNo, bookNo, pageNo, lineNo, childName, childGender,
     dateOfBirth, placeOfBirth, fatherName, motherName,
     godfatherName, godmotherName, ministerName, dateOfBaptism,
     placeOfBaptism, certificateIssued, new Date()]
  );
}

async function insertMarriageRecord(recordId, data) {
  const {
    registryNo, groomName, brideName, dateOfMarriage, placeOfMarriage,
    witness1Name, witness2Name, ministerName, certificateIssued = false
  } = data;

  await cassandraClient.execute(
    `INSERT INTO marriage_records 
     (id, registry_no, groom_name, bride_name, date_of_marriage, 
      place_of_marriage, witness1_name, witness2_name, minister_name, 
      certificate_issued, created_at) 
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [recordId, registryNo, groomName, brideName, dateOfMarriage,
     placeOfMarriage, witness1Name, witness2Name, ministerName,
     certificateIssued, new Date()]
  );
}

async function insertConfirmationRecord(recordId, data) {
  const {
    registryNo, confirmedName, dateOfConfirmation, placeOfConfirmation,
    sponsorName, ministerName, certificateIssued = false
  } = data;

  await cassandraClient.execute(
    `INSERT INTO confirmation_records 
     (id, registry_no, confirmed_name, date_of_confirmation, 
      place_of_confirmation, sponsor_name, minister_name, 
      certificate_issued, created_at) 
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [recordId, registryNo, confirmedName, dateOfConfirmation,
     placeOfConfirmation, sponsorName, ministerName,
     certificateIssued, new Date()]
  );
}

async function insertDeathRecord(recordId, data) {
  const {
    registryNo, deceasedName, dateOfDeath, placeOfDeath, causeOfDeath,
    ageAtDeath, burialDate, burialPlace, certificateIssued = false
  } = data;

  await cassandraClient.execute(
    `INSERT INTO death_records 
     (id, registry_no, deceased_name, date_of_death, place_of_death, 
      cause_of_death, age_at_death, burial_date, burial_place, 
      certificate_issued, created_at) 
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [recordId, registryNo, deceasedName, dateOfDeath, placeOfDeath,
     causeOfDeath, ageAtDeath, burialDate, burialPlace,
     certificateIssued, new Date()]
  );
}

module.exports = router;
