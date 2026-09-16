import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/services/ocr_image_pick.dart';

void main() {
  group('OcrImagePick.mimeForExtension', () {
    test('maps heic and heif to image/heic', () {
      expect(OcrImagePick.mimeForExtension('heic'), 'image/heic');
      expect(OcrImagePick.mimeForExtension('HEIC'), 'image/heic');
      expect(OcrImagePick.mimeForExtension('heif'), 'image/heic');
    });

    test('keeps the existing image types', () {
      expect(OcrImagePick.mimeForExtension('png'), 'image/png');
      expect(OcrImagePick.mimeForExtension('webp'), 'image/webp');
      expect(OcrImagePick.mimeForExtension('jpg'), 'image/jpeg');
      expect(OcrImagePick.mimeForExtension('jpeg'), 'image/jpeg');
      expect(OcrImagePick.mimeForExtension(null), 'image/jpeg');
    });
  });
}
