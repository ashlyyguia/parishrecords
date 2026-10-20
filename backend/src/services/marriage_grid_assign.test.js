const { marriageGridToRows } = require('./marriage_grid_assign');

// One cell per (row,key). Row 1 = header, row 2 = entry with groom top / bride bottom.
function word(text, x, y) {
  return {
    text,
    confidence: 90,
    vertices: [{ x, y }, { x: x + 10, y }, { x: x + 10, y: y + 6 }, { x, y: y + 6 }],
  };
}
function cell(key, row, x, y, w, h) {
  return { key, row, x, y, w, h };
}

test('splits a paired cell into groom (top) and bride (bottom)', () => {
  const left = {
    cells: [
      cell('no', 1, 0, 100, 40, 80),
      cell('contracting_parties', 1, 40, 100, 200, 80),
      cell('marriage_date', 1, 240, 100, 120, 80),
    ],
  };
  const leftWords = [
    word('47', 5, 110),
    word('Marlon', 50, 110), // top half -> groom
    word('Ana', 50, 160), // bottom half -> bride
    word('1994', 250, 110), // shared
  ];
  const right = { cells: [] };
  const { rows } = marriageGridToRows(left, leftWords, right, []);
  expect(rows).toHaveLength(1);
  expect(rows[0].groom.name).toBe('Marlon');
  expect(rows[0].bride.name).toBe('Ana');
  expect(rows[0].dateOfMarriage).toBe('1994');
  expect(rows[0].lineNo).toBe('47');
});

test('keeps a two-line groom together when the text sits low in the cell band', () => {
  // Real IMG_20260915_094054_545 entry 1: the CV row band (515..666, mid 591)
  // is taller than the four printed lines, which sit low in it. The groom's
  // second line (MEJORADA, cy 594) is just below the geometric cell midpoint,
  // so a cell-midpoint split misfiles it as the bride. Splitting at the text's
  // own vertical extent keeps the groom's two lines together.
  const left = {
    cells: [cell('contracting_parties', 1, 40, 515, 400, 151)],
  };
  const y = (v) => v - 3; // word() offsets the center by +3
  const leftWords = [
    word('JOHN', 60, y(563)), word('REYNAN', 120, y(563)),
    word('MEJORADA', 90, y(594)),
    word('MERA', 60, y(636)),
    word('MAGNAONG', 90, y(661)),
  ];
  const { rows } = marriageGridToRows(left, leftWords, { cells: [] }, []);
  expect(rows[0].groom.name).toBe('JOHN REYNAN MEJORADA');
  expect(rows[0].bride.name).toBe('MERA MAGNAONG');
});

test('flags GROOM_BRIDE_SPLIT_UNCERTAIN when both names land on one side', () => {
  const left = { cells: [cell('contracting_parties', 1, 40, 100, 200, 80)] };
  const leftWords = [word('Marlon', 50, 108), word('Ana', 90, 112)]; // both top
  const { warnings } = marriageGridToRows(left, leftWords, { cells: [] }, []);
  expect(warnings).toContain('GROOM_BRIDE_SPLIT_UNCERTAIN');
});

test('strips a NO-column entry number that bled into a name cell', () => {
  // The printed entry digit is centred on the band and can fall a little past
  // the narrow NO column into contracting parties, prefixing a name like
  // "3 ALYSSA BALABAG". A person's name never starts with a digit, so drop it.
  const left = { cells: [cell('contracting_parties', 1, 40, 100, 400, 160)] };
  const leftWords = [
    word('JAY', 60, 110), word('BUNAO', 70, 130), // groom
    word('3', 45, 198), word('ALYSSA', 60, 200), word('BALABAG', 70, 220), // bride + stray digit
  ];
  const { rows } = marriageGridToRows(left, leftWords, { cells: [] }, []);
  expect(rows[0].groom.name).toBe('JAY BUNAO');
  expect(rows[0].bride.name).toBe('ALYSSA BALABAG');
});

test('keeps a leading number in non-name fields (e.g. a birth date)', () => {
  // birth ("datesPlaceOfBirth") legitimately starts with a day/year number.
  const left = { cells: [cell('birth', 1, 40, 100, 400, 160)] };
  const leftWords = [
    word('1994', 60, 110), word('APRIL', 120, 110), // groom birth
    word('1999', 60, 200), word('MAY', 120, 200), // bride birth
  ];
  const { rows } = marriageGridToRows(left, leftWords, { cells: [] }, []);
  expect(rows[0].groom.datesPlaceOfBirth).toBe('1994 APRIL');
  expect(rows[0].bride.datesPlaceOfBirth).toBe('1999 MAY');
});

test('sponsors (shared right col) go to groom.sponsors', () => {
  const right = { cells: [cell('sponsors', 1, 0, 100, 200, 80)] };
  const rightWords = [word('Victor', 10, 120), word('Amalia', 60, 120)];
  const { rows } = marriageGridToRows(
    { cells: [cell('contracting_parties', 1, 0, 100, 10, 80)] },
    [word('X', 1, 110)],
    right,
    rightWords,
  );
  expect(rows[0].groom.sponsors).toContain('Victor');
});

test('parents (paired right col) split into groom.parents / bride.parents', () => {
  const right = { cells: [cell('parents', 1, 0, 100, 200, 80)] };
  const rightWords = [word('Nilo', 10, 110), word('Remy', 10, 160)];
  const { rows } = marriageGridToRows(
    { cells: [cell('contracting_parties', 1, 0, 100, 10, 80)] },
    [word('X', 1, 110)],
    right,
    rightWords,
  );
  expect(rows[0].groom.parents).toBe('Nilo');
  expect(rows[0].bride.parents).toBe('Remy');
});

test('a single word in a paired cell is not flagged uncertain', () => {
  const left = { cells: [cell('contracting_parties', 1, 40, 100, 200, 80)] };
  const { warnings, rows } = marriageGridToRows(left, [word('Marlon', 50, 108)], { cells: [] }, []);
  expect(warnings).not.toContain('GROOM_BRIDE_SPLIT_UNCERTAIN');
  expect(rows[0].groom.name).toBe('Marlon');
  expect(rows[0].bride.name).toBe('');
});

// A register-sized grid: header row 0, then `n` entry rows of height `h` from
// y = top, with the given column keys side by side.
function grid(keys, { n = 5, top = 100, h = 100, colW = 200, headerH = 60 } = {}) {
  const cells = [];
  keys.forEach((key, i) => {
    cells.push(cell(key, 0, i * colW, top - headerH, colW, headerH));
    for (let r = 1; r <= n; r += 1) cells.push(cell(key, r, i * colW, top + (r - 1) * h, colW, h));
  });
  return { width: keys.length * colW, height: top + n * h + 50, cells };
}
// A word box of handwriting height (word() is 6 px tall).
function tall(text, x, y, h = 20) {
  return {
    text,
    confidence: 90,
    vertices: [{ x, y }, { x: x + 50, y }, { x: x + 50, y: y + h }, { x, y: y + h }],
  };
}

test('reads a cell line by line, left to right, even when a line drifts', () => {
  const left = grid(['contracting_parties']);
  // "JOHN" sits 4 px lower than "REYNAN" on the same handwritten line.
  const words = [
    tall('REYNAN', 80, 102), tall('JOHN', 20, 108),
    tall('MEJORADA', 60, 128),
    tall('MERA', 20, 152), tall('MAGNAONG', 60, 174),
  ];
  const { rows } = marriageGridToRows(left, words, { cells: [] }, []);
  expect(rows[1].groom.name).toBe('JOHN REYNAN MEJORADA');
  expect(rows[1].bride.name).toBe('MERA MAGNAONG');
});

test('takes words written past the outermost column edge into that column', () => {
  const left = grid(['contracting_parties', 'marriage_date']);
  left.width = 500; // the date column ends at 400, the page at 500
  const words = [word('JUAN', 20, 120), word('NOVEMBER', 410, 110), word('2022', 420, 170)];
  const { rows } = marriageGridToRows(left, words, { cells: [] }, []);
  expect(rows[1].dateOfMarriage).toBe('NOVEMBER 2022');
});

test('drops a stray entry number wherever it lands in a name', () => {
  const left = grid(['contracting_parties']);
  const words = [tall('RICHARD', 20, 110), tall('12', 140, 112), tall('CAMACHO', 75, 110)];
  const { rows } = marriageGridToRows(left, words, { cells: [] }, []);
  expect(rows[1].groom.name).toBe('RICHARD CAMACHO');
});

test('a full entry pushes a line written above its rule back into its own entry', () => {
  // Near the spine every entry's first parent is written just above the grid
  // line, so by position alone each entry would hold its neighbour's last
  // parent. Each entry holds four lines; the cascade puts them back.
  const right = grid(['parents'], { n: 3 });
  const words = [];
  const names = [['A1', 'A2', 'A3', 'A4'], ['B1', 'B2', 'B3', 'B4'], ['C1', 'C2', 'C3', 'C4']];
  names.forEach((entry, e) => {
    entry.forEach((nm, k) => {
      // Lines at -8, 17, 42, 67 px from the entry's top rule: the first one is
      // above it (in the header for entry 1, in the previous entry otherwise).
      words.push(word(nm, 20, 100 + e * 100 - 11 + k * 25));
    });
  });
  const { rows } = marriageGridToRows({ cells: [] }, [], right, words);
  const byRow = Object.fromEntries(rows.map((r) => [r.index, `${r.groom.parents} / ${r.bride.parents}`]));
  expect(byRow[1]).toBe('A1 A2 / A3 A4');
  expect(byRow[2]).toBe('B1 B2 / B3 B4');
  expect(byRow[3]).toBe('C1 C2 / C3 C4');
});
