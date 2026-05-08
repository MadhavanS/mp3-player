import '../models/track_item.dart';
import 'song_metadata_cache_types.dart';
import 'song_metadata_cache_stub.dart'
    if (dart.library.io) 'song_metadata_cache_io.dart'
    as impl;

/// Local metadata cache used to render the library quickly on app launch.
class SongMetadataCache {
  static Future<Map<String, TrackItem>> loadTracksByPaths(List<String> paths) =>
      impl.loadTracksByPaths(paths);

  /// Loads cached tracks for the provided library roots (cold-start fast path).
  static Future<Map<String, CachedTrackSnapshot>> loadSnapshotsForRoots(
    List<String> roots,
  ) => impl.loadSnapshotsForRoots(roots);

  static Future<void> saveTracks(Iterable<TrackItem> tracks) =>
      impl.saveTracks(tracks);

  /// Upserts tracks with known file modified timestamps (diff-sync path).
  static Future<void> saveTrackSnapshots(
    Iterable<CachedTrackSnapshot> tracks,
  ) => impl.saveTrackSnapshots(tracks);

  static Future<void> deleteMissingPaths(Set<String> existingPaths) =>
      impl.deleteMissingPaths(existingPaths);
}
