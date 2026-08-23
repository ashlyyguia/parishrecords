import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/models/baptismal_register_row.dart';
import 'package:parishrecord/models/record.dart';
import 'package:parishrecord/services/baptismal_row_validation.dart';

BaptismalRegisterRow row({
  String name = 'JEZL ANTOINETTE',
  String date = '12 MAY 2016',
  String birth = '19 FEBRUARY 2001',
  bool selected = true,
  String lineNo = '1',
}) {
  final r = BaptismalRegisterRow(
    lineNo: lineNo,
    fields: {for (final k in baptismalFieldKeys) k: OcrField(value: '', confidence: 0.9)},
    selected: selected,
  );
  r.setValue('nameOfChild', name);
  r.setValue('dateOfBaptism', date);
  r.setValue('placeAndBirthDate', birth);
  return r;
}

void main() {
  final now = DateTime(2026, 8, 22);

  test('accepts a complete row', () {
    expect(validateBaptismalRows([row()], now: now), isEmpty);
  });

  test('blocks a missing name', () {
    final issues = validateBaptismalRows([row(name: '  ')], now: now);
    expect(issues.single.field, 'nameOfChild');
    expect(issues.single.blocking, isTrue);
  });

  test('blocks a missing baptism date', () {
    final issues = validateBaptismalRows([row(date: '')], now: now);
    expect(issues.single.field, 'dateOfBaptism');
    expect(issues.single.blocking, isTrue);
  });

  test('blocks an unparseable baptism date', () {
    final issues = validateBaptismalRows([row(date: 'sometime in may')], now: now);
    expect(issues.single.field, 'dateOfBaptism');
    expect(issues.single.blocking, isTrue);
  });

  test('blocks a future baptism date', () {
    final issues = validateBaptismalRows([row(date: '1 JANUARY 2030')], now: now);
    expect(issues.single.blocking, isTrue);
    expect(issues.single.message, contains('future'));
  });

  test('blocks a baptism date before 1900', () {
    expect(validateBaptismalRows([row(date: '5 MAY 1899')], now: now).single.blocking, isTrue);
  });

  test('blocks a birth date after the baptism date', () {
    final issues = validateBaptismalRows(
      [row(date: '12 MAY 2016', birth: '19 FEBRUARY 2020')], now: now,
    );
    expect(issues.single.field, 'placeAndBirthDate');
    expect(issues.single.blocking, isTrue);
  });

  test('ignores an unparseable birth date rather than blocking', () {
    expect(
      validateBaptismalRows([row(birth: 'CAGAYAN DE ORO CITY')], now: now),
      isEmpty,
    );
  });

  test('skips unselected rows entirely', () {
    expect(validateBaptismalRows([row(name: '', selected: false)], now: now), isEmpty);
  });

  test('flags a duplicate of an existing record without blocking', () {
    final existing = [
      ParishRecord(
        id: '1', type: RecordType.baptism,
        name: 'jezl antoinette', date: DateTime(2016, 5, 12),
      ),
    ];
    final issues = validateBaptismalRows([row()], existing: existing, now: now);
    expect(issues.single.blocking, isFalse);
    expect(issues.single.message, contains('already'));
  });

  test('flags a duplicate between two selected rows', () {
    final issues = validateBaptismalRows([row(lineNo: '1'), row(lineNo: '2')], now: now);
    expect(issues.where((i) => !i.blocking), hasLength(1));
  });

  test('reports the row index so the UI can point at it', () {
    final issues = validateBaptismalRows([row(), row(name: '')], now: now);
    expect(issues.single.rowIndex, 1);
  });

  test('baptismDateOf parses the register format', () {
    expect(baptismDateOf(row(date: '12 MAY 2016')), DateTime(2016, 5, 12));
    expect(baptismDateOf(row(date: 'nonsense')), isNull);
  });
}
