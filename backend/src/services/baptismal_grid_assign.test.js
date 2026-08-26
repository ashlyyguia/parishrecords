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
