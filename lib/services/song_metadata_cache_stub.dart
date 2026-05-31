import '../models/track_item.dart';
import 'song_metadata_cache_types.dart';

Future<Map<String, TrackItem>> loadTracksByPaths(List<String> paths) async =>
    const <String, TrackItem>{};

Future<void> saveTracks(Iterable<TrackItem> tracks) async {}

Future<Map<String, CachedTrackSnapshot>> loadSnapshotsForRoots(
  List<String> roots,
) async =>
    const <String, CachedTrackSnapshot>{};

Future<void> saveTrackSnapshots(Iterable<CachedTrackSnapshot> tracks) async {}

Future<void> deleteMissingPaths(Set<String> existingPaths) async {}

Future<void> deletePaths(Iterable<String> paths) async {}

Future<void> markArtDiskCachedForPath(String filePath) async {}

Future<void> clearArtDiskCacheFlagForPath(String filePath) async {}

Future<bool> hasValidArtDiskCacheForPath(String filePath) async => false;

Future<Set<String>> pathKeysWithValidArtDiskCache(
  Iterable<String> filePaths,
) async =>
    const <String>{};

Future<void> clearAllSongMetadataCache() async {}
