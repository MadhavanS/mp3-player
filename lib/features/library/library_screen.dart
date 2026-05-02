import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../audio/player_controller.dart';
import '../../models/track_item.dart';
import '../../theme/app_theme.dart';
import '../../widgets/track_album_art.dart';

const String kLibraryMainTitle = 'Poll, Top Tracks this Week';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({
    super.key,
    required this.folderPaths,
    required this.onOpenDrawer,
  });

  final List<String> folderPaths;
  final VoidCallback onOpenDrawer;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final player = PlayerController.of(context);

    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final tracks = player.playlist;

        return ColoredBox(
          color: AppColors.navy,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.menu_rounded),
                        color: AppColors.textOnNavy,
                        tooltip: 'Open menu',
                        onPressed: onOpenDrawer,
                      ),
                      Expanded(
                        child: Text(
                          kLibraryMainTitle,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: AppColors.textOnNavy,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
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
                        color: AppColors.textMuted.withOpacity(0.95),
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
                color: AppColors.textOnNavy.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'No tracks yet',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppColors.textOnNavy,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Open the menu and go to Settings to add folders. MP3 files are scanned recursively.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary.withOpacity(0.9),
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
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        color: Color(0x22FFFFFF),
        indent: 88,
      ),
      itemBuilder: (context, i) {
        final track = tracks[i];
        final selected = i == player.currentIndex;
        return _TrackTile(
          track: track,
          selected: selected,
          onTap: () => _selectTrack(context, i),
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
  });

  final TrackItem track;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: selected ? Colors.white.withOpacity(0.06) : Colors.transparent,
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
                      '${track.metaLine} · ${track.genres}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.textMuted.withOpacity(0.9),
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColors.textOnNavy,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary.withOpacity(0.95),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.more_horiz_rounded),
                color: AppColors.textOnNavy.withOpacity(0.8),
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}
