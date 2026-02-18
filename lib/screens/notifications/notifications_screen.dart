import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/notification_provider.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _toggleRead(WidgetRef ref, String id, bool currentRead) async {
    final repo = ref.read(notificationsRepositoryProvider);
    await repo.setRead(id, !currentRead);
    ref.invalidate(notificationsProvider);
    await ref.read(notificationsProvider.future);
  }

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(notificationsProvider);
    await ref.read(notificationsProvider.future);
  }

  Future<void> _markAllRead(WidgetRef ref) async {
    final current = await ref.read(notificationsProvider.future);
    if (current.isEmpty) return;
    final repo = ref.read(notificationsRepositoryProvider);
    final ids = current
        .where((n) => !n.read && !n.archived)
        .map((n) => n.id)
        .toList();
    if (ids.isNotEmpty) {
      await repo.bulkSetRead(ids, true);
    }
    ref.invalidate(notificationsProvider);
    await ref.read(notificationsProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final notificationsAsync = ref.watch(notificationsProvider);
    final unreadCount = notificationsAsync.maybeWhen(
      data: (rows) => rows.where((n) => !n.read && !n.archived).length,
      orElse: () => 0,
    );

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Notifications'),
            if (unreadCount > 0) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$unreadCount unread',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (unreadCount > 0)
            IconButton(
              tooltip: 'Mark all as read',
              icon: const Icon(Icons.mark_email_read_outlined),
              onPressed: () => _markAllRead(ref),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: notificationsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              _NotificationsErrorState(onRetry: () => _refresh(ref), error: e),
          data: (rows) {
            if (rows.isEmpty) {
              return const _NotificationsEmptyState();
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final n = rows[index];
                final title = n.title;
                final body = n.body;
                final read = n.read;
                final archived = n.archived;
                final createdAt = n.createdAt;

                return Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colorScheme.outline.withValues(alpha: 0.14),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (!read && !archived)
                              ? colorScheme.primary
                              : colorScheme.outline.withValues(alpha: 0.3),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    title.isEmpty ? 'Notification' : title,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: read
                                          ? FontWeight.w600
                                          : FontWeight.w800,
                                    ),
                                  ),
                                ),
                                if (archived) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colorScheme.secondary.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      'Archived',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: colorScheme.secondary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 6),
                            if (body.isNotEmpty)
                              Text(
                                body,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurface.withValues(
                                    alpha: 0.78,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Text(
                                  _formatTimestamp(createdAt),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  tooltip: read ? 'Mark unread' : 'Mark read',
                                  icon: Icon(
                                    read
                                        ? Icons.mark_email_unread_outlined
                                        : Icons.mark_email_read_outlined,
                                  ),
                                  onPressed: () => _toggleRead(ref, n.id, read),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _NotificationsEmptyState extends StatelessWidget {
  const _NotificationsEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                size: 44,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'No notifications yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Pull down to refresh.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationsErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  final Object? error;
  const _NotificationsErrorState({required this.onRetry, this.error});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colorScheme.error.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 44,
                color: colorScheme.error,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Failed to load notifications',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Please check your connection and try again.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Text(
                  'Details: $error',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatTimestamp(DateTime dt) {
  final local = dt.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  final y = local.year.toString();
  final m = two(local.month);
  final d = two(local.day);
  final h = two(local.hour);
  final min = two(local.minute);
  return '$y-$m-$d $h:$min';
}
