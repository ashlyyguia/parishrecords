import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notification.dart';

// Notifications have been removed from the app. These providers remain
// only to satisfy imports in existing code and always expose empty data.

final notificationsProvider = Provider<List<LocalNotification>>(
  (ref) => const [],
);

final unreadNotificationsCountProvider = Provider<int>((ref) => 0);
