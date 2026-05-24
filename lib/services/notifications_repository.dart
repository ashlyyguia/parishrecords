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

  /// Admin, staff, and finance can see broadcast notifications in the inbox.
  Future<bool> _hasBroadInboxAccess() async {
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
      return role == 'admin' || role == 'staff' || role == 'finance';
    } catch (e) {
      developer.log('Role lookup failed: $e', name: 'NotificationsRepository');
      return false;
    }
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
      return role == 'admin' || role == 'staff';
    } catch (e) {
      developer.log('Role lookup failed: $e', name: 'NotificationsRepository');
      return false;
    }
  }

  Future<String> _currentUserRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return '';
    try {
      final snap = await _db.collection('users').doc(uid).get().timeout(_timeout);
      return (snap.data()?['role'] ?? '').toString().trim().toLowerCase();
    } catch (_) {
      return '';
    }
  }

  /// Whether [data] is visible to the signed-in user ([uid], [role]).
  bool _matchesInbox(
    Map<String, dynamic> data, {
    required String uid,
    required String role,
    required bool broadInbox,
  }) {
    final audienceRaw = data['audience'];
    if (audienceRaw is List && audienceRaw.isNotEmpty) {
      final allowed = audienceRaw
          .map((e) => e.toString().trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toList();
      return allowed.contains(role);
    }

    final userId = (data['user_id'] ?? '').toString().trim();
    if (userId.isNotEmpty) {
      return userId == uid;
    }

    // Role-wide broadcasts (no user_id, no audience list).
    return broadInbox;
  }

  /// Finance/admin inbox alert tied to a donation or fee record.
  Future<void> notifyFinanceAudience({
    required String title,
    required String body,
    required String type,
    required String route,
    required String resourceId,
    String? createdByUid,
  }) async {
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    final createdBy = createdByUid ??
        ((authUid != null && authUid.isNotEmpty) ? authUid : 'guest');

    await _db.collection('notifications').add({
      'title': title,
      'body': body,
      'audience': ['finance', 'admin'],
      'type': type,
      'route': route,
      'resource_id': resourceId,
      'created_at': FieldValue.serverTimestamp(),
      'created_by_uid': createdBy,
    }).timeout(
      _timeout,
      onTimeout: () =>
          throw TimeoutException('Finance notification create timed out'),
    );
  }

  /// Online / GCash donation (landing or signed-in).
  Future<void> notifyFinanceOnOnlineDonation({
    required String donationId,
    required String donorName,
    required String donationType,
    required String paymentMethod,
    double amount = 0,
    bool amountPending = false,
  }) async {
    final channel = paymentMethod.toLowerCase() == 'gcash'
        ? 'GCash'
        : paymentMethod.toLowerCase() == 'maya'
            ? 'Maya'
            : paymentMethod.toLowerCase() == 'gotyme'
                ? 'GoTyme'
                : paymentMethod;

    final amountLabel = amountPending || amount <= 0
        ? 'amount pending in app'
        : '₱${amount.toStringAsFixed(2)}';

    await notifyFinanceAudience(
      title: 'New online donation',
      body: '$donorName — $amountLabel via $channel ($donationType)',
      type: 'online_donation',
      route: '/donations',
      resourceId: donationId,
    );
  }

  /// Admin manual in-person cash donation.
  Future<void> notifyFinanceOnCashDonation({
    required String donationId,
    required String donorName,
    required double amount,
    String? campaign,
    String method = 'cash',
  }) async {
    final camp = (campaign ?? 'General').trim();
    final methodLabel = method.toLowerCase() == 'cash' ? 'cash' : method;
    await notifyFinanceAudience(
      title: 'Cash donation recorded',
      body:
          '$donorName — ₱${amount.toStringAsFixed(2)} in-person $methodLabel ($camp)',
      type: 'cash_donation',
      route: '/donations',
      resourceId: donationId,
    );
  }

  /// Admin certificate fee payment.
  Future<void> notifyFinanceOnCertificateFee({
    required String donationId,
    required String payerName,
    required double amount,
    String? certificateType,
    String method = 'cash',
  }) async {
    final cert = (certificateType ?? 'Certificate').trim();
    final methodLabel = method.toLowerCase() == 'cash' ? 'cash' : method;
    await notifyFinanceAudience(
      title: 'Certificate fee recorded',
      body:
          '$payerName — ₱${amount.toStringAsFixed(2)} for $cert ($methodLabel)',
      type: 'certificate_fee',
      route: '/certificate-fees',
      resourceId: donationId,
    );
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
      type: data['type']?.toString(),
      route: (data['route'] ?? data['action_route'])?.toString(),
      resourceId: (data['resource_id'] ?? data['resourceId'])?.toString(),
    );
  }

  Future<List<LocalNotification>> list({int limit = 100}) async {
    final uid = _requireUid();
    final broadInbox = await _hasBroadInboxAccess();
    final role = await _currentUserRole();

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
      if (!_matchesInbox(
        data,
        uid: uid,
        role: role,
        broadInbox: broadInbox,
      )) {
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

  /// Remove from the signed-in user's inbox (archive + mark read).
  Future<void> dismissFromInbox(String id) async {
    final uid = _requireUid();
    final ref = _db
        .collection('notifications')
        .doc(id)
        .collection('user_state')
        .doc(uid);
    await ref.set({
      'archived': true,
      'read': true,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).timeout(
      _timeout,
      onTimeout: () =>
          throw TimeoutException('Dismiss notification timed out'),
    );
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

  Future<void> createSystemNotification({
    required String title,
    required String body,
    required String userId,
    String? type,
    String? route,
    String? resourceId,
  }) async {
    await _db.collection('notifications').add({
      'title': title,
      'body': body,
      'user_id': userId,
      'type': type ?? 'system',
      if (route != null && route.isNotEmpty) 'route': route,
      if (resourceId != null && resourceId.isNotEmpty)
        'resource_id': resourceId,
      'created_at': FieldValue.serverTimestamp(),
      'created_by_uid': 'system',
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
