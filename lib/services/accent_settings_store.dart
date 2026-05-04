import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/accent_color_option.dart';

const _kAccentKey = 'app_accent_color_option';
const _kCustomArgbKey = 'app_accent_custom_argb';

typedef AccentLoadResult = ({AppAccentColorOption option, Color customAccent});

abstract final class AccentSettingsStore {
  static Future<AccentLoadResult> load() async {
    final p = await SharedPreferences.getInstance();
    final option = AppAccentColorOption.parse(p.getString(_kAccentKey));
    final argb = p.getInt(_kCustomArgbKey);
    final fallback = AppAccentColorOption.blue.swatchColor;
    final custom = argb != null ? Color(argb) : fallback;
    return (option: option, customAccent: custom);
  }

  static Future<void> save(AppAccentColorOption option, Color? customIfCustom) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccentKey, option.persistedName);
    if (option == AppAccentColorOption.custom && customIfCustom != null) {
      await prefs.setInt(_kCustomArgbKey, customIfCustom.toARGB32());
    }
  }
}
