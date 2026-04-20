import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserRequestsRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const Duration _timeout = Duration(seconds: 20);

  String _requireUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) throw Exception('Not authenticated');
    return uid;
  }

  Future<List<Map<String, dynamic>>> listMyRequests({int limit = 50}) async {
    final uid = _requireUid();

    final snap = await _firestore
        .collection('requests')
        .where('created_by_uid', isEqualTo: uid)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .get()
        .timeout(_timeout);

    return snap.docs.map((doc) {
      final data = doc.data();
      data['request_id'] = doc.id;
      return data;
    }).toList();
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

    final data = doc.data() ?? {};
    data['request_id'] = doc.id;
    return data;
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
    data['status'] = 'pending';

    final docRef = await _firestore
        .collection('requests')
        .add(data)
        .timeout(_timeout);

    return {'request_id': docRef.id, ...data};
  }
}
