import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/youtube_track.dart';

/// YouTube search (metadata only — playback uses downloaded local files).
class YoutubeSearchService {
  YoutubeSearchService._();

  static final instance = YoutubeSearchService._();

  final YoutubeExplode _yt = YoutubeExplode();

  Future<List<YoutubeTrack>> search(String query, {int limit = 25}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    try {
      final list = await _yt.search.search(q);
      final videos = list.take(limit);
      return videos.map(_trackFromVideo).toList(growable: false);
    } catch (e, st) {
      debugPrint('YoutubeSearchService.search: $e\n$st');
      return const [];
    }
  }

  Future<YoutubeTrack?> resolveVideo(String videoIdOrUrl) async {
    try {
      final video = await _yt.videos.get(videoIdOrUrl);
      return _trackFromVideo(video);
    } catch (e, st) {
      debugPrint('YoutubeSearchService.resolveVideo: $e\n$st');
      return null;
    }
  }

  YoutubeTrack _trackFromVideo(Video video) {
    return YoutubeTrack(
      videoId: video.id.value,
      title: video.title,
      artist: video.author,
      thumbnailUrl: video.thumbnails.mediumResUrl,
      duration: video.duration,
    );
  }

  void close() => _yt.close();
}
