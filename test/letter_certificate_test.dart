import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/models/record.dart';
import 'package:parishrecord/screens/records/letter_certificate.dart';

ParishRecord _record(RecordType type, String key, Map<String, dynamic> f) =>
    ParishRecord(
      id: 'r1',
      type: type,
      name: (f['fullName'] ?? 'X').toString(),
      date: DateTime(2026, 1, 1),
      notes: json.encode({key: f}),
    );

void main() {
  test('ordinal days', () {
    String o(int d) => ordinalDay(d).map((s) => s.text).join();
    expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 28, 31].map(o).toList(), [
      '1st',
      '2nd',
      '3rd',
      '4th',
      '11th',
      '12th',
      '13th',
      '21st',
      '22nd',
      '23rd',
      '28th',
      '31st',
    ]);
    expect(ordinalDay(4).last.superscript, isTrue);
  });

  test('No Record reads like the parish sample', () {
    final c = LetterCertificate.fromRecord(
      _record(RecordType.noRecord, 'noRecord', {
        'register': 'baptism',
        'fullName': 'Florida A. Nuqui',
        'sex': 'daughter',
        'father': 'Francisco Nuqui',
        'mother': 'Rosenda Abuton',
        'purpose': 'any legal purposes',
        'dateIssued': '2026-08-04',
        'parishPriest': 'REV. FR. DANILO B. RUDINAS',
        'priestPosition': 'Parish Vicar',
      }),
    );
    expect(c.title, 'CERTIFICATION');
    expect(
      c.bodyText,
      'This is to certify that the Baptismal record of FLORIDA A. NUQUI, '
      'daughter of Francisco Nuqui and Rosenda Abuton, and was supposed to '
      'have been baptized in this parish, could not be found in the Records '
      'of Baptism.\n'
      'This certification is issued upon the request of the above-mentioned '
      'name for any legal purposes.\n'
      'Given and sealed this 4th day of August, 2026 at the Holy Rosary '
      'Parish Office, Oroquieta City.',
    );
    expect(c.closing, 'Sincerely in Christ,');
    expect(c.signatory, 'REV. FR. DANILO B. RUDINAS');
    expect(c.position, 'Parish Vicar');
  });

  test('No Record follows the register searched', () {
    String body(String reg) => LetterCertificate.fromRecord(
      _record(RecordType.noRecord, 'noRecord', {
        'register': reg,
        'fullName': 'Ana Cruz',
        'sex': 'son',
        'father': 'Pedro Cruz',
        'dateIssued': '2026-08-04',
      }),
    ).bodyText;
    expect(
      body('marriage'),
      contains(
        'the Marriage record of ANA CRUZ, son of Pedro Cruz, and was supposed to have been married',
      ),
    );
    expect(body('marriage'), contains('Records of Marriage.'));
    expect(body('confirmation'), contains('been confirmed in this parish'));
    expect(body('death'), contains('the Death record of'));
    expect(
      body('death'),
      contains(
        'been buried in this parish, could not be found in the Records of Burial.',
      ),
    );
  });

  test('Good Moral reads like the parish sample', () {
    final c = LetterCertificate.fromRecord(
      _record(RecordType.goodMoral, 'goodMoral', {
        'fullName': 'Julie An P. Alvarez',
        'sex': 'daughter',
        'residentOf': 'P-3 Upper Lancangan, Oroquieta City, Misamis Occidental',
        'father': 'Garlan Alvarez',
        'mother': 'Sagrada Alvarez',
        'purpose':
            'avail youth Internship Program for Organic Agriculture (YIPOA)',
        'dateIssued': '2026-09-28',
        'parishPriest': 'REV. MSGR. MAXIMINO A. NARON, JR.',
        'priestPosition': 'Parish Priest',
      }),
    );
    expect(c.title, 'CERTIFICATE OF GOOD MORAL CHARACTER');
    expect(
      c.bodyText,
      'This is to certify that JULIE AN P. ALVAREZ, a resident of P-3 Upper '
      'Lancangan, Oroquieta City, Misamis Occidental, under the jurisdiction '
      'of Holy Rosary Parish, and the daughter of Garlan Alvarez and Sagrada '
      'Alvarez, is known to be of Good Moral Character and being a '
      'law-abiding citizen.\n'
      'This certificate is issued upon the request of the interested party '
      'to avail youth Internship Program for Organic Agriculture (YIPOA).\n'
      'Given and sealed this 28th day of September 2026, at the office of the '
      'Holy Rosary Parish, Oroquieta City.',
    );
    expect(c.closing, isNull);
  });

  test('older entries without the new fields still print sensibly', () {
    final gm = LetterCertificate.fromRecord(
      _record(RecordType.goodMoral, 'goodMoral', {
        'title': 'Ms.',
        'fullName': 'Maria Santos',
        'residentOf': 'Brgy. Lower Lamac, Oroquieta City',
        'personOf': 'good moral character',
        'purpose': 'employment',
        'dateIssued': '2026-10-01',
        'parishPriest': 'FR. DANILO B. RUDINAS',
      }),
    );
    expect(
      gm.bodyText,
      contains(
        'MARIA SANTOS, a resident of Brgy. Lower Lamac, Oroquieta City, under the jurisdiction of Holy Rosary Parish, is known',
      ),
    );
    expect(gm.bodyText, contains('interested party to use for employment.'));
    expect(gm.position, 'Parish Vicar');

    final nr = LetterCertificate.fromRecord(
      _record(RecordType.noRecord, 'noRecord', {
        'fullName': 'Jose Reyes',
        'residentOf': 'Poblacion',
        'dateIssued': '2026-10-01',
      }),
    );
    expect(
      nr.bodyText,
      contains(
        'the Baptismal record of JOSE REYES, who was supposed to have been baptized',
      ),
    );
    expect(nr.bodyText, contains('name for any legal purposes.'));
  });
}
