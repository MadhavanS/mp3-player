import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists recent YouTube lookup queries (most recent first).
class YoutubeSearchHistoryStore {
  YoutubeSearchHistoryStore._();

  static const _prefsKey = 'youtube_search_history_v1';
  static const maxEntries = 12;

  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => e.toString().trim())
          .where((q) => q.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Future<List<String>> remember(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return load();

    final existing = await load();
    final next = [
      trimmed,
      for (final q in existing)
        if (q.toLowerCase() != trimmed.toLowerCase()) q,
    ];
    final capped = next.take(maxEntries).toList(growable: false);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(capped));
    return capped;
  }

  static Future<void> remove(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final lower = trimmed.toLowerCase();
    final next = (await load())
        .where((q) => q.toLowerCase() != lower)
        .toList(growable: false);
    final prefs = await SharedPreferences.getInstance();
    if (next.isEmpty) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, jsonEncode(next));
    }
  }
}
