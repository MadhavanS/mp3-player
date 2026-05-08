import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track_item.dart';
import 'music_library_path_key.dart';
import 'recent_list_limits_store.dart';

/// Records when a file path was first seen as **new** after a library baseline.
///
/// The first full scan after an empty map establishes a baseline (`0` = already in
/// library, hidden from RecentlyAdded). Paths that appear in later scans get a real
/// timestamp and show up here — settings-folder scans only ([mergeScanPaths]).
class RecentlyAddedStore {
  RecentlyAddedStore._();

  static const _prefsKey = 'recently_added_first_seen_v2';

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

  static void _applyLimitToNewEntries(Map<String, int> map, int limit) {
    final positives = map.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (positives.length <= limit) return;
    for (final e in positives.skip(limit)) {
      // Keep baseline presence but drop out of RecentlyAdded display.
      map[e.key] = 0;
    }
  }

  /// Call after collecting scan results from Settings music folders.
  ///
  /// New paths since the last baseline scan get [firstSeenMs] = now.
  /// The first non-empty scan seeds every path with `0` (not shown as RecentlyAdded).
  /// Removed paths drop out of the map.
  static Future<void> mergeScanPaths(Iterable<String> paths) async {
    final prefs = await SharedPreferences.getInstance();
    var m = await _loadMap();
    final limit = await RecentListLimitsStore.loadRecentlyAddedLimit();
    final incomingKeys = <String>{};
    for (final path in paths) {
      final k = canonicalMusicLibraryPathKey(path);
      if (k.isEmpty) continue;
      incomingKeys.add(k);
    }
    m.removeWhere((k, _) => !incomingKeys.contains(k));

    if (incomingKeys.isEmpty) {
      await prefs.setString(_prefsKey, jsonEncode(m));
      revision.value++;
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final brandNew = incomingKeys.where((k) => !m.containsKey(k)).toList();

    if (m.isEmpty) {
      // First catalog snapshot: baseline everything as existing library (not "new").
      for (final k in incomingKeys) {
        m[k] = 0;
      }
    } else {
      for (final k in brandNew) {
        m[k] = now;
      }
    }
    _applyLimitToNewEntries(m, limit);

    await prefs.setString(_prefsKey, jsonEncode(m));
    revision.value++;
  }

  /// Paths first seen after baseline, ordered newest-first (by first-seen time).
  static Future<List<String>> orderedPathsForLibrary(
    List<TrackItem> tracks,
  ) async {
    final limit = await RecentListLimitsStore.loadRecentlyAddedLimit();
    final m = await _loadMap();
    final rows = <({String path, int ts})>[];
    for (final t in tracks) {
      final fp = t.filePath;
      if (fp == null || fp.isEmpty) continue;
      final k = canonicalMusicLibraryPathKey(fp);
      final ts = m[k];
      if (ts != null && ts > 0) rows.add((path: fp, ts: ts));
    }
    rows.sort((a, b) => b.ts.compareTo(a.ts));
    return rows.take(limit).map((r) => r.path).toList();
  }

  static Future<void> trimToConfiguredLimit() async {
    final prefs = await SharedPreferences.getInstance();
    final m = await _loadMap();
    final limit = await RecentListLimitsStore.loadRecentlyAddedLimit();
    _applyLimitToNewEntries(m, limit);
    await prefs.setString(_prefsKey, jsonEncode(m));
    revision.value++;
  }
}
