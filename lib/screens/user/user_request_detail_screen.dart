import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/user_providers.dart';
import '../../services/requests_repository.dart';
import '../../services/user_requests_repository.dart';
import '../../widgets/app_loading.dart';

class UserRequestDetailScreen extends ConsumerWidget {
  final String requestId;
  const UserRequestDetailScreen({super.key, required this.requestId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final async = ref.watch(requestDetailProvider(requestId));

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Request Details'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(requestDetailProvider(requestId)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: async.when(
        data: (row) {
          final type = (row['request_type'] ?? 'certificate').toString();
          final status = (row['status'] ?? 'pending').toString();
          final statusLabel = UserRequestsRepository.statusLabel(status);
          final requestedAt =
              (row['requested_at_display'] ?? row['requested_at'] ?? '')
                  .toString();
          final timeline = row['timeline'] is List
              ? (row['timeline'] as List)
              : const [];

          final cancellable =
              status.toLowerCase() != 'ready' &&
              status.toLowerCase() != 'approved' &&
              status.toLowerCase() != 'cancelled';

          final typeLabel = RequestsRepository.certificateTypeLabel(type);
          final personName = (row['certificate_for_name'] ??
                  row['requester_name'] ??
                  '')
              .toString();
          final submittedBy = (row['submitted_by_name'] ?? '').toString();
          final statusMessage = _statusGuidance(
            status: status,
            typeLabel: typeLabel,
            requesterName: personName,
          );

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (statusMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    color: _statusBannerColor(status, colorScheme),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            status.toLowerCase() == 'rejected'
                                ? Icons.cancel_outlined
                                : status.toLowerCase() == 'approved'
                                ? Icons.check_circle_outline
                                : Icons.info_outline,
                            color: _statusBannerIconColor(status, colorScheme),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              statusMessage,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        type.toUpperCase(),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (personName.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Person on certificate: $personName',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (submittedBy.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Requested by: $submittedBy',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text('Tracking ID: $requestId'),
                      if (requestedAt.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Submitted: $requestedAt',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.info_outline, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Status: $statusLabel',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status Timeline',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (timeline.isEmpty)
                        Text(
                          'No timeline updates yet.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        )
                      else
                        Column(
                          children: [
                            for (int i = 0; i < timeline.length; i++)
                              _TimelineItem(
                                title:
                                    (timeline[i] is Map
                                            ? (timeline[i] as Map)['status']
                                            : 'update')
                                        .toString(),
                                subtitle:
                                    (timeline[i] is Map
                                            ? (timeline[i] as Map)['at']
                                            : null)
                                        ?.toString(),
                                isLast: i == timeline.length - 1,
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (cancellable)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                  ),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Cancel request?'),
                        content: const Text(
                          'This will mark your request as cancelled.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('No'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text('Yes, cancel'),
                          ),
                        ],
                      ),
                    );
                    if (ok != true) return;

                    try {
                      await ref
                          .read(userRequestsRepositoryProvider)
                          .cancel(requestId);
                      ref.invalidate(myRequestsProvider);
                      ref.invalidate(requestDetailProvider(requestId));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Request cancelled.')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Cancel failed: $e')),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel Request'),
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'This request can no longer be cancelled.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
        loading: () => const AppLoading(message: 'Loading request...'),
        error: (e, _) => Center(child: Text('Failed to load request: $e')),
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool isLast;

  const _TimelineItem({
    required this.title,
    required this.subtitle,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 34,
                color: colorScheme.outline.withValues(alpha: 0.4),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String? _statusGuidance({
  required String status,
  required String typeLabel,
  required String requesterName,
}) {
  final s = status.trim().toLowerCase();
  if (s == 'pending') {
    return 'Your request is being reviewed. You will receive a notification when it is approved or if the parish needs more information.';
  }
  if (s == 'approved' ||
      s == 'rejected' ||
      s == 'ready' ||
      s == 'completed') {
    return RequestsRepository.notificationForStatus(
      status: s,
      typeLabel: typeLabel,
      requesterName: requesterName,
    ).body;
  }
  return null;
}

Color _statusBannerColor(String status, ColorScheme colorScheme) {
  switch (status.trim().toLowerCase()) {
    case 'approved':
      return Colors.green.withValues(alpha: 0.12);
    case 'rejected':
      return colorScheme.errorContainer.withValues(alpha: 0.5);
    default:
      return colorScheme.primaryContainer.withValues(alpha: 0.4);
  }
}

Color _statusBannerIconColor(String status, ColorScheme colorScheme) {
  switch (status.trim().toLowerCase()) {
    case 'approved':
      return Colors.green.shade700;
    case 'rejected':
      return colorScheme.error;
    default:
      return colorScheme.primary;
  }
}
