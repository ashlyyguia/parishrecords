import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/record.dart';
import '../providers/auth_provider.dart';
import '../screens/admin/admin_shell.dart';
import '../screens/admin/pages/analytics_page.dart';
import '../screens/admin/pages/backup_page.dart';
import '../screens/admin/pages/certificates_page.dart';
import '../screens/admin/pages/notifications_page.dart';
import '../screens/admin/pages/overview_page.dart';
import '../screens/admin/pages/records_page.dart';
import '../screens/admin/pages/settings_page.dart';
import '../screens/admin/pages/users_page.dart';
import '../screens/admin/pages/announcements_page.dart';
import '../screens/dashboard/enhanced_dashboard_screen.dart';
import '../screens/login/forgot_password_screen.dart';
import '../screens/login/login_screen.dart';
import '../screens/login/register_screen.dart';
import '../screens/login/verify_code_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/public_announcements_list_screen.dart';
import '../screens/public_announcement_detail_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/records/certificate_request_form_screen.dart';
import '../screens/records/certificate_requests_list_screen.dart';
import '../screens/records/confirmation_form_screen.dart';
import '../screens/records/death_form_screen.dart';
import '../screens/records/enhanced_baptism_form_screen.dart';
import '../screens/records/marriage_form_screen.dart';
import '../screens/records/record_detail_screen.dart';
import '../screens/records/record_form_screen.dart';
import '../screens/records/records_list_screen.dart';
import '../screens/shell/bottom_nav_shell.dart';
import '../screens/splash/splash_screen.dart';

GoRouter createRouter() {
  return GoRouter(
    // For web, we want the public announcements landing page as the default
    // entry point instead of the login screen.
    initialLocation: '/announcements',
    errorBuilder: (context, state) => const NotFoundScreen(),
    routes: [
      // Optional: keep splash route if you still navigate to it elsewhere
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/verify-code',
        builder: (context, state) => const VerifyCodeScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      // Public announcements landing (no auth required)
      GoRoute(
        path: '/announcements',
        builder: (context, state) => const PublicAnnouncementsListScreen(),
      ),
      GoRoute(
        path: '/announcements/:id',
        builder: (context, state) => PublicAnnouncementDetailScreen(
          announcementId: state.pathParameters['id'] ?? '',
        ),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            _AuthGate(child: BottomNavShell(child: child)),
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const EnhancedDashboardScreen(),
          ),
          GoRoute(
            path: '/records',
            builder: (context, state) => const RecordsListScreen(),
          ),
          GoRoute(
            path: '/records/certificates',
            builder: (context, state) => const CertificateRequestsListScreen(),
          ),
          GoRoute(
            path: '/records/new',
            builder: (context, state) => const RecordFormScreen(),
          ),
          GoRoute(
            path: '/records/new/baptism',
            builder: (context, state) {
              final extra = state.extra;
              return EnhancedBaptismFormScreen(
                existing: extra is ParishRecord ? extra : null,
                startWithOcr: extra is String && extra == 'ocr',
              );
            },
          ),
          GoRoute(
            path: '/records/new/marriage',
            builder: (context, state) {
              final extra = state.extra;
              return MarriageFormScreen(
                existing: extra is ParishRecord ? extra : null,
                startWithOcr: extra is String && extra == 'ocr',
              );
            },
          ),
          GoRoute(
            path: '/records/new/confirmation',
            builder: (context, state) {
              final extra = state.extra;
              return ConfirmationFormScreen(
                existing: extra is ParishRecord ? extra : null,
                startWithOcr: extra is String && extra == 'ocr',
              );
            },
          ),
          GoRoute(
            path: '/records/new/death',
            builder: (context, state) {
              final extra = state.extra;
              return DeathFormScreen(
                existing: extra is ParishRecord ? extra : null,
                startWithOcr: extra is String && extra == 'ocr',
              );
            },
          ),
          GoRoute(
            path: '/records/enhanced-baptism',
            builder: (context, state) {
              final extra = state.extra;
              return EnhancedBaptismFormScreen(
                existing: extra is ParishRecord ? extra : null,
              );
            },
          ),
          GoRoute(
            path: '/records/certificate-request',
            builder: (context, state) => CertificateRequestFormScreen(
              initialRecordType: state.extra is String
                  ? state.extra as String
                  : null,
            ),
          ),
          GoRoute(
            path: '/records/:id',
            builder: (context, state) =>
                RecordDetailScreen(recordId: state.pathParameters['id'] ?? ''),
          ),
          GoRoute(
            path: '/records/:id/edit',
            builder: (context, state) {
              // The edit screen will receive an existing record via state.extra when navigated from list
              final existing = state.extra;
              return RecordFormScreen(existing: existing as dynamic);
            },
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: '/notifications',
            builder: (context, state) => const NotificationsScreen(),
          ),
        ],
      ),
      // Admin web shell with sidebar and nested pages
      GoRoute(path: '/admin', redirect: (context, state) => '/admin/overview'),
      ShellRoute(
        builder: (context, state, child) =>
            _AdminGate(child: AdminShell(child: child)),
        routes: [
          GoRoute(
            path: '/admin/overview',
            builder: (context, state) => const AdminOverviewPage(),
          ),
          GoRoute(
            path: '/admin/users',
            builder: (context, state) => const AdminUsersPage(),
          ),
          GoRoute(
            path: '/admin/analytics',
            builder: (context, state) => const AdminAnalyticsPage(),
          ),
          GoRoute(
            path: '/admin/records',
            builder: (context, state) {
              final extra = state.extra;
              return AdminRecordsPage(
                initialFilter: extra is Map<String, dynamic> ? extra : null,
              );
            },
          ),
          GoRoute(
            path: '/admin/records/:id',
            builder: (context, state) =>
                RecordDetailScreen(recordId: state.pathParameters['id'] ?? ''),
          ),
          GoRoute(
            path: '/admin/certificates',
            builder: (context, state) => const AdminCertificatesPage(),
          ),
          GoRoute(
            path: '/admin/notifications',
            builder: (context, state) => const AdminNotificationsPage(),
          ),
          GoRoute(
            path: '/admin/announcements',
            builder: (context, state) => const AdminAnnouncementsPage(),
          ),
          GoRoute(
            path: '/admin/records/new/baptism',
            builder: (context, state) {
              final extra = state.extra;
              return EnhancedBaptismFormScreen(
                existing: extra is ParishRecord ? extra : null,
                fromAdmin: true,
              );
            },
          ),
          GoRoute(
            path: '/admin/records/new/marriage',
            builder: (context, state) {
              final extra = state.extra;
              return MarriageFormScreen(
                existing: extra is ParishRecord ? extra : null,
                fromAdmin: true,
              );
            },
          ),
          GoRoute(
            path: '/admin/records/new/confirmation',
            builder: (context, state) {
              final extra = state.extra;
              return ConfirmationFormScreen(
                existing: extra is ParishRecord ? extra : null,
                fromAdmin: true,
              );
            },
          ),
          GoRoute(
            path: '/admin/records/new/death',
            builder: (context, state) {
              final extra = state.extra;
              return DeathFormScreen(
                existing: extra is ParishRecord ? extra : null,
                fromAdmin: true,
              );
            },
          ),
          GoRoute(
            path: '/admin/backup',
            builder: (context, state) => const AdminBackupPage(),
          ),
          GoRoute(
            path: '/admin/settings',
            builder: (context, state) => const AdminSettingsPage(),
          ),
        ],
      ),
    ],
  );
}

class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.search_off, size: 48),
                const SizedBox(height: 12),
                const Text('Page not found'),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed: () => context.go('/login'),
                      child: const Text('Login'),
                    ),
                    OutlinedButton(
                      onPressed: () => context.go('/admin/overview'),
                      child: const Text('Admin Home'),
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
}

class _AdminGate extends ConsumerStatefulWidget {
  final Widget child;
  const _AdminGate({required this.child});

  @override
  ConsumerState<_AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends ConsumerState<_AdminGate> {
  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    if (!auth.initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (auth.user == null) {
      return const LoginScreen();
    }
    final isRoleAdmin = auth.user!.role.trim().toLowerCase() == 'admin';

    if (kDebugMode) {
      debugPrint('Admin Access Check:');
      debugPrint('Role: ${auth.user!.role}');
      debugPrint('Is Role Admin: $isRoleAdmin');
    }

    return widget.child;
  }
}

class _AdminAccessDenied extends ConsumerStatefulWidget {
  const _AdminAccessDenied();

  @override
  ConsumerState<_AdminAccessDenied> createState() => _AdminAccessDeniedState();
}

class _AdminAccessDeniedState extends ConsumerState<_AdminAccessDenied> {
  bool _refreshing = false;

  Future<void> _refreshAccess() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
    });
    try {
      await ref.read(authProvider.notifier).refreshCurrentUser();
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final email = auth.user?.email ?? '';
    final role = auth.user?.role ?? '';
    final uid = auth.user?.id ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Admin Access')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 40),
                    const SizedBox(height: 12),
                    const Text(
                      'Admin access required',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Signed in as: $email\nUID: $uid\nCurrent role: $role',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Ask an administrator to set your account role to admin in Firestore (users/<uid>.role = "admin") or promote your user via the backend script.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        FilledButton(
                          onPressed: _refreshing ? null : _refreshAccess,
                          child: _refreshing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Refresh Access'),
                        ),
                        OutlinedButton(
                          onPressed: () => context.go('/home'),
                          child: const Text('Go to Home'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthGate extends ConsumerWidget {
  final Widget child;
  const _AuthGate({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (!auth.initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (auth.user == null) {
      return const LoginScreen();
    }
    return child;
  }
}
