import 'dart:async';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart' as app;
import 'app/bootstrap.dart';

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      await bootstrap();
      runApp(const ProviderScope(child: app.MyApp()));
    },
    (error, stack) {
      // Report non-Flutter errors
      if (isCrashlyticsSupported) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      }
    },
  );
}

