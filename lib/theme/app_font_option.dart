enum AppFontOption {
  system,
  roboto,
  serif,
  monospace,
  fraunces;

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
      case 'fraunces':
        return AppFontOption.fraunces;
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
    AppFontOption.fraunces => 'Fraunces',
  };

  String get subtitle => switch (this) {
    AppFontOption.system => 'Use the default platform font',
    AppFontOption.roboto => 'Clean sans-serif style',
    AppFontOption.serif => 'Classic serif typography',
    AppFontOption.monospace => 'Fixed-width style',
    AppFontOption.fraunces => 'Google serif display font',
  };

  String? get fontFamily => switch (this) {
    AppFontOption.system => null,
    AppFontOption.roboto => 'Roboto',
    AppFontOption.serif => 'serif',
    AppFontOption.monospace => 'monospace',
    AppFontOption.fraunces => null,
  };
}
