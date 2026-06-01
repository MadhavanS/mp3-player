import 'package:flutter/material.dart';

import '../../audio/player_controller.dart';
import '../../models/library_tab_id.dart';
import '../../models/track_item.dart';
import 'thumbnail/youtube_album_art.dart';
import 'youtube_duration_format.dart';
import 'models/youtube_track.dart';
import 'storage/youtube_track_store.dart';
import 'youtube_stream_paths.dart';

TrackItem trackItemForYoutubeSearch(
  YoutubeTrack track, {
  required String filePath,
}) {
  final durationLabel = track.duration != null
      ? formatYoutubeDurationMs(track.duration!.inMilliseconds)
      : '';
  return TrackItem(
    title: track.title,
    artist: track.artist,
    metaLine: durationLabel.isEmpty ? 'YouTube' : 'YouTube · $durationLabel',
    genres: '',
    artColors: TrackItem.fromFilePath(track.videoId).artColors,
    filePath: filePath,
  );
}

/// One [TrackItem] for a search result (local file or stream path).
Future<TrackItem?> trackItemForYoutubeSearchTrack(YoutubeTrack track) async {
  final items = await trackItemsForYoutubeSearchResults([track]);
  return items.isEmpty ? null : items.first;
}

/// Builds playlist rows for search results (local file or stream path).
Future<List<TrackItem>> trackItemsForYoutubeSearchResults(
  List<YoutubeTrack> results,
) async {
  final store = YoutubeTrackStore.instance;
  final out = <TrackItem>[];
  for (final yt in results) {
    final local = await store.filePathForVideoId(yt.videoId);
    final path = local ?? youtubeStreamPathForVideoId(yt.videoId);
    var item = trackItemForYoutubeSearch(yt, filePath: path);
    final artBytes = await resolveYoutubeAlbumArtForPath(path);
    if (artBytes != null && artBytes.isNotEmpty) {
      item = item.withEmbeddedMetadata(
        albumArtBytes: artBytes,
        replaceAlbumArtFromFile: true,
      );
    }
    out.add(item);
  }
  return out;
}

/// Plays one search result and queues the visible result list.
Future<void> playYoutubeSearchResult({
  required BuildContext context,
  required PlayerController player,
  required List<YoutubeTrack> results,
  required int index,
}) async {
  if (results.isEmpty || index < 0 || index >= results.length) return;

  final items = await trackItemsForYoutubeSearchResults(results);
  if (items.isEmpty) return;

  // Folder browse scope only applies to local library paths.
  player.setPlaybackPathKeyScope(null, reloadQueue: false);

  await player.setPlaylistAndPlay(
    items,
    startIndex: index.clamp(0, items.length - 1),
    playbackOriginTab: LibraryTabId.youtubeSearch,
  );
}
