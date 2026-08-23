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
          'nameOfChild': 'JEZL ANTOINETTE HITUTUAAN',
          'placeAndBirthDate': '19 FEBRUARY 2001',
          'legitimacy': 'L',
          'parents': 'LITA / HITUTUAAN',
          'residentsOf': 'P-2 CANITOAN',
          'dateOfBaptism': '12 MAY 2016',
          'minister': 'FR. PABLITO ARCAPA',
          'sponsors': 'JOMARIE / POL',
          'observations': 'Married to X',
        },
      );

  test('carries every register column including the two new ones', () {
    final map = build();
    expect(map['nameOfChild'], 'JEZL ANTOINETTE HITUTUAAN');
    expect(map['legitimacy'], 'L');
    expect(map['observations'], 'Married to X');
    expect(map['minister'], 'FR. PABLITO ARCAPA');
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
    expect(entry.name, 'JEZL ANTOINETTE HITUTUAAN');
    expect(entry.baptismDateText, '12 MAY 2016');
    expect(entry.minister, 'FR. PABLITO ARCAPA');
    expect(entry.parents, 'LITA / HITUTUAAN');
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
