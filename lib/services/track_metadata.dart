import 'dart:typed_data';

import '../models/track_item.dart';
import 'mp3_scanner_types.dart';
import 'song_metadata_cache_types.dart';
import 'track_metadata_stub.dart' if (dart.library.io) 'track_metadata_io.dart' as impl;

Future<TrackItem> readAudioMetadata(TrackItem base) => impl.readAudioMetadata(base);

Future<Uint8List?> readCoverBytesOnly(String filePath) =>
    impl.readCoverBytesOnly(filePath);

Future<String?> readEmbeddedComposer(String filePath) =>
    impl.readEmbeddedComposer(filePath);

int _adaptiveBatchSize({required bool isPlaying, required int libraryLength}) {
  if (isPlaying) return 1;
  if (libraryLength > 2000) return 6;
  if (libraryLength > 500) return 4;
  return 8;
}

Duration _adaptiveDelay({required bool isPlaying}) =>
    Duration(milliseconds: isPlaying ? 300 : 12);

/// Loads metadata in small batches to avoid UI jank from large cover extraction.
Future<void> enrichPlaylistTracks({
  required List<TrackItem> tracks,
  required void Function(String path, TrackItem updated) onTrackUpdated,
  Map<String, ScannedMp3File>? scannedByPath,
  Map<String, CachedTrackSnapshot>? snapshotsByPath,
  bool backgroundSyncPending = false,
  bool isPlaying = false,
  int? libraryLength,
  int? batchSize,
  Duration? interBatchDelay,
}) async {
  final withPath =
      tracks.where((t) => t.filePath != null && t.filePath!.isNotEmpty).toList();
  if (withPath.isEmpty) return;

  final effectiveBatchSize =
      batchSize ??
      _adaptiveBatchSize(
        isPlaying: isPlaying,
        libraryLength: libraryLength ?? withPath.length,
      );
  final effectiveDelay =
      interBatchDelay ?? _adaptiveDelay(isPlaying: isPlaying);

  for (var i = 0; i < withPath.length; i += effectiveBatchSize) {
    final batch = withPath.skip(i).take(effectiveBatchSize);
    await Future.wait(batch.map((t) async {
      final path = t.filePath!;
      final scanned = scannedByPath?[path];
      final snap = snapshotsByPath?[path];
      final fingerprintMatches =
          scanned != null &&
          snap != null &&
          snap.fileModifiedMs == scanned.lastModifiedMs &&
          snap.fileSizeBytes == scanned.fileSizeBytes;

      if (fingerprintMatches) {
        return;
      }
      if (backgroundSyncPending && scanned != null) {
        return;
      }

      final updated = await readAudioMetadata(t);
      onTrackUpdated(path, updated);
    }));
    final hasMore = i + effectiveBatchSize < withPath.length;
    if (hasMore && effectiveDelay > Duration.zero) {
      await Future<void>.delayed(effectiveDelay);
    }
  }
}
