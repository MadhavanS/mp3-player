import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User preferences for the YouTube download feature.
class YoutubeSettingsStore {
  YoutubeSettingsStore._();

  static const _mergeIntoSongsKey = 'youtube_merge_into_songs_v1';
  static const _customStoragePathKey = 'youtube_custom_storage_path_v1';

  static final ValueNotifier<int> revision = ValueNotifier(0);

  /// When true, downloaded YouTube tracks also appear in Library › Songs.
  static Future<bool> loadMergeIntoSongs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_mergeIntoSongsKey) ?? false;
  }

  static Future<void> saveMergeIntoSongs(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_mergeIntoSongsKey, enabled);
    revision.value++;
  }

  /// When set, new YouTube downloads are saved under this folder instead of the
  /// default app [Documents/youtube_audio] directory.
  static Future<String?> loadCustomStoragePath() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_customStoragePathKey)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  static Future<void> saveCustomStoragePath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = path?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await prefs.remove(_customStoragePathKey);
    } else {
      await prefs.setString(_customStoragePathKey, trimmed);
    }
    revision.value++;
  }

  static Future<void> clearCustomStoragePath() =>
      saveCustomStoragePath(null);
}
