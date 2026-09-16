/**
 * HEIC/HEIF -> JPEG normalization.
 *
 * iPhones save photos as HEIC by default. The rest of the OCR pipeline only
 * decodes JPEG/PNG/WebP (magic-byte gate in baptismal_image_preprocess.js,
 * and the Python CV grid service), so a HEIC upload must be transcoded to
 * JPEG once, at the top of each OCR route, before any of that runs.
 *
 * `heic-convert` (pure-JS libheif/WASM) is used deliberately instead of
 * sharp: sharp's prebuilt binaries do not guarantee HEVC/HEIC *decode* on
 * every platform (notably Windows dev machines), and this must behave
 * identically in dev and on the Linux host.
 */

// ISO-BMFF `ftyp` major brands that mean HEIF/HEIC still-image content.
// (AVIF is intentionally excluded — different codec, not what iPhones emit.)
const HEIF_BRANDS = new Set([
  'heic', 'heix', 'heim', 'heis', 'hevc', 'hevx', 'mif1', 'msf1', 'heif',
]);

/**
 * True only when the buffer is a HEIF/HEIC image, sniffed by its `ftyp` box.
 * Never trusts a declared mime/extension.
 */
function isHeic(buffer) {
  if (!Buffer.isBuffer(buffer) || buffer.length < 12) return false;
  if (buffer.toString('latin1', 4, 8) !== 'ftyp') return false;
  return HEIF_BRANDS.has(buffer.toString('latin1', 8, 12));
}

/**
 * Decodes HEIC bytes and re-encodes as JPEG. Throws (rejects) on undecodable
 * input so the caller can map the failure to a real "unsupported image"
 * error rather than silently passing HEIC downstream.
 */
async function heicToJpeg(buffer) {
  const convert = require('heic-convert');
  const out = await convert({ buffer, format: 'JPEG', quality: 0.92 });
  return Buffer.from(out);
}

module.exports = { isHeic, heicToJpeg, HEIF_BRANDS };
