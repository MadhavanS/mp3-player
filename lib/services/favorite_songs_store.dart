import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_file_present.dart';
import 'music_library_path_key.dart';

/// Persists absolute file paths marked as favourites (newest first).
class FavoriteSongsStore {
  FavoriteSongsStore._();

  static const _key = 'favorite_song_paths_v1';

  static final ValueNotifier<int> revision = ValueNotifier(0);

  static List<String> _paths = [];
  static Future<void>? _loadFuture;

  static Future<void> _readFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      _paths = [];
      return;
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      _paths = decoded.cast<String>();
    } catch (_) {
      _paths = [];
    }
  }

  /// Loads from disk on first use; later calls are cheap.
  static Future<void> ensureLoaded() async {
    _loadFuture ??= _readFromPrefs();
    await _loadFuture;
  }

  static Future<List<String>> loadPaths() async {
    await ensureLoaded();
    return List.unmodifiable(_paths);
  }

  static bool isFavorite(String path) {
    if (path.isEmpty) return false;
    return _paths.any((p) => _samePath(p, path));
  }

  static bool _samePath(String a, String b) {
    final ka = canonicalMusicLibraryPathKey(a);
    final kb = canonicalMusicLibraryPathKey(b);
    if (ka.isNotEmpty && kb.isNotEmpty) return ka == kb;
    return a == b;
  }

  /// Returns `true` if the path is a favourite after this call.
  static Future<bool> toggleFavorite(String path) async {
    if (path.isEmpty) return false;
    await ensureLoaded();
    final prefs = await SharedPreferences.getInstance();
    final wasFavorite = _paths.any((p) => _samePath(p, path));
    _paths.removeWhere((p) => _samePath(p, path));
    if (wasFavorite) {
      // Removed above.
    } else {
      _paths.insert(0, path);
    }
    await prefs.setString(_key, jsonEncode(_paths));
    revision.value++;
    return !wasFavorite;
  }

  /// Removes entries whose files no longer exist on disk (no-op on web).
  static Future<void> replacePath(String oldPath, String newPath) async {
    final oldKey = canonicalMusicLibraryPathKey(oldPath);
    final newKey = canonicalMusicLibraryPathKey(newPath);
    if (oldKey.isEmpty || newKey.isEmpty || oldKey == newKey) return;

    await ensureLoaded();
    final prefs = await SharedPreferences.getInstance();
    final next = <String>[];
    var replaced = false;
    int? replacedIndex;
    final seenKeys = <String>{};

    for (final p in _paths) {
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

    // Only update favourites when [oldPath] (or [newPath]) was already stored.
    if (!replaced) return;

    if (oldKey != newKey) {
      final at = (replacedIndex ?? 0).clamp(0, next.length);
      next.insert(at, newPath);
    }

    _paths = next;
    await prefs.setString(_key, jsonEncode(_paths));
    revision.value++;
  }

  static Future<void> pruneMissingPaths() async {
    await ensureLoaded();
    final kept = _paths.where(localFileStillPresent).toList();
    if (kept.length == _paths.length) return;
    _paths = kept;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_paths));
    revision.value++;
  }
}
