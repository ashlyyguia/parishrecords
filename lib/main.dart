import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers/auth_provider.dart';
// Removed theme mode provider usage; app uses a single light theme
import 'services/local_storage.dart';
import 'services/sync_service.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'services/push_service.dart';
import 'services/local_notifications_service.dart';
import 'screens/login/login_screen.dart';
import 'screens/dashboard/enhanced_dashboard_screen.dart';
import 'screens/shell/bottom_nav_shell.dart';
import 'screens/records/records_list_screen.dart';
import 'screens/records/record_detail_screen.dart';
import 'screens/ocr/ocr_capture_screen.dart';
import 'screens/notifications/notifications_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/admin/admin_shell.dart';
import 'screens/admin/pages/activity_page.dart';
import 'screens/admin/pages/overview_page.dart';
import 'screens/admin/pages/users_page.dart';
import 'screens/admin/pages/analytics_page.dart';
import 'screens/admin/pages/records_page.dart';
import 'screens/admin/pages/notifications_page.dart';
import 'screens/admin/pages/backup_page.dart';
import 'screens/admin/pages/settings_page.dart';
import 'screens/admin/pages/certificates_page.dart';
import 'screens/records/record_form_screen.dart';
import 'screens/records/marriage_form_screen.dart';
import 'screens/records/confirmation_form_screen.dart';
import 'screens/records/death_form_screen.dart';
import 'screens/records/enhanced_baptism_form_screen.dart';
import 'screens/records/certificate_request_form_screen.dart';
import 'screens/records/ocr_scan_screen.dart';
import 'firebase_options.dart';
import 'screens/login/register_with_invite.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await LocalStorageService.init();
  await PushService.init();
  await LocalNotificationsService.init();
  // Start offline sync orchestrator
  SyncService.start();

  // Crashlytics: handle uncaught errors to avoid killing the process in dev
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true; // prevent crash loop
  };
  if (!kReleaseMode) {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
  }

  runZonedGuarded(
    () {
      runApp(const ProviderScope(child: MyApp()));
    },
    (error, stack) {
      // Report non-Flutter errors
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    },
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

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ThemeData(
      useMaterial3: true,
      visualDensity: VisualDensity.compact,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: const Color(0xFF6C63FF),
            brightness: Brightness.light,
          ).copyWith(
            primary: const Color(0xFF6C63FF),
            secondary: const Color(0xFF7C8DB5),
            surface: Colors.white,
            onSurface: const Color(0xFF1F2430),
          ),
      scaffoldBackgroundColor: const Color(0xFFF6F7FB),
      cardColor: Colors.white,
      textTheme: GoogleFonts.poppinsTextTheme().copyWith(
        headlineLarge: GoogleFonts.merriweather(fontWeight: FontWeight.w700),
        headlineMedium: GoogleFonts.merriweather(fontWeight: FontWeight.w700),
        headlineSmall: GoogleFonts.merriweather(fontWeight: FontWeight.w700),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1F2430),
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF1F2430),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFE6E8EF)),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF2F4F8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: const BorderSide(color: Color(0xFFE6E8EF)),
      ),
      listTileTheme: const ListTileThemeData(
        dense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE6E8EF),
        thickness: 1,
      ),
    );

    // Dark theme removed per request

    final router = GoRouter(
      initialLocation: '/splash',
      errorBuilder: (context, state) => const NotFoundScreen(),
      routes: [
        GoRoute(
          path: '/splash',
          builder: (context, state) => const SplashScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/register',
          builder: (context, state) => const RegisterWithInviteScreen(),
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
              path: '/records/new',
              builder: (context, state) => const RecordFormScreen(),
            ),
            GoRoute(
              path: '/records/new/baptism',
              builder: (context, state) => const EnhancedBaptismFormScreen(),
            ),
            GoRoute(
              path: '/records/new/marriage',
              builder: (context, state) => const MarriageFormScreen(),
            ),
            GoRoute(
              path: '/records/new/confirmation',
              builder: (context, state) => const ConfirmationFormScreen(),
            ),
            GoRoute(
              path: '/records/new/death',
              builder: (context, state) => const DeathFormScreen(),
            ),
            GoRoute(
              path: '/records/enhanced-baptism',
              builder: (context, state) => const EnhancedBaptismFormScreen(),
            ),
            GoRoute(
              path: '/records/certificate-request',
              builder: (context, state) => const CertificateRequestFormScreen(),
            ),
            GoRoute(
              path: '/records/:id',
              builder: (context, state) => RecordDetailScreen(
                recordId: state.pathParameters['id'] ?? '',
              ),
            ),
            GoRoute(
              path: '/records/:id/scan',
              builder: (context, state) => OCRScanScreen(
                recordId: state.pathParameters['id'] ?? '',
              ),
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
              path: '/ocr',
              builder: (context, state) => const OcrCaptureScreen(),
            ),
            GoRoute(
              path: '/notifications',
              builder: (context, state) => const NotificationsScreen(),
            ),
            GoRoute(
              path: '/profile',
              builder: (context, state) => const ProfileScreen(),
            ),
          ],
        ),
        // Admin web shell with sidebar and nested pages
        GoRoute(
          path: '/admin',
          redirect: (context, state) => '/admin/overview',
        ),
        ShellRoute(
          builder: (context, state, child) => _AdminGate(child: AdminShell(child: child)),
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
              path: '/admin/activity',
              builder: (context, state) => const AdminActivityPage(),
            ),
            GoRoute(
              path: '/admin/records',
              builder: (context, state) => const AdminRecordsPage(),
            ),
            GoRoute(
              path: '/admin/certificates',
              builder: (context, state) => const AdminCertificatesPage(),
            ),
            GoRoute(
              path: '/admin/records/new/baptism',
              builder: (context, state) => const EnhancedBaptismFormScreen(),
            ),
            GoRoute(
              path: '/admin/records/new/marriage',
              builder: (context, state) => const MarriageFormScreen(),
            ),
            GoRoute(
              path: '/admin/records/new/confirmation',
              builder: (context, state) => const ConfirmationFormScreen(),
            ),
            GoRoute(
              path: '/admin/records/new/death',
              builder: (context, state) => const DeathFormScreen(),
            ),
            GoRoute(
              path: '/admin/notifications',
              builder: (context, state) => const AdminNotificationsPage(),
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

    return MaterialApp.router(
      title: 'Parish Record',
      theme: theme,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    );
  }
}

class _AdminGate extends ConsumerWidget {
  final Widget child;
  const _AdminGate({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (!auth.initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (auth.user == null) {
      return const LoginScreen();
    }
    final email = (auth.user!.email).toLowerCase();
    final isEmailAdmin = email == 'admin@gmail.com';
    final isRoleAdmin = auth.user!.role == 'admin';
    
    // Debug logging (development only)
    if (kDebugMode) {
      debugPrint('Admin Access Check:');
      debugPrint('Email: $email');
      debugPrint('Role: ${auth.user!.role}');
      debugPrint('Is Email Admin: $isEmailAdmin');
      debugPrint('Is Role Admin: $isRoleAdmin');
    }
    
    if (!(isRoleAdmin || isEmailAdmin)) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.admin_panel_settings, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Access Restricted',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('Admin access required. Current role: ${auth.user!.role}'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/home'),
                child: const Text('Back to Dashboard'),
              ),
            ],
          ),
        ),
      );
    }
    return child;
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
