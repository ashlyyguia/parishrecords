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

test('flags GROOM_BRIDE_SPLIT_UNCERTAIN when both names land on one side', () => {
  const left = { cells: [cell('contracting_parties', 1, 40, 100, 200, 80)] };
  const leftWords = [word('Marlon', 50, 108), word('Ana', 90, 112)]; // both top
  const { warnings } = marriageGridToRows(left, leftWords, { cells: [] }, []);
  expect(warnings).toContain('GROOM_BRIDE_SPLIT_UNCERTAIN');
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
