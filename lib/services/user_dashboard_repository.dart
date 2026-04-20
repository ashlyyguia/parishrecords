import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserDashboardRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const Duration _timeout = Duration(seconds: 20);

  String _requireUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) throw Exception('Not authenticated');
    return uid;
  }

  Future<Map<String, dynamic>> getMyDashboard() async {
    final uid = _requireUid();

    // Get user stats from Firestore
    final userDoc = await _firestore
        .collection('users')
        .doc(uid)
        .get()
        .timeout(_timeout);
    final userData = userDoc.data() ?? {};

    // Get user's recent records count
    int recordsCount = 0;
    final collections = [
      'baptism_records',
      'marriage_records',
      'confirmation_records',
      'funeral_records',
    ];

    for (final collection in collections) {
      try {
        final snap = await _firestore
            .collection(collection)
            .where('created_by_uid', isEqualTo: uid)
            .count()
            .get();
        recordsCount += snap.count ?? 0;
      } catch (e) {
        // Ignore errors
      }
    }

    // Get recent requests
    final requestsSnap = await _firestore
        .collection('requests')
        .where('created_by_uid', isEqualTo: uid)
        .orderBy('created_at', descending: true)
        .limit(5)
        .get()
        .timeout(_timeout);

    return {
      'user': userData,
      'records_count': recordsCount,
      'recent_requests': requestsSnap.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList(),
      'generated_at': DateTime.now().toIso8601String(),
    };
  }
}
