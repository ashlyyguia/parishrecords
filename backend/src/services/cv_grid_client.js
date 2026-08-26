/**
 * Client for the Python CV grid service (POST /v1/grid). The service key
 * never reaches the browser -- only the Node backend calls this. Any failure
 * is a coded CvGridError the route maps to the word-clustering fallback.
 */

class CvGridError extends Error {
  constructor(code, message) {
    super(message || code);
    this.code = code;
  }
}

function parsePage(raw) {
  if (!raw || typeof raw !== 'object') throw new CvGridError('CV_BAD_RESPONSE', 'missing page');
  const cells = Array.isArray(raw.cells) ? raw.cells : [];
  if (typeof raw.image_b64 !== 'string' || !raw.image_b64) {
    throw new CvGridError('CV_BAD_RESPONSE', 'missing page image');
  }
  return {
    imageBuffer: Buffer.from(raw.image_b64, 'base64'),
    width: Number(raw.width) || 0,
    height: Number(raw.height) || 0,
    rows: Number(raw.rows) || 0,
    cols: Number(raw.cols) || 0,
    cells: cells.map((c) => ({
      key: String(c.key), row: Number(c.row) || 0,
      x: Number(c.x) || 0, y: Number(c.y) || 0, w: Number(c.w) || 0, h: Number(c.h) || 0,
    })),
  };
}

async function fetchGrid(imageBuffer, { env = process.env, fetchImpl = fetch } = {}) {
  const baseUrl = env.OCR_SERVICE_URL;
  if (!baseUrl) throw new CvGridError('CV_DISABLED', 'OCR_SERVICE_URL not set');
  const timeoutMs = Number(env.OCR_TIMEOUT_MS) || 20000;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  let res;
  try {
    res = await fetchImpl(`${baseUrl.replace(/\/$/, '')}/v1/grid`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/octet-stream',
        'X-OCR-Service-Key': env.OCR_SERVICE_KEY || '',
      },
      body: imageBuffer,
      signal: controller.signal,
    });
  } catch (e) {
    throw new CvGridError('CV_UNREACHABLE', e && e.message);
  } finally {
    clearTimeout(timer);
  }

  let body;
  try {
    body = await res.json();
  } catch (e) {
    throw new CvGridError('CV_BAD_RESPONSE', 'non-JSON');
  }

  if (!res.ok || !body || body.success !== true) {
    // A structured OcrError (4xx/5xx) means the service ran but refused/failed
    // this image -- treat as "CV can't help here", i.e. fall back.
    throw new CvGridError('CV_REFUSED', body && body.code);
  }
  if (!body.pages || !body.pages.left || !body.pages.right) {
    throw new CvGridError('CV_BAD_RESPONSE', 'missing pages');
  }
  return {
    rotationApplied: Number(body.rotation_applied) || 0,
    deskewDeg: Number(body.deskew_deg) || 0,
    warnings: Array.isArray(body.warnings) ? body.warnings.map(String) : [],
    pages: { left: parsePage(body.pages.left), right: parsePage(body.pages.right) },
  };
}

module.exports = { fetchGrid, CvGridError };
