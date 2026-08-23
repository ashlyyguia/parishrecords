import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/backend.dart';
import '../models/baptismal_register_row.dart';

/// A scan failure the UI can act on: show [message], offer retry when
/// [retryable].
class BaptismalOcrFailure implements Exception {
  const BaptismalOcrFailure({
    required this.code,
    required this.message,
    required this.retryable,
  });

  final String code;
  final String message;
  final bool retryable;

  @override
  String toString() => 'BaptismalOcrFailure($code): $message';
}

/// Sends register photos to the backend Vision proxy.
///
/// Vision credentials live on the server; this client only ever sees the
/// extracted rows.
class BaptismalOcrService {
  BaptismalOcrService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const Duration _timeout = Duration(seconds: 60);

  // Codes where retrying the same image cannot help (server misconfiguration
  // or a defect in the submitted image/page itself). Everything else --
  // including VISION_QUOTA, VISION_UNAVAILABLE, NO_TEXT_FOUND, and
  // INTERNAL_ERROR -- is a transient condition where a retry may succeed,
  // so it is retryable by omission from this set.
  static const Set<String> _permanent = {
    'VISION_AUTH',
    'IMAGE_INVALID',
    'IMAGE_TOO_LARGE',
    'LAYOUT_UNRECOGNIZED',
    'UNAUTHENTICATED',
  };

  static const Map<String, String> _fallbackMessages = {
    'NETWORK': 'Could not reach the server. Check your connection and retry.',
    'UNAUTHENTICATED': 'You are signed out. Sign in again to scan.',
    'BAD_RESPONSE': 'The server returned an unexpected response. Please retry.',
  };

  Future<BaptismalOcrScan> scan({
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
            Uri.parse('${BackendConfig.apiBaseUrl}/ocr/baptismal/scan'),
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
        decoded['code']?.toString() ?? 'BAD_RESPONSE',
        decoded['message']?.toString(),
      );
    }

    final data = decoded['data'];
    if (data is! Map) throw _failure('BAD_RESPONSE', null);
    return BaptismalOcrScan.fromJson(Map<String, dynamic>.from(data));
  }

  /// Falls back to the signed-in user's Firebase ID token when the caller
  /// doesn't supply one. Swallows any Firebase error (e.g. no app
  /// initialized, no signed-in user) as "no token" rather than letting it
  /// escape as an unrelated exception type.
  Future<String?> _currentUserToken() async {
    try {
      return await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {
      return null;
    }
  }

  BaptismalOcrFailure _failure(String code, String? serverMessage) {
    return BaptismalOcrFailure(
      code: code,
      message: serverMessage ?? _fallbackMessages[code] ?? 'OCR failed. Please retry.',
      retryable: !_permanent.contains(code),
    );
  }
}
