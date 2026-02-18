import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ThemeModeState {
  final ThemeMode mode;
  const ThemeModeState(this.mode);
}

class ThemeModeNotifier extends Notifier<ThemeModeState> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  @override
  ThemeModeState build() {
    ref.onDispose(() {
      _sub?.cancel();
    });

    _listenRemote();
    return const ThemeModeState(ThemeMode.system);
  }

  void _listenRemote() {
    _sub?.cancel();
    _sub = FirebaseFirestore.instance
        .collection('settings')
        .doc('app')
        .snapshots()
        .listen((doc) {
          final s = (doc.data()?['themeMode']?.toString() ?? '').toLowerCase();
          if (s.isNotEmpty) {
            state = ThemeModeState(_fromString(s));
          }
        });
  }

  Future<void> setMode(ThemeMode mode) async {
    state = ThemeModeState(mode);
    await FirebaseFirestore.instance.collection('settings').doc('app').set({
      'themeMode': _toString(mode),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String _toString(ThemeMode m) {
    switch (m) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
        return 'system';
    }
  }

  ThemeMode _fromString(String s) {
    switch (s) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeModeState>(
  ThemeModeNotifier.new,
);
