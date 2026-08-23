const { sniffImageType, preprocessForOcr } = require('./baptismal_image_preprocess');

describe('sniffImageType', () => {
  test('detects JPEG', () => {
    expect(sniffImageType(Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0]))).toBe('image/jpeg');
  });

  test('detects PNG', () => {
    expect(sniffImageType(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))).toBe('image/png');
  });

  test('detects WebP', () => {
    const buf = Buffer.concat([
      Buffer.from('RIFF'), Buffer.from([0, 0, 0, 0]), Buffer.from('WEBP'),
    ]);
    expect(sniffImageType(buf)).toBe('image/webp');
  });

  test('rejects a PDF masquerading as an image', () => {
    expect(sniffImageType(Buffer.from('%PDF-1.4'))).toBe(null);
  });

  test('rejects empty and tiny buffers', () => {
    expect(sniffImageType(Buffer.alloc(0))).toBe(null);
    expect(sniffImageType(Buffer.from([0xff]))).toBe(null);
  });

  test('detects a WebP buffer that is exactly at the 12-byte minimum', () => {
    const buf = Buffer.concat([
      Buffer.from('RIFF'), Buffer.from([0, 0, 0, 0]), Buffer.from('WEBP'),
    ]);
    expect(buf.length).toBe(12);
    expect(sniffImageType(buf)).toBe('image/webp');
  });

  test('rejects a RIFF buffer one byte short of the WebP fourcc', () => {
    // RIFF + size + only 3 of the 4 WEBP fourcc bytes = 11 bytes total.
    const buf = Buffer.concat([
      Buffer.from('RIFF'), Buffer.from([0, 0, 0, 0]), Buffer.from('WEB'),
    ]);
    expect(buf.length).toBe(11);
    expect(sniffImageType(buf)).toBe(null);
  });

  test('detects a truncated JPEG that still carries the SOI marker', () => {
    // Only the 3-byte start-of-image marker is present; the rest of a real
    // JPEG stream is missing. Magic-byte sniffing should still succeed —
    // full validity is a decode-time concern, not a sniffing concern.
    expect(sniffImageType(Buffer.from([0xff, 0xd8, 0xff]))).toBe('image/jpeg');
  });

  test('rejects a RIFF header whose fourcc is not WEBP', () => {
    const buf = Buffer.concat([
      Buffer.from('RIFF'), Buffer.from([0, 0, 0, 0]), Buffer.from('AVI '),
    ]);
    expect(sniffImageType(buf)).toBe(null);
  });

  test('detects by bytes even when the declared mime/name disagrees', () => {
    // Simulate an upload whose declared content-type and filename claim PNG,
    // but whose bytes are actually a JPEG. sniffImageType takes only the
    // buffer, so it has no way to be fooled by the declaration.
    const lyingUpload = {
      originalname: 'photo.png',
      mimetype: 'image/png',
      buffer: Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0]),
    };
    expect(sniffImageType(lyingUpload.buffer)).toBe('image/jpeg');
    expect(sniffImageType(lyingUpload.buffer)).not.toBe(lyingUpload.mimetype);
  });
});

describe('preprocessForOcr', () => {
  test('returns a usable buffer and does not mutate the input', async () => {
    const sharp = require('sharp');
    const original = await sharp({
      create: { width: 40, height: 30, channels: 3, background: { r: 200, g: 200, b: 200 } },
    }).jpeg().toBuffer();
    const copy = Buffer.from(original);

    const out = await preprocessForOcr(original);

    expect(Buffer.isBuffer(out)).toBe(true);
    expect(out.length).toBeGreaterThan(0);
    expect(original.equals(copy)).toBe(true); // original untouched
  });

  test('falls back to the original buffer when processing fails', async () => {
    const notAnImage = Buffer.from('definitely not an image');
    const out = await preprocessForOcr(notAnImage);
    expect(out).toBe(notAnImage);
  });
});
