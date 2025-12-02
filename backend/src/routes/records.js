const express = require('express');
const { v4: uuidv4 } = require('uuid');
const cassandraClient = require('../database/cassandra');
const { logAudit } = require('../utils/audit');

const router = express.Router();

// Best-effort schema migration: ensure records_by_type has a notes TEXT column
let notesColumnEnsured = false;
async function ensureRecordsByTypeNotesColumn() {
  // Schema already includes the notes column in records_by_type in this deployment,
  // so we avoid running ALTER TABLE at runtime. Just mark as ensured.
  if (notesColumnEnsured) return;
  notesColumnEnsured = true;
}

// Get all records (backed by records_by_type + per-type tables)
router.get('/', async (req, res) => {
  try {
    await ensureRecordsByTypeNotesColumn();
    const { limit = 50, type } = req.query;

    let query =
      'SELECT type, parish_id, id, name, date, place, certificate_status, created_at, notes FROM records_by_type';
    const params = [];

    if (type) {
      query += ' WHERE type = ?';
      params.push(type.toString());
    }

    query += ` LIMIT ${parseInt(limit, 10)}`;

    const result = await cassandraClient.execute(query, params);

    const rows = await Promise.all(
      result.rows.map(async (r) => {
        let notes = r.notes || null;

        // For legacy records that never had notes stored in records_by_type,
        // rebuild a best-effort notes JSON from the sacrament tables so the
        // Flutter detail screen can show full information.
        if (!notes) {
          try {
            const built = await buildNotesFromPerTypeSummary(r);
            if (built) {
              notes = JSON.stringify(built);
              // Best-effort persist back to records_by_type for future calls
              try {
                await cassandraClient.execute(
                  'UPDATE records_by_type SET notes = ? WHERE type = ? AND created_at = ? AND id = ?',
                  [
                    notes,
                    r.type,
                    r.created_at || r.date,
                    r.id,
                  ],
                );
              } catch (persistErr) {
                console.error('Warning: failed to persist backfilled notes', persistErr);
              }
            }
          } catch (rebuildErr) {
            console.error('Warning: failed to rebuild notes from per-type tables', rebuildErr);
          }
        }

        return {
          id: r.id ? r.id.toString() : undefined,
          type: r.type,
          // Flutter expects a `text` field for the record title
          text: r.name,
          image_ref: null,
          // Treat parish_id as the logical source/parish identifier
          source: r.parish_id || null,
          // Rich JSON notes are stored in records_by_type.notes
          notes: notes,
          created_at: r.created_at || r.date || new Date(),
          certificate_status: r.certificate_status || null,
        };
      }),
    );

    res.json({
      rows,
      records: rows,
      count: rows.length,
    });
  } catch (error) {
    console.error('Get records error:', error);
    res.status(500).json({ error: 'Failed to fetch records' });
  }
});

// Public-style verification endpoint used by QR codes
// Returns a minimal payload suitable for checking that a certificate
// or record reference is valid.
router.get('/verify/:id', async (req, res) => {
  try {
    const { id } = req.params;

    const result = await cassandraClient.execute(
      'SELECT type, parish_id, name, date, place, certificate_status, created_at FROM records_by_type WHERE id = ? ALLOW FILTERING',
      [id],
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        valid: false,
        error: 'Record not found',
      });
    }

    const row = result.rows[0];
    const type = (row.type || 'baptism').toString();
    const parishId = (row.parish_id || 'default_parish').toString();
    const status = (row.certificate_status || 'pending').toString();

    return res.json({
      valid: true,
      id: id.toString(),
      type,
      name: row.name || 'Unnamed Record',
      parish: parishId,
      date: row.date || null,
      place: row.place || null,
      certificate_status: status,
      created_at: row.created_at || null,
    });
  } catch (error) {
    console.error('Verify record error:', error);
    return res.status(500).json({
      valid: false,
      error: 'Failed to verify record',
    });
  }
});

// Get record by ID (backed by records_by_type + per-type tables)
router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;

    // Look up basic metadata (type + parish) from records_by_type
    const metaResult = await cassandraClient.execute(
      'SELECT type, parish_id, name, date, place, certificate_status, created_at FROM records_by_type WHERE id = ? ALLOW FILTERING',
      [id]
    );

    if (metaResult.rows.length === 0) {
      return res.status(404).json({ error: 'Record not found' });
    }

    const meta = metaResult.rows[0];
    const type = (meta.type || 'baptism').toString();
    const parishId = (meta.parish_id || 'default_parish').toString();

    let detailRow = null;

    if (type === 'baptism') {
      const r = await cassandraClient.execute(
        'SELECT * FROM baptism_records WHERE parish_id = ? AND id = ?',
        [parishId, id]
      );
      if (r.rows.length > 0) detailRow = r.rows[0];
    } else if (type === 'marriage') {
      const r = await cassandraClient.execute(
        'SELECT * FROM marriage_records WHERE parish_id = ? AND id = ?',
        [parishId, id]
      );
      if (r.rows.length > 0) detailRow = r.rows[0];
    } else if (type === 'confirmation') {
      const r = await cassandraClient.execute(
        'SELECT * FROM confirmation_records WHERE parish_id = ? AND id = ?',
        [parishId, id]
      );
      if (r.rows.length > 0) detailRow = r.rows[0];
    } else if (type === 'death' || type === 'funeral') {
      const r = await cassandraClient.execute(
        'SELECT * FROM death_records WHERE parish_id = ? AND id = ?',
        [parishId, id]
      );
      if (r.rows.length > 0) detailRow = r.rows[0];
    }

    if (!detailRow) {
      return res.status(404).json({ error: 'Record details not found' });
    }

    const name = detailRow.name || meta.name || 'Unnamed Record';
    // Detailed JSON notes now live only in the client payload / metadata,
    // not as a dedicated column in the per-type tables.
    const notes = null;

    const response = {
      id,
      type,
      name,
      notes,
      date: meta.date || detailRow.date || null,
      parish: parishId,
      place: meta.place || detailRow.place || null,
      certificate_status: meta.certificate_status || null,
      created_at: meta.created_at || null,
    };

    // Audit: Sacrament record viewed
    let action;
    if (type === 'baptism') action = 'Baptism Record Viewed';
    else if (type === 'marriage') action = 'Marriage Record Viewed';
    else if (type === 'confirmation') action = 'Confirmation Record Viewed';
    else if (type === 'death' || type === 'funeral') action = 'Funeral Record Viewed';
    else action = 'Sacrament Record Viewed';

    await logAudit(req, {
      action,
      resourceType: `${type}_record`,
      resourceId: id,
      newValues: { name },
    });

    res.json(response);
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
      text,
      source,
      image_ref,
      certificateStatus = 'pending',
      notes,
    } = req.body;

    // Prefer a recordId provided by the client from the notes JSON
    // (supports both legacy `metadata.recordId` and current `meta.recordId`).
    let recordId = null;
    let parsedNotes = null;
    if (notes) {
      try {
        parsedNotes = JSON.parse(notes.toString());
        if (parsedNotes) {
          if (parsedNotes.metadata && parsedNotes.metadata.recordId) {
            recordId = parsedNotes.metadata.recordId.toString();
          } else if (parsedNotes.meta && parsedNotes.meta.recordId) {
            recordId = parsedNotes.meta.recordId.toString();
          }
        }
      } catch (_) {
        // ignore JSON parse errors, we'll generate an ID below
      }
    }
    if (!recordId) {
      recordId = uuidv4();
    }
    const now = new Date();

    // Normalize parish identifier (used as partition key in *_records tables)
    const parishId = (source || 'default').toString();

    const recordType = (type || 'baptism').toString();
    const recordName = (text || 'Unnamed Record').toString();
    const recordNotes = notes ? notes.toString() : null;

    // Insert into specific record type table based on normalized recordType.
    // Even if the frontend does not send separate *Data payloads, we can
    // derive most fields from the rich notes JSON created by the Flutter forms.
    const baptismData = req.body.baptismData || (parsedNotes && parsedNotes.baptismData) || {};
    const marriageData = req.body.marriageData || (parsedNotes && parsedNotes.marriageData) || {};
    const confirmationData = req.body.confirmationData || (parsedNotes && parsedNotes.confirmationData) || {};
    const deathData = req.body.deathData || (parsedNotes && parsedNotes.deathData) || {};

    if (recordType === 'baptism') {
      await insertBaptismRecord(recordId, baptismData, parishId, recordNotes, certificateStatus);
    } else if (recordType === 'marriage') {
      await insertMarriageRecord(recordId, marriageData, parishId, recordNotes, certificateStatus);
    } else if (recordType === 'confirmation') {
      await insertConfirmationRecord(recordId, confirmationData, parishId, recordNotes, certificateStatus);
    } else if (recordType === 'death' || recordType === 'funeral') {
      await insertDeathRecord(recordId, deathData, parishId, recordNotes, certificateStatus);
    }

    // Audit: Sacrament record added
    let action;
    if (recordType === 'baptism') action = 'Baptism Record Added';
    else if (recordType === 'marriage') action = 'Marriage Record Added';
    else if (recordType === 'confirmation') action = 'Confirmation Record Added';
    else if (recordType === 'death' || recordType === 'funeral') action = 'Funeral Record Added';
    else action = 'Sacrament Record Added';

    await logAudit(req, {
      action,
      resourceType: `${recordType}_record`,
      resourceId: recordId,
      newValues: { name: recordName, parishId },
    });

    res.status(201).json({
      message: 'Record created successfully',
      recordId
    });

  } catch (error) {
    console.error('Create record error:', error);
    res.status(500).json({ error: 'Failed to create record' });
  }
});

// Update record (backed by records_by_type + per-type tables)
router.put('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { type, text, certificateStatus, notes } = req.body;

    // Load existing summary to determine type and created_at
    const metaResult = await cassandraClient.execute(
      'SELECT type, parish_id, name, certificate_status, created_at FROM records_by_type WHERE id = ? ALLOW FILTERING',
      [id],
    );
    if (metaResult.rows.length === 0) {
      return res.status(404).json({ error: 'Record not found' });
    }
    const meta = metaResult.rows[0];

    const finalType = (type || meta.type || 'baptism').toString();
    const finalCertificateStatus = (
      certificateStatus || meta.certificate_status || 'pending'
    ).toString();

    // Determine final notes: now rely solely on the payload; we no longer
    // store notes JSON in the per-type tables.
    const finalNotes = notes ? notes.toString() : null;

    if (!finalNotes) {
      return res
        .status(400)
        .json({ error: 'Missing notes payload for record update' });
    }

    // Refresh the per-type sacrament table row from the final notes JSON
    await upsertPerTypeFromNotes(id, finalType, finalNotes, finalCertificateStatus);

    // Audit: Sacrament record updated
    let action;
    if (finalType === 'baptism') action = 'Baptism Record Updated';
    else if (finalType === 'marriage') action = 'Marriage Record Updated';
    else if (finalType === 'confirmation') action = 'Confirmation Record Updated';
    else if (finalType === 'death' || finalType === 'funeral')
      action = 'Funeral Record Updated';
    else action = 'Sacrament Record Updated';

    await logAudit(req, {
      action,
      resourceType: `${finalType}_record`,
      resourceId: id,
      newValues: { name: text || meta.name },
    });

    res.json({ message: 'Record updated successfully' });
  } catch (error) {
    console.error('Update record error:', error);
    res.status(500).json({ error: 'Failed to update record' });
  }
});

// Update certificate status only (records_by_type + per-type tables)
router.put('/:id/certificate-status', async (req, res) => {
  try {
    const { id } = req.params;
    const { status } = req.body;

    if (!status) {
      return res.status(400).json({ error: 'Missing status' });
    }

    const metaResult = await cassandraClient.execute(
      'SELECT type, parish_id, created_at FROM records_by_type WHERE id = ? ALLOW FILTERING',
      [id],
    );
    if (metaResult.rows.length === 0) {
      return res.status(404).json({ error: 'Record not found' });
    }
    const meta = metaResult.rows[0];
    const type = (meta.type || 'baptism').toString();
    const parishId = (meta.parish_id || 'default_parish').toString();
    const createdAt = meta.created_at;

    const normalizedStatus = status.toString();

    // Update summary row in records_by_type
    await cassandraClient.execute(
      'UPDATE records_by_type SET certificate_status = ? WHERE type = ? AND created_at = ? AND id = ?',
      [normalizedStatus, type, createdAt, id],
    );

    // Audit: certificate status change for a record (treated as update on sacrament record)
    await logAudit(req, {
      action: 'Certificate Status Updated',
      resourceType: `${type}_record`,
      resourceId: id,
      newValues: { status: normalizedStatus },
    });

    res.json({ message: 'Certificate status updated successfully' });
  } catch (error) {
    console.error('Update certificate status error:', error);
    res.status(500).json({ error: 'Failed to update certificate status' });
  }
});

// Delete record (per-type tables + records_by_type only)
router.delete('/:id', async (req, res) => {
  try {
    const { id } = req.params;

    const metaResult = await cassandraClient.execute(
      'SELECT type, parish_id, name, created_at FROM records_by_type WHERE id = ? ALLOW FILTERING',
      [id],
    );
    if (metaResult.rows.length === 0) {
      return res.status(404).json({ error: 'Record not found' });
    }
    const meta = metaResult.rows[0];
    const recordType = (meta.type || 'baptism').toString();
    const parishId = (meta.parish_id || 'default_parish').toString();
    const createdAt = meta.created_at;
    const name = meta.name || null;

    // Delete from per-type table
    if (recordType === 'baptism') {
      await cassandraClient.execute(
        'DELETE FROM baptism_records WHERE parish_id = ? AND id = ?',
        [parishId, id],
      );
    } else if (recordType === 'marriage') {
      await cassandraClient.execute(
        'DELETE FROM marriage_records WHERE parish_id = ? AND id = ?',
        [parishId, id],
      );
    } else if (recordType === 'confirmation') {
      await cassandraClient.execute(
        'DELETE FROM confirmation_records WHERE parish_id = ? AND id = ?',
        [parishId, id],
      );
    } else if (recordType === 'death' || recordType === 'funeral') {
      await cassandraClient.execute(
        'DELETE FROM death_records WHERE parish_id = ? AND id = ?',
        [parishId, id],
      );
    }

    // Delete summary row
    await cassandraClient.execute(
      'DELETE FROM records_by_type WHERE type = ? AND created_at = ? AND id = ?',
      [recordType, createdAt, id],
    );

    // Audit: Sacrament record deleted
    let action;
    if (recordType === 'baptism') action = 'Baptism Record Deleted';
    else if (recordType === 'marriage') action = 'Marriage Record Deleted';
    else if (recordType === 'confirmation') action = 'Confirmation Record Deleted';
    else if (recordType === 'death' || recordType === 'funeral')
      action = 'Funeral Record Deleted';
    else action = 'Sacrament Record Deleted';

    await logAudit(req, {
      action,
      resourceType: `${recordType}_record`,
      resourceId: id,
      oldValues: { name },
    });

    res.json({ message: 'Record deleted successfully' });
  } catch (error) {
    console.error('Delete record error:', error);
    res.status(500).json({ error: 'Failed to delete record' });
  }
});

// Get baptism records (simple debug endpoint)
router.get('/baptism/all', async (req, res) => {
  try {
    const result = await cassandraClient.execute('SELECT * FROM baptism_records LIMIT 100');
    res.json(result.rows);
  } catch (error) {
    console.error('Get baptism records error:', error);
    res.status(500).json({ error: 'Failed to fetch baptism records' });
  }
});

// Helper to safely parse date strings
function parseDateSafe(value) {
  if (!value) return null;
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return null;
  return d;
}

// Helper functions for specific record types (aligned with revised schema)
async function insertBaptismRecord(recordId, data, parishId, recordNotes, certificateStatus) {
  const {
    registryNo, bookNo, pageNo, lineNo, childName,
    dateOfBirth, placeOfBirth, fatherName, motherName,
    godfatherName, godmotherName, ministerName, dateOfBaptism,
    placeOfBaptism, certificateIssued = false,
  } = data;

  const now = new Date();
  const recordDate = parseDateSafe(dateOfBaptism) || parseDateSafe(dateOfBirth) || now;
  const place = placeOfBaptism || placeOfBirth || null;

  await cassandraClient.execute(
    `INSERT INTO baptism_records 
     (parish_id, id, name, gender, date_of_birth, place_of_birth, father_name, mother_name, godfather_name, godmother_name, date_of_baptism, time_of_baptism, minister_name, date, place, created_at, updated_at, created_by, book_number, page_number, line_number) 
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      parishId,
      recordId,
      childName || 'Unnamed',
      data.childGender || null,
      parseDateSafe(dateOfBirth) || null,
      placeOfBirth || null,
      fatherName || null,
      motherName || null,
      godfatherName || null,
      godmotherName || null,
      parseDateSafe(dateOfBaptism) || null,
      null, // time_of_baptism (not exposed separately in backend payload yet)
      ministerName || null,
      recordDate,
      place,
      now,
      now,
      null,
      bookNo,
      pageNo,
      lineNo,
    ]
  );

  const normalizedStatus = (certificateStatus || 'pending').toString();
  await upsertRecordsByTypeSummary(
    'baptism',
    parishId,
    recordId,
    childName || 'Unnamed',
    recordDate,
    place,
    normalizedStatus,
    now,
    recordNotes,
  );
}

async function insertMarriageRecord(recordId, data, parishId, recordNotes, certificateStatus) {
  let dateOfMarriage = null;
  let placeOfMarriage = null;
  let officiantName = null;
  let groomName = null;
  let groomAgeOrDob = null;
  let groomCivilStatus = null;
  let groomReligion = null;
  let groomAddress = null;
  let brideName = null;
  let witness1Name = null;
  let witness2Name = null;
  let remarks = null;
  let registryNo = null;
  let bookNo = null;
  let pageNo = null;
  let lineNo = null;

  // Prefer full details from the notes JSON saved by the Flutter form
  if (recordNotes) {
    try {
      const decoded = JSON.parse(recordNotes);
      const marriage = decoded.marriage || {};
      const groom = decoded.groom || {};
      const bride = decoded.bride || {};
      const witnesses = decoded.witnesses || {};
      const meta = decoded.meta || {};

      dateOfMarriage = marriage.date?.toString() || null;
      placeOfMarriage = marriage.place?.toString() || null;
      officiantName = marriage.officiant?.toString() || null;

      groomName = groom.fullName?.toString() || null;
      groomAgeOrDob = groom.ageOrDob?.toString() || null;
      groomCivilStatus = groom.civilStatus?.toString() || null;
      groomReligion = groom.religion?.toString() || null;
      groomAddress = groom.address?.toString() || null;

      brideName = bride.fullName?.toString() || null;

      witness1Name = witnesses.witness1?.toString() || null;
      witness2Name = witnesses.witness2?.toString() || null;

      remarks = decoded.remarks?.toString() || null;

      registryNo = meta.registryNo?.toString() || null;
      bookNo = meta.bookNo?.toString() || null;
      pageNo = meta.pageNo?.toString() || null;
      lineNo = meta.lineNo?.toString() || null;
    } catch (_) {
      // Fallback to the compact data object below
    }
  }

  // Fallbacks from compact data payload if any field is missing
  dateOfMarriage = dateOfMarriage || data.dateOfMarriage || null;
  placeOfMarriage = placeOfMarriage || data.placeOfMarriage || null;
  groomName = groomName || data.groomName || null;
  brideName = brideName || data.brideName || null;
  witness1Name = witness1Name || data.witness1Name || null;
  witness2Name = witness2Name || data.witness2Name || null;
  registryNo = registryNo || data.registryNo || null;

  const now = new Date();
  const recordDate = parseDateSafe(dateOfMarriage) || now;
  const place = placeOfMarriage || null;
  const displayName =
    groomName && brideName
      ? `${groomName} & ${brideName}`
      : groomName || brideName || 'Marriage Record';

  const normalizedStatus = (certificateStatus || 'pending').toString();

  await cassandraClient.execute(
    `INSERT INTO marriage_records 
     (parish_id, id, groom_name, bride_name, date, time_of_marriage, place, officiant_name, groom_age_or_dob, groom_civil_status, groom_religion, groom_address, witness1_name, witness2_name, remarks, created_at, updated_at, created_by, book_number, page_number, line_number) 
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      parishId,
      recordId,
      groomName,
      brideName,
      recordDate,
      null, // time_of_marriage (UI does not capture time separately yet)
      place,
      officiantName,
      groomAgeOrDob,
      groomCivilStatus,
      groomReligion,
      groomAddress,
      witness1Name,
      witness2Name,
      remarks,
      now,
      now,
      null,
      bookNo,
      pageNo,
      lineNo,
    ]
  );

  await upsertRecordsByTypeSummary(
    'marriage',
    parishId,
    recordId,
    displayName,
    recordDate,
    place,
    normalizedStatus,
    now,
    recordNotes,
  );
}

async function insertConfirmationRecord(recordId, data, parishId, recordNotes, certificateStatus) {
  let confirmedName = null;
  let dateOfConfirmation = null;
  let placeOfConfirmation = null;
  let sponsorName = null;
  let ministerName = null;
  let ageOrDob = null;
  let placeOfBirth = null;
  let fatherName = null;
  let motherName = null;
  let address = null;
  let remarks = null;
  let registryNo = null;
  let bookNo = null;
  let pageNo = null;
  let lineNo = null;

  // Prefer rich data from the notes JSON created by ConfirmationFormScreen
  if (recordNotes) {
    try {
      const decoded = JSON.parse(recordNotes);
      const confirmand = decoded.confirmand || {};
      const parents = decoded.parents || {};
      const sponsor = decoded.sponsor || {};
      const confirmation = decoded.confirmation || {};
      const meta = decoded.meta || {};

      confirmedName = confirmand.fullName?.toString() || null;
      ageOrDob = confirmand.dateOfBirth?.toString() || null;
      placeOfBirth = confirmand.placeOfBirth?.toString() || null;
      address = confirmand.address?.toString() || null;

      fatherName = parents.father?.toString() || null;
      motherName = parents.mother?.toString() || null;

      sponsorName = sponsor.fullName?.toString() || null;

      dateOfConfirmation = confirmation.date?.toString() || null;
      placeOfConfirmation = confirmation.place?.toString() || null;
      ministerName = confirmation.officiant?.toString() || null;

      remarks = decoded.remarks?.toString() || null;

      // Registry info lives in meta
      registryNo = meta.registryNo?.toString() || null;
      bookNo = meta.bookNo?.toString() || null;
      pageNo = meta.pageNo?.toString() || null;
      lineNo = meta.lineNo?.toString() || null;
    } catch (_) {
      // Fall back to compact confirmationData object below
    }
  }

  // Fallback to compact confirmationData fields if anything is missing
  confirmedName = confirmedName || data.confirmedName || null;
  dateOfConfirmation = dateOfConfirmation || data.dateOfConfirmation || null;
  placeOfConfirmation = placeOfConfirmation || data.placeOfConfirmation || null;
  sponsorName = sponsorName || data.sponsorName || null;
  ministerName = ministerName || data.ministerName || null;
  registryNo = registryNo || data.registryNo || null;

  const now = new Date();
  const recordDate = parseDateSafe(dateOfConfirmation) || now;
  const place = placeOfConfirmation || null;
  const displayName = confirmedName || 'Confirmation Record';
  const normalizedStatus = (certificateStatus || 'pending').toString();

  await cassandraClient.execute(
    `INSERT INTO confirmation_records 
     (parish_id, id, name, age_or_dob, place_of_birth, father_name, mother_name, address, sponsor_name, date, place, minister_name, remarks, created_at, updated_at, created_by, book_number, page_number, line_number) 
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      parishId,
      recordId,
      confirmedName,
      ageOrDob,
      placeOfBirth,
      fatherName,
      motherName,
      address,
      sponsorName,
      recordDate,
      place,
      ministerName,
      remarks,
      now,
      now,
      null,
      bookNo,
      pageNo,
      lineNo,
    ]
  );

  await upsertRecordsByTypeSummary(
    'confirmation',
    parishId,
    recordId,
    displayName,
    recordDate,
    place,
    normalizedStatus,
    now,
    recordNotes,
  );
}

async function insertDeathRecord(recordId, data, parishId, recordNotes, certificateStatus) {
  let registryNo = null;
  let deceasedName = null;
  let gender = null;
  let ageOrDob = null;
  let dateOfBirth = null;
  let dateOfDeath = null;
  let placeOfDeath = null;
  let causeOfDeath = null;
  let civilStatus = null;
  let religion = null;
  let address = null;
  let fatherName = null;
  let motherName = null;
  let spouseName = null;
  let informantName = null;
  let informantRelation = null;
  let burialDate = null;
  let burialPlace = null;
  let ministerName = null;
  let bookNo = null;
  let pageNo = null;
  let lineNo = null;
  let certificateIssued = false;

  // Prefer detailed JSON saved by DeathFormScreen
  if (recordNotes) {
    try {
      const decoded = JSON.parse(recordNotes);
      const deceased = decoded.deceased || {};
      const family = decoded.family || {};
      const representative = decoded.representative || {};
      const burial = decoded.burial || {};
      const meta = decoded.meta || {};

      deceasedName = deceased.fullName?.toString() || null;
      gender = deceased.gender?.toString() || null;
      ageOrDob = deceased.age?.toString() || null;
      dateOfBirth = deceased.dateOfBirth?.toString() || null;
      dateOfDeath = deceased.dateOfDeath?.toString() || null;
      placeOfDeath = deceased.placeOfDeath?.toString() || null;
      causeOfDeath = deceased.causeOfDeath?.toString() || null;
      civilStatus = deceased.civilStatus?.toString() || null;
      address = deceased.address?.toString() || null;

      fatherName = family.father?.toString() || null;
      motherName = family.mother?.toString() || null;
      spouseName = family.spouse?.toString() || null;

      informantName = representative.name?.toString() || null;
      informantRelation = representative.relationship?.toString() || null;

      burialDate = burial.date?.toString() || null;
      burialPlace = burial.place?.toString() || null;
      ministerName = burial.officiant?.toString() || null;

      bookNo = meta.bookNo?.toString() || null;
      pageNo = meta.pageNo?.toString() || null;
      lineNo = meta.lineNo?.toString() || null;
    } catch (_) {
      // Fall back to compact deathData object below
    }
  }

  // Fallbacks from compact deathData payload if any field is missing
  registryNo = registryNo || data.registryNo || null;
  deceasedName = deceasedName || data.deceasedName || null;
  dateOfDeath = dateOfDeath || data.dateOfDeath || null;
  placeOfDeath = placeOfDeath || data.placeOfDeath || null;
  causeOfDeath = causeOfDeath || data.causeOfDeath || null;
  ageOrDob = ageOrDob || data.ageAtDeath || null;
  burialDate = burialDate || data.burialDate || null;
  burialPlace = burialPlace || data.burialPlace || null;
  if (data.certificateIssued === true) {
    certificateIssued = true;
  }

  const now = new Date();
  const recordDate = parseDateSafe(dateOfDeath) || now;
  const place = placeOfDeath || burialPlace || null;
  const displayName = deceasedName || 'Death Record';
  const normalizedStatus = (certificateStatus || 'pending').toString();

  await cassandraClient.execute(
    `INSERT INTO death_records 
     (parish_id, id, name, gender, age_or_dob, date_of_birth, date, place, place_of_death, cause_of_death, civil_status, religion, address, father_name, mother_name, spouse_name, informant_name, informant_relation, burial_date, burial_place, minister_name, created_at, updated_at, created_by, book_number, page_number, line_number) 
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      parishId,
      recordId,
      deceasedName,
      gender,
      ageOrDob,
      parseDateSafe(dateOfBirth) || null,
      recordDate,
      place,
      placeOfDeath,
      causeOfDeath,
      civilStatus,
      religion,
      address,
      fatherName,
      motherName,
      spouseName,
      informantName,
      informantRelation,
      parseDateSafe(burialDate) || null,
      burialPlace,
      ministerName,
      now,
      now,
      null,
      bookNo,
      pageNo,
      lineNo,
    ]
  );

  await upsertRecordsByTypeSummary(
    'death',
    parishId,
    recordId,
    displayName,
    recordDate,
    place,
    normalizedStatus,
    now,
    recordNotes,
  );
}

// Re-derive and upsert the per-type row from the final notes JSON when a record is edited
async function upsertPerTypeFromNotes(recordId, recordType, recordNotes, certificateStatus) {
  if (!recordNotes) {
    return;
  }

  let parsedNotes = null;
  try {
    parsedNotes = JSON.parse(recordNotes);
  } catch (_) {
    // If notes are not valid JSON, we cannot safely derive structured fields
  }

  const baptismData = parsedNotes && parsedNotes.baptismData ? parsedNotes.baptismData : {};
  const marriageData = parsedNotes && parsedNotes.marriageData ? parsedNotes.marriageData : {};
  const confirmationData = parsedNotes && parsedNotes.confirmationData ? parsedNotes.confirmationData : {};
  const deathData = parsedNotes && parsedNotes.deathData ? parsedNotes.deathData : {};

  // Try to reuse the existing parish_id from the per-type table so we don't change partition key
  let parishId = 'default_parish';
  let tableName = null;
  if (recordType === 'baptism') {
    tableName = 'baptism_records';
  } else if (recordType === 'marriage') {
    tableName = 'marriage_records';
  } else if (recordType === 'confirmation') {
    tableName = 'confirmation_records';
  } else if (recordType === 'death' || recordType === 'funeral') {
    tableName = 'death_records';
  }

  if (tableName) {
    try {
      const result = await cassandraClient.execute(
        `SELECT parish_id FROM ${tableName} WHERE id = ? ALLOW FILTERING`,
        [recordId]
      );
      if (result.rows.length > 0 && result.rows[0].parish_id) {
        parishId = result.rows[0].parish_id.toString();
      }
    } catch (err) {
      console.error('Warning: failed to load parish_id for per-type update', recordId, recordType, err);
    }
  }

  try {
    if (recordType === 'baptism') {
      await insertBaptismRecord(recordId, baptismData, parishId, recordNotes, certificateStatus);
    } else if (recordType === 'marriage') {
      await insertMarriageRecord(recordId, marriageData, parishId, recordNotes, certificateStatus);
    } else if (recordType === 'confirmation') {
      await insertConfirmationRecord(recordId, confirmationData, parishId, recordNotes, certificateStatus);
    } else if (recordType === 'death' || recordType === 'funeral') {
      await insertDeathRecord(recordId, deathData, parishId, recordNotes, certificateStatus);
    }
  } catch (err) {
    console.error('Warning: failed to upsert per-type record from notes', recordId, recordType, err);
  }
}

// Build a notes JSON object for legacy records using data from the per-type
// sacrament tables. The structure is aligned with what the Flutter forms
// produce so the detail screen can render it.
async function buildNotesFromPerTypeSummary(summaryRow) {
  const type = (summaryRow.type || '').toString();
  const parishId = (summaryRow.parish_id || 'default_parish').toString();
  const id = summaryRow.id ? summaryRow.id.toString() : null;

  if (!id || !type) return null;

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

// Shared helper: maintain a compact cross-sacrement view used by listings/admin
async function upsertRecordsByTypeSummary(
  type,
  parishId,
  recordId,
  name,
  date,
  place,
  certificateStatus,
  createdAt,
  notes,
) {
  const safeType = (type || 'unknown').toString();
  const safeParish = (parishId || 'default_parish').toString();
  const safeId = recordId ? recordId.toString() : null;
  const safeName = name || 'Unnamed Record';
  const safeStatus = (certificateStatus || 'pending').toString();
  const created = createdAt || new Date();

  if (!safeId) {
    return;
  }

  await ensureRecordsByTypeNotesColumn();
  await cassandraClient.execute(
    `INSERT INTO records_by_type (type, parish_id, id, name, date, place, certificate_status, created_at, notes)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      safeType,
      safeParish,
      safeId,
      safeName,
      date || created,
      place || null,
      safeStatus,
      created,
      notes || null,
    ],
  );
}

module.exports = router;
