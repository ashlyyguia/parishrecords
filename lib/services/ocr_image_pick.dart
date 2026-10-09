import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'ocr_service.dart';

/// Picks register photos for OCR — camera on phones, file upload on web/desktop.
class OcrImagePick {
  OcrImagePick._();

  static final _picker = ImagePicker();

  /// Long-edge cap for "full resolution" register photos on phones.
  ///
  /// Uploading the camera original is not safe on Android/iOS: 50–108 MP
  /// sensors produce 10–25 MB JPEGs, over the backend's 10 MB limit (and slow
  /// on mobile data). 4096 px keeps every detail the grid + OCR pipeline uses
  /// -- all 67 sample register photos are ~4032 px and scan correctly -- while
  /// the native picker does the resize (fast, memory-safe, keeps EXIF
  /// orientation, and turns HEIF gallery photos into JPEG).
  static const double registerMaxEdge = 4096;

  static bool get _useFilePicker =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;

  /// Gallery / filesystem (always available where OCR runs).
  ///
  /// [fullResolution] keeps register photos large (up to [registerMaxEdge] on
  /// the long side) for dense handwriting, instead of the normal 2000 px.
  static Future<List<XFile>> pickImages({
    bool allowMultiple = true,
    bool fullResolution = false,
  }) async {
    if (_useFilePicker) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'],
        allowMultiple: allowMultiple,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return [];
      final out = <XFile>[];
      for (final f in result.files) {
        final bytes = f.bytes;
        if (bytes == null) continue;
        out.add(
          XFile.fromData(
            bytes,
            name: f.name,
            mimeType: mimeForExtension(f.extension),
          ),
        );
      }
      return out;
    }

    final maxDim = fullResolution ? registerMaxEdge : 2000.0;
    const quality = 92;

    if (allowMultiple) {
      final picked = await _picker.pickMultiImage(
        maxWidth: maxDim,
        maxHeight: maxDim,
        imageQuality: quality,
      );
      return picked;
    }

    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: maxDim,
      maxHeight: maxDim,
      imageQuality: quality,
    );
    return picked == null ? [] : [picked];
  }

  /// Take photo or pick image(s) — used for multi-page register scans.
  static Future<List<XFile>> pickRegisterPages(
    BuildContext context, {
    bool allowMultiple = true,
    bool includeCamera = true,
    bool fullResolution = false,
  }) async {
    final canCamera = includeCamera && ocrSupportsCamera;

    if (!canCamera) {
      return pickImages(
        allowMultiple: allowMultiple,
        fullResolution: fullResolution,
      );
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take photo'),
              subtitle: const Text('One page — scan again to add more'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(allowMultiple ? 'Choose images' : 'Choose image'),
              subtitle: Text(
                allowMultiple
                    ? 'Select multiple register pages at once'
                    : 'Select one register photo',
              ),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
          ],
        ),
      ),
    );

    if (choice == null) return [];

    if (choice == 'camera') {
      final shot = await pickCameraPhoto(fullResolution: fullResolution);
      return shot == null ? [] : [shot];
    }

    return pickImages(
      allowMultiple: allowMultiple,
      fullResolution: fullResolution,
    );
  }

  /// Device camera (Android/iOS native only).
  static Future<XFile?> pickCameraPhoto({bool fullResolution = false}) async {
    if (!ocrSupportsCamera) return null;
    return _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: fullResolution ? registerMaxEdge : 2000.0,
      maxHeight: fullResolution ? registerMaxEdge : 2000.0,
      imageQuality: 92,
    );
  }

  @visibleForTesting
  static String mimeForExtension(String? ext) {
    switch (ext?.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }
}
