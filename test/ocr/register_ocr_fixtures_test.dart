import 'package:flutter_test/flutter_test.dart';
import 'support/ocr_scoring.dart';
import 'support/register_ocr_fixture.dart';
import 'package:parishrecord/services/register_ocr_scan_helper.dart';

void main() {
  test('synthetic fixture replays through parser and scores well', () {
    final fixture = loadFixture('_synthetic');
    final expected = loadExpected('_synthetic');

    final entries =
        RegisterOcrScanHelper.parseEntriesFromCells(fixture.cells);
    final actual = entries.map(entryToFieldMap).toList();

    final score = scoreRows(expected: expected, actual: actual);
    // ignore: avoid_print
    print(score.report('_synthetic'));

    expect(score.rowRecall, greaterThanOrEqualTo(0.5));
    expect(score.fieldMeans['name'], greaterThan(0.5));
  });
}
