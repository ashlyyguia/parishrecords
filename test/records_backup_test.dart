import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/models/record.dart';
import 'package:parishrecord/services/records_backup.dart';

void main() {
  group('recordsToBackupJson', () {
    test('maps a populated record to the backup shape', () {
      final records = [
        ParishRecord(
          id: 'abc123',
          type: RecordType.marriage,
          name: 'Juan & Maria',
          date: DateTime.utc(2026, 9, 15, 10, 30),
          imagePath: '/scans/img.jpg',
          parish: 'San Isidro',
          notes: '{"lineNo":4}',
          certificateStatus: CertificateStatus.approved,
        ),
      ];

      final out = recordsToBackupJson(records);

      expect(out, hasLength(1));
      expect(out.first, {
        'id': 'abc123',
        'type': 'marriage',
        'name': 'Juan & Maria',
        'date': '2026-09-15T10:30:00.000Z',
        'imagePath': '/scans/img.jpg',
        'parish': 'San Isidro',
        'notes': '{"lineNo":4}',
        'certificateStatus': 'approved',
      });
    });

    test('preserves null imagePath, parish, and notes', () {
      final records = [
        ParishRecord(
          id: 'x',
          type: RecordType.baptism,
          name: 'Baby',
          date: DateTime.utc(2026, 1, 2),
        ),
      ];

      final map = recordsToBackupJson(records).first;

      expect(map['imagePath'], isNull);
      expect(map['parish'], isNull);
      expect(map['notes'], isNull);
      expect(map['type'], 'baptism');
      expect(map['certificateStatus'], 'pending');
    });

    test('returns an empty list for empty input', () {
      expect(recordsToBackupJson(const []), isEmpty);
    });
  });
}
