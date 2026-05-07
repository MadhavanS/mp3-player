import '../models/track_item.dart';

Future<Map<String, TrackItem>> loadTracksByPaths(List<String> paths) async =>
    const <String, TrackItem>{};

Future<void> saveTracks(Iterable<TrackItem> tracks) async {}

Future<void> deleteMissingPaths(Set<String> existingPaths) async {}
