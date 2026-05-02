import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persisted list of absolute directory paths the user added for MP3 scanning.
class SavedMusicFolders {
  SavedMusicFolders._();

  static const _key = 'music_folder_paths_v1';

  static Future<List<String>> load() async {
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

  static Future<void> save(List<String> paths) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(paths));
  }
}
