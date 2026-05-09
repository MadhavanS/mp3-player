/// Background tone for player-chrome palettes; separate from accent color.
enum PlayerChromeBackgroundKind {
  /// In-house palette tuned for the active chrome theme.
  themeDefault,
  dark,
  light,
  grey,
  custom;

  static PlayerChromeBackgroundKind parse(String? raw) {
    switch (raw) {
      case 'themeDefault':
        return PlayerChromeBackgroundKind.themeDefault;
      case 'dark':
        return PlayerChromeBackgroundKind.dark;
      case 'light':
        return PlayerChromeBackgroundKind.light;
      case 'grey':
        return PlayerChromeBackgroundKind.grey;
      case 'custom':
        return PlayerChromeBackgroundKind.custom;
      default:
        return PlayerChromeBackgroundKind.themeDefault;
    }
  }

  String get label => switch (this) {
        PlayerChromeBackgroundKind.themeDefault => 'Default',
        PlayerChromeBackgroundKind.dark => 'Dark',
        PlayerChromeBackgroundKind.light => 'Light',
        PlayerChromeBackgroundKind.grey => 'Grey',
        PlayerChromeBackgroundKind.custom => 'Custom',
      };

  String get subtitle => switch (this) {
        PlayerChromeBackgroundKind.themeDefault =>
          'Designed for the active theme (see hint below).',
        PlayerChromeBackgroundKind.dark => 'Stronger contrast for this theme',
        PlayerChromeBackgroundKind.light => 'Bright surfaces and dark text',
        PlayerChromeBackgroundKind.grey => 'Neutral blue-grey surfaces',
        PlayerChromeBackgroundKind.custom =>
          'Pick a background color for the app',
      };
}
