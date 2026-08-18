import 'package:flutter_test/flutter_test.dart';
import 'support/ocr_scoring.dart';
import 'support/register_ocr_fixture.dart';
import 'package:parishrecord/services/register_ocr_scan_helper.dart';

void main() {
  test('baptism-left OCR.space fixture parses into clean, scored rows', () {
    final fixture = loadFixture('baptism_left');
    final expected = loadExpected('baptism_left');

    final scan = RegisterOcrScanHelper.scanResultFromCloud(
      fixture.cells,
      fixture.flatText,
      recordType: 'baptism',
    );
    final actual = scan.entries.map(entryToFieldMap).toList();
    final score = scoreRows(expected: expected, actual: actual);
    // ignore: avoid_print
    print(score.report('baptism_left'));

    expect(score.rowRecall, greaterThanOrEqualTo(0.9));
    expect(score.fieldMeans['name'], greaterThanOrEqualTo(0.6));
  });
}
