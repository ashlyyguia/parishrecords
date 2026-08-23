import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/models/baptismal_register_row.dart';

void main() {
  group('OcrField', () {
    test('flags low confidence for review', () {
      expect(OcrField(value: 'X', confidence: 0.42).needsReview, isTrue);
      expect(OcrField(value: 'X', confidence: 0.91).needsReview, isFalse);
    });

    test('flags inherited values for review even at high confidence', () {
      expect(
        OcrField(value: 'FR. ARCAPA', confidence: 0.99, inherited: true).needsReview,
        isTrue,
      );
    });

    test('does not flag an empty optional field', () {
      expect(OcrField(value: '', confidence: 0).needsReview, isFalse);
    });
  });

  group('BaptismalOcrScan.fromJson', () {
    final json = {
      'scanId': 'abc',
      'rotation': 90,
      'warnings': ['LAYOUT_UNCERTAIN'],
      'rows': [
        {
          'index': 0,
          'lineNo': '1',
          'fields': {
            'nameOfChild': {'value': 'JEZL ANTOINETTE', 'confidence': 0.71, 'inherited': false},
            'dateOfBaptism': {'value': '12 MAY 2016', 'confidence': 0.0, 'inherited': true},
          },
        },
      ],
    };

    test('parses rows, fields, rotation and warnings', () {
      final scan = BaptismalOcrScan.fromJson(json);
      expect(scan.scanId, 'abc');
      expect(scan.rotation, 90);
      expect(scan.warnings, ['LAYOUT_UNCERTAIN']);
      expect(scan.rows, hasLength(1));
      expect(scan.rows.first.lineNo, '1');
      expect(scan.rows.first.field('nameOfChild').value, 'JEZL ANTOINETTE');
      expect(scan.rows.first.field('dateOfBaptism').inherited, isTrue);
    });

    test('fills every known key even when the server omits it', () {
      final scan = BaptismalOcrScan.fromJson(json);
      for (final key in baptismalFieldKeys) {
        expect(scan.rows.first.fields.containsKey(key), isTrue, reason: 'missing $key');
      }
      expect(scan.rows.first.field('sponsors').value, '');
    });

    test('rows default to selected', () {
      expect(BaptismalOcrScan.fromJson(json).rows.first.selected, isTrue);
    });

    test('every field key has a label', () {
      for (final key in baptismalFieldKeys) {
        expect(baptismalFieldLabels[key], isNotNull, reason: 'no label for $key');
      }
    });
  });

  group('BaptismalOcrScan.fromJson edge cases', () {
    test('row with no fields map still exposes every known key', () {
      final scan = BaptismalOcrScan.fromJson({
        'scanId': 'x',
        'rotation': 0,
        'warnings': [],
        'rows': [
          {'index': 0, 'lineNo': '1'},
        ],
      });
      for (final key in baptismalFieldKeys) {
        expect(scan.rows.first.fields.containsKey(key), isTrue, reason: 'missing $key');
      }
      expect(scan.rows.first.field('nameOfChild').value, '');
    });

    test('a field whose JSON is null falls back to an empty field', () {
      final scan = BaptismalOcrScan.fromJson({
        'scanId': 'x',
        'rotation': 0,
        'warnings': [],
        'rows': [
          {
            'index': 0,
            'lineNo': '1',
            'fields': {'nameOfChild': null},
          },
        ],
      });
      expect(scan.rows.first.field('nameOfChild').value, '');
      expect(scan.rows.first.field('nameOfChild').confidence, 0);
      expect(scan.rows.first.field('nameOfChild').needsReview, isFalse);
    });

    test('confidence arriving as an int is parsed as a double', () {
      final scan = BaptismalOcrScan.fromJson({
        'scanId': 'x',
        'rotation': 0,
        'warnings': [],
        'rows': [
          {
            'index': 0,
            'lineNo': '1',
            'fields': {
              'nameOfChild': {'value': 'X', 'confidence': 1, 'inherited': false},
            },
          },
        ],
      });
      expect(scan.rows.first.field('nameOfChild').confidence, 1.0);
      expect(scan.rows.first.field('nameOfChild').needsReview, isFalse);
    });

    test('rows that is not a list yields an empty row list, not a crash', () {
      final scan = BaptismalOcrScan.fromJson({
        'scanId': 'x',
        'rotation': 0,
        'warnings': [],
        'rows': 'not-a-list',
      });
      expect(scan.rows, isEmpty);
    });

    test('empty warnings array parses to an empty list', () {
      final scan = BaptismalOcrScan.fromJson({
        'scanId': 'x',
        'rotation': 0,
        'warnings': [],
        'rows': [],
      });
      expect(scan.warnings, isEmpty);
    });
  });
}
