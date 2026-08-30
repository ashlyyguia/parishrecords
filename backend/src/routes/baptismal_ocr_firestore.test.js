const zlib = require('zlib');
const express = require('express');
const request = require('supertest');
const { createBaptismalOcrRouter } = require('./baptismal_ocr_firestore');
const { MAX_INPUT_PIXELS } = require('../services/baptismal_image_preprocess');

// A genuine, decodable tiny JPEG -- generated the same way
// `baptismal_image_preprocess.test.js` does (sharp({ create: {...} })), so
// the route's real `isDecodableImage` (sharp(buffer).metadata()) probe
// accepts it. Built once in beforeAll since sharp encoding is async.
let JPEG;
const b64 = (buf) => buf.toString('base64');

beforeAll(async () => {
  const sharp = require('sharp');
  JPEG = await sharp({
    create: { width: 40, height: 30, channels: 3, background: { r: 200, g: 60, b: 60 } },
  }).jpeg().toBuffer();
});

/**
 * Builds a syntactically-complete but otherwise empty PNG that declares
 * arbitrary pixel dimensions in its IHDR chunk -- mirrors
 * `baptismal_image_preprocess.test.js`'s helper of the same shape. Used to
 * exercise the real `isDecodableImage` pixel-limit branch through the route
 * without needing an actual multi-hundred-megapixel file on disk.
 */
function makePngWithClaimedDimensions(width, height) {
  const chunk = (type, data) => {
    const typeAndData = Buffer.concat([Buffer.from(type), data]);
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length, 0);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(zlib.crc32(typeAndData) >>> 0, 0);
    return Buffer.concat([len, typeAndData, crc]);
  };
  const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const ihdrData = Buffer.alloc(13);
  ihdrData.writeUInt32BE(width, 0);
  ihdrData.writeUInt32BE(height, 4);
  ihdrData[8] = 8; // bit depth
  ihdrData[9] = 2; // color type: RGB
  ihdrData[10] = 0; // compression
  ihdrData[11] = 0; // filter
  ihdrData[12] = 0; // interlace
  const ihdr = chunk('IHDR', ihdrData);
  const idat = chunk('IDAT', zlib.deflateSync(Buffer.alloc(0)));
  const iend = chunk('IEND', Buffer.alloc(0));
  return Buffer.concat([sig, ihdr, idat, iend]);
}

function appWith(overrides = {}, role = 'admin') {
  const app = express();
  app.use('/api/ocr/baptismal', createBaptismalOcrRouter({
    // Stand in for verifyFirebaseToken so tests need no Firebase.
    verifyToken: (req, _res, next) => { req.user = { uid: 'u1', role }; next(); },
    recognize: async () => ({ words: [{ text: 'X', vertices: [], confidence: 1 }], fullText: 'X' }),
    extract: () => ({
      rows: [{
        index: 0,
        lineNo: '1',
        fields: { givenName: { value: 'Juan', confidence: 0.9, inherited: false } },
      }],
      rotation: 0,
      gutterX: 500,
      columns: { left: [{ key: 'givenName', x0: 0, x1: 100, matched: true }], right: [] },
      warnings: ['GUTTER_UNCONFIRMED'],
    }),
    ...overrides,
  }));
  return app;
}

describe('POST /api/ocr/baptismal/scan', () => {
  test('returns extracted rows for a valid JPEG', async () => {
    const res = await request(appWith()).post('/api/ocr/baptismal/scan')
      .send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.scanId).toBe('s1');
    expect(res.body.data.rows).toHaveLength(1);
    expect(res.body.data.rotation).toBe(0);

    // Full response-shape contract for the Flutter client -- not just the
    // three fields above.
    const { data } = res.body;
    expect(data.warnings).toEqual(['GUTTER_UNCONFIRMED', 'CONFIDENCE_UNAVAILABLE']);
    // FIX 12: `columns`/`gutterX` are deliberately NOT serialized -- nothing
    // reads them (`BaptismalOcrScan.fromJson` ignores both) and they sit in
    // a content-relative coordinate frame that isn't usable for an image
    // overlay as-is. `extract()` above still returns them (other callers of
    // `extractBaptismalRows` may use them), but the ROUTE must not echo them.
    expect(data.columns).toBeUndefined();
    expect(data.gutterX).toBeUndefined();

    const row = data.rows[0];
    expect(row.lineNo).toBe('1');
    expect(row.fields).toBeTruthy();
    const field = row.fields.givenName;
    expect(field).toEqual({ value: 'Juan', confidence: 0.9, inherited: false });
  });

  test('rejects a parishioner', async () => {
    const res = await request(appWith({}, 'parishioner')).post('/api/ocr/baptismal/scan')
      .send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(res.status).toBe(403);
    expect(res.body.success).toBe(false);
  });

  test('allows staff', async () => {
    const res = await request(appWith({}, 'staff')).post('/api/ocr/baptismal/scan')
      .send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(res.status).toBe(200);
  });

  test('rejects a missing scanId', async () => {
    const res = await request(appWith()).post('/api/ocr/baptismal/scan')
      .send({ imageBase64: b64(JPEG) });
    expect(res.status).toBe(400);
  });

  test('rejects a non-image payload with IMAGE_INVALID', async () => {
    const res = await request(appWith()).post('/api/ocr/baptismal/scan')
      .send({ scanId: 's1', imageBase64: b64(Buffer.from('%PDF-1.4 not an image')) });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe('IMAGE_INVALID');
  });

  test('rejects an oversized image with IMAGE_TOO_LARGE', async () => {
    const big = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(11 * 1024 * 1024, 1)]);
    const res = await request(appWith()).post('/api/ocr/baptismal/scan')
      .send({ scanId: 's1', imageBase64: b64(big) });
    expect(res.status).toBe(413);
    expect(res.body.code).toBe('IMAGE_TOO_LARGE');
  });

  const failure = (code) => async () => { const e = new Error(code); e.code = code; throw e; };

  test.each([
    ['OCR_AUTH', 500],
    ['OCR_QUOTA', 429],
    ['OCR_UNAVAILABLE', 502],
    ['NO_TEXT_FOUND', 422],
  ])('maps %s to HTTP %i', async (code, status) => {
    const res = await request(appWith({ recognize: failure(code) }))
      .post('/api/ocr/baptismal/scan').send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(res.status).toBe(status);
    expect(res.body.code).toBe(code);
    expect(res.body.success).toBe(false);
  });

  test('maps LAYOUT_UNRECOGNIZED from the extractor to 422', async () => {
    const res = await request(appWith({
      extract: () => { const e = new Error('nope'); e.code = 'LAYOUT_UNRECOGNIZED'; throw e; },
    })).post('/api/ocr/baptismal/scan').send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(res.status).toBe(422);
    expect(res.body.code).toBe('LAYOUT_UNRECOGNIZED');
  });

  test('never echoes cell values in an error body', async () => {
    const res = await request(appWith({ recognize: failure('OCR_QUOTA') }))
      .post('/api/ocr/baptismal/scan').send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(JSON.stringify(res.body)).not.toContain('imageBase64');
  });

  test('never echoes cell values when a later step fails after recognition and extraction both succeed', async () => {
    // The existing "never echoes cell values" test above throws inside
    // recognize(), before any cell data exists in memory -- it cannot prove
    // the no-leak property. Here, recognition succeeds and extraction
    // succeeds in the sense that it computes real cell values before a
    // downstream failure occurs (attached to the thrown error, standing in
    // for e.g. a later serialization/audit step that references the
    // extracted rows) -- this is the path where an actual leak could occur.
    const secretValue = 'Maria Santos Cruz';
    const extract = () => {
      const rows = [{
        index: 0,
        lineNo: '1',
        fields: { givenName: { value: secretValue, confidence: 0.95, inherited: false } },
      }];
      const err = new Error('downstream failure after extraction computed real values');
      err.rows = rows;
      throw err;
    };
    const res = await request(appWith({ extract }))
      .post('/api/ocr/baptismal/scan').send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(res.status).toBe(500);
    expect(res.body.code).toBe('INTERNAL_ERROR');
    expect(res.body.success).toBe(false);
    const serialized = JSON.stringify(res.body);
    expect(serialized).not.toContain(secretValue);
    expect(serialized).not.toContain('imageBase64');
  });
});

describe('POST /api/ocr/baptismal/scan edge cases', () => {
  test('rejects an imageBase64 that is not valid base64 with IMAGE_INVALID', async () => {
    // Node's base64 decoder never throws on malformed input -- it silently
    // drops out-of-alphabet characters -- so this must be caught downstream
    // by the magic-byte/size checks rather than a try/catch around the
    // decode itself. This string decodes to bytes that don't match any
    // supported image signature.
    const res = await request(appWith()).post('/api/ocr/baptismal/scan')
      .send({ scanId: 's1', imageBase64: '!!!not-base64-at-all!!!' });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe('IMAGE_INVALID');
  });

  test('rejects an empty imageBase64 string', async () => {
    const res = await request(appWith()).post('/api/ocr/baptismal/scan')
      .send({ scanId: 's1', imageBase64: '' });
    expect(res.status).toBe(400);
  });

  test('rejects a whitespace-only scanId', async () => {
    const res = await request(appWith()).post('/api/ocr/baptismal/scan')
      .send({ scanId: '   ', imageBase64: b64(JPEG) });
    expect(res.status).toBe(400);
  });

  test('maps an extractor error with no .code to INTERNAL_ERROR (500), not VISION_UNAVAILABLE', async () => {
    // An uncoded error from extractBaptismalRows is an internal bug, not a
    // Vision-availability problem -- mislabelling it as VISION_UNAVAILABLE
    // would misdirect debugging (see fix round: this used to default to
    // VISION_UNAVAILABLE/502).
    const res = await request(appWith({
      extract: () => { throw new Error('totally unexpected'); },
    })).post('/api/ocr/baptismal/scan').send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(res.status).toBe(500);
    expect(res.body.code).toBe('INTERNAL_ERROR');
    expect(res.body.success).toBe(false);
    // No-leak property: the underlying error message must never appear.
    expect(JSON.stringify(res.body)).not.toContain('totally unexpected');
  });

  test('rejects a magic-valid but undecodable stub with IMAGE_INVALID and never calls Vision', async () => {
    // A bare 3-byte JPEG SOI marker passes sniffImageType (it only checks
    // magic bytes) but carries no payload past the signature -- it cannot
    // possibly be a decodable image. This must be rejected before the route
    // ever spends a Vision call on it.
    const stub = Buffer.from([0xff, 0xd8, 0xff]);
    const recognize = jest.fn(async () => ({ words: [], fullText: '' }));
    const res = await request(appWith({ recognize })).post('/api/ocr/baptismal/scan')
      .send({ scanId: 's1', imageBase64: b64(stub) });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe('IMAGE_INVALID');
    expect(recognize).not.toHaveBeenCalled();
  });

  test('rejects a magic-valid stub with garbage body (FF D8 FF FF FF FF) with IMAGE_INVALID and never calls Vision', async () => {
    // Magic bytes alone (FF D8 FF) are valid, and there are bytes past the
    // signature, but the body is not a real JPEG structure -- the real
    // decode probe (sharp metadata) must still reject it before Vision is
    // ever touched.
    const stub = Buffer.from([0xff, 0xd8, 0xff, 0xff, 0xff, 0xff]);
    const recognize = jest.fn(async () => ({ words: [], fullText: '' }));
    const res = await request(appWith({ recognize })).post('/api/ocr/baptismal/scan')
      .send({ scanId: 's1', imageBase64: b64(stub) });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe('IMAGE_INVALID');
    expect(recognize).not.toHaveBeenCalled();
  });

  test('a genuine decodable image passes the decodability probe and reaches Vision', async () => {
    const recognize = jest.fn(async () => ({ words: [{ text: 'X', vertices: [], confidence: 1 }], fullText: 'X' }));
    const res = await request(appWith({ recognize })).post('/api/ocr/baptismal/scan')
      .send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(res.status).toBe(200);
    expect(recognize).toHaveBeenCalledTimes(1);
  });

  // FIX 5 regression: a genuine image whose HEADER declares dimensions past
  // MAX_INPUT_PIXELS (an ordinary phone photo from a 50MP sensor, or an
  // adversarial decompression-bomb-style header either way) must be told
  // it's a RESOLUTION problem (IMAGE_TOO_LARGE), not falsely told its
  // FORMAT isn't supported (IMAGE_INVALID) -- and must never reach Vision.
  test('rejects an image whose declared dimensions exceed the pixel cap with IMAGE_TOO_LARGE, not IMAGE_INVALID', async () => {
    const side = Math.ceil(Math.sqrt(MAX_INPUT_PIXELS)) + 1000;
    const huge = makePngWithClaimedDimensions(side, side);
    const recognize = jest.fn(async () => ({ words: [], fullText: '' }));

    const res = await request(appWith({ recognize })).post('/api/ocr/baptismal/scan')
      .send({ scanId: 's1', imageBase64: b64(huge) });

    expect(res.status).toBe(413);
    expect(res.body.code).toBe('IMAGE_TOO_LARGE');
    expect(res.body.success).toBe(false);
    // The message must be honest about resolution, not claim an unsupported
    // format -- this is a valid PNG, just over the resolution cap.
    expect(res.body.message.toLowerCase()).not.toContain('supported image');
    expect(recognize).not.toHaveBeenCalled();
  });
});

describe('scanId logging (FIX 12)', () => {
  // `scanId` is only validated as a non-empty string (no length/character
  // bound) inside a request body allowed up to 20MB -- unbounded, it's both
  // a log-injection vector (embedded CR/LF forging fake log lines) and a
  // way to blow up log storage with one oversized field.
  test('strips embedded CR/LF from scanId before logging on the success path', async () => {
    const logSpy = jest.spyOn(console, 'log').mockImplementation(() => {});
    try {
      const injected = 's1\n[FAKE] admin login succeeded\r\nscan=evil';
      const res = await request(appWith()).post('/api/ocr/baptismal/scan')
        .send({ scanId: injected, imageBase64: b64(JPEG) });
      expect(res.status).toBe(200);
      const logged = logSpy.mock.calls.map((c) => c.join(' ')).join('\n');
      expect(logged).not.toContain('\n[FAKE]');
      expect(logged).not.toContain('\r');
    } finally {
      logSpy.mockRestore();
    }
  });

  test('truncates an oversized scanId before logging on a failure path', async () => {
    const warnSpy = jest.spyOn(console, 'warn').mockImplementation(() => {});
    try {
      const huge = 'x'.repeat(5000);
      const res = await request(appWith({
        extract: () => { const e = new Error('nope'); e.code = 'LAYOUT_UNRECOGNIZED'; throw e; },
      })).post('/api/ocr/baptismal/scan').send({ scanId: huge, imageBase64: b64(JPEG) });
      expect(res.status).toBe(422);
      const logged = warnSpy.mock.calls.map((c) => c.join(' ')).join('\n');
      expect(logged).not.toContain(huge);
      // Some bounded prefix of the id may still appear -- just not the
      // unbounded original.
      expect(logged.length).toBeLessThan(huge.length);
    } finally {
      warnSpy.mockRestore();
    }
  });
});

describe('CV grid path', () => {
  const gridPages = {
    pages: {
      left: { imageBuffer: Buffer.from('L'), cells: [
        { key: 'no', row: 0, x: 0, y: 0, w: 40, h: 40 },
        { key: 'child_name', row: 0, x: 40, y: 0, w: 200, h: 40 },
      ] },
      right: { imageBuffer: Buffer.from('R'), cells: [
        { key: 'minister', row: 0, x: 0, y: 0, w: 200, h: 40 },
      ] },
    },
    rotationApplied: 90, deskewDeg: 0.5, warnings: [],
  };
  const wordAt = (text, cx, cy) => ({
    text, confidence: 1,
    vertices: [{ x: cx - 5, y: cy - 5 }, { x: cx + 5, y: cy - 5 }, { x: cx + 5, y: cy + 5 }, { x: cx - 5, y: cy + 5 }],
  });

  test('uses CV rows when the grid service succeeds', async () => {
    const app = express();
    app.use('/api/ocr/baptismal', createBaptismalOcrRouter({
      verifyToken: (req, _res, next) => { req.user = { uid: 'u', role: 'admin' }; next(); },
      fetchGrid: async () => gridPages,
      // The CV path OCRs each rectified page; preprocess passes the tiny
      // non-image buffer through unchanged, so we can key off its contents.
      recognizeImage: async (buf) => (buf.toString() === 'L'
        ? { words: [wordAt('1', 20, 20), wordAt('JUAN', 140, 20)] }
        : { words: [wordAt('FR.X', 100, 20)] }),
    }));
    const res = await request(app).post('/api/ocr/baptismal/scan')
      .send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(res.status).toBe(200);
    expect(res.body.data.rows).toHaveLength(1);
    expect(res.body.data.rows[0].fields.nameOfChild.value).toBe('JUAN');
    expect(res.body.data.rows[0].fields.minister.value).toBe('FR.X');
    expect(res.body.data.rotation).toBe(90);
    expect(res.body.data.warnings).not.toContain('CV_UNAVAILABLE');
    expect(res.body.data.warnings).toContain('CONFIDENCE_UNAVAILABLE');
  });

  test('falls back to word-clustering with CV_UNAVAILABLE when the grid service genuinely fails', async () => {
    const { CvGridError } = require('../services/cv_grid_client');
    const app = express();
    app.use('/api/ocr/baptismal', createBaptismalOcrRouter({
      verifyToken: (req, _res, next) => { req.user = { uid: 'u', role: 'admin' }; next(); },
      fetchGrid: async () => { throw new CvGridError('CV_UNREACHABLE', 'down'); },
      recognize: async () => ({ words: [{ text: 'X', vertices: [], confidence: 1 }] }),
      extract: () => ({ rows: [{ index: 0, lineNo: '1', fields: {} }], rotation: 0, warnings: [] }),
    }));
    const res = await request(app).post('/api/ocr/baptismal/scan')
      .send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(res.status).toBe(200);
    expect(res.body.data.rows).toHaveLength(1);
    expect(res.body.data.warnings).toContain('CV_UNAVAILABLE');
  });

  test('CV_DISABLED (service not configured) falls back SILENTLY -- no CV_UNAVAILABLE warning', async () => {
    // The service being unconfigured is an intentional off-state, not a
    // fault: a fallback scan that works fine should not surface a scary
    // "issue to review" banner. Only genuine CV failures warn.
    const { CvGridError } = require('../services/cv_grid_client');
    const app = express();
    app.use('/api/ocr/baptismal', createBaptismalOcrRouter({
      verifyToken: (req, _res, next) => { req.user = { uid: 'u', role: 'admin' }; next(); },
      fetchGrid: async () => { throw new CvGridError('CV_DISABLED', 'OCR_SERVICE_URL not set'); },
      recognize: async () => ({ words: [{ text: 'X', vertices: [], confidence: 1 }] }),
      extract: () => ({ rows: [{ index: 0, lineNo: '1', fields: {} }], rotation: 0, warnings: [] }),
    }));
    const res = await request(app).post('/api/ocr/baptismal/scan')
      .send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(res.status).toBe(200);
    expect(res.body.data.warnings).not.toContain('CV_UNAVAILABLE');
    expect(res.body.data.warnings).toContain('CONFIDENCE_UNAVAILABLE');
  });

  test('an OCR.space failure during the CV path still maps to its OCR_* code', async () => {
    // fetchGrid succeeds, but OCR on the rectified pages fails with a coded
    // OCR error. The catch falls back to the single-OCR path, which fails the
    // same way, and the OCR_* code must reach the client (not INTERNAL_ERROR).
    const app = express();
    const ocrFail = () => { const e = new Error('quota'); e.code = 'OCR_QUOTA'; throw e; };
    app.use('/api/ocr/baptismal', createBaptismalOcrRouter({
      verifyToken: (req, _res, next) => { req.user = { uid: 'u', role: 'admin' }; next(); },
      fetchGrid: async () => gridPages,
      recognizeImage: ocrFail,
      recognize: ocrFail,
    }));
    const res = await request(app).post('/api/ocr/baptismal/scan')
      .send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(res.status).toBe(429);
    expect(res.body.code).toBe('OCR_QUOTA');
  });
});

describe('body size ordering', () => {
  // Regression: mounted after server.js's global express.json({limit:'10mb'}),
  // a valid ~13.4MB base64 scan dies with a generic Express 413 and never
  // reaches our handler. The router must own a 20mb parser and be mounted
  // ahead of the global one.
  test('accepts a base64 body over 10MB', async () => {
    // A genuine decodable JPEG (so the real isDecodableImage probe passes),
    // padded with trailing bytes after its EOI marker to reach ~8MB of
    // total image bytes -> ~10.9MB of base64, past the global 10mb limit.
    // sharp's metadata() only reads the header, so trailing padding after a
    // structurally-complete JPEG doesn't affect decodability.
    const image = Buffer.concat([JPEG, Buffer.alloc(8 * 1024 * 1024 - JPEG.length, 1)]);
    const res = await request(appWith()).post('/api/ocr/baptismal/scan')
      .send({ scanId: 's1', imageBase64: b64(image) });
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
  });

  test('server.js mounts the router before the global JSON parser', () => {
    const fs = require('fs');
    const path = require('path');
    const src = fs.readFileSync(path.join(__dirname, '..', 'server.js'), 'utf8');
    const mountAt = src.indexOf("app.use('/api/ocr/baptismal'");
    const globalJsonAt = src.indexOf("express.json({ limit: '10mb' })");
    expect(mountAt).toBeGreaterThan(-1);
    expect(globalJsonAt).toBeGreaterThan(-1);
    expect(mountAt).toBeLessThan(globalJsonAt);
  });
});
