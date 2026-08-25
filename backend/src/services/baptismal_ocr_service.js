/**
 * OCR.space I/O for baptismal register scans.
 *
 * This module is the ONLY place OCR.space is called for baptismal scans. It
 * performs no layout analysis (see baptismal_register_layout.js) and never
 * lets the API key reach the client. It normalizes OCR.space's axis-aligned
 * word overlay into the { text, vertices:[TL,TR,BR,BL], confidence } shape the
 * layout pipeline consumes.
 *
 * Engine 1 is required: it is the OCR.space engine that returns word bounding
 * boxes. Engines 2/3 return text only, which the geometry pipeline can't use.
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

  let json;
  try {
    json = await callOcrSpace(imageBuffer.toString('base64'), {
      apiKey,
      fetchImpl: options.fetchImpl,
      engine: '1',
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
