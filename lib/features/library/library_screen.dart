import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../audio/player_controller.dart';
import '../../models/track_item.dart';
import '../../theme/app_theme.dart';
import '../../widgets/track_album_art.dart';
import '../player/track_overflow_actions.dart';

/// Key for the library search field (widget tests).
const Key librarySearchFieldKey = Key('library_search_field');

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.folderPaths,
    required this.onOpenDrawer,
    this.onRefreshLibrary,
  });

  final List<String> folderPaths;
  final VoidCallback onOpenDrawer;
  final VoidCallback? onRefreshLibrary;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _folderHint {
    if (widget.folderPaths.isEmpty) return '';
    if (widget.folderPaths.length == 1) {
      return p.basename(widget.folderPaths.single);
    }
    return '${widget.folderPaths.length} folders';
  }

  static bool _trackMatchesQuery(TrackItem t, String q) {
    if (q.isEmpty) return true;
    return t.title.toLowerCase().contains(q);
  }

  static List<int> _filteredPlaylistIndices(
    List<TrackItem> tracks,
    String rawQuery,
  ) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) {
      return List<int>.generate(tracks.length, (i) => i);
    }
    final out = <int>[];
    for (var i = 0; i < tracks.length; i++) {
      if (_trackMatchesQuery(tracks[i], q)) out.add(i);
    }
    return out;
  }

  Future<void> _selectTrack(BuildContext context, int playlistIndex) async {
    final player = PlayerController.of(context);
    if (playlistIndex < 0 || playlistIndex >= player.playlist.length) return;
    await player.jumpToIndex(playlistIndex);
  }

  Future<void> _onTrackOverflow(
    BuildContext context,
    PlayerController player,
    int playlistIndex,
    TrackOverflowAction action,
  ) async {
    await applyTrackOverflowAction(context, player, playlistIndex, action);
  }

  InputDecoration _searchDecoration(AppPalette pal, ThemeData theme) {
    final hasQuery = _searchController.text.trim().isNotEmpty;
    return InputDecoration(
      hintText: 'Search by title',
      hintStyle: theme.textTheme.bodyMedium?.copyWith(
        color: pal.textMuted.withValues(alpha: 0.72),
      ),
      isDense: true,
      filled: true,
      fillColor: pal.onScaffold.withValues(alpha: 0.1),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      prefixIcon: Icon(
        Icons.search_rounded,
        color: pal.textMuted.withValues(alpha: 0.9),
        size: 22,
      ),
      suffixIcon: hasQuery
          ? IconButton(
              tooltip: 'Clear search',
              icon: Icon(
                Icons.close_rounded,
                color: pal.onScaffold.withValues(alpha: 0.75),
                size: 20,
              ),
              onPressed: () {
                _searchController.clear();
                FocusScope.of(context).unfocus();
              },
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final player = PlayerController.of(context);

    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final tracks = player.playlist;
        final query = _searchController.text.trim();
        final filteredIndices =
            tracks.isEmpty ? <int>[] : _filteredPlaylistIndices(tracks, query);

        final pal = context.palette;
        return ColoredBox(
          color: pal.scaffoldBackground,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.menu_rounded),
                        color: pal.onScaffold,
                        tooltip: 'Open menu',
                        onPressed: widget.onOpenDrawer,
                      ),
                      Expanded(
                        child: TextField(
                          key: librarySearchFieldKey,
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          keyboardType: TextInputType.text,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: pal.onScaffold,
                            fontSize: 15,
                          ),
                          decoration: _searchDecoration(pal, theme),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded),
                        color: pal.onScaffold,
                        tooltip: 'Refresh library',
                        onPressed: widget.onRefreshLibrary,
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
                  child: _buildListBody(
                    theme,
                    context,
                    tracks,
                    filteredIndices,
                    player,
                  ),
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
    List<int> filteredIndices,
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

    if (filteredIndices.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 56,
                color: pal.onScaffold.withValues(alpha: 0.45),
              ),
              const SizedBox(height: 16),
              Text(
                'No matches',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: pal.onScaffold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Nothing in your library has a title matching your search.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: pal.textSecondary.withValues(alpha: 0.9),
                ),
              ),
              if (_searchController.text.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '“${_searchController.text.trim()}”',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: pal.textMuted.withValues(alpha: 0.95),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: filteredIndices.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: pal.dividerOnHero,
        indent: 88,
      ),
      itemBuilder: (context, i) {
        final playlistIndex = filteredIndices[i];
        final track = tracks[playlistIndex];
        final selected = playlistIndex == player.currentIndex;
        return _TrackTile(
          track: track,
          selected: selected,
          onTap: () => _selectTrack(context, playlistIndex),
          onOverflowAction: (action) =>
              _onTrackOverflow(context, player, playlistIndex, action),
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
    required this.onOverflowAction,
  });

  final TrackItem track;
  final bool selected;
  final VoidCallback onTap;
  final void Function(TrackOverflowAction action) onOverflowAction;

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
              PopupMenuButton<TrackOverflowAction>(
                tooltip: 'Track options',
                icon: Icon(
                  Icons.more_horiz_rounded,
                  color: pal.onScaffold.withValues(alpha: 0.8),
                ),
                padding: EdgeInsets.zero,
                onSelected: onOverflowAction,
                itemBuilder: (context) => trackOverflowPopupMenuEntries(
                  enableDeleteFromDevice: trackCanDeleteFromDevice(track),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
