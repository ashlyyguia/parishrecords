import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import '../config/backend.dart';
import 'local_storage.dart';

class SyncService {
  static Timer? _timer;

  static Future<void> enqueue(String op, Map<String, dynamic> payload) async {
    final box = Hive.box(LocalStorageService.syncQueueBox);
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    await box.put(id, {
      'id': id,
      'op': op, // create_record | update_record | delete_record
      'payload': json.encode(payload),
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
      'retry': 0,
      'lastError': null,
    });
  }

  static void start({Duration interval = const Duration(seconds: 10)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _drainQueue());
  }

  static Future<void> _drainQueue() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final token = await user.getIdToken();
    final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
    final base = BackendConfig.baseUrl;

    final box = Hive.box(LocalStorageService.syncQueueBox);
    final keys = box.keys.toList(growable: false);
    for (final key in keys) {
      final m = box.get(key) as Map?;
      if (m == null) continue;
      final op = (m['op'] ?? '').toString();
      final payloadStr = (m['payload'] ?? '{}').toString();
      final payload = json.decode(payloadStr) as Map<String, dynamic>;
      int retry = (m['retry'] as int?) ?? 0;

      try {
        if (op == 'create_record') {
          final resp = await http.post(Uri.parse('$base/api/records'), headers: headers, body: json.encode(payload));
          if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
          await box.delete(key);
        } else if (op == 'update_record') {
          final id = (payload['id'] ?? '').toString();
          if (id.isEmpty) throw Exception('Missing id');
          final data = Map<String, dynamic>.from(payload)..remove('id');
          final resp = await http.put(Uri.parse('$base/api/records/$id'), headers: headers, body: json.encode(data));
          if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
          await box.delete(key);
        } else if (op == 'delete_record') {
          final id = (payload['id'] ?? '').toString();
          if (id.isEmpty) throw Exception('Missing id');
          final resp = await http.delete(Uri.parse('$base/api/records/$id'), headers: headers);
          if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
          await box.delete(key);
        } else {
          // Unknown op -> drop
          await box.delete(key);
        }
      } catch (e) {
        // backoff: cap retries
        retry += 1;
        if (retry > 10) {
          await box.put(key, {
            ...m,
            'status': 'failed',
            'retry': retry,
            'lastError': e.toString(),
          });
        } else {
          await box.put(key, {
            ...m,
            'status': 'pending',
            'retry': retry,
            'lastError': e.toString(),
          });
        }
      }
    }
  }
}
