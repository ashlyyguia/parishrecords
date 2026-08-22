const {
  boxOf, normalizeOrientation, splitSpread, calibrateColumns, LEFT_COLUMNS, RIGHT_COLUMNS,
} = require('./baptismal_register_layout');
const {
  buildRegisterFixture, GUTTER_X0, GUTTER_X1, FIRST_ROW_Y, ROW_H,
} = require('../../test/helpers/register_fixture');

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
    // The child's given name sits at x=160 in the fixture; it must land in the
    // name column, not in lineNo or place.
    expect(160).toBeGreaterThanOrEqual(name.x0);
    expect(160).toBeLessThan(name.x1);
  });

  // Critical 1: a header-only page (no data rows below it — a blank/unfilled
  // register page, or a photo cropped tight to the header row) has no
  // header-to-data gap for a naive gap-sweep to find. The boundary must
  // still land below the header row, never above it.
  test('matches every header on a page with no data rows below them', () => {
    const { words } = normalizeOrientation(buildRegisterFixture({ rotation: 0, rows: 0 }).words);
    const { left, right } = splitSpread(words);
    const leftResult = calibrateColumns(left, LEFT_COLUMNS);
    const rightResult = calibrateColumns(right, RIGHT_COLUMNS);
    expect(leftResult.columns.every((c) => c.matched)).toBe(true);
    expect(leftResult.warnings).toEqual([]);
    expect(rightResult.columns.every((c) => c.matched)).toBe(true);
    expect(rightResult.warnings).toEqual([]);
  });

  test('matches every header on a page with exactly one data row', () => {
    const { words } = normalizeOrientation(buildRegisterFixture({ rotation: 0, rows: 1 }).words);
    const { left, right } = splitSpread(words);
    const leftResult = calibrateColumns(left, LEFT_COLUMNS);
    const rightResult = calibrateColumns(right, RIGHT_COLUMNS);
    expect(leftResult.columns.every((c) => c.matched)).toBe(true);
    expect(leftResult.warnings).toEqual([]);
    expect(rightResult.columns.every((c) => c.matched)).toBe(true);
    expect(rightResult.warnings).toEqual([]);
  });

  test('matches every header on a header-only page with no page titles either', () => {
    const { words } = normalizeOrientation(
      buildRegisterFixture({ rotation: 0, rows: 0 }).words.filter(
        (w) => w.text !== 'Baptismal' && w.text !== 'Register',
      ),
    );
    const { left } = splitSpread(words);
    const { columns, warnings } = calibrateColumns(left, LEFT_COLUMNS);
    expect(columns.every((c) => c.matched)).toBe(true);
    expect(warnings).toEqual([]);
  });

  // Critical 2: a missed header's fallback center is a fraction of page
  // width. A stray word far outside the normal content area (e.g. an
  // overflowing observations note) inflates that width and can push the
  // fallback past a correctly matched neighbour's real position, inverting
  // the band between them so words falling in it match no column at all.
  test('clamps an inverted band caused by a missed header plus a stray far-right word', () => {
    const built = buildRegisterFixture({ rotation: 0, omitHeaders: ['MINISTER'] });
    const strayWord = {
      text: 'OVERFLOWNOTE',
      vertices: [
        { x: 2400, y: 300 }, { x: 2600, y: 300 },
        { x: 2600, y: 322 }, { x: 2400, y: 322 },
      ],
      confidence: 0.9,
    };
    const { words } = normalizeOrientation([...built.words, strayWord]);
    const { columns, warnings } = calibrateColumns(splitSpread(words).right, RIGHT_COLUMNS);

    expect(warnings).toContain('LAYOUT_UNCERTAIN');
    expect(columns.find((c) => c.key === 'minister').matched).toBe(false);

    // No band may invert or collapse: every column's x1 must exceed its x0,
    // and bands must stay in ascending order left-to-right no matter how far
    // the unmatched column's fallback would otherwise have been pushed.
    for (const c of columns) {
      expect(c.x1).toBeGreaterThan(c.x0);
    }
    for (let i = 1; i < columns.length; i += 1) {
      expect(columns[i].x0).toBeGreaterThanOrEqual(columns[i - 1].x1 - 0.001);
    }
  });

  // Important 3: real handwritten registers have uneven row spacing. The
  // header/data boundary must come from the header row's own position, not
  // from "the widest gap anywhere on the page" — otherwise a wide inter-row
  // gap further down can pull the boundary into the data region and let a
  // stray data word masquerade as a header.
  test('does not let a wide inter-row gap pull the header boundary into the data region', () => {
    const built = buildRegisterFixture({ rotation: 0, rows: 3 });
    const rowThreeCy = FIRST_ROW_Y + 2 * ROW_H;
    const SHIFT = 1000;

    // Baseline: real header centers with normal (even) row spacing, no decoy.
    const baseline = calibrateColumns(
      splitSpread(normalizeOrientation(built.words).words).left, LEFT_COLUMNS,
    );
    const baselineParents = baseline.columns.find((c) => c.key === 'parents');

    // Push row 3 far down the page: the row2->row3 gap (~1000px) now dwarfs
    // the real header->row1 gap (~78px) -- deliberately uneven spacing, as a
    // real handwritten register would have.
    const shiftedWords = built.words.map((w) => {
      const b = boxOf(w);
      if (b.cy !== rowThreeCy) return w;
      return { ...w, vertices: w.vertices.map((v) => ({ x: v.x, y: v.y + SHIFT })) };
    });

    // A decoy word reading "PARENTS", sitting in what is now a huge gap
    // between row 2 and the shifted row 3. If the boundary were (wrongly)
    // pulled down into that gap, this decoy would count as a second
    // "parents" header hit and drag the column's center off the real header.
    const decoy = {
      text: 'PARENTS',
      vertices: [
        { x: 384, y: 300 }, { x: 447, y: 300 }, { x: 447, y: 322 }, { x: 384, y: 322 },
      ],
      confidence: 0.9,
    };

    const { words } = normalizeOrientation([...shiftedWords, decoy]);
    const { columns, warnings } = calibrateColumns(splitSpread(words).left, LEFT_COLUMNS);
    const parents = columns.find((c) => c.key === 'parents');

    expect(parents.matched).toBe(true);
    expect(warnings).toEqual([]);
    // The decoy must not have been folded into the header average: the band
    // stays anchored to the real header regardless of the later uneven gap.
    expect(Math.abs(parents.x0 - baselineParents.x0)).toBeLessThan(2);
    expect(Math.abs(parents.x1 - baselineParents.x1)).toBeLessThan(2);
  });

  // Round-2 finding: the forward-monotonic safety net that used to follow
  // the per-column neighbour clamp applied unconditionally to EVERY center,
  // including matched ones, even though its own comment claimed to leave
  // "matched (trustworthy) centers untouched". Two-or-more adjacent
  // unmatched columns could clamp to the same value and tie; the old
  // forward nudge broke that tie by pushing later centers ahead, and the
  // push could cascade into the next MATCHED column's own detected center.
  // These tests build synthetic column defs (not LEFT_COLUMNS/RIGHT_COLUMNS,
  // which stay untouched) so header presence/absence — and therefore which
  // columns are matched vs. unmatched — is fully controlled, independent of
  // the protected register fixture's geometry.
  describe('unmatched-run tie-breaking (round-2 regression)', () => {
    // Eight generic columns, spaced 150px apart, is enough room to carve out
    // runs of unmatched columns of any length/position needed below. Each
    // header token is single-word and unique, so a present header word's own
    // cx becomes its exactly-known matched center.
    const SYNTH_COLUMNS = [
      { key: 'colA', header: ['alpha'], fallbackRatio: 0.05 },
      { key: 'colB', header: ['beta'], fallbackRatio: 0.20 },
      { key: 'colC', header: ['gamma'], fallbackRatio: 0.35 },
      { key: 'colD', header: ['delta'], fallbackRatio: 0.50 },
      { key: 'colE', header: ['epsilon'], fallbackRatio: 0.65 },
      { key: 'colF', header: ['zeta'], fallbackRatio: 0.80 },
      { key: 'colG', header: ['eta'], fallbackRatio: 0.90 },
    ];
    const SYNTH_CX = {
      colA: 100, colB: 250, colC: 400, colD: 550, colE: 700, colF: 850, colG: 1000,
    };

    function makeWord(text, cx, cy = 100) {
      const w = 60;
      const h = 22;
      return {
        text,
        vertices: [
          { x: cx - w / 2, y: cy - h / 2 }, { x: cx + w / 2, y: cy - h / 2 },
          { x: cx + w / 2, y: cy + h / 2 }, { x: cx - w / 2, y: cy + h / 2 },
        ],
        confidence: 0.9,
      };
    }

    /** Builds a header-only page with only the given column keys' header
     * words present; the rest are omitted so they're genuinely unmatched. */
    function buildSynthPage(presentKeys, extraWords = []) {
      const words = SYNTH_COLUMNS
        .filter((def) => presentKeys.includes(def.key))
        .map((def) => makeWord(def.header[0].toUpperCase(), SYNTH_CX[def.key]));
      return [...words, ...extraWords];
    }

    function assertNoInvertedOrZeroWidthBands(columns) {
      for (const c of columns) {
        expect(c.x1).toBeGreaterThan(c.x0);
      }
      for (let i = 1; i < columns.length; i += 1) {
        expect(columns[i].x0).toBeGreaterThanOrEqual(columns[i - 1].x1 - 0.001);
      }
    }

    test('two adjacent unmatched columns between two matched ones never move a matched center', () => {
      // colA,colB matched | colC,colD unmatched (the run) | colE,colF matched.
      const defs = SYNTH_COLUMNS.slice(0, 6);
      const words = buildSynthPage(['colA', 'colB', 'colE', 'colF']);
      const { columns, warnings } = calibrateColumns(words, defs);
      const byKey = Object.fromEntries(columns.map((c) => [c.key, c]));

      expect(warnings).toContain('LAYOUT_UNCERTAIN');
      expect(byKey.colA.matched).toBe(true);
      expect(byKey.colB.matched).toBe(true);
      expect(byKey.colC.matched).toBe(false);
      expect(byKey.colD.matched).toBe(false);
      expect(byKey.colE.matched).toBe(true);
      expect(byKey.colF.matched).toBe(true);

      // The shared boundary between two ADJACENT MATCHED columns is a pure
      // function of their own declared header cx values (midpoint), with no
      // dependency on anything in the unmatched run — so this independently
      // proves neither center was moved, without re-deriving the
      // redistribution math the implementation itself uses.
      expect(byKey.colA.x1).toBeCloseTo((SYNTH_CX.colA + SYNTH_CX.colB) / 2, 6);
      expect(byKey.colB.x0).toBeCloseTo((SYNTH_CX.colA + SYNTH_CX.colB) / 2, 6);
      expect(byKey.colE.x1).toBeCloseTo((SYNTH_CX.colE + SYNTH_CX.colF) / 2, 6);
      expect(byKey.colF.x0).toBeCloseTo((SYNTH_CX.colE + SYNTH_CX.colF) / 2, 6);

      assertNoInvertedOrZeroWidthBands(columns);
    });

    test('three adjacent unmatched columns never move a matched center', () => {
      // colA,colB matched | colC,colD,colE unmatched (the run) | colF,colG matched.
      const defs = SYNTH_COLUMNS;
      const words = buildSynthPage(['colA', 'colB', 'colF', 'colG']);
      const { columns, warnings } = calibrateColumns(words, defs);
      const byKey = Object.fromEntries(columns.map((c) => [c.key, c]));

      expect(warnings).toContain('LAYOUT_UNCERTAIN');
      expect(byKey.colA.matched).toBe(true);
      expect(byKey.colB.matched).toBe(true);
      expect(byKey.colC.matched).toBe(false);
      expect(byKey.colD.matched).toBe(false);
      expect(byKey.colE.matched).toBe(false);
      expect(byKey.colF.matched).toBe(true);
      expect(byKey.colG.matched).toBe(true);

      expect(byKey.colA.x1).toBeCloseTo((SYNTH_CX.colA + SYNTH_CX.colB) / 2, 6);
      expect(byKey.colB.x0).toBeCloseTo((SYNTH_CX.colA + SYNTH_CX.colB) / 2, 6);
      expect(byKey.colF.x1).toBeCloseTo((SYNTH_CX.colF + SYNTH_CX.colG) / 2, 6);
      expect(byKey.colG.x0).toBeCloseTo((SYNTH_CX.colF + SYNTH_CX.colG) / 2, 6);

      assertNoInvertedOrZeroWidthBands(columns);
    });

    test('the first column unmatched never moves the matched columns after it', () => {
      // colA unmatched (leftmost) | colB,colC matched.
      const defs = SYNTH_COLUMNS.slice(0, 3);
      const words = buildSynthPage(['colB', 'colC']);
      const { columns, warnings } = calibrateColumns(words, defs);
      const byKey = Object.fromEntries(columns.map((c) => [c.key, c]));

      expect(warnings).toContain('LAYOUT_UNCERTAIN');
      expect(byKey.colA.matched).toBe(false);
      expect(byKey.colB.matched).toBe(true);
      expect(byKey.colC.matched).toBe(true);

      expect(byKey.colB.x1).toBeCloseTo((SYNTH_CX.colB + SYNTH_CX.colC) / 2, 6);
      expect(byKey.colC.x0).toBeCloseTo((SYNTH_CX.colB + SYNTH_CX.colC) / 2, 6);

      assertNoInvertedOrZeroWidthBands(columns);
    });

    test('the last column unmatched never moves the matched columns before it', () => {
      // colA,colB matched | colC unmatched (rightmost).
      const defs = SYNTH_COLUMNS.slice(0, 3);
      const words = buildSynthPage(['colA', 'colB']);
      const { columns, warnings } = calibrateColumns(words, defs);
      const byKey = Object.fromEntries(columns.map((c) => [c.key, c]));

      expect(warnings).toContain('LAYOUT_UNCERTAIN');
      expect(byKey.colA.matched).toBe(true);
      expect(byKey.colB.matched).toBe(true);
      expect(byKey.colC.matched).toBe(false);

      expect(byKey.colA.x1).toBeCloseTo((SYNTH_CX.colA + SYNTH_CX.colB) / 2, 6);
      expect(byKey.colB.x0).toBeCloseTo((SYNTH_CX.colA + SYNTH_CX.colB) / 2, 6);

      assertNoInvertedOrZeroWidthBands(columns);
    });

    test('all columns unmatched still produces valid, ascending, non-degenerate bands', () => {
      const defs = SYNTH_COLUMNS.slice(0, 4);
      // No header words present at all; filler words (matching no column
      // token) establish a page width for calibrateColumns to work with.
      const filler = [makeWord('FILLER', 50, 400), makeWord('FILLER', 1200, 400)];
      const words = buildSynthPage([], filler);
      const { columns, warnings } = calibrateColumns(words, defs);

      expect(warnings).toContain('LAYOUT_UNCERTAIN');
      expect(columns.every((c) => !c.matched)).toBe(true);
      assertNoInvertedOrZeroWidthBands(columns);
    });
  });

  // Round-3 finding: the round-2 fix's degenerate-interval branch (matched
  // anchors too close together for MIN_GAP-spaced distinct centers) stepped
  // from `lo` by MIN_GAP per unmatched column without ever comparing against
  // `hi`, so a narrow-but-nonzero interval could still overshoot the next
  // matched anchor and invert the band between them -- reintroducing the
  // exact "words match no column and vanish silently" failure the guard
  // exists to prevent, just relocated to a smaller interval than round 2's
  // fix was tested against. The fix replaces the two-branch (degenerate vs.
  // spacious) logic with one formula that can never step outside [lo, hi].
  describe('degenerate interval handling (round-3 regression)', () => {
    function makeWord(text, cx, cy = 100) {
      const w = 60;
      const h = 22;
      return {
        text,
        vertices: [
          { x: cx - w / 2, y: cy - h / 2 }, { x: cx + w / 2, y: cy - h / 2 },
          { x: cx + w / 2, y: cy + h / 2 }, { x: cx - w / 2, y: cy + h / 2 },
        ],
        confidence: 0.9,
      };
    }

    // colZ/colF are matched columns adjacent to another matched column
    // (colA/colE respectively) on the far side from the run under test. The
    // boundary between two ADJACENT matched columns is a pure function of
    // their own declared cx values (the redistribution loop never runs
    // there), so checking colZ.x1/colA.x0 and colE.x1/colF.x0 against that
    // midpoint independently proves colA's and colE's centers are exactly
    // what was detected -- unmoved by whatever the run between them did.
    const DEFS = [
      { key: 'colZ', header: ['zulu'], fallbackRatio: 0.01 },
      { key: 'colA', header: ['alpha'], fallbackRatio: 0.10 },
      { key: 'colB', header: ['beta'], fallbackRatio: 0.30 },
      { key: 'colC', header: ['gamma'], fallbackRatio: 0.50 },
      { key: 'colD', header: ['delta'], fallbackRatio: 0.70 },
      { key: 'colE', header: ['epsilon'], fallbackRatio: 0.90 },
      { key: 'colF', header: ['foxtrot'], fallbackRatio: 0.99 },
    ];
    const COL_Z_CX = 0;
    const COL_F_CX = 10000;

    /** Builds the colZ..colF page with colA at `cxA`, colE at `cxE`, and
     * colB/colC/colD (the run under test) genuinely unmatched. */
    function buildPage(cxA, cxE) {
      return [
        makeWord('ZULU', COL_Z_CX),
        makeWord('ALPHA', cxA),
        makeWord('EPSILON', cxE),
        makeWord('FOXTROT', COL_F_CX),
      ];
    }

    function byKeyOf(columns) {
      return Object.fromEntries(columns.map((c) => [c.key, c]));
    }

    test('reviewer repro: two matched anchors 1px apart with three unmatched columns between them', () => {
      const { columns, warnings } = calibrateColumns(buildPage(100, 101), DEFS);
      const byKey = byKeyOf(columns);

      expect(warnings).toContain('LAYOUT_UNCERTAIN');
      expect(byKey.colB.matched).toBe(false);
      expect(byKey.colC.matched).toBe(false);
      expect(byKey.colD.matched).toBe(false);

      // colA and colE's own detected centers are exactly 100 and 101 --
      // unmoved by the run between them.
      expect(byKey.colZ.x1).toBeCloseTo((COL_Z_CX + 100) / 2, 9);
      expect(byKey.colA.x0).toBeCloseTo((COL_Z_CX + 100) / 2, 9);
      expect(byKey.colE.x1).toBeCloseTo((101 + COL_F_CX) / 2, 9);
      expect(byKey.colF.x0).toBeCloseTo((101 + COL_F_CX) / 2, 9);

      for (const c of columns) {
        expect(c.x1).toBeGreaterThanOrEqual(c.x0);
      }
      for (let i = 1; i < columns.length; i += 1) {
        expect(columns[i].x0).toBeGreaterThanOrEqual(columns[i - 1].x1 - 1e-9);
      }
    });

    test('zero-width interval: two matched anchors at the same x with unmatched columns between them', () => {
      const { columns, warnings } = calibrateColumns(buildPage(500, 500), DEFS);
      const byKey = byKeyOf(columns);

      expect(warnings).toContain('LAYOUT_UNCERTAIN');

      // colA and colE's own detected centers are exactly 500 -- unmoved.
      expect(byKey.colZ.x1).toBeCloseTo((COL_Z_CX + 500) / 2, 9);
      expect(byKey.colA.x0).toBeCloseTo((COL_Z_CX + 500) / 2, 9);
      expect(byKey.colE.x1).toBeCloseTo((500 + COL_F_CX) / 2, 9);
      expect(byKey.colF.x0).toBeCloseTo((500 + COL_F_CX) / 2, 9);

      // A genuinely zero-width interval collapses the run's bands to zero
      // width too -- honest and acceptable, unlike an inverted band.
      expect(byKey.colB.x0).toBeCloseTo(500, 9);
      expect(byKey.colB.x1).toBeCloseTo(500, 9);
      expect(byKey.colC.x0).toBeCloseTo(500, 9);
      expect(byKey.colC.x1).toBeCloseTo(500, 9);
      expect(byKey.colD.x0).toBeCloseTo(500, 9);
      expect(byKey.colD.x1).toBeCloseTo(500, 9);

      for (const c of columns) {
        expect(c.x1).toBeGreaterThanOrEqual(c.x0);
      }
      for (let i = 1; i < columns.length; i += 1) {
        expect(columns[i].x0).toBeGreaterThanOrEqual(columns[i - 1].x1 - 1e-9);
      }
    });

    // Pins the boundary between "degenerate" and "spacious" that round 2's
    // two-branch logic drew at `hi - lo <= runLength * MIN_GAP` (MIN_GAP=1,
    // runLength=3, so the old threshold sat at an interval width of 3). This
    // interval is just above that -- round 2 would have taken the spacious
    // branch here, so this alone wouldn't have caught the round-2 bug, but it
    // pins that both sides of the old branch split now produce the same kind
    // of well-formed, non-inverted result via the single unified formula.
    test('narrow-but-not-degenerate interval just above the old branch threshold', () => {
      const { columns, warnings } = calibrateColumns(buildPage(100, 103.5), DEFS);
      const byKey = byKeyOf(columns);

      expect(warnings).toContain('LAYOUT_UNCERTAIN');
      expect(byKey.colZ.x1).toBeCloseTo((COL_Z_CX + 100) / 2, 9);
      expect(byKey.colA.x0).toBeCloseTo((COL_Z_CX + 100) / 2, 9);
      expect(byKey.colE.x1).toBeCloseTo((103.5 + COL_F_CX) / 2, 9);
      expect(byKey.colF.x0).toBeCloseTo((103.5 + COL_F_CX) / 2, 9);

      for (const c of columns) {
        expect(c.x1).toBeGreaterThanOrEqual(c.x0);
      }
      for (let i = 1; i < columns.length; i += 1) {
        expect(columns[i].x0).toBeGreaterThanOrEqual(columns[i - 1].x1 - 1e-9);
      }
    });
  });

  // Property-style sweep: rather than one synthetic layout at a time, vary
  // BOTH which columns are matched and how far apart the matched anchors sit
  // (0px coincident, 1px reviewer-repro-scale, 150px wide) across a table of
  // cases, and check the same invariants hold for every one of them. This is
  // the generalized version of the three regressions above -- the point is
  // to stop re-deriving one specific inverted-band scenario at a time.
  describe('band invariants hold across synthetic layouts (property-style)', () => {
    const TOKENS = ['aaa', 'bbb', 'ccc', 'ddd', 'eee'];

    function makeWord(text, cx, cy = 100) {
      const w = 60;
      const h = 22;
      return {
        text,
        vertices: [
          { x: cx - w / 2, y: cy - h / 2 }, { x: cx + w / 2, y: cy - h / 2 },
          { x: cx + w / 2, y: cy + h / 2 }, { x: cx - w / 2, y: cy + h / 2 },
        ],
        confidence: 0.9,
      };
    }

    function buildConfig(cxs, mask) {
      const defs = cxs.map((_, i) => ({
        key: `col${i}`,
        header: [TOKENS[i]],
        fallbackRatio: (i + 1) / (cxs.length + 1),
      }));
      const words = cxs
        .map((cx, i) => (mask[i] ? makeWord(TOKENS[i].toUpperCase(), cx) : null))
        .filter(Boolean);
      // Filler words far outside the anchor range establish page bounds even
      // when every column in the mask is unmatched (mirrors the existing
      // all-unmatched test above).
      const minCx = Math.min(...cxs);
      const maxCx = Math.max(...cxs);
      const filler = [
        makeWord('FILLERLEFT', minCx - 500, 400),
        makeWord('FILLERRIGHT', maxCx + 500, 400),
      ];
      return { defs, words: [...words, ...filler] };
    }

    // Anchor spacing to sweep: 0 (every anchor coincides -- the zero-width
    // case), 1px (the reviewer-repro scale), 150px (the existing tests'
    // wide scale).
    const SPACINGS = [0, 1, 150];
    // Match masks over 5 columns: none matched, all matched, a run in the
    // middle, a run at each edge, and two separate single-column runs.
    const MASKS = [
      [false, false, false, false, false],
      [true, true, true, true, true],
      [true, false, false, false, true],
      [false, false, true, true, true],
      [true, true, true, false, false],
      [true, false, true, false, true],
      [false, true, false, true, false],
    ];

    for (const spacing of SPACINGS) {
      for (const mask of MASKS) {
        const label = mask.map((m) => (m ? '1' : '0')).join('');
        test(`spacing=${spacing}px mask=${label} produces non-inverted, non-decreasing bands`, () => {
          const cxs = mask.map((_, i) => i * spacing);
          const { defs, words } = buildConfig(cxs, mask);
          const { columns } = calibrateColumns(words, defs);

          expect(columns).toHaveLength(mask.length);

          // Invariant: no inverted band (zero-width is fine; negative is not).
          for (const c of columns) {
            expect(c.x1).toBeGreaterThanOrEqual(c.x0);
          }

          // Invariant: bands are non-decreasing left to right.
          for (let i = 1; i < columns.length; i += 1) {
            expect(columns[i].x0).toBeGreaterThanOrEqual(columns[i - 1].x1 - 1e-9);
          }

          // Invariant: a matched column's own known anchor position is
          // exactly what calibration detected (each token matches exactly
          // one word, so no averaging), and that position always falls
          // within that column's own band.
          columns.forEach((c, i) => {
            if (!mask[i]) return;
            expect(cxs[i]).toBeGreaterThanOrEqual(c.x0 - 1e-9);
            expect(cxs[i]).toBeLessThanOrEqual(c.x1 + 1e-9);
          });

          // Invariant: two ADJACENT matched columns share a boundary that is
          // a pure function of their own known positions, independent of
          // anything else on the page -- proving neither one moved.
          for (let i = 1; i < columns.length; i += 1) {
            if (mask[i - 1] && mask[i]) {
              const expectedBoundary = (cxs[i - 1] + cxs[i]) / 2;
              expect(columns[i - 1].x1).toBeCloseTo(expectedBoundary, 6);
              expect(columns[i].x0).toBeCloseTo(expectedBoundary, 6);
            }
          }
        });
      }
    }
  });
});
