import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'recent_list_limits_store.dart';

/// Persists absolute file paths in MRU order (newest first), capped.
class RecentlyPlayedStore {
  RecentlyPlayedStore._();

  static const _key = 'recently_played_paths_v1';

  /// Bumps when persisted recently-played list changes (Library tab refresh).
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static Future<List<String>> loadPaths() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <String>[];
    final limit = await RecentListLimitsStore.loadRecentlyPlayedLimit();
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final list = decoded.cast<String>();
      if (list.length <= limit) return list;
      final trimmed = list.sublist(0, limit);
      await prefs.setString(_key, jsonEncode(trimmed));
      return trimmed;
    } catch (_) {
      return <String>[];
    }
  }

  /// Records [path] as most recently played; trims list to the configured limit.
  static Future<void> recordPlay(String path) async {
    if (path.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    List<String> list = await loadPaths();
    final limit = await RecentListLimitsStore.loadRecentlyPlayedLimit();
    if (list.isNotEmpty && list.first == path) return;
    list.remove(path);
    list.insert(0, path);
    if (list.length > limit) {
      list = list.sublist(0, limit);
    }
    await prefs.setString(_key, jsonEncode(list));
    revision.value++;
  }

  static Future<void> trimToConfiguredLimit() async {
    final prefs = await SharedPreferences.getInstance();
    final list = await loadPaths();
    await prefs.setString(_key, jsonEncode(list));
    revision.value++;
  }
}
