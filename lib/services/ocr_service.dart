import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

/// OCR recognition mode
enum OcrMode {
  printed,
  handwritten,
  auto,
}

/// OCR recognition result with metadata
class OcrResult {
  final String text;
  final OcrMode mode;
  final double confidence;
  final List<TextBlock> blocks;
  final String? language;

  OcrResult({
    required this.text,
    required this.mode,
    this.confidence = 0.0,
    this.blocks = const [],
    this.language,
  });
}

/// True when Google ML Kit text recognition is available (Android/iOS only).
bool get ocrUsesMlKit =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Camera capture for register OCR (Android/iOS native apps only).
bool get ocrSupportsCamera => ocrUsesMlKit;

/// Short hint for the upload UI on the current platform.
String get ocrUploadHint {
  if (ocrUsesMlKit) {
    return 'Scan multiple pages — left then right side. Rows merge by register No.';
  }
  if (kIsWeb) {
    return 'Upload one or more JPG/PNG pages; add more to merge records. '
        'Review rows after scan.';
  }
  return 'Upload multiple register pages; scans merge by register number (No.).';
}

class OcrService {
  OcrService._();

  static final OcrService instance = OcrService._();

  TextRecognizer? _printedRecognizer;
  TextRecognizer? _eastAsianRecognizer;

  TextRecognizer get _printedTextRecognizer {
    _printedRecognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    return _printedRecognizer!;
  }

  TextRecognizer get _eastAsianTextRecognizer {
    _eastAsianRecognizer ??= TextRecognizer(
      script: TextRecognitionScript.japanese,
    );
    return _eastAsianRecognizer!;
  }

  /// Recognize text from an image path (works on web blob URLs and mobile paths).
  Future<OcrResult> recognizePath(
    String path, {
    OcrMode mode = OcrMode.auto,
    String? languageHint,
  }) async {
    if (ocrUsesMlKit) {
      return recognizeText(File(path), mode: mode, languageHint: languageHint);
    }
    return _recognizeWithTesseract(
      path,
      mode: mode,
      languageHint: languageHint,
    );
  }

  /// Recognize text from JPEG/PNG bytes (used when only bytes are available).
  Future<OcrResult> recognizeBytes(
    Uint8List bytes, {
    OcrMode mode = OcrMode.auto,
    String? languageHint,
  }) async {
    final path = kIsWeb
        ? XFile.fromData(bytes, name: 'ocr.jpg', mimeType: 'image/jpeg').path
        : await _writeTempJpeg(bytes);
    try {
      return await recognizePath(path, mode: mode, languageHint: languageHint);
    } finally {
      if (!kIsWeb && path.contains('ocr_')) {
        try {
          final f = File(path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
  }

  Future<OcrResult> _recognizeWithTesseract(
    String path, {
    required OcrMode mode,
    String? languageHint,
    Map<String, String>? tesseractArgs,
  }) async {
    final lang = languageHint ?? 'eng';
    final argSets = tesseractArgs != null
        ? [tesseractArgs]
        : (kIsWeb ? _webTesseractArgSets : _defaultTesseractArgs);

    OcrResult? best;
    for (final args in argSets) {
      try {
        final text = await FlutterTesseractOcr.extractText(
          path,
          language: lang,
          args: args,
        );
        final trimmed = text.trim();
        final result = OcrResult(
          text: trimmed,
          mode: mode,
          confidence: trimmed.isEmpty ? 0.0 : 0.75,
          blocks: const [],
          language: lang,
        );
        if (best == null || _tesseractScore(trimmed) > _tesseractScore(best.text)) {
          best = result;
        }
        if (kIsWeb && _tesseractScore(trimmed) >= 180) break;
      } catch (e) {
        debugPrint('Tesseract OCR Error ($args): $e');
      }
    }

    return best ??
        OcrResult(
          text: '',
          mode: mode,
          confidence: 0.0,
          language: lang,
        );
  }

  static final _defaultTesseractArgs = [
    {'preserve_interword_spaces': '1'},
  ];

  /// PSM modes tuned for parish register tables (web tries each, keeps best).
  static final _webTesseractArgSets = [
    {
      'preserve_interword_spaces': '1',
      'tessedit_pageseg_mode': '6',
    },
    {
      'preserve_interword_spaces': '1',
      'tessedit_pageseg_mode': '4',
    },
  ];

  /// Heuristic score — favors multi-line register-like OCR on web.
  static int _tesseractScore(String text) {
    final t = text.trim();
    if (t.isEmpty) return 0;
    var score = t.length;
    final lines =
        t.split(RegExp(r'\r?\n')).where((l) => l.trim().length > 2).length;
    score += lines * 30;
    if (RegExp(r'\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]?\d{0,4}').hasMatch(t)) {
      score += 40;
    }
    if (RegExp(
      r'baptism|marriage|minister|sponsor|child|parents|born|residents',
      caseSensitive: false,
    ).hasMatch(t)) {
      score += 50;
    }
    if (t.contains('\t') || RegExp(r' {2,}').hasMatch(t)) score += 25;
    return score;
  }

  Future<String> _writeTempJpeg(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/ocr_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes);
    return file.path;
  }

  Future<OcrResult> recognizeText(
    File file, {
    OcrMode mode = OcrMode.auto,
    String? languageHint,
  }) async {
    if (!ocrUsesMlKit) {
      return recognizePath(file.path, mode: mode, languageHint: languageHint);
    }

    final inputImage = InputImage.fromFile(file);
    final recognizer = _selectRecognizer(languageHint);

    try {
      final RecognizedText recognizedText = await recognizer.processImage(
        inputImage,
      );

      double totalConfidence = 0;
      int blockCount = 0;

      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          for (final element in line.elements) {
            if (element.confidence != null && element.confidence! > 0) {
              totalConfidence += element.confidence!;
              blockCount++;
            }
          }
        }
      }

      final avgConfidence = blockCount > 0 ? totalConfidence / blockCount : 0.0;

      return OcrResult(
        text: recognizedText.text,
        mode: mode,
        confidence: avgConfidence,
        blocks: recognizedText.blocks,
        language: languageHint ?? 'latin',
      );
    } catch (e) {
      debugPrint('OCR Error: $e');
      return OcrResult(
        text: '',
        mode: mode,
        confidence: 0.0,
        language: languageHint,
      );
    }
  }

  Future<String> recognizeTextFromFile(File file) async {
    final result = await recognizeText(file, mode: OcrMode.auto);
    return result.text;
  }

  Future<OcrResult> recognizePrintedText(File file, {String? language}) async {
    return recognizeText(file, mode: OcrMode.printed, languageHint: language);
  }

  Future<OcrResult> recognizeHandwrittenText(
    File file, {
    String? language,
  }) async {
    return recognizeText(
      file,
      mode: OcrMode.handwritten,
      languageHint: language,
    );
  }

  Future<String> extractTextFromImage(
    String path, {
    bool historical = false,
    OcrMode mode = OcrMode.auto,
  }) async {
    final result = await recognizePath(path, mode: mode);
    return result.text;
  }

  Future<OcrResult> recognizeTextFromBytes(
    Uint8List bytes, {
    OcrMode mode = OcrMode.auto,
    String? languageHint,
  }) async {
    return recognizeBytes(bytes, mode: mode, languageHint: languageHint);
  }

  List<Map<String, dynamic>> extractStructuredData(OcrResult result) {
    final structured = <Map<String, dynamic>>[];

    for (int i = 0; i < result.blocks.length; i++) {
      final block = result.blocks[i];
      structured.add({
        'index': i,
        'text': block.text,
        'lines': block.lines.map((line) => line.text).toList(),
        'boundingBox': {
          'left': block.boundingBox.left,
          'top': block.boundingBox.top,
          'width': block.boundingBox.width,
          'height': block.boundingBox.height,
        },
      });
    }

    return structured;
  }

  TextRecognizer _selectRecognizer(String? languageHint) {
    if (languageHint == null) {
      return _printedTextRecognizer;
    }

    final lang = languageHint.toLowerCase();

    if (['zh', 'ja', 'ko', 'cmn', 'jpn', 'kor'].contains(lang)) {
      return _eastAsianTextRecognizer;
    }

    return _printedTextRecognizer;
  }

  Future<void> dispose() async {
    await _printedRecognizer?.close();
    await _eastAsianRecognizer?.close();

    _printedRecognizer = null;
    _eastAsianRecognizer = null;
  }
}
