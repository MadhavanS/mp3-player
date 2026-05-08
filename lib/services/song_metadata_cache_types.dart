import '../models/track_item.dart';

class CachedTrackSnapshot {
  const CachedTrackSnapshot({
    required this.track,
    required this.fileModifiedMs,
    required this.fileSizeBytes,
  });

  final TrackItem track;
  final int fileModifiedMs;
  final int fileSizeBytes;
}
