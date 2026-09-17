import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/models/register_marriage_entry.dart';
import 'package:parishrecord/models/record.dart';
import 'package:parishrecord/services/marriage_row_validation.dart';

void main() {
  test('missing groom or bride name is blocking', () {
    final e = RegisterMarriageEntry(
      id: '1', groom: MarriagePartyInfo(name: 'M'), bride: MarriagePartyInfo(name: ''));
    final issues = validateMarriageRows([e]);
    expect(issues.any((i) => i.blocking && i.field == 'brideName'), isTrue);
  });

  test('both names present -> no blocking issue', () {
    final e = RegisterMarriageEntry(
      id: '1', groom: MarriagePartyInfo(name: 'Marlon'), bride: MarriagePartyInfo(name: 'Ana'));
    expect(validateMarriageRows([e]).where((i) => i.blocking), isEmpty);
  });

  test('a one-character name is too short (blocking)', () {
    final e = RegisterMarriageEntry(
      id: '1', groom: MarriagePartyInfo(name: 'X'), bride: MarriagePartyInfo(name: 'Ana'));
    expect(issuesFor(e, 'groomName').where((i) => i.blocking), isNotEmpty);
  });

  test('unselected rows are not validated', () {
    final e = RegisterMarriageEntry(
      id: '1', groom: MarriagePartyInfo(name: ''), bride: MarriagePartyInfo(name: ''),
      selected: false);
    expect(validateMarriageRows([e]), isEmpty);
  });

  test('a couple already saved is flagged non-blocking (duplicate)', () {
    final e = RegisterMarriageEntry(
      id: '1', groom: MarriagePartyInfo(name: 'Marlon'), bride: MarriagePartyInfo(name: 'Ana'));
    final existing = ParishRecord(
      id: 'r1',
      name: 'Marlon & Ana',
      type: RecordType.marriage,
      date: DateTime(2023, 1, 7),
    );
    final issues = validateMarriageRows([e], existing: [existing]);
    expect(issues.any((i) => !i.blocking), isTrue);
    expect(issues.every((i) => !i.blocking), isTrue);
  });
}

Iterable<MarriageRowIssue> issuesFor(RegisterMarriageEntry e, String field) =>
    validateMarriageRows([e]).where((i) => i.field == field);
