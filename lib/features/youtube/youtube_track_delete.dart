import 'dart:async';

import '../../audio/player_controller.dart';
import '../../services/favorite_songs_store.dart';
import '../../services/music_library_path_key.dart';
import '../../services/recently_added_store.dart';
import '../../services/recently_played_store.dart';
import '../../services/song_metadata_cache.dart';
import '../../services/user_playlists_store.dart';
import 'catalog/youtube_library_catalog.dart';
import 'download/youtube_download_manager.dart';
import 'download/youtube_download_queue_store.dart';
import 'storage/youtube_track_store.dart';
import 'thumbnail/youtube_thumbnail_cache.dart';
import 'youtube_video_id.dart';

/// Deletes a YouTube download and removes it from player state everywhere.
Future<void> deleteYoutubeDownload({
  required PlayerController player,
  required String filePath,
  String? videoId,
}) async {
  final path = filePath.trim();
  if (path.isEmpty) return;

  final id = videoId ?? parseYoutubeVideoIdFromPath(path);
  if (id == null || id.isEmpty) return;

  YoutubeDownloadManager.instance.cancel(id);

  final pathKey = canonicalMusicLibraryPathKey(path);
  final wasPlaying = player.isPlaying;
  final curPath = player.currentTrack?.filePath?.trim();
  final targetsCurrent =
      curPath != null &&
      curPath.isNotEmpty &&
      canonicalMusicLibraryPathKey(curPath) == pathKey;

  if (targetsCurrent) {
    await player.stopForExternalFileEdit();
  }

  await YoutubeTrackStore.instance.delete(id);
  await YoutubeDownloadQueueStore.remove(id);
  await YoutubeThumbnailCache.instance.deleteForVideoId(id);
  await player.evictArtCachesForPath(path);
  player.removeFromLibraryCatalogByPath(path);
  unawaited(SongMetadataCache.deletePaths([path]));
  await Future.wait([
    FavoriteSongsStore.removePath(path),
    RecentlyPlayedStore.removePath(path),
    RecentlyAddedStore.removePathKey(path),
    UserPlaylistsStore.removePathFromAllPlaylists(path),
  ]);

  var resumedCurrentRemoval = false;
  while (true) {
    var queueIx = -1;
    for (var qi = 0; qi < player.playlist.length; qi++) {
      final fp = player.playlist[qi].filePath?.trim();
      if (fp == null || fp.isEmpty) continue;
      if (canonicalMusicLibraryPathKey(fp) == pathKey) {
        queueIx = qi;
        break;
      }
    }
    if (queueIx < 0) break;
    final isCurrentQueueItem = queueIx == player.currentIndex;
    await player.removePlaylistEntryAt(
      queueIx,
      resumePlayingIfCurrentRemoved:
          isCurrentQueueItem && wasPlaying && !resumedCurrentRemoval,
    );
    if (isCurrentQueueItem) {
      resumedCurrentRemoval = true;
    }
  }

  await YoutubeLibraryCatalog.instance.reload();
}
