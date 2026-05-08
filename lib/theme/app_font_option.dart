enum AppFontOption {
  system,
  roboto,
  serif,
  monospace;

  static AppFontOption parse(String? raw) {
    switch (raw) {
      case 'system':
        return AppFontOption.system;
      case 'roboto':
        return AppFontOption.roboto;
      case 'serif':
        return AppFontOption.serif;
      case 'monospace':
        return AppFontOption.monospace;
      default:
        return AppFontOption.system;
    }
  }
}

extension AppFontOptionPresentation on AppFontOption {
  String get label => switch (this) {
    AppFontOption.system => 'System default',
    AppFontOption.roboto => 'Roboto',
    AppFontOption.serif => 'Serif',
    AppFontOption.monospace => 'Monospace',
  };

  String get subtitle => switch (this) {
    AppFontOption.system => 'Use the default platform font',
    AppFontOption.roboto => 'Clean sans-serif style',
    AppFontOption.serif => 'Classic serif typography',
    AppFontOption.monospace => 'Fixed-width style',
  };

  String? get fontFamily => switch (this) {
    AppFontOption.system => null,
    AppFontOption.roboto => 'Roboto',
    AppFontOption.serif => 'serif',
    AppFontOption.monospace => 'monospace',
  };
}
