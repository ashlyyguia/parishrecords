import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuditService {
  static const Duration _timeout = Duration(seconds: 20);

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static String? _uid() => FirebaseAuth.instance.currentUser?.uid;

  static Future<bool> _canWrite() async {
    final uid = _uid();
    if (uid == null || uid.isEmpty) return false;
    final snap = await _db
        .collection('users')
        .doc(uid)
        .get()
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Role lookup timed out'),
        );
    final role = (snap.data()?['role'] ?? '').toString().trim().toLowerCase();
    return role == 'admin' || role == 'staff';
  }

  static Future<void> log({
    required String action,
    required String userId,
    required String details,
    String? userEmail,
    String? userName,
    String? userRole,
    DateTime? timestamp,
  }) async {
    final now = timestamp ?? DateTime.now();
    // Write audit logs to Firestore (best-effort, no local storage)
    try {
      if (!await _canWrite()) return;

      // Get current user info if not provided
      String? email = userEmail;
      String? name = userName;
      String? role = userRole;

      if (email == null || name == null) {
        final user = FirebaseAuth.instance.currentUser;
        email ??= user?.email;
        name ??= user?.displayName ?? email?.split('@').first;
      }

      if (role == null) {
        final snap = await _db
            .collection('users')
            .doc(userId)
            .get()
            .timeout(
              const Duration(seconds: 5),
              onTimeout: () => throw TimeoutException('Role lookup timed out'),
            );
        role = (snap.data()?['role'] ?? 'user').toString();
      }

      await _db
          .collection('audit_logs')
          .add({
            'user_id': userId,
            'user_email': email ?? 'Unknown',
            'user_name': name ?? 'Unknown',
            'user_role': role,
            'action': action,
            'details': details,
            'new_values': details,
            'timestamp': now.toIso8601String(),
            'created_at': FieldValue.serverTimestamp(),
          })
          .timeout(
            _timeout,
            onTimeout: () =>
                throw TimeoutException('Audit log write timed out'),
          );
    } catch (_) {
      // Ignore failures for audit logging.
    }
  }
}
