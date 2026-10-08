import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:parishrecord/services/certificate_signature_service.dart';

void main() {
  Uint8List photo({bool withInk = true}) {
    // Off-white "paper" with a dark diagonal stroke in the middle.
    final im = img.Image(width: 400, height: 200);
    img.fill(im, color: img.ColorRgb8(236, 232, 224));
    if (withInk) {
      img.drawLine(im,
          x1: 100, y1: 120, x2: 300, y2: 80,
          color: img.ColorRgb8(20, 30, 90), thickness: 5);
    }
    return Uint8List.fromList(img.encodeJpg(im, quality: 92));
  }

  test('paper becomes transparent and the ink is cropped', () {
    final out = img.decodePng(CertificateSignatureService.prepare(photo()))!;
    expect(out.numChannels, 4);
    // Cropped close to the stroke (200 x 40 plus padding), not the full page.
    expect(out.width, lessThan(240));
    expect(out.height, lessThan(80));
    // A corner is paper: fully transparent.
    expect(out.getPixel(0, 0).a, 0);
    // The centre is on the stroke: opaque.
    expect(out.getPixel(out.width ~/ 2, out.height ~/ 2).a, greaterThan(200));
  });

  test('a blank page is rejected', () {
    expect(() => CertificateSignatureService.prepare(photo(withInk: false)),
        throwsFormatException);
  });

  test('a non-image is rejected', () {
    expect(() => CertificateSignatureService.prepare(Uint8List.fromList([1, 2, 3])),
        throwsFormatException);
  });
}
