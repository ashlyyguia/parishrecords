import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserProfileRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const Duration _timeout = Duration(seconds: 20);

  String _requireUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) throw Exception('Not authenticated');
    return uid;
  }

  Future<Map<String, dynamic>> getMyProfile() async {
    final uid = _requireUid();

    final doc = await _firestore
        .collection('users')
        .doc(uid)
        .get()
        .timeout(_timeout);

    if (!doc.exists) {
      throw Exception('Profile not found');
    }

    final data = doc.data() ?? {};
    data['uid'] = doc.id;
    return data;
  }

  Future<void> updateMyProfile(Map<String, dynamic> patch) async {
    final uid = _requireUid();

    // Remove sensitive fields that shouldn't be updated directly
    patch.remove('uid');
    patch.remove('role');
    patch.remove('created_at');

    patch['updated_at'] = FieldValue.serverTimestamp();

    await _firestore
        .collection('users')
        .doc(uid)
        .update(patch)
        .timeout(_timeout);
  }

  Future<Map<String, dynamic>> exportMyData() async {
    final uid = _requireUid();

    // Gather all user data
    final userDoc = await _firestore.collection('users').doc(uid).get();
    final userData = userDoc.data() ?? {};

    // Get user's records from all collections
    final records = <Map<String, dynamic>>[];
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
            .get();
        for (final doc in snap.docs) {
          final data = doc.data();
          data['id'] = doc.id;
          data['type'] = collection.replaceAll('_records', '');
          records.add(data);
        }
      } catch (e) {
        // Ignore errors
      }
    }

    return {
      'user': userData,
      'records': records,
      'exported_at': DateTime.now().toIso8601String(),
    };
  }
}
