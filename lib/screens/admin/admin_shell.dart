import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AdminShell extends ConsumerWidget {
  final Widget child;
  const AdminShell({super.key, required this.child});

  static const _items = [
    _NavItem('Overview', Icons.dashboard_outlined, '/admin/overview'),
    _NavItem('Users', Icons.group_outlined, '/admin/users'),
    _NavItem('Analytics', Icons.insights_outlined, '/admin/analytics'),
    _NavItem('Records', Icons.list_alt_outlined, '/admin/records'),
    _NavItem('Certificates', Icons.verified_outlined, '/admin/certificates'),
    _NavItem('Announcements', Icons.campaign_outlined, '/admin/announcements'),
    _NavItem(
      'Notifications',
      Icons.notifications_outlined,
      '/admin/notifications',
    ),
    _NavItem('Backup/Export', Icons.cloud_upload_outlined, '/admin/backup'),
    _NavItem('Settings & Audit', Icons.settings_outlined, '/admin/settings'),
  ];

  int _indexFromLocation(String location) {
    for (int i = 0; i < _items.length; i++) {
      if (location.startsWith(_items[i].route)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.toString();
    final idx = _indexFromLocation(location);
    final isWide = MediaQuery.of(context).size.width >= 1000;

    void goSafe(String route) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(route);
      });
    }

    Widget wrapContent(Widget child) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final pad = w < 480 ? 12.0 : 16.0;
          final content = Padding(padding: EdgeInsets.all(pad), child: child);

          if (w >= 1400) {
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: content,
              ),
            );
          }

          return content;
        },
      );
    }

    if (isWide) {
      return Scaffold(
        resizeToAvoidBottomInset: true,
        body: Row(
          children: [
            SizedBox(
              width: 280,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          const Icon(Icons.church_outlined),
                          const SizedBox(width: 8),
                          Text(
                            'ParishRecord',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _items.length,
                        itemBuilder: (context, i) {
                          final it = _items[i];
                          final selected = i == idx;
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                if (location.startsWith(it.route)) return;
                                goSafe(it.route);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? Theme.of(context).colorScheme.primary
                                            .withValues(alpha: 0.08)
                                      : null,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    _buildAdminNavIcon(it, 0),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        it.label,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.black,
                          ),
                          icon: const Icon(Icons.logout),
                          label: const Text('Logout'),
                          onPressed: () {
                            FirebaseAuth.instance.signOut();
                            goSafe('/login');
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: SafeArea(child: wrapContent(child))),
          ],
        ),
      );
    }

    // Narrow screens: slide-out drawer menu with selection highlight
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Admin'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: const Icon(Icons.church_outlined),
                title: const Text('ParishRecord'),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, i) {
                    final it = _items[i];
                    final selected = i == idx;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          final route = it.route;
                          final shouldGo = !location.startsWith(route);
                          Navigator.of(context).pop();
                          if (!shouldGo) return;
                          goSafe(route);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.08)
                                : null,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              _buildAdminNavIcon(it, 0),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  it.label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.of(context).pop();
                    FirebaseAuth.instance.signOut();
                    goSafe('/login');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.logout, color: Colors.black),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Logout',
                            style: TextStyle(color: Colors.black),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(child: wrapContent(child)),
    );
  }

  Widget _buildAdminNavIcon(_NavItem item, int unread) {
    final base = Icon(item.icon);
    if (item.route != '/admin/notifications' || unread <= 0) {
      return base;
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        base,
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final String route;
  const _NavItem(this.label, this.icon, this.route);
}
