import 'dart:io';

import '../../models/track_item.dart';
import '../../services/music_library_path_key.dart';
import 'models/youtube_track.dart';
import 'search/youtube_bookmark_store.dart';
import 'storage/youtube_track_record.dart';
import 'storage/youtube_track_store.dart';
import 'youtube_stream_paths.dart';

/// True when [track] is a YouTube stream or download row.
bool isYoutubePlaybackTrack(TrackItem track) {
  final path = track.filePath?.trim() ?? '';
  if (path.isEmpty) return false;
  if (isYoutubeStreamPath(path)) return true;
  if (isYoutubeDownloadStoragePath(path)) return true;
  return track.metaLine.toLowerCase().contains('youtube');
}

/// Resolves the YouTube video id for a playing [TrackItem], if any.
Future<String?> youtubeVideoIdForTrackItem(TrackItem track) async {
  final path = track.filePath?.trim() ?? '';
  if (path.isEmpty) return null;

  final fromStream = youtubeVideoIdFromStreamPath(path);
  if (fromStream != null) return fromStream;

  if (isYoutubeDownloadStoragePath(path)) {
    final record = await YoutubeTrackStore.instance.findByLocalPath(path);
    if (record != null) return record.videoId;
  }
  return null;
}

/// Metadata for download UI and thumbnails on Now Playing.
Future<YoutubeTrack?> youtubeTrackForPlayerItem(TrackItem track) async {
  final videoId = await youtubeVideoIdForTrackItem(track);
  if (videoId == null || videoId.isEmpty) return null;

  final record = await YoutubeTrackStore.instance.get(videoId);
  final bookmark = await YoutubeBookmarkStore.findByVideoId(videoId);
  final localPath = record?.localPath?.trim();
  final hasFile =
      localPath != null && localPath.isNotEmpty && await _fileExists(localPath);

  if (hasFile && record != null) {
    return YoutubeTrack(
      videoId: videoId,
      title: track.title.trim().isNotEmpty ? track.title : record.title,
      artist: track.artist.trim().isNotEmpty ? track.artist : record.artist,
      thumbnailUrl: record.thumbnailUrl,
      duration: _durationFromRecord(record) ?? bookmark?.duration,
    );
  }

  return YoutubeTrack(
    videoId: videoId,
    title: track.title.trim().isNotEmpty
        ? track.title
        : (record?.title ?? bookmark?.title ?? videoId),
    artist: track.artist.trim().isNotEmpty
        ? track.artist
        : (record?.artist ?? bookmark?.artist ?? 'Unknown artist'),
    thumbnailUrl: record?.thumbnailUrl?.trim().isNotEmpty == true
        ? record!.thumbnailUrl
        : bookmark?.thumbnailUrl,
    duration: _durationFromRecord(record) ?? bookmark?.duration,
  );
}

Duration? _durationFromRecord(YoutubeTrackRecord? record) {
  if (record == null) return null;
  final ms = record.durationMs;
  if (ms == null || ms <= 0) return null;
  return Duration(milliseconds: ms);
}

Future<bool> _fileExists(String path) async {
  try {
    return await File(path).exists();
  } catch (_) {
    return false;
  }
}
