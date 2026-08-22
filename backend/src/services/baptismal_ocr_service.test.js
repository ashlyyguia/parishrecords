const { resolveVisionCredentials, recognizeWords } = require('./baptismal_ocr_service');

describe('resolveVisionCredentials', () => {
  test('prefers the dedicated Vision credentials', () => {
    const env = {
      GOOGLE_CLOUD_VISION_CREDENTIALS_JSON: '{"project_id":"vision-proj"}',
      FIREBASE_SERVICE_ACCOUNT_JSON: '{"project_id":"fb-proj"}',
    };
    expect(resolveVisionCredentials(env).credentials.project_id).toBe('vision-proj');
  });

  test('falls back to the Firebase service account', () => {
    const env = { FIREBASE_SERVICE_ACCOUNT_JSON: '{"project_id":"fb-proj"}' };
    expect(resolveVisionCredentials(env).credentials.project_id).toBe('fb-proj');
  });

  test('throws VISION_AUTH when nothing is configured', () => {
    expect(() => resolveVisionCredentials({})).toThrow(/VISION_AUTH|not configured/);
    try { resolveVisionCredentials({}); } catch (e) { expect(e.code).toBe('VISION_AUTH'); }
  });

  test('throws VISION_AUTH on unparseable JSON', () => {
    try {
      resolveVisionCredentials({ GOOGLE_CLOUD_VISION_CREDENTIALS_JSON: 'not json' });
      throw new Error('should have thrown');
    } catch (e) {
      expect(e.code).toBe('VISION_AUTH');
    }
  });
});

describe('recognizeWords', () => {
  const visionResponse = {
    fullTextAnnotation: {
      text: 'JEZL ANTOINETTE',
      pages: [{
        blocks: [{
          paragraphs: [{
            words: [
              {
                confidence: 0.93,
                boundingBox: { vertices: [{x:120,y:100},{x:180,y:100},{x:180,y:122},{x:120,y:122}] },
                symbols: [{ text: 'J' }, { text: 'E' }, { text: 'Z' }, { text: 'L' }],
              },
              {
                confidence: 0.71,
                boundingBox: { vertices: [{x:190,y:100},{x:300,y:100},{x:300,y:122},{x:190,y:122}] },
                symbols: 'ANTOINETTE'.split('').map((t) => ({ text: t })),
              },
            ],
          }],
        }],
      }],
    },
  };

  const fakeClient = (response) => ({ documentTextDetection: async () => [response] });

  test('normalizes words to text + vertices + confidence', async () => {
    const { words, fullText } = await recognizeWords(Buffer.from('x'), { client: fakeClient(visionResponse) });
    expect(fullText).toBe('JEZL ANTOINETTE');
    expect(words).toHaveLength(2);
    expect(words[0].text).toBe('JEZL');
    expect(words[0].confidence).toBeCloseTo(0.93);
    expect(words[0].vertices[0]).toEqual({ x: 120, y: 100 });
    expect(words[1].text).toBe('ANTOINETTE');
  });

  test('throws NO_TEXT_FOUND on an empty annotation', async () => {
    try {
      await recognizeWords(Buffer.from('x'), { client: fakeClient({}) });
      throw new Error('should have thrown');
    } catch (e) {
      expect(e.code).toBe('NO_TEXT_FOUND');
    }
  });

  test('maps a quota error to VISION_QUOTA', async () => {
    const client = { documentTextDetection: async () => { const e = new Error('quota'); e.code = 8; throw e; } };
    try {
      await recognizeWords(Buffer.from('x'), { client });
      throw new Error('should have thrown');
    } catch (e) {
      expect(e.code).toBe('VISION_QUOTA');
    }
  });

  test('maps an auth error to VISION_AUTH', async () => {
    const client = { documentTextDetection: async () => { const e = new Error('denied'); e.code = 7; throw e; } };
    try {
      await recognizeWords(Buffer.from('x'), { client });
      throw new Error('should have thrown');
    } catch (e) {
      expect(e.code).toBe('VISION_AUTH');
    }
  });

  test('maps anything else to VISION_UNAVAILABLE', async () => {
    const client = { documentTextDetection: async () => { throw new Error('socket hang up'); } };
    try {
      await recognizeWords(Buffer.from('x'), { client });
      throw new Error('should have thrown');
    } catch (e) {
      expect(e.code).toBe('VISION_UNAVAILABLE');
    }
  });
});

describe('defaultClient (production Vision client, lazily required)', () => {
  const env = { GOOGLE_CLOUD_VISION_CREDENTIALS_JSON: '{"project_id":"vision-proj"}' };

  afterEach(() => {
    jest.dontMock('@google-cloud/vision');
    jest.resetModules();
  });

  test('constructs ImageAnnotatorClient with the resolved credentials on first use', async () => {
    jest.resetModules();
    const documentTextDetection = jest
      .fn()
      .mockResolvedValue([{ fullTextAnnotation: { text: 'X', pages: [] } }]);
    jest.doMock('@google-cloud/vision', () => ({
      ImageAnnotatorClient: jest.fn().mockImplementation(() => ({ documentTextDetection })),
    }));

    const vision = require('@google-cloud/vision');
    const { recognizeWords: recognizeWordsIsolated } = require('./baptismal_ocr_service');

    // No text annotation with words survives normalization, so this still
    // rejects (NO_TEXT_FOUND) — irrelevant here; we only assert on how the
    // client was constructed.
    await expect(recognizeWordsIsolated(Buffer.from('x'), { env })).rejects.toMatchObject({
      code: 'NO_TEXT_FOUND',
    });

    expect(vision.ImageAnnotatorClient).toHaveBeenCalledTimes(1);
    expect(vision.ImageAnnotatorClient).toHaveBeenCalledWith({
      credentials: { project_id: 'vision-proj' },
    });
  });

  test('reuses the cached client on a second call instead of constructing again', async () => {
    jest.resetModules();
    const documentTextDetection = jest
      .fn()
      .mockResolvedValue([{ fullTextAnnotation: { text: 'X', pages: [] } }]);
    jest.doMock('@google-cloud/vision', () => ({
      ImageAnnotatorClient: jest.fn().mockImplementation(() => ({ documentTextDetection })),
    }));

    const vision = require('@google-cloud/vision');
    const { recognizeWords: recognizeWordsIsolated } = require('./baptismal_ocr_service');

    await expect(recognizeWordsIsolated(Buffer.from('x'), { env })).rejects.toMatchObject({
      code: 'NO_TEXT_FOUND',
    });
    await expect(recognizeWordsIsolated(Buffer.from('x'), { env })).rejects.toMatchObject({
      code: 'NO_TEXT_FOUND',
    });

    expect(vision.ImageAnnotatorClient).toHaveBeenCalledTimes(1);
  });
});
