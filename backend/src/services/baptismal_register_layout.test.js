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

/** Finds the word with the given exact text; throws if absent or ambiguous. */
function wordNamed(out, text) {
  const matches = out.words.filter((w) => w.text === text);
  if (matches.length !== 1) {
    throw new Error(`expected exactly one word with text "${text}", found ${matches.length}`);
  }
  return matches[0];
}

// Column headers reduced to tokens that are unique per fixture (no 'NAME'/'OF'/
// 'DATE', which each appear in more than one header), listed in left-to-right
// column order. Used to assert x-ordering survives rotation + recovery.
const COLUMN_ORDER_ANCHORS = [
  'NO.', 'CHILD', 'PLACE', 'ILL', 'PARENTS', 'RESIDENTS', 'BAPTISM', 'MINISTER',
  'SPONSORS', 'OBSERVATIONS',
];

// The header row plus the first-column value of each data row (rowCount
// defaults to 3), in top-to-bottom order. Used to assert y-ordering survives
// rotation + recovery.
const ROW_ORDER_ANCHORS = ['NO.', '1', '2', '3'];

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

      // The detected rotation must actually match what was applied — this is
      // the thing normalizeOrientation exists to compute.
      expect(rotated.rotation).toBe(rotation);
      expect(rotated.words).toHaveLength(upright.words.length);

      // Real positional check, not just one header/data pair: the full
      // left-to-right column order and top-to-bottom row order recovered
      // from the rotated page must match the upright page exactly.
      const xOrder = (out) => COLUMN_ORDER_ANCHORS
        .map((text) => ({ text, cx: boxOf(wordNamed(out, text)).cx }))
        .sort((a, b) => a.cx - b.cx)
        .map((a) => a.text);
      const yOrder = (out) => ROW_ORDER_ANCHORS
        .map((text) => ({ text, cy: boxOf(wordNamed(out, text)).cy }))
        .sort((a, b) => a.cy - b.cy)
        .map((a) => a.text);

      expect(xOrder(rotated)).toEqual(xOrder(upright));
      expect(xOrder(rotated)).toEqual(COLUMN_ORDER_ANCHORS);
      expect(yOrder(rotated)).toEqual(yOrder(upright));
      expect(yOrder(rotated)).toEqual(ROW_ORDER_ANCHORS);
    });
  }

  test('recovered coordinates are content-relative, not source-image pixels', () => {
    // Pins the coordinate contract documented on normalizeOrientation: for a
    // rotated page, the inverse rotation is computed against the word
    // CONTENT's own bounding box, not true source-image page dimensions
    // (which this module never captures). That leaves recovered coordinates
    // offset from the literal source-image pixel position — returned by the
    // rotation:0 passthrough case — by exactly the content's margin. A later
    // consumer mapping these coordinates back onto the scanned image (e.g.
    // to draw a highlight box) must not assume they are source-image-accurate.
    const original = buildRegisterFixture({ rotation: 0 }).words;
    const marginX = Math.min(...original.flatMap((w) => w.vertices.map((v) => v.x)));
    const marginY = Math.min(...original.flatMap((w) => w.vertices.map((v) => v.y)));

    // Sanity: the fixture actually has a margin, so a zero offset below
    // wouldn't just be a coincidence of the geometry.
    expect(marginX).toBeGreaterThan(0);
    expect(marginY).toBeGreaterThan(0);

    const expectedOffset = {
      90: { dx: 0, dy: -marginY },
      180: { dx: -marginX, dy: -marginY },
      270: { dx: -marginX, dy: 0 },
    };

    for (const rotation of [90, 180, 270]) {
      const recovered = normalizeOrientation(buildRegisterFixture({ rotation }).words).words;
      const originalBox = boxOf(wordNamed({ words: original }, 'NO.'));
      const recoveredBox = boxOf(wordNamed({ words: recovered }, 'NO.'));
      const { dx, dy } = expectedOffset[rotation];

      expect(recoveredBox.cx).toBe(originalBox.cx + dx);
      expect(recoveredBox.cy).toBe(originalBox.cy + dy);
    }
  });
});
