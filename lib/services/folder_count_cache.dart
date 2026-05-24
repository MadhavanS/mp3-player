import 'package:path/path.dart' as p;

import 'folder_browser.dart';

/// Session cache for recursive MP3 counts under a folder (Files browser badges).
class FolderCountCache {
  FolderCountCache._();

  static final FolderCountCache instance = FolderCountCache._();

  final Map<String, int> _cache = <String, int>{};

  /// True when [filePath] is [folderPath] or a file under it.
  static bool pathIsUnderFolder(String filePath, String folderPath) {
    try {
      final normFile = p.normalize(filePath);
      final normFolder = p.normalize(folderPath);
      if (normFile == normFolder) return true;
      return p.isWithin(normFolder, normFile);
    } catch (_) {
      return false;
    }
  }

  /// In-memory catalog count (zero IO). Null when catalog empty or no matches.
  int? countFromCatalog(String folderPath, Iterable<String> catalogPaths) {
    var anyPath = false;
    var count = 0;
    for (final filePath in catalogPaths) {
      if (filePath.isEmpty) continue;
      anyPath = true;
      if (pathIsUnderFolder(filePath, folderPath)) count++;
    }
    if (!anyPath) return null;
    if (count > 0) {
      _cache[folderPath] = count;
      return count;
    }
    return null;
  }

  /// Recursive disk walk, cached per [folderPath].
  Future<int> countFromDisk(String folderPath) async {
    final cached = _cache[folderPath];
    if (cached != null) return cached;
    final count = await totalMp3CountUnderFolder(folderPath);
    _cache[folderPath] = count;
    return count;
  }

  /// Catalog first, then disk fallback.
  Future<int> resolveSongCount(
    String folderPath,
    Iterable<String> catalogPaths,
  ) async {
    final fromCatalog = countFromCatalog(folderPath, catalogPaths);
    if (fromCatalog != null) return fromCatalog;
    return countFromDisk(folderPath);
  }

  void clear() => _cache.clear();
}
