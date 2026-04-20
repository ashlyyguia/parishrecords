import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/record.dart';
import '../providers/auth_provider.dart';
import '../screens/admin/enhanced_admin_shell.dart';
import '../screens/admin/pages/announcements_page.dart';
import '../screens/admin/pages/audit_logs_page.dart';
import '../screens/admin/pages/integrations_page.dart';
import '../screens/admin/pages/notifications_page.dart';
import '../screens/admin/pages/ocr_queue_page.dart';
import '../screens/admin/pages/admin_finance_page.dart';
import '../screens/admin/pages/enhanced_admin_dashboard_page.dart';
import '../screens/admin/pages/admin_user_management_page.dart';
import '../screens/admin/pages/admin_parishioners_page.dart';
import '../screens/admin/pages/settings_page.dart';
import '../screens/admin/pages/records_page.dart';
import '../screens/admin/pages/reports_page.dart';
import '../screens/admin/pages/requests_center_page.dart';
import '../screens/admin/pages/system_health_page.dart';
import '../screens/finance/finance_shell.dart';
import '../screens/finance/pages/donations_ledger_page.dart';
import '../screens/finance/pages/finance_dashboard_page.dart';
import '../screens/finance/pages/finance_reconcile_page.dart';
import '../screens/finance/pages/finance_reports_page.dart';
import '../screens/login/forgot_password_screen.dart';
import '../screens/login/login_screen.dart';
import '../screens/login/register_screen.dart';
import '../screens/login/verify_code_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/landing/landing_shell.dart';
import '../screens/landing/home_section.dart';
import '../screens/landing/about_section.dart';
import '../screens/landing/mass_time_section.dart';
import '../screens/landing/events_section.dart';
import '../screens/landing/donations_section.dart';
import '../screens/landing/announcements_section.dart';
import '../screens/landing/contact_section.dart';
import '../screens/records/certificate_request_form_screen.dart';
import '../screens/records/certificate_requests_list_screen.dart';
import '../screens/records/confirmation_form_screen.dart';
import '../screens/records/death_form_screen.dart';
import '../screens/records/enhanced_baptism_form_screen.dart';
import '../screens/records/marriage_form_screen.dart';
import '../screens/records/record_detail_screen.dart';
import '../screens/records/record_form_screen.dart';
import '../screens/records/records_list_screen.dart';

import '../screens/splash/splash_screen.dart';
import '../screens/staff/pages/staff_households_page.dart';
import '../screens/staff/pages/staff_household_detail_page.dart';
import '../screens/staff/pages/staff_ocr_sacrament_match_page.dart';
import '../screens/staff/pages/staff_dashboard_page.dart';
import '../screens/staff/pages/staff_ocr_preprocess_page.dart';
import '../screens/staff/pages/staff_ocr_upload_page.dart';
import '../screens/staff/pages/staff_ocr_verify_page.dart';
import '../screens/staff/pages/staff_requests_inbox_page.dart';
import '../screens/staff/pages/staff_records_page.dart';
import '../screens/staff/pages/staff_schedule_page.dart';
import '../screens/staff/staff_shell.dart';
import '../screens/user/user_household_list_screen.dart';
import '../screens/user/user_add_household_screen.dart';
import '../screens/user/user_edit_household_screen.dart';
import '../screens/user/user_household_detail_screen.dart';
import '../screens/user/user_add_family_member_screen.dart';
import '../screens/user/user_member_detail_screen.dart';
import '../screens/user/user_ocr_sacrament_link_screen.dart';
import '../screens/user/dashboard_screen.dart';
import '../screens/user/user_donations_screen.dart';
import '../screens/user/user_shell.dart';
import '../screens/user/user_profile_household_screen.dart';
import '../screens/user/user_request_detail_screen.dart';
import '../screens/user/user_requests_list_screen.dart';
import '../screens/user/user_sacraments_screen.dart';
import '../widgets/app_loading_screen.dart';

GoRouter createRouter() {
  final isMobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);
  return GoRouter(
    initialLocation: isMobile ? '/splash' : '/',
    errorBuilder: (context, state) => const NotFoundScreen(),
    routes: [
      // Public landing pages with shared navbar shell
      ShellRoute(
        builder: (context, state, child) => LandingShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomeSection()),
          GoRoute(
            path: '/about',
            builder: (context, state) => const AboutSection(),
          ),
          GoRoute(
            path: '/mass-time',
            builder: (context, state) => const MassTimeSection(),
          ),
          GoRoute(
            path: '/events',
            builder: (context, state) => const EventsSection(),
          ),
          GoRoute(
            path: '/donations',
            builder: (context, state) => const DonationsSection(),
          ),
          GoRoute(
            path: '/announcements',
            builder: (context, state) => const AnnouncementsSection(),
          ),
          GoRoute(
            path: '/contact',
            builder: (context, state) => const ContactSection(),
          ),
        ],
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const _DashboardRedirectScreen(),
      ),
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
      ShellRoute(
        builder: (context, state, child) =>
            _ParishionerGate(child: UserShell(child: child)),
        routes: [
          GoRoute(
            path: '/home', // Keep /home for backwards compatibility/redirects
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/user/dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/user/notifications',
            builder: (context, state) => const NotificationsScreen(),
          ),
          GoRoute(
            path: '/user/profile',
            builder: (context, state) => const UserProfileHouseholdScreen(),
          ),
          GoRoute(
            path: '/user/donations',
            builder: (context, state) => const UserDonationsScreen(),
          ),
          GoRoute(
            path: '/user/requests',
            builder: (context, state) => const UserRequestsListScreen(),
          ),
          GoRoute(
            path: '/user/requests/:id',
            builder: (context, state) => UserRequestDetailScreen(
              requestId: state.pathParameters['id'] ?? '',
            ),
          ),
          GoRoute(
            path: '/user/sacraments',
            builder: (context, state) => const UserSacramentsScreen(),
          ),
          GoRoute(
            path: '/user/households',
            builder: (context, state) => const UserHouseholdListScreen(),
          ),
          GoRoute(
            path: '/user/households/new',
            builder: (context, state) => const UserAddHouseholdScreen(),
          ),
          GoRoute(
            path: '/user/households/:id',
            builder: (context, state) => UserHouseholdDetailScreen(
              householdId: state.pathParameters['id'] ?? '',
            ),
          ),
          GoRoute(
            path: '/user/households/:id/edit',
            builder: (context, state) => UserEditHouseholdScreen(
              householdId: state.pathParameters['id'] ?? '',
            ),
          ),
          GoRoute(
            path: '/user/households/:id/members/new',
            builder: (context, state) => UserAddFamilyMemberScreen(
              householdId: state.pathParameters['id'] ?? '',
            ),
          ),
          GoRoute(
            path: '/user/households/:householdId/members/:memberId',
            builder: (context, state) => UserMemberDetailScreen(
              householdId: state.pathParameters['householdId'] ?? '',
              memberId: state.pathParameters['memberId'] ?? '',
            ),
          ),
          GoRoute(
            path: '/user/households/:id/ocr-link',
            builder: (context, state) => UserOcrSacramentLinkScreen(
              householdId: state.pathParameters['id'] ?? '',
            ),
          ),
          GoRoute(
            path: '/donate',
            builder: (context, state) => const DonationsSection(),
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

      // Finance shell with role-based access and nested pages
      GoRoute(
        path: '/finance',
        redirect: (context, state) => '/finance/dashboard',
      ),
      ShellRoute(
        builder: (context, state, child) =>
            _FinanceGate(child: FinanceShell(child: child)),
        routes: [
          GoRoute(
            path: '/finance/dashboard',
            name: 'finance_dashboard',
            builder: (context, state) => const FinanceDashboardPage(),
          ),
          GoRoute(
            path: '/finance/donations',
            name: 'finance_ledger',
            builder: (context, state) => const DonationsLedgerPage(),
          ),
          GoRoute(
            path: '/finance/reconcile',
            name: 'finance_reconcile',
            builder: (context, state) => const FinanceReconcilePage(),
          ),
          GoRoute(
            path: '/finance/reports',
            name: 'finance_reports',
            builder: (context, state) => const FinanceReportsPage(),
          ),
          GoRoute(
            path: '/finance/notifications',
            builder: (context, state) => const NotificationsScreen(),
          ),
          GoRoute(
            path: '/finance/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),

      // Staff shell with role-based access and nested pages
      GoRoute(path: '/staff', redirect: (context, state) => '/staff/dashboard'),
      ShellRoute(
        builder: (context, state, child) =>
            _StaffGate(child: StaffShell(child: child)),
        routes: [
          GoRoute(
            path: '/staff/households/:id/ocr-match',
            builder: (context, state) => StaffOcrSacramentMatchPage(
              householdId: state.pathParameters['id'] ?? '',
            ),
          ),
          GoRoute(
            path: '/staff/households',
            builder: (context, state) => const StaffHouseholdsPage(),
          ),
          GoRoute(
            path: '/staff/households/:id',
            builder: (context, state) => StaffHouseholdDetailPage(
              householdId: state.pathParameters['id'] ?? '',
            ),
          ),
          GoRoute(
            path: '/staff/dashboard',
            builder: (context, state) => const StaffDashboardPage(),
          ),
          GoRoute(
            path: '/staff/requests',
            builder: (context, state) => const StaffRequestsInboxPage(),
          ),
          GoRoute(
            path: '/staff/records',
            builder: (context, state) => const StaffRecordsPage(),
          ),
          GoRoute(
            path: '/staff/ocr/upload',
            builder: (context, state) => const StaffOcrUploadPage(),
          ),
          GoRoute(
            path: '/staff/ocr/preprocess',
            builder: (context, state) => const StaffOcrPreprocessPage(),
          ),
          GoRoute(
            path: '/staff/ocr/verify',
            builder: (context, state) => const StaffOcrVerifyPage(),
          ),
          GoRoute(
            path: '/staff/schedule',
            builder: (context, state) => const StaffSchedulePage(),
          ),
          GoRoute(
            path: '/staff/notifications',
            builder: (context, state) => const NotificationsScreen(),
          ),
          GoRoute(
            path: '/staff/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),

      // Admin web shell with sidebar and nested pages
      GoRoute(path: '/admin', redirect: (context, state) => '/admin/dashboard'),
      ShellRoute(
        builder: (context, state, child) =>
            _AdminGate(child: EnhancedAdminShell(child: child)),
        routes: [
          GoRoute(
            path: '/admin/dashboard',
            builder: (context, state) => const EnhancedAdminDashboardPage(),
          ),
          GoRoute(
            path: '/admin/users',
            builder: (context, state) => const AdminUserManagementPage(),
          ),
          GoRoute(
            path: '/admin/households',
            builder: (context, state) => const StaffHouseholdsPage(),
          ),
          GoRoute(
            path: '/admin/households/:id',
            builder: (context, state) => StaffHouseholdDetailPage(
              householdId: state.pathParameters['id'] ?? '',
            ),
          ),
          GoRoute(
            path: '/admin/parishioners',
            builder: (context, state) => const AdminParishionersPage(),
          ),
          GoRoute(
            path: '/admin/records',
            builder: (context, state) => const AdminRecordsPage(),
          ),
          GoRoute(
            path: '/admin/records/:id',
            builder: (context, state) =>
                RecordDetailScreen(recordId: state.pathParameters['id'] ?? ''),
          ),
          GoRoute(
            path: '/admin/requests',
            builder: (context, state) => const AdminRequestsCenterPage(),
          ),
          GoRoute(
            path: '/admin/ocr',
            builder: (context, state) => const AdminOcrQueuePage(),
          ),
          GoRoute(
            path: '/admin/finance',
            builder: (context, state) => const AdminFinancePage(),
          ),
          GoRoute(
            path: '/admin/reports',
            builder: (context, state) => const AdminReportsPage(),
          ),
          GoRoute(
            path: '/admin/system',
            builder: (context, state) => const AdminSystemHealthPage(),
          ),
          GoRoute(
            path: '/admin/audit',
            builder: (context, state) => const AdminAuditLogsPage(),
          ),
          GoRoute(
            path: '/admin/integrations',
            builder: (context, state) => const AdminIntegrationsPage(),
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
            path: '/admin/settings',
            builder: (context, state) => const AdminSettingsPage(),
          ),
          GoRoute(
            path: '/admin/profile',
            builder: (context, state) => const ProfileScreen(),
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
        ],
      ),
    ],
  );
}

class _FinanceGate extends ConsumerStatefulWidget {
  final Widget child;
  const _FinanceGate({required this.child});

  @override
  ConsumerState<_FinanceGate> createState() => _FinanceGateState();
}

class _FinanceGateState extends ConsumerState<_FinanceGate> {
  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    if (!auth.initialized) {
      return const AppLoadingScreen(message: 'Loading...');
    }
    if (auth.user == null) {
      return const LoginScreen();
    }
    final role = auth.user!.role.trim().toLowerCase();
    final allowed = role == 'finance' || role == 'admin';
    if (!allowed) {
      return const _FinanceAccessDenied();
    }
    return widget.child;
  }
}

class _FinanceAccessDenied extends StatelessWidget {
  const _FinanceAccessDenied();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Finance Access')),
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
                      'Finance access required',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Ask an administrator to set your role to finance.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => context.go('/home'),
                      child: const Text('Go to Home'),
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
                      onPressed: () => context.go('/admin/dashboard'),
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
      return const AppLoadingScreen(message: 'Loading...');
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

    if (!isRoleAdmin) {
      return const _AdminAccessDenied();
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

class _DashboardRedirectScreen extends ConsumerWidget {
  const _DashboardRedirectScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      if (!auth.initialized) return;
      if (auth.user == null) {
        context.go('/login');
        return;
      }

      final role = auth.user!.role.trim().toLowerCase();
      // Redirect based on actual role, not default to staff
      if (role == 'admin') {
        context.go('/admin/dashboard');
      } else if (role == 'finance') {
        context.go('/finance/dashboard');
      } else if (role == 'staff') {
        context.go('/staff/dashboard');
      } else {
        context.go('/home');
      }
    });

    return const AppLoadingScreen(message: 'Redirecting...');
  }
}

class _StaffGate extends ConsumerStatefulWidget {
  final Widget child;
  const _StaffGate({required this.child});

  @override
  ConsumerState<_StaffGate> createState() => _StaffGateState();
}

class _StaffGateState extends ConsumerState<_StaffGate> {
  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    if (!auth.initialized) {
      return const AppLoadingScreen(message: 'Loading...');
    }
    if (auth.user == null) {
      return const LoginScreen();
    }
    final role = auth.user!.role.trim().toLowerCase();
    final allowed = role == 'staff' || role == 'admin';
    if (!allowed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        context.go('/home');
      });
      return const AppLoadingScreen(message: 'Redirecting...');
    }
    return widget.child;
  }
}

class _ParishionerGate extends ConsumerWidget {
  final Widget child;
  const _ParishionerGate({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (!auth.initialized) {
      return const AppLoadingScreen(message: 'Loading...');
    }
    if (auth.user == null) {
      return const LoginScreen();
    }

    final role = auth.user!.role.trim().toLowerCase();
    final isParishioner =
        role.isEmpty || role == 'parishioner' || role == 'user';
    if (!isParishioner) {
      return const _DashboardRedirectScreen();
    }

    return child;
  }
}
