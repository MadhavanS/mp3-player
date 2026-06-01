import 'dart:typed_data';

import '../../../services/album_art_cache.dart';
import '../../../services/album_art_dimensions.dart';
import '../../../services/music_library_path_key.dart';
import '../search/youtube_bookmark_store.dart';
import '../storage/youtube_track_store.dart';
import '../youtube_stream_paths.dart';
import 'youtube_thumbnail_cache.dart';

/// Thumbnail URL from Isar or bookmarks.
Future<String?> youtubeThumbnailUrlForVideoId(String videoId) async {
  final id = videoId.trim();
  if (id.isEmpty) return null;
  final record = await YoutubeTrackStore.instance.get(id);
  final fromRecord = record?.thumbnailUrl?.trim();
  if (fromRecord != null && fromRecord.isNotEmpty) return fromRecord;
  final bookmark = await YoutubeBookmarkStore.findByVideoId(id);
  final fromBookmark = bookmark?.thumbnailUrl?.trim();
  if (fromBookmark != null && fromBookmark.isNotEmpty) return fromBookmark;
  return null;
}

Future<String?> _videoIdForArtPath(String path) async {
  final fromStream = youtubeVideoIdFromStreamPath(path);
  if (fromStream != null) return fromStream;
  if (isYoutubeDownloadStoragePath(path)) {
    final record = await YoutubeTrackStore.instance.findByLocalPath(path);
    return record?.videoId;
  }
  return null;
}

/// Loads YouTube cover bytes and primes the path-keyed album-art disk cache.
Future<Uint8List?> resolveYoutubeAlbumArtForPath(
  String path, {
  int targetDimension = kAlbumArtPrimeDimension,
}) async {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return null;

  final videoId = await _videoIdForArtPath(trimmed);
  if (videoId == null || videoId.isEmpty) return null;

  final thumbUrl = await youtubeThumbnailUrlForVideoId(videoId);
  final bytes = await YoutubeThumbnailCache.instance.getThumbnailBytes(
    videoId,
    thumbUrl,
  );
  if (bytes == null || bytes.isEmpty) return null;

  await primeAlbumArtDiskCache(trimmed, bytes);
  final dim = clampAlbumArtDimension(targetDimension);
  final scaled = await cachedAlbumArtForPathAnyDimension(
    trimmed,
    targetDimension: dim,
  );
  return scaled ?? bytes;
}

bool pathUsesYoutubeAlbumArt(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return false;
  return isYoutubeStreamPath(trimmed) || isYoutubeDownloadStoragePath(trimmed);
}
