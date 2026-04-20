import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/requests_repository.dart';

final requestsRepositoryProvider = Provider<RequestsRepository>((ref) {
  return RequestsRepository();
});

final certificateRequestsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, int>((ref, limit) async {
      final repo = ref.watch(requestsRepositoryProvider);
      try {
        final rows = await repo
            .list(limit: limit)
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                debugPrint('certificateRequestsProvider: Timeout after 10s');
                return <Map<String, dynamic>>[];
              },
            );
        return rows;
      } catch (_) {
        return <Map<String, dynamic>>[];
      }
    });
