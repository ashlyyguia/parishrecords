/// OCR (Optical Character Recognition) Screens and Utilities
///
/// This library provides comprehensive text recognition capabilities
/// for both printed and handwritten text using Google ML Kit.
///
/// ## Features
/// - Printed text recognition (documents, certificates, forms)
/// - Handwritten text recognition (cursive, block letters)
/// - Auto-detection mode for mixed content
/// - Multi-language support (English, Spanish, French, Chinese, Japanese, etc.)
/// - Confidence scoring for recognition results
/// - Structured text block extraction
///
/// ## Usage
///
/// ### Basic OCR Scanning
/// ```dart
/// import 'package:parishrecord/screens/ocr/ocr.dart';
///
/// // Navigate to the enhanced scanner
/// final result = await Navigator.push(
///   context,
///   MaterialPageRoute(builder: (_) => const EnhancedOcrScannerScreen()),
/// );
///
/// if (result != null) {
///   print('Recognized text: $result');
/// }
/// ```
///
/// ### Service-only Usage
/// ```dart
/// import 'package:parishrecord/services/ocr_service.dart';
///
/// // Recognize printed text
/// final result = await OcrService.instance.recognizePrintedText(imageFile);
///
/// // Recognize handwritten text
/// final result = await OcrService.instance.recognizeHandwrittenText(imageFile);
///
/// // Auto-detect with language hint
/// final result = await OcrService.instance.recognizeText(
///   imageFile,
///   mode: OcrMode.auto,
///   languageHint: 'en',
/// );
///
/// print('Text: ${result.text}');
/// print('Confidence: ${result.confidence}');
/// ```
///
/// ### Legacy Simple Scanner
/// For basic OCR without mode selection, use:
/// ```dart
/// final result = await Navigator.push(
///   context,
///   MaterialPageRoute(builder: (_) => const OcrScanScreen()),
/// );
/// ```

export 'enhanced_ocr_scanner_screen.dart';
export 'ocr_scan_screen.dart';
export 'ocr_editable_result_screen.dart';
export 'enhanced_ocr_capture_screen.dart';
