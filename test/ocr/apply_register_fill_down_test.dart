import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/models/register_ocr_entry.dart';
import 'package:parishrecord/services/register_ocr_scan_helper.dart';

RegisterOcrEntry _row(String name, {bool selected = true}) =>
    RegisterOcrEntry(id: name, name: name, rawLine: '', selected: selected);

void main() {
  test('fills date (+parsed) and minister on selected rows only', () {
    final a = _row('Alderto');
    final b = _row('Elliana', selected: false);
    final n = RegisterOcrScanHelper.applyRegisterFillDown(
      [a, b],
      date: '16 May 2016',
      minister: 'Fr. Daryl Rosales',
    );
    expect(n, 1);
    expect(a.baptismDateText, '16 May 2016');
    expect(a.date, DateTime(2016, 5, 16));
    expect(a.minister, 'Fr. Daryl Rosales');
    // untouched
    expect(b.baptismDateText, '');
    expect(b.date, isNull);
    expect(b.minister, '');
  });

  test('returns 0 when nothing to apply', () {
    final a = _row('x');
    expect(RegisterOcrScanHelper.applyRegisterFillDown([a]), 0);
    expect(a.baptismDateText, '');
  });

  test('keeps baptismDateText even when the date is unparseable', () {
    final a = _row('x');
    RegisterOcrScanHelper.applyRegisterFillDown([a], date: 'not a date');
    expect(a.baptismDateText, 'not a date');
    expect(a.date, isNull);
  });
}
