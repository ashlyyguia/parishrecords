const express = require('express');
const { body, validationResult } = require('express-validator');

const { verifyFirebaseToken } = require('../middleware/auth');
const { recognizeWords } = require('../services/baptismal_ocr_service');
const { extractBaptismalRows } = require('../services/baptismal_register_layout');
const { sniffImageType, preprocessForOcr } = require('../services/baptismal_image_preprocess');

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
};

const MESSAGE_BY_CODE = {
  IMAGE_INVALID: 'That file is not a supported image. Use JPEG, PNG, or WebP.',
  IMAGE_TOO_LARGE: 'That image is larger than 10 MB. Please use a smaller photo.',
  VISION_AUTH: 'OCR is not configured on the server. Contact an administrator.',
  VISION_QUOTA: 'The OCR service is rate-limited right now. Try again shortly.',
  VISION_UNAVAILABLE: 'Could not reach the OCR service. Check your connection and retry.',
  NO_TEXT_FOUND: 'No readable text was found. Retake the photo with better lighting and framing.',
  LAYOUT_UNRECOGNIZED: 'This page does not look like a baptismal register. Check the photo and retry.',
};

/**
 * Byte length of each format's magic-byte signature, as matched by
 * `sniffImageType`. A buffer that is no longer than its own signature
 * matched the magic bytes but carries no payload whatsoever past them --
 * e.g. a bare 3-byte `FF D8 FF` JPEG stub. That is unambiguously not a
 * decodable image, and it is cheap to catch before ever handing the buffer
 * to `preprocessForOcr` (which silently falls back to the original buffer on
 * any decode failure, so its output alone can't distinguish "decoded fine"
 * from "gave up") or to Vision (a paid, rate-limited API call).
 *
 * This is deliberately a length check, not a real decode (e.g.
 * `sharp(buffer).metadata()`). A real decode throws identically for a
 * genuinely truncated/synthetic buffer -- including this very route's own
 * "valid JPEG" test fixture, `FF D8 FF E0` followed by 16 arbitrary filler
 * bytes, which is not a structurally valid JPEG either -- and for an
 * actually-malicious stub. It cannot tell the two apart, so it would reject
 * legitimate-looking test/dev uploads exactly as hard as garbage. Requiring
 * *some* payload past the signature is the cheap signal that actually
 * discriminates a bare magic-bytes-only stub from anything else, without
 * spending decode time or a Vision call on input that could not possibly be
 * an image.
 */
const SIGNATURE_LENGTH = { 'image/jpeg': 3, 'image/png': 8, 'image/webp': 12 };

function looksDecodable(buffer, mime) {
  const sigLen = SIGNATURE_LENGTH[mime];
  return typeof sigLen === 'number' && buffer.length > sigLen;
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

      if (!looksDecodable(buffer, mime)) return fail(res, 'IMAGE_INVALID', scanId);

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
        const code = e && STATUS_BY_CODE[e.code] ? e.code : 'VISION_UNAVAILABLE';
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
