import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrService {
  OcrService._();

  static final OcrService instance = OcrService._();

  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  Future<String> recognizeTextFromFile(File file) async {
    final inputImage = InputImage.fromFile(file);
    final RecognizedText recognizedText = await _textRecognizer.processImage(
      inputImage,
    );
    return recognizedText.text;
  }

  /// Extracts text from an image file at the given path.
  /// [historical] - when true, uses latin script (same as default for now).
  Future<String> extractTextFromImage(String path, {bool historical = false}) async {
    final file = File(path);
    return recognizeTextFromFile(file);
  }

  Future<void> dispose() async {
    await _textRecognizer.close();
  }
}
