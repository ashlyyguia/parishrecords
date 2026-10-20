import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/record.dart';

/// Office-issued certificates written as a letter on A4 bond paper — the
/// Certificate of Good Moral Character and the Certificate of No Record
/// ("CERTIFICATION") — following the parish's own typed samples.
///
/// The wording is built once as [LetterCertificate] (plain spans with bold /
/// underline / superscript flags) and drawn twice from it: on screen by
/// [LetterCertificatePage] and into the PDF by [LetterCertificate.buildPdf],
/// so the preview and the printout say exactly the same thing.

/// A priest who signs these certificates, offered as a quick pick.
class CertificateSignatory {
  final String name;
  final String position;
  const CertificateSignatory(this.name, this.position);
}

const kCertificateSignatories = [
  CertificateSignatory('REV. MSGR. MAXIMINO A. NARON, JR.', 'Parish Priest'),
  CertificateSignatory('REV. FR. DANILO B. RUDINAS', 'Parish Vicar'),
];

/// The register a Certificate of No Record says was searched.
enum NoRecordRegister { baptism, marriage, confirmation, death }

extension NoRecordRegisterText on NoRecordRegister {
  String get id => name;

  /// "the Baptismal record of …"
  String get adjective => const {
    NoRecordRegister.baptism: 'Baptismal',
    NoRecordRegister.marriage: 'Marriage',
    NoRecordRegister.confirmation: 'Confirmation',
    NoRecordRegister.death: 'Death',
  }[this]!;

  /// "… was supposed to have been baptized in this parish"
  String get verb => const {
    NoRecordRegister.baptism: 'baptized',
    NoRecordRegister.marriage: 'married',
    NoRecordRegister.confirmation: 'confirmed',
    NoRecordRegister.death: 'buried',
  }[this]!;

  /// "… could not be found in the Records of Baptism."
  String get book => const {
    NoRecordRegister.baptism: 'Baptism',
    NoRecordRegister.marriage: 'Marriage',
    NoRecordRegister.confirmation: 'Confirmation',
    NoRecordRegister.death: 'Burial',
  }[this]!;

  /// Form label.
  String get label => const {
    NoRecordRegister.baptism: 'Baptism',
    NoRecordRegister.marriage: 'Marriage',
    NoRecordRegister.confirmation: 'Confirmation',
    NoRecordRegister.death: 'Death / Burial',
  }[this]!;

  static NoRecordRegister fromId(String? id) {
    final v = (id ?? '').trim().toLowerCase();
    for (final r in NoRecordRegister.values) {
      if (r.name == v) return r;
    }
    if (v == 'funeral' || v == 'burial') return NoRecordRegister.death;
    return NoRecordRegister.baptism;
  }
}

/// A run of certificate text.
class LetterSpan {
  final String text;
  final bool bold;
  final bool underline;
  final bool superscript;
  const LetterSpan(
    this.text, {
    this.bold = false,
    this.underline = false,
    this.superscript = false,
  });
}

/// "4" + superscript "th".
List<LetterSpan> ordinalDay(int day, {bool bold = true}) {
  final suffix = (day % 100 >= 11 && day % 100 <= 13)
      ? 'th'
      : const {1: 'st', 2: 'nd', 3: 'rd'}[day % 10] ?? 'th';
  return [
    LetterSpan('$day', bold: bold),
    LetterSpan(suffix, bold: bold, superscript: true),
  ];
}

/// "Francisco Nuqui and Rosenda Abuton", one name alone, or ''.
String joinParents(String father, String mother) {
  final names = [father.trim(), mother.trim()].where((n) => n.isNotEmpty);
  return names.join(' and ');
}

class LetterCertificate {
  final bool isNoRecord;
  final String title;
  final List<LetterSpan> salutation;
  final List<List<LetterSpan>> paragraphs;
  final String? closing;
  final String signatory;
  final String position;

  const LetterCertificate({
    required this.isNoRecord,
    required this.title,
    required this.salutation,
    required this.paragraphs,
    required this.closing,
    required this.signatory,
    required this.position,
  });

  /// Plain text of the body, for tests and accessibility.
  String get bodyText =>
      paragraphs.map((p) => p.map((s) => s.text).join()).join('\n');

  static Map<String, dynamic> _fields(ParishRecord record, String key) {
    try {
      final decoded = json.decode(record.notes ?? '');
      if (decoded is Map && decoded[key] is Map) {
        return Map<String, dynamic>.from(decoded[key] as Map);
      }
    } catch (_) {}
    return const {};
  }

  /// Position that goes with a signing priest's name: the one stored, else
  /// the matching quick pick, else Parish Priest.
  static String positionFor(String priest, String stored) {
    if (stored.trim().isNotEmpty) return stored.trim();
    final p = priest.toUpperCase().replaceAll(RegExp(r'^REV\.?\s+'), '');
    for (final s in kCertificateSignatories) {
      if (s.name.toUpperCase().contains(p) && p.isNotEmpty) return s.position;
    }
    return 'Parish Priest';
  }

  /// The certificate for a Good Moral or No Record entry, from the fields its
  /// form stored in the notes. Entries saved with the older fill-in-the-blank
  /// form (no parents, purpose "fit person for …") still print sensibly.
  factory LetterCertificate.fromRecord(ParishRecord record) {
    final noRecord = record.type == RecordType.noRecord;
    final f = _fields(record, noRecord ? 'noRecord' : 'goodMoral');
    String s(String k) => (f[k] ?? '').toString().trim();
    final name = s('fullName').isNotEmpty ? s('fullName') : record.name;
    final issued = DateTime.tryParse(s('dateIssued')) ?? record.date;
    final priest = s('parishPriest').isNotEmpty
        ? s('parishPriest')
        : kCertificateSignatories[noRecord ? 1 : 0].name;
    final position = positionFor(priest, s('priestPosition'));
    final legacy = !f.containsKey('sex');
    if (noRecord) {
      return LetterCertificate.noRecord(
        name: name,
        register: NoRecordRegisterText.fromId(s('register')),
        sex: s('sex'),
        father: s('father'),
        mother: s('mother'),
        purpose: s('purpose'),
        dateIssued: issued,
        signatory: priest,
        position: position,
      );
    }
    return LetterCertificate.goodMoral(
      name: name,
      residentOf: s('residentOf'),
      sex: s('sex'),
      father: s('father'),
      mother: s('mother'),
      // The old form's purpose completed "is therefore a fit person for …".
      purpose: legacy && s('purpose').isNotEmpty
          ? 'use for ${s('purpose')}'
          : s('purpose'),
      dateIssued: issued,
      signatory: priest,
      position: position,
    );
  }

  static String _sentence(String text) {
    final t = text.trim();
    if (t.isEmpty) return t;
    return RegExp(r'[.!?]$').hasMatch(t) ? t : '$t.';
  }

  static String _child(String sex) {
    final v = sex.trim().toLowerCase();
    if (v == 'son' || v == 'daughter') return v;
    return 'child';
  }

  factory LetterCertificate.noRecord({
    required String name,
    required NoRecordRegister register,
    required String sex,
    required String father,
    required String mother,
    required String purpose,
    required DateTime dateIssued,
    required String signatory,
    required String position,
  }) {
    final parents = joinParents(father, mother);
    final purposeText = purpose.trim().isEmpty
        ? 'any legal purposes'
        : purpose.trim();
    return LetterCertificate(
      isNoRecord: true,
      title: 'CERTIFICATION',
      salutation: const [LetterSpan('TO WHOM IT MAY CONCERN:', bold: true)],
      paragraphs: [
        [
          LetterSpan(
            'This is to certify that the ${register.adjective} record of ',
          ),
          // The comma rides with the name so justification cannot open a
          // gap between them (the samples underline it too).
          LetterSpan(
            '${name.trim().toUpperCase()},',
            bold: true,
            underline: true,
          ),
          LetterSpan(
            parents.isEmpty
                ? ' who was supposed to have been ${register.verb} in this '
                      'parish, could not be found in the Records of '
                      '${register.book}.'
                : ' ${_child(sex)} of $parents, and was supposed to have '
                      'been ${register.verb} in this parish, could not be '
                      'found in the Records of ${register.book}.',
          ),
        ],
        [
          LetterSpan(
            'This certification is issued upon the request of the '
            'above-mentioned name for ${_sentence(purposeText)}',
          ),
        ],
        [
          const LetterSpan('Given and sealed this '),
          ...ordinalDay(dateIssued.day),
          LetterSpan(
            ' day of ${DateFormat('MMMM, yyyy').format(dateIssued)}',
            bold: true,
          ),
          const LetterSpan(
            ' at the Holy Rosary Parish Office, Oroquieta City.',
          ),
        ],
      ],
      closing: 'Sincerely in Christ,',
      signatory: signatory.trim().toUpperCase(),
      position: position.trim(),
    );
  }

  factory LetterCertificate.goodMoral({
    required String name,
    required String residentOf,
    required String sex,
    required String father,
    required String mother,
    required String purpose,
    required DateTime dateIssued,
    required String signatory,
    required String position,
  }) {
    final parents = joinParents(father, mother);
    final resident = residentOf.trim();
    return LetterCertificate(
      isNoRecord: false,
      title: 'CERTIFICATE OF GOOD MORAL CHARACTER',
      salutation: const [LetterSpan('To whom it may Concern,')],
      paragraphs: [
        [
          const LetterSpan('This is to certify that '),
          LetterSpan(
            '${name.trim().toUpperCase()},',
            bold: true,
            underline: true,
          ),
          LetterSpan(
            '${resident.isEmpty ? '' : ' a resident of $resident,'} under '
            'the jurisdiction of Holy Rosary Parish'
            '${parents.isEmpty ? '' : ', and the ${_child(sex)} of $parents'}'
            ', is known to be of Good Moral Character and being a '
            'law-abiding citizen.',
          ),
        ],
        [
          LetterSpan(
            'This certificate is issued upon the request of the interested '
            'party${purpose.trim().isEmpty ? '.' : ' to ${_sentence(purpose)}'}',
          ),
        ],
        [
          const LetterSpan('Given and sealed this '),
          ...ordinalDay(dateIssued.day),
          const LetterSpan(' day of '),
          LetterSpan(DateFormat('MMMM yyyy').format(dateIssued), bold: true),
          const LetterSpan(
            ', at the office of the Holy Rosary Parish, Oroquieta City.',
          ),
        ],
      ],
      closing: null,
      signatory: signatory.trim().toUpperCase(),
      position: position.trim(),
    );
  }

  // -------------------------------------------------------------------------
  // Page geometry, in PDF points on A4 (595 x 842), shared by both renderers.
  // -------------------------------------------------------------------------

  static const pageWidth = 595.28;
  static const pageHeight = 841.89;
  static const marginLeft = 72.0;
  static const marginRight = 72.0;
  static const marginTop = 58.0;
  static const sealHeight = 82.0;
  static const bodySize = 14.0;
  static const indent = 44.0;
  static const headSize = 18.5;

  double get lineHeight => isNoRecord ? 2.0 : 1.55;
  double get paragraphGap => isNoRecord ? 12 : 12;
  double get titleSize => isNoRecord ? 21 : 17.5;
  double get titleSpacing => isNoRecord ? 5 : 0.4;
  double get gapBeforeSignature => isNoRecord ? 40 : 110;

  static const sealLeft = 'assets/images/certificates/seal_archdiocese.png';
  static const sealRight = 'assets/images/certificates/seal_parish.png';
  static const bodyFont = 'Carlito';
  static const headFont = 'CrimsonText';

  // -------------------------------------------------------------------------
  // PDF
  // -------------------------------------------------------------------------

  Future<pw.Document> buildPdf() async {
    Future<pw.Font> font(String path) async =>
        pw.Font.ttf(await rootBundle.load(path));
    Future<pw.MemoryImage> image(String path) async =>
        pw.MemoryImage((await rootBundle.load(path)).buffer.asUint8List());
    final regular = await font('assets/fonts/Carlito-Regular.ttf');
    final bold = await font('assets/fonts/Carlito-Bold.ttf');
    final headBold = await font('assets/fonts/CrimsonText-Bold.ttf');
    final headItalic = await font('assets/fonts/CrimsonText-Italic.ttf');
    final left = await image(sealLeft);
    final right = await image(sealRight);

    pw.TextStyle body({bool b = false}) => pw.TextStyle(
      font: b ? bold : regular,
      fontSize: bodySize,
      color: PdfColors.black,
    );

    pw.InlineSpan span(LetterSpan s) {
      final style = body(b: s.bold).copyWith(
        decoration: s.underline ? pw.TextDecoration.underline : null,
        fontSize: s.superscript ? bodySize * 0.62 : bodySize,
      );
      return pw.TextSpan(
        text: s.text,
        style: style,
        baseline: s.superscript ? bodySize * 0.38 : 0,
      );
    }

    pw.Widget paragraph(List<LetterSpan> spans, {bool indented = true}) =>
        pw.RichText(
          textAlign: pw.TextAlign.justify,
          text: pw.TextSpan(
            style: body().copyWith(lineSpacing: bodySize * (lineHeight - 1)),
            children: [
              if (indented)
                pw.WidgetSpan(child: pw.SizedBox(width: indent, height: 1)),
              for (final s in spans) span(s),
            ],
          ),
        );

    final doc = pw.Document(title: title, author: 'Holy Rosary Parish');
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(
          marginLeft,
          marginTop,
          marginRight,
          40,
        ),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.SizedBox(height: sealHeight, child: pw.Image(left)),
                pw.SizedBox(width: 22),
                pw.Column(
                  children: [
                    pw.Text(
                      'ARCHDIOCESE OF OZAMIS',
                      style: pw.TextStyle(font: headBold, fontSize: headSize),
                    ),
                    pw.Text(
                      'HOLY ROSARY PARISH',
                      style: pw.TextStyle(font: headBold, fontSize: headSize),
                    ),
                    pw.Text(
                      '7207 Oroquieta City',
                      style: pw.TextStyle(font: headItalic, fontSize: 14),
                    ),
                  ],
                ),
                pw.SizedBox(width: 22),
                pw.SizedBox(height: sealHeight, child: pw.Image(right)),
              ],
            ),
            pw.SizedBox(height: 44),
            pw.Center(
              child: pw.Text(
                title,
                style: pw.TextStyle(
                  font: headBold,
                  fontSize: titleSize,
                  letterSpacing: titleSpacing,
                ),
              ),
            ),
            pw.SizedBox(height: 36),
            paragraph(salutation, indented: false),
            pw.SizedBox(height: paragraphGap),
            for (final p in paragraphs) ...[
              paragraph(p),
              pw.SizedBox(height: paragraphGap),
            ],
            pw.SizedBox(height: gapBeforeSignature),
            if (closing != null) ...[
              pw.Text(closing!, style: body()),
              pw.SizedBox(height: 40),
            ],
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(signatory, style: body(b: true)),
                pw.SizedBox(height: 3),
                pw.Text(position, style: body()),
              ],
            ),
            pw.SizedBox(height: 90),
            pw.Text('PARISH SEAL', style: body().copyWith(fontSize: 13)),
          ],
        ),
      ),
    );
    return doc;
  }
}

/// The certificate drawn on screen as an A4 page (scaled to fit its box).
class LetterCertificatePage extends StatelessWidget {
  final LetterCertificate certificate;
  const LetterCertificatePage({super.key, required this.certificate});

  @override
  Widget build(BuildContext context) {
    final c = certificate;
    const size = LetterCertificate.bodySize;
    TextStyle body({bool bold = false}) => TextStyle(
      fontFamily: LetterCertificate.bodyFont,
      fontSize: size,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color: Colors.black,
      height: c.lineHeight,
    );

    InlineSpan span(LetterSpan s) {
      if (s.superscript) {
        return WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Transform.translate(
            offset: const Offset(0, -size * 0.38),
            child: Text(
              s.text,
              style: body(
                bold: s.bold,
              ).copyWith(fontSize: size * 0.62, height: 1),
            ),
          ),
        );
      }
      return TextSpan(
        text: s.text,
        style: body(
          bold: s.bold,
        ).copyWith(decoration: s.underline ? TextDecoration.underline : null),
      );
    }

    Widget paragraph(List<LetterSpan> spans, {bool indented = true}) =>
        Text.rich(
          TextSpan(
            style: body(),
            children: [
              if (indented)
                const WidgetSpan(
                  child: SizedBox(width: LetterCertificate.indent, height: 1),
                ),
              for (final s in spans) span(s),
            ],
          ),
          textAlign: TextAlign.justify,
          textScaler: TextScaler.noScaling,
          // Line spacing only between lines, as in the PDF.
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: false,
            applyHeightToLastDescent: false,
          ),
        );

    const head = TextStyle(
      fontFamily: LetterCertificate.headFont,
      fontWeight: FontWeight.w700,
      fontSize: LetterCertificate.headSize,
      color: Colors.black,
      height: 1.15,
    );

    return ColoredBox(
      color: Colors.white,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: LetterCertificate.pageWidth,
          height: LetterCertificate.pageHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              LetterCertificate.marginLeft,
              LetterCertificate.marginTop,
              LetterCertificate.marginRight,
              40,
            ),
            child: DefaultTextStyle(
              style: body(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        LetterCertificate.sealLeft,
                        height: LetterCertificate.sealHeight,
                      ),
                      const SizedBox(width: 22),
                      const Column(
                        children: [
                          Text('ARCHDIOCESE OF OZAMIS', style: head),
                          Text('HOLY ROSARY PARISH', style: head),
                          Text(
                            '7207 Oroquieta City',
                            style: TextStyle(
                              fontFamily: LetterCertificate.headFont,
                              fontStyle: FontStyle.italic,
                              fontSize: 14,
                              color: Colors.black,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 22),
                      Image.asset(
                        LetterCertificate.sealRight,
                        height: LetterCertificate.sealHeight,
                      ),
                    ],
                  ),
                  const SizedBox(height: 44),
                  Center(
                    child: Text(
                      c.title,
                      style: head.copyWith(
                        fontSize: c.titleSize,
                        letterSpacing: c.titleSpacing,
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),
                  paragraph(c.salutation, indented: false),
                  SizedBox(height: c.paragraphGap),
                  for (final p in c.paragraphs) ...[
                    paragraph(p),
                    SizedBox(height: c.paragraphGap),
                  ],
                  SizedBox(height: c.gapBeforeSignature),
                  if (c.closing != null) ...[
                    Text(c.closing!, style: body().copyWith(height: 1.2)),
                    const SizedBox(height: 40),
                  ],
                  Column(
                    children: [
                      Text(
                        c.signatory,
                        style: body(bold: true).copyWith(height: 1.2),
                      ),
                      const SizedBox(height: 3),
                      Text(c.position, style: body().copyWith(height: 1.2)),
                    ],
                  ),
                  const SizedBox(height: 90),
                  Text(
                    'PARISH SEAL',
                    style: body().copyWith(fontSize: 13, height: 1.2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
