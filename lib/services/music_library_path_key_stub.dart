import 'package:path/path.dart' as p;

/// Stable key for comparing paths on web/stub builds (no [dart:io]).
String canonicalMusicLibraryPathKey(String rawPath) {
  final trimmed = rawPath.trim();
  if (trimmed.isEmpty) return '';
  return p.normalize(trimmed).toLowerCase();
}
