const express = require('express');
const request = require('supertest');
const { createBaptismalOcrRouter } = require('./baptismal_ocr_firestore');

const JPEG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(16, 1)]);
const b64 = (buf) => buf.toString('base64');

function appWith(overrides = {}, role = 'admin') {
  const app = express();
  app.use('/api/ocr/baptismal', createBaptismalOcrRouter({
    // Stand in for verifyFirebaseToken so tests need no Firebase.
    verifyToken: (req, _res, next) => { req.user = { uid: 'u1', role }; next(); },
    recognize: async () => ({ words: [{ text: 'X', vertices: [], confidence: 1 }], fullText: 'X' }),
    extract: () => ({ rows: [{ index: 0, lineNo: '1', fields: {} }], rotation: 0, gutterX: 500, columns: { left: [], right: [] }, warnings: [] }),
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
    ['VISION_AUTH', 500],
    ['VISION_QUOTA', 429],
    ['VISION_UNAVAILABLE', 502],
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
    const res = await request(appWith({ recognize: failure('VISION_QUOTA') }))
      .post('/api/ocr/baptismal/scan').send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(JSON.stringify(res.body)).not.toContain('imageBase64');
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

  test('maps an extractor error with no .code to VISION_UNAVAILABLE (502)', async () => {
    const res = await request(appWith({
      extract: () => { throw new Error('totally unexpected'); },
    })).post('/api/ocr/baptismal/scan').send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(res.status).toBe(502);
    expect(res.body.code).toBe('VISION_UNAVAILABLE');
    expect(res.body.success).toBe(false);
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
});

describe('body size ordering', () => {
  // Regression: mounted after server.js's global express.json({limit:'10mb'}),
  // a valid ~13.4MB base64 scan dies with a generic Express 413 and never
  // reaches our handler. The router must own a 20mb parser and be mounted
  // ahead of the global one.
  test('accepts a base64 body over 10MB', async () => {
    // 8MB of image bytes -> ~10.9MB of base64, past the global 10mb limit.
    const image = Buffer.concat([
      Buffer.from([0xff, 0xd8, 0xff, 0xe0]),
      Buffer.alloc(8 * 1024 * 1024, 1),
    ]);
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
