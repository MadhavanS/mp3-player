import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists absolute file paths in MRU order (newest first), capped.
class RecentlyPlayedStore {
  RecentlyPlayedStore._();

  static const _key = 'recently_played_paths_v1';
  static const _maxEntries = 50;

  static Future<List<String>> loadPaths() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.cast<String>();
    } catch (_) {
      return [];
    }
  }

  /// Records [path] as most recently played; trims list to [_maxEntries].
  static Future<void> recordPlay(String path) async {
    if (path.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    List<String> list = await loadPaths();
    if (list.isNotEmpty && list.first == path) return;
    list.remove(path);
    list.insert(0, path);
    if (list.length > _maxEntries) {
      list = list.sublist(0, _maxEntries);
    }
    await prefs.setString(_key, jsonEncode(list));
  }
}
