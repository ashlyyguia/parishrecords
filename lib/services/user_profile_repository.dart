import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../config/backend.dart';

class UserProfileRepository {
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

  Future<http.Response> _putJsonWithAuth(Uri url, Object payload) async {
    var token = await _getToken();
    var resp = await http
        .put(
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
          .put(
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

  String _requireUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) throw Exception('Not authenticated');
    return uid;
  }

  Uri _uri(String path) {
    return Uri.parse(BackendConfig.baseUrl).replace(path: path);
  }

  Future<Map<String, dynamic>> getMyProfile() async {
    final uid = _requireUid();
    final url = _uri('/api/users/$uid');

    final resp = await _getWithAuth(url).timeout(
      _timeout,
      onTimeout: () => throw TimeoutException('Profile request timed out'),
    );

    if (resp.statusCode >= 400) {
      throw Exception('Profile API failed (${resp.statusCode})');
    }

    final body = json.decode(resp.body);
    if (body is Map<String, dynamic>) return body;
    throw Exception('Unexpected profile payload');
  }

  Future<void> updateMyProfile(Map<String, dynamic> patch) async {
    final uid = _requireUid();
    final url = _uri('/api/users/$uid');

    final resp = await _putJsonWithAuth(url, patch).timeout(
      _timeout,
      onTimeout: () => throw TimeoutException('Profile update timed out'),
    );

    if (resp.statusCode >= 400) {
      throw Exception('Profile update failed (${resp.statusCode})');
    }
  }

  Future<Map<String, dynamic>> exportMyData() async {
    final uid = _requireUid();
    final url = _uri('/api/users/$uid/export');

    final resp = await _postWithAuth(url).timeout(
      _timeout,
      onTimeout: () => throw TimeoutException('Export request timed out'),
    );

    if (resp.statusCode >= 400) {
      throw Exception('Export failed (${resp.statusCode})');
    }

    final body = json.decode(resp.body);
    if (body is Map<String, dynamic>) return body;
    throw Exception('Unexpected export payload');
  }
}
