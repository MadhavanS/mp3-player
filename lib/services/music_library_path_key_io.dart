import 'dart:io' show File;

import 'package:path/path.dart' as p;

/// Canonical path keys for playlist vs Files filtering (handles junctions/long paths).
String canonicalMusicLibraryPathKey(String rawPath) {
  final trimmed = rawPath.trim();
  if (trimmed.isEmpty) return '';
  try {
    return p.normalize(File(trimmed).absolute.path).toLowerCase();
  } catch (_) {
    return p.normalize(trimmed).toLowerCase();
  }
}
