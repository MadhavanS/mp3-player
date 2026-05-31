import 'dart:async';

import 'package:flutter/material.dart';

import '../../../audio/player_controller.dart';
import '../../../models/library_tab_id.dart';
import '../../../models/track_item.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/track_list_album_art.dart';

class YoutubeTrackTile extends StatelessWidget {
  const YoutubeTrackTile({
    super.key,
    required this.track,
    required this.player,
    required this.allTracks,
    this.onDelete,
  });

  final TrackItem track;
  final PlayerController player;
  final List<TrackItem> allTracks;
  final Future<void> Function(TrackItem track)? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;

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
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete download',
          onPressed: onDelete == null ? null : () => unawaited(onDelete!(track)),
        ),
      ),
    );
  }
}
