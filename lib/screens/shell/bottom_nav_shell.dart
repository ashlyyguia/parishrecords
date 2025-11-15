import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/notification_provider.dart';

class BottomNavShell extends ConsumerWidget {
  final Widget child;
  const BottomNavShell({super.key, required this.child});

  static const _routes = ['/home', '/records', '/profile'];

  int _indexFromLocation(String location) {
    for (int i = 0; i < _routes.length; i++) {
      if (location.startsWith(_routes[i])) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _indexFromLocation(location);
    final unread = ref.watch(unreadNotificationsCountProvider);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) {
          context.go(_routes[i]);
        },
        destinations: [
          NavigationDestination(
            icon: unread > 0
                ? Badge(
                    label: Text(unread > 99 ? '99+' : unread.toString()),
                    child: const Icon(Icons.dashboard_outlined),
                  )
                : const Icon(Icons.dashboard_outlined),
            selectedIcon: unread > 0
                ? Badge(
                    label: Text(unread > 99 ? '99+' : unread.toString()),
                    child: const Icon(Icons.dashboard),
                  )
                : const Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          const NavigationDestination(icon: Icon(Icons.folder_copy_outlined), selectedIcon: Icon(Icons.folder_copy), label: 'Records'),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
