import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../config/backend.dart';

class FinanceRepository {
  static const Duration _timeout = Duration(seconds: 20);

  Never _throwHttp(String message, http.Response resp, Uri url) {
    final snippet = resp.body.length > 400
        ? resp.body.substring(0, 400)
        : resp.body;
    throw Exception('$message (${resp.statusCode}) url=$url body=$snippet');
  }

  Future<String> _getToken({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final token = await user.getIdToken(forceRefresh);
    if (token == null || token.isEmpty) throw Exception('Missing auth token');
    return token;
  }

  Future<http.Response> _getWithAuth(Uri url) async {
    var token = await _getToken();
    var resp = await http
        .get(
          url,
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        )
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Request timed out'),
        );

    if (resp.statusCode == 401) {
      token = await _getToken(forceRefresh: true);
      resp = await http
          .get(
            url,
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(
            _timeout,
            onTimeout: () => throw TimeoutException('Request timed out'),
          );
    }

    return resp;
  }

  Future<http.Response> _postJsonWithAuth(Uri url, Object payload) async {
    var token = await _getToken();
    var resp = await http
        .post(
          url,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
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
              'Accept': 'application/json',
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

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse(
      BackendConfig.baseUrl,
    ).replace(path: path, queryParameters: query);
  }

  Future<Map<String, dynamic>> getOverview({int days = 30}) async {
    final url = _uri('/api/finance/overview', {'days': days.toString()});

    final resp = await _getWithAuth(url).timeout(
      _timeout,
      onTimeout: () => throw TimeoutException('Finance overview timed out'),
    );

    if (resp.statusCode >= 400) {
      _throwHttp('Finance overview failed', resp, url);
    }

    final body = json.decode(resp.body);
    if (body is Map<String, dynamic>) return body;
    throw Exception('Unexpected finance overview payload');
  }

  Future<Map<String, dynamic>> bankImport({
    required List<Map<String, dynamic>> rows,
  }) async {
    final url = _uri('/api/finance/bank_import');

    final resp = await _postJsonWithAuth(url, {'rows': rows}).timeout(
      _timeout,
      onTimeout: () => throw TimeoutException('Bank import timed out'),
    );

    if (resp.statusCode >= 400) {
      throw Exception('Bank import failed (${resp.statusCode})');
    }

    final body = json.decode(resp.body);
    if (body is Map<String, dynamic>) return body;
    throw Exception('Unexpected bank import payload');
  }

  Future<Map<String, dynamic>> reconcile({
    required List<Map<String, dynamic>> matches,
  }) async {
    final url = _uri('/api/finance/reconcile');

    final resp = await _postJsonWithAuth(url, {'matches': matches}).timeout(
      _timeout,
      onTimeout: () => throw TimeoutException('Reconcile timed out'),
    );

    if (resp.statusCode >= 400) {
      throw Exception('Reconcile failed (${resp.statusCode})');
    }

    final body = json.decode(resp.body);
    if (body is Map<String, dynamic>) return body;
    throw Exception('Unexpected reconcile payload');
  }
}
