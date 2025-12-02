import 'package:hive_flutter/hive_flutter.dart';
import 'dart:developer' as developer;

class LocalStorageService {
  static const usersBox = 'users_box';
  static const recordsBox = 'records_box';
  static const notificationsBox = 'notifications_box';
  static const logsBox = 'logs_box';
  static const settingsBox = 'settings_box';
  static const syncQueueBox = 'sync_queue_box';
  static const requestsBox = 'requests_box';
  static const auditsBox = 'audits_box';
  static bool _initialized = false;

  static Future<void> init() async {
    try {
      if (!_initialized) {
        await Hive.initFlutter();
        _initialized = true;
      }

      // List of all boxes to initialize
      final boxes = [
        usersBox,
        recordsBox,
        notificationsBox,
        logsBox,
        settingsBox,
        syncQueueBox,
        requestsBox,
        auditsBox,
      ];

      // Open each box with error handling
      for (final boxName in boxes) {
        await _openBoxSafely(boxName);
      }

      developer.log('✅ All Hive boxes initialized successfully');
    } catch (e) {
      developer.log('❌ Error initializing Hive: $e');
      rethrow;
    }
  }

  static Future<void> _openBoxSafely(String boxName) async {
    try {
      if (!Hive.isBoxOpen(boxName)) {
        await Hive.openBox(boxName);
        developer.log('📦 Opened Hive box: $boxName');
      }
    } catch (e) {
      developer.log('⚠️ Error opening box $boxName: $e');

      // If it's a lock error, try to recover
      if (e.toString().contains('lock failed') ||
          e.toString().contains('locked')) {
        developer.log('🔄 Attempting to recover from lock error for $boxName');

        // Wait a bit and try again
        await Future.delayed(const Duration(milliseconds: 500));

        try {
          if (!Hive.isBoxOpen(boxName)) {
            await Hive.openBox(boxName);
            developer.log('✅ Successfully recovered box: $boxName');
          }
        } catch (retryError) {
          developer.log('❌ Failed to recover box $boxName: $retryError');
          // Continue with other boxes instead of failing completely
        }
      } else {
        rethrow;
      }
    }
  }

  static Future<void> clearAll() async {
    try {
      if (Hive.isBoxOpen(usersBox)) {
        await Hive.box(usersBox).clear();
      }
      if (Hive.isBoxOpen(recordsBox)) {
        await Hive.box(recordsBox).clear();
      }
      if (Hive.isBoxOpen(notificationsBox)) {
        await Hive.box(notificationsBox).clear();
      }
      if (Hive.isBoxOpen(logsBox)) {
        await Hive.box(logsBox).clear();
      }
      if (Hive.isBoxOpen(settingsBox)) {
        await Hive.box(settingsBox).clear();
      }
      if (Hive.isBoxOpen(syncQueueBox)) {
        await Hive.box(syncQueueBox).clear();
      }
      if (Hive.isBoxOpen(requestsBox)) {
        await Hive.box(requestsBox).clear();
      }
      if (Hive.isBoxOpen(auditsBox)) {
        await Hive.box(auditsBox).clear();
      }
      developer.log('🧹 All Hive boxes cleared successfully');
    } catch (e) {
      developer.log('❌ Error clearing Hive boxes: $e');
    }
  }

  static Future<void> closeAll() async {
    try {
      final boxes = [
        usersBox,
        recordsBox,
        notificationsBox,
        logsBox,
        settingsBox,
        syncQueueBox,
        requestsBox,
        auditsBox,
      ];

      for (final boxName in boxes) {
        if (Hive.isBoxOpen(boxName)) {
          await Hive.box(boxName).close();
          developer.log('📦 Closed Hive box: $boxName');
        }
      }

      developer.log('✅ All Hive boxes closed successfully');
    } catch (e) {
      developer.log('❌ Error closing Hive boxes: $e');
    }
  }
}
