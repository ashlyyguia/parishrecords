import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/announcement.dart';
import '../../providers/user_providers.dart';
import '../../services/announcements_repository.dart';
import 'widgets/announcements_card.dart';
import 'widgets/dashboard_kpi_card.dart';
import 'widgets/quick_action_button.dart';
import 'widgets/recent_activities_table.dart';

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
        },
        child: dashAsync.when(
          data: (data) => _buildContent(context, data, ref),
          loading: () => const Center(child: CircularProgressIndicator()),
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

  Widget _buildContent(BuildContext context, Map<String, dynamic> data, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final requests = (data['requests'] as List?) ?? [];
    final sacraments = (data['sacraments'] as List?) ?? [];

    // Build recent activities list
    final List<Map<String, dynamic>> activities = [];
    for (var r in requests) {
      activities.add({
        'date': r['created_at']?.toString().substring(0, 10) ?? '—',
        'title': 'Request: ${r['request_type']?.toString().toUpperCase() ?? 'Certificate'}',
        'subtitle': 'ID: ${r['request_id'] ?? '-'}',
        'status': r['status'] ?? 'pending',
        'raw': r,
        'type': 'request'
      });
    }
    // Sort by date (naive string sort for now)
    activities.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));

    final isWide = MediaQuery.of(context).size.width >= 900;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KPI Cards
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
                    title: 'My Requests',
                    value: '${requests.length}',
                    icon: Icons.assignment_outlined,
                    color: Colors.orange,
                    onTap: () => context.go('/user/requests'),
                  ),
                  DashboardKpiCard(
                    title: 'Sacraments',
                    value: '${sacraments.length}',
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
                onPressed: () {
                  if (sacraments.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('You cannot request a certificate because there are no sacrament records linked to your account.'),
                      ),
                    );
                    return;
                  }
                  context.go('/records/certificate-request');
                },
                icon: Icons.add_circle_outline,
                label: 'Request Certificate',
                color: sacraments.isEmpty ? Colors.grey : colorScheme.primary,
              ),
              QuickActionButton(
                onPressed: () => context.go('/mass-time'),
                icon: Icons.schedule_outlined,
                label: 'View Mass Schedule',
                color: colorScheme.secondary,
                isOutlined: true,
              ),

              QuickActionButton(
                onPressed: () => context.go('/contact'),
                icon: Icons.mail_outline,
                label: 'Contact Parish',
                color: colorScheme.tertiary,
                isOutlined: true,
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Main Content Area (Table + Announcements)
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: _buildRecentActivitiesSection(textTheme, activities, context),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 1,
                  child: _buildAnnouncementsSection(textTheme, ref),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRecentActivitiesSection(textTheme, activities, context),
                const SizedBox(height: 32),
                _buildAnnouncementsSection(textTheme, ref),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildRecentActivitiesSection(
    TextTheme textTheme,
    List<Map<String, dynamic>> activities,
    BuildContext context,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Activities',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: RecentActivitiesTable(
            activities: activities.take(5).toList(),
            onRowTap: (activity) {
              if (activity['type'] == 'request') {
                final id = activity['raw']['request_id'];
                if (id != null) {
                  context.go('/user/requests/$id');
                }
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAnnouncementsSection(TextTheme textTheme, WidgetRef ref) {
    final announcementsAsync = ref.watch(_dashboardAnnouncementsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Announcements',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        announcementsAsync.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (e, st) => const Text('Could not load announcements.'),
          data: (items) {
            if (items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No active announcements at this time.',
                  style: textTheme.bodyMedium,
                ),
              );
            }
            return Column(
              children: items.take(3).map((a) => AnnouncementsCard(
                title: a.title,
                date: _formatDate(a.eventDateTime),
                onViewTap: () {},
              )).toList(),
            );
          },
        ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

final _dashboardAnnouncementsProvider = StreamProvider<List<Announcement>>((ref) {
  return AnnouncementsRepository().watchPublicActive();
});
