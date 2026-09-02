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
