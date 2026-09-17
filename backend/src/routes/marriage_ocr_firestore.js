const express = require('express');
const { body, validationResult } = require('express-validator');

const { verifyFirebaseToken } = require('../middleware/auth');
const { recognizeWords } = require('../services/baptismal_ocr_service');
const { extractMarriageRows } = require('../services/marriage_register_layout');
const { fetchGrid: defaultFetchGrid } = require('../services/cv_grid_client');
const { marriageGridToRows } = require('../services/marriage_grid_assign');
const {
  sniffImageType,
  preprocessForOcr,
  MAX_INPUT_PIXELS,
} = require('../services/baptismal_image_preprocess');
const { isHeic, heicToJpeg } = require('../services/heic_to_jpeg');

const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
const ACCEPTED = new Set(['image/jpeg', 'image/png', 'image/webp']);

// Same OCR.space-friendly bounds the baptismal route uses.
const OCRSPACE_MAX_EDGE = 2500;
const OCRSPACE_JPEG_QUALITY = 80;

const STATUS_BY_CODE = {
  IMAGE_INVALID: 400,
  IMAGE_TOO_LARGE: 413,
  OCR_AUTH: 500,
  OCR_QUOTA: 429,
  OCR_UNAVAILABLE: 502,
  NO_TEXT_FOUND: 422,
  LAYOUT_UNRECOGNIZED: 422,
  SPREAD_UNREADABLE: 422,
  INTERNAL_ERROR: 500,
};

const MESSAGE_BY_CODE = {
  IMAGE_INVALID: 'That file is not a supported image. Use JPEG, PNG, or WebP.',
  IMAGE_TOO_LARGE: 'That image is too large to process (either the file size or its resolution is over the limit). Please use a smaller or lower-resolution photo.',
  OCR_AUTH: 'OCR is not configured on the server. Contact an administrator.',
  OCR_QUOTA: 'The OCR service is rate-limited right now. Try again shortly.',
  OCR_UNAVAILABLE: 'Could not reach the OCR service. Check your connection and retry.',
  NO_TEXT_FOUND: 'No readable text was found. Retake the photo with better lighting and framing.',
  LAYOUT_UNRECOGNIZED: 'This page does not look like a marriage register. Check the photo and retry.',
  SPREAD_UNREADABLE: "Couldn't read this register spread reliably. Retake the photo with the book opened flat, both pages fully in frame, and even lighting, then try again.",
  INTERNAL_ERROR: 'Something went wrong while processing this scan. Try again, and contact an administrator if it persists.',
};

function refusalDetail(reason, side) {
  const where = side === 'left' ? 'left' : side === 'right' ? 'right' : null;
  switch (reason) {
    case 'grid_not_found':
      return where
        ? `The ${where} page's ruled lines couldn't be found — lay the book flat, fill the frame with the page, and retake.`
        : "The register's ruled lines couldn't be found — lay the book flat, fill the frame, and retake.";
    case 'columns_unmatched':
      return where
        ? `The ${where} page's column lines were too faint or curved to read — press the book flat near the spine and retake.`
        : 'The column lines were too faint or curved to read — press the book flat near the spine and retake.';
    case 'rows_disagree':
    case 'pitch_mismatch':
      return "The two pages didn't line up — flatten the book so both pages sit in the same plane, keep both fully in frame, and retake.";
    default:
      return null;
  }
}

let sharpUnavailableWarnedInRoute = false;

const MAX_LOGGED_SCAN_ID_LENGTH = 64;
function sanitizeScanIdForLog(scanId) {
  const s = typeof scanId === 'string' ? scanId : String(scanId);
  return s.replace(/[\r\n]+/g, ' ').slice(0, MAX_LOGGED_SCAN_ID_LENGTH);
}

const PIXEL_LIMIT_ERROR_MESSAGE = 'Input image exceeds pixel limit';

async function isDecodableImage(buffer) {
  let sharp;
  try {
    sharp = require('sharp');
  } catch (e) {
    if (!sharpUnavailableWarnedInRoute) {
      console.error('[marriage-ocr] sharp unavailable, skipping decodability probe: ' + (e && e.message));
      sharpUnavailableWarnedInRoute = true;
    }
    return { decodable: true, tooLarge: false };
  }
  try {
    const meta = await sharp(buffer, { limitInputPixels: MAX_INPUT_PIXELS }).metadata();
    return { decodable: Boolean(meta && meta.width > 0 && meta.height > 0), tooLarge: false };
  } catch (e) {
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

// --- Header-band drop + renumber (ported from baptismal_grid_assign, adapted
// for the marriage row shape where the printed name lives at groom.name) ------

// Printed labels of the register's own header band and page titles. A row whose
// text is only these is the header, not an entry.
const HEADER_WORDS = new Set([
  'no', 'contracting', 'parties', 'legal', 'status', 'actual', 'address',
  'dates', 'places', 'of', 'birth', 'baptism', 'marriage', 'parents',
  'sponsors', 'sponsor', 'minister', 'license', 'observations', 'observation',
  'register', 'and', 'name', 'names',
]);

function tokens(s) {
  return String(s || '').toLowerCase().split(/[^a-z0-9]+/).filter(Boolean);
}

function plausibleNo(s) {
  const digits = String(s || '').replace(/\D/g, '');
  if (!digits) return null;
  const n = Number(digits);
  return n >= 1 && n <= 999 ? String(n) : null;
}

function hasDataText(s) {
  return tokens(s).some((t) => t.length >= 2 && /[a-z]/.test(t) && !HEADER_WORDS.has(t));
}

function isMarriageDataRow(row) {
  if (plausibleNo(row.lineNo)) return true;
  return hasDataText(row.groom && row.groom.name);
}

// The header band is geometrically identical to a data row, so it's told apart
// only by text: it reads as column labels and sits above the first entry. Keep
// everything from the first data row down; renumber by position, keeping a
// cleanly recognized register number when there is one.
function dropHeaderAndRenumber(rows) {
  const firstData = rows.findIndex(isMarriageDataRow);
  const kept = firstData > 0 ? rows.slice(firstData) : rows;
  return kept.map((r, i) => ({
    ...r,
    index: i,
    lineNo: plausibleNo(r.lineNo) || String(i + 1),
  }));
}

// --- Left/right row-offset alignment (ported from baptismal_grid_assign) ------

function pageRowTops(page) {
  const tops = new Map();
  for (const c of (page && page.cells) || []) {
    if (!tops.has(c.row) || c.y < tops.get(c.row)) tops.set(c.row, c.y);
  }
  return tops;
}
function median(nums) {
  if (nums.length === 0) return 0;
  const s = [...nums].sort((a, b) => a - b);
  return s[Math.floor(s.length / 2)];
}
function rowOffset(leftTops, rightTops) {
  const li = [...leftTops.keys()].sort((a, b) => a - b);
  if (li.length < 2 || rightTops.size < 2) return 0;
  const pitch = median(li.slice(1).map((r, k) => leftTops.get(r) - leftTops.get(li[k])));
  const tol = Math.max(20, pitch * 0.6);
  let best = { d: 0, score: -1 };
  for (let d = -6; d <= 6; d += 1) {
    let score = 0;
    for (const r of li) {
      const ry = rightTops.get(r + d);
      if (ry != null && Math.abs(leftTops.get(r) - ry) <= tol) score += 1;
    }
    if (score > best.score) best = { d, score };
  }
  return best.score >= 2 ? best.d : 0;
}

// Shift the right page's cell row indices into the left page's frame, so the
// pure marriageGridToRows mapper joins the two halves per physical entry.
function alignRightPage(leftPage, rightPage) {
  const d = rowOffset(pageRowTops(leftPage), pageRowTops(rightPage));
  if (!d) return rightPage;
  return { ...rightPage, cells: (rightPage.cells || []).map((c) => ({ ...c, row: c.row - d })) };
}

function createMarriageOcrRouter(deps = {}) {
  const recognize = deps.recognize || recognizeWords;
  const extract = deps.extract || extractMarriageRows;
  const preprocess = deps.preprocess || preprocessForOcr;
  const verifyToken = deps.verifyToken || verifyFirebaseToken;
  const fetchGrid = deps.fetchGrid || defaultFetchGrid;
  const recognizeImage = deps.recognizeImage
    || ((buf) => recognizeWords(buf, { detectOrientation: false }));

  const router = express.Router();
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
      if (buffer.length === 0) return fail(res, 'IMAGE_INVALID', scanId);
      if (buffer.length > MAX_IMAGE_BYTES) return fail(res, 'IMAGE_TOO_LARGE', scanId);

      if (isHeic(buffer)) {
        try {
          buffer = await heicToJpeg(buffer);
        } catch (e) {
          return fail(res, 'IMAGE_INVALID', scanId);
        }
      }

      const mime = sniffImageType(buffer);
      if (!mime || !ACCEPTED.has(mime)) return fail(res, 'IMAGE_INVALID', scanId);

      const decodability = await isDecodableImage(buffer);
      if (!decodability.decodable) {
        return fail(res, decodability.tooLarge ? 'IMAGE_TOO_LARGE' : 'IMAGE_INVALID', scanId);
      }

      try {
        let result;
        let extraWarnings = [];
        try {
          const grid = await fetchGrid(buffer, { register: 'marriage' });
          const [leftPrep, rightPrep] = await Promise.all([
            preprocess(grid.pages.left.imageBuffer, { maxEdge: OCRSPACE_MAX_EDGE, quality: OCRSPACE_JPEG_QUALITY }),
            preprocess(grid.pages.right.imageBuffer, { maxEdge: OCRSPACE_MAX_EDGE, quality: OCRSPACE_JPEG_QUALITY }),
          ]);
          const [leftOcr, rightOcr] = await Promise.all([
            recognizeImage(leftPrep), recognizeImage(rightPrep),
          ]);
          const rightAligned = alignRightPage(grid.pages.left, grid.pages.right);
          const built = marriageGridToRows(
            grid.pages.left, leftOcr.words, rightAligned, rightOcr.words,
          );
          result = {
            rows: dropHeaderAndRenumber(built.rows),
            rotation: grid.rotationApplied,
            warnings: [...grid.warnings, ...built.warnings],
          };
        } catch (cvErr) {
          if (cvErr && cvErr.code === 'CV_REFUSED') {
            const unreadable = new Error('cv refused spread');
            unreadable.code = 'SPREAD_UNREADABLE';
            unreadable.detail = refusalDetail(cvErr.reason, cvErr.side);
            throw unreadable;
          }
          const prepared = await preprocess(buffer, {
            maxEdge: OCRSPACE_MAX_EDGE,
            quality: OCRSPACE_JPEG_QUALITY,
          });
          const { words } = await recognize(prepared);
          result = extract(words);
          if (!cvErr || cvErr.code !== 'CV_DISABLED') extraWarnings = ['CV_UNAVAILABLE'];
        }

        // Counts only -- never cell values / recognized text (PII).
        console.log(
          `[marriage-ocr] scan=${sanitizeScanIdForLog(scanId)} rows=${result.rows.length} ` +
          `rotation=${result.rotation} warnings=${result.warnings.length} cv=${extraWarnings.length === 0} ms=${Date.now() - startedAt}`,
        );

        return res.json({
          success: true,
          data: {
            scanId,
            rows: result.rows,
            rotation: result.rotation,
            warnings: [...result.warnings, ...extraWarnings, 'CONFIDENCE_UNAVAILABLE'],
          },
        });
      } catch (e) {
        const code = e && STATUS_BY_CODE[e.code] ? e.code : 'INTERNAL_ERROR';
        return fail(res, code, scanId, e && e.detail);
      }
    },
  );

  return router;
}

function fail(res, code, scanId, detail) {
  console.warn(`[marriage-ocr] scan=${sanitizeScanIdForLog(scanId)} failed code=${code}`);
  const body = {
    success: false,
    code,
    message: MESSAGE_BY_CODE[code] || 'OCR failed.',
  };
  if (detail) body.detail = detail;
  return res.status(STATUS_BY_CODE[code] || 500).json(body);
}

module.exports = { createMarriageOcrRouter, router: createMarriageOcrRouter() };
