import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RequestsRepository {
  static const Duration _timeout = Duration(seconds: 12);

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

  Future<List<Map<String, dynamic>>> list({int limit = 50}) async {
    return _listFromFirestore(limit: limit);
  }

  Future<List<Map<String, dynamic>>> _listFromFirestore({
    int limit = 50,
  }) async {
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await FirebaseFirestore.instance
          .collection('requests')
          .orderBy('requested_at', descending: true)
          .limit(limit)
          .get()
          .timeout(
            _timeout,
            onTimeout: () => throw TimeoutException('Requests list timed out'),
          );
    } catch (_) {
      snap = await FirebaseFirestore.instance
          .collection('requests')
          .orderBy('created_at', descending: true)
          .limit(limit)
          .get()
          .timeout(
            _timeout,
            onTimeout: () => throw TimeoutException('Requests list timed out'),
          );
    }

    String toIso(dynamic val) {
      if (val == null) return '';
      if (val is Timestamp) return val.toDate().toIso8601String();
      if (val is DateTime) return val.toIso8601String();
      return val.toString();
    }

    return snap.docs.map((doc) {
      final d = doc.data();
      return <String, dynamic>{
        'request_id': doc.id,
        'record_id': d['record_id'],
        'parish_id': d['parish_id'],
        'request_type': d['request_type'],
        'requester_name': d['requester_name'],
        'status': d['status'] ?? 'pending',
        'requested_at': toIso(
          d['requested_at'] ?? d['created_at'] ?? d['createdAt'],
        ),
        'processed_at': toIso(d['processed_at']),
        'processed_by': d['processed_by'],
        'notification_sent': d['notification_sent'] == true,
      };
    }).toList();
  }

  Future<void> create({
    required String requestType,
    required String requesterName,
    String? recordId,
    String? parishId,
  }) async {
    final uid = _requireUid();
    await _db
        .collection('requests')
        .add({
          'request_type': requestType,
          'requester_name': requesterName,
          'record_id': recordId,
          'parish_id': parishId,
          'status': 'pending',
          'requested_at': FieldValue.serverTimestamp(),
          'created_at': FieldValue.serverTimestamp(),
          'created_by_uid': uid,
          'notification_sent': false,
        })
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Create request timed out'),
        );
  }

  Future<void> updateStatus(
    String requestId, {
    required String status,
    bool? notificationSent,
    String? parishId,
  }) async {
    final isAdmin = await _isAdmin();
    if (!isAdmin) {
      throw Exception('Admin access required');
    }
    await _db
        .collection('requests')
        .doc(requestId)
        .set({
          'status': status,
          'notification_sent': notificationSent,
          'parish_id': parishId,
          'processed_at': FieldValue.serverTimestamp(),
          'processed_by': _requireUid(),
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true))
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Update request timed out'),
        );
  }
}
