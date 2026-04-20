import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';

class UserShell extends ConsumerStatefulWidget {
  final Widget child;
  const UserShell({super.key, required this.child});

  @override
  ConsumerState<UserShell> createState() => _UserShellState();
}

class _NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String route;
  final Color color;

  const _NavItem(
    this.label,
    this.icon,
    this.activeIcon,
    this.route,
    this.color,
  );
}

class _UserShellState extends ConsumerState<UserShell> {
  bool _sidebarExpanded = true;
  int _hoveredIndex = -1;

  static const _navItems = [
    _NavItem(
      'Dashboard',
      Icons.dashboard_outlined,
      Icons.dashboard_rounded,
      '/user/dashboard',
      Colors.blue,
    ),
    _NavItem(
      'My Profile',
      Icons.person_outline,
      Icons.person_rounded,
      '/user/profile',
      Colors.teal,
    ),
    _NavItem(
      'My Requests',
      Icons.assignment_outlined,
      Icons.assignment_rounded,
      '/user/requests',
      Colors.orange,
    ),
    _NavItem(
      'Sacraments',
      Icons.church_outlined,
      Icons.church_rounded,
      '/user/sacraments',
      Colors.indigo,
    ),
  ];

  int _getIndexFromLocation(String location) {
    for (int i = 0; i < _navItems.length; i++) {
      if (location.startsWith(_navItems[i].route)) return i;
    }
    return 0; // Default to Dashboard
  }

  _NavItem _getItemFromLocation(String location) {
    for (final item in _navItems) {
      if (location.startsWith(item.route)) return item;
    }
    return _navItems[0];
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final selectedIndex = _getIndexFromLocation(location);
    final currentItem = _getItemFromLocation(location);
    final colorScheme = Theme.of(context).colorScheme;
    final isWide = MediaQuery.of(context).size.width >= 1024;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      drawer: isWide
          ? null
          : Drawer(
              child: _buildSidebar(
                colorScheme,
                selectedIndex,
                location,
                true,
                isMobileDrawer: true,
              ),
            ),
      body: Row(
        children: [
          // Animated Sidebar for Desktop
          if (isWide)
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
                _buildTopBar(colorScheme, currentItem, location, isWide),

                // Page Content
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(
    ColorScheme colorScheme,
    _NavItem currentItem,
    String location,
    bool isWide,
  ) {
    final auth = ref.watch(authProvider);
    final user = auth.user;
    final displayName = user?.displayName ?? 'Parishioner';

    return Container(
      height: 72,
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
          if (!isWide)
            IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
            ),
          if (!isWide) const SizedBox(width: 16),
          // Page Title & Breadcrumb
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                currentItem.label,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              Text(
                'ParishRecord $location',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Actions
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Consumer(
              builder: (context, ref, _) {
                final countAsync = ref.watch(unreadNotificationsCountStreamProvider);
                final count = countAsync.value ?? 0;
                return Stack(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_outlined),
                      onPressed: () => context.go('/user/notifications'),
                      tooltip: 'Notifications',
                    ),
                    if (count > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            count > 9 ? '9+' : count.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 16),
          // User Menu
          PopupMenuButton<String>(
            tooltip: 'Account Menu',
            offset: const Offset(0, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            onSelected: (value) {
              if (value == 'logout') {
                _handleLogout();
              } else if (value == 'profile') {
                context.go('/user/profile');
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      user?.email ?? '',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person_outline, size: 20),
                    SizedBox(width: 12),
                    Text('My Profile'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 20, color: Colors.red),
                    SizedBox(width: 12),
                    Text('Sign out', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
            child: CircleAvatar(
              radius: 20,
              backgroundColor: colorScheme.primaryContainer,
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : 'P',
                style: TextStyle(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
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
    bool isWide, {
    bool isMobileDrawer = false,
  }) {
    final expanded = isMobileDrawer || _sidebarExpanded;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        children: [
          // Logo Area
          Container(
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: expanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(Icons.church, color: colorScheme.primary, size: 28),
                if (expanded) ...[
                  const SizedBox(width: 12),
                  const Text(
                    'ParishRecord',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Navigation Links
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _navItems.length,
              itemBuilder: (context, index) {
                final item = _navItems[index];
                final isSelected = selectedIndex == index;
                final isHovered = _hoveredIndex == index;

                return MouseRegion(
                  onEnter: (_) => setState(() => _hoveredIndex = index),
                  onExit: (_) => setState(() => _hoveredIndex = -1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? item.color.withValues(alpha: 0.15)
                          : isHovered
                              ? colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5)
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          if (isMobileDrawer) {
                            Navigator.of(context).pop();
                          }
                          context.go(item.route);
                        },
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: expanded ? 16 : 12,
                          ),
                          child: Row(
                            mainAxisAlignment: expanded
                                ? MainAxisAlignment.start
                                : MainAxisAlignment.center,
                            children: [
                              Icon(
                                isSelected ? item.activeIcon : item.icon,
                                color: isSelected
                                    ? item.color
                                    : colorScheme.onSurfaceVariant,
                                size: 24,
                              ),
                              if (expanded) ...[
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    item.label,
                                    style: TextStyle(
                                      color: isSelected
                                          ? item.color
                                          : colorScheme.onSurface,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Collapse/Expand Toggle (Desktop only)
          if (!isMobileDrawer)
            Padding(
              padding: const EdgeInsets.all(12),
              child: IconButton(
                icon: Icon(
                  _sidebarExpanded
                      ? Icons.chevron_left_rounded
                      : Icons.chevron_right_rounded,
                ),
                onPressed: () {
                  setState(() => _sidebarExpanded = !_sidebarExpanded);
                },
                tooltip: _sidebarExpanded ? 'Collapse Menu' : 'Expand Menu',
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      ref.read(authProvider.notifier).signOut();
      context.go('/login');
    }
  }
}
