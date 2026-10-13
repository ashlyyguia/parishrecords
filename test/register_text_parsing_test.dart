import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/utils/register_text_parsing.dart';

void main() {
  group('splitParentNames', () {
    test('OCR text with middle initials and no separator', () {
      expect(
        splitParentNames('EGLORIA M . PATEÑO LITO E . BALILI'),
        ['EGLORIA M. PATEÑO', 'LITO E. BALILI'],
      );
    });

    test('explicit separators', () {
      expect(splitParentNames('Jose Santos / Ana Cruz'),
          ['Jose Santos', 'Ana Cruz']);
      expect(splitParentNames('Jose Santos & Ana Cruz'),
          ['Jose Santos', 'Ana Cruz']);
      expect(splitParentNames('Jose Santos and Ana Cruz'),
          ['Jose Santos', 'Ana Cruz']);
    });

    test('a single name stays whole', () {
      expect(splitParentNames('Ana Cruz'), ['Ana Cruz']);
    });
  });

  group('motherAndFather', () {
    test('the parent sharing the family surname is the father', () {
      final p = motherAndFather(
        'LITO E . BALILI EGLORIA M . PATEÑO',
        familySurname: 'BALILI',
      );
      expect(p.father, 'LITO E. BALILI');
      expect(p.mother, 'EGLORIA M. PATEÑO');
    });

    test('mother first by default', () {
      final p = motherAndFather('EGLORIA M . PATEÑO LITO E . CRUZ');
      expect(p.mother, 'EGLORIA M. PATEÑO');
      expect(p.father, 'LITO E. CRUZ');
    });
  });

  group('splitPlaceAndDate', () {
    test('place then written date', () {
      final r = splitPlaceAndDate('Oroquieta City, May 5, 1995');
      expect(r.date, DateTime(1995, 5, 5));
      expect(r.place, 'Oroquieta City');
    });

    test('date first, numeric', () {
      final r = splitPlaceAndDate('05/12/1995 Bunga, Oroquieta');
      expect(r.date, DateTime(1995, 5, 12));
      expect(r.place, 'Bunga, Oroquieta');
    });

    test('day month year', () {
      final r = splitPlaceAndDate('12 Jan 1990 - Loboc');
      expect(r.date, DateTime(1990, 1, 12));
      expect(r.place, 'Loboc');
    });

    test('no date keeps the whole text as the place', () {
      final r = splitPlaceAndDate('Oroquieta City');
      expect(r.date, isNull);
      expect(r.place, 'Oroquieta City');
    });
  });
}
