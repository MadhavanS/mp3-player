import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecentListLimitsStore {
  RecentListLimitsStore._();

  static const int defaultLimit = 30;
  static const _recentlyAddedKey = 'recently_added_limit_v1';
  static const _recentlyPlayedKey = 'recently_played_limit_v1';

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<int> loadRecentlyAddedLimit() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getInt(_recentlyAddedKey);
    return _sanitize(raw);
  }

  static Future<int> loadRecentlyPlayedLimit() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getInt(_recentlyPlayedKey);
    return _sanitize(raw);
  }

  static Future<void> saveRecentlyAddedLimit(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_recentlyAddedKey, _sanitize(value));
    revision.value++;
  }

  static Future<void> saveRecentlyPlayedLimit(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_recentlyPlayedKey, _sanitize(value));
    revision.value++;
  }

  static int _sanitize(int? raw) {
    if (raw == null || raw < 1) return defaultLimit;
    if (raw > 500) return 500;
    return raw;
  }
}
