// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/records_provider.dart';
import '../../../models/record.dart';
import '../admin_design_system.dart';

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
    final pendingCertificates = records
        .where((r) => r.certificateStatus == CertificateStatus.pending)
        .length;
    final approvedCertificates = records
        .where((r) => r.certificateStatus == CertificateStatus.approved)
        .length;
    final now = DateTime.now();
    final thisMonthRecords = records.where((r) {
      return r.date.year == now.year && r.date.month == now.month;
    }).length;
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

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Container(
        decoration: AdminDesignSystem.pageBackground(context),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Modern Header with Design System
                    _buildWelcomeHeader(theme, colorScheme, auth),
                    const SizedBox(height: 24),

                    // Statistics Grid using Design System
                    _buildModernStatsGrid(
                      context,
                      totalRecords,
                      pendingCertificates,
                      approvedCertificates,
                      thisMonthRecords,
                    ),
                    const SizedBox(height: 24),

                    // Record Types Distribution
                    _buildRecordTypesCard(
                      context,
                      baptismRecords,
                      marriageRecords,
                      confirmationRecords,
                      funeralRecords,
                    ),
                    const SizedBox(height: 24),

                    // Quick Actions Grid
                    _buildQuickActionsGrid(context),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeHeader(
    ThemeData theme,
    ColorScheme colorScheme,
    dynamic auth,
  ) {
    return AdminDesignSystem.pageHeader(
      context,
      title: 'Welcome back, ${auth.user?.displayName ?? 'Administrator'}',
      subtitle: 'Parish Record Management System',
      icon: Icons.dashboard,
      actions: [
        AdminDesignSystem.actionButton(
          context,
          label: 'Refresh',
          icon: Icons.refresh,
          onPressed: () => ref.invalidate(recordsProvider),
          isPrimary: false,
        ),
      ],
    );
  }

  Widget _buildModernStatsGrid(
    BuildContext context,
    int totalRecords,
    int pendingCertificates,
    int approvedCertificates,
    int thisMonthRecords,
  ) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: context.isWide ? 4 : 2,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 2.2,
      children: [
        AdminDesignSystem.statCard(
          context,
          title: 'Total Records',
          value: totalRecords.toString(),
          icon: Icons.folder_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        AdminDesignSystem.statCard(
          context,
          title: 'Pending Review',
          value: pendingCertificates.toString(),
          icon: Icons.pending_actions,
          color: Colors.orange,
        ),
        AdminDesignSystem.statCard(
          context,
          title: 'Approved',
          value: approvedCertificates.toString(),
          icon: Icons.verified,
          color: Colors.green,
        ),
        AdminDesignSystem.statCard(
          context,
          title: 'This Month',
          value: thisMonthRecords.toString(),
          icon: Icons.calendar_month,
          color: Theme.of(context).colorScheme.secondary,
        ),
      ],
    );
  }

  Widget _buildRecordTypesCard(
    BuildContext context,
    int baptism,
    int marriage,
    int confirmation,
    int funeral,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AdminDesignSystem.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminDesignSystem.sectionTitle(
            context,
            'Record Types Distribution',
            action: 'View All',
          ),
          const SizedBox(height: 20),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: context.isWide ? 4 : 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 3.5,
            children: [
              _buildModernRecordTypeItem(
                'Baptism',
                baptism,
                Icons.child_care,
                Colors.blue,
              ),
              _buildModernRecordTypeItem(
                'Marriage',
                marriage,
                Icons.favorite,
                Colors.pink,
              ),
              _buildModernRecordTypeItem(
                'Confirmation',
                confirmation,
                Icons.verified_user,
                Colors.green,
              ),
              _buildModernRecordTypeItem(
                'Funeral',
                funeral,
                Icons.local_florist,
                Colors.grey,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModernRecordTypeItem(
    String title,
    int count,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  count.toString(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsGrid(BuildContext context) {
    final actions = [
      _QuickAction('Manage Users', Icons.people, Colors.blue, '/admin/users'),
      _QuickAction(
        'Analytics',
        Icons.analytics,
        Colors.green,
        '/admin/analytics',
      ),
      _QuickAction('Records', Icons.list_alt, Colors.purple, '/admin/records'),
      _QuickAction(
        'Requests',
        Icons.assignment,
        Colors.teal,
        '/admin/requests',
      ),
      _QuickAction('Settings', Icons.settings, Colors.grey, '/admin/settings'),
    ];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AdminDesignSystem.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminDesignSystem.sectionTitle(context, 'Quick Actions'),
          const SizedBox(height: 20),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: context.isWide ? 3 : 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 4.5,
            children: actions
                .map((action) => _buildModernActionButton(action))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildModernActionButton(_QuickAction action) {
    return Material(
      color: action.color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => context.go(action.route),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: action.color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(action.icon, color: action.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  action.label,
                  style: TextStyle(
                    color: action.color,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: action.color, size: 16),
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

  _QuickAction(this.label, this.icon, this.color, this.route);
}
