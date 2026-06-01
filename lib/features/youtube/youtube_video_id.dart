import 'dart:math' as math;

import 'package:path/path.dart' as p;

/// Parses a YouTube video id from a downloaded file name (`{videoId}_{title}.m4a`).
String? parseYoutubeVideoIdFromPath(String filePath) {
  final base = p.basenameWithoutExtension(filePath);
  final ytMatch = RegExp(r'^([A-Za-z0-9_-]{11})_').firstMatch(base);
  if (ytMatch != null) return ytMatch.group(1);

  final underscore = base.indexOf('_');
  if (underscore <= 0) return null;
  final id = base.substring(0, underscore).trim();
  return id.isEmpty ? null : id;
}

/// Stable id for a file in the YouTube storage folder (parsed id or sanitized basename).
String videoIdForStorageFile(String filePath) {
  final parsed = parseYoutubeVideoIdFromPath(filePath);
  if (parsed != null && parsed.isNotEmpty) return parsed;
  final base = p.basenameWithoutExtension(filePath).trim();
  final sanitized = base.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  if (sanitized.isEmpty) return 'local_file';
  return sanitized.substring(0, math.min(sanitized.length, 48));
}
