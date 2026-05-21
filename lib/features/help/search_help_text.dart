/// Shared search-field hints and help copy for library and Files screens.
abstract final class SearchHelpText {
  static const int libraryMinChars = 3;

  /// Shown in the library search field (Songs, Favourites, queue, etc.).
  static const String libraryTrackFieldHint = 'm: album  s: title  a: artist';

  static const String playlistTabFieldHint =
      'Playlists (min. $libraryMinChars characters)';

  /// Shown in the Files browser search field.
  static const String filesFieldHint = 'Folders & titles';
}
