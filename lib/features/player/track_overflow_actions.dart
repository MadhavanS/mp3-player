import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../audio/player_controller.dart';
import '../../models/library_tab_id.dart';
import '../../models/track_item.dart';
import '../../services/favorite_songs_store.dart';
import '../../services/music_library_path_key.dart';
import '../../services/song_metadata_cache.dart';
import '../../services/track_file_delete.dart';
import '../../services/user_playlists_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/action_pill_toast.dart';
import '../../widgets/create_playlist_name_dialog.dart';
import '../../widgets/player_adaptive_controls.dart';
import 'edit_track_tags_sheet.dart';
import 'site_rename_standalone_dialog.dart';

enum TrackOverflowAction {
  playNext,
  playFromHere,
  playOnlyThis,
  addToPlaylist,
  removeFromPlaylist,
  toggleFavorite,
  autoTag,
  manualTagEditor,
  deleteFromDevice,
}

bool trackCanDeleteFromDevice(TrackItem track) =>
    !kIsWeb && track.filePath != null && track.filePath!.isNotEmpty;

bool trackCanToggleFavorite(TrackItem track) =>
    !kIsWeb && track.filePath != null && track.filePath!.isNotEmpty;

bool trackCanEditTags(TrackItem track) =>
    !kIsWeb && track.filePath != null && track.filePath!.isNotEmpty;

Widget _compactOverflowMenuRow({
  required IconData icon,
  required String label,
  Color? iconColor,
  Color? labelColor,
}) {
  return ListTile(
    dense: true,
    visualDensity: VisualDensity.compact,
    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    minLeadingWidth: 28,
    horizontalTitleGap: 12,
    leading: Icon(icon, size: 20, color: iconColor),
    title: Text(
      label,
      style: TextStyle(fontSize: 14, color: labelColor),
    ),
  );
}

List<PopupMenuEntry<TrackOverflowAction>> trackOverflowPopupMenuEntries({
  required bool enableDeleteFromDevice,
  bool enableFavorite = false,
  bool isFavorite = false,
  bool enableTagEditor = false,
}) {
  return [
    PopupMenuItem(
      value: TrackOverflowAction.playNext,
      child: _compactOverflowMenuRow(
        icon: Icons.queue_play_next_rounded,
        label: 'Play next',
      ),
    ),
    PopupMenuItem(
      value: TrackOverflowAction.playFromHere,
      child: _compactOverflowMenuRow(
        icon: Icons.playlist_play_rounded,
        label: 'Play from here',
      ),
    ),
    PopupMenuItem(
      value: TrackOverflowAction.playOnlyThis,
      child: _compactOverflowMenuRow(
        icon: Icons.music_note_rounded,
        label: 'Play this song only',
      ),
    ),
    PopupMenuItem(
      value: TrackOverflowAction.addToPlaylist,
      child: _compactOverflowMenuRow(
        icon: Icons.playlist_add_rounded,
        label: 'Add to playlist',
      ),
    ),
    if (enableFavorite)
      PopupMenuItem(
        value: TrackOverflowAction.toggleFavorite,
        child: _compactOverflowMenuRow(
          icon: isFavorite
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          label: isFavorite ? 'Remove from favourites' : 'Add to favourites',
        ),
      ),
    if (enableTagEditor) ...[
      const PopupMenuDivider(),
      PopupMenuItem(
        value: TrackOverflowAction.autoTag,
        child: _compactOverflowMenuRow(
          icon: Icons.auto_fix_high_outlined,
          label: 'Clean site-style name',
        ),
      ),
      PopupMenuItem(
        value: TrackOverflowAction.manualTagEditor,
        child: _compactOverflowMenuRow(
          icon: Icons.edit_note_rounded,
          label: 'Manual tag editor',
        ),
      ),
    ],
    if (enableDeleteFromDevice) ...[
      const PopupMenuDivider(),
      PopupMenuItem(
        value: TrackOverflowAction.deleteFromDevice,
        child: Builder(
          builder: (ctx) {
            final err = Theme.of(ctx).colorScheme.error;
            return _compactOverflowMenuRow(
              icon: Icons.delete_outline_rounded,
              label: 'Delete from device',
              iconColor: err,
              labelColor: err,
            );
          },
        ),
      ),
    ],
  ];
}

/// Filled heart when favourited + track overflow menu (library / files lists).
class TrackOverflowMenuWithFavourite extends StatelessWidget {
  const TrackOverflowMenuWithFavourite({
    super.key,
    required this.pal,
    required this.track,
    required this.onSelected,
    this.overflowIcon = Icons.more_horiz_rounded,
    this.iconSize = 24,
    this.menuIconColor,
  });

  final AppPalette pal;
  final TrackItem track;
  final ValueChanged<TrackOverflowAction> onSelected;
  final IconData overflowIcon;
  final double iconSize;

  /// Defaults to [AppPalette.onScaffold] at 80% opacity (library). Files explorer
  /// passes a muted variant so the heart still uses [BuildContext.controlAccent].
  final Color? menuIconColor;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FavoriteSongsStore.revision,
      builder: (context, _) {
        final path = track.filePath ?? '';
        final favOk = trackCanToggleFavorite(track);
        final isFav = favOk && FavoriteSongsStore.isFavorite(path);
        final accent = context.controlAccent;
        final silver = context.appliedThemePalette == AppThemePalette.silver;
        final iconFg = menuIconColor ?? pal.onScaffold.withValues(alpha: 0.8);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isFav)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.favorite_rounded,
                  size: iconSize * 0.85,
                  color: silver ? Colors.black : accent,
                ),
              ),
            PopupMenuButton<TrackOverflowAction>(
              tooltip: 'Track options',
              icon: Icon(overflowIcon, color: iconFg, size: iconSize),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 200, maxWidth: 248),
              onSelected: onSelected,
              itemBuilder: (ctx) => trackOverflowPopupMenuEntries(
                enableDeleteFromDevice: trackCanDeleteFromDevice(track),
                enableFavorite: favOk,
                isFavorite: isFav,
                enableTagEditor: trackCanEditTags(track),
              ),
            ),
          ],
        );
      },
    );
  }
}

Future<void> _showUserPlaylistPickerAndAdd(
  BuildContext context,
  String filePath,
) async {
  final raw = filePath.trim();
  if (raw.isEmpty) {
    if (context.mounted) {
      ActionPillToast.show(context, 'No file path', uppercaseLabel: true);
    }
    return;
  }

  final playlists = await UserPlaylistsStore.loadAll();
  if (!context.mounted) return;

  final pal = context.palette;
  final theme = Theme.of(context);

  Future<void> createNewAndAdd(BuildContext sheetContext) async {
    final name = await showCreatePlaylistNameDialogWithExistingNames(
      context,
      existingNames: playlists.map((p) => p.name).toSet(),
    );
    if (!sheetContext.mounted) return;
    if (name == null || name.trim().isEmpty) return;
    final trimmed = name.trim();
    final id = await UserPlaylistsStore.createPlaylist(trimmed);
    if (id == null) {
      if (context.mounted) {
        ActionPillToast.show(
          context,
          'Playlist name already exists. Please rename it.',
          uppercaseLabel: true,
        );
      }
      return;
    }
    final added = await UserPlaylistsStore.addPathToPlaylist(id, raw);
    if (added && context.mounted) {
      await PlayerController.of(
        context,
      ).syncAddedSongToActiveUserPlaylistQueue(id, raw);
    }
    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
    if (!context.mounted) return;
    ActionPillToast.show(
      context,
      added ? 'Added to $trimmed' : 'Already exists in this playlist',
      uppercaseLabel: true,
    );
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: pal.surface,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      'Add to playlist',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: pal.textPrimary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => createNewAndAdd(ctx),
                    child: const Text('Create new'),
                  ),
                ],
              ),
            ),
            if (playlists.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Text(
                  'No playlists yet. Tap Create new to make one and add this song.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: pal.textSecondary,
                  ),
                ),
              )
            else
              SizedBox(
                height: min(
                  MediaQuery.sizeOf(ctx).height * 0.5,
                  120 + playlists.length * 56.0,
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: playlists.length,
                  itemBuilder: (context, i) {
                    final pl = playlists[i];
                    return ListTile(
                      leading: Icon(
                        Icons.queue_music_rounded,
                        color: context.controlAccent,
                      ),
                      title: Text(
                        pl.name,
                        style: TextStyle(color: pal.textPrimary),
                      ),
                      subtitle: Text(
                        '${pl.paths.length} songs',
                        style: TextStyle(color: pal.textSecondary),
                      ),
                      onTap: () async {
                        final added =
                            await UserPlaylistsStore.addPathToPlaylist(
                              pl.id,
                              raw,
                            );
                        if (added && context.mounted) {
                          await PlayerController.of(
                            context,
                          ).syncAddedSongToActiveUserPlaylistQueue(pl.id, raw);
                        }
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        if (!context.mounted) return;
                        ActionPillToast.show(
                          context,
                          added
                              ? 'Added to ${pl.name}'
                              : 'Already exists in ${pl.name}',
                          uppercaseLabel: true,
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// When the row isn’t in [PlayerController.playlist] (e.g. queue is Favourites),
/// play actions use this list + index ([playbackOriginTab] for NP dismiss).
class TrackOverflowQueueContext {
  const TrackOverflowQueueContext({
    required this.tracks,
    required this.index,
    required this.playbackOriginTab,
  });

  final List<TrackItem> tracks;
  final int index;
  final LibraryTabId playbackOriginTab;
}

Future<void> applyTrackOverflowAction(
  BuildContext context,
  PlayerController player,
  int playlistIndex,
  TrackOverflowAction action, {
  LibraryTabId? playbackOriginTab,
  TrackOverflowQueueContext? outsideQueue,
  String? userPlaylistId,
}) async {
  var tracks = player.playlist;
  var ix = playlistIndex;
  if (ix < 0 || ix >= tracks.length) {
    final o = outsideQueue;
    if (o == null) return;
    tracks = o.tracks;
    ix = o.index;
    if (ix < 0 || ix >= tracks.length) return;
  }

  final tab = playbackOriginTab ?? outsideQueue?.playbackOriginTab;

  switch (action) {
    case TrackOverflowAction.playNext:
      final t = tracks[ix];
      final added = await player.playTrackNext(t, playbackOriginTab: tab);
      if (context.mounted) {
        if (added) {
          ActionPillToast.show(
            context,
            'Queued as next',
            icon: Icons.queue_play_next_rounded,
            uppercaseLabel: true,
          );
        } else {
          ActionPillToast.show(
            context,
            'Already playing',
            uppercaseLabel: true,
          );
        }
      }

    case TrackOverflowAction.playFromHere:
      await player.setPlaylistAndPlay(
        tracks.sublist(ix),
        playbackOriginTab: tab ?? LibraryTabId.songs,
        keepShuffleMode: true,
      );

    case TrackOverflowAction.playOnlyThis:
      await player.setPlaylistAndPlay(
        [tracks[ix]],
        playbackOriginTab: tab ?? LibraryTabId.songs,
        keepShuffleMode: true,
      );

    case TrackOverflowAction.addToPlaylist:
      final t = tracks[ix];
      final path = t.filePath;
      if (path == null || path.isEmpty) {
        if (context.mounted) {
          ActionPillToast.show(
            context,
            'Need a local file',
            uppercaseLabel: true,
          );
        }
        return;
      }
      await _showUserPlaylistPickerAndAdd(context, path);

    case TrackOverflowAction.removeFromPlaylist:
      final pid = userPlaylistId;
      final p = tracks[ix].filePath;
      if (pid == null || p == null || p.isEmpty) return;
      await UserPlaylistsStore.removePathFromPlaylist(pid, p);
      if (context.mounted) {
        ActionPillToast.show(
          context,
          'Removed from playlist',
          uppercaseLabel: true,
        );
      }
      if (player.playbackOriginUserPlaylistId == pid) {
        final rk = canonicalMusicLibraryPathKey(p);
        var queueIx = -1;
        for (var j = 0; j < player.playlist.length; j++) {
          final fp = player.playlist[j].filePath;
          if (fp == null || fp.isEmpty) continue;
          if (rk.isNotEmpty) {
            if (canonicalMusicLibraryPathKey(fp) == rk) {
              queueIx = j;
              break;
            }
          } else if (fp == p) {
            queueIx = j;
            break;
          }
        }
        if (queueIx >= 0) {
          final wasPlaying = player.isPlaying;
          final removingCurrent = queueIx == player.currentIndex;
          await player.removePlaylistEntryAt(
            queueIx,
            resumePlayingIfCurrentRemoved: wasPlaying && removingCurrent,
          );
        }
      }

    case TrackOverflowAction.toggleFavorite:
      final t = tracks[ix];
      final path = t.filePath;
      if (path == null || path.isEmpty || kIsWeb) return;
      final nowFav = await FavoriteSongsStore.toggleFavorite(path);
      if (context.mounted) {
        ActionPillToast.showUsingRootNavigator(
          nowFav ? 'Favourited' : 'Removed from favourites',
          icon: nowFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          uppercaseLabel: true,
        );
      }

    case TrackOverflowAction.autoTag:
      await showStandaloneSiteRenameDialog(context, tracks[ix]);

    case TrackOverflowAction.manualTagEditor:
      await showManualTagEditor(context, tracks[ix]);

    case TrackOverflowAction.deleteFromDevice:
      final track = tracks[ix];
      final path = track.filePath;
      if (path == null || path.isEmpty) return;

      final basename = p.basename(path);
      final confirmed = await showPlayerConfirmDialog(
        context: context,
        title: 'Delete from device?',
        message:
            'This permanently removes the file from storage.\n'
            '$basename\n\n'
            'This cannot be undone.',
        cancelLabel: 'Cancel',
        confirmLabel: 'Delete',
        destructive: true,
      );
      if (confirmed != true || !context.mounted) return;

      final wasPlaying = player.isPlaying;
      final targetsCurrent = player.currentTrack?.filePath == path;

      if (targetsCurrent) {
        await player.stopForExternalFileEdit();
      }

      final err = await deleteMusicFileOrError(path);

      if (err != null) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Could not delete: $err')));
        }
        if (targetsCurrent) {
          await player.reloadCurrentSource();
          if (wasPlaying && context.mounted) {
            await player.play();
          }
        }
        return;
      }

      player.removeFromLibraryCatalogByPath(path);
      unawaited(SongMetadataCache.deletePaths([path]));
      final queueIx = player.playlist.indexWhere((t) => t.filePath == path);
      if (queueIx >= 0) {
        await player.removePlaylistEntryAt(
          queueIx,
          resumePlayingIfCurrentRemoved: wasPlaying && targetsCurrent,
        );
      }

      if (context.mounted) {
        ActionPillToast.show(context, 'Deleted', uppercaseLabel: true);
      }
  }
}
