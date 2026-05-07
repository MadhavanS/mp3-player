import '../models/track_item.dart';
import 'song_metadata_cache_stub.dart'
    if (dart.library.io) 'song_metadata_cache_io.dart'
    as impl;

/// Local metadata cache used to render the library quickly on app launch.
class SongMetadataCache {
  static Future<Map<String, TrackItem>> loadTracksByPaths(List<String> paths) =>
      impl.loadTracksByPaths(paths);

  static Future<void> saveTracks(Iterable<TrackItem> tracks) =>
      impl.saveTracks(tracks);

  static Future<void> deleteMissingPaths(Set<String> existingPaths) =>
      impl.deleteMissingPaths(existingPaths);
}
