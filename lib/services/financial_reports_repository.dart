import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../config/backend.dart';

class FinancialReportsRepository {
  static const Duration _timeout = Duration(seconds: 30);

  Future<String> _getToken({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final token = await user.getIdToken(forceRefresh);
    if (token == null || token.isEmpty) throw Exception('Missing auth token');
    return token;
  }

  Future<http.Response> _postJsonWithAuth(Uri url, Object payload) async {
    var token = await _getToken();
    var resp = await http
        .post(
          url,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: json.encode(payload),
        )
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Request timed out'),
        );

    if (resp.statusCode == 401) {
      token = await _getToken(forceRefresh: true);
      resp = await http
          .post(
            url,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: json.encode(payload),
          )
          .timeout(
            _timeout,
            onTimeout: () => throw TimeoutException('Request timed out'),
          );
    }

    return resp;
  }

  Uri _uri(String path) {
    return Uri.parse(BackendConfig.baseUrl).replace(path: path);
  }

  Future<Map<String, dynamic>> generate({
    required String template,
    required DateTime from,
    required DateTime to,
  }) async {
    final url = _uri('/api/reports/financial');

    final payload = {
      'template': template,
      'from': from.toIso8601String(),
      'to': to.toIso8601String(),
    };

    final resp = await _postJsonWithAuth(url, payload).timeout(
      _timeout,
      onTimeout: () => throw TimeoutException('Report generation timed out'),
    );

    if (resp.statusCode >= 400) {
      throw Exception('Reports API failed (${resp.statusCode})');
    }

    final body = json.decode(resp.body);
    if (body is Map<String, dynamic>) return body;
    throw Exception('Unexpected report payload');
  }
}
