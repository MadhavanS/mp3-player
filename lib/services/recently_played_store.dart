import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_file_present.dart';
import 'music_library_path_key.dart';
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
      final present = list.where(localFileStillPresent).toList();
      if (present.length <= limit) {
        if (present.length != list.length) {
          await prefs.setString(_key, jsonEncode(present));
        }
        return present;
      }
      final trimmed = present.sublist(0, limit);
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

  /// After [PlayerController.replaceTrackPath], swap [oldPath] for [newPath] and
  /// drop duplicate canonical keys so RecentlyPlayed does not show two rows.
  static Future<void> replacePath(String oldPath, String newPath) async {
    final oldKey = canonicalMusicLibraryPathKey(oldPath);
    final newKey = canonicalMusicLibraryPathKey(newPath);
    if (oldKey.isEmpty || newKey.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final list = await loadPaths();
    final next = <String>[];
    var replaced = false;
    int? replacedIndex;
    final seenKeys = <String>{};

    for (var i = 0; i < list.length; i++) {
      final p = list[i];
      final k = canonicalMusicLibraryPathKey(p);
      if (k == oldKey) {
        if (replacedIndex == null) replacedIndex = next.length;
        replaced = true;
        continue;
      }
      if (k == newKey) {
        replaced = true;
        continue;
      }
      if (k.isNotEmpty) {
        if (seenKeys.contains(k)) continue;
        seenKeys.add(k);
      }
      next.add(p);
    }

    if (!replaced) return;

    if (oldKey != newKey) {
      final at = (replacedIndex ?? 0).clamp(0, next.length);
      next.insert(at, newPath);
    }

    final limit = await RecentListLimitsStore.loadRecentlyPlayedLimit();
    final trimmed = next.length > limit ? next.sublist(0, limit) : next;
    await prefs.setString(_key, jsonEncode(trimmed));
    revision.value++;
  }

  /// Removes [path] from recently played (canonical path comparison).
  static Future<void> removePath(String path) async {
    if (path.isEmpty) return;
    final removeKey = canonicalMusicLibraryPathKey(path);
    final prefs = await SharedPreferences.getInstance();
    final list = await loadPaths();
    final next = list
        .where((p) {
          if (removeKey.isNotEmpty) {
            return canonicalMusicLibraryPathKey(p) != removeKey;
          }
          return p != path;
        })
        .toList(growable: false);
    if (next.length == list.length) return;
    await prefs.setString(_key, jsonEncode(next));
    revision.value++;
  }
}
