/**
 * Debug helper: runs one register photo through the same CV grid + OCR.space
 * path the /ocr/baptismal/scan route uses and writes the grid cells and the
 * recognized word boxes (in the grid's frame) to a JSON file, so row/column
 * assignment can be checked offline without re-calling OCR.space.
 *
 * Usage: node backend/scripts/dump_grid_words.js <photo> <out.json> [baptismal|marriage]
 * Needs backend/.env (OCRSPACE_API_KEY, OCR_SERVICE_URL, OCR_SERVICE_KEY).
 * The output holds register contents: keep it local, never commit it.
 */
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const fs = require('fs');
const { fetchGrid } = require('../src/services/cv_grid_client');
const { preprocessForOcr, imageDimensions } = require('../src/services/baptismal_image_preprocess');
const { recognizeWords } = require('../src/services/baptismal_ocr_service');
const { rescaleWordsToGrid } = require('../src/services/ocr_word_frame');

(async () => {
  const [file, out, register = 'baptismal'] = process.argv.slice(2);
  const grid = await fetchGrid(fs.readFileSync(file), { register });
  const pages = {};
  for (const side of ['left', 'right']) {
    const page = grid.pages[side];
    const prep = await preprocessForOcr(page.imageBuffer, { maxEdge: 2500, quality: 80 });
    const { words } = await recognizeWords(prep, { detectOrientation: false });
    const dims = await imageDimensions(prep);
    const { imageBuffer, ...rest } = page;
    pages[side] = { ...rest, words: rescaleWordsToGrid(words, page, dims) };
    fs.writeFileSync(out.replace(/\.json$/, `_${side}.jpg`), imageBuffer);
  }
  fs.writeFileSync(out, JSON.stringify({ register, pages }, null, 1));
  console.log('wrote', out);
})().catch((e) => { console.error(e); process.exit(1); });
