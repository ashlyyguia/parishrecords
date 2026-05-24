import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class UserRequestsRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const Duration _timeout = Duration(seconds: 20);
  static final _displayDateFormat = DateFormat('MMM d, yyyy • h:mm a');

  String _requireUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) throw Exception('Not authenticated');
    return uid;
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  String _normalizeStatus(dynamic raw) {
    final s = (raw ?? 'pending').toString().trim().toLowerCase();
    if (s.isEmpty) return 'pending';
    if (s == 'submitted') return 'pending';
    return s;
  }

  /// Groups statuses for user filter chips (pending / processing / completed).
  static String filterBucket(String status) {
    final s = status.trim().toLowerCase();
    if (s.isEmpty || s == 'pending' || s == 'submitted') return 'pending';
    if (s == 'completed' ||
        s == 'cancelled' ||
        s == 'canceled' ||
        s == 'rejected' ||
        s == 'ready') {
      return 'completed';
    }
    return 'processing';
  }

  static String statusLabel(String status) {
    final s = status.trim().toLowerCase();
    switch (s) {
      case 'pending':
      case 'submitted':
        return 'Pending';
      case 'approved':
        return 'Approved';
      case 'processing':
      case 'in_progress':
        return 'Processing';
      case 'completed':
        return 'Completed';
      case 'rejected':
        return 'Rejected';
      case 'cancelled':
      case 'canceled':
        return 'Cancelled';
      case 'ready':
        return 'Ready';
      default:
        if (s.isEmpty) return 'Pending';
        return s[0].toUpperCase() + s.substring(1);
    }
  }

  Map<String, dynamic> _normalizeRequest(
    String docId,
    Map<String, dynamic> data,
  ) {
    final dt = _parseDate(
      data['requested_at'] ?? data['created_at'] ?? data['createdAt'],
    );
    final status = _normalizeStatus(data['status']);

    final certFor = (data['certificate_for_name'] ?? data['requester_name'] ?? '')
        .toString();
    final submittedBy = (data['submitted_by_name'] ?? '').toString();

    return {
      ...data,
      'request_id': docId,
      'id': docId,
      'requester_name': certFor,
      'certificate_for_name': certFor,
      'submitted_by_name': submittedBy,
      'status': status,
      'requested_at': dt?.toIso8601String() ?? '',
      'requested_at_display': dt != null ? _displayDateFormat.format(dt) : '',
      'created_at': dt?.toIso8601String() ?? '',
    };
  }

  Future<List<Map<String, dynamic>>> listMyRequests({int limit = 50}) async {
    final uid = _requireUid();

    final snap = await _firestore
        .collection('requests')
        .where('created_by_uid', isEqualTo: uid)
        .get()
        .timeout(_timeout);

    final list = snap.docs
        .map((doc) => _normalizeRequest(doc.id, doc.data()))
        .toList();

    list.sort((a, b) {
      final dA = _parseDate(a['requested_at']);
      final dB = _parseDate(b['requested_at']);
      if (dA == null && dB == null) return 0;
      if (dA == null) return 1;
      if (dB == null) return -1;
      return dB.compareTo(dA);
    });

    return list.take(limit).toList();
  }

  Future<Map<String, dynamic>> getRequestDetail(String requestId) async {
    final doc = await _firestore
        .collection('requests')
        .doc(requestId)
        .get()
        .timeout(_timeout);

    if (!doc.exists) {
      throw Exception('Request not found');
    }

    return _normalizeRequest(doc.id, doc.data() ?? {});
  }

  Future<void> cancel(String requestId) async {
    _requireUid();

    await _firestore
        .collection('requests')
        .doc(requestId)
        .update({
          'status': 'cancelled',
          'cancelled_at': FieldValue.serverTimestamp(),
        })
        .timeout(_timeout);
  }

  Future<Map<String, dynamic>> createRequest(Map<String, dynamic> data) async {
    final uid = _requireUid();

    data['created_by_uid'] = uid;
    data['created_at'] = FieldValue.serverTimestamp();
    data['requested_at'] = FieldValue.serverTimestamp();
    data['status'] = 'pending';

    final docRef = await _firestore
        .collection('requests')
        .add(data)
        .timeout(_timeout);

    return {'request_id': docRef.id, ...data, 'status': 'pending'};
  }
}
