import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/notification.dart';
import '../services/notifications_repository.dart';
import '../services/offline_cache.dart';

/// Provides a singleton instance of [NotificationsRepository].
final notificationsRepositoryProvider = Provider<NotificationsRepository>((
  ref,
) {
  return NotificationsRepository();
});

/// Loads the latest notifications from the backend.
///
/// UI code can use this with `ref.watch(notificationsProvider)` and
/// handle `AsyncValue<List<LocalNotification>>` states.
final notificationsProvider = FutureProvider<List<LocalNotification>>((
  ref,
) async {
  final repo = ref.watch(notificationsRepositoryProvider);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  final key = uid == null ? null : 'notifications_$uid';

  List<LocalNotification>? cached;
  if (key != null) {
    final raw = await OfflineCache.readJson(key);
    if (raw is List) {
      cached = raw
          .whereType<Map>()
          .map((m) {
            final mm = m.cast<String, dynamic>();
            final id = (mm['id'] ?? '').toString();
            if (id.isEmpty) return null;
            return LocalNotification.fromMap(mm, id);
          })
          .whereType<LocalNotification>()
          .toList();
    }
  }

  try {
    final list = await repo.listStrict(limit: 100);
    if (key != null) {
      await OfflineCache.writeJson(
        key,
        list.map((n) => <String, dynamic>{'id': n.id, ...n.toMap()}).toList(),
      );
    }
    return list;
  } catch (_) {
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    rethrow;
  }
});

/// Derived provider that exposes the unread notifications count
/// based on the latest data from [notificationsProvider].
final unreadNotificationsCountProvider = FutureProvider<int>((ref) async {
  final list = await ref.watch(notificationsProvider.future);
  return list.where((n) => !n.read && !n.archived).length;
});

final unreadNotificationsCountStreamProvider = StreamProvider<int>((ref) {
  final repo = ref.watch(notificationsRepositoryProvider);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  final key = uid == null ? null : 'notifications_$uid';

  final stream = Stream.periodic(const Duration(seconds: 15))
      .asyncMap((_) async {
        try {
          final list = await repo.listStrict(limit: 100);
          if (key != null) {
            await OfflineCache.writeJson(
              key,
              list
                  .map((n) => <String, dynamic>{'id': n.id, ...n.toMap()})
                  .toList(),
            );
          }
          return list;
        } catch (_) {
          if (key == null) return const <LocalNotification>[];
          final raw = await OfflineCache.readJson(key);
          if (raw is! List) return const <LocalNotification>[];
          return raw
              .whereType<Map>()
              .map((m) {
                final mm = m.cast<String, dynamic>();
                final id = (mm['id'] ?? '').toString();
                if (id.isEmpty) return null;
                return LocalNotification.fromMap(mm, id);
              })
              .whereType<LocalNotification>()
              .toList();
        }
      })
      .map((list) => list.where((n) => !n.read && !n.archived).length)
      .distinct();
  return stream;
});
