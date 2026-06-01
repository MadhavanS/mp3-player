import 'dart:async';

import 'package:flutter/material.dart';

import '../../../audio/player_controller.dart';
import '../../../models/library_tab_id.dart';
import '../../../models/track_item.dart';
import '../../../services/music_library_path_key.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/track_list_album_art.dart';
import '../../library/library_track_lookup.dart';
import '../../player/track_overflow_actions.dart';
import 'youtube_library_track_menu.dart';

class YoutubeTrackTile extends StatelessWidget {
  const YoutubeTrackTile({
    super.key,
    required this.track,
    required this.player,
    required this.allTracks,
    required this.listIndex,
  });

  final TrackItem track;
  final PlayerController player;
  final List<TrackItem> allTracks;
  final int listIndex;

  int _playlistIndex(Map<String, int> indexByPathKey) {
    final path = track.filePath?.trim();
    if (path == null || path.isEmpty) return -1;
    final key = canonicalMusicLibraryPathKey(path);
    if (key.isEmpty) return -1;
    return indexByPathKey[key] ?? -1;
  }

  TrackOverflowQueueContext? _outsideQueue(int plIndex) {
    if (plIndex >= 0) return null;
    return TrackOverflowQueueContext(
      tracks: allTracks,
      index: listIndex,
      playbackOriginTab: LibraryTabId.youtube,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;
    final pathIndexMap = playlistIndexByPathKey(
      [
        for (final t in player.playlist)
          if (t.filePath != null && t.filePath!.trim().isNotEmpty) t.filePath!,
      ],
    );
    final plIndex = _playlistIndex(pathIndexMap);

    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: TrackListAlbumArt(track: track),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(color: pal.textPrimary),
        ),
        subtitle: Text(
          '${track.artist} · ${track.metaLine}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(color: pal.textSecondary),
        ),
        onTap: () {
          final path = track.filePath?.trim();
          if (path == null || path.isEmpty) return;
          var startIndex = 0;
          for (var i = 0; i < allTracks.length; i++) {
            if (allTracks[i].filePath?.trim() == path) {
              startIndex = i;
              break;
            }
          }
          unawaited(
            player.setPlaylistAndPlay(
              allTracks,
              startIndex: startIndex,
              playbackOriginTab: LibraryTabId.youtube,
            ),
          );
        },
        trailing: YoutubeLibraryTrackOverflowMenu(
          pal: pal,
          track: track,
          onSelected: (action) {
            unawaited(
              applyYoutubeLibraryTrackAction(
                context,
                player: player,
                track: track,
                playlistIndex: plIndex,
                action: action,
                outsideQueue: _outsideQueue(plIndex),
              ),
            );
          },
        ),
      ),
    );
  }
}
