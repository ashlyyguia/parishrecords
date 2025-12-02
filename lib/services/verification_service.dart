import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/backend.dart';

class VerificationService {
  String get _base => BackendConfig.baseUrl;

  Future<void> sendCode({required String email, required String code}) async {
    final uri = Uri.parse('$_base/api/auth/send-code');
    final resp = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: json.encode({'email': email, 'code': code}),
    );

    if (resp.statusCode != 200) {
      throw Exception(
        'Failed to send verification code: ${resp.statusCode} ${resp.body}',
      );
    }
  }
}
