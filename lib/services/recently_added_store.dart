import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track_item.dart';
import 'music_library_path_key.dart';

/// Records when a file path was first seen after a library scan (canonical keys).
class RecentlyAddedStore {
  RecentlyAddedStore._();

  static const _prefsKey = 'recently_added_first_seen_v1';

  static final ValueNotifier<int> revision = ValueNotifier(0);

  static Future<Map<String, int>> _loadMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final m = <String, int>{};
      for (final e in decoded.entries) {
        m[e.key] = (e.value as num).toInt();
      }
      return m;
    } catch (_) {
      return {};
    }
  }

  /// Call after collecting scan results: new paths get [firstSeenMs], removed paths drop out.
  static Future<void> mergeScanPaths(Iterable<String> paths) async {
    final prefs = await SharedPreferences.getInstance();
    var m = await _loadMap();
    final now = DateTime.now().millisecondsSinceEpoch;
    final incomingKeys = <String>{};
    for (final path in paths) {
      final k = canonicalMusicLibraryPathKey(path);
      if (k.isEmpty) continue;
      incomingKeys.add(k);
      m.putIfAbsent(k, () => now);
    }
    m.removeWhere((k, _) => !incomingKeys.contains(k));
    await prefs.setString(_prefsKey, jsonEncode(m));
    revision.value++;
  }

  /// Library paths that have a first-seen time, ordered newest-first.
  static Future<List<String>> orderedPathsForLibrary(List<TrackItem> tracks) async {
    final m = await _loadMap();
    final rows = <({String path, int ts})>[];
    for (final t in tracks) {
      final fp = t.filePath;
      if (fp == null || fp.isEmpty) continue;
      final k = canonicalMusicLibraryPathKey(fp);
      final ts = m[k];
      if (ts != null) rows.add((path: fp, ts: ts));
    }
    rows.sort((a, b) => b.ts.compareTo(a.ts));
    return rows.map((r) => r.path).toList();
  }
}
