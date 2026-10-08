import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:parishrecord/services/certificate_signature_service.dart';

/// Writes a sample (made-up) signature through the real cleaning step and
/// places it in a copy of the certificate's signature block, for review.
void main() {
  test('render signature preview', () async {
    final out = Directory('build/signature_preview')..createSync(recursive: true);

    // 1. A "phone photo" of a scribble: warm off-white paper with a light
    //    shadow gradient, blue-black ink.
    final photo = img.Image(width: 900, height: 420);
    for (final p in photo) {
      final shade = 238 - (p.x / 900 * 22).round() - (p.y / 420 * 10).round();
      p..r = shade..g = shade - 4..b = shade - 12;
    }
    final ink = img.ColorRgb8(25, 30, 80);
    var prev = const Point<double>(120, 240);
    for (var t = 0.0; t <= 1.0; t += 0.004) {
      final x = 120 + 620 * t;
      final y = 230 - 70 * sin(t * 14) * (1 - t * 0.6) + 40 * sin(t * 5);
      img.drawLine(photo,
          x1: prev.x.round(), y1: prev.y.round(), x2: x.round(), y2: y.round(),
          color: ink, thickness: 6, antialias: true);
      prev = Point(x, y);
    }
    img.drawLine(photo, x1: 160, y1: 320, x2: 700, y2: 290, color: ink, thickness: 5);
    final jpg = Uint8List.fromList(img.encodeJpg(photo, quality: 88));
    File('${out.path}/1_uploaded_photo.jpg').writeAsBytesSync(jpg);

    // 2. The real cleaning step used by the app.
    final png = CertificateSignatureService.prepare(jpg);
    File('${out.path}/2_cleaned_signature.png').writeAsBytesSync(png);

    // 3. Same layout as signatureBlock() in certificate_template_screen.dart.
    final bold = pw.Font.helveticaBold();
    final italic = pw.Font.helveticaOblique();
    final regular = pw.Font.helvetica();
    pw.Widget block(bool withSig) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Rev.', style: pw.TextStyle(font: italic, fontSize: 8)),
                pw.SizedBox(width: 4),
                pw.Container(
                  width: 110,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 1)),
                  ),
                  padding: const pw.EdgeInsets.only(bottom: 2),
                  child: pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
                    if (withSig)
                      pw.Image(pw.MemoryImage(png), height: 30, fit: pw.BoxFit.contain),
                    pw.Text('FR. DANILO B. RUDINAS',
                        style: pw.TextStyle(font: bold, fontSize: 8),
                        textAlign: pw.TextAlign.center, maxLines: 2),
                  ]),
                ),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Text('Parish Priest / VICAR',
                style: pw.TextStyle(font: bold, fontSize: 7), textAlign: pw.TextAlign.right),
          ],
        );
    pw.Widget registry(String k, String v) => pw.Text('$k  $v',
        style: pw.TextStyle(font: regular, fontSize: 8));

    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: const PdfPageFormat(360, 230, marginAll: 16),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        for (final withSig in [false, true]) ...[
          pw.Text(withSig ? 'WITH E-SIGNATURE' : 'BEFORE (no e-signature)',
              style: pw.TextStyle(font: bold, fontSize: 7, color: PdfColors.grey600)),
          pw.SizedBox(height: 4),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: .5)),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                registry('Dated :', 'October 8, 2026'),
                registry('Page  :', '12'),
                registry('Vol.  :', '18'),
                registry('Series :', '2026'),
              ]),
              pw.Spacer(),
              pw.SizedBox(width: 150, child: block(withSig)),
            ]),
          ),
          pw.SizedBox(height: 12),
        ],
      ]),
    ));
    File('${out.path}/3_signature_block.pdf').writeAsBytesSync(await doc.save());
  });
}
