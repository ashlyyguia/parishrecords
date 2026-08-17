import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/backend.dart';
import 'register_ocr_scan_helper.dart';

/// Normalized cloud OCR result: full text + positioned word cells.
class CloudOcrResult {
  CloudOcrResult({required this.text, required this.cells});

  final String text;
  final List<OcrLineBox> cells;

  static CloudOcrResult? fromResponseJson(Map<String, dynamic> json) {
    if (json['success'] != true) return null;
    final data = json['data'];
    if (data is! Map) return null;
    final cells = <OcrLineBox>[];
    final rawCells = data['cells'];
    if (rawCells is List) {
      for (final c in rawCells) {
        if (c is Map) {
          cells.add(OcrLineBox.fromJson(Map<String, dynamic>.from(c)));
        }
      }
    }
    return CloudOcrResult(text: data['text']?.toString() ?? '', cells: cells);
  }
}

/// Sends register photos to the backend OCR proxy (OCR.space).
class CloudOcrService {
  CloudOcrService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const Duration _timeout = Duration(seconds: 30);

  /// Returns cloud OCR cells+text, or null on any failure (caller falls back).
  Future<CloudOcrResult?> scanRegister(
    Uint8List jpeg, {
    required String recordType,
  }) async {
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (idToken == null) return null;
      final res = await _client
          .post(
            Uri.parse('${BackendConfig.apiBaseUrl}/ocr/scan'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({
              'imageBase64': base64Encode(jpeg),
              'recordType': recordType,
            }),
          )
          .timeout(_timeout);
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return null;
      return CloudOcrResult.fromResponseJson(decoded);
    } catch (_) {
      return null;
    }
  }
}
