import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'music_library_path_key.dart';

/// One user-saved playlist (ordered absolute file paths).
class UserPlaylistEntry {
  const UserPlaylistEntry({
    required this.id,
    required this.name,
    required this.paths,
  });

  final String id;
  final String name;
  final List<String> paths;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'paths': paths,
      };

  factory UserPlaylistEntry.fromJson(Map<String, dynamic> m) {
    return UserPlaylistEntry(
      id: m['id'] as String,
      name: m['name'] as String,
      paths: (m['paths'] as List<dynamic>).cast<String>(),
    );
  }
}

/// Named playlists persisted in [SharedPreferences].
class UserPlaylistsStore {
  UserPlaylistsStore._();

  static const _prefsKey = 'user_playlists_v1';

  static final ValueNotifier<int> revision = ValueNotifier(0);

  static Future<List<UserPlaylistEntry>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => UserPlaylistEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<UserPlaylistEntry> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
    revision.value++;
  }

  static Future<void> createPlaylist(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    final list = await loadAll();
    final id = 'pl_${DateTime.now().millisecondsSinceEpoch}';
    list.insert(0, UserPlaylistEntry(id: id, name: n, paths: []));
    await _save(list);
  }

  static Future<void> deletePlaylist(String id) async {
    final list = await loadAll();
    list.removeWhere((e) => e.id == id);
    await _save(list);
  }

  /// Appends [path] if not already present (canonical path comparison). Returns whether it was added.
  static Future<bool> addPathToPlaylist(String playlistId, String path) async {
    final raw = path.trim();
    if (raw.isEmpty) return false;
    final list = await loadAll();
    final idx = list.indexWhere((e) => e.id == playlistId);
    if (idx < 0) return false;
    final pl = list[idx];
    final newKey = canonicalMusicLibraryPathKey(raw);
    if (newKey.isNotEmpty) {
      for (final existing in pl.paths) {
        if (canonicalMusicLibraryPathKey(existing) == newKey) {
          return false;
        }
      }
    } else {
      if (pl.paths.contains(raw)) return false;
    }
    list[idx] = UserPlaylistEntry(
      id: pl.id,
      name: pl.name,
      paths: [...pl.paths, raw],
    );
    await _save(list);
    return true;
  }
}
