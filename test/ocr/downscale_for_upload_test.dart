import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:parishrecord/services/register_ocr_image_preprocess.dart';

void main() {
  test('caps the long edge at maxDim and returns a decodable JPEG', () async {
    final src = img.Image(width: 3000, height: 1500);
    img.fill(src, color: img.ColorRgb8(200, 200, 200));
    final bytes = Uint8List.fromList(img.encodeJpg(src, quality: 90));

    final out = await RegisterOcrImagePreprocess.downscaleForUpload(bytes, maxDim: 2000);
    final decoded = img.decodeImage(out);
    expect(decoded, isNotNull);
    expect(decoded!.width, lessThanOrEqualTo(2000));
    expect(decoded.height, lessThanOrEqualTo(2000));
    expect(out, isNotEmpty);
  });

  test('leaves already-small images decodable', () async {
    final src = img.Image(width: 800, height: 600);
    img.fill(src, color: img.ColorRgb8(10, 10, 10));
    final bytes = Uint8List.fromList(img.encodeJpg(src));
    final out = await RegisterOcrImagePreprocess.downscaleForUpload(bytes);
    expect(img.decodeImage(out), isNotNull);
  });
}
