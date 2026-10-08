import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'app/app_theme.dart';
import 'app/router.dart';
import 'services/push_service.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'firebase_options.dart';
import 'widgets/app_root_wrapper.dart';

Future<void> main() async {
  // Move all initialization inside runZonedGuarded to avoid zone mismatch
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      if (kIsWeb) {
        // Keep each browser tab's sign-in separate (sessionStorage), so one
        // browser can have admin, staff, finance and parishioner signed in
        // side by side in different tabs. The default (LOCAL) shares one
        // sign-in across every tab. Trade-off: closing a tab signs it out.
        try {
          await FirebaseAuth.instance.setPersistence(Persistence.SESSION);
        } catch (e) {
          debugPrint('Could not set per-tab auth persistence: $e');
        }
      }
      if (!kIsWeb) {
        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: true,
        );
      }
      await Hive.initFlutter();
      await PushService.init();

      // Crashlytics: only supported on iOS/Android. Skip on web and Windows to avoid
      // 'pluginConstants['isCrashlyticsCollectionEnabled'] != null' assertion.
      final useCrashlytics =
          !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android);
      if (useCrashlytics) {
        if (!kReleaseMode) {
          await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
            false,
          );
        }
        FlutterError.onError =
            FirebaseCrashlytics.instance.recordFlutterFatalError;
        PlatformDispatcher.instance.onError = (error, stack) {
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
          return true;
        };
      }

      runApp(const ProviderScope(child: MyApp()));
    },
    (error, stack) {
      final useCrashlytics =
          !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android);
      if (useCrashlytics) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      }
      debugPrint('Uncaught error: $error');
      debugPrint('Stack trace: $stack');
    },
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = createRouter();

    return MaterialApp.router(
      title: 'Holy Rosary',
      theme: buildAppTheme(),
      themeMode: ThemeMode.light,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      builder: (context, child) => AppRootWrapper(child: child),
    );
  }
}
