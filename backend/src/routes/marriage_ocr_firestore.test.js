const fs = require('fs');
const pathlib = require('path');
const express = require('express');
const request = require('supertest');
const { createMarriageOcrRouter } = require('./marriage_ocr_firestore');

let JPEG;
const b64 = (buf) => buf.toString('base64');

beforeAll(async () => {
  const sharp = require('sharp');
  JPEG = await sharp({
    create: { width: 40, height: 30, channels: 3, background: { r: 200, g: 60, b: 60 } },
  }).jpeg().toBuffer();
});

const wordAt = (text, cx, cy) => ({
  text,
  confidence: 1,
  vertices: [
    { x: cx - 5, y: cy - 5 }, { x: cx + 5, y: cy - 5 },
    { x: cx + 5, y: cy + 5 }, { x: cx - 5, y: cy + 5 },
  ],
});

// One entry: header row 0 (labels), entry row 1 with groom top / bride bottom.
const gridPages = {
  pages: {
    left: {
      imageBuffer: Buffer.from('L'),
      cells: [
        { key: 'no', row: 0, x: 0, y: 0, w: 40, h: 40 },
        { key: 'contracting_parties', row: 0, x: 40, y: 0, w: 200, h: 40 },
        { key: 'no', row: 1, x: 0, y: 100, w: 40, h: 80 },
        { key: 'contracting_parties', row: 1, x: 40, y: 100, w: 200, h: 80 },
        { key: 'marriage_date', row: 1, x: 240, y: 100, w: 120, h: 80 },
      ],
    },
    right: {
      imageBuffer: Buffer.from('R'),
      cells: [
        { key: 'minister', row: 0, x: 0, y: 0, w: 200, h: 40 },
        { key: 'minister', row: 1, x: 0, y: 100, w: 200, h: 80 },
      ],
    },
  },
  rotationApplied: 90,
  deskewDeg: 0.5,
  warnings: [],
};

function marriageApp(overrides = {}, role = 'admin') {
  const app = express();
  app.use('/api/ocr/marriage', createMarriageOcrRouter({
    verifyToken: (req, _res, next) => { req.user = { uid: 'u', role }; next(); },
    fetchGrid: async () => gridPages,
    recognizeImage: async (buf) => (buf.toString() === 'L'
      ? {
        words: [
          // header row labels
          wordAt('NO', 20, 20), wordAt('CONTRACTING', 140, 20),
          // entry: groom top (y<140), bride bottom (y>=140)
          wordAt('47', 20, 120), wordAt('Marlon', 140, 120), wordAt('Ana', 140, 160),
          wordAt('1994', 300, 130),
        ],
      }
      : { words: [wordAt('MINISTER', 100, 20), wordAt('FrAlcher', 100, 130)] }),
    ...overrides,
  }));
  return app;
}

describe('POST /api/ocr/marriage/scan', () => {
  test('returns marriage rows in the groom/bride shape with CONFIDENCE_UNAVAILABLE', async () => {
    const res = await request(marriageApp()).post('/api/ocr/marriage/scan')
      .send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.scanId).toBe('s1');
    expect(res.body.data.rows).toHaveLength(1); // header row dropped
    const row = res.body.data.rows[0];
    expect(row.groom.name).toBe('Marlon');
    expect(row.bride.name).toBe('Ana');
    expect(row.dateOfMarriage).toBe('1994');
    expect(row.minister).toBe('FrAlcher');
    expect(row.lineNo).toBe('47');
    expect(res.body.data.rotation).toBe(90);
    expect(res.body.data.warnings).toContain('CONFIDENCE_UNAVAILABLE');
  });

  test('rejects a parishioner (403)', async () => {
    const res = await request(marriageApp({}, 'parishioner')).post('/api/ocr/marriage/scan')
      .send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(res.status).toBe(403);
  });

  test('a deliberate CV refusal surfaces SPREAD_UNREADABLE and does not fall back', async () => {
    const { CvGridError } = require('../services/cv_grid_client');
    const extract = jest.fn();
    const app = express();
    app.use('/api/ocr/marriage', createMarriageOcrRouter({
      verifyToken: (req, _res, next) => { req.user = { uid: 'u', role: 'admin' }; next(); },
      fetchGrid: async () => {
        const e = new CvGridError('CV_REFUSED', 'no_table_detected');
        e.reason = 'columns_unmatched';
        e.side = 'left';
        throw e;
      },
      extract,
    }));
    const res = await request(app).post('/api/ocr/marriage/scan')
      .send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(res.status).toBe(422);
    expect(res.body.code).toBe('SPREAD_UNREADABLE');
    expect(res.body.detail).toMatch(/left page/i);
    expect(extract).not.toHaveBeenCalled();
    expect(JSON.stringify(res.body)).not.toContain('no_table_detected');
  });

  test('a genuine CV failure falls back to extractMarriageRows and adds CV_UNAVAILABLE', async () => {
    const { CvGridError } = require('../services/cv_grid_client');
    const app = express();
    app.use('/api/ocr/marriage', createMarriageOcrRouter({
      verifyToken: (req, _res, next) => { req.user = { uid: 'u', role: 'admin' }; next(); },
      fetchGrid: async () => { throw new CvGridError('CV_UNREACHABLE', 'down'); },
      recognize: async () => ({ words: [{ text: 'X', vertices: [], confidence: 1 }] }),
      extract: () => ({
        rows: [{ index: 0, lineNo: '1', groom: { name: 'M' }, bride: { name: 'A' },
          dateOfMarriage: '', minister: '', licenseNumber: '', observations: '' }],
        rotation: 0, warnings: [],
      }),
    }));
    const res = await request(app).post('/api/ocr/marriage/scan')
      .send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(res.status).toBe(200);
    expect(res.body.data.rows).toHaveLength(1);
    expect(res.body.data.warnings).toContain('CV_UNAVAILABLE');
  });

  test('maps LAYOUT_UNRECOGNIZED from the fallback extractor to 422', async () => {
    const { CvGridError } = require('../services/cv_grid_client');
    const app = express();
    app.use('/api/ocr/marriage', createMarriageOcrRouter({
      verifyToken: (req, _res, next) => { req.user = { uid: 'u', role: 'admin' }; next(); },
      fetchGrid: async () => { throw new CvGridError('CV_DISABLED', 'off'); },
      recognize: async () => ({ words: [{ text: 'X', vertices: [], confidence: 1 }] }),
      extract: () => { const e = new Error('nope'); e.code = 'LAYOUT_UNRECOGNIZED'; throw e; },
    }));
    const res = await request(app).post('/api/ocr/marriage/scan')
      .send({ scanId: 's1', imageBase64: b64(JPEG) });
    expect(res.status).toBe(422);
    expect(res.body.code).toBe('LAYOUT_UNRECOGNIZED');
    expect(res.body.message.toLowerCase()).toContain('marriage register');
  });
});

describe('server.js mount', () => {
  test('mounts the marriage router before the global JSON parser', () => {
    const src = fs.readFileSync(pathlib.join(__dirname, '..', 'server.js'), 'utf8');
    const mountAt = src.indexOf("app.use('/api/ocr/marriage'");
    const globalJsonAt = src.indexOf("express.json({ limit: '10mb' })");
    expect(mountAt).toBeGreaterThan(-1);
    expect(globalJsonAt).toBeGreaterThan(-1);
    expect(mountAt).toBeLessThan(globalJsonAt);
  });
});
