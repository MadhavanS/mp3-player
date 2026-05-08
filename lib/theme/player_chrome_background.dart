/// Background tone for Julia ([AppThemePalette.player]) and Leah
/// ([AppThemePalette.playerSoft]); separate from accent color.
enum PlayerChromeBackgroundKind {
  dark,
  light,
  grey,
  custom;

  static PlayerChromeBackgroundKind parse(String? raw) {
    switch (raw) {
      case 'light':
        return PlayerChromeBackgroundKind.light;
      case 'grey':
        return PlayerChromeBackgroundKind.grey;
      case 'custom':
        return PlayerChromeBackgroundKind.custom;
      default:
        return PlayerChromeBackgroundKind.dark;
    }
  }

  String get label => switch (this) {
        PlayerChromeBackgroundKind.dark => 'Dark',
        PlayerChromeBackgroundKind.light => 'Light',
        PlayerChromeBackgroundKind.grey => 'Grey',
        PlayerChromeBackgroundKind.custom => 'Custom',
      };

  String get subtitle => switch (this) {
        PlayerChromeBackgroundKind.dark => 'Default theme backgrounds',
        PlayerChromeBackgroundKind.light => 'Bright surfaces and dark text',
        PlayerChromeBackgroundKind.grey => 'Neutral blue-grey surfaces',
        PlayerChromeBackgroundKind.custom => 'Pick a background color for the app',
      };
}
