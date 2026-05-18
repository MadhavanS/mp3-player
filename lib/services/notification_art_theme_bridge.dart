import '../theme/app_theme.dart';

/// Current theme palette for notification/widget placeholders (no [BuildContext]).
abstract final class NotificationArtThemeBridge {
  static AppThemePalette Function() palette = () => AppThemePalette.julia;
}
