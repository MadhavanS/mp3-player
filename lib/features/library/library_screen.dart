import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../audio/player_controller.dart';
import '../../models/track_item.dart';
import '../../theme/app_theme.dart';
import '../../widgets/track_album_art.dart';

const String kLibraryMainTitle = 'Poll, Top Tracks this Week';

enum _TrackMenuAction { playFromHere, playOnlyThis, addToPlaylist }

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({
    super.key,
    required this.folderPaths,
    required this.onOpenDrawer,
    this.onRefreshLibrary,
  });

  final List<String> folderPaths;
  final VoidCallback onOpenDrawer;
  final VoidCallback? onRefreshLibrary;

  String get _folderHint {
    if (folderPaths.isEmpty) return '';
    if (folderPaths.length == 1) return p.basename(folderPaths.single);
    return '${folderPaths.length} folders';
  }

  Future<void> _selectTrack(BuildContext context, int i) async {
    final player = PlayerController.of(context);
    if (i < 0 || i >= player.playlist.length) return;
    await player.jumpToIndex(i);
  }

  Future<void> _onTrackMenu(
    BuildContext context,
    PlayerController player,
    int index,
    _TrackMenuAction action,
  ) async {
    final tracks = List<TrackItem>.from(player.playlist);
    if (index < 0 || index >= tracks.length) return;

    switch (action) {
      case _TrackMenuAction.playFromHere:
        await player.setPlaylistAndPlay(tracks.sublist(index));
      case _TrackMenuAction.playOnlyThis:
        await player.setPlaylistAndPlay([tracks[index]]);
      case _TrackMenuAction.addToPlaylist:
        final t = tracks[index];
        final added = await player.addToPlaylistIfAbsent(t);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                added
                    ? 'Added to playlist: ${t.title}'
                    : 'Already in playlist: ${t.title}',
              ),
            ),
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final player = PlayerController.of(context);

    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final tracks = player.playlist;

        final pal = context.palette;
        return ColoredBox(
          color: pal.scaffoldBackground,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.menu_rounded),
                        color: pal.onScaffold,
                        tooltip: 'Open menu',
                        onPressed: onOpenDrawer,
                      ),
                      Expanded(
                        child: Text(
                          kLibraryMainTitle,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: pal.onScaffold,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded),
                        color: pal.onScaffold,
                        tooltip: 'Refresh library',
                        onPressed: onRefreshLibrary,
                      ),
                    ],
                  ),
                ),
                if (_folderHint.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: Text(
                      _folderHint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: pal.textMuted.withValues(alpha: 0.95),
                      ),
                    ),
                  ),
                Expanded(
                  child: _buildListBody(theme, context, tracks, player),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildListBody(
    ThemeData theme,
    BuildContext context,
    List<TrackItem> tracks,
    PlayerController player,
  ) {
    final pal = context.palette;
    if (tracks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.library_music_outlined,
                size: 56,
                color: pal.onScaffold.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'No tracks yet',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: pal.onScaffold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Open the menu and go to Settings to add folders. MP3 files are scanned recursively.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: pal.textSecondary.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: tracks.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: pal.dividerOnHero,
        indent: 88,
      ),
      itemBuilder: (context, i) {
        final track = tracks[i];
        final selected = i == player.currentIndex;
        return _TrackTile(
          track: track,
          selected: selected,
          onTap: () => _selectTrack(context, i),
          onMenuAction: (action) => _onTrackMenu(context, player, i, action),
        );
      },
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.selected,
    required this.onTap,
    required this.onMenuAction,
  });

  final TrackItem track;
  final bool selected;
  final VoidCallback onTap;
  final void Function(_TrackMenuAction action) onMenuAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;

    return Material(
      color: selected ? pal.onScaffold.withValues(alpha: 0.08) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TrackAlbumArt(track: track, display: TrackArtDisplay.list),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.genres.isEmpty
                          ? track.metaLine
                          : '${track.metaLine} · ${track.genres}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: pal.textMuted.withValues(alpha: 0.9),
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: pal.onScaffold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: pal.textSecondary.withValues(alpha: 0.95),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_TrackMenuAction>(
                tooltip: 'Track options',
                icon: Icon(
                  Icons.more_horiz_rounded,
                  color: pal.onScaffold.withValues(alpha: 0.8),
                ),
                padding: EdgeInsets.zero,
                onSelected: onMenuAction,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _TrackMenuAction.playFromHere,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.playlist_play_rounded),
                      title: Text('Play from here'),
                      subtitle: Text('New queue: this track to end of list'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _TrackMenuAction.playOnlyThis,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.music_note_rounded),
                      title: Text('Play this song only'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _TrackMenuAction.addToPlaylist,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.playlist_add_rounded),
                      title: Text('Add to playlist'),
                      subtitle: Text(
                        'Appends to the queue if this song is not already in it',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
