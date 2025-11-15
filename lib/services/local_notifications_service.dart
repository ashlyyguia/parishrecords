import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationsService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _inited = false;

  static Future<void> init() async {
    if (_inited || kIsWeb) return; // Web not handled here

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );

    await _plugin.initialize(initSettings);

    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'parish_default',
        'Parish Notifications',
        description: 'General notifications',
        importance: Importance.high,
      );
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(channel);
    }

    _inited = true;
  }

  static Future<void> show(String id, String title, String body) async {
    if (kIsWeb) return; // handled separately if needed
    const androidDetails = AndroidNotificationDetails(
      'parish_default',
      'Parish Notifications',
      channelDescription: 'General notifications',
      priority: Priority.high,
      importance: Importance.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    // Use a stable int hash for id
    final intId = id.hashCode & 0x7fffffff;
    await _plugin.show(intId, title, body, details);
  }
}
