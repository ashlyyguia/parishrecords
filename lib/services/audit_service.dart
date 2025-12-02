import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import '../config/backend.dart';
import 'local_storage.dart';

class AuditService {
  static const _boxName = LocalStorageService.auditsBox;

  static Box<dynamic> _box() {
    if (!Hive.isBoxOpen(_boxName)) {
      throw StateError(
        'Audit box not opened. Make sure LocalStorageService.init() is called.',
      );
    }
    return Hive.box(_boxName);
  }

  static Future<void> log({
    required String action,
    required String userId,
    required String details,
    DateTime? timestamp,
  }) async {
    final now = timestamp ?? DateTime.now();
    // Send to backend Cassandra audit_logs table (best-effort, no local storage)
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final token = await user.getIdToken();
        final headers = {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        };
        final payload = json.encode({
          'user_id': userId,
          'action': action,
          'new_values': details,
          'timestamp': now.toIso8601String(),
        });
        final uri = Uri.parse('${BackendConfig.baseUrl}/api/admin/logs');
        await http.post(uri, headers: headers, body: payload);
      }
    } catch (_) {
      // Ignore backend failures for audit logging.
    }
  }

  static Future<List<Map<String, dynamic>>> getLogs({
    int limit = 200,
    int days = 30,
  }) async {
    final box = _box();
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final entries = <Map<String, dynamic>>[];

    for (final value in box.values) {
      if (value is Map) {
        final map = Map<String, dynamic>.from(value);
        final tsRaw = map['action_time'] ?? map['timestamp'];
        final ts = DateTime.tryParse(tsRaw?.toString() ?? '');
        if (ts != null && ts.isAfter(cutoff)) {
          entries.add(map..['action_time'] = ts.toIso8601String());
        }
      }
    }

    entries.sort((a, b) {
      final aTs =
          DateTime.tryParse(a['action_time']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bTs =
          DateTime.tryParse(b['action_time']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bTs.compareTo(aTs);
    });

    if (entries.length > limit) {
      return entries.take(limit).toList();
    }
    return entries;
  }
}
