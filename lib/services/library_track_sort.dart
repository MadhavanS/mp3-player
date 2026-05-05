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
}

extension LibraryTrackSortModeStorage on LibraryTrackSortMode {
  String get prefsValue => switch (this) {
        LibraryTrackSortMode.modifiedNewest => 'modified_newest',
        LibraryTrackSortMode.modifiedOldest => 'modified_oldest',
        LibraryTrackSortMode.titleAZ => 'title_az',
        LibraryTrackSortMode.titleZA => 'title_za',
      };

  String get menuLabel => switch (this) {
        LibraryTrackSortMode.modifiedNewest => 'Date modified (newest first)',
        LibraryTrackSortMode.modifiedOldest => 'Date modified (oldest first)',
        LibraryTrackSortMode.titleAZ => 'Title (A–Z)',
        LibraryTrackSortMode.titleZA => 'Title (Z–A)',
      };
}

LibraryTrackSortMode? _parseSortMode(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return switch (raw) {
    'modified_newest' => LibraryTrackSortMode.modifiedNewest,
    'modified_oldest' => LibraryTrackSortMode.modifiedOldest,
    'title_az' => LibraryTrackSortMode.titleAZ,
    'title_za' => LibraryTrackSortMode.titleZA,
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
        LibraryTrackSortMode.modifiedNewest;
  }

  static Future<void> save(LibraryTrackSortMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.prefsValue);
    revision.value++;
  }
}

/// Orders filtered catalog indices; catalog order is modified-newest-first from scan.
List<int> sortFilteredTrackIndices(
  List<int> indices,
  List<TrackItem> tracks,
  LibraryTrackSortMode mode,
) {
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
  }
  return out;
}

String _basenameTitleKey(String path) =>
    p.basenameWithoutExtension(path).toLowerCase();

/// Sort immediate `.mp3` paths for the Files explorer (may stat files on IO).
Future<List<String>> sortMp3PathsForFilesExplorer(
  List<String> paths,
  LibraryTrackSortMode mode,
) async {
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
  }
}
