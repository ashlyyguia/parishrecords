// ignore_for_file: use_build_context_synchronously, unnecessary_to_list_in_spreads

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';

/// Enhanced Admin Shell with modern UX patterns
class EnhancedAdminShell extends ConsumerStatefulWidget {
  final Widget child;
  const EnhancedAdminShell({super.key, required this.child});

  @override
  ConsumerState<EnhancedAdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<EnhancedAdminShell> {
  bool _sidebarExpanded = true;
  int _hoveredIndex = -1;

  static final _navGroups = [
    _NavGroup(
      label: 'Overview',
      items: [
        _NavItem(
          'Dashboard',
          Icons.dashboard_outlined,
          Icons.dashboard_rounded,
          '/admin/dashboard',
          Colors.blue,
        ),
      ],
    ),
    _NavGroup(
      label: 'Management',
      items: [
        _NavItem(
          'Users',
          Icons.group_outlined,
          Icons.group_rounded,
          '/admin/users',
          Colors.orange,
        ),
        _NavItem(
          'Households',
          Icons.home_work_outlined,
          Icons.home_work_rounded,
          '/admin/households',
          Colors.teal,
        ),
        _NavItem(
          'Parishioners',
          Icons.people_outlined,
          Icons.people_rounded,
          '/admin/parishioners',
          Colors.green,
        ),
        _NavItem(
          'Sacraments',
          Icons.church_outlined,
          Icons.church_rounded,
          '/admin/records',
          Colors.indigo,
        ),
      ],
    ),
    _NavGroup(
      label: 'Operations',
      items: [
        _NavItem(
          'OCR Queue',
          Icons.document_scanner_outlined,
          Icons.document_scanner_rounded,
          '/admin/ocr',
          Colors.cyan,
        ),
        _NavItem(
          'Requests',
          Icons.assignment_outlined,
          Icons.assignment_rounded,
          '/admin/requests',
          Colors.amber,
        ),
        _NavItem(
          'Finance',
          Icons.account_balance_wallet_outlined,
          Icons.account_balance_wallet_rounded,
          '/admin/finance',
          Colors.green,
        ),
      ],
    ),
    _NavGroup(
      label: 'System',
      items: [
        _NavItem(
          'Reports',
          Icons.assessment_outlined,
          Icons.assessment_rounded,
          '/admin/reports',
          Colors.blueGrey,
        ),
        _NavItem(
          'Announcements',
          Icons.campaign_outlined,
          Icons.campaign_rounded,
          '/admin/announcements',
          Colors.deepOrange,
        ),
        _NavItem(
          'Audit Logs',
          Icons.receipt_long_outlined,
          Icons.receipt_long_rounded,
          '/admin/audit',
          Colors.brown,
        ),
        _NavItem(
          'Settings',
          Icons.settings_outlined,
          Icons.settings_rounded,
          '/admin/settings',
          Colors.grey,
        ),
      ],
    ),
  ];

  int _getIndexFromLocation(String location) {
    int idx = 0;
    for (final group in _navGroups) {
      for (final item in group.items) {
        if (location.startsWith(item.route)) return idx;
        idx++;
      }
    }
    return 0;
  }

  _NavItem? _getItemFromLocation(String location) {
    for (final group in _navGroups) {
      for (final item in group.items) {
        if (location.startsWith(item.route)) return item;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final selectedIndex = _getIndexFromLocation(location);
    final currentItem = _getItemFromLocation(location);
    final colorScheme = Theme.of(context).colorScheme;
    final isWide = MediaQuery.of(context).size.width >= 1200;
    final isMedium = MediaQuery.of(context).size.width >= 800;

    // Auto-collapse sidebar on medium screens
    if (!isMedium && _sidebarExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() => _sidebarExpanded = false);
      });
    }

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: Row(
        children: [
          // Animated Sidebar
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            width: _sidebarExpanded ? 280 : 72,
            child: _buildSidebar(colorScheme, selectedIndex, location, isWide),
          ),

          // Main Content Area
          Expanded(
            child: Column(
              children: [
                // Enhanced Top Bar
                _buildTopBar(colorScheme, currentItem, location),

                // Page Content
                Expanded(child: _buildContentArea(context, widget.child)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(
    ColorScheme colorScheme,
    int selectedIndex,
    String location,
    bool isWide,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Logo Section
          _buildLogoSection(colorScheme),

          const Divider(height: 1, indent: 16, endIndent: 16),

          // Navigation Groups
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < _navGroups.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 24,
                        indent: _sidebarExpanded ? 16 : 20,
                        endIndent: _sidebarExpanded ? 16 : 20,
                      ),
                    _buildNavGroup(
                      _navGroups[i],
                      colorScheme,
                      selectedIndex,
                      location,
                    ),
                  ],
                ],
              ),
            ),
          ),

          const Divider(height: 1, indent: 16, endIndent: 16),

          // Bottom Actions
          _buildBottomActions(colorScheme),
        ],
      ),
    );
  }

  Widget _buildLogoSection(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: MouseRegion(
        onEnter: (_) => setState(() {}),
        child: GestureDetector(
          onTap: () => context.go('/admin/dashboard'),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [colorScheme.primary, colorScheme.tertiary],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.church_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                if (_sidebarExpanded) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ParishRecord',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          'Admin Portal',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavGroup(
    _NavGroup group,
    ColorScheme colorScheme,
    int selectedIndex,
    String location,
  ) {
    int runningIndex = 0;
    for (final g in _navGroups) {
      if (g == group) break;
      runningIndex += g.items.length;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_sidebarExpanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
            child: Text(
              group.label.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                letterSpacing: 0.5,
              ),
            ),
          ),
        ...group.items.asMap().entries.map((entry) {
          final idx = runningIndex + entry.key;
          final item = entry.value;
          final isSelected = idx == selectedIndex;
          final isHovered = _hoveredIndex == idx;

          return MouseRegion(
            onEnter: (_) => setState(() => _hoveredIndex = idx),
            onExit: (_) => setState(() => _hoveredIndex = -1),
            child: GestureDetector(
              onTap: () {
                if (!location.startsWith(item.route)) {
                  context.go(item.route);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: EdgeInsets.symmetric(
                  horizontal: _sidebarExpanded ? 12 : 10,
                  vertical: 2,
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: _sidebarExpanded ? 12 : 0,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? item.color.withValues(alpha: 0.1)
                      : isHovered
                      ? colorScheme.onSurface.withValues(alpha: 0.05)
                      : null,
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected
                      ? Border.all(
                          color: item.color.withValues(alpha: 0.3),
                          width: 1,
                        )
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: _sidebarExpanded
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.center,
                  children: [
                    if (!_sidebarExpanded) const SizedBox(width: 4),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        isSelected ? item.selectedIcon : item.icon,
                        color: isSelected
                            ? item.color
                            : colorScheme.onSurfaceVariant,
                        size: 22,
                      ),
                    ),
                    if (_sidebarExpanded) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: isSelected
                                ? item.color
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (isSelected)
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: item.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildBottomActions(ColorScheme colorScheme) {
    final authState = ref.watch(authProvider);
    final user = authState.user;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Toggle Sidebar Button
          GestureDetector(
            onTap: () => setState(() => _sidebarExpanded = !_sidebarExpanded),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _sidebarExpanded ? Icons.chevron_left : Icons.chevron_right,
                color: colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ),
          ),

          const SizedBox(height: 8),

          // User Profile Mini
          if (_sidebarExpanded && user != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: colorScheme.primary,
                    child: Text(
                      (user.displayName ?? user.email)[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.displayName ?? user.email,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          user.role.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else if (user != null)
            CircleAvatar(
              radius: 20,
              backgroundColor: colorScheme.primary,
              child: Text(
                (user.displayName ?? user.email)[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar(
    ColorScheme colorScheme,
    _NavItem? currentItem,
    String location,
  ) {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          // Breadcrumbs
          if (currentItem != null)
            Row(
              children: [
                Icon(currentItem.icon, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  currentItem.label,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),

          const Spacer(),

          // Search Button - Navigate to records page for searching
          _buildTopBarButton(
            icon: Icons.search,
            onTap: () => context.go('/admin/records'),
            colorScheme: colorScheme,
          ),

          const SizedBox(width: 8),

          // Notifications - Navigate to notifications page
          _buildTopBarButton(
            icon: Icons.notifications_outlined,
            onTap: () => context.go('/admin/notifications'),
            colorScheme: colorScheme,
          ),

          const SizedBox(width: 8),

          // Quick Actions Menu
          _buildQuickActionsMenu(colorScheme),

          const SizedBox(width: 8),

          // User Menu with Logout
          _buildUserMenu(colorScheme),
        ],
      ),
    );
  }

  Widget _buildTopBarButton({
    required IconData icon,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
    Widget? badge,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child:
            badge ?? Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
      ),
    );
  }

  // Removed - replaced with simple navigation button above

  Widget _buildQuickActionsMenu(ColorScheme colorScheme) {
    return PopupMenuButton<String>(
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [colorScheme.primary, colorScheme.tertiary],
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 20),
      ),
      itemBuilder: (context) => [
        _buildQuickActionItem(
          Icons.person_add,
          'Add User',
          Colors.orange,
          () => context.go('/admin/users'),
        ),
        _buildQuickActionItem(
          Icons.home_work,
          'Add Household',
          Colors.teal,
          () => context.go('/admin/households'),
        ),
        _buildQuickActionItem(
          Icons.campaign,
          'New Announcement',
          Colors.deepOrange,
          () => context.go('/admin/announcements'),
        ),
      ],
    );
  }

  Widget _buildUserMenu(ColorScheme colorScheme) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    if (user == null) return const SizedBox.shrink();

    return PopupMenuButton<String>(
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.displayName ?? user.email,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                user.email,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'profile',
          child: Row(
            children: [
              Icon(Icons.person_outline, color: colorScheme.onSurface),
              const SizedBox(width: 12),
              const Text('Profile'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'settings',
          child: Row(
            children: [
              Icon(Icons.settings_outlined, color: colorScheme.onSurface),
              const SizedBox(width: 12),
              const Text('Settings'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout, color: colorScheme.error),
              const SizedBox(width: 12),
              Text('Logout', style: TextStyle(color: colorScheme.error)),
            ],
          ),
        ),
      ],
      onSelected: (value) async {
        if (value == 'profile') {
          context.go('/admin/profile');
        } else if (value == 'settings') {
          context.go('/admin/settings');
        } else if (value == 'logout') {
          await ref.read(authProvider.notifier).logout();
          if (context.mounted) context.go('/login');
        }
      },
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: CircleAvatar(
          radius: 18,
          backgroundColor: colorScheme.primary,
          child: Text(
            (user.displayName ?? user.email)[0].toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  PopupMenuEntry<String> _buildQuickActionItem(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return PopupMenuItem<String>(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildContentArea(BuildContext context, Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = constraints.maxWidth < 600 ? 16.0 : 24.0;

        return AnimatedPadding(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.all(padding),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1400),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _NavGroup {
  final String label;
  final List<_NavItem> items;
  _NavGroup({required this.label, required this.items});
}

class _NavItem {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String route;
  final Color color;

  _NavItem(this.label, this.icon, this.selectedIcon, this.route, this.color);
}
