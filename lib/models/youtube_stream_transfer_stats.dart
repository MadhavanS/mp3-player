import '../util/format_bytes.dart';

/// Estimated network activity while streaming YouTube audio.
class YoutubeStreamTransferStats {
  const YoutubeStreamTransferStats({
    required this.downloadRateBytesPerSec,
    required this.estimatedBytesConsumed,
    required this.bufferAhead,
    required this.streamBitrateBitsPerSec,
    required this.isBuffering,
  });

  final double downloadRateBytesPerSec;
  final int estimatedBytesConsumed;
  final Duration bufferAhead;
  final int streamBitrateBitsPerSec;
  final bool isBuffering;

  String get summaryLine {
    final rate = formatTransferRate(downloadRateBytesPerSec);
    final loaded = formatFileSize(estimatedBytesConsumed);
    final buf = bufferAhead.inSeconds;
    if (isBuffering) {
      return 'Buffering… · $rate · $loaded loaded';
    }
    if (buf > 0) {
      return '$rate · $loaded loaded · ${buf}s buffered';
    }
    return '$rate · $loaded loaded';
  }
}
