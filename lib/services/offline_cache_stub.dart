import 'dart:convert';

class OfflineCache {
  static final Map<String, String> _mem = <String, String>{};

  static Future<String?> readString(String key) async {
    return _mem[key];
  }

  static Future<void> writeString(String key, String value) async {
    _mem[key] = value;
  }

  static Future<void> delete(String key) async {
    _mem.remove(key);
  }

  static Future<dynamic> readJson(String key) async {
    final raw = await readString(key);
    if (raw == null) return null;
    return json.decode(raw);
  }

  static Future<void> writeJson(String key, Object value) async {
    await writeString(key, json.encode(value));
  }
}
