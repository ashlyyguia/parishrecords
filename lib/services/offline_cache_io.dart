import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:path_provider/path_provider.dart';

class OfflineCache {
  static const Duration _timeout = Duration(seconds: 3);

  static String _sanitize(String key) {
    return key.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  static Future<Directory> _cacheDir() async {
    Directory base;
    try {
      base = await getApplicationDocumentsDirectory().timeout(
        _timeout,
        onTimeout: () => throw TimeoutException('cache dir init timed out'),
      );
    } catch (_) {
      base = Directory.systemTemp;
    }

    final dir = Directory(
      '${base.path}${Platform.pathSeparator}parishrecord_cache',
    );
    try {
      final exists = await dir.exists().timeout(
        _timeout,
        onTimeout: () => throw TimeoutException('cache dir exists timed out'),
      );
      if (!exists) {
        await dir
            .create(recursive: true)
            .timeout(
              _timeout,
              onTimeout: () =>
                  throw TimeoutException('cache dir create timed out'),
            );
      }
    } catch (_) {
      // If anything goes wrong, fallback to systemTemp without further IO
      return Directory.systemTemp;
    }

    return dir;
  }

  static Future<File> _fileForKey(String key) async {
    final dir = await _cacheDir();
    final filename = '${_sanitize(key)}.json';
    return File('${dir.path}${Platform.pathSeparator}$filename');
  }

  static Future<String?> readString(String key) async {
    try {
      final f = await _fileForKey(key);
      final exists = await f.exists().timeout(_timeout, onTimeout: () => false);
      if (!exists) return null;
      return await f.readAsString().timeout(
        _timeout,
        onTimeout: () => throw TimeoutException('cache read timed out'),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeString(String key, String value) async {
    try {
      final f = await _fileForKey(key);
      await f
          .writeAsString(value, flush: true)
          .timeout(
            _timeout,
            onTimeout: () => throw TimeoutException('cache write timed out'),
          );
    } catch (_) {}
  }

  static Future<void> delete(String key) async {
    try {
      final f = await _fileForKey(key);
      final exists = await f.exists().timeout(_timeout, onTimeout: () => false);
      if (exists) {
        await f.delete().timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('cache delete timed out'),
        );
      }
    } catch (_) {}
  }

  static Future<dynamic> readJson(String key) async {
    final raw = await readString(key);
    if (raw == null) return null;
    try {
      return json.decode(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeJson(String key, Object value) async {
    await writeString(key, json.encode(value));
  }
}
