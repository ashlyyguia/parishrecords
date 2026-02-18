import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/requests_repository.dart';
import '../services/offline_cache.dart';

final requestsRepositoryProvider = Provider<RequestsRepository>((ref) {
  return RequestsRepository();
});

final certificateRequestsProvider = FutureProvider.family<
    List<Map<String, dynamic>>, int>((ref, limit) async {
  final repo = ref.watch(requestsRepositoryProvider);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  final key = uid == null ? null : 'requests_${uid}_$limit';

  List<Map<String, dynamic>>? cached;
  if (key != null) {
    final raw = await OfflineCache.readJson(key);
    if (raw is List) {
      cached = raw
          .whereType<Map>()
          .map((m) => m.cast<String, dynamic>())
          .toList();
    }
  }

  try {
    final rows = await repo.list(limit: limit);
    if (key != null) {
      await OfflineCache.writeJson(key, rows);
    }
    return rows;
  } catch (_) {
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    rethrow;
  }
});
