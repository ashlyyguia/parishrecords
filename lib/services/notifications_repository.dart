import 'dart:convert';
import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/backend.dart';
import '../models/notification.dart';

class NotificationsRepository {
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

  LocalNotification _fromBackend(Map<String, dynamic> m) {
    final createdRaw = m['createdAt'] ?? m['created_at'];
    final createdAt =
        DateTime.tryParse(createdRaw?.toString() ?? '') ?? DateTime.now();
    return LocalNotification(
      id: (m['id'] ?? '').toString(),
      title: (m['title'] ?? '').toString(),
      body: (m['body'] ?? '').toString(),
      createdAt: createdAt,
      read: m['read'] == true,
      archived: m['archived'] == true,
    );
  }

  Future<List<Map<String, dynamic>>> listRaw({int limit = 100}) async {
    try {
      final headers = await _authHeader();
      final uri = Uri.parse('$_base/api/notifications?limit=$limit');
      final resp = await http.get(uri, headers: headers);
      if (resp.statusCode != 200) {
        throw Exception(
          'Notifications list failed: ${resp.statusCode} ${resp.body}',
        );
      }
      final body = json.decode(resp.body) as Map<String, dynamic>;
      final rows = (body['rows'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      return rows;
    } catch (e) {
      developer.log(
        'Notifications list error: $e',
        name: 'NotificationsRepository',
      );
      return const [];
    }
  }

  Future<List<LocalNotification>> list({int limit = 100}) async {
    final rows = await listRaw(limit: limit);
    return rows.map(_fromBackend).toList();
  }

  Future<void> setRead(String id, bool read) async {
    try {
      final headers = await _authHeader();
      final uri = Uri.parse('$_base/api/notifications/$id/read');
      final payload = json.encode({'read': read});
      final resp = await http.patch(uri, headers: headers, body: payload);
      if (resp.statusCode != 200) {
        throw Exception('Set read failed: ${resp.statusCode} ${resp.body}');
      }
    } catch (e) {
      developer.log(
        'Notifications setRead error: $e',
        name: 'NotificationsRepository',
      );
      rethrow;
    }
  }

  Future<void> setArchived(String id, bool archived) async {
    try {
      final headers = await _authHeader();
      final uri = Uri.parse('$_base/api/notifications/$id/archive');
      final payload = json.encode({'archived': archived});
      final resp = await http.patch(uri, headers: headers, body: payload);
      if (resp.statusCode != 200) {
        throw Exception('Set archived failed: ${resp.statusCode} ${resp.body}');
      }
    } catch (e) {
      developer.log(
        'Notifications setArchived error: $e',
        name: 'NotificationsRepository',
      );
      rethrow;
    }
  }

  Future<void> create({required String title, required String body}) async {
    try {
      final headers = await _authHeader();
      final uri = Uri.parse('$_base/api/notifications');
      final payload = json.encode({'title': title, 'body': body});
      final resp = await http.post(uri, headers: headers, body: payload);
      if (resp.statusCode != 201) {
        throw Exception(
          'Create notification failed: ${resp.statusCode} ${resp.body}',
        );
      }
    } catch (e) {
      developer.log(
        'Notifications create error: $e',
        name: 'NotificationsRepository',
      );
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    try {
      final headers = await _authHeader();
      final uri = Uri.parse('$_base/api/notifications/$id');
      final resp = await http.delete(uri, headers: headers);
      if (resp.statusCode != 200) {
        throw Exception(
          'Delete notification failed: ${resp.statusCode} ${resp.body}',
        );
      }
    } catch (e) {
      developer.log(
        'Notifications delete error: $e',
        name: 'NotificationsRepository',
      );
      rethrow;
    }
  }
}
