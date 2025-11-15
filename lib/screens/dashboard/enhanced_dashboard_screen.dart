import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../models/record.dart';
import '../../providers/auth_provider.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/records_provider.dart';

class EnhancedDashboardScreen extends ConsumerStatefulWidget {
  const EnhancedDashboardScreen({super.key});

  @override
  ConsumerState<EnhancedDashboardScreen> createState() =>
      _EnhancedDashboardScreenState();
}

class _EnhancedDashboardScreenState
    extends ConsumerState<EnhancedDashboardScreen>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final user = ref.watch(authProvider).user;
    final analytics = ref.watch(analyticsProvider);
    final notifications = ref.watch(notificationsProvider);
    final records = ref.watch(recordsProvider);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          // Enhanced App Bar
          SliverAppBar(
            expandedHeight: 120,
            floating: false,
            pinned: true,
            elevation: 0,
            backgroundColor: colorScheme.surface,
            foregroundColor: colorScheme.onSurface,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colorScheme.primary.withValues(alpha: 0.1),
                      colorScheme.surface,
                    ],
                  ),
                ),
              ),
            ),
            title: Text(
              'Dashboard',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            actions: [
              // Notifications Badge
              Stack(
                children: [
                  IconButton(
                    onPressed: () => context.push('/notifications'),
                    icon: Icon(
                      Icons.notifications_outlined,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  if (notifications.isNotEmpty)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: colorScheme.error,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          '${notifications.length > 9 ? '9+' : notifications.length}',
                          style: TextStyle(
                            color: colorScheme.onError,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),

              // Profile Button
              IconButton(
                onPressed: () => context.push('/profile'),
                icon: CircleAvatar(
                  radius: 16,
                  backgroundColor: colorScheme.primary,
                  child: Text(
                    _getUserInitial(user),
                    style: TextStyle(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),

          // Dashboard Content
          SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Welcome Section
                        _buildWelcomeSection(user, colorScheme, theme),

                        const SizedBox(height: 20),

                        // Quick Actions
                        _buildQuickActions(colorScheme, theme),

                        const SizedBox(height: 20),

                        // Statistics Cards
                        _buildStatisticsCards(analytics, colorScheme, theme),

                        const SizedBox(height: 20),

                        // Recent Records
                        _buildRecentRecords(records, colorScheme, theme),

                        const SizedBox(
                          height: 80,
                        ), // Bottom padding for nav bar
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeSection(
    dynamic user,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    final now = DateTime.now();
    final hour = now.hour;
    String greeting = 'Good morning';
    if (hour >= 12 && hour < 17) {
      greeting = 'Good afternoon';
    } else if (hour >= 17) {
      greeting = 'Good evening';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colorScheme.primary, colorScheme.secondary],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            greeting,
            style: TextStyle(
              fontSize: 16,
              color: colorScheme.onPrimary.withValues(alpha: 0.9),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            user?.displayName ?? user?.email?.split('@').first ?? 'User',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: colorScheme.onPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            DateFormat('EEEE, MMMM d, yyyy').format(now),
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onPrimary.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(ColorScheme colorScheme, ThemeData theme) {
    final actions = [
      {
        'title': 'Add Record',
        'subtitle': 'Create new parish record',
        'icon': Icons.add_circle_outline,
        'color': colorScheme.primary,
        'route': '/records',
      },
      {
        'title': 'Scan Certificate',
        'subtitle': 'OCR text extraction',
        'icon': Icons.document_scanner_outlined,
        'color': colorScheme.secondary,
        'route': '/ocr',
      },
      {
        'title': 'Search Records',
        'subtitle': 'Find existing records',
        'icon': Icons.search_outlined,
        'color': colorScheme.tertiary,
        'route': '/records',
      },
      {
        'title': 'Certificate Request',
        'subtitle': 'Process requests',
        'icon': Icons.request_page_outlined,
        'color': colorScheme.error,
        'route': '/records',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: actions.length,
          itemBuilder: (context, index) {
            final action = actions[index];
            return _buildActionCard(
              title: action['title'] as String,
              subtitle: action['subtitle'] as String,
              icon: action['icon'] as IconData,
              color: action['color'] as Color,
              onTap: () => context.push(action['route'] as String),
              colorScheme: colorScheme,
            );
          },
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return Card(
      elevation: 2,
      shadowColor: color.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 2),
              Flexible(
                child: Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatisticsCards(
    dynamic analytics,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    // Get real data from records
    final records = ref.watch(recordsProvider);
    final totalRecords = records.length;
    final thisMonth = records.where((record) {
      final now = DateTime.now();
      return record.date.year == now.year && record.date.month == now.month;
    }).length;
    final pendingApproval = records.where((record) => 
      record.certificateStatus == CertificateStatus.pending
    ).length;

    final stats = [
      {
        'title': 'Total Records',
        'value': totalRecords.toString(),
        'change': '+12%',
        'icon': Icons.folder_outlined,
        'color': colorScheme.primary,
      },
      {
        'title': 'This Month',
        'value': thisMonth.toString(),
        'change': '+5%',
        'icon': Icons.calendar_today_outlined,
        'color': colorScheme.secondary,
      },
      {
        'title': 'Pending Approval',
        'value': pendingApproval.toString(),
        'change': pendingApproval > 0 ? '+${pendingApproval}' : '0',
        'icon': Icons.pending_outlined,
        'color': colorScheme.tertiary,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Statistics',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: stats.length,
            itemBuilder: (context, index) {
              final stat = stats[index];
              return Container(
                width: 140,
                margin: EdgeInsets.only(
                  right: index < stats.length - 1 ? 8 : 0,
                ),
                child: _buildStatCard(
                  title: stat['title'] as String,
                  value: stat['value'] as String,
                  change: stat['change'] as String,
                  icon: stat['icon'] as IconData,
                  color: stat['color'] as Color,
                  colorScheme: colorScheme,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String change,
    required IconData icon,
    required Color color,
    required ColorScheme colorScheme,
  }) {
    final isPositive = change.startsWith('+');

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 18),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: (isPositive ? Colors.green : Colors.red).withValues(
                      alpha: 0.1,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    change,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: isPositive ? Colors.green : Colors.red,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentRecords(
    dynamic records,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    // Mock recent records - replace with actual data
    final recentRecords = [
      {
        'name': 'Maria Santos',
        'type': 'Baptism',
        'date': DateTime.now().subtract(const Duration(days: 1)),
        'status': 'Pending',
      },
      {
        'name': 'Juan Cruz',
        'type': 'Marriage',
        'date': DateTime.now().subtract(const Duration(days: 2)),
        'status': 'Approved',
      },
      {
        'name': 'Ana Rodriguez',
        'type': 'Confirmation',
        'date': DateTime.now().subtract(const Duration(days: 3)),
        'status': 'Pending',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Records',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            TextButton(
              onPressed: () => context.push('/records'),
              child: Text(
                'View All',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: recentRecords.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              color: colorScheme.outline.withValues(alpha: 0.2),
            ),
            itemBuilder: (context, index) {
              final record = recentRecords[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: CircleAvatar(
                  backgroundColor: _getRecordTypeColor(
                    record['type'] as String,
                  ).withValues(alpha: 0.1),
                  child: Icon(
                    _getRecordTypeIcon(record['type'] as String),
                    color: _getRecordTypeColor(record['type'] as String),
                    size: 20,
                  ),
                ),
                title: Text(
                  record['name'] as String,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                subtitle: Text(
                  '${record['type']} • ${DateFormat('MMM d, yyyy').format(record['date'] as DateTime)}',
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(
                      record['status'] as String,
                    ).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    record['status'] as String,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _getStatusColor(record['status'] as String),
                    ),
                  ),
                ),
                onTap: () => context.push('/records'),
              );
            },
          ),
        ),
      ],
    );
  }

  Color _getRecordTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'baptism':
        return Colors.blue;
      case 'marriage':
        return Colors.pink;
      case 'confirmation':
        return Colors.purple;
      case 'death':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  IconData _getRecordTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'baptism':
        return Icons.water_drop_outlined;
      case 'marriage':
        return Icons.favorite_outline;
      case 'confirmation':
        return Icons.verified_outlined;
      case 'death':
        return Icons.person_outline;
      default:
        return Icons.description_outlined;
    }
  }

  String _getUserInitial(dynamic user) {
    if (user?.displayName != null && user.displayName.isNotEmpty) {
      return user.displayName.substring(0, 1).toUpperCase();
    }
    if (user?.email != null && user.email.isNotEmpty) {
      return user.email.substring(0, 1).toUpperCase();
    }
    return 'U';
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
