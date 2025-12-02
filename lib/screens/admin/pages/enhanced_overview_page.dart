import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/records_provider.dart';
import '../../../models/record.dart';
import '../../../utils/responsive.dart';

class EnhancedAdminOverviewPage extends ConsumerStatefulWidget {
  const EnhancedAdminOverviewPage({super.key});

  @override
  ConsumerState<EnhancedAdminOverviewPage> createState() =>
      _EnhancedAdminOverviewPageState();
}

class _EnhancedAdminOverviewPageState
    extends ConsumerState<EnhancedAdminOverviewPage>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
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
    final records = ref.watch(recordsProvider);
    final auth = ref.watch(authProvider);

    // Calculate statistics
    final totalRecords = records.length;
    final baptismRecords = records
        .where((r) => r.type == RecordType.baptism)
        .length;
    final marriageRecords = records
        .where((r) => r.type == RecordType.marriage)
        .length;
    final confirmationRecords = records
        .where((r) => r.type == RecordType.confirmation)
        .length;
    final funeralRecords = records
        .where((r) => r.type == RecordType.funeral)
        .length;
    final totalRequests = records
        .where((record) => _isCertificateRequest(record))
        .length;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primary.withValues(alpha: 0.1),
              colorScheme.surface,
              colorScheme.secondary.withValues(alpha: 0.05),
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: SingleChildScrollView(
                padding: context.padAll(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Modern Header
                    _buildModernHeader(theme, colorScheme, auth, context),
                    SizedBox(height: context.rf(24)),

                    // Statistics Cards
                    _buildStatisticsGrid(
                      theme,
                      colorScheme,
                      totalRecords,
                      baptismRecords,
                      marriageRecords,
                      confirmationRecords,
                      funeralRecords,
                      totalRequests,
                    ),
                    const SizedBox(height: 24),

                    // Record Types Chart
                    _buildRecordTypesSection(
                      theme,
                      colorScheme,
                      baptismRecords,
                      marriageRecords,
                      confirmationRecords,
                      funeralRecords,
                    ),
                    const SizedBox(height: 24),

                    // Quick Actions
                    _buildQuickActions(context, theme, colorScheme),
                    SizedBox(height: context.rf(24)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernHeader(
    ThemeData theme,
    ColorScheme colorScheme,
    dynamic auth,
    BuildContext context,
  ) {
    final now = DateTime.now();
    final hour = now.hour;
    String greeting;
    IconData greetingIcon;

    if (hour < 12) {
      greeting = 'Good Morning';
      greetingIcon = Icons.wb_sunny;
    } else if (hour < 17) {
      greeting = 'Good Afternoon';
      greetingIcon = Icons.wb_sunny_outlined;
    } else {
      greeting = 'Good Evening';
      greetingIcon = Icons.nights_stay;
    }

    return Container(
      padding: context.padAll(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primary,
            colorScheme.primary.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: context.padAll(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(greetingIcon, size: 28, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w500,
                    fontSize: context.rf(
                      theme.textTheme.titleMedium?.fontSize ?? 16,
                    ),
                  ),
                ),
                SizedBox(height: context.rf(4)),
                Text(
                  auth.user?.displayName ?? 'Administrator',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: context.rf(
                      theme.textTheme.titleLarge?.fontSize ?? 20,
                    ),
                  ),
                ),
                SizedBox(height: context.rf(8)),
                Text(
                  'Parish Record Management System',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsGrid(
    ThemeData theme,
    ColorScheme colorScheme,
    int totalRecords,
    int baptismRecords,
    int marriageRecords,
    int confirmationRecords,
    int funeralRecords,
    int totalRequests,
  ) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.8,
      children: [
        _buildStatCard(
          'Total Records',
          totalRecords.toString(),
          Icons.folder_outlined,
          colorScheme.primary,
          theme,
        ),
        _buildStatCard(
          'Baptism Records',
          baptismRecords.toString(),
          Icons.water_drop_outlined,
          Colors.blue,
          theme,
        ),
        _buildStatCard(
          'Marriage Records',
          marriageRecords.toString(),
          Icons.favorite_outline,
          Colors.pink,
          theme,
        ),
        _buildStatCard(
          'Confirmation Records',
          confirmationRecords.toString(),
          Icons.verified,
          Colors.purple,
          theme,
        ),
        _buildStatCard(
          'Death Records',
          funeralRecords.toString(),
          Icons.person_outline,
          Colors.grey,
          theme,
        ),
        _buildStatCard(
          'Total Requests',
          totalRequests.toString(),
          Icons.request_page_outlined,
          Colors.orange,
          theme,
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
    ThemeData theme,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              Icon(Icons.trending_up, color: Colors.green, size: 16),
            ],
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 4),
          Flexible(
            child: Text(
              title,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordTypesSection(
    ThemeData theme,
    ColorScheme colorScheme,
    int baptism,
    int marriage,
    int confirmation,
    int funeral,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pie_chart, color: colorScheme.primary, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Record Types Distribution',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildRecordTypeItem(
                  'Baptism',
                  baptism,
                  Icons.child_care,
                  Colors.blue,
                  theme,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildRecordTypeItem(
                  'Marriage',
                  marriage,
                  Icons.favorite,
                  Colors.pink,
                  theme,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildRecordTypeItem(
                  'Confirmation',
                  confirmation,
                  Icons.verified_user,
                  Colors.green,
                  theme,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildRecordTypeItem(
                  'Funeral',
                  funeral,
                  Icons.local_florist,
                  Colors.grey,
                  theme,
                ),
              ),
            ],
          ),
        ],
      ),
    );
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

  Widget _buildRecordTypeItem(
    String title,
    int count,
    IconData icon,
    Color color,
    ThemeData theme,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count.toString(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flash_on, color: colorScheme.primary, size: 24),
              const SizedBox(width: 12),
              Text(
                'Quick Actions',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 3.5,
            children: [
              _buildQuickActionButton(
                'Manage Users',
                Icons.people,
                colorScheme.primary,
                () => context.go('/admin/users'),
              ),
              _buildQuickActionButton(
                'Certificates',
                Icons.verified,
                Colors.orange,
                () => context.go('/admin/certificates'),
              ),
              _buildQuickActionButton(
                'Analytics',
                Icons.analytics,
                Colors.green,
                () => context.go('/admin/analytics'),
              ),
              _buildQuickActionButton(
                'Settings',
                Icons.settings,
                Colors.grey,
                () => context.go('/admin/settings'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton(
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
