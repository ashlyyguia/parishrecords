const fs = require('fs');
const path = require('path');
const { isHeic, heicToJpeg } = require('./heic_to_jpeg');

const FIXTURE = path.join(__dirname, '..', '..', 'test', 'fixtures', 'sample.heic');
const heic = fs.readFileSync(FIXTURE);

describe('isHeic', () => {
  test('detects a real iPhone HEIC by its ftyp brand', () => {
    expect(isHeic(heic)).toBe(true);
  });

  test('rejects JPEG, PNG, and WebP magic bytes', () => {
    expect(isHeic(Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0]))).toBe(false);
    expect(isHeic(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))).toBe(false);
    const webp = Buffer.concat([Buffer.from('RIFF'), Buffer.from([0, 0, 0, 0]), Buffer.from('WEBP')]);
    expect(isHeic(webp)).toBe(false);
  });

  test('rejects a short buffer and an ftyp box with a non-HEIF brand', () => {
    expect(isHeic(Buffer.from([0, 0, 0, 0x20]))).toBe(false); // too short for a brand
    const mp4 = Buffer.concat([Buffer.from([0, 0, 0, 0x20]), Buffer.from('ftypmp42'), Buffer.alloc(8, 0)]);
    expect(isHeic(mp4)).toBe(false);
  });
});

describe('heicToJpeg', () => {
  test('converts a real HEIC to JPEG bytes', async () => {
    const out = await heicToJpeg(heic);
    expect(Buffer.isBuffer(out)).toBe(true);
    expect(out.length).toBeGreaterThan(0);
    expect(out[0]).toBe(0xff);
    expect(out[1]).toBe(0xd8);
    expect(out[2]).toBe(0xff);
  }, 20000);

  test('rejects an ftyp-heic header with a garbage body', async () => {
    const spy = jest.spyOn(console, 'log').mockImplementation(() => {});
    const fake = Buffer.concat([Buffer.from([0, 0, 0, 0x20]), Buffer.from('ftypheic'), Buffer.alloc(64, 0)]);
    await expect(heicToJpeg(fake)).rejects.toBeTruthy();
    spy.mockRestore();
  });
});
