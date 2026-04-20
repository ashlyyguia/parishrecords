import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AdminMobileShell extends StatelessWidget {
  final Widget child;
  const AdminMobileShell({super.key, required this.child});

  static const _routes = <_NavItem>[
    _NavItem('Overview', Icons.dashboard_outlined, '/admin/overview'),
    _NavItem('Records', Icons.list_alt_outlined, '/admin/records'),
    _NavItem('Users', Icons.group_outlined, '/admin/users'),
    _NavItem('More', Icons.more_horiz_outlined, null),
  ];

  int _indexFromLocation(String location) {
    for (int i = 0; i < _routes.length; i++) {
      final route = _routes[i].route;
      if (route != null && location.startsWith(route)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _indexFromLocation(location);

    return Scaffold(
      appBar: AppBar(title: const Text('Admin'), centerTitle: true),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) {
          final route = _routes[i].route;
          if (route != null) {
            context.go(route);
          } else {
            _showMoreMenu(context);
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'Records',
          ),
          NavigationDestination(
            icon: Icon(Icons.group_outlined),
            selectedIcon: Icon(Icons.group),
            label: 'Users',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz_outlined),
            selectedIcon: Icon(Icons.more_horiz),
            label: 'More',
          ),
        ],
      ),
    );
  }

  void _showMoreMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'More Options',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.assignment_outlined),
              title: const Text('Requests'),
              onTap: () {
                Navigator.pop(context);
                context.go('/admin/requests');
              },
            ),
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('OCR Queue'),
              onTap: () {
                Navigator.pop(context);
                context.go('/admin/ocr');
              },
            ),
            ListTile(
              leading: const Icon(Icons.insights_outlined),
              title: const Text('Analytics'),
              onTap: () {
                Navigator.pop(context);
                context.go('/admin/analytics');
              },
            ),
            ListTile(
              leading: const Icon(Icons.summarize_outlined),
              title: const Text('Reports'),
              onTap: () {
                Navigator.pop(context);
                context.go('/admin/reports');
              },
            ),
            ListTile(
              leading: const Icon(Icons.campaign_outlined),
              title: const Text('Announcements'),
              onTap: () {
                Navigator.pop(context);
                context.go('/admin/announcements');
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                context.go('/admin/settings');
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_outlined),
              title: const Text('Profile'),
              onTap: () {
                Navigator.pop(context);
                context.go('/admin/profile');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final String? route;
  const _NavItem(this.label, this.icon, this.route);
}
