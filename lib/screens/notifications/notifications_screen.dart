import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/notification_provider.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifs = ref.watch(notificationsProvider);
    final df = DateFormat.yMMMd().add_jm();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Mark all as read',
            onPressed: () async {
              for (final n in notifs.where((n) => !n.read)) {
                await ref.read(notificationsProvider.notifier).markRead(n.id, true);
              }
            },
            icon: const Icon(Icons.done_all),
          )
        ],
      ),
      body: notifs.isEmpty
          ? const Center(child: Text('No notifications'))
          : ListView.separated(
              padding: const EdgeInsets.all(8),
              itemBuilder: (c, i) {
                final n = notifs[i];
                return ListTile(
                  leading: Icon(n.read ? Icons.notifications : Icons.notifications_active_outlined,
                      color: n.read ? Colors.grey : Theme.of(context).colorScheme.primary),
                  title: Text(n.title, style: TextStyle(fontWeight: n.read ? FontWeight.normal : FontWeight.w600)),
                  subtitle: Text('${df.format(n.createdAt)}\n${n.body}'),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: Icon(n.read ? Icons.mark_email_unread : Icons.mark_email_read_outlined),
                    tooltip: n.read ? 'Mark as unread' : 'Mark as read',
                    onPressed: () => ref.read(notificationsProvider.notifier).toggleRead(n.id),
                  ),
                );
              },
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemCount: notifs.length,
            ),
    );
  }
}
