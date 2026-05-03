import 'dart:math' show min;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../audio/player_controller.dart';
import '../../models/track_item.dart';
import '../../services/track_file_delete.dart';
import '../../services/user_playlists_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/action_pill_toast.dart';

enum TrackOverflowAction {
  playFromHere,
  playOnlyThis,
  addToPlaylist,
  deleteFromDevice,
}

bool trackCanDeleteFromDevice(TrackItem track) =>
    !kIsWeb &&
    track.filePath != null &&
    track.filePath!.isNotEmpty;

List<PopupMenuEntry<TrackOverflowAction>> trackOverflowPopupMenuEntries({
  required bool enableDeleteFromDevice,
}) {
  return [
    const PopupMenuItem(
      value: TrackOverflowAction.playFromHere,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.playlist_play_rounded),
        title: Text('Play from here'),
        subtitle: Text('New queue: this track to end of list'),
      ),
    ),
    const PopupMenuItem(
      value: TrackOverflowAction.playOnlyThis,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.music_note_rounded),
        title: Text('Play this song only'),
      ),
    ),
    const PopupMenuItem(
      value: TrackOverflowAction.addToPlaylist,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.playlist_add_rounded),
        title: Text('Add to playlist'),
        subtitle: Text('Choose a saved playlist'),
      ),
    ),
    if (enableDeleteFromDevice) ...[
      const PopupMenuDivider(),
      PopupMenuItem(
        value: TrackOverflowAction.deleteFromDevice,
        child: Builder(
          builder: (ctx) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.delete_outline_rounded,
              color: Theme.of(ctx).colorScheme.error,
            ),
            title: Text(
              'Delete from device',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
            subtitle: const Text('Removes this MP3 file permanently'),
          ),
        ),
      ),
    ],
  ];
}

Future<void> _showUserPlaylistPickerAndAdd(
  BuildContext context,
  String filePath,
) async {
  final raw = filePath.trim();
  if (raw.isEmpty) {
    if (context.mounted) {
      ActionPillToast.show(
        context,
        'No file path',
        uppercaseLabel: true,
      );
    }
    return;
  }

  final playlists = await UserPlaylistsStore.loadAll();
  if (!context.mounted) return;

  if (playlists.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No playlists'),
        content: const Text(
          'Create a playlist in Library → Playlist first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return;
  }

  final pal = context.palette;
  final theme = Theme.of(context);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: pal.surface,
    showDragHandle: true,
    builder: (ctx) {
      final listHeight = min(
        MediaQuery.sizeOf(ctx).height * 0.5,
        120 + playlists.length * 56.0,
      );
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Text(
                'Add to playlist',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: pal.textPrimary,
                ),
              ),
            ),
            SizedBox(
              height: listHeight,
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: playlists.length,
                itemBuilder: (context, i) {
                  final pl = playlists[i];
                  return ListTile(
                    leading: Icon(
                      Icons.queue_music_rounded,
                      color: pal.primary,
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
                          await UserPlaylistsStore.addPathToPlaylist(pl.id, raw);
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      if (!context.mounted) return;
                      ActionPillToast.show(
                        context,
                        added
                            ? 'Added to ${pl.name}'
                            : 'Already in playlist',
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

Future<void> applyTrackOverflowAction(
  BuildContext context,
  PlayerController player,
  int playlistIndex,
  TrackOverflowAction action,
) async {
  final tracks = player.playlist;
  if (playlistIndex < 0 || playlistIndex >= tracks.length) return;

  switch (action) {
    case TrackOverflowAction.playFromHere:
      await player.setPlaylistAndPlay(tracks.sublist(playlistIndex));

    case TrackOverflowAction.playOnlyThis:
      await player.setPlaylistAndPlay([tracks[playlistIndex]]);

    case TrackOverflowAction.addToPlaylist:
      final t = tracks[playlistIndex];
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

    case TrackOverflowAction.deleteFromDevice:
      final track = tracks[playlistIndex];
      final path = track.filePath;
      if (path == null || path.isEmpty) return;

      final basename = p.basename(path);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final scheme = Theme.of(ctx).colorScheme;
          return AlertDialog(
            title: const Text('Delete from device?'),
            content: Text(
              'This permanently removes the file from storage.\n'
              '$basename\n\n'
              'This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                ),
                child: const Text('Delete'),
              ),
            ],
          );
        },
      );
      if (confirmed != true || !context.mounted) return;

      final wasPlaying = player.isPlaying;
      final targetsCurrent =
          playlistIndex == player.currentIndex &&
          player.currentTrack?.filePath == path;

      if (targetsCurrent) {
        await player.stopForExternalFileEdit();
      }

      final err = await deleteMusicFileOrError(path);

      if (err != null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not delete: $err')),
          );
        }
        if (targetsCurrent) {
          await player.reloadCurrentSource();
          if (wasPlaying && context.mounted) {
            await player.play();
          }
        }
        return;
      }

      await player.removePlaylistEntryAt(playlistIndex);

      if (context.mounted) {
        ActionPillToast.show(
          context,
          'Deleted',
          uppercaseLabel: true,
        );
      }
  }
}
