import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/models/register_marriage_entry.dart';
import 'package:parishrecord/utils/manual_register_notes.dart';

void main() {
  test('toMarriageOcrNotesMap keeps flat register schema + provenance', () {
    final e = RegisterMarriageEntry(
      id: '1',
      lineNo: '3',
      groom: MarriagePartyInfo(name: 'M', parents: 'A & B'),
      bride: MarriagePartyInfo(name: 'A'),
      dateOfMarriage: 'Apr 18 1994',
      minister: 'Alf',
      licenseNumber: '88',
      observations: 'catholic',
    );
    final m = ManualRegisterNotes.toMarriageOcrNotesMap(
      volNo: '20-B', seriesNo: 'S1', entry: e, scanId: 'scan-1', imagePath: null);
    expect(m['source'], 'manual_marriage_register');
    expect(m['status'], 'official');
    expect(m['sacramentType'], 'marriage');
    expect((m['groom'] as Map)['name'], 'M');
    expect((m['bride'] as Map)['name'], 'A');
    expect(m['ocrScanId'], 'scan-1');
    expect(m['volNo'], '20-B');
    expect(ManualRegisterNotes.isManualMarriageMap(m), isTrue);
  });
}
