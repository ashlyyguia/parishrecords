/**
 * Google Cloud Vision I/O for baptismal register scans.
 *
 * This module is the ONLY place Vision is called. It performs no layout
 * analysis — see baptismal_register_layout.js for that. Credentials never
 * leave the server.
 */

function codedError(message, code) {
  const err = new Error(message);
  err.code = code;
  return err;
}

/**
 * Resolves Vision service-account credentials from the environment.
 * Prefers a dedicated Vision key; falls back to the Firebase service account
 * because it belongs to the same GCP project (the Vision API just needs
 * enabling on it).
 */
function resolveVisionCredentials(env) {
  const raw =
    env.GOOGLE_CLOUD_VISION_CREDENTIALS_JSON || env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (!raw) {
    throw codedError(
      'VISION_AUTH: no Vision credentials configured (set GOOGLE_CLOUD_VISION_CREDENTIALS_JSON)',
      'VISION_AUTH',
    );
  }
  try {
    return { credentials: JSON.parse(raw) };
  } catch (e) {
    throw codedError('VISION_AUTH: credentials JSON is not parseable', 'VISION_AUTH');
  }
}

let cachedClient = null;

function defaultClient(env) {
  if (cachedClient) return cachedClient;
  // Required lazily so unit tests can inject a fake client without the
  // real SDK (or credentials) being present.
  const vision = require('@google-cloud/vision');
  cachedClient = new vision.ImageAnnotatorClient(resolveVisionCredentials(env));
  return cachedClient;
}

// gRPC status codes we care about: 7 = PERMISSION_DENIED, 16 = UNAUTHENTICATED,
// 8 = RESOURCE_EXHAUSTED (quota).
function mapVisionError(err) {
  if (err.code === 'NO_TEXT_FOUND' || err.code === 'VISION_AUTH') return err;
  if (err.code === 7 || err.code === 16) {
    return codedError('VISION_AUTH: Vision rejected the credentials', 'VISION_AUTH');
  }
  if (err.code === 8) {
    return codedError('VISION_QUOTA: Vision quota exceeded', 'VISION_QUOTA');
  }
  return codedError('VISION_UNAVAILABLE: could not reach Vision', 'VISION_UNAVAILABLE');
}

function wordText(word) {
  return (word.symbols || []).map((s) => s.text || '').join('');
}

/**
 * Runs handwriting-capable OCR and normalizes the response.
 * @returns {Promise<{words: Array, fullText: string}>}
 */
async function recognizeWords(imageBuffer, options = {}) {
  const client = options.client || defaultClient(options.env || process.env);
  let response;
  try {
    const [result] = await client.documentTextDetection({
      image: { content: imageBuffer },
      imageContext: { languageHints: ['en'] },
    });
    response = result;
  } catch (e) {
    throw mapVisionError(e);
  }

  const annotation = response && response.fullTextAnnotation;
  if (!annotation || !annotation.text) {
    throw codedError('NO_TEXT_FOUND: Vision found no text in the image', 'NO_TEXT_FOUND');
  }

  const words = [];
  for (const page of annotation.pages || []) {
    for (const block of page.blocks || []) {
      for (const paragraph of block.paragraphs || []) {
        for (const word of paragraph.words || []) {
          const text = wordText(word).trim();
          if (!text) continue;
          const vertices = ((word.boundingBox || {}).vertices || []).map((v) => ({
            x: v.x || 0,
            y: v.y || 0,
          }));
          if (vertices.length !== 4) continue;
          words.push({
            text,
            vertices,
            confidence: typeof word.confidence === 'number' ? word.confidence : 0,
          });
        }
      }
    }
  }

  if (words.length === 0) {
    throw codedError('NO_TEXT_FOUND: no readable words in the image', 'NO_TEXT_FOUND');
  }

  return { words, fullText: annotation.text };
}

module.exports = { resolveVisionCredentials, recognizeWords };
