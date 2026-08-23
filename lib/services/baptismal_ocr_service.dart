import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/backend.dart';
import '../models/baptismal_register_row.dart';

/// How the UI should help the user recover from a [BaptismalOcrFailure].
///
/// A single `retryable` bool cannot express what the UI needs: some
/// failures are worth retrying with the same image, some never will be no
/// matter how many times the same bytes are resubmitted, and some aren't
/// about the image at all.
enum OcrRecovery {
  /// Transient condition (server or network). Retrying with the exact same
  /// image bytes may well succeed.
  retry,

  /// These bytes will never produce a usable scan. The user must supply a
  /// different photo; retrying the same upload will fail identically.
  differentImage,

  /// The caller has no valid session. The user must sign in again before
  /// scanning can proceed.
  signIn,

  /// A server-side misconfiguration the user cannot fix themselves.
  contactAdmin,
}

/// A scan failure the UI can act on: show [message], and use [recovery] to
/// decide what action to offer (retry / new photo / sign in / contact
/// admin).
class BaptismalOcrFailure implements Exception {
  const BaptismalOcrFailure({
    required this.code,
    required this.message,
    required this.recovery,
  });

  final String code;
  final String message;
  final OcrRecovery recovery;

  /// True only when retrying with the same image bytes may succeed.
  /// Derived from [recovery]; kept for existing callers that only need a
  /// bool (e.g. Task 15's retry button).
  bool get retryable => recovery == OcrRecovery.retry;

  @override
  String toString() => 'BaptismalOcrFailure($code): $message';
}

/// Sends register photos to the backend Vision proxy.
///
/// Vision credentials live on the server; this client only ever sees the
/// extracted rows.
class BaptismalOcrService {
  BaptismalOcrService({
    http.Client? client,
    Duration timeout = const Duration(seconds: 60),
  })  : _client = client ?? http.Client(),
        _timeout = timeout;

  final http.Client _client;
  final Duration _timeout;

  // Maps every backend/client error code to how the UI should help the user
  // recover. NO_TEXT_FOUND, IMAGE_INVALID, IMAGE_TOO_LARGE, and
  // LAYOUT_UNRECOGNIZED are about the submitted bytes specifically -- Vision
  // is deterministic on identical input, so re-running OCR on the same
  // upload fails identically every time; the user must supply a different
  // photo. VISION_QUOTA, VISION_UNAVAILABLE, INTERNAL_ERROR, NETWORK, and
  // BAD_RESPONSE are transient (server load, connectivity, a flaky
  // response) and a same-image retry may well succeed. UNAUTHENTICATED
  // means there is no valid session. VISION_AUTH means the server's Vision
  // credentials are misconfigured -- nothing the user can do about that.
  // Any code not listed here (an unrecognized/future server code) defaults
  // to `retry`, matching prior behavior of treating unknown codes as
  // possibly-transient.
  static const Map<String, OcrRecovery> _recoveryByCode = {
    'VISION_QUOTA': OcrRecovery.retry,
    'VISION_UNAVAILABLE': OcrRecovery.retry,
    'INTERNAL_ERROR': OcrRecovery.retry,
    'NETWORK': OcrRecovery.retry,
    'BAD_RESPONSE': OcrRecovery.retry,
    'NO_TEXT_FOUND': OcrRecovery.differentImage,
    'IMAGE_INVALID': OcrRecovery.differentImage,
    'IMAGE_TOO_LARGE': OcrRecovery.differentImage,
    'LAYOUT_UNRECOGNIZED': OcrRecovery.differentImage,
    'UNAUTHENTICATED': OcrRecovery.signIn,
    'VISION_AUTH': OcrRecovery.contactAdmin,
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
      recovery: _recoveryByCode[code] ?? OcrRecovery.retry,
    );
  }
}
