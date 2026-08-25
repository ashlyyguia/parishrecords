const express = require('express');
const { body, validationResult } = require('express-validator');

const { verifyFirebaseToken } = require('../middleware/auth');
const { recognizeWords } = require('../services/baptismal_ocr_service');
const { extractBaptismalRows } = require('../services/baptismal_register_layout');
const {
  sniffImageType,
  preprocessForOcr,
  MAX_INPUT_PIXELS,
} = require('../services/baptismal_image_preprocess');

const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
const ACCEPTED = new Set(['image/jpeg', 'image/png', 'image/webp']);

const STATUS_BY_CODE = {
  IMAGE_INVALID: 400,
  IMAGE_TOO_LARGE: 413,
  OCR_AUTH: 500,
  OCR_QUOTA: 429,
  OCR_UNAVAILABLE: 502,
  NO_TEXT_FOUND: 422,
  LAYOUT_UNRECOGNIZED: 422,
  INTERNAL_ERROR: 500,
};

const MESSAGE_BY_CODE = {
  IMAGE_INVALID: 'That file is not a supported image. Use JPEG, PNG, or WebP.',
  // Covers both trigger paths for this code: the 10MB byte cap AND the
  // decode-time resolution cap (MAX_INPUT_PIXELS) -- the latter can be
  // tripped by a photo that is nowhere near 10MB, so the message must not
  // claim it's specifically about file size.
  IMAGE_TOO_LARGE: 'That image is too large to process (either the file size or its resolution is over the limit). Please use a smaller or lower-resolution photo.',
  OCR_AUTH: 'OCR is not configured on the server. Contact an administrator.',
  OCR_QUOTA: 'The OCR service is rate-limited right now. Try again shortly.',
  OCR_UNAVAILABLE: 'Could not reach the OCR service. Check your connection and retry.',
  NO_TEXT_FOUND: 'No readable text was found. Retake the photo with better lighting and framing.',
  LAYOUT_UNRECOGNIZED: 'This page does not look like a baptismal register. Check the photo and retry.',
  INTERNAL_ERROR: 'Something went wrong while processing this scan. Try again, and contact an administrator if it persists.',
};

// Logged once per process (not per request) so a broken sharp install
// doesn't flood the logs while the decodability gate silently degrades.
let sharpUnavailableWarnedInRoute = false;

// `scanId` is client-supplied and only validated as a non-empty string
// (express-validator's `.isString().trim().notEmpty()` has no length or
// character bound), inside a request body allowed up to 20MB. Logging it
// unbounded is both a log-injection vector (embedded CR/LF can forge fake
// log lines) and an easy way to blow up log storage with a single
// oversized field. This never affects behaviour -- only what reaches the
// log -- so a caller can never observe the truncation/stripping.
const MAX_LOGGED_SCAN_ID_LENGTH = 64;
function sanitizeScanIdForLog(scanId) {
  const s = typeof scanId === 'string' ? scanId : String(scanId);
  return s.replace(/[\r\n]+/g, ' ').slice(0, MAX_LOGGED_SCAN_ID_LENGTH);
}

// The exact message sharp/libvips throws from `metadata()` when a header's
// declared width*height exceeds `limitInputPixels` -- distinct from every
// other decode failure (corrupt header, premature EOF, wrong format).
// Verified against the installed sharp version; see
// `baptismal_image_preprocess.test.js` for the harness that would catch a
// message change on a sharp upgrade.
const PIXEL_LIMIT_ERROR_MESSAGE = 'Input image exceeds pixel limit';

/**
 * Cheap, real decodability probe run BEFORE `preprocessForOcr`/Vision.
 *
 * `sniffImageType` only checks magic bytes, so a magic-valid-but-garbage
 * buffer (e.g. a bare `FF D8 FF` stub, or `FF D8 FF FF FF FF`) would
 * otherwise sail through and burn a paid Vision call before failing later.
 * `preprocessForOcr` can't be used as that signal either: it swallows its
 * own decode errors and returns the original buffer unchanged, so a
 * successful call there proves nothing about decodability.
 *
 * This calls `sharp(buffer).metadata()`, which parses just the image header
 * (no full pixel decode) -- cheap enough to run on every upload before
 * Vision is ever touched. `limitInputPixels` is passed through so a header
 * declaring an enormous width/height (a decompression-bomb style payload)
 * is rejected here rather than only being caught later inside
 * `preprocessForOcr`.
 *
 * If the `sharp` native module itself is unavailable in this environment,
 * the probe can't run at all; rather than hard-failing every upload because
 * of a broken deploy, this degrades the same way `preprocessForOcr` does --
 * warn once and let the buffer through unprobed.
 *
 * @returns {Promise<{decodable: boolean, tooLarge: boolean}>} `tooLarge` is
 *   only ever true when `decodable` is false -- it distinguishes "this is a
 *   real image, just bigger than our resolution cap" (IMAGE_TOO_LARGE, a
 *   true and actionable message: retake at a lower resolution) from every
 *   other decode failure (IMAGE_INVALID: not a supported image at all). An
 *   ordinary phone photo from a 50 MP sensor is a real, valid, well under
 *   10 MB JPEG that used to hit this exact branch and be told -- falsely --
 *   that its FORMAT wasn't supported.
 */
async function isDecodableImage(buffer) {
  let sharp;
  try {
    sharp = require('sharp');
  } catch (e) {
    if (!sharpUnavailableWarnedInRoute) {
      console.error('[baptismal-ocr] sharp unavailable, skipping decodability probe: ' + (e?.message));
      sharpUnavailableWarnedInRoute = true;
    }
    return { decodable: true, tooLarge: false };
  }
  try {
    const meta = await sharp(buffer, { limitInputPixels: MAX_INPUT_PIXELS }).metadata();
    return { decodable: Boolean(meta && meta.width > 0 && meta.height > 0), tooLarge: false };
  } catch (e) {
    // Every OTHER decode failure (corrupt header, premature EOF, wrong
    // format, etc.) means "not decodable" for reasons unrelated to size --
    // the specific reason doesn't change the outcome there, so it stays
    // uninspected (see fail()'s single generic log line) except for this
    // one pixel-limit case, which gets its own, honest error code.
    const tooLarge = Boolean(e && e.message && e.message.includes(PIXEL_LIMIT_ERROR_MESSAGE));
    return { decodable: false, tooLarge };
  }
}

function requireStaffOrAdmin(req, res, next) {
  const role = req.user && req.user.role;
  const isAdmin = (req.user && req.user.admin === true) || role === 'admin';
  if (isAdmin || role === 'staff') return next();
  return res.status(403).json({ success: false, message: 'Staff or admin role required' });
}

function createBaptismalOcrRouter(deps = {}) {
  const recognize = deps.recognize || recognizeWords;
  const extract = deps.extract || extractBaptismalRows;
  const preprocess = deps.preprocess || preprocessForOcr;
  const verifyToken = deps.verifyToken || verifyFirebaseToken;

  const router = express.Router();

  // Base64 inflates a 10MB image to ~13.4MB, over the app-wide 10mb limit.
  // This router is mounted BEFORE the global parser in server.js so this
  // limit is the one that applies -- see the mount step in server.js.
  router.use(express.json({ limit: '20mb' }));

  router.post(
    '/scan',
    verifyToken,
    requireStaffOrAdmin,
    [body('scanId').isString().trim().notEmpty(), body('imageBase64').isString().notEmpty()],
    async (req, res) => {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({
          success: false,
          message: 'scanId and imageBase64 are required',
          code: 'IMAGE_INVALID',
        });
      }

      const { scanId } = req.body;
      const startedAt = Date.now();

      let buffer;
      try {
        buffer = Buffer.from(req.body.imageBase64, 'base64');
      } catch (e) {
        return fail(res, 'IMAGE_INVALID', scanId);
      }

      // Node's base64 decoder never throws on malformed input -- it silently
      // drops characters outside the alphabet -- so a bogus imageBase64
      // string (or one that decodes to nothing) surfaces here as an empty or
      // near-empty buffer rather than a caught exception. The checks below
      // (size, magic bytes, decodability) catch it regardless of how it got
      // here.
      if (buffer.length === 0) return fail(res, 'IMAGE_INVALID', scanId);

      if (buffer.length > MAX_IMAGE_BYTES) return fail(res, 'IMAGE_TOO_LARGE', scanId);

      const mime = sniffImageType(buffer);
      if (!mime || !ACCEPTED.has(mime)) return fail(res, 'IMAGE_INVALID', scanId);

      const decodability = await isDecodableImage(buffer);
      if (!decodability.decodable) {
        // A pixel-limit rejection is a real, valid, well-under-10MB image --
        // e.g. an 8000x6000 (48MP) phone photo at 281KB, from the 50MP
        // sensors standard on the mid-range phones this app's picker targets
        // (`fullResolution: true`). Telling that user "not a supported
        // image, use JPEG/PNG/WebP" is simply false: the format is fine, the
        // RESOLUTION is what tripped the cap. IMAGE_TOO_LARGE (with its
        // resolution-aware message below) is the honest code for this case;
        // every other decode failure is a genuine format/corruption problem
        // and stays IMAGE_INVALID.
        return fail(res, decodability.tooLarge ? 'IMAGE_TOO_LARGE' : 'IMAGE_INVALID', scanId);
      }

      try {
        const prepared = await preprocess(buffer);
        const { words } = await recognize(prepared);
        const result = extract(words);

        // Log counts only -- never cell values or recognized text (records
        // of minors).
        console.log(
          `[baptismal-ocr] scan=${sanitizeScanIdForLog(scanId)} words=${words.length} rows=${result.rows.length} ` +
          `rotation=${result.rotation} warnings=${result.warnings.length} ms=${Date.now() - startedAt}`,
        );

        // `columns`/`gutterX` are deliberately NOT included: nothing reads
        // them (`BaptismalOcrScan.fromJson` on the Flutter side ignores both
        // -- see lib/models/baptismal_register_row.dart), and they're in a
        // normalized CONTENT-RELATIVE coordinate frame (see
        // normalizeOrientation's doc comment in baptismal_register_layout.js)
        // that isn't even usable for an image overlay without extra
        // bookkeeping this pipeline doesn't do. Serializing them on every
        // response is pure dead weight.
        return res.json({
          success: true,
          data: {
            scanId,
            rows: result.rows,
            rotation: result.rotation,
            // OCR.space returns no per-word confidence, so the per-field
            // low-confidence flag can't fire. Signal the review UI to show a
            // scan-level "verify every field" banner instead.
            warnings: [...result.warnings, 'CONFIDENCE_UNAVAILABLE'],
          },
        });
      } catch (e) {
        // An error with a recognized .code (OCR_*, NO_TEXT_FOUND,
        // LAYOUT_UNRECOGNIZED, ...) is mapped to its specific status. An
        // uncoded error is an internal bug (e.g. in extractBaptismalRows),
        // not an OCR-availability problem -- defaulting it to
        // OCR_UNAVAILABLE would misdirect debugging, so it maps to
        // INTERNAL_ERROR/500 instead. Never include e.message in the
        // response body (no-leak property).
        const code = e && STATUS_BY_CODE[e.code] ? e.code : 'INTERNAL_ERROR';
        return fail(res, code, scanId);
      }
    },
  );

  return router;
}

function fail(res, code, scanId) {
  console.warn(`[baptismal-ocr] scan=${sanitizeScanIdForLog(scanId)} failed code=${code}`);
  return res.status(STATUS_BY_CODE[code] || 500).json({
    success: false,
    code,
    message: MESSAGE_BY_CODE[code] || 'OCR failed.',
  });
}

module.exports = { createBaptismalOcrRouter, router: createBaptismalOcrRouter() };
