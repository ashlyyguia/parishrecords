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
    this.detail,
  });

  final String code;
  final String message;
  final OcrRecovery recovery;

  /// Optional capture-guidance text for a refused spread (which page / what to
  /// fix). Populated from the server's `detail` field when present.
  final String? detail;

  /// True only when retrying with the same image bytes may succeed.
  /// Derived from [recovery]; kept for existing callers that only need a
  /// bool (e.g. Task 15's retry button).
  bool get retryable => recovery == OcrRecovery.retry;

  @override
  String toString() => 'BaptismalOcrFailure($code): $message';
}

/// Sends register photos to the backend OCR.space proxy.
///
/// The OCR.space key lives on the server; this client only ever sees the
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
  // LAYOUT_UNRECOGNIZED are about the submitted bytes specifically -- OCR
  // is deterministic on identical input, so re-running OCR on the same
  // upload fails identically every time; the user must supply a different
  // photo. OCR_QUOTA, OCR_UNAVAILABLE, INTERNAL_ERROR, NETWORK, and
  // BAD_RESPONSE are transient (server load, connectivity, a flaky
  // response) and a same-image retry may well succeed. UNAUTHENTICATED
  // means there is no valid session. OCR_AUTH means the server's OCR.space
  // key is misconfigured -- nothing the user can do about that.
  // Any code not listed here (an unrecognized/future server code) defaults
  // to `retry`, matching prior behavior of treating unknown codes as
  // possibly-transient.
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
    // The CV service ran and judged this spread unreadable (faded rules, a
    // page out of frame, the book not opened flat). Re-submitting the same
    // bytes fails identically, so the user must retake -- not retry.
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
        'Your account does not have permission to scan baptismal records. '
        'Contact an administrator.',
  };

  /// Maps an HTTP status to an error code when the server response carries
  /// none of its own.
  ///
  /// `verifyFirebaseToken` (`backend/src/middleware/auth.js`) replies
  /// `{ error: '...' }` on a 401 -- no `code` key at all -- and
  /// `requireStaffOrAdmin` (`backend/src/routes/baptismal_ocr_firestore.js`)
  /// replies `{ success: false, message: '...' }` on a 403, also with no
  /// `code`. Both used to fall through to the generic `'BAD_RESPONSE'` ??
  /// fallback below, which maps to [OcrRecovery.retry] -- so an admin whose
  /// token had simply expired saw "The server returned an unexpected
  /// response. Please retry." and an infinite, never-succeeding retry loop,
  /// because [OcrRecovery.signIn] (the only recovery that actually fixes an
  /// expired token) could never be produced by the server's response shape.
  /// Reading the HTTP status directly closes that gap without requiring any
  /// backend change.
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
      // `decoded['code']` is present for every response this route itself
      // generates (see `baptismal_ocr_firestore.js`'s `fail()`), but 401s
      // from `verifyFirebaseToken` and 403s from `requireStaffOrAdmin` --
      // both shared/generic middleware, not this route's own error path --
      // carry no `code` at all. `_codeForStatus` derives one from the HTTP
      // status itself in that case, rather than defaulting to
      // 'BAD_RESPONSE' (which maps to an endless, never-succeeding retry
      // loop for what is actually an expired-session or permissions
      // problem). `decoded['error']` covers `verifyFirebaseToken`'s
      // `{ error: '...' }` shape, which uses a different key than every
      // other response's `message`.
      throw _failure(
        decoded['code']?.toString() ?? _codeForStatus(res.statusCode),
        decoded['message']?.toString() ?? decoded['error']?.toString(),
        decoded['detail']?.toString(),
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

  BaptismalOcrFailure _failure(String code, String? serverMessage, [String? detail]) {
    return BaptismalOcrFailure(
      code: code,
      message: serverMessage ?? _fallbackMessages[code] ?? 'OCR failed. Please retry.',
      recovery: _recoveryByCode[code] ?? OcrRecovery.retry,
      detail: detail,
    );
  }
}
