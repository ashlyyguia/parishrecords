const {
  boxOf, normalizeOrientation, splitSpread, calibrateColumns, LEFT_COLUMNS, RIGHT_COLUMNS,
} = require('./baptismal_register_layout');
const { buildRegisterFixture, GUTTER_X0, GUTTER_X1 } = require('../../test/helpers/register_fixture');

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

describe('splitSpread', () => {
  test('finds the gutter and confirms it via the page titles', () => {
    const { words } = normalizeOrientation(buildRegisterFixture({ rotation: 0 }).words);
    const out = splitSpread(words);
    expect(out.gutterX).toBeGreaterThanOrEqual(GUTTER_X0 - 60);
    expect(out.gutterX).toBeLessThanOrEqual(GUTTER_X1 + 60);
    expect(out.confirmed).toBe(true);
    expect(out.left.some((w) => w.text === 'CHILD')).toBe(true);
    expect(out.right.some((w) => w.text === 'MINISTER')).toBe(true);
    expect(out.left.some((w) => w.text === 'MINISTER')).toBe(false);
  });

  test('splits correctly on a rotated page too', () => {
    const { words } = normalizeOrientation(buildRegisterFixture({ rotation: 180 }).words);
    const out = splitSpread(words);
    expect(out.left.some((w) => w.text === 'CHILD')).toBe(true);
    expect(out.right.some((w) => w.text === 'SPONSORS')).toBe(true);
  });

  test('reports unconfirmed when the page titles are missing', () => {
    const { words } = normalizeOrientation(buildRegisterFixture({ rotation: 0 }).words);
    const stripped = words.filter((w) => w.text !== 'Baptismal' && w.text !== 'Register');
    expect(splitSpread(stripped).confirmed).toBe(false);
  });
});

describe('calibrateColumns', () => {
  const pages = () => {
    const { words } = normalizeOrientation(buildRegisterFixture({ rotation: 0 }).words);
    return splitSpread(words);
  };

  test('matches every left-page header', () => {
    const { columns, warnings } = calibrateColumns(pages().left, LEFT_COLUMNS);
    expect(columns.map((c) => c.key)).toEqual([
      'lineNo', 'nameOfChild', 'placeAndBirthDate', 'legitimacy', 'parents',
    ]);
    expect(columns.every((c) => c.matched)).toBe(true);
    expect(warnings).toEqual([]);
  });

  test('matches every right-page header', () => {
    const { columns, warnings } = calibrateColumns(pages().right, RIGHT_COLUMNS);
    expect(columns.map((c) => c.key)).toEqual([
      'residentsOf', 'dateOfBaptism', 'minister', 'sponsors', 'observations',
    ]);
    expect(columns.every((c) => c.matched)).toBe(true);
    expect(warnings).toEqual([]);
  });

  test('produces bands in ascending, non-overlapping order', () => {
    const { columns } = calibrateColumns(pages().left, LEFT_COLUMNS);
    for (let i = 1; i < columns.length; i += 1) {
      expect(columns[i].x0).toBeGreaterThanOrEqual(columns[i - 1].x1 - 0.001);
    }
  });

  test('falls back and warns when a header is unreadable', () => {
    const { words } = normalizeOrientation(
      buildRegisterFixture({ rotation: 0, omitHeaders: ['L or ILL'] }).words,
    );
    const { columns, warnings } = calibrateColumns(splitSpread(words).left, LEFT_COLUMNS);
    expect(warnings).toContain('LAYOUT_UNCERTAIN');
    expect(columns.find((c) => c.key === 'legitimacy').matched).toBe(false);
    expect(columns).toHaveLength(5);
  });

  test('warns when no header matches at all', () => {
    const { warnings } = calibrateColumns([], LEFT_COLUMNS);
    expect(warnings).toContain('LAYOUT_UNCERTAIN');
  });

  // Regression: matching on 'name' hits both "NAME OF CHILD" and "NAME OF
  // PARENTS", averaging them into a center over the birth-date column.
  test('does not let the parents header drag the child-name column right', () => {
    const { columns } = calibrateColumns(pages().left, LEFT_COLUMNS);
    const name = columns.find((c) => c.key === 'nameOfChild');
    const place = columns.find((c) => c.key === 'placeAndBirthDate');
    expect(name.x1).toBeLessThanOrEqual(place.x0 + 0.001);
    // The child's given name sits at x=160 in the fixture; it must land in the
    // name column, not in lineNo or place.
    expect(160).toBeGreaterThanOrEqual(name.x0);
    expect(160).toBeLessThan(name.x1);
  });
});
