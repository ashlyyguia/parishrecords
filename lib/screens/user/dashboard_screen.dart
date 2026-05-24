import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/user_providers.dart';
import 'widgets/dashboard_kpi_card.dart';
import 'widgets/quick_action_button.dart';
import 'widgets/recent_activities_list.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashAsync = ref.watch(myDashboardProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent, // Shell provides background
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myDashboardProvider);
          ref.invalidate(mySacramentsProvider);
        },
        child: dashAsync.when(
          data: (data) => _buildContent(context, data, ref),
          loading: () => _buildSkeletonContent(context),
          error: (e, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, color: colorScheme.error, size: 48),
                const SizedBox(height: 16),
                Text('Failed to load dashboard: $e'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(myDashboardProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    Map<String, dynamic> data,
    WidgetRef ref,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final requests = (data['requests'] as List?) ?? [];
    final members = (data['members'] as List?) ?? [];
    final sacramentsCount = data['sacraments_count'] is int
        ? data['sacraments_count'] as int
        : ((data['sacraments'] as List?) ?? []).length;
    final pendingRequests = requests
        .where((r) => r['status'] == 'pending')
        .length;

    final activities = _buildActivitiesFromRequests(requests);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KPI Cards (Analytics Section)
          Text(
            'Analytics Overview',
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth < 600 ? 2 : 4;
              return GridView.count(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.5,
                children: [
                  DashboardKpiCard(
                    title: 'Members',
                    value: '${members.length}',
                    icon: Icons.people_outline,
                    color: colorScheme.primary,
                    onTap: () => context.go('/user/household'),
                  ),
                  DashboardKpiCard(
                    title: 'Pending',
                    value: '$pendingRequests',
                    icon: Icons.assignment_late_outlined,
                    color: Colors.orange,
                    onTap: () => context.go('/user/requests'),
                  ),
                  DashboardKpiCard(
                    title: 'My Requests',
                    value: '${requests.length}',
                    icon: Icons.assignment_outlined,
                    color: Colors.blue,
                    onTap: () => context.go('/user/requests'),
                  ),
                  DashboardKpiCard(
                    title: 'Sacraments',
                    value: '$sacramentsCount',
                    icon: Icons.church_outlined,
                    color: Colors.indigo,
                    onTap: () => context.go('/user/sacraments'),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 32),

          // Quick Actions
          Text(
            'Quick Actions',
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              QuickActionButton(
                onPressed: () => context.go('/records/certificate-request?user=1'),
                icon: Icons.add_circle_outline,
                label: 'Request Certificate',
                color: colorScheme.primary,
              ),
              QuickActionButton(
                onPressed: () => context.go('/user/mass-schedule'),
                icon: Icons.schedule_outlined,
                label: 'Mass Schedule',
                color: colorScheme.secondary,
                isOutlined: true,
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Main Content Area
          _buildRecentActivitiesSection(textTheme, activities, context),
        ],
      ),
    );
  }

  static List<Map<String, dynamic>> _buildActivitiesFromRequests(
    List<dynamic> requests,
  ) {
    final activities = <Map<String, dynamic>>[];
    for (final raw in requests) {
      if (raw is! Map) continue;
      final r = Map<String, dynamic>.from(raw);
      activities.add({
        'raw': r,
        'type': 'request',
        'when': r['requested_at'],
      });
    }
    activities.sort((a, b) {
      final aWhen = (a['when'] ?? '').toString();
      final bWhen = (b['when'] ?? '').toString();
      return bWhen.compareTo(aWhen);
    });
    return activities;
  }

  Widget _buildRecentActivitiesSection(
    TextTheme textTheme,
    List<Map<String, dynamic>> activities,
    BuildContext context,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent activity',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (activities.isNotEmpty)
              TextButton(
                onPressed: () => context.go('/user/requests'),
                child: const Text('See all'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Your latest certificate requests',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: RecentActivitiesList(
            activities: activities.take(5).toList(),
            onViewAll: activities.isEmpty
                ? null
                : () => context.go('/user/requests'),
            onTap: (activity) {
              final raw = activity['raw'] as Map<String, dynamic>?;
              final id = raw?['request_id'] ?? raw?['id'];
              if (id != null && id.toString().isNotEmpty) {
                context.go('/user/requests/$id');
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    IconData icon,
    IconData activeIcon,
    String value,
    String label,
    Color color,
  ) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(height: 12),
        Text(
          value,
          style: textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildStatVerticalDivider(ColorScheme colorScheme) {
    return Container(
      height: 60,
      width: 1,
      color: colorScheme.outlineVariant.withValues(alpha: 0.3),
    );
  }

  Widget _buildSkeletonContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final shimmer = colorScheme.onSurface.withValues(alpha: 0.08);
    final shimmerDark = colorScheme.onSurface.withValues(alpha: 0.13);

    Widget box(double w, double h, {double radius = 8}) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: shimmer,
        borderRadius: BorderRadius.circular(radius),
      ),
    );

    Widget card({required Widget child}) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: child,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KPI skeleton row
          Row(
            children: List.generate(
              2,
              (i) => Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i == 0 ? 16 : 0),
                  height: 90,
                  decoration: BoxDecoration(
                    color: shimmer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Quick Actions skeleton
          box(130, 22, radius: 6),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: List.generate(
              3,
              (_) => Container(
                width: 140,
                height: 44,
                decoration: BoxDecoration(
                  color: shimmer,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Recent activities skeleton
          box(160, 22, radius: 6),
          const SizedBox(height: 16),
          card(
            child: Column(
              children: List.generate(
                4,
                (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: shimmerDark,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            box(double.infinity, 13),
                            const SizedBox(height: 6),
                            box(100, 11),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      box(60, 24, radius: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
