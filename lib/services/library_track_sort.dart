import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track_item.dart';
import 'file_path_mtime_sort.dart';

/// How Songs (library) and Files browser order `.mp3` rows.
enum LibraryTrackSortMode {
  modifiedNewest,
  modifiedOldest,
  titleAZ,
  titleZA,

  /// Album tag ([TrackItem.metaLine]); unknown/placeholder sorts last.
  albumAZ,
  albumZA,

  /// All tracks from the first Settings music folder, then the second, etc.
  /// Within each root, ordered by relative path (folder structure).
  folderOrder,
}

extension LibraryTrackSortModeStorage on LibraryTrackSortMode {
  String get prefsValue => switch (this) {
        LibraryTrackSortMode.modifiedNewest => 'modified_newest',
        LibraryTrackSortMode.modifiedOldest => 'modified_oldest',
        LibraryTrackSortMode.titleAZ => 'title_az',
        LibraryTrackSortMode.titleZA => 'title_za',
        LibraryTrackSortMode.albumAZ => 'album_az',
        LibraryTrackSortMode.albumZA => 'album_za',
        LibraryTrackSortMode.folderOrder => 'folder_order',
      };

  String get menuLabel => switch (this) {
        LibraryTrackSortMode.modifiedNewest => 'Date modified (newest first)',
        LibraryTrackSortMode.modifiedOldest => 'Date modified (oldest first)',
        LibraryTrackSortMode.titleAZ => 'Title (A–Z)',
        LibraryTrackSortMode.titleZA => 'Title (Z–A)',
        LibraryTrackSortMode.albumAZ => 'Album (A–Z)',
        LibraryTrackSortMode.albumZA => 'Album (Z–A)',
        LibraryTrackSortMode.folderOrder => 'Folder order (library folders)',
      };
}

LibraryTrackSortMode? _parseSortMode(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return switch (raw) {
    'modified_newest' => LibraryTrackSortMode.modifiedNewest,
    'modified_oldest' => LibraryTrackSortMode.modifiedOldest,
    'title_az' => LibraryTrackSortMode.titleAZ,
    'title_za' => LibraryTrackSortMode.titleZA,
    'album_az' => LibraryTrackSortMode.albumAZ,
    'album_za' => LibraryTrackSortMode.albumZA,
    'folder_order' => LibraryTrackSortMode.folderOrder,
    _ => null,
  };
}

/// Persisted sort order shared by Library › Songs and drawer › Files.
class LibraryTrackSortStore {
  LibraryTrackSortStore._();

  static const _prefsKey = 'library_track_sort_v1';

  static final ValueNotifier<int> revision = ValueNotifier(0);

  static Future<LibraryTrackSortMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    return _parseSortMode(prefs.getString(_prefsKey)) ??
        LibraryTrackSortMode.folderOrder;
  }

  static Future<void> save(LibraryTrackSortMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.prefsValue);
    revision.value++;
  }
}

/// Index of the first Settings music root that contains [filePath], or [roots.length]
/// when none match (sorted last).
int libraryRootIndexForPath(String filePath, List<String> roots) {
  if (roots.isEmpty) return 0;
  final norm = p.normalize(filePath).toLowerCase();
  for (var i = 0; i < roots.length; i++) {
    final base = p.normalize(roots[i]).toLowerCase();
    if (norm == base) return i;
    final sep = p.separator;
    final pref = base.endsWith(sep) ? base : '$base$sep';
    if (norm.startsWith(pref)) return i;
  }
  return roots.length;
}

/// Lowercased path relative to the owning library root (for stable folder walk order).
String libraryRelativePathForSort(String filePath, List<String> roots) {
  final normFile = p.normalize(filePath);
  for (final root in roots) {
    final normRoot = p.normalize(root);
    if (normFile == normRoot) return '';
    final sep = p.separator;
    final pref = normRoot.endsWith(sep) ? normRoot : '$normRoot$sep';
    if (normFile.startsWith(pref)) {
      return p.relative(normFile, from: normRoot).toLowerCase();
    }
  }
  return normFile.toLowerCase();
}

int _folderOrderPathCmp(String pathA, String pathB, List<String> roots) {
  final ra = libraryRootIndexForPath(pathA, roots);
  final rb = libraryRootIndexForPath(pathB, roots);
  final rootCmp = ra.compareTo(rb);
  if (rootCmp != 0) return rootCmp;
  final rel = libraryRelativePathForSort(pathA, roots)
      .compareTo(libraryRelativePathForSort(pathB, roots));
  if (rel != 0) return rel;
  return pathA.toLowerCase().compareTo(pathB.toLowerCase());
}

void _sortPathsByFolderOrder(List<String> paths, List<String> roots) {
  paths.sort(
    (a, b) => _folderOrderPathCmp(a, b, roots),
  );
}

/// Normalized album tag for sort; empty or placeholder sorts last in A–Z.
String _albumTagKey(TrackItem t) {
  final m = t.metaLine.trim();
  if (m.isEmpty || m.toLowerCase() == 'mp3') return '';
  return m.toLowerCase();
}

/// Files explorer: no tag read — parent folder name, then title from filename.
String _parentFolderSortKey(String path) =>
    p.basename(p.dirname(p.normalize(path))).toLowerCase();

/// Orders filtered catalog indices; catalog order is modified-newest-first from scan.
List<int> sortFilteredTrackIndices(
  List<int> indices,
  List<TrackItem> tracks,
  LibraryTrackSortMode mode, {
  List<String> libraryRoots = const [],
}) {
  if (indices.length < 2) return List<int>.from(indices);
  final out = List<int>.from(indices);
  int titleCmp(int ia, int ib) {
    final ta = tracks[ia].title.toLowerCase();
    final tb = tracks[ib].title.toLowerCase();
    final c = ta.compareTo(tb);
    if (c != 0) return c;
    final pa = (tracks[ia].filePath ?? '').toLowerCase();
    final pb = (tracks[ib].filePath ?? '').toLowerCase();
    return pa.compareTo(pb);
  }

  int albumCmp(int ia, int ib) {
    final aa = _albumTagKey(tracks[ia]);
    final bb = _albumTagKey(tracks[ib]);
    final hasA = aa.isNotEmpty;
    final hasB = bb.isNotEmpty;
    if (hasA != hasB) {
      return hasA ? -1 : 1;
    }
    final c = aa.compareTo(bb);
    if (c != 0) return c;
    return titleCmp(ia, ib);
  }

  switch (mode) {
    case LibraryTrackSortMode.modifiedNewest:
      out.sort((a, b) => a.compareTo(b));
      break;
    case LibraryTrackSortMode.modifiedOldest:
      out.sort((a, b) => b.compareTo(a));
      break;
    case LibraryTrackSortMode.titleAZ:
      out.sort(titleCmp);
      break;
    case LibraryTrackSortMode.titleZA:
      out.sort((a, b) => titleCmp(b, a));
      break;
    case LibraryTrackSortMode.albumAZ:
      out.sort(albumCmp);
      break;
    case LibraryTrackSortMode.albumZA:
      out.sort((a, b) => albumCmp(b, a));
      break;
    case LibraryTrackSortMode.folderOrder:
      out.sort((a, b) {
        final pa = tracks[a].filePath ?? '';
        final pb = tracks[b].filePath ?? '';
        final pathCmp = _folderOrderPathCmp(pa, pb, libraryRoots);
        if (pathCmp != 0) return pathCmp;
        return a.compareTo(b);
      });
      break;
  }
  return out;
}

String _basenameTitleKey(String path) =>
    p.basenameWithoutExtension(path).toLowerCase();

/// Sort immediate `.mp3` paths for the Files explorer (may stat files on IO).
Future<List<String>> sortMp3PathsForFilesExplorer(
  List<String> paths,
  LibraryTrackSortMode mode, {
  List<String> libraryRoots = const [],
}) async {
  if (paths.length <= 1) return List<String>.from(paths);
  switch (mode) {
    case LibraryTrackSortMode.modifiedNewest:
      final out = List<String>.from(paths);
      await sortPathsByModifiedNewestFirst(out);
      return out;
    case LibraryTrackSortMode.modifiedOldest:
      final out = List<String>.from(paths);
      await sortPathsByModifiedNewestFirst(out);
      return out.reversed.toList();
    case LibraryTrackSortMode.titleAZ:
      final out = List<String>.from(paths);
      out.sort(
        (a, b) => _basenameTitleKey(a).compareTo(_basenameTitleKey(b)),
      );
      return out;
    case LibraryTrackSortMode.titleZA:
      final out = List<String>.from(paths);
      out.sort(
        (a, b) => _basenameTitleKey(b).compareTo(_basenameTitleKey(a)),
      );
      return out;
    case LibraryTrackSortMode.albumAZ:
      final outAlbum = List<String>.from(paths);
      outAlbum.sort((a, b) {
        final d = _parentFolderSortKey(a).compareTo(_parentFolderSortKey(b));
        if (d != 0) return d;
        return _basenameTitleKey(a).compareTo(_basenameTitleKey(b));
      });
      return outAlbum;
    case LibraryTrackSortMode.albumZA:
      final outAlbumZ = List<String>.from(paths);
      outAlbumZ.sort((a, b) {
        final d = _parentFolderSortKey(b).compareTo(_parentFolderSortKey(a));
        if (d != 0) return d;
        return _basenameTitleKey(b).compareTo(_basenameTitleKey(a));
      });
      return outAlbumZ;
    case LibraryTrackSortMode.folderOrder:
      final out = List<String>.from(paths);
      _sortPathsByFolderOrder(out, libraryRoots);
      return out;
  }
}
