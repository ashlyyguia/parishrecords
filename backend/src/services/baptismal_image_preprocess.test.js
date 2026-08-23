const zlib = require('zlib');
const { sniffImageType, preprocessForOcr, MAX_INPUT_PIXELS } = require('./baptismal_image_preprocess');

/**
 * Builds a syntactically-complete but otherwise empty PNG that declares
 * arbitrary pixel dimensions in its IHDR chunk. Used to prove that a
 * huge-dimension image is rejected at decode time (via sharp's
 * `limitInputPixels`) instead of being fully decoded into memory — the
 * on-disk buffer here is under 100 bytes regardless of the claimed
 * width/height.
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
    // A non-grayscale source (distinct R/G/B channels) so a later assertion
    // can prove the grayscale stage actually ran rather than the pipeline
    // silently no-oping (falling into the catch-and-return-original path).
    const original = await sharp({
      create: { width: 40, height: 30, channels: 3, background: { r: 220, g: 40, b: 40 } },
    }).jpeg().toBuffer();
    const copy = Buffer.from(original);

    const out = await preprocessForOcr(original);

    expect(Buffer.isBuffer(out)).toBe(true);
    expect(out.length).toBeGreaterThan(0);
    expect(original.equals(copy)).toBe(true); // original untouched

    // Discriminate "sharp actually processed the image" from "sharp threw
    // and we fell back to the original buffer" — both would otherwise
    // satisfy every assertion above. sharp's grayscale() encodes to
    // web-friendly sRGB with three (now-identical) channels rather than
    // collapsing to one, so check that the R/G/B channel means converged
    // instead of asserting a channel count.
    expect(out.equals(original)).toBe(false);
    const [origStats, outStats] = await Promise.all([sharp(original).stats(), sharp(out).stats()]);
    const [origR, origG, origB] = origStats.channels.map((c) => c.mean);
    expect(Math.max(origR, origG, origB) - Math.min(origR, origG, origB)).toBeGreaterThan(50); // source was distinctly colored
    const [outR, outG, outB] = outStats.channels.map((c) => c.mean);
    expect(Math.max(outR, outG, outB) - Math.min(outR, outG, outB)).toBeLessThan(2); // grayscale() collapsed channels to near-identical means
    const outMeta = await sharp(out).metadata();
    expect(outMeta.format).toBe('jpeg');
  });

  test('falls back to the original buffer when processing fails', async () => {
    const notAnImage = Buffer.from('definitely not an image');
    const out = await preprocessForOcr(notAnImage);
    expect(out).toBe(notAnImage);
  });

  test('falls back to the original buffer instead of fully decoding a huge-dimension image', async () => {
    // A PNG whose header claims dimensions well beyond MAX_INPUT_PIXELS,
    // but whose actual on-disk bytes are tiny (~90 bytes). If the decode-time
    // pixel cap were not in place, sharp would attempt to allocate/decode
    // gigabytes of raw pixels for this. It should instead be rejected at
    // the header-check stage — fast, and without exhausting memory — and
    // preprocessForOcr should fall back to the identity buffer.
    const side = Math.ceil(Math.sqrt(MAX_INPUT_PIXELS)) + 1000; // comfortably over the cap
    const huge = makePngWithClaimedDimensions(side, side);

    const start = Date.now();
    const out = await preprocessForOcr(huge);
    const elapsedMs = Date.now() - start;

    expect(out).toBe(huge); // identity fallback, not a decoded/re-encoded buffer
    expect(elapsedMs).toBeLessThan(5000); // fails fast at the header check, not after a full decode
  });
});
