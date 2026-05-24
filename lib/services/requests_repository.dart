import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'notifications_repository.dart';

class RequestsRepository {
  final NotificationsRepository _notifications = NotificationsRepository();
  static const Duration _timeout = Duration(seconds: 12);

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  String _requireUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw Exception('Not authenticated');
    }
    return uid;
  }

  Future<bool> _canManageRequests() async {
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
    return role == 'admin' || role == 'staff';
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
        'certificate_for_name':
            d['certificate_for_name'] ?? d['requester_name'],
        'submitted_by_name': d['submitted_by_name'],
        'status': d['status'] ?? 'pending',
        'requested_at': toIso(
          d['requested_at'] ?? d['created_at'] ?? d['createdAt'],
        ),
        'processed_at': toIso(d['processed_at']),
        'processed_by': d['processed_by'],
        'notification_sent': d['notification_sent'] == true,
        'created_by_uid': d['created_by_uid'],
      };
    }).toList();
  }

  Future<void> create({
    required String requestType,
    required String requesterName,
    String? submittedByName,
    String? recordId,
    String? parishId,
  }) async {
    final uid = _requireUid();
    final submitted = submittedByName?.trim() ?? '';
    await _db
        .collection('requests')
        .add({
          'request_type': requestType,
          'requester_name': requesterName,
          'certificate_for_name': requesterName,
          if (submitted.isNotEmpty) 'submitted_by_name': submitted,
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

  static String personOnCertificate(Map<String, dynamic> request) {
    return (request['certificate_for_name'] ?? request['requester_name'] ?? '')
        .toString()
        .trim();
  }

  static String submittedByName(Map<String, dynamic> request) {
    return (request['submitted_by_name'] ?? '').toString().trim();
  }

  static String certificateTypeLabel(String requestType) {
    switch (requestType.trim().toLowerCase()) {
      case 'baptism':
        return 'Baptism';
      case 'marriage':
        return 'Marriage';
      case 'confirmation':
        return 'Confirmation';
      case 'death':
      case 'funeral':
        return 'Death / Funeral';
      default:
        if (requestType.trim().isEmpty) return 'Certificate';
        return requestType[0].toUpperCase() +
            requestType.substring(1).toLowerCase();
    }
  }

  static ({String title, String body}) notificationForStatus({
    required String status,
    required String typeLabel,
    String requesterName = '',
  }) {
    final name = requesterName.trim();
    final greeting = name.isNotEmpty ? 'Hi $name, ' : '';

    switch (status.trim().toLowerCase()) {
      case 'approved':
        return (
          title: 'Certificate request approved',
          body:
              '${greeting}your $typeLabel certificate request has been approved. '
              'In about 5 minutes you may come to the parish office to receive '
              'your certificate, or open My Requests in the app for details.',
        );
      case 'rejected':
        return (
          title: 'Certificate request update',
          body:
              '${greeting}your $typeLabel certificate request was not approved. '
              'Please contact the parish office for assistance.',
        );
      case 'completed':
      case 'ready':
        return (
          title: 'Your certificate is ready',
          body:
              '${greeting}your $typeLabel certificate is ready for pickup. '
              'Please visit the parish office during office hours.',
        );
      default:
        return (
          title: 'Certificate request updated',
          body:
              '${greeting}your $typeLabel certificate request status is now: $status.',
        );
    }
  }

  Future<void> _notifyRequestStatusChange({
    required String userId,
    required String requestId,
    required String status,
    required String requestType,
    required String certificateForName,
    String? submittedByName,
  }) async {
    final typeLabel = certificateTypeLabel(requestType);
    final greetName = (submittedByName != null && submittedByName.isNotEmpty)
        ? submittedByName
        : certificateForName;
    final copy = notificationForStatus(
      status: status,
      typeLabel: typeLabel,
      requesterName: greetName,
    );
    try {
      await _notifications.createSystemNotification(
        title: copy.title,
        body: copy.body,
        userId: userId,
        type: 'request',
        route: '/user/requests/$requestId',
        resourceId: requestId,
      );
    } catch (_) {}
  }

  Future<void> updateStatus(
    String requestId, {
    required String status,
    bool? notificationSent,
    String? parishId,
  }) async {
    final canManage = await _canManageRequests();
    if (!canManage) {
      throw Exception('Staff access required');
    }

    final docRef = _db.collection('requests').doc(requestId);
    final before = await docRef.get().timeout(
      _timeout,
      onTimeout: () => throw TimeoutException('Load request timed out'),
    );
    final beforeData = before.data() ?? {};
    final previousStatus =
        (beforeData['status'] ?? 'pending').toString().trim().toLowerCase();
    final newStatus = status.trim().toLowerCase();
    final ownerUid = (beforeData['created_by_uid'] ?? '').toString();

    final patch = <String, dynamic>{
      'status': newStatus,
      'processed_at': FieldValue.serverTimestamp(),
      'processed_by': _requireUid(),
      'updated_at': FieldValue.serverTimestamp(),
    };
    if (parishId != null) {
      patch['parish_id'] = parishId;
    }

    final shouldNotify =
        ownerUid.isNotEmpty && newStatus != previousStatus;
    if (shouldNotify) {
      patch['notification_sent'] = true;
    } else if (notificationSent != null) {
      patch['notification_sent'] = notificationSent;
    }

    await docRef.set(patch, SetOptions(merge: true)).timeout(
      _timeout,
      onTimeout: () => throw TimeoutException('Update request timed out'),
    );

    if (shouldNotify) {
      final submitted = RequestsRepository.submittedByName(beforeData);
      await _notifyRequestStatusChange(
        userId: ownerUid,
        requestId: requestId,
        status: newStatus,
        requestType: (beforeData['request_type'] ?? 'certificate').toString(),
        certificateForName: personOnCertificate(beforeData),
        submittedByName: submitted.isNotEmpty ? submitted : null,
      );
    }
  }

  Future<void> delete(String requestId) async {
    final canManage = await _canManageRequests();
    if (!canManage) {
      throw Exception('Staff access required');
    }

    await _db
        .collection('requests')
        .doc(requestId)
        .delete()
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Delete request timed out'),
        );
  }
}
