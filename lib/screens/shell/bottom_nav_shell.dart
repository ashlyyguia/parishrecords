import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/notification_provider.dart';

class BottomNavShell extends ConsumerWidget {
  final Widget child;
  const BottomNavShell({super.key, required this.child});

  static const _routes = [
    '/home',
    '/records',
    '/records/certificates',
    '/notifications',
    '/profile',
  ];

  int _indexFromLocation(String location) {
    // Certificates tab should match its more specific routes first
    if (location.startsWith('/records/certificates') ||
        location.startsWith('/records/certificate-request')) {
      return 2;
    }
    for (int i = 0; i < _routes.length; i++) {
      if (location.startsWith(_routes[i])) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _indexFromLocation(location);
    final unreadStreamAsync = ref.watch(unreadNotificationsCountStreamProvider);
    final unread = unreadStreamAsync.maybeWhen(data: (v) => v, orElse: () => 0);

    ref.listen<AsyncValue<int>>(unreadNotificationsCountStreamProvider, (
      previous,
      next,
    ) {
      final prevCount =
          previous?.maybeWhen(data: (v) => v, orElse: () => 0) ?? 0;
      final currentCount = next.maybeWhen(data: (v) => v, orElse: () => 0);
      if (currentCount > prevCount && prevCount != 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              currentCount == 1
                  ? 'You have a new notification'
                  : 'You have $currentCount unread notifications',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) {
          context.go(_routes[i]);
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            selectedIcon: const Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          const NavigationDestination(
            icon: Icon(Icons.folder_copy_outlined),
            selectedIcon: Icon(Icons.folder_copy),
            label: 'Records',
          ),
          const NavigationDestination(
            icon: Icon(Icons.request_page_outlined),
            selectedIcon: Icon(Icons.request_page),
            label: 'Certificates',
          ),
          NavigationDestination(
            icon: _buildNotificationIcon(unread, false),
            selectedIcon: _buildNotificationIcon(unread, true),
            label: 'Notifications',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationIcon(int unread, bool selected) {
    final baseIcon = Icon(
      selected ? Icons.notifications : Icons.notifications_outlined,
    );
    if (unread <= 0) return baseIcon;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        baseIcon,
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
            ),
            constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
            child: Center(
              child: Text(
                unread > 9 ? '9+' : '$unread',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
