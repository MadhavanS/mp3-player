import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_font_option.dart';

const _kFontOptionKey = 'app_font_option';

abstract final class FontSettingsStore {
  static Future<AppFontOption> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppFontOption.parse(prefs.getString(_kFontOptionKey));
  }

  static Future<void> save(AppFontOption option) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFontOptionKey, option.name);
  }
}
