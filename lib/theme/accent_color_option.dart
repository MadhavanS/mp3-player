import 'package:flutter/material.dart';

/// User-selectable accent for play controls, toasts, sliders, and list highlights.
enum AppAccentColorOption {
  /// Classic blue — default for this app.
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
        return AppAccentColorOption.blue;
    }
  }
}

extension AppAccentColorOptionResolve on AppAccentColorOption {
  Color get swatchColor => switch (this) {
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
