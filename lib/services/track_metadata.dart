import '../models/track_item.dart';
import 'track_metadata_stub.dart' if (dart.library.io) 'track_metadata_io.dart' as impl;

Future<TrackItem> readAudioMetadata(TrackItem base) => impl.readAudioMetadata(base);

/// Loads metadata in small batches to avoid UI jank from large cover extraction.
Future<void> enrichPlaylistTracks({
  required List<TrackItem> tracks,
  required void Function(String path, TrackItem updated) onTrackUpdated,
  int batchSize = 4,
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
