const { gridToRows, GRID_KEY_TO_FIELD } = require('./baptismal_grid_assign');

// One word whose box-centre lands inside a given cell rect.
const wordAt = (text, cx, cy) => ({
  text,
  vertices: [
    { x: cx - 5, y: cy - 5 }, { x: cx + 5, y: cy - 5 },
    { x: cx + 5, y: cy + 5 }, { x: cx - 5, y: cy + 5 },
  ],
  confidence: 1,
});
const cell = (key, row, x, y, w, h) => ({ key, row, x, y, w, h });

test('maps grid snake_case keys to backend field keys', () => {
  expect(GRID_KEY_TO_FIELD.child_name).toBe('nameOfChild');
  expect(GRID_KEY_TO_FIELD.baptism_date).toBe('dateOfBaptism');
  expect(GRID_KEY_TO_FIELD.l_or_ill).toBeUndefined();
});

test('places words into the correct cell and row, joins left+right', () => {
  const leftPage = { cells: [
    cell('no', 0, 0, 0, 40, 40), cell('child_name', 0, 40, 0, 200, 40),
    cell('no', 1, 0, 40, 40, 40), cell('child_name', 1, 40, 40, 200, 40),
  ] };
  const rightPage = { cells: [
    cell('minister', 0, 0, 0, 200, 40), cell('baptism_date', 0, 200, 0, 120, 40),
    cell('minister', 1, 0, 40, 200, 40), cell('baptism_date', 1, 200, 40, 120, 40),
  ] };
  const leftWords = [wordAt('1', 20, 20), wordAt('JUAN', 140, 20), wordAt('2', 20, 60), wordAt('MARIA', 140, 60)];
  const rightWords = [wordAt('FR.PADRE', 100, 20), wordAt('12MAY2016', 260, 20)];

  const { rows } = gridToRows(leftPage, leftWords, rightPage, rightWords);
  expect(rows).toHaveLength(2);
  expect(rows[0].lineNo).toBe('1');
  expect(rows[0].fields.nameOfChild.value).toBe('JUAN');
  expect(rows[0].fields.minister.value).toBe('FR.PADRE');
  expect(rows[0].fields.dateOfBaptism.value).toBe('12MAY2016');
  expect(rows[1].fields.nameOfChild.value).toBe('MARIA');
});

test('ignored columns (l_or_ill, observations) never appear as fields', () => {
  const leftPage = { cells: [cell('l_or_ill', 0, 0, 0, 40, 40)] };
  const rightPage = { cells: [cell('observations', 0, 0, 0, 200, 40)] };
  const { rows } = gridToRows(leftPage, [wordAt('L', 20, 20)], rightPage, [wordAt('note', 100, 20)]);
  expect(rows[0].fields.legitimacy).toBeUndefined();
  expect(rows[0].fields.observations).toBeUndefined();
});

test('a word outside every cell is dropped, leaving the field empty', () => {
  const leftPage = { cells: [cell('child_name', 0, 40, 0, 200, 40)] };
  const { rows } = gridToRows(leftPage, [wordAt('STRAY', 500, 500)], { cells: [] }, []);
  expect(rows[0].fields.nameOfChild.value).toBe('');
});

test('drops the printed header row and numbers data rows from one', () => {
  // Row 0 is the printed column-header band; row 1 is the first real entry.
  const leftPage = { cells: [
    cell('no', 0, 0, 0, 40, 40), cell('child_name', 0, 40, 0, 200, 40),
    cell('no', 1, 0, 80, 40, 40), cell('child_name', 1, 40, 80, 200, 40),
  ] };
  const rightPage = { cells: [
    cell('baptism_date', 0, 0, 0, 120, 40),
    cell('baptism_date', 1, 0, 80, 120, 40),
  ] };
  const leftWords = [
    wordAt('No.', 20, 20), wordAt('Name', 60, 20), wordAt('of', 95, 20), wordAt('Child', 140, 20),
    wordAt('1', 20, 100), wordAt('JUAN', 140, 100),
  ];
  const rightWords = [
    wordAt('Date', 30, 20), wordAt('of', 60, 20), wordAt('Baptism', 100, 20),
    wordAt('12MAY2016', 60, 100),
  ];

  const { rows } = gridToRows(leftPage, leftWords, rightPage, rightWords);
  expect(rows).toHaveLength(1);
  expect(rows[0].lineNo).toBe('1');
  expect(rows[0].fields.nameOfChild.value).toBe('JUAN');
  expect(rows[0].fields.dateOfBaptism.value).toBe('12MAY2016');
});

test('joins the same physical row when one page has extra header rows (index offset)', () => {
  // Both halves share the y-axis. The right page caught a title + header band
  // as two extra rows, so the first entry is right-row 2 but left-row 0. They
  // must still be joined -- same y means same person -- and the two extra
  // right rows dropped, not paired with real entries.
  const leftPage = { cells: [
    cell('no', 0, 0, 200, 40, 40), cell('child_name', 0, 40, 200, 200, 40),
    cell('no', 1, 0, 280, 40, 40), cell('child_name', 1, 40, 280, 200, 40),
  ] };
  const rightPage = { cells: [
    cell('minister', 0, 0, 40, 200, 40),   // title band (y=40)
    cell('minister', 1, 0, 120, 200, 40),  // header labels (y=120)
    cell('baptism_date', 2, 200, 200, 120, 40), // entry 1 (y=200)
    cell('baptism_date', 3, 200, 280, 120, 40), // entry 2 (y=280)
  ] };
  const leftWords = [
    wordAt('1', 20, 220), wordAt('JUAN', 140, 220),
    wordAt('2', 20, 300), wordAt('MARIA', 140, 300),
  ];
  const rightWords = [
    wordAt('Register', 100, 60), wordAt('Baptism', 100, 140),
    wordAt('12MAY2016', 260, 220), wordAt('13MAY2016', 260, 300),
  ];

  const { rows } = gridToRows(leftPage, leftWords, rightPage, rightWords);
  const juan = rows.find((r) => r.fields.nameOfChild.value === 'JUAN');
  expect(juan).toBeDefined();
  expect(juan.fields.dateOfBaptism.value).toBe('12MAY2016');
});

// --- Lines written on or across a ruled line ----------------------------------
// A ruled page like the real register: a header band (row 0) then `n` entry
// rows of height 70 starting at y=100, with the given columns side by side.
function ruledPage(keys, n = 4) {
  const cells = [];
  keys.forEach((key, i) => {
    cells.push(cell(key, 0, i * 300, 0, 300, 100));
    for (let r = 1; r <= n; r += 1) cells.push(cell(key, r, i * 300, 100 + (r - 1) * 70, 300, 70));
  });
  return { cells };
}
// A word box 16px tall centred at (cx, cy).
const word = (text, cx, cy) => ({
  text,
  vertices: [
    { x: cx - 40, y: cy - 8 }, { x: cx + 40, y: cy - 8 },
    { x: cx + 40, y: cy + 8 }, { x: cx - 40, y: cy + 8 },
  ],
  confidence: 1,
});

test('a second sponsor written on the bottom rule stays with its own entry', () => {
  // Rows: 1 = 100-170, 2 = 170-240, 3 = 240-310, 4 = 310-380. Each entry's
  // second sponsor sits on that row's bottom rule; the last one just below
  // the table's bottom border.
  const left = ruledPage(['child_name']);
  const right = ruledPage(['sponsors']);
  const leftWords = [word('ANA', 150, 135), word('BEN', 150, 205), word('CIA', 150, 275), word('DAN', 150, 345)];
  const rightWords = [
    word('PEDRO', 150, 135), word('ROSA', 150, 170),
    word('JUAN', 150, 205), word('LINA', 150, 240),
    word('MARK', 150, 275), word('NENA', 150, 310),
    word('RUDY', 150, 345), word('TESS', 150, 382),
  ];
  const { rows } = gridToRows(left, leftWords, right, rightWords);
  expect(rows.map((r) => r.fields.sponsors.value)).toEqual([
    'PEDRO ROSA', 'JUAN LINA', 'MARK NENA', 'RUDY TESS',
  ]);
});

test('a place of birth written above its row joins the date below it', () => {
  // Each entry's place line is written on (or just over) the row's top rule,
  // the date in the row; the first place line crosses into the header band.
  const left = ruledPage(['child_name', 'place_and_birth_date']);
  const right = ruledPage(['minister']);
  const leftWords = [
    word('ANA', 150, 135), word('BEN', 150, 205), word('CIA', 150, 275), word('DAN', 150, 345),
    word('OZAMIZ', 450, 100), word('1 MAY 2009', 450, 140),
    word('OROQUIETA', 450, 166), word('2 JUNE 2010', 450, 210),
    word('CALAMBA', 450, 236), word('3 JULY 2011', 450, 280),
    word('TANGUB', 450, 306), word('4 AUG 2012', 450, 350),
  ];
  const { rows } = gridToRows(left, leftWords, right, []);
  expect(rows.map((r) => r.fields.placeAndBirthDate.value)).toEqual([
    'OZAMIZ 1 MAY 2009', 'OROQUIETA 2 JUNE 2010', 'CALAMBA 3 JULY 2011', 'TANGUB 4 AUG 2012',
  ]);
});

test('words sitting inside their rows are left where they are', () => {
  const left = ruledPage(['child_name', 'parents']);
  const leftWords = [
    word('ANA', 150, 120), word('CRUZ', 150, 155),
    word('BEN', 150, 190), word('REYES', 150, 225),
    word('CIA', 150, 260), word('LIM', 150, 295),
    word('DAN', 150, 330), word('TAN', 150, 365),
    word('UNKNOWN', 450, 120), word('ROSA CRUZ', 450, 155),
  ];
  const { rows } = gridToRows(left, leftWords, ruledPage(['minister']), []);
  expect(rows.map((r) => r.fields.nameOfChild.value)).toEqual(['ANA CRUZ', 'BEN REYES', 'CIA LIM', 'DAN TAN']);
  expect(rows[0].fields.parents.value).toBe('UNKNOWN ROSA CRUZ');
  expect(rows[1].fields.parents.value).toBe('');
});
