import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../config/backend.dart';

class StaffScheduleRepository {
  static const Duration _timeout = Duration(seconds: 20);

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

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse(
      BackendConfig.baseUrl,
    ).replace(path: path, queryParameters: query);
  }

  Future<List<Map<String, dynamic>>> listTodayEvents({
    String date = 'today',
  }) async {
    final url = _uri('/api/events', {'date': date});

    final resp = await _getWithAuth(url).timeout(
      _timeout,
      onTimeout: () => throw TimeoutException('Events request timed out'),
    );

    if (resp.statusCode >= 400) {
      throw Exception('Events API failed (${resp.statusCode})');
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

  Future<List<Map<String, dynamic>>> listBookings({
    String? eventId,
    int limit = 100,
  }) async {
    final q = <String, String>{'limit': limit.toString()};
    if (eventId != null && eventId.isNotEmpty) q['event_id'] = eventId;

    final url = _uri('/api/bookings', q);
    final resp = await _getWithAuth(url).timeout(
      _timeout,
      onTimeout: () => throw TimeoutException('Bookings request timed out'),
    );

    if (resp.statusCode >= 400) {
      throw Exception('Bookings API failed (${resp.statusCode})');
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

  Future<void> confirmBooking(String bookingId) async {
    final url = _uri('/api/bookings/$bookingId/confirm');

    final resp = await _postWithAuth(url).timeout(
      _timeout,
      onTimeout: () => throw TimeoutException('Confirm request timed out'),
    );

    if (resp.statusCode >= 400) {
      throw Exception('Confirm API failed (${resp.statusCode})');
    }
  }
}
