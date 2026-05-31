import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User preferences for the YouTube download feature.
class YoutubeSettingsStore {
  YoutubeSettingsStore._();

  static const _mergeIntoSongsKey = 'youtube_merge_into_songs_v1';

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
}
