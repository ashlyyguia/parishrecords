const {
  extractMarriageRows,
  calibrateColumns,
  LEFT_COLUMNS,
  RIGHT_COLUMNS,
} = require('./marriage_register_layout');

// Upright word (rotation 0): vertices in tl, tr, br, bl order.
function word(text, x, y, w = 40, h = 12) {
  return {
    text,
    confidence: 90,
    vertices: [
      { x, y },
      { x: x + w, y },
      { x: x + w, y: y + h },
      { x, y: y + h },
    ],
  };
}

// A minimal but complete two-page marriage spread: titles, header row, and two
// entries (groom line + bride line each). Left x in [0,430], gutter gap, right
// x in [600,1000]. y grows downward.
function marriageSpread() {
  const words = [];
  // Titles (above the header band).
  words.push(word('Marriage', 150, 0));
  words.push(word('Register', 720, 0));
  // Left header row (y=40).
  words.push(word('NO', 10, 40, 24));
  words.push(word('CONTRACTING', 70, 40, 80));
  words.push(word('LEGAL', 170, 40, 40));
  words.push(word('STATUS', 170, 54, 40));
  words.push(word('ACTUAL', 240, 40, 40));
  words.push(word('ADDRESS', 240, 54, 40));
  words.push(word('BIRTH', 310, 40, 40));
  words.push(word('BAPTISM', 370, 40, 40));
  words.push(word('MARRIAGE', 410, 40, 40));
  // Right header row (y=40).
  words.push(word('PARENTS', 610, 40, 50));
  words.push(word('SPONSORS', 700, 40, 50));
  words.push(word('MINISTER', 800, 40, 50));
  words.push(word('LICENSE', 880, 40, 40));
  words.push(word('OBSERVATIONS', 940, 40, 50));
  // Entry 1: number "1" at y~100; groom line y~95, bride line y~130.
  words.push(word('1', 10, 100, 16));
  words.push(word('MARLON', 70, 95, 60)); // groom name (top)
  words.push(word('ANA', 70, 130, 40)); // bride name (bottom)
  words.push(word('single', 170, 95, 40));
  words.push(word('single', 170, 130, 40));
  words.push(word('Bunga', 240, 95, 40));
  words.push(word('Talic', 240, 130, 40));
  words.push(word('JAN', 410, 100, 40)); // marriage date (shared, spans entry)
  words.push(word('NILO', 610, 95, 40)); // groom parent (top)
  words.push(word('REMY', 610, 130, 40)); // bride parent (bottom)
  words.push(word('Ricky', 700, 100, 40)); // sponsor (shared)
  words.push(word('FrAlcher', 800, 100, 60)); // minister (shared)
  words.push(word('3518247', 880, 100, 50)); // license (shared)
  // Entry 2: number "2" at y~200; groom line y~195, bride line y~230.
  words.push(word('2', 10, 200, 16));
  words.push(word('MARK', 70, 195, 60));
  words.push(word('GHERYL', 70, 230, 60));
  words.push(word('single', 170, 195, 40));
  words.push(word('single', 170, 230, 40));
  words.push(word('FEB', 410, 200, 40));
  words.push(word('GENE', 610, 195, 40));
  words.push(word('SUSAN', 610, 230, 40));
  return words;
}

test('calibrateColumns matches the marriage left-page headers', () => {
  const words = marriageSpread().filter((w) => {
    const cx = (w.vertices[0].x + w.vertices[1].x) / 2;
    return cx < 500;
  });
  const cal = calibrateColumns(words, LEFT_COLUMNS);
  const matched = cal.columns.filter((c) => c.matched).map((c) => c.key);
  expect(matched).toEqual(expect.arrayContaining(['contractingParties', 'birth', 'baptism']));
});

test('a paired column splits into groom (top) and bride (bottom)', () => {
  const { rows } = extractMarriageRows(marriageSpread());
  expect(rows.length).toBeGreaterThanOrEqual(2);
  expect(rows[0].groom.name).toContain('MARLON');
  expect(rows[0].bride.name).toContain('ANA');
  expect(rows[0].groom.parents).toContain('NILO');
  expect(rows[0].bride.parents).toContain('REMY');
  // Shared columns land on the row / groom.
  expect(rows[0].groom.sponsors).toContain('Ricky');
  expect(rows[0].licenseNumber).toContain('3518247');
});

test('non-register page is rejected', () => {
  const words = [
    { text: 'memo', confidence: 80, vertices: [{ x: 0, y: 0 }, { x: 10, y: 0 }, { x: 10, y: 6 }, { x: 0, y: 6 }] },
  ];
  expect(() => extractMarriageRows(words)).toThrow(/LAYOUT_UNRECOGNIZED/);
});

test('RIGHT_COLUMNS declares the five right-page keys', () => {
  expect(RIGHT_COLUMNS.map((c) => c.key)).toEqual([
    'parents', 'sponsors', 'minister', 'licenseNo', 'observations',
  ]);
});
