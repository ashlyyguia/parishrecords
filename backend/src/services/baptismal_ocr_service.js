/**
 * OCR.space I/O for baptismal register scans.
 *
 * This module is the ONLY place OCR.space is called for baptismal scans. It
 * performs no layout analysis (see baptismal_register_layout.js) and never
 * lets the API key reach the client. It normalizes OCR.space's axis-aligned
 * word overlay into the { text, vertices:[TL,TR,BR,BL], confidence } shape the
 * layout pipeline consumes.
 *
 * Engine selection (measured on real register pages, see
 * scripts/probe_ocrspace.js):
 *  - Engine 2 (default): returns word bounding boxes (TextOverlay) AND reads
 *    Latin-script handwriting more accurately than Engine 1 — the best fit for
 *    these registers.
 *  - Engine 1: also returns boxes; kept as a fallback via OCRSPACE_ENGINE.
 *  - Engine 3: unusable here — it times out (HTTP 504) or returns almost no
 *    text (≈39 words vs ≈559 on the same page), so the geometry pipeline gets
 *    nothing to work with.
 * The geometry pipeline REQUIRES word boxes, so only an overlay-returning
 * engine (1 or 2) is viable.
 */

const { callOcrSpace, overlayToCells } = require('./ocrspace_service');

function codedError(message, code) {
  const err = new Error(message);
  err.code = code;
  return err;
}

// callOcrSpace throws plain Errors; classify them by message into the wire
// codes the route maps to HTTP statuses. A missing key is a server
// misconfiguration (OCR_AUTH). Rate/quota messages are transient (OCR_QUOTA).
// Everything else (network, HTTP, unknown processing error) is treated as a
// reach-the-service problem (OCR_UNAVAILABLE, retryable).
function mapOcrSpaceError(err) {
  const msg = String((err && err.message) || '');
  if (/OCRSPACE_API_KEY/i.test(msg)) {
    return codedError('OCR_AUTH: OCR.space key is not configured', 'OCR_AUTH');
  }
  if (/quota|exceeded|rate ?limit|too many|throttl/i.test(msg)) {
    return codedError('OCR_QUOTA: OCR.space rate limit reached', 'OCR_QUOTA');
  }
  return codedError('OCR_UNAVAILABLE: could not reach OCR.space', 'OCR_UNAVAILABLE');
}

/**
 * Runs OCR.space Engine 1 on the prepared image and normalizes the response.
 * @returns {Promise<{words: Array, fullText: string}>}
 */
async function recognizeWords(imageBuffer, options = {}) {
  const env = options.env || process.env;
  const apiKey = options.apiKey || env.OCRSPACE_API_KEY;
  // Engine 2 by default: it returns the word boxes the layout pipeline needs
  // and reads this handwriting better than Engine 1 (Engine 3 is unusable —
  // see the module doc comment). Overridable via OCRSPACE_ENGINE.
  const engine = options.engine || env.OCRSPACE_ENGINE || '2';

  let json;
  try {
    json = await callOcrSpace(imageBuffer.toString('base64'), {
      apiKey,
      fetchImpl: options.fetchImpl,
      engine,
    });
  } catch (e) {
    throw mapOcrSpaceError(e);
  }

  const { text, cells } = overlayToCells(json);
  if (!cells || cells.length === 0) {
    throw codedError('NO_TEXT_FOUND: OCR.space returned no word boxes', 'NO_TEXT_FOUND');
  }

  const words = cells.map((c) => ({
    text: c.text,
    vertices: [
      { x: c.left, y: c.top },
      { x: c.left + c.width, y: c.top },
      { x: c.left + c.width, y: c.top + c.height },
      { x: c.left, y: c.top + c.height },
    ],
    confidence: 1,
  }));

  return { words, fullText: text || '' };
}

module.exports = { recognizeWords };
