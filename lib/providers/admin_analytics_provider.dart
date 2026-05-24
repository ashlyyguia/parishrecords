import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

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

  Map<String, dynamic> toJson() {
    return {
      'households': households,
      'parishioners': parishioners,
      'records': records,
      'requests': requests,
      'donations': donations,
      'ocrPending': ocrPending,
    };
  }

  factory AdminAnalytics.fromJson(Map<String, dynamic> json) {
    return AdminAnalytics(
      households: (json['households'] as num?)?.toInt() ?? 0,
      parishioners: (json['parishioners'] as num?)?.toInt() ?? 0,
      records: (json['records'] as num?)?.toInt() ?? 0,
      requests: (json['requests'] as num?)?.toInt() ?? 0,
      donations: (json['donations'] as num?)?.toInt() ?? 0,
      ocrPending: (json['ocrPending'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Helper to safely get count with fallback to simple count if filtered query fails
Future<int> _safeCount(
  FirebaseFirestore firestore,
  String collection, {
  Map<String, dynamic>? whereEqualTo,
}) async {
  try {
    Query query = firestore.collection(collection);
    if (whereEqualTo != null) {
      whereEqualTo.forEach((field, value) {
        query = query.where(field, isEqualTo: value);
      });
    }
    final snap = await query.count().get();
    return snap.count ?? 0;
  } catch (e) {
    developer.log(
      'Count query failed for $collection (filtered: $whereEqualTo), falling back to simple count: $e',
      name: 'AdminAnalytics',
    );
    // Fallback: try simple count without filters
    try {
      final snap = await firestore.collection(collection).count().get();
      return snap.count ?? 0;
    } catch (e2) {
      developer.log(
        'Simple count also failed for $collection: $e2',
        name: 'AdminAnalytics',
      );
      // Avoid full collection scans (slow/expensive). Return 0 if counts fail.
      return 0;
    }
  }
}

Future<AdminAnalytics> _getCounts(FirebaseFirestore firestore) async {
  // Run counts in parallel to minimize startup latency.
  final householdsFuture = _safeCount(
    firestore,
    'households',
    whereEqualTo: {'isArchived': false},
  );
  final parishionersFuture = _safeCount(
    firestore,
    'household_members',
    whereEqualTo: {'isActive': true},
  );
  final requestsFuture = _safeCount(
    firestore,
    'requests',
    whereEqualTo: {'status': 'pending'},
  );
  final donationsFuture = _safeCount(firestore, 'donations');
  final ocrPendingFuture = _safeCount(
    firestore,
    'ocr_jobs',
    whereEqualTo: {'status': 'pending'},
  );

  final recordCollections = [
    'baptism_records',
    'marriage_records',
    'confirmation_records',
    'funeral_records',
  ];

  final recordCountFutures = recordCollections
      .map((collection) => _safeCount(firestore, collection))
      .toList();

  final results = await Future.wait<int>([
    householdsFuture,
    parishionersFuture,
    requestsFuture,
    donationsFuture,
    ocrPendingFuture,
    ...recordCountFutures,
  ]);

  final householdsCount = results[0];
  final parishionersCount = results[1];
  final requestsCount = results[2];
  final donationsCount = results[3];
  final ocrPendingCount = results[4];

  final recordsCount = results
      .sublist(5)
      .fold<int>(0, (sum, value) => sum + value);

  return AdminAnalytics.fromCounts(
    households: householdsCount,
    parishioners: parishionersCount,
    records: recordsCount,
    requests: requestsCount,
    donations: donationsCount,
    ocrPending: ocrPendingCount,
  );
}

AdminAnalytics? _cachedAdminAnalytics;
DateTime? _cachedAdminAnalyticsAt;

const String _adminAnalyticsHiveBox = 'admin_analytics_cache';
const String _adminAnalyticsHiveKey = 'dashboard_counts';

/// Provider for admin analytics
final adminDashboardAnalyticsProvider = StreamProvider<AdminAnalytics>((
  ref,
) async* {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw Exception('Not authenticated');

  final firestore = FirebaseFirestore.instance;

  try {
    final box = Hive.isBoxOpen(_adminAnalyticsHiveBox)
        ? Hive.box(_adminAnalyticsHiveBox)
        : await Hive.openBox(_adminAnalyticsHiveBox);

    final cachedMap = box.get(_adminAnalyticsHiveKey);
    if (cachedMap is Map) {
      final cachedData = cachedMap.cast<String, dynamic>();
      final cachedAtIso = cachedData['cachedAt']?.toString();
      final payload = cachedData['data'];
      final cachedAt = cachedAtIso == null
          ? null
          : DateTime.tryParse(cachedAtIso);
      if (payload is Map && cachedAt != null) {
        final a = AdminAnalytics.fromJson(payload.cast<String, dynamic>());
        _cachedAdminAnalytics = a;
        _cachedAdminAnalyticsAt = cachedAt;
      }
    }
  } catch (_) {}

  // Emit cached counts immediately (if available) to speed up initial paint.
  final cached = _cachedAdminAnalytics;
  final cachedAt = _cachedAdminAnalyticsAt;
  if (cached != null && cachedAt != null) {
    yield cached;
  }

  final initial = await _getCounts(firestore);
  _cachedAdminAnalytics = initial;
  _cachedAdminAnalyticsAt = DateTime.now();

  try {
    final box = Hive.isBoxOpen(_adminAnalyticsHiveBox)
        ? Hive.box(_adminAnalyticsHiveBox)
        : await Hive.openBox(_adminAnalyticsHiveBox);
    await box.put(_adminAnalyticsHiveKey, {
      'cachedAt': _cachedAdminAnalyticsAt!.toIso8601String(),
      'data': initial.toJson(),
    });
  } catch (_) {}

  yield initial;

  // Poll less frequently to reduce query load and contention during startup.
  yield* Stream.periodic(const Duration(seconds: 30)).asyncMap((_) async {
    final fresh = await _getCounts(firestore);
    _cachedAdminAnalytics = fresh;
    _cachedAdminAnalyticsAt = DateTime.now();

    try {
      final box = Hive.isBoxOpen(_adminAnalyticsHiveBox)
          ? Hive.box(_adminAnalyticsHiveBox)
          : await Hive.openBox(_adminAnalyticsHiveBox);
      await box.put(_adminAnalyticsHiveKey, {
        'cachedAt': _cachedAdminAnalyticsAt!.toIso8601String(),
        'data': fresh.toJson(),
      });
    } catch (_) {}

    return fresh;
  });
});
