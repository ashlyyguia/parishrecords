#!/usr/bin/env node
/**
 * Records real Cloud Vision responses for the sample register photos, so the
 * layout tests can run offline against genuine OCR output.
 *
 * Usage (from the repo root, with credentials in the environment):
 *   node backend/scripts/record_vision_fixture.js
 *
 * Writes backend/test/fixtures/vision-<name>.json — the normalized word list,
 * NOT the raw Vision payload, to keep the fixtures small and stable.
 */

const fs = require('fs');
const path = require('path');

const { recognizeWords } = require('../src/services/baptismal_ocr_service');
const { preprocessForOcr } = require('../src/services/baptismal_image_preprocess');

const ATTACHMENTS = path.join(__dirname, '..', '..', 'attachments');
const OUT_DIR = path.join(__dirname, '..', 'test', 'fixtures');

// Thrown errors already embed their code as a "CODE: message" prefix
// (see baptismal_ocr_service.js's codedError helper and Node's own fs
// errors, e.g. ENOENT). Only prepend the code again if it isn't already
// there, so we don't print it twice.
function describeError(e) {
  if (e.code && e.message.startsWith(`${e.code}:`)) return e.message;
  return `${e.code || 'ERROR'}: ${e.message}`;
}

async function main() {
  if (!process.env.GOOGLE_CLOUD_VISION_CREDENTIALS_JSON &&
      !process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
    console.error(
      'No Vision credentials in the environment. Set ' +
      'GOOGLE_CLOUD_VISION_CREDENTIALS_JSON (or FIREBASE_SERVICE_ACCOUNT_JSON) ' +
      'and make sure the Vision API is enabled on that project.',
    );
    process.exit(1);
  }

  fs.mkdirSync(OUT_DIR, { recursive: true });

  const files = fs.readdirSync(ATTACHMENTS).filter((f) => /\.(jpe?g|png|webp)$/i.test(f));
  if (files.length === 0) {
    console.error(`No images found in ${ATTACHMENTS}`);
    process.exit(1);
  }

  let succeeded = 0;
  let failed = 0;

  for (const file of files) {
    try {
      const buffer = fs.readFileSync(path.join(ATTACHMENTS, file));
      const prepared = await preprocessForOcr(buffer);
      const { words } = await recognizeWords(prepared);
      const name = path.basename(file).replace(/\.[^.]+$/, '').toLowerCase();
      const out = path.join(OUT_DIR, `vision-${name}.json`);
      fs.writeFileSync(out, JSON.stringify({ words }, null, 2));
      console.log(`${file}: ${words.length} words -> ${path.relative(process.cwd(), out)}`);
      succeeded += 1;
    } catch (e) {
      console.error(`${file}: FAILED (${describeError(e)})`);
      failed += 1;
    }
  }

  console.log(`\nDone: ${succeeded} succeeded, ${failed} failed.`);
  if (failed > 0) {
    process.exitCode = 1;
  }
}

main().catch((e) => {
  console.error(`Failed: ${describeError(e)}`);
  process.exit(1);
});
