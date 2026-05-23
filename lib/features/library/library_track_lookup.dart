import '../../models/track_item.dart';
import '../../services/music_library_path_key.dart';

/// O(1) path-key → [TrackItem] for library list builders (built once per catalog rebuild).
Map<String, TrackItem> libraryTracksByPathKey(List<TrackItem> library) {
  final map = <String, TrackItem>{};
  for (final t in library) {
    final fp = t.filePath?.trim();
    if (fp == null || fp.isEmpty) continue;
    final key = canonicalMusicLibraryPathKey(fp);
    if (key.isNotEmpty) map[key] = t;
  }
  return map;
}

/// O(1) path-key → playlist index for overflow / highlight helpers.
Map<String, int> playlistIndexByPathKey(List<String> playlistPaths) {
  final map = <String, int>{};
  for (var i = 0; i < playlistPaths.length; i++) {
    final key = canonicalMusicLibraryPathKey(playlistPaths[i]);
    if (key.isNotEmpty) map[key] = i;
  }
  return map;
}

TrackItem trackForPathKey(
  String path,
  Map<String, TrackItem> byPathKey,
) {
  final key = canonicalMusicLibraryPathKey(path);
  if (key.isNotEmpty) {
    final hit = byPathKey[key];
    if (hit != null) return hit;
  }
  return TrackItem.fromFilePath(path);
}

/// Joins persisted path lists to catalog rows (bounded for tab builds).
List<TrackItem> tracksForPaths(
  List<String> paths,
  Map<String, TrackItem> byPathKey, {
  int? maxCount,
}) {
  final take = maxCount == null ? paths.length : paths.length.clamp(0, maxCount);
  final out = <TrackItem>[];
  for (var i = 0; i < take; i++) {
    out.add(trackForPathKey(paths[i], byPathKey));
  }
  return out;
}
