import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../providers/requests_provider.dart';
import '../../../providers/ocr_jobs_provider.dart';
import '../../../widgets/app_loading.dart';

class StaffDashboardPage extends ConsumerWidget {
  const StaffDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final size = MediaQuery.of(context).size;
    final width = size.width;

    // Responsive breakpoints
    final isDesktop = width >= 1200;
    final isTablet = width >= 768 && width < 1200;
    final isMobile = width < 768;

    final horizontalPadding = isDesktop ? 32.0 : (isTablet ? 24.0 : 16.0);
    final verticalPadding = isDesktop ? 32.0 : (isTablet ? 24.0 : 20.0);

    final requestsAsync = ref.watch(certificateRequestsProvider(50));
    final ocrAsync = ref.watch(ocrJobsAssignedToMeProvider(30));

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Staff Portal Header
                _buildPortalHeader(context, colorScheme, isMobile),
                SizedBox(height: isDesktop ? 28 : (isTablet ? 24 : 20)),
                // Stats Overview - Responsive grid
                _buildStatsOverview(
                  context,
                  requestsAsync,
                  ocrAsync,
                  colorScheme,
                  isDesktop,
                  isTablet,
                  isMobile,
                ),
                SizedBox(height: isDesktop ? 28 : (isTablet ? 24 : 20)),
                // Main Content Grid
                isDesktop
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: Column(
                              children: [
                                _buildQuickActions(
                                  context,
                                  colorScheme,
                                  isTablet,
                                  isMobile,
                                ),
                                const SizedBox(height: 24),
                                _buildRecentRequests(
                                  context,
                                  requestsAsync,
                                  colorScheme,
                                  isTablet,
                                  isMobile,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: _buildMyTasks(
                              context,
                              ocrAsync,
                              colorScheme,
                              isTablet,
                              isMobile,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          _buildQuickActions(
                            context,
                            colorScheme,
                            isTablet,
                            isMobile,
                          ),
                          SizedBox(height: isTablet ? 24 : 20),
                          _buildMyTasks(
                            context,
                            ocrAsync,
                            colorScheme,
                            isTablet,
                            isMobile,
                          ),
                          SizedBox(height: isTablet ? 24 : 20),
                          _buildRecentRequests(
                            context,
                            requestsAsync,
                            colorScheme,
                            isTablet,
                            isMobile,
                          ),
                        ],
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPortalHeader(
    BuildContext context,
    ColorScheme colorScheme,
    bool isMobile,
  ) {
    final now = DateTime.now();
    final timeStr = DateFormat('EEEE, MMMM d, yyyy').format(now);
    final hour = now.hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';

    return Container(
      padding: EdgeInsets.all(isMobile ? 20 : 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary,
            Color.from(
              alpha: 1.0,
              red: colorScheme.primary.r * 0.7,
              green: colorScheme.primary.g * 0.8,
              blue: colorScheme.primary.b * 1.2,
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(isMobile ? 16 : 24),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.admin_panel_settings_outlined,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$greeting,',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Staff Portal',
                            style: GoogleFonts.inter(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Notification icon
                    IconButton(
                      icon: const Icon(
                        Icons.notifications_outlined,
                        color: Colors.white,
                        size: 24,
                      ),
                      onPressed: () => context.go('/staff/notifications'),
                    ),
                    // Profile icon
                    IconButton(
                      icon: const Icon(
                        Icons.person_outline,
                        color: Colors.white,
                        size: 24,
                      ),
                      onPressed: () => context.go('/staff/profile'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  timeStr,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.admin_panel_settings_outlined,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$greeting,',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Staff Portal',
                        style: GoogleFonts.inter(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        timeStr,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                // Notification icon
                IconButton(
                  icon: const Icon(
                    Icons.notifications_outlined,
                    color: Colors.white,
                    size: 24,
                  ),
                  onPressed: () => context.go('/staff/notifications'),
                ),
                // Profile icon
                IconButton(
                  icon: const Icon(
                    Icons.person_outline,
                    color: Colors.white,
                    size: 24,
                  ),
                  onPressed: () => context.go('/staff/profile'),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Active',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatsOverview(
    BuildContext context,
    AsyncValue<List<Map<String, dynamic>>> requestsAsync,
    AsyncValue<List<dynamic>> ocrAsync,
    ColorScheme colorScheme,
    bool isDesktop,
    bool isTablet,
    bool isMobile,
  ) {
    return requestsAsync.when(
      data: (requests) {
        final pending = requests.where((r) => r['status'] == 'pending').length;
        final approved = requests
            .where((r) => r['status'] == 'approved')
            .length;

        return ocrAsync.when(
          data: (jobs) {
            final pendingJobs = jobs
                .where((j) => j['status'] == 'pending')
                .length;

            final stats = [
              _StatData(
                title: 'Pending',
                value: pending.toString(),
                subtitle: 'Need attention',
                icon: Icons.pending_actions_outlined,
                color: const Color(0xFFF59E0B),
                bgColor: const Color(0xFFFEF3C7),
              ),
              _StatData(
                title: 'Approved',
                value: approved.toString(),
                subtitle: 'Completed',
                icon: Icons.check_circle_outlined,
                color: const Color(0xFF10B981),
                bgColor: const Color(0xFFD1FAE5),
              ),
              _StatData(
                title: 'OCR Tasks',
                value: pendingJobs.toString(),
                subtitle: 'In queue',
                icon: Icons.document_scanner_outlined,
                color: const Color(0xFF3B82F6),
                bgColor: const Color(0xFFDBEAFE),
              ),
              _StatData(
                title: 'Total',
                value: (requests.length + jobs.length).toString(),
                subtitle: 'All time',
                icon: Icons.folder_outlined,
                color: const Color(0xFF8B5CF6),
                bgColor: const Color(0xFFEDE9FE),
              ),
            ];

            // Responsive grid layout
            if (isDesktop) {
              // 4 columns on desktop
              return Row(
                children: stats
                    .map(
                      (stat) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: _StatCard(data: stat, isMobile: false),
                        ),
                      ),
                    )
                    .toList(),
              );
            } else if (isTablet) {
              // 2x2 grid on tablet
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(data: stats[0], isMobile: false),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(data: stats[1], isMobile: false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(data: stats[2], isMobile: false),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(data: stats[3], isMobile: false),
                      ),
                    ],
                  ),
                ],
              );
            } else {
              // 2x2 grid on mobile with smaller cards
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(data: stats[0], isMobile: true),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatCard(data: stats[1], isMobile: true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(data: stats[2], isMobile: true),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatCard(data: stats[3], isMobile: true),
                      ),
                    ],
                  ),
                ],
              );
            }
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const SizedBox.shrink(),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildQuickActions(
    BuildContext context,
    ColorScheme colorScheme,
    bool isTablet,
    bool isMobile,
  ) {
    final actions = [
      _ActionData(
        icon: Icons.add_circle_outline,
        label: 'Add Records',
        description: 'Create new parish record',
        color: const Color(0xFF3B82F6),
        onTap: () => context.go('/staff/records'),
      ),
      _ActionData(
        icon: Icons.document_scanner_outlined,
        label: 'Scan Certificate',
        description: 'OCR text extraction',
        color: const Color(0xFF8B5CF6),
        onTap: () => context.go('/staff/ocr/upload'),
      ),
      _ActionData(
        icon: Icons.schedule_outlined,
        label: 'Schedule',
        description: 'View parish schedule',
        color: const Color(0xFF10B981),
        onTap: () => context.go('/staff/schedule'),
      ),
      _ActionData(
        icon: Icons.people_outline,
        label: 'Requests',
        description: 'Certificate requests',
        color: const Color(0xFFF59E0B),
        onTap: () => context.go('/staff/requests'),
      ),
    ];

    // Responsive grid: 2x2 on mobile/tablet, 4 columns on desktop
    final crossAxisCount = isTablet ? 4 : 2;
    final childAspectRatio = isMobile ? 6.0 : (isTablet ? 1.8 : 3.0);
    final padding = isMobile ? 12.0 : 24.0;

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.flash_on_outlined,
                color: colorScheme.primary,
                size: isMobile ? 20 : 22,
              ),
              const SizedBox(width: 10),
              Text(
                'Quick Actions',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 16 : 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 16 : 20),
          isMobile
              ? Column(
                  children: actions
                      .map(
                        (a) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ActionCard(data: a, isMobile: isMobile),
                        ),
                      )
                      .toList(),
                )
              : GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: isMobile ? 8 : 12,
                  crossAxisSpacing: isMobile ? 8 : 12,
                  childAspectRatio: childAspectRatio,
                  children: actions
                      .map((a) => _ActionCard(data: a, isMobile: isMobile))
                      .toList(),
                ),
        ],
      ),
    );
  }

  Widget _buildMyTasks(
    BuildContext context,
    AsyncValue<List<dynamic>> ocrAsync,
    ColorScheme colorScheme,
    bool isTablet,
    bool isMobile,
  ) {
    final padding = isMobile ? 16.0 : 24.0;

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.task_alt_outlined,
                color: colorScheme.primary,
                size: isMobile ? 20 : 22,
              ),
              const SizedBox(width: 10),
              Text(
                'My Tasks',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 16 : 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 16 : 20),
          ocrAsync.when(
            data: (jobs) {
              if (jobs.isEmpty) {
                return _buildEmptyState(
                  icon: Icons.inbox_outlined,
                  message: 'No pending tasks',
                  submessage: 'You\'re all caught up!',
                );
              }
              return Column(
                children: jobs
                    .take(5)
                    .map(
                      (job) => _TaskItem(
                        title: job['filename'] ?? 'Document ${job['id']}',
                        status: job['status'] ?? 'pending',
                        time: '2 hours ago',
                        isMobile: isMobile,
                      ),
                    )
                    .toList(),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => _buildEmptyState(
              icon: Icons.error_outline,
              message: 'Could not load tasks',
              submessage: 'Try refreshing',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentRequests(
    BuildContext context,
    AsyncValue<List<Map<String, dynamic>>> requestsAsync,
    ColorScheme colorScheme,
    bool isTablet,
    bool isMobile,
  ) {
    final padding = isMobile ? 16.0 : 24.0;

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
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
              Row(
                children: [
                  Icon(
                    Icons.history_outlined,
                    color: colorScheme.primary,
                    size: isMobile ? 20 : 22,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Recent Requests',
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 16 : 18,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: () => context.go('/staff/requests'),
                child: Text(
                  'View All',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 16 : 20),
          requestsAsync.when(
            data: (requests) {
              final recent = requests.take(5).toList();
              if (recent.isEmpty) {
                return _buildEmptyState(
                  icon: Icons.inbox_outlined,
                  message: 'No recent requests',
                  submessage: 'New requests will appear here',
                );
              }
              return Column(
                children: recent.asMap().entries.map((entry) {
                  final isLast = entry.key == recent.length - 1;
                  return Column(
                    children: [
                      _RequestItem(
                        request: entry.value,
                        colorScheme: colorScheme,
                        isMobile: isMobile,
                      ),
                      if (!isLast) const Divider(height: 1),
                    ],
                  );
                }).toList(),
              );
            },
            loading: () =>
                const Center(child: AppLoading(message: 'Loading...')),
            error: (_, _) => _buildEmptyState(
              icon: Icons.error_outline,
              message: 'Failed to load requests',
              submessage: 'Please try again',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String message,
    required String submessage,
  }) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: const Color(0xFF94A3B8)),
          const SizedBox(height: 12),
          Text(
            message,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            submessage,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}

// Data Classes
class _StatData {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color bgColor;

  _StatData({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.bgColor,
  });
}

class _ActionData {
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final VoidCallback onTap;

  _ActionData({
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.onTap,
  });
}

class _StatCard extends StatelessWidget {
  final _StatData data;
  final bool isMobile;
  const _StatCard({required this.data, required this.isMobile});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(isMobile ? 8 : 10),
                decoration: BoxDecoration(
                  color: data.bgColor,
                  borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
                ),
                child: Icon(
                  data.icon,
                  color: data.color,
                  size: isMobile ? 18 : 22,
                ),
              ),
              const Spacer(),
              Text(
                data.value,
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 22 : 28,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 8 : 12),
          Text(
            data.title,
            style: GoogleFonts.inter(
              fontSize: isMobile ? 12 : 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            data.subtitle,
            style: GoogleFonts.inter(
              fontSize: isMobile ? 11 : 12,
              color: const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final _ActionData data;
  final bool isMobile;
  const _ActionCard({required this.data, required this.isMobile});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: data.onTap,
      borderRadius: BorderRadius.circular(isMobile ? 8 : 12),
      child: Container(
        padding: EdgeInsets.all(isMobile ? 8 : 16),
        decoration: BoxDecoration(
          color: data.color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(isMobile ? 8 : 12),
          border: Border.all(
            color: data.color.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(isMobile ? 6 : 10),
              decoration: BoxDecoration(
                color: data.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(isMobile ? 6 : 10),
              ),
              child: Icon(
                data.icon,
                color: data.color,
                size: isMobile ? 16 : 20,
              ),
            ),
            SizedBox(width: isMobile ? 8 : 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    data.label,
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 12 : 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  Text(
                    data.description,
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 10 : 12,
                      color: const Color(0xFF64748B),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: data.color.withValues(alpha: 0.5),
              size: isMobile ? 10 : 14,
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskItem extends StatelessWidget {
  final String title;
  final String status;
  final String time;
  final bool isMobile;

  const _TaskItem({
    required this.title,
    required this.status,
    required this.time,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    final isPending = status == 'pending';
    return Container(
      padding: EdgeInsets.symmetric(vertical: isMobile ? 10 : 12),
      child: Row(
        children: [
          Container(
            width: isMobile ? 6 : 8,
            height: isMobile ? 6 : 8,
            decoration: BoxDecoration(
              color: isPending
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFF10B981),
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: isMobile ? 10 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 12 : 13,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF1E293B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  time,
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 11 : 12,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 8 : 10,
              vertical: isMobile ? 3 : 4,
            ),
            decoration: BoxDecoration(
              color: isPending
                  ? const Color(0xFFFEF3C7)
                  : const Color(0xFFD1FAE5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isPending ? 'Pending' : 'Done',
              style: GoogleFonts.inter(
                fontSize: isMobile ? 10 : 11,
                fontWeight: FontWeight.w500,
                color: isPending
                    ? const Color(0xFFD97706)
                    : const Color(0xFF059669),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestItem extends StatelessWidget {
  final Map<String, dynamic> request;
  final ColorScheme colorScheme;
  final bool isMobile;

  const _RequestItem({
    required this.request,
    required this.colorScheme,
    required this.isMobile,
  });

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'approved':
        return const Color(0xFF10B981);
      case 'rejected':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF64748B);
    }
  }

  Color _getStatusBgColor(String? status) {
    switch (status) {
      case 'pending':
        return const Color(0xFFFEF3C7);
      case 'approved':
        return const Color(0xFFD1FAE5);
      case 'rejected':
        return const Color(0xFFFEE2E2);
      default:
        return const Color(0xFFF1F5F9);
    }
  }

  IconData _getStatusIcon(String? status) {
    switch (status) {
      case 'pending':
        return Icons.pending_outlined;
      case 'approved':
        return Icons.check_circle_outlined;
      case 'rejected':
        return Icons.cancel_outlined;
      default:
        return Icons.help_outline;
    }
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  @override
  Widget build(BuildContext context) {
    final status = request['status'] ?? 'unknown';
    final statusColor = _getStatusColor(status);
    final statusBgColor = _getStatusBgColor(status);

    return Container(
      padding: EdgeInsets.symmetric(vertical: isMobile ? 12 : 14),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isMobile ? 8 : 10),
            decoration: BoxDecoration(
              color: statusBgColor,
              borderRadius: BorderRadius.circular(isMobile ? 8 : 10),
            ),
            child: Icon(
              _getStatusIcon(status),
              color: statusColor,
              size: isMobile ? 16 : 18,
            ),
          ),
          SizedBox(width: isMobile ? 12 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request['request_type'] ?? 'Unknown Request',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 13 : 14,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  request['created_at'] ?? 'Just now',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 11 : 12,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 8 : 10,
              vertical: isMobile ? 3 : 4,
            ),
            decoration: BoxDecoration(
              color: statusBgColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _capitalize(status),
              style: GoogleFonts.inter(
                fontSize: isMobile ? 10 : 11,
                fontWeight: FontWeight.w500,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
