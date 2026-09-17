import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/backend.dart';
import '../models/register_marriage_entry.dart';
import 'baptismal_ocr_service.dart' show OcrRecovery;

// Reuse the baptismal failure taxonomy verbatim -- the marriage route emits
// the same error codes -- but keep a distinct exception type so callers can
// catch marriage failures specifically.
export 'baptismal_ocr_service.dart' show OcrRecovery;

/// A marriage scan failure the UI can act on: show [message], and use
/// [recovery] to decide what action to offer.
class MarriageOcrFailure implements Exception {
  const MarriageOcrFailure({
    required this.code,
    required this.message,
    required this.recovery,
    this.detail,
  });

  final String code;
  final String message;
  final OcrRecovery recovery;

  /// Optional capture-guidance text for a refused spread.
  final String? detail;

  bool get retryable => recovery == OcrRecovery.retry;

  @override
  String toString() => 'MarriageOcrFailure($code): $message';
}

/// One completed marriage-register scan: the parsed entries plus scan metadata.
class MarriageOcrScan {
  MarriageOcrScan({
    required this.scanId,
    required this.rotation,
    required this.warnings,
    required this.entries,
  });

  final String scanId;
  final int rotation;
  final List<String> warnings;
  final List<RegisterMarriageEntry> entries;
}

/// Sends marriage-register photos to the backend OCR proxy (`/ocr/marriage`).
///
/// Mirrors [BaptismalOcrService]: the OCR key lives on the server, and this
/// client only ever sees the extracted rows.
class MarriageOcrService {
  MarriageOcrService({
    http.Client? client,
    Duration timeout = const Duration(seconds: 60),
  })  : _client = client ?? http.Client(),
        _timeout = timeout;

  final http.Client _client;
  final Duration _timeout;

  static const Map<String, OcrRecovery> _recoveryByCode = {
    'OCR_QUOTA': OcrRecovery.retry,
    'OCR_UNAVAILABLE': OcrRecovery.retry,
    'INTERNAL_ERROR': OcrRecovery.retry,
    'NETWORK': OcrRecovery.retry,
    'BAD_RESPONSE': OcrRecovery.retry,
    'NO_TEXT_FOUND': OcrRecovery.differentImage,
    'IMAGE_INVALID': OcrRecovery.differentImage,
    'IMAGE_TOO_LARGE': OcrRecovery.differentImage,
    'LAYOUT_UNRECOGNIZED': OcrRecovery.differentImage,
    'SPREAD_UNREADABLE': OcrRecovery.differentImage,
    'UNAUTHENTICATED': OcrRecovery.signIn,
    'OCR_AUTH': OcrRecovery.contactAdmin,
    'FORBIDDEN': OcrRecovery.contactAdmin,
  };

  static const Map<String, String> _fallbackMessages = {
    'NETWORK': 'Could not reach the server. Check your connection and retry.',
    'UNAUTHENTICATED': 'You are signed out. Sign in again to scan.',
    'BAD_RESPONSE': 'The server returned an unexpected response. Please retry.',
    'FORBIDDEN':
        'Your account does not have permission to scan marriage records. '
        'Contact an administrator.',
  };

  static String _codeForStatus(int statusCode) {
    switch (statusCode) {
      case 401:
        return 'UNAUTHENTICATED';
      case 403:
        return 'FORBIDDEN';
      default:
        return 'BAD_RESPONSE';
    }
  }

  Future<MarriageOcrScan> scan({
    required String scanId,
    required Uint8List bytes,
    String? idToken,
  }) async {
    final token = idToken ?? await _currentUserToken();
    if (token == null || token.isEmpty) {
      throw _failure('UNAUTHENTICATED', null);
    }

    http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse('${BackendConfig.apiBaseUrl}/ocr/marriage/scan'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'scanId': scanId,
              'imageBase64': base64Encode(bytes),
            }),
          )
          .timeout(_timeout);
    } catch (_) {
      throw _failure('NETWORK', null);
    }

    Map<String, dynamic>? decoded;
    try {
      final raw = jsonDecode(res.body);
      if (raw is Map<String, dynamic>) decoded = raw;
    } catch (_) {
      decoded = null;
    }

    if (decoded == null) throw _failure('BAD_RESPONSE', null);

    if (res.statusCode != 200 || decoded['success'] != true) {
      throw _failure(
        decoded['code']?.toString() ?? _codeForStatus(res.statusCode),
        decoded['message']?.toString() ?? decoded['error']?.toString(),
        decoded['detail']?.toString(),
      );
    }

    final data = decoded['data'];
    if (data is! Map) throw _failure('BAD_RESPONSE', null);
    final map = Map<String, dynamic>.from(data);

    final rows = (map['rows'] as List? ?? const [])
        .whereType<Map>()
        .map((r) => RegisterMarriageEntry.fromScanJson(Map<String, dynamic>.from(r)))
        .toList();
    final rawRotation = map['rotation'];
    return MarriageOcrScan(
      scanId: map['scanId']?.toString() ?? scanId,
      rotation: rawRotation is num ? rawRotation.toInt() : 0,
      warnings: (map['warnings'] as List? ?? const [])
          .map((w) => w.toString())
          .toList(),
      entries: rows,
    );
  }

  Future<String?> _currentUserToken() async {
    try {
      return await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {
      return null;
    }
  }

  MarriageOcrFailure _failure(String code, String? serverMessage, [String? detail]) {
    return MarriageOcrFailure(
      code: code,
      message: serverMessage ?? _fallbackMessages[code] ?? 'OCR failed. Please retry.',
      recovery: _recoveryByCode[code] ?? OcrRecovery.retry,
      detail: detail,
    );
  }
}
