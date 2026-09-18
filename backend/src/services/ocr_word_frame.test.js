const { rescaleWordsToGrid } = require('./ocr_word_frame');

// Each word carries box vertices in the pixel frame OCR ran on. When the page
// was downscaled for OCR (preprocessForOcr maxEdge), that frame is smaller than
// the CV grid's cell frame, so vertices must be scaled back up before a word can
// be tested against a cell.
const word = (text, x, y) => ({
  text,
  vertices: [
    { x, y }, { x: x + 10, y }, { x: x + 10, y: y + 4 }, { x, y: y + 4 },
  ],
});

describe('rescaleWordsToGrid', () => {
  test('scales word vertices from the prepped frame up into the grid frame', () => {
    const words = [word('JOHN', 800, 1250)];
    const gridPage = { width: 1971, height: 3048 };
    const preppedDims = { width: 1617, height: 2500 }; // downscaled by ~0.82

    const [out] = rescaleWordsToGrid(words, gridPage, preppedDims);

    const sx = 1971 / 1617;
    const sy = 3048 / 2500;
    expect(out.vertices[0].x).toBeCloseTo(800 * sx, 5);
    expect(out.vertices[0].y).toBeCloseTo(1250 * sy, 5);
    expect(out.text).toBe('JOHN'); // other fields preserved
  });

  test('returns words unchanged when the prepped frame equals the grid frame', () => {
    const words = [word('MERA', 100, 200)];
    const gridPage = { width: 2000, height: 2400 };
    const out = rescaleWordsToGrid(words, gridPage, { width: 2000, height: 2400 });
    expect(out[0].vertices).toEqual(words[0].vertices);
  });

  test('returns words unchanged when the prepped dimensions are unknown', () => {
    // preprocessForOcr fell back to the original (e.g. sharp unavailable): no
    // resize happened, so the words are already in the grid frame.
    const words = [word('AMOR', 50, 60)];
    const gridPage = { width: 2000, height: 2400 };
    expect(rescaleWordsToGrid(words, gridPage, null)[0].vertices).toEqual(words[0].vertices);
  });
});
