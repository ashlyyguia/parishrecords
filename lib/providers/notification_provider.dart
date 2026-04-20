import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/notification.dart';
import '../services/notifications_repository.dart';

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
  return await repo.listStrict(limit: 100);
});

/// Derived provider that exposes the unread notifications count
/// based on the latest data from [notificationsProvider].
final unreadNotificationsCountProvider = FutureProvider<int>((ref) async {
  final list = await ref.watch(notificationsProvider.future);
  return list.where((n) => !n.read && !n.archived).length;
});

final unreadNotificationsCountStreamProvider = StreamProvider<int>((ref) {
  final repo = ref.watch(notificationsRepositoryProvider);
  return Stream.periodic(const Duration(seconds: 15))
      .asyncMap((_) => repo.listStrict(limit: 100))
      .map((list) => list.where((n) => !n.read && !n.archived).length)
      .distinct();
});
