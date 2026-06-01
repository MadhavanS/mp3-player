import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/youtube_page_id.dart';

/// YouTube hub preferences (default tab, remembered search text).
class YoutubeHomeStore {
  YoutubeHomeStore._();

  static const _defaultPageKey = 'youtube_hub_default_page_v1';
  static const _searchTextKey = 'youtube_hub_search_text_v1';

  static final ValueNotifier<int> revision = ValueNotifier(0);

  static Future<YoutubePageId> loadDefaultPage() async {
    final prefs = await SharedPreferences.getInstance();
    return YoutubePageId.parse(prefs.getString(_defaultPageKey)) ??
        YoutubePageId.library;
  }

  static Future<void> saveDefaultPage(YoutubePageId page) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultPageKey, page.wireValue);
    revision.value++;
  }

  static Future<String> loadSearchText() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_searchTextKey) ?? '';
  }

  static Future<void> saveSearchText(String text) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = text;
    if (trimmed.isEmpty) {
      await prefs.remove(_searchTextKey);
    } else {
      await prefs.setString(_searchTextKey, trimmed);
    }
  }
}
