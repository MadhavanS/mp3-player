import '../../../models/track_item.dart';
import 'youtube_stream_paths.dart';
import 'youtube_watch_url.dart';

/// JSON snapshot for a streaming YouTube queue row (`ytstream:…`).
Map<String, dynamic>? youtubePlaybackMetaJsonForTrack(
  String path,
  TrackItem track,
) {
  final trimmed = path.trim();
  if (!isYoutubeStreamPath(trimmed)) return null;

  final videoId = youtubeVideoIdFromStreamPath(trimmed);
  if (videoId == null || videoId.isEmpty) return null;

  final title = track.title.trim();
  final artist = track.artist.trim();
  final metaLine = track.metaLine.trim();

  return {
    'videoId': videoId,
    'watchUrl': youtubeWatchUrlForVideoId(videoId),
    'title': title.isNotEmpty ? title : videoId,
    'artist': artist.isNotEmpty ? artist : 'Unknown artist',
    if (metaLine.isNotEmpty) 'metaLine': metaLine,
    'thumbnailUrl': youtubeDefaultThumbnailUrlForVideoId(videoId),
  };
}

TrackItem trackItemFromYoutubePlaybackMeta(
  String path,
  Map<String, dynamic> meta,
) {
  final trimmed = path.trim();
  final title = (meta['title'] as String?)?.trim();
  final artist = (meta['artist'] as String?)?.trim();
  final metaLine = (meta['metaLine'] as String?)?.trim();

  return TrackItem(
    title: title != null && title.isNotEmpty
        ? title
        : (youtubeVideoIdFromStreamPath(trimmed) ?? trimmed),
    artist: artist != null && artist.isNotEmpty ? artist : 'Unknown artist',
    metaLine: metaLine != null && metaLine.isNotEmpty ? metaLine : 'YouTube',
    genres: '',
    artColors: TrackItem.fromFilePath(trimmed).artColors,
    filePath: trimmed,
  );
}

Map<String, Map<String, dynamic>> parseYoutubeByPathJson(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, Map<String, dynamic>>{};
  for (final entry in raw.entries) {
    final path = entry.key.toString().trim();
    if (path.isEmpty || !isYoutubeStreamPath(path)) continue;
    final value = entry.value;
    if (value is! Map) continue;
    out[path] = Map<String, dynamic>.from(value);
  }
  return out;
}
