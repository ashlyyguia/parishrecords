import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Prepares register photos for OCR (resize + contrast for faded registers).
class RegisterOcrImagePreprocess {
  static const int maxDimension = 2400;

  /// Returns enhanced JPEG bytes for OCR.
  static Future<Uint8List> enhanceBytes(Uint8List inputBytes) async {
    return enhanceWithOptions(inputBytes);
  }

  /// Adjustable preprocessing before OCR (staff preprocess screen).
  static Future<Uint8List> enhanceWithOptions(
    Uint8List inputBytes, {
    double contrast = 1.35,
    double brightness = 0.08,
    bool highContrast = false,
    bool sharpen = false,
  }) async {
    final work = () => _encodeVariant(
          inputBytes,
          contrast: highContrast ? 1.55 : contrast,
          brightness: highContrast ? 0.04 : brightness,
          sharpen: sharpen || highContrast,
        );
    if (kIsWeb) return work();
    return compute(
      _encodeVariantArgs,
      _EncodeArgs(
        inputBytes,
        contrast: highContrast ? 1.55 : contrast,
        brightness: highContrast ? 0.04 : brightness,
        sharpen: sharpen || highContrast,
      ),
    );
  }

  /// Rotate image 90° clockwise [quarterTurns] times (1 = 90°, 2 = 180°, …).
  static Future<Uint8List> rotateBytes(
    Uint8List inputBytes, {
    int quarterTurns = 1,
  }) async {
    final turns = quarterTurns % 4;
    if (turns == 0) return inputBytes;
    final work = () => _rotate(inputBytes, turns);
    if (kIsWeb) return work();
    return compute(_rotateArgs, _RotateArgs(inputBytes, turns));
  }

  /// Preprocessed image(s) for web Tesseract (standard + high-contrast fallback).
  static Future<List<Uint8List>> webOcrVariants(Uint8List inputBytes) async {
    if (kIsWeb) {
      return [
        _enhanceStandard(inputBytes),
        _enhanceHighContrast(inputBytes),
      ];
    }
    return [await enhanceBytes(inputBytes)];
  }

  /// Resized path for OCR; on web returns a blob URL from enhanced bytes.
  static Future<String> enhanceForOcr(String inputPath) async {
    final bytes = await XFile(inputPath).readAsBytes();
    final enhanced = await enhanceBytes(bytes);
    return pathForEnhancedBytes(enhanced);
  }

  static Future<String> pathForEnhancedBytes(Uint8List bytes) async {
    if (kIsWeb) {
      return XFile.fromData(
        bytes,
        name: 'ocr_enhanced.jpg',
        mimeType: 'image/jpeg',
      ).path;
    }
    final dir = await getTemporaryDirectory();
    final out = File(
      '${dir.path}/ocr_ready_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await out.writeAsBytes(bytes);
    return out.path;
  }
}

class _EncodeArgs {
  _EncodeArgs(
    this.bytes, {
    required this.contrast,
    required this.brightness,
    required this.sharpen,
  });
  final Uint8List bytes;
  final double contrast;
  final double brightness;
  final bool sharpen;
}

Uint8List _encodeVariantArgs(_EncodeArgs args) => _encodeVariant(
      args.bytes,
      contrast: args.contrast,
      brightness: args.brightness,
      sharpen: args.sharpen,
    );

class _RotateArgs {
  _RotateArgs(this.bytes, this.turns);
  final Uint8List bytes;
  final int turns;
}

Uint8List _rotateArgs(_RotateArgs args) => _rotate(args.bytes, args.turns);

Uint8List _rotate(Uint8List inputBytes, int quarterTurns) {
  try {
    final decoded = img.decodeImage(inputBytes);
    if (decoded == null) return inputBytes;
    final rotated = img.copyRotate(decoded, angle: quarterTurns * 90);
    return Uint8List.fromList(img.encodeJpg(rotated, quality: 92));
  } catch (_) {
    return inputBytes;
  }
}

Uint8List _enhanceStandard(Uint8List inputBytes) {
  return _encodeVariant(inputBytes);
}

Uint8List _enhanceHighContrast(Uint8List inputBytes) {
  return _encodeVariant(
    inputBytes,
    contrast: 1.55,
    brightness: 0.04,
    sharpen: false,
  );
}

Uint8List _encodeVariant(
  Uint8List inputBytes, {
  double contrast = 1.35,
  double brightness = 0.08,
  bool sharpen = false,
}) {
  try {
    final decoded = img.decodeImage(inputBytes);
    if (decoded == null) return inputBytes;

    var image = _resize(decoded);
    image = img.grayscale(image);

    if (sharpen) {
      image = img.convolution(
        image,
        filter: [0, -1, 0, -1, 5, -1, 0, -1, 0],
      );
    }

    image = img.adjustColor(
      image,
      contrast: contrast,
      brightness: brightness,
      gamma: contrast > 1.5 ? 1.1 : 1.05,
    );

    return Uint8List.fromList(img.encodeJpg(image, quality: 92));
  } catch (_) {
    return inputBytes;
  }
}

img.Image _resize(img.Image image) {
  if (image.width <= RegisterOcrImagePreprocess.maxDimension &&
      image.height <= RegisterOcrImagePreprocess.maxDimension) {
    return image;
  }
  if (image.width >= image.height) {
    return img.copyResize(
      image,
      width: RegisterOcrImagePreprocess.maxDimension,
    );
  }
  return img.copyResize(
    image,
    height: RegisterOcrImagePreprocess.maxDimension,
  );
}
