import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/staff_schedule_repository.dart';

final staffScheduleRepositoryProvider = Provider<StaffScheduleRepository>((
  ref,
) {
  return StaffScheduleRepository();
});

final staffTodayEventsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final repo = ref.watch(staffScheduleRepositoryProvider);
      try {
        final result = await repo.listTodayEvents().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            debugPrint('staffTodayEventsProvider: Timeout after 10s');
            return <Map<String, dynamic>>[];
          },
        );
        return result;
      } catch (e) {
        debugPrint('staffTodayEventsProvider error: $e');
        return <Map<String, dynamic>>[];
      }
    });
