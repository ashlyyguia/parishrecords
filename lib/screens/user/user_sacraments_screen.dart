import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/user_providers.dart';
import '../../widgets/app_loading.dart';

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
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.0,
              ),
              itemCount: rows.length,
              itemBuilder: (context, i) =>
                  _buildSacramentCard(rows[i], theme, colorScheme, ref),
            ),
          );
        },
        loading: () => const AppLoading(message: 'Loading sacraments...'),
        error: (e, _) => Center(child: Text('Failed to load sacraments: $e')),
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
                'Your sacrament records will appear here once they are linked to your household.',
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

  Widget _buildSacramentCard(
    dynamic r,
    ThemeData theme,
    ColorScheme colorScheme,
    WidgetRef ref,
  ) {
    final title = (r['title'] ?? r['type'] ?? 'Record').toString();
    final date = (r['date'] ?? '').toString();
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
      child: InkWell(
        onTap: certUrl.isEmpty ? null : () => _openUrl(ref.context, certUrl),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(iconData, color: color, size: 28),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (date.isNotEmpty)
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 14,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              date,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (certUrl.isNotEmpty)
                FilledButton.tonal(
                  onPressed: () => _openUrl(ref.context, certUrl),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 36),
                  ),
                  child: const Text('View Certificate'),
                )
              else
                OutlinedButton(
                  onPressed: null,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 36),
                  ),
                  child: const Text('No Certificate'),
                ),
            ],
          ),
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
      case 'burial':
        return Icons.church_outlined;
      case 'communion':
        return Icons.restaurant_outlined;
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
      case 'burial':
        return Colors.purple;
      case 'communion':
        return Colors.amber;
      default:
        return Colors.teal;
    }
  }
}
