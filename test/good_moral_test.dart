import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/models/record.dart';
import 'package:parishrecord/screens/records/certificate_layouts.dart';

void main() {
  group('RecordType.goodMoral', () {
    test('round-trips through its stored names', () {
      expect(RecordType.goodMoral.value, 'good_moral');
      expect(RecordType.goodMoral.label, 'Good Moral');
      for (final stored in [
        'good_moral',
        'goodMoral',
        'GOODMORAL',
        'Good Moral',
      ]) {
        expect(
          RecordTypeExtension.fromString(stored),
          RecordType.goodMoral,
          reason: stored,
        );
      }
    });

    test('the other types keep their names', () {
      expect(RecordTypeExtension.fromString('funeral'), RecordType.funeral);
      expect(RecordType.baptism.label, 'Baptism');
    });
  });

  group('Good Moral certificate layout', () {
    final layout = CertificateLayout.of(RecordType.goodMoral);

    test('uses its own form and fills every printed blank', () {
      expect(layout.background, 'assets/images/certificates/good_moral.jpg');
      expect(
        layout.slots.keys,
        containsAll([
          'name',
          'residentOf',
          'personOf',
          'knownAs',
          'fitFor',
          'fitFor2',
          'dated',
          'priest',
        ]),
      );
    });

    test('blanks run top to bottom in the order the form prints them', () {
      final ys = [
        for (final k in [
          'name',
          'residentOf',
          'personOf',
          'knownAs',
          'fitFor',
          'fitFor2',
        ])
          layout.slots[k]!.y,
      ];
      expect(ys, orderedEquals([...ys]..sort()));
      for (final s in layout.slots.values) {
        expect(s.x0, lessThan(s.x1));
        expect(s.y, inInclusiveRange(0, 1));
      }
    });

    test('offers Mr., Ms. and Mx. to circle, left to right', () {
      final marks = layout.marks;
      expect(marks.keys, ['Mr.', 'Ms.', 'Mx.']);
      expect(marks['Mr.']!.x1, lessThanOrEqualTo(marks['Ms.']!.x0));
      expect(marks['Ms.']!.x1, lessThanOrEqualTo(marks['Mx.']!.x0));
    });
  });
}
