import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../config/backend.dart';

class UserDashboardRepository {
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

  String _requireUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) throw Exception('Not authenticated');
    return uid;
  }

  Uri _uri(String path) {
    return Uri.parse(BackendConfig.baseUrl).replace(path: path);
  }

  Future<Map<String, dynamic>> getMyDashboard() async {
    final uid = _requireUid();
    final url = _uri('/api/users/$uid/dashboard');

    debugPrint('Fetching dashboard from: $url');

    try {
      final resp = await _getWithAuth(url).timeout(
        _timeout,
        onTimeout: () => throw TimeoutException(
          'Dashboard request timed out after ${_timeout.inSeconds}s',
        ),
      );

      debugPrint('Dashboard response status: ${resp.statusCode}');

      if (resp.statusCode >= 400) {
        debugPrint('Dashboard error body: ${resp.body}');
        throw Exception(
          'Dashboard API failed (${resp.statusCode}): ${resp.body}',
        );
      }

      final body = json.decode(resp.body);
      if (body is Map<String, dynamic>) {
        debugPrint('Dashboard loaded successfully');
        return body;
      }
      throw Exception('Unexpected dashboard payload: ${resp.body}');
    } catch (e, stackTrace) {
      debugPrint('Dashboard fetch error: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }
}
