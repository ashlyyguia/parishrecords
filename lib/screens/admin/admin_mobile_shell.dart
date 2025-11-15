import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AdminMobileShell extends StatelessWidget {
  final Widget child;
  const AdminMobileShell({super.key, required this.child});

  static const _routes = <_NavItem>[
    _NavItem('Home', Icons.home_outlined, '/admin/overview'),
    _NavItem('Records', Icons.folder_copy_outlined, '/admin/records'),
    _NavItem('Profile', Icons.person_outline, '/admin/settings'),
  ];

  int _indexFromLocation(String location) {
    for (int i = 0; i < _routes.length; i++) {
      if (location.startsWith(_routes[i].route)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _indexFromLocation(location);

    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) {
          context.go(_routes[i].route);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.folder_copy_outlined), selectedIcon: Icon(Icons.folder_copy), label: 'Records'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
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
