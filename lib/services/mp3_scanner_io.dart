import 'dart:io';

import 'package:path/path.dart' as p;

import 'library_path_exclude.dart';

/// Lists `.mp3` paths under [rootDir]. Sorted by file name (case-insensitive).
Future<List<String>> scanMp3Files(String rootDir, {bool recursive = true}) async {
  final dir = Directory(rootDir);
  if (!await dir.exists()) return [];

  final List<String> out = [];
  await for (final entity in dir.list(recursive: recursive, followLinks: false)) {
    if (entity is! File) continue;
    if (!pathPassesLibraryVisibility(entity.path)) continue;
    if (p.extension(entity.path).toLowerCase() != '.mp3') continue;
    out.add(entity.path);
  }
  out.sort((a, b) => p.basename(a).toLowerCase().compareTo(p.basename(b).toLowerCase()));
  return out;
}
