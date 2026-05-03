import 'dart:io';

import 'package:path/path.dart' as p;

import 'library_path_exclude.dart';
import 'mp3_scanner_io.dart';

/// Immediate subfolders (full paths, sorted by name) and `.mp3` files in [absolutePath].
Future<({List<String> dirs, List<String> mp3Paths})> listFolderChildrenSorted(
    String absolutePath,
) async {
  final dir = Directory(absolutePath);
  if (!await dir.exists()) {
    return (dirs: <String>[], mp3Paths: <String>[]);
  }
  final dirs = <String>[];
  final mp3 = <String>[];
  await for (final entity in dir.list(followLinks: false)) {
    try {
      if (entity is Directory) {
        if (basenameIsExcludedLibraryFolder(p.basename(entity.path))) {
          continue;
        }
        dirs.add(entity.path);
      } else if (entity is File) {
        if (!pathPassesLibraryVisibility(entity.path)) continue;
        if (p.extension(entity.path).toLowerCase() != '.mp3') continue;
        mp3.add(entity.path);
      }
    } on FileSystemException {
      continue;
    }
  }
  int cmp(String a, String b) =>
      p.basename(a).toLowerCase().compareTo(p.basename(b).toLowerCase());
  dirs.sort(cmp);
  mp3.sort(cmp);
  return (dirs: dirs, mp3Paths: mp3);
}

/// Recursive MP3 count under [folderPath] including nested folders.
Future<int> totalMp3CountUnderFolder(String folderPath) async {
  final files = await scanMp3Files(folderPath, recursive: true);
  return files.length;
}

/// Count of nested directories strictly under [folderPath] (any depth).
Future<int> recursiveSubfolderCount(String folderPath) async {
  final root = Directory(folderPath);
  if (!await root.exists()) return 0;
  var n = 0;
  await for (final e in root.list(recursive: true, followLinks: false)) {
    if (e is Directory && e.path != folderPath) n++;
  }
  return n;
}

bool pathIsInsideAllowedRoots(String candidate, Iterable<String> roots) {
  final norm = p.normalize(candidate).toLowerCase();
  for (final root in roots) {
    final base = p.normalize(root).toLowerCase();
    if (norm == base) return true;
    final sep = p.separator;
    final pref = base.endsWith(sep) ? base : '$base$sep';
    if (norm.startsWith(pref)) return true;
  }
  return false;
}
