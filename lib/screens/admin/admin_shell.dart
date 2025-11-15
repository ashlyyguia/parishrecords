import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminShell extends StatelessWidget {
  final Widget child;
  const AdminShell({super.key, required this.child});

  static const _items = [
    _NavItem('Overview', Icons.dashboard_outlined, '/admin/overview'),
    _NavItem('Users', Icons.group_outlined, '/admin/users'),
    _NavItem('Analytics', Icons.insights_outlined, '/admin/analytics'),
    _NavItem('Activity', Icons.history_outlined, '/admin/activity'),
    _NavItem('Records', Icons.list_alt_outlined, '/admin/records'),
    _NavItem('Certificates', Icons.verified_outlined, '/admin/certificates'),
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
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final idx = _indexFromLocation(location);
    final isWide = MediaQuery.of(context).size.width >= 1000;

    if (isWide) {
      return Scaffold(
        resizeToAvoidBottomInset: true,
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: idx,
              onDestinationSelected: (i) => context.go(_items[i].route),
              extended: true,
              labelType: NavigationRailLabelType.none,
              leading: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
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
              trailing: Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.logout),
                      label: const Text('Logout'),
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) context.go('/login');
                      },
                    ),
                  ],
                ),
              ),
              destinations: [
                for (final it in _items)
                  NavigationRailDestination(
                    icon: Icon(it.icon),
                    label: Text(it.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: child,
                ),
              ),
            ),
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
                    return ListTile(
                      leading: Icon(it.icon),
                      title: Text(it.label),
                      selected: selected,
                      selectedTileColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                      onTap: () {
                        Navigator.of(context).pop();
                        if (!location.startsWith(it.route)) {
                          context.go(it.route);
                        }
                      },
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Logout'),
                onTap: () async {
                  await FirebaseAuth.instance.signOut();
                  if (context.mounted) context.go('/login');
                },
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: child,
        ),
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final String route;
  const _NavItem(this.label, this.icon, this.route);
}
