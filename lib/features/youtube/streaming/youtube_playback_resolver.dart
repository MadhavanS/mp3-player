import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../storage/youtube_track_store.dart';
import 'youtube_stream_resolver.dart';

/// Chooses an [AudioSource] for YouTube playback: local file first, then stream.
///
/// Phase 1: local files only; streaming URI path is wired in a follow-up change.
class YoutubePlaybackResolver {
  YoutubePlaybackResolver._();

  static final instance = YoutubePlaybackResolver._();

  Future<AudioSource?> resolve(
    String videoId, {
    MediaItem? tag,
  }) async {
    final id = videoId.trim();
    if (id.isEmpty) return null;

    final local = await _tryLocalFile(id, tag);
    if (local != null) {
      debugPrint('[YoutubePlaybackResolver] local file for $id');
      return local;
    }

    final stream = await YoutubeStreamResolver.instance.resolve(id);
    if (stream == null) return null;

    final mediaTag = tag ??
        MediaItem(
          id: id,
          title: id,
          artist: 'YouTube',
        );

    debugPrint('[YoutubePlaybackResolver] stream URI for $id');
    return AudioSource.uri(
      Uri.parse(stream.streamUrl),
      tag: mediaTag,
    );
  }

  Future<AudioSource?> _tryLocalFile(String videoId, MediaItem? tag) async {
    final path = await YoutubeTrackStore.instance.filePathForVideoId(videoId);
    if (path == null || path.isEmpty) return null;
    return AudioSource.file(path, tag: tag);
  }
}
