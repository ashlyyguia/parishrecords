// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../providers/admin_analytics_provider.dart';
import '../../../providers/admin_providers.dart';
import '../../../providers/auth_provider.dart';

/// Enhanced Admin Dashboard with modern UX patterns and beautiful animations
class EnhancedAdminDashboardPage extends ConsumerStatefulWidget {
  const EnhancedAdminDashboardPage({super.key});

  @override
  ConsumerState<EnhancedAdminDashboardPage> createState() =>
      _EnhancedAdminDashboardPageState();
}

class _EnhancedAdminDashboardPageState
    extends ConsumerState<EnhancedAdminDashboardPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late List<Animation<double>> _cardAnimations;
  bool _showWelcome = true;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // Staggered animations for cards
    _cardAnimations = List.generate(6, (index) {
      final begin = (index * 0.1).clamp(0.0, 1.0);
      final end = (0.6 + index * 0.08).clamp(0.0, 1.0);
      return CurvedAnimation(
        parent: _animController,
        curve: Interval(begin, end, curve: Curves.easeOutCubic),
      );
    });

    _animController.forward();

    // Hide welcome banner after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showWelcome = false);
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final analyticsAsync = ref.watch(adminDashboardAnalyticsProvider);
    final authState = ref.watch(authProvider);
    final user = authState.user;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(adminDashboardAnalyticsProvider);
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Banner
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: _showWelcome && user != null
                  ? _buildWelcomeBanner(colorScheme, textTheme, user)
                  : const SizedBox.shrink(),
            ),

            const SizedBox(height: 24),

            // Stats Grid & Dashboard Content
            analyticsAsync.when(
              data: (analytics) => Column(
                children: [
                  _buildStatsGrid(analytics, colorScheme),
                  const SizedBox(height: 32),
                  _buildQuickActionsSection(colorScheme, textTheme),
                  const SizedBox(height: 32),
                  _buildActivityAndStatusSection(
                    colorScheme,
                    textTheme,
                    analytics,
                  ),
                  const SizedBox(height: 32),
                ],
              ),
              loading: () => Column(
                children: [
                  _buildStatsGridLoading(colorScheme),
                  const SizedBox(height: 32),
                  _buildQuickActionsSection(colorScheme, textTheme),
                  const SizedBox(height: 32),
                  _buildActivityAndStatusSection(
                    colorScheme,
                    textTheme,
                    AdminAnalytics(
                      households: 0,
                      parishioners: 0,
                      records: 0,
                      requests: 0,
                      donations: 0,
                      ocrPending: 0,
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
              error: (e, _) => Column(
                children: [
                  _buildStatsErrorBanner(colorScheme, e),
                  const SizedBox(height: 16),
                  _buildStatsGrid(
                    AdminAnalytics(
                      households: 0,
                      parishioners: 0,
                      records: 0,
                      requests: 0,
                      donations: 0,
                      ocrPending: 0,
                    ),
                    colorScheme,
                  ),
                  const SizedBox(height: 32),
                  _buildQuickActionsSection(colorScheme, textTheme),
                  const SizedBox(height: 32),
                  _buildActivityAndStatusSection(
                    colorScheme,
                    textTheme,
                    AdminAnalytics(
                      households: 0,
                      parishioners: 0,
                      records: 0,
                      requests: 0,
                      donations: 0,
                      ocrPending: 0,
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeBanner(
    ColorScheme colorScheme,
    TextTheme textTheme,
    dynamic user,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colorScheme.primary, colorScheme.tertiary],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.waving_hand_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back, ${user.displayName ?? user.email ?? 'Admin'}!',
                  style: textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Here\'s what\'s happening in your parish today.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _showWelcome = false),
            icon: const Icon(Icons.close, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(AdminAnalytics analytics, ColorScheme colorScheme) {
    // Note: Trend data should come from analytics API comparing current vs previous period
    final stats = [
      _StatItem(
        label: 'Households',
        value: analytics.households,
        icon: Icons.home_work_rounded,
        color: Colors.blue,
        route: '/admin/households',
        emptyMessage: 'No households yet',
      ),
      _StatItem(
        label: 'Sacrament Records',
        value: analytics.records,
        icon: Icons.church_rounded,
        color: Colors.purple,
        route: '/admin/records',
        emptyMessage: 'No records yet',
      ),
      _StatItem(
        label: 'Pending Requests',
        value: analytics.requests,
        icon: Icons.assignment_rounded,
        color: Colors.orange,
        route: '/admin/requests',
        emptyMessage: 'No pending requests',
      ),
      _StatItem(
        label: 'Donations',
        value: analytics.donations,
        icon: Icons.favorite_rounded,
        color: Colors.pink,
        route: '/admin/donations',
        emptyMessage: 'No donations yet',
      ),
      _StatItem(
        label: 'OCR Pending',
        value: analytics.ocrPending,
        icon: Icons.document_scanner_rounded,
        color: Colors.teal,
        route: '/admin/ocr',
        emptyMessage: 'No pending OCR jobs',
      ),
    ];

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: stats.asMap().entries.map((entry) {
        final index = entry.key;
        final stat = entry.value;

        return AnimatedBuilder(
          animation: _cardAnimations[index],
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, 30 * (1 - _cardAnimations[index].value)),
              child: Opacity(
                opacity: _cardAnimations[index].value,
                child: child,
              ),
            );
          },
          child: SizedBox(
            width: 280,
            child: _StatCard(stat: stat, onTap: () => context.go(stat.route)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStatsGridLoading(ColorScheme colorScheme) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: List.generate(6, (index) {
        return SizedBox(
          width: 280,
          child: Container(
            height: 140,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(child: CircularProgressIndicator()),
          ),
        );
      }),
    );
  }

  Widget _buildStatsErrorBanner(ColorScheme colorScheme, Object error) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Failed to load analytics: $error',
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
          ),
          FilledButton.icon(
            onPressed: () => ref.invalidate(adminDashboardAnalyticsProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsSection(
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final actions = [
      _QuickAction(
        label: 'Add User',
        icon: Icons.person_add_rounded,
        color: Colors.orange,
        route: '/admin/users',
      ),
      _QuickAction(
        label: 'Add Household',
        icon: Icons.home_work_rounded,
        color: Colors.teal,
        route: '/admin/households',
      ),
      _QuickAction(
        label: 'New Record',
        icon: Icons.add_box_rounded,
        color: Colors.purple,
        route: '/admin/records',
      ),
      _QuickAction(
        label: 'Add Record (OCR)',
        icon: Icons.document_scanner_rounded,
        color: Colors.cyan,
        route: '/admin/ocr/upload',
      ),
      _QuickAction(
        label: 'Announcement',
        icon: Icons.campaign_rounded,
        color: Colors.deepOrange,
        route: '/admin/announcements',
      ),
      _QuickAction(
        label: 'Donation',
        icon: Icons.favorite_rounded,
        color: Colors.red,
        route: '/admin/donations',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: actions.map((action) {
            return _QuickActionButton(
              action: action,
              onTap: () => context.go(action.route),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildRecentActivitySection(
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final recentActivityAsync = ref.watch(adminRecentActivityProvider(8));

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Activity',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: () => context.go('/admin/requests'),
                child: const Text('View All'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          recentActivityAsync.when(
            data: (activities) {
              if (activities.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No recent activity',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                );
              }
              return Column(
                children: activities.take(5).map((activity) {
                  final title = activity['title']?.toString() ?? 'Unknown';
                  final subtitle = activity['subtitle']?.toString() ?? '';
                  final iconName = activity['icon']?.toString() ?? 'info';
                  final category = activity['category']?.toString() ?? 'other';
                  final date = activity['date'] as DateTime?;
                  final timeAgo = date != null
                      ? _formatTimeAgo(date.toIso8601String())
                      : 'Unknown';

                  final (icon, color) = _getActivityIconAndColor(
                    iconName,
                    category,
                  );

                  return _buildActivityItem(
                    colorScheme,
                    title,
                    subtitle,
                    timeAgo,
                    icon,
                    color,
                  );
                }).toList(),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Failed to load activity',
                  style: TextStyle(color: colorScheme.error),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityAndStatusSection(
    ColorScheme colorScheme,
    TextTheme textTheme,
    AdminAnalytics analytics,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1100) {
          return Column(
            children: [
              _buildRecentActivitySection(colorScheme, textTheme),
              const SizedBox(height: 24),
              _buildSystemStatusSection(colorScheme, textTheme, analytics),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: _buildRecentActivitySection(colorScheme, textTheme),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: _buildSystemStatusSection(
                colorScheme,
                textTheme,
                analytics,
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatTimeAgo(String timestamp) {
    if (timestamp.isEmpty) return 'Unknown';
    try {
      final date = DateTime.parse(timestamp);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 30) return '${diff.inDays}d ago';
      return '${(diff.inDays / 30).floor()}mo ago';
    } catch (_) {
      return timestamp;
    }
  }

  (IconData, Color) _getActivityIconAndColor(String iconName, String category) {
    // Map icon names to icons and colors
    switch (iconName) {
      case 'water_drop':
        return (Icons.water_drop, Colors.purple);
      case 'favorite':
        return (Icons.favorite, Colors.pink);
      case 'check_circle':
        return (Icons.check_circle, Colors.teal);
      case 'church':
        return (Icons.church, Colors.indigo);
      case 'verified':
        return (Icons.verified, Colors.amber);
      case 'volunteer_activism':
        return (Icons.volunteer_activism, Colors.red);
      case 'home_work':
        return (Icons.home_work, Colors.blue);
      case 'person':
        return (Icons.person, Colors.cyan);
      case 'add_circle':
        return (Icons.add_circle, Colors.green);
      default:
        // Fallback based on category
        switch (category) {
          case 'record':
            return (Icons.description, Colors.blue);
          case 'request':
            return (Icons.assignment, Colors.orange);
          case 'donation':
            return (Icons.favorite, Colors.red);
          default:
            return (Icons.info, Colors.blueGrey);
        }
    }
  }

  Widget _buildActivityItem(
    ColorScheme colorScheme,
    String title,
    String subtitle,
    String time,
    IconData icon,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Text(
            time,
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemStatusSection(
    ColorScheme colorScheme,
    TextTheme textTheme,
    AdminAnalytics analytics,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'System Status',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          _buildStatusIndicator(
            'Database',
            'Connected',
            Icons.storage,
            Colors.green,
            colorScheme,
          ),
          const SizedBox(height: 16),
          _buildStatusIndicator(
            'Authentication',
            'Active',
            Icons.security,
            Colors.green,
            colorScheme,
          ),
          const SizedBox(height: 16),
          _buildStatusIndicator(
            'OCR Service',
            analytics.ocrPending > 0 ? 'Processing' : 'Ready',
            Icons.document_scanner,
            analytics.ocrPending > 0 ? Colors.orange : Colors.green,
            colorScheme,
          ),
          const SizedBox(height: 16),
          _buildStatusIndicator(
            'Email Service',
            'Configured',
            Icons.email,
            Colors.blue,
            colorScheme,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => context.go('/admin/system'),
            icon: const Icon(Icons.settings),
            label: const Text('System Settings'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(
    String label,
    String status,
    IconData icon,
    Color statusColor,
    ColorScheme colorScheme,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    status,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatItem {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final String route;
  final String emptyMessage;

  _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.route,
    required this.emptyMessage,
  });

  bool get isEmpty => value == 0;
}

class _StatCard extends StatelessWidget {
  final _StatItem stat;
  final VoidCallback onTap;

  const _StatCard({required this.stat, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.5),
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: stat.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(stat.icon, color: stat.color, size: 24),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                stat.value.toString(),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: stat.isEmpty
                      ? colorScheme.onSurface.withValues(alpha: 0.4)
                      : colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                stat.isEmpty ? stat.emptyMessage : stat.label,
                style: TextStyle(
                  color: stat.isEmpty
                      ? colorScheme.onSurface.withValues(alpha: 0.5)
                      : colorScheme.onSurfaceVariant,
                  fontSize: 14,
                  fontStyle: stat.isEmpty ? FontStyle.italic : FontStyle.normal,
                ),
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
  final Color color;
  final String route;

  _QuickAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.route,
  });
}

class _QuickActionButton extends StatelessWidget {
  final _QuickAction action;
  final VoidCallback onTap;

  const _QuickActionButton({required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: action.color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: action.color.withOpacity(0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, color: action.color, size: 20),
              const SizedBox(width: 8),
              Text(
                action.label,
                style: TextStyle(
                  color: action.color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
