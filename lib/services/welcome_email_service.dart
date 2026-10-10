import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/backend.dart';

/// Asks the backend to email a "successfully registered" welcome message to
/// the signed-in user. The backend takes the address from the ID token and
/// sends it at most once per account.
///
/// Best effort: registration never waits on or fails because of this.
class WelcomeEmailService {
  WelcomeEmailService._();

  static Future<void> send({http.Client? client}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await user.getIdToken();
      final c = client ?? http.Client();
      try {
        final resp = await c
            .post(
              Uri.parse('${BackendConfig.apiBaseUrl}/auth/welcome-email'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 20));
        if (resp.statusCode >= 300) {
          debugPrint('Welcome email not sent: ${resp.statusCode} ${resp.body}');
        }
      } finally {
        if (client == null) c.close();
      }
    } catch (e) {
      debugPrint('Welcome email request failed: $e');
    }
  }
}
