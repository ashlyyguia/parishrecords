import 'package:firebase_auth/firebase_auth.dart';
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

/// Unread count via repository so audience / role filtering stays consistent.
Future<int> _fetchUnreadCount() async {
  if (FirebaseAuth.instance.currentUser?.uid == null) return 0;
  try {
    final repo = NotificationsRepository();
    final list = await repo.list(limit: 50);
    return list.where((n) => !n.read && !n.archived).length;
  } catch (_) {
    return 0;
  }
}

/// Stream that polls unread notification count every 5 seconds.
/// Uses a lightweight Firestore query instead of the full listStrict.
final unreadNotificationsCountStreamProvider = StreamProvider<int>((ref) async* {
  // Emit initial value immediately
  yield await _fetchUnreadCount();

  // Poll every 5 seconds
  yield* Stream.periodic(const Duration(seconds: 5))
      .asyncMap((_) => _fetchUnreadCount())
      .distinct();
});
