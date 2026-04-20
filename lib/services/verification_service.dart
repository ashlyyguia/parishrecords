import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/backend.dart';

/// Service for sending verification emails via backend API (EmailJS)
class VerificationService {
  static String get _base => BackendConfig.baseUrl;

  /// Send verification code email via EmailJS backend
  /// Called after user registers to send the verification code to their email
  static Future<void> sendVerificationEmail({
    required String email,
    required String code,
    String? displayName,
  }) async {
    final uri = Uri.parse('$_base/api/verification/send-code');

    final payload = {'email': email, 'code': code, 'displayName': displayName};

    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Failed to send verification email: ${resp.body}');
    }
  }

  /// Resend verification code for a user
  /// Requires Firebase Auth token
  static Future<void> resendVerificationCode({
    required String uid,
    required String idToken,
  }) async {
    final uri = Uri.parse('$_base/api/verification/resend-code');

    final payload = {'uid': uid};

    final resp = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode(payload),
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Failed to resend verification code: ${resp.body}');
    }
  }

  /// Request password reset link from backend
  static Future<String?> requestPasswordResetLink(String email) async {
    final uri = Uri.parse('$_base/api/auth/reset-password');
    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Failed to request password reset: ${resp.body}');
    }

    final data = jsonDecode(resp.body);
    return data['devModeLink'] as String?;
  }
}
