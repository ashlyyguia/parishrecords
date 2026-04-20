import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FinancialReportsRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const Duration _timeout = Duration(seconds: 30);

  String _requireUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw Exception('Not authenticated');
    }
    return uid;
  }

  Future<Map<String, dynamic>> generate({
    required String template,
    required DateTime from,
    required DateTime to,
  }) async {
    _requireUid();

    // Generate report from Firestore data
    final snap = await _firestore
        .collection('donations')
        .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('created_at', isLessThanOrEqualTo: Timestamp.fromDate(to))
        .get()
        .timeout(_timeout);

    double total = 0;
    final byMethod = <String, double>{};
    final byCampaign = <String, double>{};

    for (final doc in snap.docs) {
      final data = doc.data();
      final amount = (data['amount'] as num?)?.toDouble() ?? 0;
      final method = data['method'] as String? ?? 'cash';
      final campaign = data['campaign'] as String? ?? 'General';

      total += amount;
      byMethod[method] = (byMethod[method] ?? 0) + amount;
      byCampaign[campaign] = (byCampaign[campaign] ?? 0) + amount;
    }

    return {
      'template': template,
      'from': from.toIso8601String(),
      'to': to.toIso8601String(),
      'total_amount': total,
      'donation_count': snap.docs.length,
      'by_method': byMethod,
      'by_campaign': byCampaign,
      'generated_at': DateTime.now().toIso8601String(),
    };
  }
}
