import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../audio/player_controller.dart';
import '../../models/track_item.dart';
import '../../services/music_library_path_key.dart';
import '../../services/recently_played_store.dart';
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
    required this.songsBrowsePathKeys,
    required this.onClearSongsBrowseFilter,
    this.onRefreshLibrary,
  });

  final List<String> folderPaths;
  final VoidCallback onOpenDrawer;
  final VoidCallback onClearSongsBrowseFilter;
  /// When non-null (including empty), Songs tab limits to tracks whose paths match keys from Files.
  final ValueListenable<Set<String>?> songsBrowsePathKeys;
  final VoidCallback? onRefreshLibrary;

  @override
  State<LibraryScreen> createState() => LibraryScreenState();
}

class LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  late final TabController _tabController;
  int _recentListRevision = 0;

  /// After returning from Files, focus the Songs tab.
  void switchToSongsTab() {
    if (!mounted) return;
    _tabController.index = 0;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController.addListener(() => setState(() {}));
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (!mounted) return;
    setState(() {
      if (!_tabController.indexIsChanging && _tabController.index == 2) {
        _recentListRevision++;
      }
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  static bool _trackMatchesQuery(TrackItem t, String q) {
    if (q.isEmpty) return true;
    return t.title.toLowerCase().contains(q);
  }

  static List<int> _playlistQueueIndices(
    List<TrackItem> tracks,
    int currentIndex,
    String rawQuery,
  ) {
    if (tracks.isEmpty) return [];
    final start = currentIndex.clamp(0, tracks.length - 1);
    final q = rawQuery.trim().toLowerCase();
    final out = <int>[];
    for (var i = start; i < tracks.length; i++) {
      if (q.isEmpty || _trackMatchesQuery(tracks[i], q)) out.add(i);
    }
    return out;
  }

  String _searchHintForTab(int i) => switch (i) {
        0 || 1 => 'Search by title',
        _ => 'Search recent',
      };

  Future<void> _playRecentPath(BuildContext context, String path) async {
    final player = PlayerController.of(context);
    final idx = player.playlist.indexWhere((t) => t.filePath == path);
    if (idx >= 0) {
      await player.jumpToIndex(idx);
    } else {
      await player.setPlaylistAndPlay([TrackItem.fromFilePath(path)]);
    }
  }

  static List<int> _playlistIndicesInPathKeySet(
    List<int> playlistIndices,
    List<TrackItem> tracks,
    Set<String>? allowedPathKeys,
  ) {
    if (allowedPathKeys == null) return playlistIndices;
    if (allowedPathKeys.isEmpty) return <int>[];
    return playlistIndices.where((i) {
      if (i < 0 || i >= tracks.length) return false;
      final fp = tracks[i].filePath;
      if (fp == null || fp.trim().isEmpty) return false;
      final key = canonicalMusicLibraryPathKey(fp);
      return key.isNotEmpty && allowedPathKeys.contains(key);
    }).toList();
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

  InputDecoration _searchDecoration(
    AppPalette pal,
    ThemeData theme, {
    required String hintText,
  }) {
    final hasQuery = _searchController.text.trim().isNotEmpty;
    return InputDecoration(
      hintText: hintText,
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
        return ValueListenableBuilder<Set<String>?>(
          valueListenable: widget.songsBrowsePathKeys,
          builder: (context, browsePathKeys, _) {
            final tracks = player.playlist;
            final query = _searchController.text.trim();
            final baseFilteredIndices = tracks.isEmpty
                ? <int>[]
                : _filteredPlaylistIndices(tracks, query);
            final songsTabIndices = _playlistIndicesInPathKeySet(
              baseFilteredIndices,
              tracks,
              browsePathKeys,
            );
            final playlistIndices = tracks.isEmpty
                ? <int>[]
                : _playlistQueueIndices(
                    tracks, player.currentIndex, query);

            final pal = context.palette;
            final hint = _searchHintForTab(_tabController.index);

            return ColoredBox(
              color: pal.scaffoldBackground,
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
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
                              decoration:
                                  _searchDecoration(pal, theme, hintText: hint),
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
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        padding: const EdgeInsets.only(left: 2, right: 8),
                        labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                        tabAlignment: TabAlignment.start,
                        indicatorColor: pal.onScaffold,
                        indicatorWeight: 2.8,
                        indicatorSize: TabBarIndicatorSize.label,
                        labelColor: pal.onScaffold,
                        unselectedLabelColor:
                            pal.textMuted.withValues(alpha: 0.76),
                        dividerColor:
                            pal.onScaffold.withValues(alpha: 0.14),
                        dividerHeight: 1,
                        labelStyle: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          fontSize: 15,
                        ),
                        unselectedLabelStyle:
                            theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.2,
                          fontSize: 15,
                        ),
                        splashFactory: NoSplash.splashFactory,
                        overlayColor:
                            WidgetStateProperty.all<Color>(Colors.transparent),
                        tabs: const [
                          Tab(text: 'Songs'),
                          Tab(text: 'Playlist'),
                          Tab(text: 'Recently played'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildTracksTab(
                            theme,
                            context,
                            tracks,
                            songsTabIndices,
                            player,
                            browsePathKeys: browsePathKeys,
                            onClearBrowseFolder: browsePathKeys == null
                                ? null
                                : widget.onClearSongsBrowseFilter,
                          ),
                          _buildTracksTab(
                            theme,
                            context,
                            tracks,
                            playlistIndices,
                            player,
                          ),
                          _buildRecentTab(theme, pal, query),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRecentTab(ThemeData theme, AppPalette pal, String rawQuery) {
    return FutureBuilder<List<String>>(
      key: ValueKey(_recentListRevision),
      future: RecentlyPlayedStore.loadPaths(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Center(
            child: CircularProgressIndicator(
              color: pal.primary,
            ),
          );
        }

        List<String> paths = snap.data ?? [];
        final q = rawQuery.trim().toLowerCase();
        if (q.isNotEmpty) {
          paths = paths
              .where(
                (path) =>
                    p.basenameWithoutExtension(path).toLowerCase().contains(q) ||
                    path.toLowerCase().contains(q),
              )
              .toList();
        }

        if ((snap.data ?? []).isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 54,
                    color: pal.onScaffold.withValues(alpha: 0.45),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Nothing here yet',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: pal.onScaffold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Songs you play will appear in this list.',
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

        if (paths.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                'No recent songs match your search.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: pal.textMuted,
                ),
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 8),
          itemCount: paths.length,
          separatorBuilder: (_, __) =>
              Divider(height: 1, color: pal.dividerOnHero, indent: 56),
          itemBuilder: (context, i) {
            final path = paths[i];
            final title =
                path.isEmpty ? path : p.basenameWithoutExtension(path);
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () =>
                    _playRecentPath(context, path),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: pal.onScaffold.withValues(alpha: 0.1),
                        child: Icon(
                          Icons.music_note_rounded,
                          color: pal.onScaffold.withValues(alpha: 0.75),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: pal.onScaffold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              path,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color:
                                    pal.textMuted.withValues(alpha: 0.92),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTracksTab(
    ThemeData theme,
    BuildContext context,
    List<TrackItem> tracks,
    List<int> filteredIndices,
    PlayerController player, {
    Set<String>? browsePathKeys,
    VoidCallback? onClearBrowseFolder,
  }) {
    final pal = context.palette;

    final hasBrowseFilter = browsePathKeys != null;

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
      final q = _searchController.text.trim();
      final title =
          hasBrowseFilter && q.isEmpty ? 'No songs in this folder' : 'No matches';
      final detail = hasBrowseFilter && q.isEmpty
          ? 'Browse Files from the menu to pick a track in this folder and subfolders, or show your full library.'
          : 'Nothing in your library has a title matching your search.';

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
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: pal.onScaffold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: pal.textSecondary.withValues(alpha: 0.9),
                ),
              ),
              if (q.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '“$q”',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: pal.textMuted.withValues(alpha: 0.95),
                  ),
                ),
              ],
              if (hasBrowseFilter && onClearBrowseFolder != null) ...[
                const SizedBox(height: 16),
                TextButton(
                  onPressed: onClearBrowseFolder,
                  child: const Text('Show all songs'),
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
