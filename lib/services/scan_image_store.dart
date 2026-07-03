import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Stores scanned certificate images on the local device (never uploaded
/// to Firebase Storage). The returned path is kept on the Firestore record
/// so the image can be found again on this device.
class ScanImageStore {
  ScanImageStore._();

  /// Saves [bytes] locally and returns the stored path, or null when the
  /// platform has no writable storage (web downloads the file instead).
  static Future<String?> save(
    Uint8List bytes, {
    required String recordType,
  }) async {
    final fileName =
        'cert_${recordType}_${DateTime.now().millisecondsSinceEpoch}.jpg';

    if (kIsWeb) {
      // Browsers cannot write to disk directly — offer the image as a
      // download so the user still keeps a local copy.
      try {
        await FilePicker.platform.saveFile(fileName: fileName, bytes: bytes);
      } catch (_) {
        // User cancelled or browser blocked the download — non-fatal.
      }
      return null;
    }

    final dir = await getApplicationDocumentsDirectory();
    final scansDir = Directory('${dir.path}${Platform.pathSeparator}parish_scans');
    if (!await scansDir.exists()) {
      await scansDir.create(recursive: true);
    }
    final file = File('${scansDir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }
}
