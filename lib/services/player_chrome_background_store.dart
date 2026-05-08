import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/player_chrome_background.dart';

const _kKindKey = 'player_chrome_bg_kind_v1';
const _kCustomArgbKey = 'player_chrome_bg_custom_argb_v1';

abstract final class PlayerChromeBackgroundStore {
  static Future<PlayerChromeBackgroundKind> loadKind() async {
    final p = await SharedPreferences.getInstance();
    return PlayerChromeBackgroundKind.parse(p.getString(_kKindKey));
  }

  static Future<Color?> loadCustomColor() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getInt(_kCustomArgbKey);
    if (v == null) return null;
    return Color(v);
  }

  static Future<void> saveKind(PlayerChromeBackgroundKind kind) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kKindKey, kind.name);
  }

  static Future<void> saveCustomColor(Color color) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kCustomArgbKey, color.toARGB32());
  }
}
