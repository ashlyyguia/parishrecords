import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DonationsRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const Duration _timeout = Duration(seconds: 20);

  String _requireUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw Exception('Not authenticated');
    }
    return uid;
  }

  Future<List<Map<String, dynamic>>> list({int limit = 200}) async {
    _requireUid();

    final snap = await _firestore
        .collection('donations')
        .orderBy('created_at', descending: true)
        .limit(limit)
        .get()
        .timeout(
          _timeout,
          onTimeout: () =>
              throw TimeoutException('Donations request timed out'),
        );

    return snap.docs.map((doc) {
      final data = doc.data();
      data['donation_id'] = doc.id;
      return data;
    }).toList();
  }

  Future<bool> reconcile(String donationId, {bool? reconciled}) async {
    _requireUid();

    final data = <String, dynamic>{'updated_at': FieldValue.serverTimestamp()};

    if (reconciled != null) {
      data['reconciled'] = reconciled;
    }

    await _firestore
        .collection('donations')
        .doc(donationId)
        .update(data)
        .timeout(
          _timeout,
          onTimeout: () =>
              throw TimeoutException('Reconcile request timed out'),
        );

    return reconciled ?? true;
  }

  Future<String> create({
    required double amount,
    String method = 'cash',
    String? campaign,
    String? donorName,
    bool anonymous = false,
  }) async {
    final uid = _requireUid();

    final data = {
      'amount': amount,
      'method': method,
      'campaign': campaign,
      'donor_name': donorName,
      'anonymous': anonymous,
      'donor_id': uid,
      'reconciled': false,
      'created_at': FieldValue.serverTimestamp(),
    };

    final docRef = await _firestore
        .collection('donations')
        .add(data)
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Donation create timed out'),
        );

    return docRef.id;
  }

  Future<void> delete(String donationId) async {
    _requireUid();

    await _firestore
        .collection('donations')
        .doc(donationId)
        .delete()
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Delete donation timed out'),
        );
  }

  Stream<List<Map<String, dynamic>>> watch() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value([]);

    return _firestore
        .collection('donations')
        .orderBy('created_at', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) {
            final data = doc.data();
            data['donation_id'] = doc.id;
            return data;
          }).toList(),
        );
  }
}
