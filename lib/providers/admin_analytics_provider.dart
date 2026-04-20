import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Admin analytics data model
class AdminAnalytics {
  final int households;
  final int parishioners;
  final int records;
  final int requests;
  final int donations;
  final int ocrPending;

  AdminAnalytics({
    required this.households,
    required this.parishioners,
    required this.records,
    required this.requests,
    required this.donations,
    required this.ocrPending,
  });

  factory AdminAnalytics.fromCounts({
    required int households,
    required int parishioners,
    required int records,
    required int requests,
    required int donations,
    required int ocrPending,
  }) {
    return AdminAnalytics(
      households: households,
      parishioners: parishioners,
      records: records,
      requests: requests,
      donations: donations,
      ocrPending: ocrPending,
    );
  }
}

/// Provider for admin analytics
final adminAnalyticsProvider = FutureProvider<AdminAnalytics>((ref) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw Exception('Not authenticated');

  developer.log('[Analytics] Loading from Firestore', name: 'AdminAnalytics');

  final firestore = FirebaseFirestore.instance;

  // Get counts from Firestore
  final householdsSnap = await firestore.collection('households').count().get();
  final parishionersSnap = await firestore
      .collection('household_members')
      .count()
      .get();
  final requestsSnap = await firestore.collection('requests').count().get();
  final donationsSnap = await firestore.collection('donations').count().get();
  final ocrSnap = await firestore
      .collection('ocr_jobs')
      .where('status', isEqualTo: 'pending')
      .count()
      .get();

  // Get record counts from all collections
  int recordsCount = 0;
  final collections = [
    'baptism_records',
    'marriage_records',
    'confirmation_records',
    'funeral_records',
  ];
  for (final collection in collections) {
    try {
      final snap = await firestore.collection(collection).count().get();
      recordsCount += snap.count ?? 0;
    } catch (e) {
      // Ignore errors
    }
  }

  return AdminAnalytics.fromCounts(
    households: householdsSnap.count ?? 0,
    parishioners: parishionersSnap.count ?? 0,
    records: recordsCount,
    requests: requestsSnap.count ?? 0,
    donations: donationsSnap.count ?? 0,
    ocrPending: ocrSnap.count ?? 0,
  );
});
