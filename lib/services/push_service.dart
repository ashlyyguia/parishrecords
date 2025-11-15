import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

class PushService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static bool _inited = false;

  // Replace with your Web Push certificate (VAPID) key from Firebase Console
  // This key is public and safe to embed in client code.
  static const String _webVapidKey = String.fromEnvironment(
    'WEB_VAPID_KEY',
    defaultValue: '',
  );

  static Future<void> init() async {
    if (_inited) return;
    _inited = true;
    // Request permissions (iOS/Web), Android 13+ uses POST_NOTIFICATIONS runtime permission
    await _requestPermission();

    // Get and persist FCM token for the current user
    await _refreshAndSaveToken();
    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      await _saveToken(token);
    });

    // Foreground message handler
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // You can show an in-app banner or SnackBar here if needed
      // Keeping it lightweight: state is updated via Firestore listener you already have
    });

    // Register background handler (no-op on web)
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );
    }

    // Subscribe to topics (mobile only) so you can send via Firebase Console without a backend
    if (!kIsWeb) {
      try {
        await _messaging.subscribeToTopic('all');
        // Try to subscribe to role topic if present
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final snap = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
          final role = (snap.data()?['role']?.toString() ?? '').trim();
          if (role.isNotEmpty) {
            await _messaging.subscribeToTopic('role_${role.toLowerCase()}');
          }
        }
      } catch (_) {}
    }
  }

  static Future<void> _requestPermission() async {
    if (kIsWeb) {
      // Zero-cost path: skip web FCM to avoid requiring a service worker
      return;
    }
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
  }

  static Future<void> _refreshAndSaveToken() async {
    if (kIsWeb) return; // Skip web token handling in zero-cost mode
    try {
      final token = await _messaging.getToken(
        vapidKey: kIsWeb && _webVapidKey.isNotEmpty ? _webVapidKey : null,
      );
      if (token != null) await _saveToken(token);
    } catch (_) {}
  }

  static Future<void> _saveToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    await ref.set({
      'fcmTokens': {token: FieldValue.serverTimestamp()},
    }, SetOptions(merge: true));
  }
}

// Top-level background handler function for Android/iOS
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized in background isolate
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {}
  // Keep minimal; app already syncs notifications via Firestore
}
