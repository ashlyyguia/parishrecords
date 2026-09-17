import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/models/register_marriage_entry.dart';

void main() {
  test('fromScanJson maps groom/bride and shared fields', () {
    final e = RegisterMarriageEntry.fromScanJson({
      'lineNo': '47',
      'groom': {'name': 'Marlon', 'legalStatus': 'single', 'parents': 'A & B'},
      'bride': {'name': 'Ana', 'actualAddress': 'Ozamiz'},
      'dateOfMarriage': 'Apr 18 1994',
      'minister': 'Alfredo',
      'licenseNumber': '8817424',
      'observations': 'catholic',
    });
    expect(e.lineNo, '47');
    expect(e.groom.name, 'Marlon');
    expect(e.groom.legalStatus, 'single');
    expect(e.groom.parents, 'A & B');
    expect(e.bride.name, 'Ana');
    expect(e.bride.actualAddress, 'Ozamiz');
    expect(e.dateOfMarriage, 'Apr 18 1994');
    expect(e.minister, 'Alfredo');
    expect(e.licenseNumber, '8817424');
    expect(e.observations, 'catholic');
    expect(e.id, isNotEmpty);
    expect(e.selected, isTrue);
  });

  test('fromScanJson tolerates missing/blank fields', () {
    final e = RegisterMarriageEntry.fromScanJson({'groom': {'name': 'Solo'}});
    expect(e.lineNo, isNull);
    expect(e.groom.name, 'Solo');
    expect(e.bride.name, '');
    expect(e.dateOfMarriage, '');
    expect(e.id, isNotEmpty);
  });
}
