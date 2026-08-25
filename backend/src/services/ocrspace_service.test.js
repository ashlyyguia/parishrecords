const { overlayToCells, callOcrSpace } = require('./ocrspace_service');

describe('overlayToCells', () => {
  test('maps word overlay to cells and text', () => {
    const sample = {
      ParsedResults: [
        {
          ParsedText: 'ALBERTO SALIGUMBA',
          TextOverlay: {
            Lines: [
              {
                Words: [
                  { WordText: 'ALBERTO', Left: 120, Top: 100, Width: 80, Height: 20 },
                  { WordText: 'SALIGUMBA', Left: 210, Top: 100, Width: 90, Height: 20 },
                ],
              },
            ],
          },
        },
      ],
    };
    const { text, cells } = overlayToCells(sample);
    expect(text).toBe('ALBERTO SALIGUMBA');
    expect(cells).toHaveLength(2);
    expect(cells[0]).toEqual({ text: 'ALBERTO', left: 120, top: 100, width: 80, height: 20 });
  });

  test('handles missing overlay and empty words', () => {
    expect(overlayToCells({}).cells).toEqual([]);
    expect(overlayToCells({ ParsedResults: [{ ParsedText: 'x' }] })).toEqual({ text: 'x', cells: [] });
    const blank = { ParsedResults: [{ TextOverlay: { Lines: [{ Words: [{ WordText: '  ', Left: 1, Top: 1, Width: 1, Height: 1 }] }] } }] };
    expect(overlayToCells(blank).cells).toEqual([]);
  });
});

describe('callOcrSpace', () => {
  test('posts required params and returns parsed json', async () => {
    let captured;
    const fakeFetch = async (url, opts) => {
      captured = { url, opts };
      return { ok: true, json: async () => ({ ParsedResults: [{ ParsedText: 'ok' }] }) };
    };
    const json = await callOcrSpace('BASE64DATA', { apiKey: 'K', fetchImpl: fakeFetch });
    expect(json.ParsedResults[0].ParsedText).toBe('ok');
    expect(captured.url).toContain('ocr.space');
    expect(captured.opts.body).toContain('apikey=K');
    expect(captured.opts.body).toContain('OCREngine=2');
    expect(captured.opts.body).toContain('isOverlayRequired=true');
  });

  test('honors an explicit engine and defaults to 2', async () => {
    const bodies = [];
    const fakeFetch = async (url, opts) => {
      bodies.push(opts.body);
      return { ok: true, json: async () => ({ ParsedResults: [{ ParsedText: 'ok' }] }) };
    };
    await callOcrSpace('X', { apiKey: 'K', fetchImpl: fakeFetch, engine: '1' });
    await callOcrSpace('X', { apiKey: 'K', fetchImpl: fakeFetch });
    expect(bodies[0]).toContain('OCREngine=1');
    expect(bodies[1]).toContain('OCREngine=2');
  });

  test('throws on processing error', async () => {
    const fakeFetch = async () => ({ ok: true, json: async () => ({ IsErroredOnProcessing: true, ErrorMessage: ['bad'] }) });
    await expect(callOcrSpace('X', { apiKey: 'K', fetchImpl: fakeFetch })).rejects.toThrow('bad');
  });

  test('throws when apiKey missing', async () => {
    await expect(callOcrSpace('X', { fetchImpl: async () => ({}) })).rejects.toThrow('OCRSPACE_API_KEY');
  });
});
