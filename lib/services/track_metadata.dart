import '../models/track_item.dart';
import 'track_metadata_stub.dart' if (dart.library.io) 'track_metadata_io.dart' as impl;

Future<TrackItem> readAudioMetadata(TrackItem base) => impl.readAudioMetadata(base);

/// Loads metadata in small batches to avoid UI jank from large cover extraction.
Future<void> enrichPlaylistTracks({
  required List<TrackItem> tracks,
  required void Function(String path, TrackItem updated) onTrackUpdated,
  int batchSize = 1,
  Duration interBatchDelay = const Duration(milliseconds: 80),
  int? maxTracks,
  bool Function()? shouldContinue,
}) async {
  final withPath = tracks
      .where((t) => t.filePath != null && t.filePath!.isNotEmpty)
      .toList(growable: false);
  final limit = maxTracks == null
      ? withPath.length
      : maxTracks.clamp(0, withPath.length);
  if (limit == 0) return;

  final effectiveBatch = batchSize.clamp(1, 2);
  for (var i = 0; i < limit; i += effectiveBatch) {
    if (shouldContinue != null && !shouldContinue()) return;
    final batch = withPath.skip(i).take(effectiveBatch);
    for (final t in batch) {
      if (shouldContinue != null && !shouldContinue()) return;
      final updated = await readAudioMetadata(t);
      final path = t.filePath!;
      onTrackUpdated(path, updated);
    }
    final hasMore = i + effectiveBatch < limit;
    if (hasMore && interBatchDelay > Duration.zero) {
      await Future<void>.delayed(interBatchDelay);
    }
  }
}
