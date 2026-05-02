import 'package:flutter/material.dart';

/// Which palette is actually applied (after resolving [AppThemeSetting.automatic]).
enum AppThemePalette { light, dark, grey }

/// User-selectable appearance in Settings.
enum AppThemeSetting {
  light,
  dark,
  grey,
  automatic,
}

extension AppThemeSettingResolve on AppThemeSetting {
  /// [automatic] uses local time: 6:00–19:59 → light, otherwise dark.
  AppThemePalette paletteAt(DateTime localNow) {
    switch (this) {
      case AppThemeSetting.light:
        return AppThemePalette.light;
      case AppThemeSetting.dark:
        return AppThemePalette.dark;
      case AppThemeSetting.grey:
        return AppThemePalette.grey;
      case AppThemeSetting.automatic:
        final h = localNow.hour;
        return (h >= 6 && h < 20)
            ? AppThemePalette.light
            : AppThemePalette.dark;
    }
  }

  String get label => switch (this) {
        AppThemeSetting.light => 'Light',
        AppThemeSetting.dark => 'Dark',
        AppThemeSetting.grey => 'Grey',
        AppThemeSetting.automatic => 'Automatic (by time)',
      };

  String get subtitle => switch (this) {
        AppThemeSetting.light => 'Navy header and white surfaces',
        AppThemeSetting.dark => 'Dim surfaces and cool accents',
        AppThemeSetting.grey => 'Neutral blue-grey tones',
        AppThemeSetting.automatic => 'Light during the day, dark at night',
      };
}

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.scaffoldBackground,
    required this.surface,
    required this.primary,
    required this.onScaffold,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
  });

  final Color scaffoldBackground;
  final Color surface;
  final Color primary;
  final Color onScaffold;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  Color get dividerOnHero => onScaffold.withValues(alpha: 0.13);

  static const AppPalette light = AppPalette(
    scaffoldBackground: Color(0xFF1A233B),
    surface: Color(0xFFFFFFFF),
    primary: Color(0xFF1A233B),
    onScaffold: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF1A233B),
    textSecondary: Color(0xFF8E99A8),
    textMuted: Color(0xFFB0B8C4),
  );

  static const AppPalette dark = AppPalette(
    scaffoldBackground: Color(0xFF0D1117),
    surface: Color(0xFF161B22),
    primary: Color(0xFF79B8FF),
    onScaffold: Color(0xFFF0F3F6),
    textPrimary: Color(0xFFF0F3F6),
    textSecondary: Color(0xFF9CA3AF),
    textMuted: Color(0xFF6B7280),
  );

  static const AppPalette grey = AppPalette(
    scaffoldBackground: Color(0xFF3D4454),
    surface: Color(0xFF4F586B),
    primary: Color(0xFF2A3142),
    onScaffold: Color(0xFFF8FAFC),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFFCBD5E1),
    textMuted: Color(0xFF94A3B8),
  );

  static AppPalette forPalette(AppThemePalette p) => switch (p) {
        AppThemePalette.light => AppPalette.light,
        AppThemePalette.dark => AppPalette.dark,
        AppThemePalette.grey => AppPalette.grey,
      };

  @override
  AppPalette copyWith({
    Color? scaffoldBackground,
    Color? surface,
    Color? primary,
    Color? onScaffold,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
  }) {
    return AppPalette(
      scaffoldBackground: scaffoldBackground ?? this.scaffoldBackground,
      surface: surface ?? this.surface,
      primary: primary ?? this.primary,
      onScaffold: onScaffold ?? this.onScaffold,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      scaffoldBackground:
          Color.lerp(scaffoldBackground, other.scaffoldBackground, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      onScaffold: Color.lerp(onScaffold, other.onScaffold, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
    );
  }
}

extension AppThemeContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}

abstract final class AppTheme {
  static ThemeData themeFor(AppThemePalette palette) {
    final ext = AppPalette.forPalette(palette);
    final brightness = switch (palette) {
      AppThemePalette.light => Brightness.light,
      AppThemePalette.dark => Brightness.dark,
      AppThemePalette.grey => Brightness.dark,
    };

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: ext.scaffoldBackground,
      extensions: [ext],
      colorScheme: ColorScheme.fromSeed(
        seedColor: ext.primary,
        brightness: brightness,
        surface: ext.surface,
        onSurface: ext.textPrimary,
        primary: ext.primary,
        onPrimary: ext.surface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: ext.onScaffold,
        centerTitle: true,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: ext.primary.withValues(alpha: 0.85),
        inactiveTrackColor: ext.textMuted.withValues(alpha: 0.35),
        thumbColor: ext.primary,
        overlayColor: ext.primary.withValues(alpha: 0.12),
        trackHeight: 3,
      ),
      textTheme: TextTheme(
        titleLarge: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 22,
          color: ext.textPrimary,
          letterSpacing: -0.5,
        ),
        titleMedium: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 16,
          color: ext.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: ext.textSecondary,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          color: ext.textMuted,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          color: ext.textMuted,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
