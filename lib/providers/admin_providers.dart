import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/admin_repository.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository();
});

final recordHistoryProvider = FutureProvider.family
    .autoDispose<List<Map<String, dynamic>>, String>((ref, recordId) async {
      final repo = ref.read(adminRepositoryProvider);
      return repo.getRecordHistory(recordId);
    });

final adminAnalyticsProvider = FutureProvider.family
    .autoDispose<List<Map<String, dynamic>>, int>((ref, days) async {
      final repo = ref.read(adminRepositoryProvider);
      return repo.getAnalytics(days: days);
    });

final adminSummaryProvider = FutureProvider.family
    .autoDispose<Map<String, dynamic>, int>((ref, days) async {
      final repo = ref.read(adminRepositoryProvider);
      return repo.getSummary(days: days);
    });

final adminRecentLogsProvider = FutureProvider.family
    .autoDispose<List<Map<String, dynamic>>, int>((ref, limit) async {
      final repo = ref.read(adminRepositoryProvider);
      return repo.getLogs(limit: limit, days: 30);
    });

/// Recent parish activity (records, requests, donations) - NOT audit logs
final adminRecentActivityProvider = FutureProvider.family
    .autoDispose<List<Map<String, dynamic>>, int>((ref, limit) async {
      final repo = ref.read(adminRepositoryProvider);
      return repo.getRecentActivity(limit: limit);
    });
