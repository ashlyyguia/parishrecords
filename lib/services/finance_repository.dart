import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FinanceRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const Duration _timeout = Duration(seconds: 20);

  String _requireUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw Exception('Not authenticated');
    }
    return uid;
  }

  Future<Map<String, dynamic>> getOverview({int days = 30}) async {
    _requireUid();

    final since = DateTime.now().subtract(Duration(days: days));

    // Get donations summary
    final snap = await _firestore
        .collection('donations')
        .where('created_at', isGreaterThan: Timestamp.fromDate(since))
        .get()
        .timeout(_timeout);

    double total = 0;
    int count = 0;
    final byMethod = <String, double>{};

    for (final doc in snap.docs) {
      final data = doc.data();
      final amount = (data['amount'] as num?)?.toDouble() ?? 0;
      final method = data['method'] as String? ?? 'cash';

      total += amount;
      count++;
      byMethod[method] = (byMethod[method] ?? 0) + amount;
    }

    return {
      'total_amount': total,
      'total_count': count,
      'by_method': byMethod,
      'period_days': days,
      'generated_at': DateTime.now().toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> bankImport({
    required List<Map<String, dynamic>> rows,
  }) async {
    _requireUid();

    // Store bank import records
    final batch = _firestore.batch();
    final collection = _firestore.collection('bank_imports');

    for (final row in rows) {
      final doc = collection.doc();
      batch.set(doc, {
        ...row,
        'imported_at': FieldValue.serverTimestamp(),
        'imported_by': FirebaseAuth.instance.currentUser?.uid,
      });
    }

    await batch.commit().timeout(_timeout);

    return {'imported': rows.length, 'status': 'success'};
  }

  Future<Map<String, dynamic>> reconcile({
    required List<Map<String, dynamic>> matches,
  }) async {
    _requireUid();

    // Update reconciliation status
    final batch = _firestore.batch();

    for (final match in matches) {
      final donationId = match['donation_id'] as String?;
      if (donationId != null) {
        final doc = _firestore.collection('donations').doc(donationId);
        batch.update(doc, {
          'reconciled': true,
          'reconciled_at': FieldValue.serverTimestamp(),
          'reconciled_by': FirebaseAuth.instance.currentUser?.uid,
        });
      }
    }

    await batch.commit().timeout(_timeout);

    return {'reconciled': matches.length, 'status': 'success'};
  }
}
