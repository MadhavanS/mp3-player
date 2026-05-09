import 'package:flutter/material.dart';

import 'app_theme.dart';

/// User-selectable accent for play controls, toasts, sliders, and list highlights.
enum AppAccentColorOption {
  /// Follows the active theme (Julia/Leah/Silver each has its own default).
  themeDefault,
  blue,
  electricBlue,
  teal,
  green,
  purple,
  pink,
  orange,
  amber,
  custom;

  String get persistedName => name;

  static AppAccentColorOption parse(String? raw) {
    switch (raw) {
      case 'themeDefault':
        return AppAccentColorOption.themeDefault;
      case 'blue':
        return AppAccentColorOption.blue;
      case 'electricBlue':
        return AppAccentColorOption.electricBlue;
      case 'teal':
        return AppAccentColorOption.teal;
      case 'green':
        return AppAccentColorOption.green;
      case 'purple':
        return AppAccentColorOption.purple;
      case 'pink':
        return AppAccentColorOption.pink;
      case 'orange':
        return AppAccentColorOption.orange;
      case 'amber':
        return AppAccentColorOption.amber;
      case 'custom':
        return AppAccentColorOption.custom;
      default:
        return AppAccentColorOption.themeDefault;
    }
  }
}

extension AppAccentColorOptionResolve on AppAccentColorOption {
  static Color defaultColorForPalette(AppThemePalette palette) {
    return switch (palette) {
      AppThemePalette.player => const Color(0xFF0B84FF),
      AppThemePalette.playerSoft => const Color(0xFFEC4899),
      AppThemePalette.silver => const Color(0xFFC8C8C8),
      AppThemePalette.daisy => const Color(0xFF151515),
      AppThemePalette.light => const Color(0xFF2563EB),
      AppThemePalette.dark => const Color(0xFF79B8FF),
      AppThemePalette.grey => const Color(0xFF38BDF8),
    };
  }

  Color resolveColorForPalette(
    AppThemePalette palette, {
    required Color customColor,
  }) {
    return switch (this) {
      AppAccentColorOption.themeDefault => defaultColorForPalette(palette),
      AppAccentColorOption.custom => customColor,
      _ => swatchColor,
    };
  }

  Color get swatchColor => switch (this) {
        AppAccentColorOption.themeDefault => const Color(0xFF2563EB),
        AppAccentColorOption.blue => const Color(0xFF2563EB),
        AppAccentColorOption.electricBlue => const Color(0xFF0B84FF),
        AppAccentColorOption.teal => const Color(0xFF14B8A6),
        AppAccentColorOption.green => const Color(0xFF22C55E),
        AppAccentColorOption.purple => const Color(0xFFA855F7),
        AppAccentColorOption.pink => const Color(0xFFEC4899),
        AppAccentColorOption.orange => const Color(0xFFF97316),
        AppAccentColorOption.amber => const Color(0xFFFBBF24),
        AppAccentColorOption.custom => const Color(0xFF64748B),
      };

  String get label => switch (this) {
        AppAccentColorOption.themeDefault => 'Default (by theme)',
        AppAccentColorOption.blue => 'Blue',
        AppAccentColorOption.electricBlue => 'Electric blue',
        AppAccentColorOption.teal => 'Teal',
        AppAccentColorOption.green => 'Green',
        AppAccentColorOption.purple => 'Purple',
        AppAccentColorOption.pink => 'Pink',
        AppAccentColorOption.orange => 'Orange',
        AppAccentColorOption.amber => 'Amber',
        AppAccentColorOption.custom => 'Custom',
      };

  String get subtitle => switch (this) {
        AppAccentColorOption.themeDefault =>
          'Uses each theme default (Julia blue, Leah pink, Silver neutral)',
        AppAccentColorOption.blue => 'Default — buttons, pills, highlights',
        AppAccentColorOption.electricBlue => 'Bright iOS-style blue',
        AppAccentColorOption.teal => 'Cool cyan-green',
        AppAccentColorOption.green => 'Fresh accent',
        AppAccentColorOption.purple => 'Violet highlights',
        AppAccentColorOption.pink => 'Magenta accent',
        AppAccentColorOption.orange => 'Warm emphasis',
        AppAccentColorOption.amber => 'Gold-toned accent',
        AppAccentColorOption.custom =>
          'Pick any color for buttons, pills, and highlights',
      };
}
