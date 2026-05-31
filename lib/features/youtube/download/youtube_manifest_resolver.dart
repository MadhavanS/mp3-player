import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'youtube_stream_format.dart';

/// Resolves the best audio-only stream for a YouTube video id.
class YoutubeManifestResolver {
  YoutubeManifestResolver._();

  static final instance = YoutubeManifestResolver._();

  final YoutubeExplode _yt = YoutubeExplode();

  Future<AudioOnlyStreamInfo?> resolveAudio(String videoId) async {
    final id = videoId.trim();
    if (id.isEmpty) return null;
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(
        id,
        ytClients: [
          YoutubeApiClient.androidVr,
          YoutubeApiClient.ios,
        ],
      );
      if (manifest.audioOnly.isEmpty) return null;
      return pickPreferredAudioStream(manifest.audioOnly);
    } catch (e) {
      return null;
    }
  }

  void close() => _yt.close();
}
