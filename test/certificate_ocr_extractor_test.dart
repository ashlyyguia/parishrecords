import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/models/record.dart';
import 'package:parishrecord/services/certificate_ocr_extractor.dart';

void main() {
  group('CertificateOcrExtractor — baptism (sample_cert Ligaya)', () {
    const ocrText = '''
ARCHDIOCESE OF OZAMIS
HOLY ROSARY PARISH
Oroquieta City
Certificate of
Baptism
This is to Certify:
That LIGAYA MARIA ORTIZ ABUHON
Child of RUFINO ABUNON
and AMADA ORTIZ
born in MOBOD, OROQUIETA CITY
on the 30th day of April
1958
Was Baptized
on the 13th day of July
1958
According to the Rite of the Roman Catholic Church
by the Rev. Fr. LUKE LYNCH
The Sponsor(s) being | MERCEDES VILLAHERMOSA
as appears from the Baptismal Register of this Church
Dated : January 8, 2026
Page : 179
Vol. : 20-B
Series : 1956-1958
Rev. FR. DANILO B. RUDINAS
Parish Priest / VICAR
''';

    late CertificateExtraction result;

    setUpAll(() {
      result = CertificateOcrExtractor.extract(ocrText, RecordType.baptism);
    });

    test('extracts child name', () {
      expect(result.values['fullName'], 'LIGAYA MARIA ORTIZ ABUHON');
    });

    test('extracts parents', () {
      expect(result.values['fatherName'], 'RUFINO ABUNON');
      expect(result.values['motherName'], 'AMADA ORTIZ');
    });

    test('extracts birth place', () {
      expect(result.values['birthPlace'], 'MOBOD, OROQUIETA CITY');
    });

    test('extracts birth and baptism dates', () {
      expect(result.values['birthDate'], '30 April 1958');
      expect(result.values['sacramentDate'], '13 July 1958');
    });

    test('extracts minister and sponsor', () {
      expect(result.values['minister'], 'LUKE LYNCH');
      expect(result.values['sponsors'], 'MERCEDES VILLAHERMOSA');
    });

    test('extracts registry footer', () {
      expect(result.values['dated'], 'January 8, 2026');
      expect(result.values['page'], '179');
      expect(result.values['vol'], '20-B');
      expect(result.values['series'], '1956-1958');
    });

    test('no missing required fields', () {
      expect(result.missingRequired, isEmpty);
    });
  });

  group('CertificateOcrExtractor — confirmation (sample_cert Doumar)', () {
    // Mimics ML Kit ordering where some values land above their labels.
    const ocrText = '''
ARCHDIOCESE OF OZAMIS
HOLY ROSARY PARISH
Oroquieta City
Certificate of
Confirmation
This is to Certify:
That DOUMAR ANTHONY TUBAC
Child of DOUGLAS TUBAC
and FELMARIE NILLAS
born in OROQUIETA CITY
on the 20th day of October
1999
Was Confirmed
on the 11th day of October
2025
According to the Rite of the Roman Catholic Church
FR ELIAS A. TABUCO
by the Rev. Fr.
ROSITA CABRERA
The Sponsor(s) being
as appears from the Confirmation Register of this Church
Dated : January 6, 2025
Page : 13
Vol. : 8
''';

    late CertificateExtraction result;

    setUpAll(() {
      result =
          CertificateOcrExtractor.extract(ocrText, RecordType.confirmation);
    });

    test('extracts name and parents', () {
      expect(result.values['fullName'], 'DOUMAR ANTHONY TUBAC');
      expect(result.values['fatherName'], 'DOUGLAS TUBAC');
      expect(result.values['motherName'], 'FELMARIE NILLAS');
    });

    test('extracts dates', () {
      expect(result.values['birthDate'], '20 October 1999');
      expect(result.values['sacramentDate'], '11 October 2025');
    });

    test('finds minister and sponsor on neighbouring lines', () {
      expect(result.values['minister'], 'FR ELIAS A. TABUCO');
      expect(result.values['sponsors'], 'ROSITA CABRERA');
    });

    test('no missing required fields', () {
      expect(result.missingRequired, isEmpty);
    });
  });

  group('certificateFieldsFor', () {
    test('every record type defines required fields', () {
      for (final type in RecordType.values) {
        final fields = certificateFieldsFor(type);
        expect(fields.where((f) => f.required), isNotEmpty,
            reason: 'no required fields for $type');
        final keys = fields.map((f) => f.key).toSet();
        expect(keys.length, fields.length,
            reason: 'duplicate field keys for $type');
      }
    });
  });
}
