import 'package:path/path.dart' as p;

/// YouTube downloads are not supported on web/stub builds.
bool isYoutubeDownloadStoragePath(String rawPath) => false;

/// Stable key for comparing paths on web/stub builds (no [dart:io]).
String canonicalMusicLibraryPathKey(String rawPath) {
  final trimmed = rawPath.trim();
  if (trimmed.isEmpty) return '';
  return p.normalize(trimmed).toLowerCase();
}
