/**
 * One-off local validation: runs the real OCR.space path on a sample register
 * image and reports STRUCTURE ONLY (counts, rotation, per-field populated
 * flags) -- never dumps recognized values, which are records of minors.
 *
 * Usage: node backend/scripts/probe_ocrspace.js attachments/IMG_3120.jpeg
 * Requires OCRSPACE_API_KEY in backend/.env (loaded via dotenv) and network.
 */
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const fs = require('fs');
const { preprocessForOcr } = require('../src/services/baptismal_image_preprocess');
const { recognizeWords } = require('../src/services/baptismal_ocr_service');
const { extractBaptismalRows } = require('../src/services/baptismal_register_layout');

(async () => {
  const file = process.argv[2] || 'attachments/IMG_3120.jpeg';
  const engine = process.argv[3] || '1';
  const raw = fs.readFileSync(file);
  const prepared = await preprocessForOcr(raw, { maxEdge: 2500, quality: 80 });
  console.log(`engine: ${engine}`);
  console.log(`prepared bytes: ${prepared.length} (base64 ~${Math.round(prepared.length * 1.34 / 1024)}KB)`);

  const { words } = await recognizeWords(prepared, { engine });
  console.log(`words with boxes: ${words.length}`); // Risk 1: must be > 0

  const result = extractBaptismalRows(words);
  console.log(`rotation detected: ${result.rotation}`); // Risk 2
  console.log(`rows detected: ${result.rows.length}`);
  console.log(`warnings: ${result.warnings.join(', ') || '(none)'}`);
  for (const row of result.rows) {
    const populated = Object.entries(row.fields)
      .filter(([, f]) => f && f.value && f.value.trim())
      .map(([k]) => k);
    console.log(`  line ${row.lineNo}: ${populated.length} fields -> ${populated.join(', ')}`);
  }
})().catch((e) => { console.error(`probe failed: ${e.code || ''} ${e.message}`); process.exit(1); });
