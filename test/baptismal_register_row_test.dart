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
        OcrField(value: 'FR. TESTMIN', confidence: 0.99, inherited: true).needsReview,
        isTrue,
      );
    });

    test('does not flag an empty optional field', () {
      expect(OcrField(value: '', confidence: 0).needsReview, isFalse);
    });

    test('empty short-circuits even when inherited and high confidence', () {
      expect(
        OcrField(value: '', confidence: 0.99, inherited: true).needsReview,
        isFalse,
      );
    });
  });

  group('OcrField edited state', () {
    test('a field parsed from JSON starts edited: false', () {
      final field = OcrField.fromJson({
        'value': 'X',
        'confidence': 0.99,
        'inherited': true,
      });
      expect(field.edited, isFalse);
      expect(field.needsReview, isTrue);
    });

    test('setValue on an inherited field clears needsReview', () {
      final row = BaptismalRegisterRow(
        lineNo: '1',
        fields: {
          'minister': OcrField(value: 'FR. TESTMIN', confidence: 0.99, inherited: true),
        },
      );
      expect(row.field('minister').needsReview, isTrue);

      row.setValue('minister', 'FR. TESTMIN JR.');

      final edited = row.field('minister');
      expect(edited.needsReview, isFalse);
      expect(edited.edited, isTrue);
      expect(edited.inherited, isTrue, reason: 'provenance is preserved, not erased');
      expect(edited.confidence, 0.99, reason: 'provenance is preserved, not erased');
    });

    test('setValue on a low-confidence field clears needsReview', () {
      final row = BaptismalRegisterRow(
        lineNo: '1',
        fields: {'sponsors': OcrField(value: 'illegible', confidence: 0.2)},
      );
      expect(row.field('sponsors').needsReview, isTrue);

      row.setValue('sponsors', 'JUAN DELA CRUZ');

      final edited = row.field('sponsors');
      expect(edited.needsReview, isFalse);
      expect(edited.edited, isTrue);
      expect(edited.confidence, 0.2, reason: 'provenance is preserved, not erased');
    });

    test('setValue to the same string still counts as reviewed', () {
      final field = OcrField(value: 'FR. TESTMIN', confidence: 0.99, inherited: true);
      final confirmed = field.copyWith(value: field.value);
      expect(confirmed.value, field.value);
      expect(confirmed.edited, isTrue);
      expect(confirmed.needsReview, isFalse);
    });

    test('copyWith with no value supplied preserves edited state', () {
      final edited = OcrField(value: 'X', confidence: 0.99, edited: true);
      final untouchedCopy = edited.copyWith();
      expect(untouchedCopy.edited, isTrue);
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
            'nameOfChild': {'value': 'TESTA SAMPLE', 'confidence': 0.71, 'inherited': false},
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
      expect(scan.rows.first.field('nameOfChild').value, 'TESTA SAMPLE');
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

    test('rotation arriving as a string falls back to 0, not a crash', () {
      final scan = BaptismalOcrScan.fromJson({
        'scanId': 'x',
        'rotation': 'not-a-number',
        'warnings': [],
        'rows': [],
      });
      expect(scan.rotation, 0);
    });

    test('warnings arriving as a string falls back to an empty list, not a crash', () {
      final scan = BaptismalOcrScan.fromJson({
        'scanId': 'x',
        'rotation': 0,
        'warnings': 'not-a-list',
        'rows': [],
      });
      expect(scan.warnings, isEmpty);
    });
  });
}
