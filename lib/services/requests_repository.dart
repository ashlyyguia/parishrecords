import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/backend.dart';

class RequestsRepository {
  String get _base => BackendConfig.baseUrl;

  Future<Map<String, String>> _authHeader() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final token = await user.getIdToken();
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Future<List<Map<String, dynamic>>> list({int limit = 50}) async {
    final headers = await _authHeader();
    final resp = await http.get(
      Uri.parse('$_base/api/requests?limit=$limit'),
      headers: headers,
    );
    if (resp.statusCode != 200) {
      throw Exception('Requests list failed: ${resp.statusCode} ${resp.body}');
    }
    final body = json.decode(resp.body) as Map<String, dynamic>;
    final rows = (body['rows'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return rows;
  }

  Future<void> create({
    required String requestType,
    required String requesterName,
    String? recordId,
    String? parishId,
  }) async {
    final headers = await _authHeader();
    final payload = {
      'request_type': requestType,
      'requester_name': requesterName,
      'record_id': recordId,
      'parish_id': parishId,
    };
    final resp = await http.post(
      Uri.parse('$_base/api/requests'),
      headers: headers,
      body: json.encode(payload),
    );
    if (resp.statusCode != 200) {
      throw Exception('Create request failed: ${resp.statusCode} ${resp.body}');
    }
  }

  Future<void> updateStatus(
    String requestId, {
    required String status,
    bool? notificationSent,
    String? parishId,
  }) async {
    final headers = await _authHeader();
    final payload = {
      'status': status,
      if (notificationSent != null) 'notification_sent': notificationSent,
      if (parishId != null) 'parish_id': parishId,
    };
    final resp = await http.put(
      Uri.parse('$_base/api/requests/$requestId'),
      headers: headers,
      body: json.encode(payload),
    );
    if (resp.statusCode != 200) {
      throw Exception('Update request failed: ${resp.statusCode} ${resp.body}');
    }
  }
}
