import 'package:shared_preferences/shared_preferences.dart';

/// Controls welcome dialog for users who have not added music folders yet.
abstract final class FirstRunLibraryHintStore {
  static const _dismissedKey = 'first_run_library_hint_dismissed_v1';

  static Future<bool> shouldShowHint() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_dismissedKey) ?? false);
  }

  /// User tapped "Later" — do not show the dialog again until folders exist.
  static Future<void> markDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dismissedKey, true);
  }
}
