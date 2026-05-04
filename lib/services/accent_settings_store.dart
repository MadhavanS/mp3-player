import 'package:shared_preferences/shared_preferences.dart';

import '../theme/accent_color_option.dart';

const _kAccentKey = 'app_accent_color_option';

abstract final class AccentSettingsStore {
  static Future<AppAccentColorOption> load() async {
    final p = await SharedPreferences.getInstance();
    return AppAccentColorOption.parse(p.getString(_kAccentKey));
  }

  static Future<void> save(AppAccentColorOption option) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAccentKey, option.persistedName);
  }
}
