import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/notification.dart';
import 'auth_provider.dart';

class NotificationsNotifier extends StateNotifier<List<LocalNotification>> {
  NotificationsNotifier({required bool isAdmin, required String? uid})
      : _isAdmin = isAdmin,
        _uid = uid,
        super(const []) {
    // Only start listening when signed in
    if (_uid == null) return;
    _sub = FirebaseFirestore.instance
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
      final list = snap.docs.map((d) {
        final m = d.data();
        return LocalNotification(
          id: d.id,
          title: (m['title'] ?? '').toString(),
          body: (m['body'] ?? '').toString(),
          createdAt: (m['createdAt'] is Timestamp)
              ? (m['createdAt'] as Timestamp).toDate()
              : DateTime.tryParse(m['createdAt']?.toString() ?? '') ?? DateTime.now(),
          read: m['read'] == true,
        );
      }).toList();
      state = list;
    });
  }

  final bool _isAdmin;
  final String? _uid;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  Future<void> markRead(String id, bool read) async {
    if (!_isAdmin) return; // Only admin can mutate notifications per rules
    await FirebaseFirestore.instance.collection('notifications').doc(id).set({'read': read}, SetOptions(merge: true));
  }

  Future<void> toggleRead(String id) async {
    if (!_isAdmin) return;
    final ref = FirebaseFirestore.instance.collection('notifications').doc(id);
    final snap = await ref.get();
    final current = snap.data();
    final newVal = !(current?['read'] == true);
    await ref.set({'read': newVal}, SetOptions(merge: true));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final notificationsProvider = StateNotifierProvider<NotificationsNotifier, List<LocalNotification>>((ref) {
  // Derive admin and uid from auth provider
  final auth = ref.watch(authProvider);
  final isAdmin = auth.user?.role == 'admin';
  final uid = auth.user?.id;
  return NotificationsNotifier(isAdmin: isAdmin, uid: uid);
});

// Derived provider for unread count (used for badges)
final unreadNotificationsCountProvider = Provider<int>((ref) {
  final list = ref.watch(notificationsProvider);
  return list.where((n) => !n.read).length;
});
