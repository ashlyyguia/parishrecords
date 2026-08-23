/**
 * Image validation and OCR pre-processing.
 *
 * Preprocessing operates on a COPY. The original upload is what gets archived
 * to Storage and must never be mutated here.
 */

const MAX_EDGE = 4096;

/**
 * Explicit decode-time pixel ceiling passed to sharp's `limitInputPixels`.
 *
 * MAX_EDGE only bounds the resize OUTPUT — sharp(buffer) fully decodes the
 * source first, and libvips' shrink-on-load only gives partial protection
 * for JPEG/WebP and none for PNG. Without an explicit cap, a small-on-disk
 * PNG that declares e.g. 50000x50000 pixels forces a full-resolution decode
 * (gigabytes of raw pixels) before we ever get to resize it down.
 *
 * 40,000,000 px (40 MP) is chosen to comfortably clear legitimate register
 * scans/photos: a two-page legal-size spread (~17in x 14in) at 600 DPI is
 * ~21.4 MP, and even a fairly aggressive 800 DPI double-page scan is well
 * under 40 MP. It sits far below sharp's own undocumented default
 * (~268 MP / 16383x16383), which is the whole point — this project should
 * not depend on a library default that could silently change. A buffer
 * that exceeds this decodes to roughly 40M * 3-4 bytes/px (~120-160 MB) at
 * most before sharp aborts, which is a bounded and acceptable worst case.
 */
const MAX_INPUT_PIXELS = 40_000_000;

// Ensures the "sharp is unavailable" condition is logged once per process
// rather than once per request, so a broken deploy (missing native binary)
// doesn't flood the logs while every upload silently degrades.
let sharpUnavailableWarned = false;

/**
 * Logs a preprocessing failure without ever including image bytes, pixel
 * dimensions, or anything else derived from the image content — these are
 * records of minors and must not be logged.
 */
function logPreprocessFailure(stage, error) {
  const message = error?.message ? error.message : String(error);
  console.error(`[baptismal_image_preprocess] sharp ${stage} failed, falling back to unprocessed image for OCR: ${message}`);
}

/**
 * Identifies an image by magic bytes. Never trust the client's declared mime.
 *
 * Each format is checked against its own minimum header length (JPEG: 3-byte
 * SOI marker, PNG: 8-byte signature, WebP: 12-byte RIFF/size/fourcc), rather
 * than a single blanket floor — a blanket 12-byte floor would reject valid
 * short JPEG/PNG headers.
 */
function sniffImageType(buffer) {
  if (!Buffer.isBuffer(buffer) || buffer.length < 3) return null;
  if (buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) return 'image/jpeg';
  if (
    buffer.length >= 8 &&
    buffer[0] === 0x89 && buffer[1] === 0x50 && buffer[2] === 0x4e && buffer[3] === 0x47 &&
    buffer[4] === 0x0d && buffer[5] === 0x0a && buffer[6] === 0x1a && buffer[7] === 0x0a
  ) return 'image/png';
  if (
    buffer.length >= 12 &&
    buffer.slice(0, 4).toString() === 'RIFF' && buffer.slice(8, 12).toString() === 'WEBP'
  ) {
    return 'image/webp';
  }
  return null;
}

/**
 * Enhances contrast and sharpness to help Vision read cramped ballpoint
 * handwriting. Returns the ORIGINAL buffer unchanged if sharp is unavailable
 * or fails — degraded accuracy beats a broken feature.
 */
async function preprocessForOcr(buffer) {
  let sharp;
  try {
    sharp = require('sharp');
  } catch (e) {
    if (!sharpUnavailableWarned) {
      logPreprocessFailure('require', e);
      sharpUnavailableWarned = true;
    }
    return buffer;
  }
  try {
    return await sharp(buffer, { limitInputPixels: MAX_INPUT_PIXELS })
      .rotate() // honour EXIF orientation
      .resize({ width: MAX_EDGE, height: MAX_EDGE, fit: 'inside', withoutEnlargement: true })
      .grayscale()
      .normalize()
      .sharpen()
      .jpeg({ quality: 92 })
      .toBuffer();
  } catch (e) {
    logPreprocessFailure('pipeline', e);
    return buffer;
  }
}

module.exports = { sniffImageType, preprocessForOcr, MAX_EDGE, MAX_INPUT_PIXELS };
