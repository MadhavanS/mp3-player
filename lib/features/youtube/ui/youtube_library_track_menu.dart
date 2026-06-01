import 'dart:async';

import 'package:flutter/material.dart';

import '../../../audio/player_controller.dart';
import '../../../models/library_tab_id.dart';
import '../../../models/track_item.dart';
import '../../../services/favorite_songs_store.dart';
import '../../../theme/app_theme.dart';
import '../../player/track_overflow_actions.dart';
import 'youtube_library_rename_dialog.dart';

/// Curated overflow actions for YouTube Library downloaded tracks.
enum YoutubeLibraryTrackAction {
  playNext,
  playFromHere,
  playOnly,
  addToPlaylist,
  toggleFavorite,
  rename,
  delete,
}

TrackOverflowAction _toOverflowAction(YoutubeLibraryTrackAction action) {
  return switch (action) {
    YoutubeLibraryTrackAction.playNext => TrackOverflowAction.playNext,
    YoutubeLibraryTrackAction.playFromHere => TrackOverflowAction.playFromHere,
    YoutubeLibraryTrackAction.playOnly => TrackOverflowAction.playOnlyThis,
    YoutubeLibraryTrackAction.addToPlaylist => TrackOverflowAction.addToPlaylist,
    YoutubeLibraryTrackAction.toggleFavorite => TrackOverflowAction.toggleFavorite,
    YoutubeLibraryTrackAction.rename => TrackOverflowAction.manualTagEditor,
    YoutubeLibraryTrackAction.delete => TrackOverflowAction.deleteFromDevice,
  };
}

Future<void> applyYoutubeLibraryTrackAction(
  BuildContext context, {
  required PlayerController player,
  required TrackItem track,
  required int playlistIndex,
  required YoutubeLibraryTrackAction action,
  TrackOverflowQueueContext? outsideQueue,
}) async {
  if (action == YoutubeLibraryTrackAction.rename) {
    await showYoutubeLibraryRenameDialog(context, track);
    return;
  }

  await applyTrackOverflowAction(
    context,
    player,
    playlistIndex,
    _toOverflowAction(action),
    playbackOriginTab: LibraryTabId.youtube,
    outsideQueue: outsideQueue,
  );
}

class YoutubeLibraryTrackOverflowMenu extends StatelessWidget {
  const YoutubeLibraryTrackOverflowMenu({
    super.key,
    required this.pal,
    required this.track,
    required this.onSelected,
  });

  final AppPalette pal;
  final TrackItem track;
  final ValueChanged<YoutubeLibraryTrackAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final path = track.filePath ?? '';
    final favOk = trackCanToggleFavorite(track);

    return ListenableBuilder(
      listenable: FavoriteSongsStore.revision,
      builder: (context, _) {
        final isFav = favOk && FavoriteSongsStore.isFavorite(path);
        final accent = context.controlAccent;
        final silver = context.appliedThemePalette == AppThemePalette.silver;
        final iconFg = pal.onScaffold.withValues(alpha: 0.8);

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isFav)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.favorite_rounded,
                  size: 20,
                  color: silver ? Colors.black : accent,
                ),
              ),
            PopupMenuButton<YoutubeLibraryTrackAction>(
              tooltip: 'Track options',
              icon: Icon(Icons.more_vert_rounded, color: iconFg, size: 24),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
              onSelected: onSelected,
              itemBuilder: (ctx) {
                final err = Theme.of(ctx).colorScheme.error;
                return [
                  const PopupMenuItem(
                    value: YoutubeLibraryTrackAction.playNext,
                    child: _MenuRow(
                      icon: Icons.queue_play_next_rounded,
                      label: 'Play next',
                    ),
                  ),
                  const PopupMenuItem(
                    value: YoutubeLibraryTrackAction.playFromHere,
                    child: _MenuRow(
                      icon: Icons.playlist_play_rounded,
                      label: 'Play from here',
                    ),
                  ),
                  const PopupMenuItem(
                    value: YoutubeLibraryTrackAction.playOnly,
                    child: _MenuRow(
                      icon: Icons.music_note_rounded,
                      label: 'Play this track only',
                    ),
                  ),
                  const PopupMenuItem(
                    value: YoutubeLibraryTrackAction.addToPlaylist,
                    child: _MenuRow(
                      icon: Icons.playlist_add_rounded,
                      label: 'Add to playlist',
                    ),
                  ),
                  if (favOk)
                    PopupMenuItem(
                      value: YoutubeLibraryTrackAction.toggleFavorite,
                      child: _MenuRow(
                        icon: isFav
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        label: isFav
                            ? 'Remove from favourites'
                            : 'Add to favourites',
                      ),
                    ),
                  if (trackCanEditTags(track))
                    const PopupMenuItem(
                      value: YoutubeLibraryTrackAction.rename,
                      child: _MenuRow(
                        icon: Icons.drive_file_rename_outline_rounded,
                        label: 'Rename',
                      ),
                    ),
                  if (trackCanDeleteFromDevice(track)) ...[
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: YoutubeLibraryTrackAction.delete,
                      child: _MenuRow(
                        icon: Icons.delete_outline_rounded,
                        label: 'Delete',
                        iconColor: err,
                        labelColor: err,
                      ),
                    ),
                  ],
                ];
              },
            ),
          ],
        );
      },
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    this.iconColor,
    this.labelColor,
  });

  final IconData icon;
  final String label;
  final Color? iconColor;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 22, color: iconColor),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 14, color: labelColor),
          ),
        ),
      ],
    );
  }
}
