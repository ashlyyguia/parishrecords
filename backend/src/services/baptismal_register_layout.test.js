const { boxOf, normalizeOrientation } = require('./baptismal_register_layout');
const { buildRegisterFixture } = require('../../test/helpers/register_fixture');

describe('boxOf', () => {
  test('returns the axis-aligned bounds and center', () => {
    const w = {
      text: 'X',
      vertices: [{ x: 10, y: 20 }, { x: 30, y: 20 }, { x: 30, y: 40 }, { x: 10, y: 40 }],
      confidence: 1,
    };
    expect(boxOf(w)).toEqual({ x0: 10, y0: 20, x1: 30, y1: 40, cx: 20, cy: 30, w: 20, h: 20 });
  });
});

describe('normalizeOrientation', () => {
  test('leaves an upright page alone', () => {
    const { words } = buildRegisterFixture({ rotation: 0 });
    const out = normalizeOrientation(words);
    expect(out.rotation).toBe(0);
  });

  for (const rotation of [90, 180, 270]) {
    test(`recovers a page rotated ${rotation} degrees`, () => {
      const upright = normalizeOrientation(buildRegisterFixture({ rotation: 0 }).words);
      const rotated = normalizeOrientation(buildRegisterFixture({ rotation }).words);

      // Same reading frame: the header row must sit above the first data row,
      // and 'NO.' must be leftmost, exactly as in the upright page.
      const headerOf = (out, text) => out.words.find((w) => w.text === text);
      expect(boxOf(headerOf(rotated, 'NO.')).cy).toBeLessThan(
        boxOf(headerOf(rotated, 'JEZL')).cy,
      );
      expect(boxOf(headerOf(rotated, 'NO.')).cx).toBeLessThan(
        boxOf(headerOf(rotated, 'JEZL')).cx,
      );
      expect(rotated.words).toHaveLength(upright.words.length);
    });
  }
});
