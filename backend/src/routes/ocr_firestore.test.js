const request = require('supertest');
const express = require('express');
const ocrRoutes = require('./ocr_firestore');

function makeApp() {
  const app = express();
  app.use(express.json({ limit: '10mb' }));
  app.use('/api/ocr', ocrRoutes);
  return app;
}

describe('POST /api/ocr/scan', () => {
  test('400 on invalid recordType / missing image', async () => {
    const res = await request(makeApp()).post('/api/ocr/scan').send({ recordType: 'invalid' });
    expect(res.status).toBe(400);
    expect(res.body.success).toBe(false);
  });

  test('200 with normalized cells on success', async () => {
    process.env.OCRSPACE_API_KEY = 'K';
    global.fetch = jest.fn(async () => ({
      ok: true,
      json: async () => ({
        ParsedResults: [
          { ParsedText: 'A', TextOverlay: { Lines: [{ Words: [{ WordText: 'A', Left: 1, Top: 2, Width: 3, Height: 4 }] }] } },
        ],
      }),
    }));
    const res = await request(makeApp())
      .post('/api/ocr/scan')
      .send({ imageBase64: 'x', recordType: 'baptism' });
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.engine).toBe('ocrspace');
    expect(res.body.data.cells[0]).toEqual({ text: 'A', left: 1, top: 2, width: 3, height: 4 });
  });

  test('502 when OCR.space errors', async () => {
    process.env.OCRSPACE_API_KEY = 'K';
    global.fetch = jest.fn(async () => ({ ok: true, json: async () => ({ IsErroredOnProcessing: true, ErrorMessage: ['nope'] }) }));
    const res = await request(makeApp())
      .post('/api/ocr/scan')
      .send({ imageBase64: 'x', recordType: 'baptism' });
    expect(res.status).toBe(502);
    expect(res.body.success).toBe(false);
  });
});
