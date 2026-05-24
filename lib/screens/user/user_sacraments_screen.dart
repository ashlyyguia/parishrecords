import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/user_providers.dart';

class UserSacramentsScreen extends ConsumerWidget {
  const UserSacramentsScreen({super.key});

  Future<void> _openUrl(BuildContext context, String url) async {
    try {
      final uri = Uri.parse(url);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open certificate link')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Open failed: $e')));
      }
    }
  }

  void _showDetail(BuildContext context, Map<String, dynamic> r) {
    final label = (r['sacrament_label'] ?? r['type'] ?? 'Sacrament').toString();
    final title = (r['title'] ?? 'Record').toString();
    final date = (r['date'] ?? '').toString();
    final member = (r['member_name'] ?? '').toString();
    final parish = (r['parish'] ?? '').toString();
    final status = (r['certificate_status'] ?? '').toString();
    final recordId = (r['record_id'] ?? r['id'] ?? '').toString();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow(ctx, 'Name', title),
              if (member.isNotEmpty) _detailRow(ctx, 'Household member', member),
              if (date.isNotEmpty) _detailRow(ctx, 'Sacrament date', date),
              if (parish.isNotEmpty) _detailRow(ctx, 'Parish / source', parish),
              if (status.isNotEmpty) _detailRow(ctx, 'Certificate status', status),
              if (recordId.isNotEmpty) _detailRow(ctx, 'Record ID', recordId),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final async = ref.watch(mySacramentsProvider);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('My Sacraments'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(mySacramentsProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: async.when(
        data: (rows) {
          if (rows.isEmpty) {
            return _buildEmptyState(theme, colorScheme);
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(mySacramentsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) =>
                  _buildSacramentTile(rows[i], theme, colorScheme, context),
            ),
          );
        },
        loading: () => _buildSkeletonList(colorScheme),
        error: (e, _) => Center(child: Text('Failed to load sacraments: $e')),
      ),
    );
  }

  Widget _buildSkeletonList(ColorScheme colorScheme) {
    final shimmer = colorScheme.onSurface.withValues(alpha: 0.08);
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => Container(
        height: 100,
        decoration: BoxDecoration(
          color: shimmer,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.church_outlined,
                size: 64,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'No sacrament records',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sacrament records appear here after you add a household member in My Profile and a matching parish record is linked.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSacramentTile(
    Map<String, dynamic> r,
    ThemeData theme,
    ColorScheme colorScheme,
    BuildContext context,
  ) {
    final title = (r['title'] ?? 'Record').toString();
    final date = (r['date'] ?? '').toString();
    final member = (r['member_name'] ?? '').toString();
    final label = (r['sacrament_label'] ?? r['type'] ?? 'Sacrament').toString();
    final certUrl = (r['certificate_url'] ?? '').toString();
    final sacramentType = (r['sacrament_type'] ?? r['type'] ?? 'record')
        .toString()
        .toLowerCase();

    final iconData = _getSacramentIcon(sacramentType);
    final color = _getSacramentColor(sacramentType);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(iconData, color: color, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (member.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Member: $member',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (date.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          date,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _showDetail(context, r),
                        icon: const Icon(Icons.info_outline, size: 18),
                        label: const Text('View details'),
                      ),
                      if (certUrl.isNotEmpty)
                        FilledButton.tonalIcon(
                          onPressed: () => _openUrl(context, certUrl),
                          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                          label: const Text('Certificate'),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: () {
                            context.push(
                              '/records/certificate-request?user=1',
                            );
                          },
                          icon: const Icon(Icons.description_outlined, size: 18),
                          label: const Text('Request certificate'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getSacramentIcon(String type) {
    switch (type) {
      case 'baptism':
        return Icons.water_drop_outlined;
      case 'confirmation':
        return Icons.local_fire_department_outlined;
      case 'marriage':
        return Icons.favorite_outline;
      case 'death':
      case 'funeral':
      case 'burial':
        return Icons.church_outlined;
      default:
        return Icons.description_outlined;
    }
  }

  Color _getSacramentColor(String type) {
    switch (type) {
      case 'baptism':
        return Colors.blue;
      case 'confirmation':
        return Colors.orange;
      case 'marriage':
        return Colors.pink;
      case 'death':
      case 'funeral':
      case 'burial':
        return Colors.purple;
      default:
        return Colors.teal;
    }
  }
}
