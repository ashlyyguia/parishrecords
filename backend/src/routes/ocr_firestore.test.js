const fs = require('fs');
const path = require('path');
const express = require('express');
const request = require('supertest');
const { createOcrRouter } = require('./ocr_firestore');

const HEIC = fs.readFileSync(path.join(__dirname, '..', '..', 'test', 'fixtures', 'sample.heic'));
const b64 = (buf) => buf.toString('base64');
const OK_JSON = { ParsedResults: [{ ParsedText: 'hi', TextOverlay: { Lines: [] } }] };

function appWith(ocr) {
  const app = express();
  app.use(express.json({ limit: '20mb' }));
  app.use('/api/ocr', createOcrRouter({ ocr }));
  return app;
}

describe('POST /api/ocr/scan HEIC support', () => {
  afterEach(() => jest.restoreAllMocks());

  test('passes JPEG straight through to the OCR backend', async () => {
    let seen;
    const ocr = async (imageBase64) => { seen = imageBase64; return OK_JSON; };
    const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0]);
    const res = await request(appWith(ocr)).post('/api/ocr/scan')
      .send({ imageBase64: b64(jpeg), recordType: 'baptism' });
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(seen).toBe(b64(jpeg)); // unchanged
  });

  test('converts a HEIC upload to JPEG before calling the OCR backend', async () => {
    let seen;
    const ocr = async (imageBase64) => { seen = imageBase64; return OK_JSON; };
    const res = await request(appWith(ocr)).post('/api/ocr/scan')
      .send({ imageBase64: b64(HEIC), recordType: 'baptism' });
    expect(res.status).toBe(200);
    const forwarded = Buffer.from(seen, 'base64');
    expect(forwarded[0]).toBe(0xff); // JPEG magic
    expect(forwarded[1]).toBe(0xd8);
    expect(forwarded[2]).toBe(0xff);
  }, 25000);

  test('rejects an undecodable HEIC with 400 and never calls the OCR backend', async () => {
    const ocr = jest.fn(async () => OK_JSON);
    const fake = Buffer.concat([Buffer.from([0, 0, 0, 0x20]), Buffer.from('ftypheic'), Buffer.alloc(64, 0)]);
    jest.spyOn(console, 'log').mockImplementation(() => {}); // restored by afterEach
    const res = await request(appWith(ocr)).post('/api/ocr/scan')
      .send({ imageBase64: b64(fake), recordType: 'baptism' });
    expect(res.status).toBe(400);
    expect(res.body.success).toBe(false);
    expect(ocr).not.toHaveBeenCalled();
  });
});

describe('POST /api/ocr/scan validation and OCR-failure paths', () => {
  afterEach(() => jest.restoreAllMocks());

  test('missing imageBase64 returns 400 and never calls the OCR backend', async () => {
    const ocr = jest.fn(async () => OK_JSON);
    const res = await request(appWith(ocr)).post('/api/ocr/scan')
      .send({ recordType: 'baptism' });
    expect(res.status).toBe(400);
    expect(res.body.success).toBe(false);
    expect(ocr).not.toHaveBeenCalled();
  });

  test('invalid recordType returns 400', async () => {
    const ocr = jest.fn(async () => OK_JSON);
    const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0]);
    const res = await request(appWith(ocr)).post('/api/ocr/scan')
      .send({ imageBase64: b64(jpeg), recordType: 'birthday' });
    expect(res.status).toBe(400);
    expect(res.body.success).toBe(false);
    expect(ocr).not.toHaveBeenCalled();
  });

  test('a failing OCR backend maps to 502 with success:false', async () => {
    const ocr = async () => { throw new Error('upstream down'); };
    const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0]);
    const res = await request(appWith(ocr)).post('/api/ocr/scan')
      .send({ imageBase64: b64(jpeg), recordType: 'baptism' });
    expect(res.status).toBe(502);
    expect(res.body.success).toBe(false);
    expect(res.body.message).toContain('OCR failed');
  });

  test('a valid marriage request succeeds (parity with baptism)', async () => {
    const ocr = jest.fn(async () => OK_JSON);
    const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0]);
    const res = await request(appWith(ocr)).post('/api/ocr/scan')
      .send({ imageBase64: b64(jpeg), recordType: 'marriage' });
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(ocr).toHaveBeenCalledTimes(1);
  });
});
