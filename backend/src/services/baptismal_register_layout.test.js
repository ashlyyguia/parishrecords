const {
  boxOf, normalizeOrientation, splitSpread, calibrateColumns, detectRows,
  LEFT_COLUMNS, RIGHT_COLUMNS, assignCells, joinPages, applyFillDown,
  extractBaptismalRows,
} = require('./baptismal_register_layout');
const {
  buildRegisterFixture, GUTTER_X0, GUTTER_X1, FIRST_ROW_Y, ROW_H, COLUMN_X,
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

  // FIX 10 regression: Vision routinely attaches punctuation to a printed
  // title word ("Baptismal," / "Register."). An exact-match hasTitle used to
  // reject that, so `confirmed` was false on every real scan -- this proves
  // punctuated titles are still recognized.
  test('confirms the gutter even when the page titles carry OCR punctuation', () => {
    const { words } = normalizeOrientation(buildRegisterFixture({ rotation: 0 }).words);
    const punctuated = words.map((w) => {
      if (w.text === 'Baptismal') return { ...w, text: 'Baptismal,' };
      if (w.text === 'Register') return { ...w, text: 'Register.' };
      return w;
    });
    expect(splitSpread(punctuated).confirmed).toBe(true);
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
    const built = buildRegisterFixture({ rotation: 0, rows: 0 });
    // Guard the premise: `rows: 0` must actually mean zero data rows (a
    // prior fixture bug treated 0 as falsy and silently substituted the
    // default 3 sample rows, which let this test pass without ever
    // exercising the true header-only, no-data-below case its name claims).
    expect(built.rowCount).toBe(0);
    expect(built.words.some((w) => boxOf(w).cy >= FIRST_ROW_Y)).toBe(false);

    const { words } = normalizeOrientation(built.words);
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
    const built = buildRegisterFixture({ rotation: 0, rows: 0 });
    // Same premise guard as above: confirm this page genuinely has zero
    // data rows before filtering out the page titles.
    expect(built.rowCount).toBe(0);
    expect(built.words.some((w) => boxOf(w).cy >= FIRST_ROW_Y)).toBe(false);

    const { words } = normalizeOrientation(
      built.words.filter((w) => w.text !== 'Baptismal' && w.text !== 'Register'),
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

describe('detectRows', () => {
  const leftPage = (opts = {}) => {
    const { words } = normalizeOrientation(buildRegisterFixture({ rows: 6, ...opts }).words);
    const left = splitSpread(words).left;
    const { columns, headerMaxY } = calibrateColumns(left, LEFT_COLUMNS);
    return { left, columns, headerMaxY };
  };

  test('anchors rows on the NO. column', () => {
    const { left, columns, headerMaxY } = leftPage();
    const { rows, warnings } = detectRows(left, columns, headerMaxY);
    expect(rows).toHaveLength(6);
    expect(rows.map((r) => r.lineNo)).toEqual(['1', '2', '3', '4', '5', '6']);
    expect(warnings).toEqual([]);
  });

  test('rows are ordered top to bottom and do not overlap', () => {
    const { left, columns, headerMaxY } = leftPage();
    const { rows } = detectRows(left, columns, headerMaxY);
    for (let i = 1; i < rows.length; i += 1) {
      expect(rows[i].y0).toBeGreaterThanOrEqual(rows[i - 1].y1 - 0.001);
    }
  });

  test('falls back to y-clustering when the NO. column is unreadable', () => {
    const { left, columns, headerMaxY } = leftPage({ omitNoColumn: true });
    const { rows, warnings } = detectRows(left, columns, headerMaxY);
    expect(warnings).toContain('ROW_ANCHOR_FALLBACK');
    expect(rows).toHaveLength(6);
    expect(rows[0].lineNo).toBe(null);
  });

  // Critical 1: the right page never has a lineNo column at all (the
  // register only prints row numbers on the left page), so it always takes
  // the fallback path -- but that is the structurally normal, expected
  // outcome for that page, not a quality problem worth flagging on every
  // single scan. Contrast with the test above, where the SAME fallback path
  // is reached on a page that DOES have a lineNo column -- that one still
  // warns.
  test('falls back silently (no warning) on a page with no lineNo column at all, e.g. the right page', () => {
    const { words } = normalizeOrientation(buildRegisterFixture({ rows: 6 }).words);
    const right = splitSpread(words).right;
    const { columns, headerMaxY } = calibrateColumns(right, RIGHT_COLUMNS);
    const { rows, warnings } = detectRows(right, columns, headerMaxY);
    expect(rows).toHaveLength(6);
    expect(warnings).not.toContain('ROW_ANCHOR_FALLBACK');
  });

  test('returns no rows for an empty page', () => {
    expect(detectRows([], [], 0).rows).toEqual([]);
  });

  // Edge case: a header-only page (no data rows below it at all — a blank
  // register page, or one cropped tight to the header). There is nothing to
  // anchor to and nothing to fall back onto either; the honest result is
  // zero rows, not a crash or a spurious row conjured from header text.
  test('returns no rows for a page with zero data rows', () => {
    const built = buildRegisterFixture({ rotation: 0, rows: 0 });
    expect(built.rowCount).toBe(0);
    const { words } = normalizeOrientation(built.words);
    const left = splitSpread(words).left;
    const { columns, headerMaxY } = calibrateColumns(left, LEFT_COLUMNS);
    const { rows } = detectRows(left, columns, headerMaxY);
    expect(rows).toEqual([]);
  });

  // Edge case: exactly one data row. A naive "need at least 2 anchors to
  // trust the column" rule (plausible if ported over too literally) would
  // force this page onto the noisier fallback path and discard the one
  // NO.-column digit that was actually read correctly.
  test('anchors a single legitimate row without falling back', () => {
    const { left, columns, headerMaxY } = leftPage({ rows: 1 });
    const { rows, warnings } = detectRows(left, columns, headerMaxY);
    expect(rows).toHaveLength(1);
    expect(rows[0].lineNo).toBe('1');
    expect(warnings).toEqual([]);
    // The row "pitch" is undefined with only one anchor; the band must still
    // come out as a well-formed, positive-height interval, not NaN or
    // inverted.
    expect(rows[0].y1).toBeGreaterThan(rows[0].y0);
    expect(Number.isNaN(rows[0].y0)).toBe(false);
    expect(Number.isNaN(rows[0].y1)).toBe(false);
  });

  /**
   * Builds a 6-row page where every row's NO.-column digit has been erased
   * except the rows at `keepIndices` (0-based) — simulating faded/damaged
   * ink that took out most of the line-number column while leaving the
   * rest of those rows' handwriting (name, dates, etc.) legible. Used to
   * test the anchor/fallback corroboration check: a sparse or lone NO.
   * anchor must not be trusted at face value when the rest of the page's
   * words evidently contain many more rows than that.
   */
  function sixRowPageWithSparseNoColumn(keepIndices) {
    const built = buildRegisterFixture({ rotation: 0, rows: 6 });
    const keepCys = new Set(keepIndices.map((r) => FIRST_ROW_Y + r * ROW_H));
    const filtered = built.words.filter((w) => {
      const b = boxOf(w);
      const isNoColumnDigit = b.cx === COLUMN_X.no && /^\d{1,3}$/.test(w.text);
      return !isNoColumnDigit || keepCys.has(b.cy);
    });
    const { words } = normalizeOrientation(filtered);
    const left = splitSpread(words).left;
    const { columns, headerMaxY } = calibrateColumns(left, LEFT_COLUMNS);
    return { left, columns, headerMaxY };
  }

  // Corroboration finding: a lone surviving NO. anchor on a 6-row page must
  // not be trusted as proof the page only has one row. Every other row's
  // non-NO. cells are still there for the fallback y-clustering to find, so
  // the pipeline must notice the mismatch and recover all 6 rows (via the
  // fallback) instead of confidently — and silently — returning 1.
  test('does not silently collapse to 1 row when only one NO. anchor survives on a 6-row page', () => {
    const { left, columns, headerMaxY } = sixRowPageWithSparseNoColumn([0]);
    const { rows, warnings } = detectRows(left, columns, headerMaxY);
    expect(rows).toHaveLength(6);
    expect(warnings).toContain('ROW_ANCHOR_FALLBACK');
  });

  // Same finding, with 2 of 6 NO. anchors surviving instead of 1: still a
  // small fraction of the page's evident row count, so it must not be
  // trusted at face value either.
  test('does not silently return only 2 rows when just 2 of 6 NO. anchors survive', () => {
    const { left, columns, headerMaxY } = sixRowPageWithSparseNoColumn([0, 3]);
    const { rows, warnings } = detectRows(left, columns, headerMaxY);
    expect(rows).toHaveLength(6);
    expect(warnings).toContain('ROW_ANCHOR_FALLBACK');
  });

  // Control: when every NO. anchor on a 6-row page is legible, corroboration
  // must be a no-op — same rows, same lineNo values, no warning. (Also
  // covered by 'anchors rows on the NO. column' above; asserted again here,
  // co-located with the sparse-anchor tests, so the full corroboration
  // matrix — 6-of-6, 2-of-6, 1-of-6 — reads together.)
  test('all anchors legible on a 6-row page: unchanged behaviour, no warning', () => {
    const { left, columns, headerMaxY } = leftPage();
    const { rows, warnings } = detectRows(left, columns, headerMaxY);
    expect(rows).toHaveLength(6);
    expect(rows.map((r) => r.lineNo)).toEqual(['1', '2', '3', '4', '5', '6']);
    expect(warnings).toEqual([]);
  });

  // Edge case: real handwritten registers are not evenly ruled. Row bands
  // must track each row's own detected numeral, not an assumed uniform
  // pitch, so a wide gap further down the page must not distort earlier
  // rows or merge/misorder later ones.
  test('handles uneven row spacing by anchoring each band to its own numeral', () => {
    const built = buildRegisterFixture({ rotation: 0, rows: 3 });
    const rowTwoCy = FIRST_ROW_Y + 1 * ROW_H;
    const rowThreeCy = FIRST_ROW_Y + 2 * ROW_H;
    const SHIFT = 500;

    // Push row 3 (and all of its cells, which share its cy) far down the
    // page: row1->row2 stays the fixture's normal 60px gap while row2->row3
    // balloons to 560px.
    const shiftedWords = built.words.map((w) => {
      const b = boxOf(w);
      if (b.cy !== rowThreeCy) return w;
      return { ...w, vertices: w.vertices.map((v) => ({ x: v.x, y: v.y + SHIFT })) };
    });

    const { words } = normalizeOrientation(shiftedWords);
    const left = splitSpread(words).left;
    const { columns, headerMaxY } = calibrateColumns(left, LEFT_COLUMNS);
    const { rows, warnings } = detectRows(left, columns, headerMaxY);

    expect(warnings).toEqual([]);
    expect(rows).toHaveLength(3);
    expect(rows.map((r) => r.lineNo)).toEqual(['1', '2', '3']);
    for (let i = 1; i < rows.length; i += 1) {
      expect(rows[i].y0).toBeGreaterThanOrEqual(rows[i - 1].y1 - 0.001);
    }
    // The row2/row3 boundary sits at the midpoint of their real (shifted)
    // detected positions, not glued near the tight row1/row2 gap.
    const expectedBoundary = (rowTwoCy + rowThreeCy + SHIFT) / 2;
    expect(rows[2].y0).toBeCloseTo(expectedBoundary, 0);
  });

  // A wrong or missing headerMaxY silently misroutes every row (see the
  // header-band bug Task 4 fixed for column calibration) — it must fail
  // loudly instead of guessing.
  test('throws rather than silently guessing when headerMaxY is missing', () => {
    const { left, columns } = leftPage();
    try {
      detectRows(left, columns);
      throw new Error('should have thrown');
    } catch (err) {
      expect(err.message).toMatch(/headerMaxY/);
    }
  });

  test('throws rather than silently guessing when headerMaxY is NaN', () => {
    const { left, columns } = leftPage();
    try {
      detectRows(left, columns, NaN);
      throw new Error('should have thrown');
    } catch (err) {
      expect(err.message).toMatch(/headerMaxY/);
    }
  });
});

/** Builds a single synthetic word with an explicit center, for adversarial
 * cell-boundary cases that the fixture's regular row/column geometry can't
 * express on its own. Mirrors register_fixture.js's internal `word()`, plus
 * an optional explicit `height` (defaulting to the fixture's fixed 22px) so
 * tests can construct words with genuinely different heights — the fixture's
 * own `word()` hardcodes every word to 22px, which never exercises a cell
 * whose two lines have different word heights (e.g. a tall capital line vs a
 * small cursive line). */
function mkWord(text, cx, cy, confidence = 0.9, height = 22) {
  const w = Math.max(24, text.length * 9);
  const h = height;
  const x0 = Math.round(cx - w / 2);
  const y0 = Math.round(cy - h / 2);
  return {
    text,
    vertices: [
      { x: x0, y: y0 }, { x: x0 + w, y: y0 },
      { x: x0 + w, y: y0 + h }, { x: x0, y: y0 + h },
    ],
    confidence,
  };
}

describe('assignCells', () => {
  const setup = () => {
    const { words } = normalizeOrientation(buildRegisterFixture({ rows: 3 }).words);
    const { left, right } = splitSpread(words);
    const leftCal = calibrateColumns(left, LEFT_COLUMNS);
    const rightCal = calibrateColumns(right, RIGHT_COLUMNS);
    return {
      left, right, leftCols: leftCal.columns, rightCols: rightCal.columns,
      leftRows: detectRows(left, leftCal.columns, leftCal.headerMaxY).rows,
      rightRows: detectRows(right, rightCal.columns, rightCal.headerMaxY).rows,
    };
  };

  test('places handwriting in the correct left-page columns', () => {
    const s = setup();
    const { cells } = assignCells(s.left, s.leftCols, s.leftRows);
    expect(cells).toHaveLength(3);
    expect(cells[0].nameOfChild.value).toBe('TESTA SAMPLE FAMILYONE');
    expect(cells[0].placeAndBirthDate.value).toBe('19 FEBRUARY 2001');
    expect(cells[0].parents.value).toBe('PARENTA FAMILYONE');
    expect(cells[1].nameOfChild.value).toBe('TESTB FAMILYTWO');
  });

  test('places handwriting in the correct right-page columns', () => {
    const s = setup();
    const { cells } = assignCells(s.right, s.rightCols, s.rightRows);
    expect(cells[0].dateOfBaptism.value).toBe('12 MAY 2016');
    expect(cells[0].minister.value).toBe('FR. TEST CLERIC');
    expect(cells[2].dateOfBaptism.value).toBe('22 MAY 2016');
  });

  // Every word in the fixture's confidence-averaging fixture used to share
  // one value (0.4), which passes identically under mean, min, max, or
  // "first word wins" — it never actually proved averaging. Two distinct
  // confidences with a known mean rule that out.
  test('averages word confidence per cell', () => {
    const s = setup();
    const col = s.leftCols.find((c) => c.key === 'nameOfChild');
    const row = s.leftRows[0];
    const cx = (col.x0 + col.x1) / 2;
    const cy = (row.y0 + row.y1) / 2;
    const words = [
      mkWord('LOW', cx - 30, cy, 0.2),
      mkWord('HIGH', cx + 30, cy, 0.8),
    ];
    const { cells } = assignCells(words, s.leftCols, s.leftRows);
    expect(cells[0].nameOfChild.value).toBe('LOW HIGH');
    expect(cells[0].nameOfChild.confidence).toBeCloseTo(0.5, 5);
  });

  test('leaves an unwritten column empty rather than guessing', () => {
    const s = setup();
    const { cells } = assignCells(s.left, s.leftCols, s.leftRows);
    expect(cells[0].legitimacy.value).toBe('');
    expect(cells[0].legitimacy.confidence).toBe(0);
  });

  // A genuinely empty cell ({value:'', confidence:0}) must stay
  // distinguishable from a cell that WAS read but with zero confidence —
  // downstream review treats "nothing here" differently from "something
  // here, but don't trust it". Confidence alone can't tell them apart (both
  // are 0); `value` is what distinguishes them.
  test('a zero-confidence word in a written cell is distinguishable from an empty cell', () => {
    const s = setup();
    const col = s.leftCols.find((c) => c.key === 'legitimacy');
    const row = s.leftRows[0];
    const cx = (col.x0 + col.x1) / 2;
    const cy = (row.y0 + row.y1) / 2;
    const word = mkWord('N', cx, cy, 0);

    const { cells } = assignCells([word], s.leftCols, s.leftRows);

    expect(cells[0].legitimacy.value).toBe('N');
    expect(cells[0].legitimacy.value).not.toBe('');
    expect(cells[0].legitimacy.confidence).toBe(0);
  });

  test('never assigns header words to a data row', () => {
    const s = setup();
    const { cells } = assignCells(s.left, s.leftCols, s.leftRows);
    const all = cells.map((c) => Object.values(c).map((f) => f.value).join(' ')).join(' ');
    expect(all).not.toContain('CHILD');
    expect(all).not.toContain('PARENTS');
  });

  // Edge case: a page with rows/columns calibrated but literally no words to
  // place (e.g. every word failed OCR, or a blank page was scanned). Every
  // cell in every row must come back empty rather than throwing.
  test('returns an all-empty grid when there are no words at all', () => {
    const s = setup();
    const { cells, dropped } = assignCells([], s.leftCols, s.leftRows);
    expect(cells).toHaveLength(s.leftRows.length);
    for (const row of cells) {
      for (const key of Object.keys(row)) {
        expect(row[key]).toEqual({ value: '', confidence: 0 });
      }
    }
    expect(dropped).toBe(0);
  });

  // Edge case: a row band that calibration/detection produced but that has
  // no handwriting in it at all (e.g. a skipped register line). Its
  // neighbours must be unaffected and it must not crash or silently borrow
  // words from an adjacent row.
  test('leaves every cell in a wordless row empty without disturbing its neighbours', () => {
    const s = setup();
    // Drop every word that falls in row 1's band, but keep rows 0 and 2 fed.
    const row1 = s.leftRows[1];
    const words = s.left.filter((w) => {
      const b = boxOf(w);
      return !(b.cy >= row1.y0 && b.cy < row1.y1);
    });
    const { cells } = assignCells(words, s.leftCols, s.leftRows);
    expect(cells).toHaveLength(3);
    for (const key of Object.keys(cells[1])) {
      expect(cells[1][key]).toEqual({ value: '', confidence: 0 });
    }
    // Row 0 (unaffected) still reads normally.
    expect(cells[0].nameOfChild.value).toBe('TESTA SAMPLE FAMILYONE');
    // Row 2 (unaffected) still reads normally too — row 1 being empty must
    // not shift row 2's words up into row 1 or otherwise corrupt it.
    expect(cells[2].nameOfChild.value).toBe('TESTC FAMILYONE');
  });

  // Edge case: row bands are half-open [y0, y1) and column bands are
  // half-open [x0, x1) (see the boundary math in calibrateColumns/
  // detectRows). A word whose center lands exactly on a shared boundary must
  // land in exactly one band — the one starting there — never both, and
  // never neither.
  test('assigns a word sitting exactly on a row boundary to the row that starts there', () => {
    const s = setup();
    const boundaryY = s.leftRows[0].y1; // === leftRows[1].y0 by construction
    const col = s.leftCols.find((c) => c.key === 'nameOfChild');
    const cx = (col.x0 + col.x1) / 2;
    const boundaryWord = mkWord('ONBOUNDARY', cx, boundaryY);

    const { cells } = assignCells([boundaryWord], s.leftCols, s.leftRows);

    expect(cells[0].nameOfChild.value).toBe('');
    expect(cells[1].nameOfChild.value).toBe('ONBOUNDARY');
  });

  test('assigns a word sitting exactly on a column boundary to the column that starts there', () => {
    const s = setup();
    const nameCol = s.leftCols.find((c) => c.key === 'nameOfChild');
    const placeCol = s.leftCols.find((c) => c.key === 'placeAndBirthDate');
    const boundaryX = nameCol.x1; // === placeCol.x0 by construction
    const row = s.leftRows[0];
    const cy = (row.y0 + row.y1) / 2;
    const boundaryWord = mkWord('ONBOUNDARY', boundaryX, cy);

    const { cells } = assignCells([boundaryWord], s.leftCols, s.leftRows);

    expect(cells[0].nameOfChild.value).not.toContain('ONBOUNDARY');
    expect(cells[0].placeAndBirthDate.value).toBe('ONBOUNDARY');
  });

  // Edge case: a single cell whose handwriting overflows onto a second
  // visual line within the same row/column band (common for a long name or
  // a wrapped note). Reading order must be top line left-to-right, then
  // bottom line left-to-right — not simply sorted by x, which would
  // interleave the two lines.
  test('reads a two-line cell top-to-bottom then left-to-right within each line', () => {
    const s = setup();
    const row = s.leftRows[1]; // a middle row, bounded on both sides
    const col = s.leftCols.find((c) => c.key === 'nameOfChild');
    const topCy = row.y0 + (row.y1 - row.y0) * 0.25;
    const bottomCy = row.y0 + (row.y1 - row.y0) * 0.75;
    const leftCx = col.x0 + (col.x1 - col.x0) * 0.3;
    const rightCx = col.x0 + (col.x1 - col.x0) * 0.7;

    // Deliberately out of reading order in the input array, so the test
    // actually exercises the sort rather than passing by accident.
    const words = [
      mkWord('RIGHT2', rightCx, bottomCy),
      mkWord('LEFT1', leftCx, topCy),
      mkWord('RIGHT1', rightCx, topCy),
      mkWord('LEFT2', leftCx, bottomCy),
    ];

    const { cells } = assignCells(words, s.leftCols, s.leftRows);

    expect(cells[1].nameOfChild.value).toBe('LEFT1 RIGHT1 LEFT2 RIGHT2');
  });

  // Real handwriting is not uniform height: a line of tall capitals and a
  // line of small cursive script routinely coexist in the same cell. The
  // fixture's own mkWord/word() hardcode every word to 22px, so without an
  // explicit height override this risky case was never exercised — a
  // whole-cell median dominated by one line's height could either merge the
  // two real lines together (interleaving words across lines by x) or, in
  // the opposite skew, split one line into two. This case uses a clearly
  // tall top line and a clearly short bottom line, well outside each
  // other's clustering tolerance, and checks reading order still comes out
  // top-line-then-bottom-line, left-to-right within each.
  test('reads a two-line cell with mixed word heights (tall capitals over small cursive) in correct order', () => {
    const s = setup();
    const row = s.leftRows[1];
    const col = s.leftCols.find((c) => c.key === 'nameOfChild');
    const leftCx = col.x0 + (col.x1 - col.x0) * 0.3;
    const rightCx = col.x0 + (col.x1 - col.x0) * 0.7;
    const topCy1 = row.y0 + 5;
    const topCy2 = row.y0 + 8;
    const bottomCy1 = row.y0 + 45;
    const bottomCy2 = row.y0 + 48;

    const words = [
      mkWord('SMALLR', rightCx, bottomCy2, 0.9, 14), // small cursive, bottom line
      mkWord('TALLL', leftCx, topCy1, 0.9, 50), // tall capitals, top line
      mkWord('SMALLL', leftCx, bottomCy1, 0.9, 14),
      mkWord('TALLR', rightCx, topCy2, 0.9, 50),
    ];

    const { cells } = assignCells(words, s.leftCols, s.leftRows);

    expect(cells[1].nameOfChild.value).toBe('TALLL TALLR SMALLL SMALLR');
  });

  // Proves the actual defect the clusterByY switch fixes, not just the
  // happy path above. Here the whole-cell median (driven by the 2 tall + 2
  // short words) yields lineTolerance = 35. The gap between the raw closest
  // cross-line words (top line's second word at row.y0+7, bottom line's
  // first word at row.y0+42 → Δ=35) sits exactly AT that naive threshold —
  // under the old pairwise `|Δcy| > tolerance` test (35 > 35 is false) that
  // pair reads as "same line", while the OLD code's other cross-line pair
  // (row.y0+5 vs row.y0+42 → Δ=37) reads as "different line": a direct,
  // concrete instance of the non-transitive comparator this task removed.
  // clusterByY instead compares each new point against its cluster's
  // running MEAN (not the nearest raw neighbour), which pulls the top
  // cluster's effective position to row.y0+6 — 36 away from the first
  // bottom-line word, safely over tolerance — so the two lines still split
  // cleanly instead of merging into one interleaved-by-x line.
  test('keeps mixed-height lines split even where a naive nearest-word check would call them one line', () => {
    const s = setup();
    const row = s.leftRows[1];
    const col = s.leftCols.find((c) => c.key === 'nameOfChild');
    const leftCx = col.x0 + (col.x1 - col.x0) * 0.3;
    const rightCx = col.x0 + (col.x1 - col.x0) * 0.7;
    const topCy1 = row.y0 + 5;
    const topCy2 = row.y0 + 7;
    const bottomCy1 = row.y0 + 42;
    const bottomCy2 = row.y0 + 44;

    const words = [
      mkWord('BOTR', rightCx, bottomCy2, 0.9, 20), // scrambled input order
      mkWord('TOPL', leftCx, topCy1, 0.9, 50),
      mkWord('BOTL', leftCx, bottomCy1, 0.9, 20),
      mkWord('TOPR', rightCx, topCy2, 0.9, 50),
    ];

    const { cells } = assignCells(words, s.leftCols, s.leftRows);

    expect(cells[1].nameOfChild.value).toBe('TOPL TOPR BOTL BOTR');
  });

  // `assignCells` deliberately drops a word whose center lands outside every
  // row band or every column band rather than guessing — but a silently
  // dropped word looks identical to a genuinely blank field to a human
  // reviewer. `dropped` must count those words so a caller can flag a page
  // where calibration went badly wrong instead of trusting an all-blank
  // result at face value.
  describe('dropped count', () => {
    test('is 0 for a clean fixture page (every word lands in some band)', () => {
      const s = setup();
      const firstY = s.leftRows[0].y0;
      const lastY = s.leftRows[s.leftRows.length - 1].y1;
      // Restrict to the data-row words only; header/title words above the
      // first row band are a separate, deliberately-dropped case covered below.
      const dataWords = s.left.filter((w) => {
        const b = boxOf(w);
        return b.cy >= firstY && b.cy < lastY;
      });
      const { dropped } = assignCells(dataWords, s.leftCols, s.leftRows);
      expect(dropped).toBe(0);
    });

    test('counts words whose center lands outside every row band or every column band', () => {
      const s = setup();
      const validRowCy = (s.leftRows[0].y0 + s.leftRows[0].y1) / 2;
      const belowLastRow = s.leftRows[s.leftRows.length - 1].y1 + 5000;
      const beforeFirstColumn = s.leftCols[0].x0 - 5000;

      const words = [
        mkWord('NOROW1', 200, belowLastRow), // outside every row band
        mkWord('NOROW2', 200, belowLastRow + 100),
        mkWord('NOCOL', beforeFirstColumn, validRowCy), // valid row, no column
      ];

      const { dropped, cells } = assignCells(words, s.leftCols, s.leftRows);

      expect(dropped).toBe(3);
      for (const row of cells) {
        for (const key of Object.keys(row)) {
          expect(row[key].value).not.toContain('NOROW');
          expect(row[key].value).not.toContain('NOCOL');
        }
      }
    });

    test('counts header words above the first row band as dropped — they legitimately have nowhere to go', () => {
      const s = setup();
      const firstRowY0 = s.leftRows[0].y0;
      const headerWords = s.left.filter((w) => boxOf(w).cy < firstRowY0);
      // Sanity: the fixture actually has header/title words up there, or
      // this test would trivially pass with dropped === 0 === length.
      expect(headerWords.length).toBeGreaterThan(0);

      const { dropped, cells } = assignCells(headerWords, s.leftCols, s.leftRows);

      expect(dropped).toBe(headerWords.length);
      for (const row of cells) {
        for (const key of Object.keys(row)) {
          expect(row[key]).toEqual({ value: '', confidence: 0 });
        }
      }
    });
  });
});

describe('applyFillDown', () => {
  const row = (over) => ({
    lineNo: '1',
    fields: {
      nameOfChild: { value: 'A', confidence: 0.9 },
      dateOfBaptism: { value: '', confidence: 0 },
      minister: { value: '', confidence: 0 },
      sponsors: { value: '', confidence: 0 },
      ...over,
    },
  });

  test('fills empty minister and date from the row above, tagged inherited', () => {
    const rows = [
      row({ dateOfBaptism: { value: '12 MAY 2016', confidence: 0.9 }, minister: { value: 'FR. TESTMIN', confidence: 0.9 } }),
      row(),
    ];
    const { rows: out, filled } = applyFillDown(rows);
    expect(out[1].fields.dateOfBaptism.value).toBe('12 MAY 2016');
    expect(out[1].fields.dateOfBaptism.inherited).toBe(true);
    expect(out[1].fields.minister.inherited).toBe(true);
    expect(out[0].fields.dateOfBaptism.inherited).toBe(false);
    expect(filled).toBe(2);
  });

  test('treats a ditto mark as empty', () => {
    const rows = [
      row({ minister: { value: 'FR. TESTMIN', confidence: 0.9 } }),
      row({ minister: { value: '-do-', confidence: 0.5 } }),
    ];
    expect(applyFillDown(rows).rows[1].fields.minister.value).toBe('FR. TESTMIN');
  });

  test('never fills sponsors or names', () => {
    const rows = [
      row({ sponsors: { value: 'SPONSORA ONE', confidence: 0.9 } }),
      row(),
    ];
    const out = applyFillDown(rows).rows;
    expect(out[1].fields.sponsors.value).toBe('');
    expect(out[1].fields.nameOfChild.value).toBe('A');
  });

  test('leaves a real value alone', () => {
    const rows = [
      row({ minister: { value: 'FR. TESTMIN', confidence: 0.9 } }),
      row({ minister: { value: 'FR. JEZON', confidence: 0.9 } }),
    ];
    expect(applyFillDown(rows).rows[1].fields.minister.value).toBe('FR. JEZON');
    expect(applyFillDown(rows).rows[1].fields.minister.inherited).toBe(false);
  });

  // Edge cases beyond the brief: Tasks 4-6 each needed a fix round for the
  // analogous cases in their own function, so these are covered here too
  // before this feature is considered done.
  test('leaves the first row empty when there is nothing above to carry', () => {
    const rows = [row(), row()];
    const out = applyFillDown(rows).rows;
    expect(out[0].fields.dateOfBaptism.value).toBe('');
    expect(out[0].fields.dateOfBaptism.inherited).toBe(false);
    expect(out[1].fields.dateOfBaptism.value).toBe('');
    expect(out[1].fields.dateOfBaptism.inherited).toBe(false);
  });

  test('leaves a ditto mark in the very first row untouched — there is nothing above to carry', () => {
    const rows = [
      row({ minister: { value: '-do-', confidence: 0.5 } }),
      row({ minister: { value: 'FR. TESTMIN', confidence: 0.9 } }),
    ];
    const out = applyFillDown(rows).rows;
    expect(out[0].fields.minister.value).toBe('-do-');
    expect(out[0].fields.minister.inherited).toBe(false);
    // The second row's real value must not be disturbed by the leading ditto.
    expect(out[1].fields.minister.value).toBe('FR. TESTMIN');
  });

  test('does not crash on a row whose fields object is missing minister/dateOfBaptism keys entirely', () => {
    const rows = [
      { lineNo: '1', fields: { nameOfChild: { value: 'A', confidence: 0.9 } } },
      row({ minister: { value: 'FR. TESTMIN', confidence: 0.9 } }),
      { lineNo: '3', fields: {} },
    ];
    const out = applyFillDown(rows).rows;
    expect(out[0].fields.minister.value).toBe('');
    expect(out[0].fields.minister.inherited).toBe(false);
    expect(out[2].fields.minister.value).toBe('FR. TESTMIN');
    expect(out[2].fields.minister.inherited).toBe(true);
  });
});

describe('joinPages', () => {
  test('joins left and right by row index', () => {
    const left = [{ nameOfChild: { value: 'A', confidence: 0.9 } }];
    const right = [{ minister: { value: 'FR. X', confidence: 0.8 } }];
    const leftRows = [{ lineNo: '1', y0: 0, y1: 50 }];
    const rightRows = [{ y0: 0, y1: 50 }];
    const { rows, warnings } = joinPages(left, right, leftRows, rightRows);
    expect(rows).toHaveLength(1);
    expect(rows[0].lineNo).toBe('1');
    expect(rows[0].fields.nameOfChild.value).toBe('A');
    expect(rows[0].fields.minister.value).toBe('FR. X');
    expect(warnings).toEqual([]);
  });

  test('warns and joins the overlap on a row-count mismatch', () => {
    const left = [{ nameOfChild: { value: 'A', confidence: 1 } }, { nameOfChild: { value: 'B', confidence: 1 } }];
    const right = [{ minister: { value: 'FR. X', confidence: 1 } }];
    const leftRows = [{ lineNo: '1', y0: 0, y1: 50 }, { lineNo: '2', y0: 50, y1: 100 }];
    const rightRows = [{ y0: 0, y1: 50 }];
    const { rows, warnings } = joinPages(left, right, leftRows, rightRows);
    expect(warnings).toContain('ROW_COUNT_MISMATCH');
    expect(rows).toHaveLength(2);
    expect(rows[1].fields.minister.value).toBe('');
  });

  test('handles one side having zero rows without crashing, joining on the overlap', () => {
    const left = [{ nameOfChild: { value: 'A', confidence: 1 } }, { nameOfChild: { value: 'B', confidence: 1 } }];
    const right = [];
    const leftRows = [{ lineNo: '1', y0: 0, y1: 50 }, { lineNo: '2', y0: 50, y1: 100 }];
    const rightRows = [];
    const { rows, warnings } = joinPages(left, right, leftRows, rightRows);
    expect(warnings).toContain('ROW_COUNT_MISMATCH');
    expect(rows).toHaveLength(2);
    expect(rows[0].fields.nameOfChild.value).toBe('A');
    expect(rows[0].fields.minister.value).toBe('');
    expect(rows[1].fields.minister.value).toBe('');
  });

  // Important 4: the highest-consequence failure mode in the whole feature.
  // If the left page mis-detects one extra row and the right page misses
  // one, the two row COUNTS can coincide by chance -- ROW_COUNT_MISMATCH
  // stays silent -- while every row past the divergence point gets paired
  // with the wrong person's data (one child's name joined to a different
  // child's parents/sponsors/date). Equal counts here (2 and 2) but the
  // second pair's y-bands don't overlap at all, so the pairing must be
  // flagged rather than silently trusted.
  test('flags misaligned rows when equal-count left/right row bands do not overlap vertically', () => {
    const left = [
      { nameOfChild: { value: 'CHILD_A', confidence: 1 } },
      { nameOfChild: { value: 'CHILD_B', confidence: 1 } },
    ];
    const right = [
      { minister: { value: 'FR. A', confidence: 1 } },
      { minister: { value: 'FR. B', confidence: 1 } },
    ];
    const leftRows = [
      { lineNo: '1', y0: 0, y1: 50 },
      { lineNo: '2', y0: 50, y1: 100 },
    ];
    // Right page's second row band sits nowhere near the left page's second
    // row band, even though both sides report exactly 2 rows.
    const rightRows = [
      { y0: 0, y1: 50 },
      { y0: 400, y1: 450 },
    ];
    const { rows, warnings } = joinPages(left, right, leftRows, rightRows);
    expect(warnings).toContain('ROW_ALIGNMENT_MISMATCH');
    expect(warnings).not.toContain('ROW_COUNT_MISMATCH');
    // Not silently re-aligned or dropped -- still joined by index, with the
    // warning as the signal a reviewer must act on.
    expect(rows).toHaveLength(2);
  });

  // Control: equal counts AND overlapping bands must NOT warn -- proves the
  // check above is actually testing overlap, not just equal counts.
  test('does not flag alignment when equal-count row bands genuinely overlap', () => {
    const left = [
      { nameOfChild: { value: 'CHILD_A', confidence: 1 } },
      { nameOfChild: { value: 'CHILD_B', confidence: 1 } },
    ];
    const right = [
      { minister: { value: 'FR. A', confidence: 1 } },
      { minister: { value: 'FR. B', confidence: 1 } },
    ];
    const leftRows = [
      { lineNo: '1', y0: 0, y1: 50 },
      { lineNo: '2', y0: 50, y1: 100 },
    ];
    const rightRows = [
      { y0: 2, y1: 48 },
      { y0: 55, y1: 98 },
    ];
    const { warnings } = joinPages(left, right, leftRows, rightRows);
    expect(warnings).not.toContain('ROW_ALIGNMENT_MISMATCH');
  });

  // FIX 2 regression: the reviewer-traced case where a bare intersection
  // test misses a one-row drift entirely. Left NO.-column anchors at cy
  // 100/200/300/400/500 give contiguous bands [50,150] [150,250] [250,350]
  // [350,450] [450,550] (100px each, sized off small printed digits). The
  // right page has a blank row 2 and a tall row 4 whose handwriting splits
  // into two visual clusters, giving anchors at 105/305/380/430/505 and
  // bands [55,205] [205,342.5] [342.5,405] [405,467.5] [467.5,555] (uneven
  // widths, sized off full-width handwriting). Counts match (5==5), so
  // ROW_COUNT_MISMATCH never fires, and EVERY index pair still intersects
  // under a bare overlap test -- so under the old check this produced an
  // empty `warnings` array while four children silently received another
  // child's baptism date, minister and sponsors.
  test('flags misalignment via centre-drift even when every index pair still bare-overlaps (reviewer-traced case)', () => {
    const leftCys = [100, 200, 300, 400, 500];
    const rightCys = [105, 305, 380, 430, 505];
    const bandsFromAnchors = (cys) => {
      const pitch = (cys[cys.length - 1] - cys[0]) / (cys.length - 1);
      return cys.map((cy, i) => {
        const prev = cys[i - 1];
        const next = cys[i + 1];
        return {
          y0: prev !== undefined ? (prev + cy) / 2 : cy - pitch / 2,
          y1: next !== undefined ? (cy + next) / 2 : cy + pitch / 2,
        };
      });
    };
    const leftRows = bandsFromAnchors(leftCys).map((b, i) => ({ lineNo: String(i + 1), ...b }));
    const rightRows = bandsFromAnchors(rightCys);

    // Sanity: every index pair genuinely still bare-overlaps, so this test
    // is actually exercising the centre-drift check, not the old overlap
    // check by coincidence.
    for (let i = 0; i < leftRows.length; i += 1) {
      const l = leftRows[i];
      const r = rightRows[i];
      expect(Math.max(l.y0, r.y0)).toBeLessThan(Math.min(l.y1, r.y1));
    }

    const left = leftCys.map((_, i) => ({ nameOfChild: { value: `CHILD_${i}`, confidence: 1 } }));
    const right = rightCys.map((_, i) => ({ minister: { value: `FR_${i}`, confidence: 1 } }));

    const { warnings } = joinPages(left, right, leftRows, rightRows);
    expect(warnings).toContain('ROW_ALIGNMENT_MISMATCH');
    expect(warnings).not.toContain('ROW_COUNT_MISMATCH');
  });

  // Control for the same geometry shape: a correct join (right anchors at
  // the SAME cy as left, just narrower/wider bands from different content
  // widths) must stay quiet -- centres agree closely even though band
  // widths still differ.
  test('does not flag centre-drift on a correct join with differently-sized bands', () => {
    const cys = [100, 200, 300, 400, 500];
    const bandsFromAnchors = (cys, halfWidth) => cys.map((cy) => ({ y0: cy - halfWidth, y1: cy + halfWidth }));
    const leftRows = bandsFromAnchors(cys, 50).map((b, i) => ({ lineNo: String(i + 1), ...b }));
    const rightRows = bandsFromAnchors(cys, 30); // narrower bands, same centres

    const left = cys.map((_, i) => ({ nameOfChild: { value: `CHILD_${i}`, confidence: 1 } }));
    const right = cys.map((_, i) => ({ minister: { value: `FR_${i}`, confidence: 1 } }));

    const { warnings } = joinPages(left, right, leftRows, rightRows);
    expect(warnings).not.toContain('ROW_ALIGNMENT_MISMATCH');
    expect(warnings).not.toContain('ROW_COUNT_MISMATCH');
  });

  // FIX 2 also requires ROW_ALIGNMENT_MISMATCH unconditionally whenever
  // ROW_COUNT_MISMATCH fires -- differing counts guarantee everything past
  // the divergence point is mispaired, even over the checkable prefix that
  // happens to still look aligned.
  test('raises ROW_ALIGNMENT_MISMATCH unconditionally alongside ROW_COUNT_MISMATCH', () => {
    const left = [
      { nameOfChild: { value: 'A', confidence: 1 } },
      { nameOfChild: { value: 'B', confidence: 1 } },
    ];
    const right = [{ minister: { value: 'FR. X', confidence: 1 } }];
    // The one checkable (overlapping) pair looks perfectly aligned on its own.
    const leftRows = [{ lineNo: '1', y0: 0, y1: 50 }, { lineNo: '2', y0: 50, y1: 100 }];
    const rightRows = [{ y0: 0, y1: 50 }];

    const { warnings } = joinPages(left, right, leftRows, rightRows);
    expect(warnings).toContain('ROW_COUNT_MISMATCH');
    expect(warnings).toContain('ROW_ALIGNMENT_MISMATCH');
  });
});

describe('extractBaptismalRows', () => {
  test('extracts a full spread end to end', () => {
    const { words } = buildRegisterFixture({ rows: 3, rotation: 0 });
    const out = extractBaptismalRows(words);
    expect(out.rotation).toBe(0);
    expect(out.rows).toHaveLength(3);
    expect(out.rows[0].fields.nameOfChild.value).toBe('TESTA SAMPLE FAMILYONE');
    expect(out.rows[0].fields.dateOfBaptism.value).toBe('12 MAY 2016');
    expect(out.rows[0].fields.parents.value).toBe('PARENTA FAMILYONE');
    expect(out.rows[0].lineNo).toBe('1');
  });

  test('produces identical field values regardless of page rotation', () => {
    const upright = extractBaptismalRows(buildRegisterFixture({ rows: 3, rotation: 0 }).words);
    for (const rotation of [90, 180, 270]) {
      const rotated = extractBaptismalRows(buildRegisterFixture({ rows: 3, rotation }).words);
      expect(rotated.rows.map((r) => r.fields.nameOfChild.value))
        .toEqual(upright.rows.map((r) => r.fields.nameOfChild.value));
      expect(rotated.rotation).toBe(rotation);
    }
  });

  test('throws LAYOUT_UNRECOGNIZED when nothing looks like a register', () => {
    const junk = [
      { text: 'HELLO', vertices: [{x:0,y:0},{x:50,y:0},{x:50,y:20},{x:0,y:20}], confidence: 0.9 },
      { text: 'WORLD', vertices: [{x:60,y:0},{x:110,y:0},{x:110,y:20},{x:60,y:20}], confidence: 0.9 },
    ];
    try {
      extractBaptismalRows(junk);
      throw new Error('should have thrown');
    } catch (e) {
      expect(e.code).toBe('LAYOUT_UNRECOGNIZED');
    }
  });

  // Important 3: with the old bare `matchedCount < 3` guard plus unbounded
  // `startsWith` header matching, a fabricated NON-register memo could rack
  // up 3+ coincidental header-token matches purely by containing ordinary
  // English words that happen to start with a short token: "CHILDREN"
  // starts with 'child', "ILLNESS" starts with 'ill', "SPONSORSHIP" starts
  // with 'sponsors', "NOTICE" starts with 'no'. That was enough to clear the
  // guard and produce a fabricated 1-row extraction from a document that
  // isn't a baptismal register at all. All of the memo's words are laid out
  // as a single narrow column (as a real memo would be), so splitSpread's
  // gutter guess drops them all on one side -- which is also exactly the
  // "evidence on both sides" gap this fix closes.
  test('throws LAYOUT_UNRECOGNIZED for a fabricated memo with coincidental header-like words', () => {
    const memoWords = [
      'NOTICE', 'TO', 'ALL', 'PARISHIONERS', 'REGARDING', 'THE', 'CHILDREN',
      'PROGRAM', 'DUE', 'TO', 'RECENT', 'ILLNESS', 'REPORTS', 'THE',
      'SPONSORSHIP', 'DRIVE', 'IS', 'POSTPONED', 'PLEASE', 'SEE', 'THE',
      'PARISH', 'REPORT', 'FOR', 'DETAILS', 'THANK', 'YOU',
    ];
    const words = memoWords.map((text, i) => mkWord(text, 40 + i * 70, 40 + Math.floor(i / 6) * 30));
    try {
      extractBaptismalRows(words);
      throw new Error('should have thrown');
    } catch (e) {
      expect(e.code).toBe('LAYOUT_UNRECOGNIZED');
    }
  });

  // Control: the genuine fixture must still be recognized at every
  // rotation, including with a header or two missing -- the tightened
  // matcher/guard must not have collaterally broken real recognition.
  test('still recognizes the genuine fixture at every rotation, even with a header missing', () => {
    for (const rotation of [0, 90, 180, 270]) {
      const { words } = buildRegisterFixture({ rotation, omitHeaders: ['L or ILL'] });
      expect(() => extractBaptismalRows(words)).not.toThrow();
    }
  });

  // Important 2: `MANY_WORDS_UNPLACED`'s ratio must not be contaminated by
  // assignCells' fixed header-word baseline (see the threshold's own doc
  // comment in the source). A partial/last page of a register with only one
  // or two rows is an ordinary input, not an edge case -- it must not warn.
  test.each([1, 2, 3])('does not warn MANY_WORDS_UNPLACED on a clean %i-row fixture', (rows) => {
    const { words } = buildRegisterFixture({ rows });
    const out = extractBaptismalRows(words);
    expect(out.warnings).not.toContain('MANY_WORDS_UNPLACED');
  });

  // Genuinely bad page: real content dropped by a badly-cropped/compressed
  // scan, not by the (now-excluded) header baseline. This is a from-scratch
  // minimal spread rather than buildRegisterFixture, because reproducing a
  // genuine data-region drop through the full pipeline requires row spacing
  // tighter than the fixture's fixed 60px pitch (see below) -- and the
  // fixture's own geometry constants must not be changed.
  //
  // Mechanism: with 22px-tall words, detectRows' clustering tolerance is
  // ~19.8px. A normally-spaced register (60px row pitch, like the fixture)
  // gives each row a ~30px half-band -- bigger than the tolerance -- so
  // anything landing outside a row's band is, by construction, also far
  // enough from every anchor to register as its own new row candidate
  // (rescued via the ROW_ANCHOR_FALLBACK corroboration check, not dropped).
  // Compressing the rows to a 30px pitch shrinks the half-band to 15px,
  // *smaller* than the 19.8px tolerance: words placed 18px past the last
  // row's anchor (outside its 15px band, so genuinely dropped) still land
  // within 19.8px of that anchor for clustering purposes, so they quietly
  // merge into the real row's corroboration cluster instead of standing out
  // as a new one. Net effect: real handwriting-shaped content vanishes with
  // no other warning standing in for it -- exactly the failure
  // MANY_WORDS_UNPLACED exists to catch.
  test('warns MANY_WORDS_UNPLACED when real content is dropped by a badly compressed page', () => {
    const w = (text, cx, cy) => mkWord(text, cx, cy);
    const words = [];
    // Left page headers + title (5/5 matched).
    words.push(w('NO.', 60, 20), w('CHILD', 220, 20), w('PLACE', 400, 20),
      w('ILL', 560, 20), w('PARENTS', 720, 20), w('Baptismal', 300, 5));
    // Right page headers + title (5/5 matched).
    words.push(w('RESIDENTS', 1100, 20), w('BAPTISM', 1250, 20), w('MINISTER', 1400, 20),
      w('SPONSORS', 1550, 20), w('OBSERVATIONS', 1700, 20), w('Register', 1400, 5));
    // 2 real data rows, compressed to a 30px pitch (vs. the fixture's 60px).
    const rowCys = [70, 100];
    rowCys.forEach((cy, i) => {
      words.push(w(String(i + 1), 60, cy));
      words.push(w(`NAME${i}`, 220, cy), w(`PLACEV${i}`, 400, cy), w(`PARENTV${i}`, 720, cy));
      words.push(w(`RESIDV${i}`, 1100, cy), w(`DATEV${i}`, 1250, cy), w(`MINV${i}`, 1400, cy), w(`SPONV${i}`, 1550, cy));
    });
    // Real content, genuinely dropped: parked 18px past the last row's
    // anchor (outside its 15px half-band) but within the 19.8px clustering
    // tolerance of it, per the mechanism above.
    const lastRowCy = rowCys[rowCys.length - 1];
    const dropped = [];
    for (let i = 0; i < 20; i += 1) {
      dropped.push(w(`REAL${i}`, 200 + i * 25, lastRowCy + 18));
    }

    const clean = extractBaptismalRows(words);
    expect(clean.warnings).not.toContain('MANY_WORDS_UNPLACED');

    const out = extractBaptismalRows(words.concat(dropped));
    expect(out.warnings).toContain('MANY_WORDS_UNPLACED');
    // The real rows still come through correctly -- only the extra dropped
    // content is affected.
    expect(out.rows).toHaveLength(2);
    expect(out.rows[0].fields.nameOfChild.value).toBe('NAME0');
    expect(out.rows[1].fields.nameOfChild.value).toBe('NAME1');
  });

  // Critical 1: RIGHT_COLUMNS has no lineNo entry (the register only prints
  // row numbers on the LEFT page, by design), so detectRows' fallback path
  // is the structurally normal, expected outcome for the right page on
  // EVERY scan -- not a quality problem. Before this fix, ROW_ANCHOR_FALLBACK
  // fired unconditionally as a result, on every clean scan at every
  // rotation, which trains a reviewer to ignore the warnings list and buries
  // the case that actually matters (the LEFT page's NO. column being
  // illegible).
  test('does not warn ROW_ANCHOR_FALLBACK on a clean fixture at any rotation', () => {
    for (const rotation of [0, 90, 180, 270]) {
      const { words } = buildRegisterFixture({ rows: 3, rotation });
      const out = extractBaptismalRows(words);
      expect(out.warnings).not.toContain('ROW_ANCHOR_FALLBACK');
    }
  });

  // The left page DOES have a lineNo column, so a left-page NO. column that
  // is genuinely unreadable must still surface the warning.
  test('warns ROW_ANCHOR_FALLBACK when the left page NO. column is unreadable', () => {
    const { words } = buildRegisterFixture({ rows: 3, omitNoColumn: true });
    const out = extractBaptismalRows(words);
    expect(out.warnings).toContain('ROW_ANCHOR_FALLBACK');
  });

  // Edge case beyond the brief: one side of the spread has zero detected
  // rows (e.g. a page whose data rows are blank or unreadable) while the
  // other has real rows. Must not crash, and must still surface the
  // resulting row-count mismatch as a warning.
  test('handles one page having zero rows without crashing', () => {
    const { words } = buildRegisterFixture({ rows: 3, rotation: 0 });
    // Strip every right-page data-row word (residentsOf/dateOfBaptism/
    // minister/sponsors), leaving only its headers and title — the right
    // page then has no rows to detect, while the left page keeps its 3.
    const stripped = words.filter((w) => {
      const b = boxOf(w);
      const isRightPageDataRow = b.cx > GUTTER_X1 && b.cy >= FIRST_ROW_Y - ROW_H / 2;
      return !isRightPageDataRow;
    });

    const out = extractBaptismalRows(stripped);
    expect(out.warnings).toContain('ROW_COUNT_MISMATCH');
    expect(out.rows).toHaveLength(3);
    expect(out.rows[0].fields.nameOfChild.value).toBe('TESTA SAMPLE FAMILYONE');
    expect(out.rows[0].fields.minister.value).toBe('');
  });
});
