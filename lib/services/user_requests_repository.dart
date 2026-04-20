import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../config/backend.dart';

class UserRequestsRepository {
  static const Duration _timeout = Duration(seconds: 20);

  Future<String> _getToken({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');
    try {
      final token = await user.getIdToken(forceRefresh);
      if (token == null || token.isEmpty) throw Exception('Missing auth token');
      return token;
    } catch (e) {
      if (e.toString().contains('network-request-failed')) {
        return 'dummy-token-network-failed';
      }
      rethrow;
    }
  }

  Future<http.Response> _getWithAuth(Uri url) async {
    var token = await _getToken();
    var resp = await http
        .get(url, headers: {'Authorization': 'Bearer $token'})
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Request timed out'),
        );

    if (resp.statusCode == 401) {
      token = await _getToken(forceRefresh: true);
      resp = await http
          .get(url, headers: {'Authorization': 'Bearer $token'})
          .timeout(
            _timeout,
            onTimeout: () => throw TimeoutException('Request timed out'),
          );
    }

    return resp;
  }

  Future<http.Response> _postWithAuth(Uri url) async {
    var token = await _getToken();
    var resp = await http
        .post(url, headers: {'Authorization': 'Bearer $token'})
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Request timed out'),
        );

    if (resp.statusCode == 401) {
      token = await _getToken(forceRefresh: true);
      resp = await http
          .post(url, headers: {'Authorization': 'Bearer $token'})
          .timeout(
            _timeout,
            onTimeout: () => throw TimeoutException('Request timed out'),
          );
    }

    return resp;
  }

  String _requireUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) throw Exception('Not authenticated');
    return uid;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse(
      BackendConfig.baseUrl,
    ).replace(path: path, queryParameters: query);
  }

  Future<List<Map<String, dynamic>>> listMyRequests({int limit = 50}) async {
    final uid = _requireUid();
    final url = _uri('/api/requests', {
      'user_id': uid,
      'limit': limit.toString(),
    });

    final resp = await _getWithAuth(url).timeout(
      _timeout,
      onTimeout: () => throw TimeoutException('Requests list timed out'),
    );

    if (resp.statusCode >= 400) {
      throw Exception('Requests list failed (${resp.statusCode})');
    }

    final body = json.decode(resp.body);
    final rows = body is Map<String, dynamic> ? body['rows'] : null;
    if (rows is List) {
      return rows
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> getRequestDetail(String requestId) async {
    final url = _uri('/api/requests/$requestId');

    final resp = await _getWithAuth(url).timeout(
      _timeout,
      onTimeout: () => throw TimeoutException('Request detail timed out'),
    );

    if (resp.statusCode >= 400) {
      throw Exception('Request detail failed (${resp.statusCode})');
    }

    final body = json.decode(resp.body);
    if (body is Map<String, dynamic>) {
      final row = body['row'];
      if (row is Map) return Map<String, dynamic>.from(row);
    }
    throw Exception('Unexpected request detail payload');
  }

  Future<void> cancel(String requestId) async {
    final url = _uri('/api/requests/$requestId/cancel');

    final resp = await _postWithAuth(url).timeout(
      _timeout,
      onTimeout: () => throw TimeoutException('Cancel timed out'),
    );

    if (resp.statusCode >= 400) {
      throw Exception('Cancel failed (${resp.statusCode})');
    }
  }

  Future<Map<String, dynamic>> createRequest(Map<String, dynamic> data) async {
    final url = _uri('/api/requests');
    final token = await _getToken();

    final resp = await http
        .post(
          url,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: json.encode(data),
        )
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Create request timed out'),
        );

    if (resp.statusCode >= 400) {
      throw Exception('Create request failed (${resp.statusCode})');
    }

    final body = json.decode(resp.body);
    if (body is Map<String, dynamic>) {
      final row = body['row'] ?? body;
      if (row is Map) return Map<String, dynamic>.from(row);
    }
    return <String, dynamic>{};
  }
}
