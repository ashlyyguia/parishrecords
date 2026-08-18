import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/services/register_ocr_scan_helper.dart';

// Three evenly-pitched rows (pitch 50), each with a two-line child name and
// a recognized No. cell, across 5 columns (No, Name, Place&Birth, Parents,
// Residents). The reconstructor must yield 3 rows with merged names.
List<OcrLineBox> _syntheticCells() {
  final cells = <OcrLineBox>[];
  final names = [
    ['Alberto', 'Saligumba'],
    ['Elliana', 'Eltagon'],
    ['Erica', 'Dejeno'],
  ];
  final places = ['07 January 2008', '08 February 2016', '22 May 2015'];
  for (var r = 0; r < 3; r++) {
    final top = 100.0 + r * 50;
    cells.add(OcrLineBox(text: '${r + 1}', top: top, left: 10, width: 15, height: 18));
    cells.add(OcrLineBox(text: names[r][0], top: top, left: 140, width: 90, height: 18));
    cells.add(OcrLineBox(text: names[r][1], top: top + 20, left: 140, width: 110, height: 18));
    cells.add(OcrLineBox(text: places[r], top: top, left: 380, width: 150, height: 18));
    cells.add(OcrLineBox(text: 'Arnel / Edelina', top: top, left: 680, width: 200, height: 18));
    cells.add(OcrLineBox(text: 'Villaflor', top: top, left: 930, width: 120, height: 18));
  }
  return cells;
}

void main() {
  test('reconstructBaptismGrid yields one row per pitch, merging two-line names', () {
    final entries = RegisterOcrScanHelper.reconstructBaptismGrid(_syntheticCells());
    expect(entries, hasLength(3));
    expect(entries[0].name.toLowerCase(), contains('alberto'));
    expect(entries[0].name.toLowerCase(), contains('saligumba'));
    expect(entries[1].name.toLowerCase(), contains('elliana'));
    expect(entries[2].name.toLowerCase(), contains('erica'));
    expect(entries.map((e) => e.lineNo), ['1', '2', '3']);
  });

  test('returns empty for too few cells', () {
    expect(RegisterOcrScanHelper.reconstructBaptismGrid(const []), isEmpty);
  });
}
