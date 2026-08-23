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

  for (const file of files) {
    const buffer = fs.readFileSync(path.join(ATTACHMENTS, file));
    const prepared = await preprocessForOcr(buffer);
    const { words } = await recognizeWords(prepared);
    const name = path.basename(file).replace(/\.[^.]+$/, '').toLowerCase();
    const out = path.join(OUT_DIR, `vision-${name}.json`);
    fs.writeFileSync(out, JSON.stringify({ words }, null, 2));
    console.log(`${file}: ${words.length} words -> ${path.relative(process.cwd(), out)}`);
  }
}

main().catch((e) => {
  console.error(`Failed (${e.code || 'ERROR'}): ${e.message}`);
  process.exit(1);
});
