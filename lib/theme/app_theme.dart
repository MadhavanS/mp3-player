import 'package:flutter/material.dart';

/// Which palette is actually applied (after resolving [AppThemeSetting.automatic]).
enum AppThemePalette { light, dark, grey, player }

/// User-selectable appearance in Settings.
enum AppThemeSetting {
  light,
  dark,
  grey,

  /// Charcoal surfaces, electric blue controls, mint secondary (player-style UI).
  player,
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
      case AppThemeSetting.player:
        return AppThemePalette.player;
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
    AppThemeSetting.player => 'Player',
    AppThemeSetting.automatic => 'Automatic (by time)',
  };

  String get subtitle => switch (this) {
    AppThemeSetting.light => 'Navy header and white surfaces',
    AppThemeSetting.dark => 'Dim surfaces and cool accents',
    AppThemeSetting.grey => 'Neutral blue-grey tones',
    AppThemeSetting.player =>
      'Charcoal background, electric blue accents, mint highlights',
    AppThemeSetting.automatic => 'Light during the day, dark at night',
  };
}

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.scaffoldBackground,
    required this.surface,
    required this.primary,
    required this.accent,
    required this.onScaffold,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
  });

  final Color scaffoldBackground;
  final Color surface;

  /// Main brand / progress / key actions.
  final Color primary;

  /// Secondary positive / saved / chip highlights (mint in Player theme).
  final Color accent;
  final Color onScaffold;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  Color get dividerOnHero => onScaffold.withValues(alpha: 0.13);

  static const AppPalette light = AppPalette(
    scaffoldBackground: Color(0xFF1A233B),
    surface: Color(0xFFFFFFFF),
    primary: Color(0xFF1A233B),
    accent: Color(0xFF2563EB),
    onScaffold: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF1A233B),
    textSecondary: Color(0xFF8E99A8),
    textMuted: Color(0xFFB0B8C4),
  );

  static const AppPalette dark = AppPalette(
    scaffoldBackground: Color(0xFF0D1117),
    surface: Color(0xFF161B22),
    primary: Color(0xFF79B8FF),
    accent: Color(0xFF7EE787),
    onScaffold: Color(0xFFF0F3F6),
    textPrimary: Color(0xFFF0F3F6),
    textSecondary: Color(0xFF9CA3AF),
    textMuted: Color(0xFF6B7280),
  );

  static const AppPalette grey = AppPalette(
    scaffoldBackground: Color(0xFF3D4454),
    surface: Color(0xFF4F586B),
    primary: Color(0xFF2A3142),
    accent: Color(0xFF38BDF8),
    onScaffold: Color(0xFFF8FAFC),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFFCBD5E1),
    textMuted: Color(0xFF94A3B8),
  );

  /// Inspired by dark music-player UIs: deep charcoal, electric blue, mint chips.
  static const AppPalette player = AppPalette(
    scaffoldBackground: Color(0xFF121212),
    surface: Color(0xFF1E1E1E),
    primary: Color(0xFF0B84FF),
    accent: Color(0xFF5FE3B3),
    onScaffold: Color(0xFFF5F5F7),
    textPrimary: Color(0xFFF5F5F7),
    textSecondary: Color(0xFFB8B8BF),
    textMuted: Color(0xFF8E8E93),
  );

  static AppPalette forPalette(AppThemePalette p) => switch (p) {
    AppThemePalette.light => AppPalette.light,
    AppThemePalette.dark => AppPalette.dark,
    AppThemePalette.grey => AppPalette.grey,
    AppThemePalette.player => AppPalette.player,
  };

  @override
  AppPalette copyWith({
    Color? scaffoldBackground,
    Color? surface,
    Color? primary,
    Color? accent,
    Color? onScaffold,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
  }) {
    return AppPalette(
      scaffoldBackground: scaffoldBackground ?? this.scaffoldBackground,
      surface: surface ?? this.surface,
      primary: primary ?? this.primary,
      accent: accent ?? this.accent,
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
      scaffoldBackground: Color.lerp(
        scaffoldBackground,
        other.scaffoldBackground,
        t,
      )!,
      surface: Color.lerp(surface, other.surface, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onScaffold: Color.lerp(onScaffold, other.onScaffold, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
    );
  }
}

/// Play/pause, shuffle/repeat highlights, toasts, sliders, and library accents.
@immutable
class AppControlAccent extends ThemeExtension<AppControlAccent> {
  const AppControlAccent({required this.color});

  final Color color;

  @override
  AppControlAccent copyWith({Color? color}) {
    return AppControlAccent(color: color ?? this.color);
  }

  @override
  AppControlAccent lerp(ThemeExtension<AppControlAccent>? other, double t) {
    if (other is! AppControlAccent) return this;
    return AppControlAccent(color: Color.lerp(color, other.color, t)!);
  }
}

/// Carries which [AppThemePalette] backs the current [MaterialApp.theme] so UI
/// can diverge layouts (Player reference) beyond token colors alone.
@immutable
class ActiveAppThemePalette extends ThemeExtension<ActiveAppThemePalette> {
  const ActiveAppThemePalette({required this.palette});

  final AppThemePalette palette;

  @override
  ActiveAppThemePalette copyWith({AppThemePalette? palette}) {
    return ActiveAppThemePalette(palette: palette ?? this.palette);
  }

  @override
  ActiveAppThemePalette lerp(covariant ActiveAppThemePalette? other, double t) {
    return t < 0.5 ? this : (other ?? this);
  }
}

extension AppThemeContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;

  /// Play buttons, notification pills, active shuffle/repeat/favourite, key list highlights.
  Color get controlAccent =>
      Theme.of(this).extension<AppControlAccent>()?.color ?? palette.primary;

  /// Prefer this over guessing from colors (matches [ThemeSettingsStore] resolve).
  AppThemePalette get appliedThemePalette =>
      Theme.of(this).extension<ActiveAppThemePalette>()?.palette ??
      AppThemePalette.dark;

  bool get usesPlayerChrome => appliedThemePalette == AppThemePalette.player;
}

extension AppThemeSettingPreviewStripe on AppThemeSetting {
  /// Four colors for a compact horizontal preview (automatic = day + night).
  List<Color> previewSwatches(DateTime resolvedClock) {
    switch (this) {
      case AppThemeSetting.automatic:
        return [
          AppPalette.light.scaffoldBackground,
          AppPalette.light.primary,
          AppPalette.dark.scaffoldBackground,
          AppPalette.dark.primary,
        ];
      default:
        final pal = AppPalette.forPalette(paletteAt(resolvedClock));
        return [pal.scaffoldBackground, pal.surface, pal.primary, pal.accent];
    }
  }
}

abstract final class AppTheme {
  static ThemeData themeFor(
    AppThemePalette palette, {
    required Color controlAccent,
    String? fontFamily,
  }) {
    final ext = AppPalette.forPalette(palette);
    final brightness = switch (palette) {
      AppThemePalette.light => Brightness.light,
      AppThemePalette.dark => Brightness.dark,
      AppThemePalette.grey => Brightness.dark,
      AppThemePalette.player => Brightness.dark,
    };

    final isPlayer = palette == AppThemePalette.player;
    final cardRadius = isPlayer ? 20.0 : 12.0;
    final buttonRadius = BorderRadius.circular(isPlayer ? 18 : 12);

    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      brightness: brightness,
      scaffoldBackgroundColor: ext.scaffoldBackground,
      extensions: [
        ext,
        ActiveAppThemePalette(palette: palette),
        AppControlAccent(color: controlAccent),
      ],
      colorScheme: ColorScheme.fromSeed(
        seedColor: ext.primary,
        brightness: brightness,
        surface: ext.surface,
        onSurface: ext.textPrimary,
        primary: ext.primary,
        onPrimary: Colors.white,
        secondary: ext.accent,
        onSecondary: palette == AppThemePalette.light
            ? Colors.white
            : const Color(0xFF0D1117),
        tertiary: ext.accent,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: ext.onScaffold,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: ext.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: buttonRadius),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: controlAccent.withValues(alpha: 0.85),
        inactiveTrackColor: ext.textMuted.withValues(alpha: 0.35),
        thumbColor: controlAccent,
        overlayColor: controlAccent.withValues(alpha: 0.12),
        trackHeight: isPlayer ? 4 : 3,
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: ext.onScaffold,
        dividerColor: ext.onScaffold.withValues(alpha: 0.12),
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
        bodyMedium: TextStyle(fontSize: 14, color: ext.textSecondary),
        bodySmall: TextStyle(fontSize: 12, color: ext.textMuted),
        labelSmall: TextStyle(
          fontSize: 11,
          color: ext.textMuted,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
