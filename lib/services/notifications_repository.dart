import 'dart:developer' as developer;
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/notification.dart';

class NotificationsRepository {
  static const Duration _timeout = Duration(seconds: 20);

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  String _requireUid() {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    if (uid == null || uid.isEmpty) {
      throw Exception('Not authenticated');
    }
    return uid;
  }

  Future<bool> _isAdmin() async {
    final uid = _requireUid();
    try {
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
    } catch (e) {
      developer.log('Role lookup failed: $e', name: 'NotificationsRepository');
      return false;
    }
  }

  Future<void> bulkSetRead(List<String> ids, bool read) async {
    if (ids.isEmpty) return;
    final uid = _requireUid();

    final batch = _db.batch();
    final now = FieldValue.serverTimestamp();
    for (final id in ids.take(200)) {
      final nid = id.toString();
      if (nid.isEmpty) continue;
      final ref = _db
          .collection('notifications')
          .doc(nid)
          .collection('user_state')
          .doc(uid);
      batch.set(ref, {
        'read': read,
        'updated_at': now,
      }, SetOptions(merge: true));
    }
    await batch.commit().timeout(
      _timeout,
      onTimeout: () =>
          throw TimeoutException('Bulk update notifications timed out'),
    );
  }

  Future<void> bulkSetArchived(List<String> ids, bool archived) async {
    if (ids.isEmpty) return;
    final uid = _requireUid();

    final batch = _db.batch();
    final now = FieldValue.serverTimestamp();
    for (final id in ids.take(200)) {
      final nid = id.toString();
      if (nid.isEmpty) continue;
      final ref = _db
          .collection('notifications')
          .doc(nid)
          .collection('user_state')
          .doc(uid);
      batch.set(ref, {
        'archived': archived,
        'updated_at': now,
      }, SetOptions(merge: true));
    }
    await batch.commit().timeout(
      _timeout,
      onTimeout: () =>
          throw TimeoutException('Bulk archive notifications timed out'),
    );
  }

  LocalNotification _fromFirestore(
    String id,
    Map<String, dynamic> data, {
    required bool read,
    required bool archived,
  }) {
    DateTime createdAt = DateTime.now();
    final ts = data['created_at'] ?? data['createdAt'];
    if (ts is Timestamp) {
      createdAt = ts.toDate();
    } else if (ts is DateTime) {
      createdAt = ts;
    } else if (ts is String) {
      createdAt = DateTime.tryParse(ts) ?? DateTime.now();
    }
    return LocalNotification(
      id: id,
      title: (data['title'] ?? '').toString(),
      body: (data['body'] ?? data['message'] ?? '').toString(),
      createdAt: createdAt,
      read: read,
      archived: archived,
    );
  }

  Future<List<LocalNotification>> list({int limit = 100}) async {
    final uid = _requireUid();
    final isAdmin = await _isAdmin();

    final snap = await _db
        .collection('notifications')
        .orderBy('created_at', descending: true)
        .limit(limit)
        .get()
        .timeout(
          _timeout,
          onTimeout: () =>
              throw TimeoutException('Notifications list timed out'),
        );

    final results = <LocalNotification>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final userId = (data['user_id'] ?? '').toString();
      final isBroadcast = data['user_id'] == null || userId.isEmpty;
      if (!isAdmin && !isBroadcast && userId != uid) {
        continue;
      }

      bool read = false;
      bool archived = false;
      try {
        final stateSnap = await doc.reference
            .collection('user_state')
            .doc(uid)
            .get()
            .timeout(
              _timeout,
              onTimeout: () =>
                  throw TimeoutException('Notification state timed out'),
            );
        final s = stateSnap.data();
        if (s != null) {
          read = s['read'] == true;
          archived = s['archived'] == true;
        }
      } catch (_) {}

      results.add(_fromFirestore(doc.id, data, read: read, archived: archived));
    }
    return results;
  }

  Future<List<LocalNotification>> listStrict({int limit = 100}) async {
    return list(limit: limit);
  }

  Future<void> setRead(String id, bool read) async {
    final uid = _requireUid();
    final ref = _db
        .collection('notifications')
        .doc(id)
        .collection('user_state')
        .doc(uid);
    await ref.set({
      'read': read,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setArchived(String id, bool archived) async {
    final uid = _requireUid();
    final ref = _db
        .collection('notifications')
        .doc(id)
        .collection('user_state')
        .doc(uid);
    await ref.set({
      'archived': archived,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> create({
    required String title,
    required String body,
    String? userId,
  }) async {
    final isAdmin = await _isAdmin();
    if (!isAdmin) {
      throw Exception('Admin access required');
    }
    await _db.collection('notifications').add({
      'title': title,
      'body': body,
      'user_id': userId,
      'created_at': FieldValue.serverTimestamp(),
      'created_by_uid': _requireUid(),
    });
  }

  Future<void> delete(String id) async {
    final isAdmin = await _isAdmin();
    if (!isAdmin) {
      throw Exception('Admin access required');
    }
    await _db.collection('notifications').doc(id).delete();
  }
}
