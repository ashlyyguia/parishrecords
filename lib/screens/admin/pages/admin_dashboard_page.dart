import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../providers/admin_analytics_provider.dart';

/// Enhanced Admin Dashboard with comprehensive overview
class AdminDashboardPage extends ConsumerStatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  ConsumerState<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends ConsumerState<AdminDashboardPage> {
  int _selectedTimeRange = 0; // 0: Today, 1: Week, 2: Month, 3: Year

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final analyticsAsync = ref.watch(adminAnalyticsProvider);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          // Time range selector
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Today')),
              ButtonSegment(value: 1, label: Text('Week')),
              ButtonSegment(value: 2, label: Text('Month')),
              ButtonSegment(value: 3, label: Text('Year')),
            ],
            selected: {_selectedTimeRange},
            onSelectionChanged: (v) =>
                setState(() => _selectedTimeRange = v.first),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: analyticsAsync.when(
        data: (analytics) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stats Cards Row with real data
              _buildStatsCards(analytics),
              const SizedBox(height: 24),

              // Charts Section
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Main Chart
                  Expanded(flex: 2, child: _buildMainChartCard()),
                  const SizedBox(width: 16),
                  // Activity Feed
                  Expanded(child: _buildRecentActivityCard()),
                ],
              ),
              const SizedBox(height: 24),

              // Pending Tasks & Quick Actions
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildPendingTasksCard(analytics)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildQuickActionsCard()),
                ],
              ),
              const SizedBox(height: 24),

              // Sacrament Distribution & Top Barangays
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildSacramentDistributionCard()),
                  const SizedBox(width: 16),
                  Expanded(child: _buildTopBarangaysCard()),
                ],
              ),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'Failed to load analytics',
                style: theme.textTheme.titleMedium,
              ),
              Text(
                e.toString(),
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsCards(AdminAnalytics analytics) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 800;

        final cards = [
          _StatCard(
            title: 'Households',
            value: analytics.households.toString(),
            icon: Icons.home,
            color: Colors.blue,
            onTap: () => context.go('/admin/households'),
          ),
          _StatCard(
            title: 'Parishioners',
            value: analytics.parishioners.toString(),
            icon: Icons.people,
            color: Colors.green,
            onTap: () => context.go('/admin/parishioners'),
          ),
          _StatCard(
            title: 'Sacrament Records',
            value: analytics.records.toString(),
            icon: Icons.church,
            color: Colors.purple,
            onTap: () => context.go('/admin/records'),
          ),
          _StatCard(
            title: 'Certificate Requests',
            value: analytics.requests.toString(),
            icon: Icons.assignment,
            color: Colors.orange,
            onTap: () => context.go('/admin/requests'),
          ),
          _StatCard(
            title: 'Donations',
            value: analytics.donations.toString(),
            icon: Icons.volunteer_activism,
            color: Colors.teal,
            onTap: () => context.go('/admin/finance'),
          ),
          _StatCard(
            title: 'OCR Pending',
            value: analytics.ocrPending.toString(),
            icon: Icons.document_scanner,
            color: Colors.red,
            onTap: () => context.go('/admin/ocr'),
          ),
        ];

        if (isNarrow) {
          return Column(
            children: cards
                .map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: c,
                  ),
                )
                .toList(),
          );
        }

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: cards
              .map(
                (c) =>
                    SizedBox(width: (constraints.maxWidth - 80) / 6, child: c),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildMainChartCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Sacrament Activity',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                DropdownButton<String>(
                  value: 'All Sacraments',
                  items: const [
                    DropdownMenuItem(
                      value: 'All Sacraments',
                      child: Text('All Sacraments'),
                    ),
                    DropdownMenuItem(value: 'Baptism', child: Text('Baptism')),
                    DropdownMenuItem(
                      value: 'Confirmation',
                      child: Text('Confirmation'),
                    ),
                    DropdownMenuItem(
                      value: 'Marriage',
                      child: Text('Marriage'),
                    ),
                  ],
                  onChanged: (v) {},
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 300,
              child: Center(
                child: Text(
                  'No data available',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivityCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Activity',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                TextButton(
                  onPressed: () => context.go('/admin/audit'),
                  child: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  'No activity yet',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingTasksCard(AdminAnalytics analytics) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pending Tasks',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (analytics.ocrPending > 0 || analytics.requests > 0)
              Column(
                children: [
                  if (analytics.ocrPending > 0)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: Colors.red.withValues(alpha: 0.1),
                        child: const Icon(Icons.task, color: Colors.red),
                      ),
                      title: const Text('Verify OCR Results'),
                      subtitle: Text('${analytics.ocrPending} records pending'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.go('/admin/ocr'),
                    ),
                  if (analytics.requests > 0)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: Colors.orange.withValues(alpha: 0.1),
                        child: const Icon(Icons.task, color: Colors.orange),
                      ),
                      title: const Text('Process Certificate Requests'),
                      subtitle: Text('${analytics.requests} requests'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.go('/admin/requests'),
                    ),
                ],
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Text(
                    'No pending tasks',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsCard() {
    final actions = [
      _QuickAction(
        'Add Household',
        Icons.home,
        '/admin/households',
        Colors.blue,
      ),
      _QuickAction(
        'New Sacrament',
        Icons.church,
        '/admin/records',
        Colors.purple,
      ),
      _QuickAction(
        'Create Event',
        Icons.event,
        '/admin/announcements',
        Colors.orange,
      ),
      _QuickAction(
        'Post Announcement',
        Icons.campaign,
        '/admin/announcements',
        Colors.red,
      ),
      _QuickAction(
        'Generate Report',
        Icons.assessment,
        '/admin/reports',
        Colors.green,
      ),
      _QuickAction(
        'System Settings',
        Icons.settings,
        '/admin/settings',
        Colors.grey,
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: actions
                  .map(
                    (a) => ActionChip(
                      avatar: Icon(a.icon, size: 18, color: a.color),
                      label: Text(a.label),
                      onPressed: () => context.go(a.route),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSacramentDistributionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sacrament Distribution',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: Center(
                child: Text(
                  'No data available',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBarangaysCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Top Barangays',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  'No data available',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Data classes
class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                title,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction {
  final String label;
  final IconData icon;
  final String route;
  final Color color;

  _QuickAction(this.label, this.icon, this.route, this.color);
}
