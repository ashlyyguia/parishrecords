import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../models/record.dart';
import '../../providers/auth_provider.dart';
import '../../providers/analytics_provider.dart';
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
                        _buildQuickActions(context, colorScheme, theme),

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

  Widget _buildQuickActions(
    BuildContext context,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    final actions = [
      {
        'title': 'Add Record',
        'subtitle': 'Create new parish record',
        'icon': Icons.add_circle_outline,
        'color': colorScheme.primary,
        'onTap': () => _openNewRecord(),
      },
      {
        'title': 'Add with OCR',
        'subtitle': 'Scan document to add',
        'icon': Icons.document_scanner_outlined,
        'color': colorScheme.tertiary,
        'onTap': () => _openNewRecordWithOcr(),
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
        'route': '/records/certificate-request',
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
              onTap:
                  (action['onTap'] as VoidCallback?) ??
                  () => context.push(action['route'] as String),
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
    final baptismRecords = records
        .where((record) => record.type == RecordType.baptism)
        .length;
    final marriageRecords = records
        .where((record) => record.type == RecordType.marriage)
        .length;
    final confirmationRecords = records
        .where((record) => record.type == RecordType.confirmation)
        .length;
    final deathRecords = records
        .where((record) => record.type == RecordType.funeral)
        .length;
    final totalRequests = records
        .where((record) => _isCertificateRequest(record))
        .length;

    final stats = [
      {
        'title': 'Total Records',
        'value': totalRecords.toString(),
        'change': '',
        'icon': Icons.folder_outlined,
        'color': colorScheme.primary,
      },
      {
        'title': 'Baptism Records',
        'value': baptismRecords.toString(),
        'change': '',
        'icon': Icons.water_drop_outlined,
        'color': Colors.blue,
      },
      {
        'title': 'Marriage Records',
        'value': marriageRecords.toString(),
        'change': '',
        'icon': Icons.favorite_outline,
        'color': Colors.pink,
      },
      {
        'title': 'Confirmation Records',
        'value': confirmationRecords.toString(),
        'change': '',
        'icon': Icons.verified_outlined,
        'color': Colors.purple,
      },
      {
        'title': 'Death Records',
        'value': deathRecords.toString(),
        'change': '',
        'icon': Icons.person_outline,
        'color': Colors.grey,
      },
      {
        'title': 'Total Requests',
        'value': totalRequests.toString(),
        'change': '',
        'icon': Icons.request_page_outlined,
        'color': Colors.orange,
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
          height: 132,
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
    final hasChange = change.trim().isNotEmpty;
    final isPositive = change.startsWith('+');

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 18),
                if (hasChange)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: (isPositive ? Colors.green : Colors.red)
                          .withValues(alpha: 0.1),
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
                fontSize: 11,
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
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
    final List<ParishRecord> allRecords =
        (records as List<ParishRecord>).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    final recentRecords = allRecords.take(3).toList();

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
                    record.type.value,
                  ).withValues(alpha: 0.1),
                  child: Icon(
                    _getRecordTypeIcon(record.type.value),
                    color: _getRecordTypeColor(record.type.value),
                    size: 20,
                  ),
                ),
                title: Text(
                  record.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                subtitle: Text(
                  '${toBeginningOfSentenceCase(record.type.value)} • ${DateFormat('MMM d, yyyy').format(record.date)}',
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                trailing: _isCertificateRequest(record)
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusColor(
                            record.certificateStatus.value,
                          ).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          record.certificateStatus.value,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _getStatusColor(
                              record.certificateStatus.value,
                            ),
                          ),
                        ),
                      )
                    : null,
                onTap: () => context.push('/records/${record.id}'),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openNewRecordWithOcr() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Scan New Record'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'baptism'),
            child: const Text('Baptism (OCR)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'marriage'),
            child: const Text('Marriage (OCR)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'confirmation'),
            child: const Text('Confirmation (OCR)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'death'),
            child: const Text('Death (OCR)'),
          ),
        ],
      ),
    );

    if (result == null || !mounted) return;

    switch (result) {
      case 'baptism':
        await context.push('/records/new/baptism', extra: 'ocr');
        break;
      case 'marriage':
        await context.push('/records/new/marriage', extra: 'ocr');
        break;
      case 'confirmation':
        await context.push('/records/new/confirmation', extra: 'ocr');
        break;
      case 'death':
        await context.push('/records/new/death', extra: 'ocr');
        break;
    }
  }

  Future<void> _openNewRecord() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Add New Record'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'baptism'),
            child: const Text('Baptism'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'marriage'),
            child: const Text('Marriage'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'confirmation'),
            child: const Text('Confirmation'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'death'),
            child: const Text('Death'),
          ),
        ],
      ),
    );

    if (result == null || !mounted) return;

    switch (result) {
      case 'baptism':
        await context.push('/records/new/baptism');
        break;
      case 'marriage':
        await context.push('/records/new/marriage');
        break;
      case 'confirmation':
        await context.push('/records/new/confirmation');
        break;
      case 'death':
        await context.push('/records/new/death');
        break;
    }
  }

  bool _isCertificateRequest(ParishRecord record) {
    final notes = record.notes;
    if (notes == null || notes.isEmpty) return false;

    try {
      final decoded = json.decode(notes);
      if (decoded is Map<String, dynamic>) {
        final type =
            (decoded['requestType'] as String?) ?? decoded['request_type'];
        if (type == 'certificate_request') {
          return true;
        }
      }
    } catch (_) {
      // Ignore JSON errors; fall back to simple string contains check below.
    }

    return notes.contains('certificate_request');
  }

  Color _getRecordTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'baptism':
        return Colors.blue;
      case 'marriage':
        return Colors.pink;
      case 'confirmation':
        return Colors.purple;
      case 'funeral':
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
      case 'funeral':
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
