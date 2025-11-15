import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class OcrService {
  Future<String> extractTextFromImage(
    String path, {
    bool historical = false,
  }) async {
    if (kIsWeb) {
      // OCR is not supported on web for this app.
      throw UnsupportedError('OCR is only available on mobile');
    }
    String usePath = path;
    // Only downscale if the file is large to reduce memory/CPU
    try {
      final file = File(path);
      final sizeBytes = await file.length();
      if (sizeBytes > 3 * 1024 * 1024) {
        final raw = await file.readAsBytes();
        final decoded = img.decodeImage(raw);
        if (decoded != null) {
          final maxSide = 1280;
          final w = decoded.width, h = decoded.height;
          if (w > maxSide || h > maxSide) {
            final resized = img.copyResize(
              decoded,
              width: w >= h ? maxSide : (w * maxSide / h).round(),
              height: h > w ? maxSide : (h * maxSide / w).round(),
              interpolation: img.Interpolation.linear,
            );
            final tmpDir = await getTemporaryDirectory();
            final out = File(
              '${tmpDir.path}/ocr_scaled_${DateTime.now().millisecondsSinceEpoch}.jpg',
            );
            await out.writeAsBytes(img.encodeJpg(resized, quality: 80));
            usePath = out.path;
          }
        }
      }
    } catch (_) {
      // Best-effort downscale; ignore failures and fall back to original path
    }
    if (historical) {
      try {
        final bytes = await File(path).readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          var proc = img.grayscale(decoded);
          proc = img.contrast(proc, contrast: 1.2);
          proc = img.adjustColor(proc, brightness: 0.02);
          // Keep preprocessing simple and broadly compatible
          final tmpDir = await getTemporaryDirectory();
          final out = File(
            '${tmpDir.path}/ocr_proc_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );
          await out.writeAsBytes(img.encodeJpg(proc, quality: 95));
          usePath = out.path;
        }
      } catch (_) {}
    }
    TextRecognizer? recognizer;
    try {
      final inputImage = InputImage.fromFilePath(usePath);
      recognizer = TextRecognizer();
      final result = await recognizer.processImage(inputImage);
      return result.text;
    } catch (e) {
      // Surface a friendly error message up the stack
      throw Exception(
        'Failed to run OCR. Please try another photo or recapture.',
      );
    } finally {
      await recognizer?.close();
    }
  }
}
