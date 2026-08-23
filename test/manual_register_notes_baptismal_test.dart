import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/utils/manual_register_notes.dart';

void main() {
  Map<String, dynamic> build() => ManualRegisterNotes.toBaptismalOcrNotesMap(
        volNo: '4',
        seriesNo: '2016',
        lineNo: '1',
        scanId: 'scan-1',
        imagePath: 'baptism_scans/2026/scan-1.jpg',
        fields: const {
          'nameOfChild': 'TESTA SAMPLE FAMILYONE',
          'placeAndBirthDate': '19 FEBRUARY 2001',
          'legitimacy': 'L',
          'parents': 'PARENTA / FAMILYONE',
          'residentsOf': 'ZONE-1 TESTVILLE',
          'dateOfBaptism': '12 MAY 2016',
          'minister': 'FR. TEST CLERIC',
          'sponsors': 'SPONSORA / ONE',
          'observations': 'Married to X',
        },
      );

  test('carries every register column including the two new ones', () {
    final map = build();
    expect(map['nameOfChild'], 'TESTA SAMPLE FAMILYONE');
    expect(map['legitimacy'], 'L');
    expect(map['observations'], 'Married to X');
    expect(map['minister'], 'FR. TEST CLERIC');
    expect(map['volNo'], '4');
    expect(map['lineNo'], '1');
  });

  test('records provenance', () {
    final map = build();
    expect(map['source'], 'baptismal_ocr_vision');
    expect(map['sacramentType'], 'baptism');
    expect(map['ocrScanId'], 'scan-1');
    expect(map['originalImagePath'], 'baptism_scans/2026/scan-1.jpg');
  });

  test('stays readable by the existing decoder as a flat baptism layout', () {
    final decoded = ManualRegisterNotes.tryDecode(jsonEncode(build()))!;
    expect(ManualRegisterNotes.isManualBaptismMap(decoded), isTrue);
    expect(ManualRegisterNotes.usesFlatRegisterLayout(decoded), isTrue);
    expect(ManualRegisterNotes.isManualMarriageMap(decoded), isFalse);
  });

  test('converts to a RegisterOcrEntry through the existing path', () {
    final entry = ManualRegisterNotes.entryFromMap(build());
    expect(entry.name, 'TESTA SAMPLE FAMILYONE');
    expect(entry.baptismDateText, '12 MAY 2016');
    expect(entry.minister, 'FR. TEST CLERIC');
    expect(entry.parents, 'PARENTA / FAMILYONE');
  });

  test('omitted optional fields become empty strings, not null', () {
    final map = ManualRegisterNotes.toBaptismalOcrNotesMap(
      volNo: '', seriesNo: '', lineNo: '2', scanId: 's', imagePath: null,
      fields: const {'nameOfChild': 'A', 'dateOfBaptism': '1 JAN 2020'},
    );
    expect(map['observations'], '');
    expect(map['legitimacy'], '');
    expect(map['originalImagePath'], isNull);
  });
}
