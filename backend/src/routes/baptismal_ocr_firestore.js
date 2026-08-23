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
  VISION_AUTH: 500,
  VISION_QUOTA: 429,
  VISION_UNAVAILABLE: 502,
  NO_TEXT_FOUND: 422,
  LAYOUT_UNRECOGNIZED: 422,
  INTERNAL_ERROR: 500,
};

const MESSAGE_BY_CODE = {
  IMAGE_INVALID: 'That file is not a supported image. Use JPEG, PNG, or WebP.',
  IMAGE_TOO_LARGE: 'That image is larger than 10 MB. Please use a smaller photo.',
  VISION_AUTH: 'OCR is not configured on the server. Contact an administrator.',
  VISION_QUOTA: 'The OCR service is rate-limited right now. Try again shortly.',
  VISION_UNAVAILABLE: 'Could not reach the OCR service. Check your connection and retry.',
  NO_TEXT_FOUND: 'No readable text was found. Retake the photo with better lighting and framing.',
  LAYOUT_UNRECOGNIZED: 'This page does not look like a baptismal register. Check the photo and retry.',
  INTERNAL_ERROR: 'Something went wrong while processing this scan. Try again, and contact an administrator if it persists.',
};

// Logged once per process (not per request) so a broken sharp install
// doesn't flood the logs while the decodability gate silently degrades.
let sharpUnavailableWarnedInRoute = false;

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
    return true;
  }
  try {
    const meta = await sharp(buffer, { limitInputPixels: MAX_INPUT_PIXELS }).metadata();
    return Boolean(meta && meta.width > 0 && meta.height > 0);
  } catch (e) {
    // Any decode failure (corrupt header, premature EOF, oversized pixel
    // count blocked by limitInputPixels, etc.) means "not decodable" -- the
    // specific reason doesn't change the outcome, so it's intentionally not
    // inspected or logged here (see fail()'s single generic log line).
    return false;
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

      if (!(await isDecodableImage(buffer))) return fail(res, 'IMAGE_INVALID', scanId);

      try {
        const prepared = await preprocess(buffer);
        const { words } = await recognize(prepared);
        const result = extract(words);

        // Log counts only -- never cell values or recognized text (records
        // of minors).
        console.log(
          `[baptismal-ocr] scan=${scanId} words=${words.length} rows=${result.rows.length} ` +
          `rotation=${result.rotation} warnings=${result.warnings.length} ms=${Date.now() - startedAt}`,
        );

        return res.json({
          success: true,
          data: {
            scanId,
            rows: result.rows,
            columns: result.columns,
            rotation: result.rotation,
            gutterX: result.gutterX,
            warnings: result.warnings,
          },
        });
      } catch (e) {
        // An error with a recognized .code (VISION_*, NO_TEXT_FOUND,
        // LAYOUT_UNRECOGNIZED, ...) is mapped to its specific status. An
        // uncoded error is an internal bug (e.g. in extractBaptismalRows),
        // not a Vision-availability problem -- defaulting it to
        // VISION_UNAVAILABLE would misdirect debugging, so it maps to
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
  console.warn(`[baptismal-ocr] scan=${scanId} failed code=${code}`);
  return res.status(STATUS_BY_CODE[code] || 500).json({
    success: false,
    code,
    message: MESSAGE_BY_CODE[code] || 'OCR failed.',
  });
}

module.exports = { createBaptismalOcrRouter, router: createBaptismalOcrRouter() };
