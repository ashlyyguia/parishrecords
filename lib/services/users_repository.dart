import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UsersRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const Duration _timeout = Duration(seconds: 20);

  String _requireUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw Exception('Not authenticated');
    }
    return uid;
  }

  Future<List<Map<String, dynamic>>> list({
    String? role,
    int limit = 100,
  }) async {
    _requireUid();

    Query<Map<String, dynamic>> query = _firestore
        .collection('users')
        .limit(limit);

    if (role != null && role != 'all') {
      query = query.where('role', isEqualTo: role);
    }

    final snap = await query.get().timeout(
      _timeout,
      onTimeout: () => throw TimeoutException('Users list timed out'),
    );

    return snap.docs.map((doc) {
      final data = doc.data();
      data['uid'] = doc.id;
      return data;
    }).toList();
  }

  Future<void> delete(String userId) async {
    _requireUid();

    await _firestore
        .collection('users')
        .doc(userId)
        .delete()
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Delete user timed out'),
        );
  }

  Future<void> updateRole(String userId, String role) async {
    _requireUid();

    await _firestore
        .collection('users')
        .doc(userId)
        .update({'role': role, 'updatedAt': FieldValue.serverTimestamp()})
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Update role timed out'),
        );
  }

  Stream<List<Map<String, dynamic>>> watch() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value([]);

    return _firestore
        .collection('users')
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) {
            final data = doc.data();
            data['uid'] = doc.id;
            return data;
          }).toList(),
        );
  }
}
