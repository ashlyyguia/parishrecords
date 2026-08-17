import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/services/register_ocr_scan_helper.dart';

void main() {
  test('scanResultFromCloud builds baptism entries from positioned cells', () {
    final cells = <OcrLineBox>[
      const OcrLineBox(text: '1', top: 100, left: 10, width: 15, height: 20),
      const OcrLineBox(text: 'Alberto', top: 100, left: 120, width: 80, height: 20),
      const OcrLineBox(text: 'Saligumba', top: 100, left: 210, width: 90, height: 20),
      const OcrLineBox(text: '07 January 2008', top: 100, left: 320, width: 140, height: 20),
    ];
    final result = RegisterOcrScanHelper.scanResultFromCloud(
      cells,
      '1 Alberto Saligumba 07 January 2008',
      recordType: 'baptism',
    );
    expect(result.entries, isNotEmpty);
    expect(result.entries.first.name.toLowerCase(), contains('alberto'));
    expect(result.isMarriage, isFalse);
  });

  test('scanResultFromCloud handles empty cloud output without throwing', () {
    final result = RegisterOcrScanHelper.scanResultFromCloud(
      const [],
      '',
      recordType: 'baptism',
    );
    expect(result.entries, isA<List>());
  });
}
