enum AppFontOption {
  system,
  roboto,
  serif,
  monospace,
  fraunces,
  /// Google Fonts: Edu NSW ACT Cursive (handwriting).
  eduNswActHandCursive;

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
      case 'eduNswActHandCursive':
        return AppFontOption.eduNswActHandCursive;
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
    AppFontOption.eduNswActHandCursive => 'Edu NSW ACT Hand Cursive',
  };

  String get subtitle => switch (this) {
    AppFontOption.system => 'Use the default platform font',
    AppFontOption.roboto => 'Clean sans-serif style',
    AppFontOption.serif => 'Classic serif typography',
    AppFontOption.monospace => 'Fixed-width style',
    AppFontOption.fraunces => 'Google serif display font',
    AppFontOption.eduNswActHandCursive =>
      'NSW/ACT school handwriting (Google Fonts: Edu NSW ACT Cursive)',
  };

  String? get fontFamily => switch (this) {
    AppFontOption.system => null,
    AppFontOption.roboto => 'Roboto',
    AppFontOption.serif => 'serif',
    AppFontOption.monospace => 'monospace',
    AppFontOption.fraunces => null,
    AppFontOption.eduNswActHandCursive => null,
  };
}
