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

  Future<void> dispose() async {
    await _textRecognizer.close();
  }
}
