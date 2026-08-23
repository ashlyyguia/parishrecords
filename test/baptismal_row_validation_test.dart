import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/models/baptismal_register_row.dart';
import 'package:parishrecord/models/record.dart';
import 'package:parishrecord/services/baptismal_row_validation.dart';

BaptismalRegisterRow row({
  String name = 'TESTA SAMPLE',
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
        name: 'testa sample', date: DateTime(2016, 5, 12),
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

  // FIX 11 regression: `RegisterOcrParser._safeDate` builds dates with
  // `DateTime(y, m, d)`, which silently ROLLS OVER an invalid day instead of
  // rejecting it -- `DateTime(2016, 2, 31)` comes back as 2 March 2016, not
  // an error. An OCR misread of "31 FEBRUARY 2016" would otherwise validate
  // cleanly and save as the wrong calendar date with no warning anywhere.
  // `register_ocr_parser.dart` is on the do-not-modify list, so the guard
  // lives in `baptismal_row_validation.dart`'s `baptismDateOf` instead.
  test('baptismDateOf rejects "31 FEBRUARY 2016" instead of silently rolling over to March', () {
    expect(baptismDateOf(row(date: '31 FEBRUARY 2016')), isNull);
  });

  test('blocks "31 FEBRUARY 2016" as a baptism date rather than saving 2 March 2016', () {
    final issues = validateBaptismalRows([row(date: '31 FEBRUARY 2016')], now: now);
    final dateIssue = issues.singleWhere((i) => i.field == 'dateOfBaptism');
    expect(dateIssue.blocking, isTrue);
  });

  test('baptismDateOf rejects "32 MAY 2016" (no valid day 32 in any month)', () {
    expect(baptismDateOf(row(date: '32 MAY 2016')), isNull);
  });

  test('blocks "32 MAY 2016" as a baptism date', () {
    final issues = validateBaptismalRows([row(date: '32 MAY 2016')], now: now);
    final dateIssue = issues.singleWhere((i) => i.field == 'dateOfBaptism');
    expect(dateIssue.blocking, isTrue);
  });

  // Control: a genuinely valid written date must still round-trip cleanly --
  // the guard must not reject legitimate dates.
  test('does not reject a genuinely valid written date', () {
    expect(baptismDateOf(row(date: '29 FEBRUARY 2016')), DateTime(2016, 2, 29));
  });

  test('does not block when the birth date equals the baptism date', () {
    final issues = validateBaptismalRows(
      [row(date: '12 MAY 2016', birth: '12 MAY 2016')],
      now: now,
    );
    expect(issues, isEmpty);
  });

  test('does not flag a duplicate when one of the pair is unselected', () {
    final issues = validateBaptismalRows(
      [row(lineNo: '1'), row(lineNo: '2', selected: false)],
      now: now,
    );
    expect(issues, isEmpty);
  });

  test('does not flag same name with different baptism dates as duplicate', () {
    final issues = validateBaptismalRows(
      [row(lineNo: '1', date: '12 MAY 2016'), row(lineNo: '2', date: '13 MAY 2016')],
      now: now,
    );
    expect(issues.where((i) => !i.blocking), isEmpty);
  });

  test('treats names differing only by case and surrounding whitespace as duplicates', () {
    final issues = validateBaptismalRows(
      [
        row(lineNo: '1', name: 'Testa Sample'),
        row(lineNo: '2', name: '  TESTA SAMPLE  '),
      ],
      now: now,
    );
    final dupIssues = issues.where((i) => !i.blocking).toList();
    expect(dupIssues, hasLength(1));
    expect(dupIssues.single.field, 'nameOfChild');
    expect(dupIssues.single.rowIndex, 1);
  });

  test('an empty row list has no issues', () {
    expect(validateBaptismalRows([], now: now), isEmpty);
  });

  test('a list where every row is unselected has no issues', () {
    final issues = validateBaptismalRows(
      [row(lineNo: '1', selected: false), row(lineNo: '2', name: '', selected: false)],
      now: now,
    );
    expect(issues, isEmpty);
  });

  test('ignores existing non-baptism records for duplicate purposes', () {
    final existing = [
      ParishRecord(
        id: '1', type: RecordType.marriage,
        name: 'testa sample', date: DateTime(2016, 5, 12),
      ),
      ParishRecord(
        id: '2', type: RecordType.funeral,
        name: 'testa sample', date: DateTime(2016, 5, 12),
      ),
      ParishRecord(
        id: '3', type: RecordType.confirmation,
        name: 'testa sample', date: DateTime(2016, 5, 12),
      ),
    ];
    final issues = validateBaptismalRows([row()], existing: existing, now: now);
    expect(issues, isEmpty);
  });

  test('a row with both a missing name and an unparseable date reports both issues', () {
    final issues = validateBaptismalRows(
      [row(name: '  ', date: 'sometime in may')],
      now: now,
    );
    expect(issues, hasLength(2));

    final nameIssue = issues.singleWhere((i) => i.field == 'nameOfChild');
    expect(nameIssue.blocking, isTrue);
    expect(nameIssue.rowIndex, 0);

    final dateIssue = issues.singleWhere((i) => i.field == 'dateOfBaptism');
    expect(dateIssue.blocking, isTrue);
    expect(dateIssue.rowIndex, 0);
  });
}
