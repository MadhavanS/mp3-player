import 'package:shared_preferences/shared_preferences.dart';

/// Controls one-time "how to add music folders" guidance for new installs.
abstract final class FirstRunLibraryHintStore {
  static const _seenKey = 'first_run_library_hint_seen_v1';

  static Future<bool> shouldShowHint() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_seenKey) ?? false);
  }

  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seenKey, true);
  }
}
