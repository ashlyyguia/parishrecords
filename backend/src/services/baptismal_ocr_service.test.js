const { recognizeWords } = require('./baptismal_ocr_service');

// OCR.space overlay response with two words on one line.
const okResponse = {
  ParsedResults: [
    {
      ParsedText: 'TESTA SAMPLE',
      TextOverlay: {
        Lines: [
          {
            Words: [
              { WordText: 'TESTA', Left: 120, Top: 100, Width: 60, Height: 22 },
              { WordText: 'SAMPLE', Left: 190, Top: 100, Width: 90, Height: 22 },
            ],
          },
        ],
      },
    },
  ],
};

const fetchReturning = (json, ok = true) => async () => ({ ok, status: ok ? 200 : 500, json: async () => json });

describe('recognizeWords (OCR.space)', () => {
  test('normalizes overlay words to text + TL,TR,BR,BL vertices + confidence 1', async () => {
    const { words, fullText } = await recognizeWords(Buffer.from('x'), {
      apiKey: 'K', env: {}, fetchImpl: fetchReturning(okResponse),
    });
    expect(fullText).toBe('TESTA SAMPLE');
    expect(words).toHaveLength(2);
    expect(words[0].text).toBe('TESTA');
    expect(words[0].confidence).toBe(1);
    // Axis-aligned box (L,T,W,H) -> TL,TR,BR,BL.
    expect(words[0].vertices).toEqual([
      { x: 120, y: 100 }, { x: 180, y: 100 }, { x: 180, y: 122 }, { x: 120, y: 122 },
    ]);
  });

  test('throws NO_TEXT_FOUND when the overlay has no words', async () => {
    const empty = { ParsedResults: [{ ParsedText: '' }] };
    await expect(
      recognizeWords(Buffer.from('x'), { apiKey: 'K', env: {}, fetchImpl: fetchReturning(empty) }),
    ).rejects.toMatchObject({ code: 'NO_TEXT_FOUND' });
  });

  test('throws OCR_AUTH when no key is configured', async () => {
    await expect(
      recognizeWords(Buffer.from('x'), { env: {}, fetchImpl: fetchReturning(okResponse) }),
    ).rejects.toMatchObject({ code: 'OCR_AUTH' });
  });

  test('maps an OCR.space rate-limit message to OCR_QUOTA', async () => {
    const errJson = { IsErroredOnProcessing: true, ErrorMessage: ['You have exceeded your concurrent connections / rate limit'] };
    await expect(
      recognizeWords(Buffer.from('x'), { apiKey: 'K', env: {}, fetchImpl: fetchReturning(errJson) }),
    ).rejects.toMatchObject({ code: 'OCR_QUOTA' });
  });

  test('maps a network failure to OCR_UNAVAILABLE', async () => {
    const fetchImpl = async () => { throw new Error('socket hang up'); };
    await expect(
      recognizeWords(Buffer.from('x'), { apiKey: 'K', env: {}, fetchImpl }),
    ).rejects.toMatchObject({ code: 'OCR_UNAVAILABLE' });
  });

  test('maps an HTTP error to OCR_UNAVAILABLE', async () => {
    await expect(
      recognizeWords(Buffer.from('x'), { apiKey: 'K', env: {}, fetchImpl: fetchReturning({}, false) }),
    ).rejects.toMatchObject({ code: 'OCR_UNAVAILABLE' });
  });
});
