import 'package:flutter/foundation.dart';
import 'package:metadata_god/metadata_god.dart';

import '../models/track_item.dart';

/// Reads tags via [metadata_god] (MP3, M4A, OGG, FLAC).
Future<TrackItem> readAudioMetadata(TrackItem base) async {
  final path = base.filePath;
  if (path == null || path.isEmpty) return base;

  try {
    final m = await MetadataGod.readMetadata(file: path);
    return base.withEmbeddedMetadata(
      title: m.title,
      artist: m.artist ?? m.albumArtist,
      album: m.album,
      genre: m.genre,
      albumArtBytes: m.picture?.data,
    );
  } catch (e, st) {
    debugPrint('readAudioMetadata: $e\n$st');
    return base;
  }
}

/// Loads metadata in small batches to avoid starving the UI isolate.
Future<void> enrichPlaylistTracks({
  required List<TrackItem> tracks,
  required void Function(String path, TrackItem updated) onTrackUpdated,
  int batchSize = 6,
}) async {
  final withPath =
      tracks.where((t) => t.filePath != null && t.filePath!.isNotEmpty).toList();
  for (var i = 0; i < withPath.length; i += batchSize) {
    final batch = withPath.skip(i).take(batchSize);
    await Future.wait(batch.map((t) async {
      final updated = await readAudioMetadata(t);
      final path = t.filePath!;
      onTrackUpdated(path, updated);
    }));
  }
}
