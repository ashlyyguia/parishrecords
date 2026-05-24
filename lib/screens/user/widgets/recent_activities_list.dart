import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/requests_repository.dart';
import '../../../services/user_requests_repository.dart';

/// Recent certificate-request activity cards for the parishioner dashboard.
class RecentActivitiesList extends StatelessWidget {
  final List<Map<String, dynamic>> activities;
  final VoidCallback? onViewAll;
  final void Function(Map<String, dynamic> activity)? onTap;

  const RecentActivitiesList({
    super.key,
    required this.activities,
    this.onViewAll,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (activities.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(
              Icons.history_rounded,
              size: 48,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'No recent activity yet',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Certificate requests you submit will appear here.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < activities.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              indent: 72,
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          _ActivityTile(
            activity: activities[i],
            onTap: onTap != null ? () => onTap!(activities[i]) : null,
          ),
        ],
        if (onViewAll != null) ...[
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
          TextButton.icon(
            onPressed: onViewAll,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('View all requests'),
          ),
        ],
      ],
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final Map<String, dynamic> activity;
  final VoidCallback? onTap;

  const _ActivityTile({required this.activity, this.onTap});

  IconData _iconForType(String type) {
    switch (type.toLowerCase()) {
      case 'baptism':
        return Icons.water_drop_outlined;
      case 'marriage':
        return Icons.favorite_outline;
      case 'confirmation':
        return Icons.verified_outlined;
      case 'death':
      case 'funeral':
        return Icons.church_outlined;
      default:
        return Icons.description_outlined;
    }
  }

  Color _iconColor(String type) {
    switch (type.toLowerCase()) {
      case 'baptism':
        return Colors.blue;
      case 'marriage':
        return Colors.pink;
      case 'confirmation':
        return Colors.orange;
      case 'death':
      case 'funeral':
        return Colors.purple;
      default:
        return Colors.teal;
    }
  }

  Color _statusColor(String status, ColorScheme colorScheme) {
    switch (UserRequestsRepository.filterBucket(status)) {
      case 'pending':
        return Colors.orange;
      case 'processing':
        return Colors.blue;
      case 'completed':
        return status.toLowerCase() == 'rejected'
            ? colorScheme.error
            : Colors.green;
      default:
        return colorScheme.primary;
    }
  }

  String _formatWhen(dynamic raw) {
    DateTime? dt;
    if (raw is DateTime) {
      dt = raw;
    } else {
      dt = DateTime.tryParse(raw?.toString() ?? '');
    }
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays < 7) return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    return DateFormat('MMM d, yyyy').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final raw = activity['raw'] as Map<String, dynamic>? ?? activity;
    final requestType = (raw['request_type'] ?? 'certificate').toString();
    final typeLabel = RequestsRepository.certificateTypeLabel(requestType);
    final personName = RequestsRepository.personOnCertificate(raw);
    final submittedBy = RequestsRepository.submittedByName(raw);
    final status = (raw['status'] ?? 'pending').toString();
    final statusLabel = UserRequestsRepository.statusLabel(status);
    final when = _formatWhen(
      raw['requested_at_display'] ??
          raw['requested_at'] ??
          raw['created_at'] ??
          activity['when'],
    );

    final iconColor = _iconColor(requestType);
    final statusColor = _statusColor(status, colorScheme);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_iconForType(requestType), color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$typeLabel certificate',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (when.isNotEmpty)
                          Text(
                            when,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (personName.isNotEmpty)
                      _DetailLine(
                        icon: Icons.badge_outlined,
                        label: 'For',
                        value: personName,
                        colorScheme: colorScheme,
                        textTheme: theme.textTheme,
                      ),
                    if (submittedBy.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _DetailLine(
                        icon: Icons.person_outline,
                        label: 'Requested by',
                        value: submittedBy,
                        colorScheme: colorScheme,
                        textTheme: theme.textTheme,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  statusLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme colorScheme;
  final TextTheme? textTheme;

  const _DetailLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.colorScheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: textTheme?.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: textTheme?.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
