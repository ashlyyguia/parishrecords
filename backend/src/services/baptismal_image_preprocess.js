/**
 * Image validation and OCR pre-processing.
 *
 * Preprocessing operates on a COPY. The original upload is what gets archived
 * to Storage and must never be mutated here.
 */

const MAX_EDGE = 4096;

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
    return buffer;
  }
  try {
    return await sharp(buffer)
      .rotate() // honour EXIF orientation
      .resize({ width: MAX_EDGE, height: MAX_EDGE, fit: 'inside', withoutEnlargement: true })
      .grayscale()
      .normalize()
      .sharpen()
      .jpeg({ quality: 92 })
      .toBuffer();
  } catch (e) {
    return buffer;
  }
}

module.exports = { sniffImageType, preprocessForOcr, MAX_EDGE };
