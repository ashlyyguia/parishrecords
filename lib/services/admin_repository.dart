import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/record.dart';

class AdminRepository {
  static const Duration _timeout = Duration(seconds: 20);

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  String _requireUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw Exception('Not authenticated');
    }
    return uid;
  }

  Future<bool> _isAdmin() async {
    final uid = _requireUid();
    final snap = await _db
        .collection('users')
        .doc(uid)
        .get()
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Role lookup timed out'),
        );
    final role = (snap.data()?['role'] ?? '').toString().trim().toLowerCase();
    return role == 'admin';
  }

  Future<List<ParishRecord>> listRecent({int limit = 50, int days = 7}) async {
    throw UnimplementedError('Firebase-only: listRecent not implemented yet');
  }

  Future<List<ParishRecord>> listByUser(String userId, {int limit = 50}) async {
    throw UnimplementedError('Firebase-only: listByUser not implemented yet');
  }

  Future<void> update(
    String id, {
    String? name,
    String? parish,
    String? imagePath,
  }) async {
    throw UnimplementedError('Firebase-only: update record not implemented');
  }

  Future<void> delete(String id) async {
    throw UnimplementedError('Firebase-only: delete record not implemented');
  }

  Future<void> deleteUser(String id) async {
    throw UnimplementedError('Firebase-only: deleteUser not implemented');
  }

  Future<Map<String, dynamic>> getSettings() async {
    final isAdmin = await _isAdmin();
    if (!isAdmin) throw Exception('Admin access required');

    final snap = await _db
        .collection('settings')
        .doc('app')
        .get()
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Settings load timed out'),
        );
    final d = snap.data();
    if (d == null) {
      return {
        'language': 'en',
        'timezone': 'UTC',
        'notify': true,
        'auto_backup': false,
      };
    }
    return {
      'language': d['language'] ?? 'en',
      'timezone': d['timezone'] ?? 'UTC',
      'notify': d['notify'] == null ? true : d['notify'] == true,
      'auto_backup': d['auto_backup'] == true,
    };
  }

  Future<void> saveSettings({
    required String language,
    required String timezone,
    required bool notify,
    required bool autoBackup,
  }) async {
    final isAdmin = await _isAdmin();
    if (!isAdmin) throw Exception('Admin access required');

    await _db
        .collection('settings')
        .doc('app')
        .set({
          'language': language,
          'timezone': timezone,
          'notify': notify,
          'auto_backup': autoBackup,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true))
        .timeout(
          _timeout,
          onTimeout: () =>
              throw TimeoutException('Admin settings save timed out'),
        );
  }

  Future<List<Map<String, dynamic>>> getLogs({
    int limit = 100,
    int days = 7,
  }) async {
    final isAdmin = await _isAdmin();
    if (!isAdmin) throw Exception('Admin access required');

    final cutoff = DateTime.now().subtract(Duration(days: days));
    final snap = await _db
        .collection('audit_logs')
        .orderBy('created_at', descending: true)
        .limit(limit)
        .get()
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Audit logs timed out'),
        );

    String toIso(dynamic v) {
      if (v == null) return '';
      if (v is Timestamp) return v.toDate().toIso8601String();
      if (v is DateTime) return v.toIso8601String();
      return v.toString();
    }

    final rows = <Map<String, dynamic>>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      final createdAt = d['created_at'];
      DateTime created = DateTime.tryParse(toIso(createdAt)) ?? DateTime.now();
      if (created.isBefore(cutoff)) continue;
      rows.add({
        'id': doc.id,
        'user_id': d['user_id'],
        'action': d['action'],
        'details': d['details'],
        'new_values': d['new_values'],
        'timestamp': d['timestamp'] ?? toIso(createdAt),
        'created_at': toIso(createdAt),
        'resource_id': d['resource_id'],
        'resource_type': d['resource_type'],
      });
    }
    return rows;
  }

  Future<List<Map<String, dynamic>>> getRecordHistory(
    String recordId, {
    int limit = 50,
  }) async {
    final isAdmin = await _isAdmin();
    if (!isAdmin) throw Exception('Admin access required');

    final snap = await _db
        .collection('audit_logs')
        .where('resource_id', isEqualTo: recordId)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .get()
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Record history timed out'),
        );

    String toIso(dynamic v) {
      if (v == null) return '';
      if (v is Timestamp) return v.toDate().toIso8601String();
      if (v is DateTime) return v.toIso8601String();
      return v.toString();
    }

    return snap.docs.map((doc) {
      final d = doc.data();
      final createdAt = d['created_at'];
      return <String, dynamic>{
        'id': doc.id,
        'user_id': d['user_id'],
        'action': d['action'],
        'details': d['details'],
        'new_values': d['new_values'],
        'timestamp': d['timestamp'] ?? toIso(createdAt),
        'created_at': toIso(createdAt),
        'resource_id': d['resource_id'],
        'resource_type': d['resource_type'],
      };
    }).toList();
  }

  Future<void> deleteLog(String id) async {
    final isAdmin = await _isAdmin();
    if (!isAdmin) throw Exception('Admin access required');
    await _db
        .collection('audit_logs')
        .doc(id)
        .delete()
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Delete log timed out'),
        );
  }

  Future<List<Map<String, dynamic>>> getUsers(
    String? role, {
    int limit = 100,
  }) async {
    final isAdmin = await _isAdmin();
    if (!isAdmin) throw Exception('Admin access required');

    Query<Map<String, dynamic>> q = _db
        .collection('users')
        .orderBy('createdAt', descending: true);
    if (role != null && role.trim().isNotEmpty) {
      q = q.where('role', isEqualTo: role.trim());
    }

    final snap = await q
        .limit(limit)
        .get()
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Get users timed out'),
        );
    return snap.docs
        .map((d) => <String, dynamic>{'uid': d.id, ...d.data()})
        .toList();
  }

  Future<void> setUserRole(String uid, String role) async {
    final isAdmin = await _isAdmin();
    if (!isAdmin) throw Exception('Admin access required');
    await _db.collection('users').doc(uid).set({
      'role': role,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setUserStatus(String uid, bool disabled) async {
    final isAdmin = await _isAdmin();
    if (!isAdmin) throw Exception('Admin access required');
    await _db.collection('users').doc(uid).set({
      'disabled': disabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<List<Map<String, dynamic>>> getDailyCounts({int days = 14}) async {
    throw UnimplementedError(
      'Firebase-only: daily record metrics not implemented yet',
    );
  }

  Future<List<Map<String, dynamic>>> getAnalytics({
    int days = 30,
    String? metricType,
  }) async {
    // Firebase-only: no backend analytics yet.
    // Keep signature for UI compatibility.
    final isAdmin = await _isAdmin();
    if (!isAdmin) throw Exception('Admin access required');
    return const <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> getSummary({int days = 7}) async {
    final isAdmin = await _isAdmin();
    if (!isAdmin) throw Exception('Admin access required');
    return await _generateLocalSummary(days: days);
  }

  Future<bool> usersHealth() async {
    final isAdmin = await _isAdmin();
    if (!isAdmin) throw Exception('Admin access required');
    final snap = await _db
        .collection('users')
        .limit(1)
        .get()
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Get users health timed out'),
        );
    return snap.docs.isNotEmpty || snap.size == 0;
  }

  Future<int> usersSync() async {
    // Firebase-only: no sync job needed.
    final isAdmin = await _isAdmin();
    if (!isAdmin) throw Exception('Admin access required');
    final snap = await _db
        .collection('users')
        .get()
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Get users sync timed out'),
        );
    return snap.docs.length;
  }

  Future<Map<String, dynamic>> _generateLocalSummary({int days = 7}) async {
    try {
      // Get user counts from Firestore only (no local records cache)
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .get();
      final usersByRole = <String, int>{};

      for (final doc in usersSnapshot.docs) {
        final role = doc.data()['role'] as String? ?? 'staff';
        usersByRole[role] = (usersByRole[role] ?? 0) + 1;
      }

      return {
        'total_records_last_days': 0,
        'users_by_role': usersByRole.isNotEmpty
            ? usersByRole
            : {'admin': 1, 'staff': 2},
        'total_users': usersSnapshot.docs.isNotEmpty
            ? usersSnapshot.docs.length
            : 4,
        'generated_at': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {
        'total_records_last_days': 0,
        'users_by_role': {'admin': 0, 'staff': 0},
        'total_users': 0,
        'error': e.toString(),
      };
    }
  }
}
