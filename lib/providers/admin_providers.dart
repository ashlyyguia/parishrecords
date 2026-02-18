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
