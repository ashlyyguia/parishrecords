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

  static bool get _useFilePicker =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;

  /// Gallery / filesystem (always available where OCR runs).
  static Future<List<XFile>> pickImages({bool allowMultiple = true}) async {
    if (_useFilePicker) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
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
            mimeType: _mimeForExtension(f.extension),
          ),
        );
      }
      return out;
    }

    if (allowMultiple) {
      final picked = await _picker.pickMultiImage(
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 92,
      );
      return picked;
    }

    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 92,
    );
    return picked == null ? [] : [picked];
  }

  /// Take photo or pick image(s) — used for multi-page register scans.
  static Future<List<XFile>> pickRegisterPages(
    BuildContext context, {
    bool allowMultiple = true,
    bool includeCamera = true,
  }) async {
    final canCamera = includeCamera && ocrSupportsCamera;

    if (!canCamera) {
      return pickImages(allowMultiple: allowMultiple);
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
      final shot = await pickCameraPhoto();
      return shot == null ? [] : [shot];
    }

    return pickImages(allowMultiple: allowMultiple);
  }

  /// Device camera (Android/iOS native only).
  static Future<XFile?> pickCameraPhoto() async {
    if (!ocrSupportsCamera) return null;
    return _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 92,
    );
  }

  static String? _mimeForExtension(String? ext) {
    switch (ext?.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }
}
