import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Picks the most compatible audio stream for local playback (M4A/AAC first).
AudioOnlyStreamInfo? pickPreferredAudioStream(
  Iterable<AudioOnlyStreamInfo> streams,
) {
  final list = streams.toList(growable: false);
  if (list.isEmpty) return null;

  final mp4 = list.where((s) => s.container == StreamContainer.mp4).toList();
  if (mp4.isNotEmpty) {
    return mp4.withHighestBitrate();
  }

  final webm = list.where((s) => s.container == StreamContainer.webM).toList();
  if (webm.isNotEmpty) {
    return webm.withHighestBitrate();
  }

  return list.withHighestBitrate();
}

/// File extension for a downloaded audio stream.
String fileExtensionForStream(StreamContainer container) {
  if (container == StreamContainer.mp4) return 'm4a';
  if (container == StreamContainer.webM) return 'webm';
  return container.name;
}

/// Human-readable container label for library UI.
String containerLabelForStream(StreamContainer container) {
  if (container == StreamContainer.mp4) return 'M4A';
  if (container == StreamContainer.webM) return 'WebM';
  return container.name.toUpperCase();
}
