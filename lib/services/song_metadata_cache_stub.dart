import '../models/track_item.dart';
import 'song_metadata_cache_types.dart';

Future<Map<String, TrackItem>> loadTracksByPaths(List<String> paths) async =>
    const <String, TrackItem>{};

Future<void> saveTracks(Iterable<TrackItem> tracks) async {}

Future<Map<String, CachedTrackSnapshot>> loadSnapshotsForRoots(
  List<String> roots,
) async => const <String, CachedTrackSnapshot>{};

Future<void> saveTrackSnapshots(Iterable<CachedTrackSnapshot> tracks) async {}

Future<void> deleteMissingPaths(Set<String> existingPaths) async {}
