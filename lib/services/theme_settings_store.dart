import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

const _kThemeSettingKey = 'app_theme_setting';

abstract final class ThemeSettingsStore {
  static Future<AppThemeSetting> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kThemeSettingKey);
    return _parse(raw);
  }

  static AppThemeSetting _parse(String? raw) {
    switch (raw) {
      case 'light':
        return AppThemeSetting.light;
      case 'dark':
        return AppThemeSetting.dark;
      case 'grey':
        return AppThemeSetting.grey;
      case 'player':
        return AppThemeSetting.player;
      case 'playerSoft':
        return AppThemeSetting.playerSoft;
      case 'silver':
        return AppThemeSetting.silver;
      case 'liya':
        return AppThemeSetting.silver;
      case 'automatic':
        return AppThemeSetting.automatic;
      default:
        return AppThemeSetting.automatic;
    }
  }

  static Future<void> save(AppThemeSetting setting) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kThemeSettingKey, setting.name);
  }
}
