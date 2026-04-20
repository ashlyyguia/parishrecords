import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserSacramentsRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const Duration _timeout = Duration(seconds: 20);

  String _requireUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) throw Exception('Not authenticated');
    return uid;
  }

  Future<List<Map<String, dynamic>>> listMine({int limit = 30}) async {
    final uid = _requireUid();
    final List<Map<String, dynamic>> results = [];

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
            .orderBy('created_at', descending: true)
            .limit(limit)
            .get()
            .timeout(_timeout);

        for (final doc in snap.docs) {
          final data = doc.data();
          data['id'] = doc.id;
          data['type'] = collection.replaceAll('_records', '');
          results.add(data);
        }
      } catch (e) {
        // Ignore errors for individual collections
      }
    }

    return results..sort((a, b) {
      final aDate = a['created_at'];
      final bDate = b['created_at'];
      if (aDate is Timestamp && bDate is Timestamp) {
        return bDate.compareTo(aDate);
      }
      return 0;
    });
  }

  Future<void> requestCorrection(
    String recordId, {
    required String message,
  }) async {
    final uid = _requireUid();

    await _firestore
        .collection('correction_tickets')
        .add({
          'record_id': recordId,
          'message': message,
          'created_by_uid': uid,
          'created_at': FieldValue.serverTimestamp(),
          'status': 'pending',
        })
        .timeout(_timeout);
  }
}
