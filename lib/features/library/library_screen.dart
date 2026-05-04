import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../audio/player_controller.dart';
import '../../models/track_item.dart';
import '../../services/favorite_songs_store.dart';
import '../../services/music_library_path_key.dart';
import '../../services/recently_added_store.dart';
import '../../services/recently_played_store.dart';
import '../../services/user_playlists_store.dart';
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

  final GlobalKey _scrollCurrentTrackKey =
      GlobalKey(debugLabel: 'libraryScrollCurrentTrack');

  final ScrollController _songsScrollController = ScrollController();
  final ScrollController _recentAddedScrollController = ScrollController();
  final ScrollController _playlistScrollController = ScrollController();
  final ScrollController _favoritesScrollController = ScrollController();
  final ScrollController _recentPlayedScrollController = ScrollController();

  static const double _kLibraryListRowStride = 88;

  /// After returning from Files, focus the Songs tab.
  void switchToSongsTab() {
    if (!mounted) return;
    _tabController.index = 0;
    setState(() {});
  }

  /// Used when closing Now Playing to restore the library section that started playback.
  void switchToTab(int index) {
    if (!mounted) return;
    _tabController.index = index.clamp(0, 4);
    setState(() {});
  }

  /// Switches library tab and scrolls so the current track row is at the top of the list.
  Future<void> switchToTabAndScrollToCurrentTrack(int index) async {
    if (!mounted) return;
    _tabController.index = index.clamp(0, 4);
    setState(() {});
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await _scrollActiveTabToCurrentTrack();
  }

  static bool _isCurrentTrackPath(PlayerController player, String? path) {
    if (path == null || path.isEmpty) return false;
    final cur = player.currentTrack?.filePath;
    if (cur == null || cur.isEmpty) return false;
    return canonicalMusicLibraryPathKey(path) ==
        canonicalMusicLibraryPathKey(cur);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _searchController.addListener(() => setState(() {}));
    _tabController.addListener(_onTabChanged);
    unawaited(FavoriteSongsStore.ensureLoaded());
  }

  void _onTabChanged() {
    if (!mounted) return;
    if (_tabController.indexIsChanging) return;
    setState(() {
      if (_tabController.index == 4) {
        _recentListRevision++;
      }
    });
    if (_tabController.index == 3) {
      unawaited(FavoriteSongsStore.pruneMissingPaths());
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    _songsScrollController.dispose();
    _recentAddedScrollController.dispose();
    _playlistScrollController.dispose();
    _favoritesScrollController.dispose();
    _recentPlayedScrollController.dispose();
    super.dispose();
  }

  bool _userPlaylistContainsCurrentPath(UserPlaylistEntry pl, String pathKey) {
    for (final p in pl.paths) {
      if (canonicalMusicLibraryPathKey(p) == pathKey) return true;
    }
    return false;
  }

  int? _indexInSongsListForPathKey(
    PlayerController player,
    List<TrackItem> tracks,
    Set<String>? browsePathKeys,
    String query,
    String pathKey,
  ) {
    final baseFilteredIndices = tracks.isEmpty
        ? <int>[]
        : _filteredPlaylistIndices(tracks, query);
    final songsTabIndices = _playlistIndicesInPathKeySet(
      baseFilteredIndices,
      tracks,
      browsePathKeys,
    );
    for (var i = 0; i < songsTabIndices.length; i++) {
      final fp = tracks[songsTabIndices[i]].filePath;
      if (fp != null && canonicalMusicLibraryPathKey(fp) == pathKey) {
        return i;
      }
    }
    return null;
  }

  Future<void> _coaxLazyListThenEnsureVisible(
    ScrollController controller,
    int index,
  ) async {
    if (!mounted) return;
    for (var attempt = 0; attempt < 8; attempt++) {
      if (!controller.hasClients) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        continue;
      }
      final max = controller.position.maxScrollExtent;
      final target = (index * _kLibraryListRowStride).clamp(0.0, max);
      controller.jumpTo(target.toDouble());
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final ctx = _scrollCurrentTrackKey.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0,
          duration: Duration.zero,
          curve: Curves.linear,
        );
        return;
      }
    }
  }

  Future<void> _scrollActiveTabToCurrentTrack() async {
    if (!mounted) return;
    final player = PlayerController.of(context);
    final cur = player.currentTrack?.filePath;
    if (cur == null || cur.isEmpty) return;
    final pathKey = canonicalMusicLibraryPathKey(cur);
    if (pathKey.isEmpty) return;

    final tab = _tabController.index;
    final tracks = player.metadataLibrary;
    final query = _searchController.text.trim();
    final browsePathKeys = widget.songsBrowsePathKeys.value;

    switch (tab) {
      case 0:
        final idx = _indexInSongsListForPathKey(
          player,
          tracks,
          browsePathKeys,
          query,
          pathKey,
        );
        if (idx == null) return;
        await _coaxLazyListThenEnsureVisible(_songsScrollController, idx);
        return;
      case 1:
        final ordered =
            await RecentlyAddedStore.orderedPathsForLibrary(tracks);
        if (!mounted) return;
        var paths = _pathsMatchingBrowse(ordered, browsePathKeys);
        paths = _filterPathsBySearch(paths, query, tracks);
        final idx =
            paths.indexWhere((p) => canonicalMusicLibraryPathKey(p) == pathKey);
        if (idx < 0) return;
        await _coaxLazyListThenEnsureVisible(_recentAddedScrollController, idx);
        return;
      case 2:
        final all = await UserPlaylistsStore.loadAll();
        if (!mounted) return;
        final filtered = _filterPlaylistsBySearch(all, query);
        final idx = filtered.indexWhere(
          (pl) => _userPlaylistContainsCurrentPath(pl, pathKey),
        );
        if (idx < 0) return;
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        var ctx = _scrollCurrentTrackKey.currentContext;
        if (ctx == null) {
          if (_playlistScrollController.hasClients) {
            final max = _playlistScrollController.position.maxScrollExtent;
            _playlistScrollController
                .jumpTo((120.0 + idx * 80).clamp(0.0, max));
            await WidgetsBinding.instance.endOfFrame;
            if (!mounted) return;
            ctx = _scrollCurrentTrackKey.currentContext;
          }
        }
        if (ctx != null && ctx.mounted) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0,
            duration: Duration.zero,
            curve: Curves.linear,
          );
        }
        return;
      case 3:
        final favPaths = await FavoriteSongsStore.loadPaths();
        if (!mounted) return;
        var paths = _pathsMatchingBrowse(favPaths, browsePathKeys);
        paths = _filterPathsBySearch(paths, query, tracks);
        final idx =
            paths.indexWhere((p) => canonicalMusicLibraryPathKey(p) == pathKey);
        if (idx < 0) return;
        await _coaxLazyListThenEnsureVisible(_favoritesScrollController, idx);
        return;
      case 4:
        final played = await RecentlyPlayedStore.loadPaths();
        if (!mounted) return;
        var paths = _pathsMatchingBrowse(played, browsePathKeys);
        paths = _filterPathsBySearch(paths, query, tracks);
        final idx =
            paths.indexWhere((p) => canonicalMusicLibraryPathKey(p) == pathKey);
        if (idx < 0) return;
        await _coaxLazyListThenEnsureVisible(_recentPlayedScrollController, idx);
        return;
      default:
        return;
    }
  }

  static bool _trackMatchesQuery(TrackItem t, String q) {
    if (q.isEmpty) return true;
    return t.title.toLowerCase().contains(q);
  }

  String _searchHintForTab(int i) => switch (i) {
        0 || 1 || 2 => 'Search by title',
        3 => 'Search favourites',
        _ => 'Search recent',
      };

  List<String> _pathsMatchingBrowse(
    List<String> paths,
    Set<String>? browsePathKeys,
  ) {
    if (browsePathKeys == null) return paths;
    if (browsePathKeys.isEmpty) return <String>[];
    return paths.where((path) {
      final k = canonicalMusicLibraryPathKey(path);
      return k.isNotEmpty && browsePathKeys.contains(k);
    }).toList();
  }

  List<String> _filterPathsBySearch(
    List<String> paths,
    String rawQuery,
    List<TrackItem> library,
  ) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return paths;
    return paths.where((path) {
      final t = _trackForPath(path, library);
      if (_trackMatchesQuery(t, q)) return true;
      return p.basenameWithoutExtension(path).toLowerCase().contains(q) ||
          path.toLowerCase().contains(q);
    }).toList();
  }

  /// Resolves a library [TrackItem] for [path] using canonical path keys (stable on Android).
  static TrackItem _trackForPath(String path, List<TrackItem> library) {
    final key = canonicalMusicLibraryPathKey(path);
    if (key.isNotEmpty) {
      for (final t in library) {
        final fp = t.filePath;
        if (fp == null || fp.isEmpty) continue;
        if (canonicalMusicLibraryPathKey(fp) == key) return t;
      }
    }
    return TrackItem.fromFilePath(path);
  }

  int _playlistIndexForPath(PlayerController player, String path) {
    final key = canonicalMusicLibraryPathKey(path);
    if (key.isEmpty) return -1;
    return player.playlist.indexWhere((t) {
      final fp = t.filePath;
      if (fp == null || fp.isEmpty) return false;
      return canonicalMusicLibraryPathKey(fp) == key;
    });
  }

  Future<void> _playOrderedPathsFrom(
    BuildContext context,
    List<String> orderedPaths,
    int startIndex, {
    required int playbackOriginTab,
    Set<String>? pathKeyScope,
  }) async {
    if (orderedPaths.isEmpty) return;
    final player = PlayerController.of(context);
    final library = player.metadataLibrary;
    final tracks = orderedPaths
        .map((path) => _trackForPath(path, library))
        .toList();
    if (pathKeyScope != null) {
      player.setPlaybackPathKeyScope(pathKeyScope);
    } else {
      player.setPlaybackPathKeyScope(null);
    }
    await player.setPlaylistAndPlay(
      tracks,
      startIndex: startIndex.clamp(0, tracks.length - 1),
      playbackOriginTab: playbackOriginTab,
    );
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

  Future<void> _showCreatePlaylistDialog(BuildContext context) async {
    final pal = context.palette;
    final theme = Theme.of(context);
    final controller = TextEditingController();
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: pal.surface,
            title: Text(
              'Create playlist',
              style: theme.textTheme.titleLarge?.copyWith(
                color: pal.textPrimary,
              ),
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Playlist name',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: pal.textMuted,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: pal.dividerOnHero),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: ctx.controlAccent,
                    width: 1.5,
                  ),
                ),
              ),
              onSubmitted: (v) {
                final t = v.trim();
                if (t.isNotEmpty) Navigator.of(ctx).pop(t);
              },
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final t = controller.text.trim();
                  if (t.isNotEmpty) Navigator.of(ctx).pop(t);
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
      if (!context.mounted || name == null || name.trim().isEmpty) return;
      await UserPlaylistsStore.createPlaylist(name.trim());
    } finally {
      controller.dispose();
    }
  }

  List<UserPlaylistEntry> _filterPlaylistsBySearch(
    List<UserPlaylistEntry> all,
    String rawQuery,
  ) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((e) => e.name.toLowerCase().contains(q)).toList();
  }

  Future<void> _showUserPlaylistSheet(
    BuildContext context,
    UserPlaylistEntry playlist,
    List<TrackItem> library,
    PlayerController player,
  ) async {
    final pal = context.palette;
    final theme = Theme.of(context);
    final paths = List<String>.from(playlist.paths);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: pal.surface,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          playlist.name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: pal.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Delete playlist',
                        icon: Icon(Icons.delete_outline_rounded,
                            color: pal.textSecondary),
                        onPressed: () async {
                          await UserPlaylistsStore.deletePlaylist(playlist.id);
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        },
                      ),
                    ],
                  ),
                ),
                if (paths.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                    child: Text(
                      'This playlist is empty.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: pal.textSecondary,
                      ),
                    ),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _playOrderedPathsFrom(
                            context,
                            paths,
                            0,
                            playbackOriginTab: 2,
                          );
                        },
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Play all'),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: min(
                      MediaQuery.sizeOf(ctx).height * 0.55,
                      24 + paths.length * 76.0,
                    ),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                      itemCount: paths.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: pal.dividerOnHero,
                        indent: 88,
                      ),
                      itemBuilder: (context, i) {
                        final path = paths[i];
                        final track = _trackForPath(path, library);
                        final selected = _isCurrentTrackPath(player, path);
                        return Material(
                          color: selected
                              ? pal.onScaffold.withValues(alpha: 0.06)
                              : Colors.transparent,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            leading: TrackAlbumArt(
                              track: track,
                              display: TrackArtDisplay.list,
                            ),
                            title: Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: pal.textPrimary,
                                fontSize: 15,
                              ),
                            ),
                            subtitle: Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: pal.textSecondary,
                              ),
                            ),
                            onTap: () {
                              Navigator.of(ctx).pop();
                              _playOrderedPathsFrom(
                                context,
                                paths,
                                i,
                                playbackOriginTab: 2,
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaylistTab(
    ThemeData theme,
    BuildContext context,
    AppPalette pal,
    String query,
    List<TrackItem> tracks,
    PlayerController player,
  ) {
    return ValueListenableBuilder<int>(
      valueListenable: UserPlaylistsStore.revision,
      builder: (context, _, __) {
        return FutureBuilder<List<UserPlaylistEntry>>(
          future: UserPlaylistsStore.loadAll(),
          builder: (context, snap) {
            final allPlaylists = snap.data ?? [];
            final filteredPlaylists =
                _filterPlaylistsBySearch(allPlaylists, query);

            final curPath = player.currentTrack?.filePath;
            final curKey = (curPath != null && curPath.isNotEmpty)
                ? canonicalMusicLibraryPathKey(curPath)
                : '';

            return ListView(
              controller: _playlistScrollController,
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () async {
                      await _showCreatePlaylistDialog(context);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: context.controlAccent
                                  .withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.add_rounded,
                              color: context.controlAccent,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Create new playlist',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: pal.onScaffold,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Name a playlist, then add songs from any track menu.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color:
                                        pal.textSecondary.withValues(alpha: 0.9),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: pal.onScaffold.withValues(alpha: 0.45),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Your playlists',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: pal.onScaffold.withValues(alpha: 0.75),
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
                if (snap.connectionState != ConnectionState.done)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  )
                else if (filteredPlaylists.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: Text(
                      query.trim().isEmpty
                          ? 'No saved playlists yet.'
                          : 'No playlists match your search.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: pal.textMuted,
                      ),
                    ),
                  )
                else
                  ...List.generate(filteredPlaylists.length, (i) {
                    final pl = filteredPlaylists[i];
                    final attachScrollKey = _tabController.index == 2 &&
                        curKey.isNotEmpty &&
                        _userPlaylistContainsCurrentPath(pl, curKey);
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (i > 0)
                          Divider(
                            height: 1,
                            color: pal.dividerOnHero,
                            indent: 56,
                          ),
                        Material(
                          key: attachScrollKey ? _scrollCurrentTrackKey : null,
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              _showUserPlaylistSheet(
                                context,
                                pl,
                                tracks,
                                player,
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor:
                                        pal.onScaffold.withValues(alpha: 0.1),
                                    child: Icon(
                                      Icons.queue_music_rounded,
                                      color: pal.onScaffold.withValues(alpha: 0.75),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          pl.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                            color: pal.onScaffold,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${pl.paths.length} songs',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: pal.textMuted
                                                .withValues(alpha: 0.92),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: pal.onScaffold.withValues(alpha: 0.45),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _onTrackOverflow(
    BuildContext context,
    PlayerController player,
    int playlistIndex,
    TrackOverflowAction action, {
    int? playbackOriginTab,
    TrackOverflowQueueContext? outsideQueue,
  }) async {
    await applyTrackOverflowAction(
      context,
      player,
      playlistIndex,
      action,
      playbackOriginTab: playbackOriginTab,
      outsideQueue: outsideQueue,
    );
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
            final tracks = player.metadataLibrary;
            final query = _searchController.text.trim();
            final baseFilteredIndices = tracks.isEmpty
                ? <int>[]
                : _filteredPlaylistIndices(tracks, query);
            final songsTabIndices = _playlistIndicesInPathKeySet(
              baseFilteredIndices,
              tracks,
              browsePathKeys,
            );

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
                          Tab(text: 'Recently added'),
                          Tab(text: 'Playlist'),
                          Tab(text: 'Favourites'),
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
                          _buildRecentlyAddedTab(
                            theme,
                            pal,
                            query,
                            player,
                            tracks,
                            browsePathKeys,
                          ),
                          _buildPlaylistTab(
                            theme,
                            context,
                            pal,
                            query,
                            tracks,
                            player,
                          ),
                          _buildFavoritesTab(
                            theme,
                            pal,
                            query,
                            player,
                            tracks,
                            browsePathKeys,
                          ),
                          _buildRecentTab(theme, pal, query, player, tracks, browsePathKeys),
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

  Widget _buildFavoritesTab(
    ThemeData theme,
    AppPalette pal,
    String rawQuery,
    PlayerController player,
    List<TrackItem> tracks,
    Set<String>? browsePathKeys,
  ) {
    return ValueListenableBuilder<int>(
      valueListenable: FavoriteSongsStore.revision,
      builder: (context, _, __) {
        return FutureBuilder<List<String>>(
          future: FavoriteSongsStore.loadPaths(),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return Center(
                child: CircularProgressIndicator(
                  color: context.controlAccent,
                ),
              );
            }

            var paths =
                _pathsMatchingBrowse(snap.data ?? [], browsePathKeys);
            paths = _filterPathsBySearch(paths, rawQuery, tracks);

            if ((snap.data ?? []).isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.favorite_border_rounded,
                        size: 54,
                        color: pal.onScaffold.withValues(alpha: 0.45),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'No favourites yet',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: pal.onScaffold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap the heart in the Now Playing footer to add songs here.',
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
                    'No favourites match your search.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: pal.textMuted,
                    ),
                  ),
                ),
              );
            }

            return ListenableBuilder(
              listenable: player,
              builder: (context, _) {
                final library = player.metadataLibrary;
                return ListView.separated(
                  controller: _favoritesScrollController,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: paths.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: pal.dividerOnHero,
                    indent: 88,
                  ),
                  itemBuilder: (context, i) {
                    final path = paths[i];
                    final track = _trackForPath(path, library);
                    final plIndex = _playlistIndexForPath(player, path);
                    final selected = _isCurrentTrackPath(player, path);
                    final attachScrollKey =
                        selected && _tabController.index == 3;
                    return Material(
                      key: attachScrollKey ? _scrollCurrentTrackKey : null,
                      color: selected
                          ? pal.onScaffold.withValues(alpha: 0.08)
                          : Colors.transparent,
                      child: InkWell(
                        onTap: () => _playOrderedPathsFrom(
                          context,
                          paths,
                          i,
                          playbackOriginTab: 3,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              TrackAlbumArt(
                                track: track,
                                display: TrackArtDisplay.list,
                              ),
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
                              TrackOverflowMenuWithFavourite(
                                pal: pal,
                                track: track,
                                onSelected: (action) {
                                  final ctxTracks = paths
                                      .map((p) =>
                                          _trackForPath(p, library))
                                      .toList();
                                  unawaited(
                                    _onTrackOverflow(
                                      context,
                                      player,
                                      plIndex >= 0 ? plIndex : -1,
                                      action,
                                      playbackOriginTab: 3,
                                      outsideQueue: plIndex < 0
                                          ? TrackOverflowQueueContext(
                                              tracks: ctxTracks,
                                              index: i,
                                              playbackOriginTab: 3,
                                            )
                                          : null,
                                    ),
                                  );
                                },
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
          },
        );
      },
    );
  }

  Widget _buildRecentlyAddedTab(
    ThemeData theme,
    AppPalette pal,
    String rawQuery,
    PlayerController player,
    List<TrackItem> tracks,
    Set<String>? browsePathKeys,
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
                'Open the menu and go to Settings to add folders.',
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

    return ValueListenableBuilder<int>(
      valueListenable: RecentlyAddedStore.revision,
      builder: (context, _, __) {
        return FutureBuilder<List<String>>(
          future: RecentlyAddedStore.orderedPathsForLibrary(tracks),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return Center(
                child: CircularProgressIndicator(color: context.controlAccent),
              );
            }

            final baseOrdered = snap.data ?? [];
            var paths = _pathsMatchingBrowse(baseOrdered, browsePathKeys);
            paths = _filterPathsBySearch(paths, rawQuery, tracks);

            if (baseOrdered.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 54,
                        color: pal.onScaffold.withValues(alpha: 0.45),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Nothing to show yet',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: pal.onScaffold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap refresh in the library header after adding music so new tracks are recorded.',
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
              final hasBrowse = browsePathKeys != null;
              final q = rawQuery.trim();
              final message = hasBrowse && q.isEmpty
                  ? 'No recently added songs in this folder.'
                  : 'No recently added songs match your search.';
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: pal.textMuted,
                    ),
                  ),
                ),
              );
            }

            return ListenableBuilder(
              listenable: player,
              builder: (context, _) {
                final library = player.metadataLibrary;
                return ListView.separated(
                  controller: _recentAddedScrollController,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: paths.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: pal.dividerOnHero,
                    indent: 88,
                  ),
                  itemBuilder: (context, i) {
                    final path = paths[i];
                    final track = _trackForPath(path, library);
                    final plIndex = _playlistIndexForPath(player, path);
                    final selected = _isCurrentTrackPath(player, path);
                    final attachScrollKey =
                        selected && _tabController.index == 1;
                    return Material(
                      key: attachScrollKey ? _scrollCurrentTrackKey : null,
                      color: selected
                          ? pal.onScaffold.withValues(alpha: 0.08)
                          : Colors.transparent,
                      child: InkWell(
                        onTap: () => _playOrderedPathsFrom(
                          context,
                          paths,
                          i,
                          playbackOriginTab: 1,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              TrackAlbumArt(
                                track: track,
                                display: TrackArtDisplay.list,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      track.genres.isEmpty
                                          ? track.metaLine
                                          : '${track.metaLine} · ${track.genres}',
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color:
                                            pal.textMuted.withValues(alpha: 0.9),
                                        fontSize: 10,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.titleMedium?.copyWith(
                                        color: pal.onScaffold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      track.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: pal.textSecondary
                                            .withValues(alpha: 0.95),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              TrackOverflowMenuWithFavourite(
                                pal: pal,
                                track: track,
                                onSelected: (action) {
                                  final ctxTracks = paths
                                      .map((p) =>
                                          _trackForPath(p, library))
                                      .toList();
                                  unawaited(
                                    _onTrackOverflow(
                                      context,
                                      player,
                                      plIndex >= 0 ? plIndex : -1,
                                      action,
                                      playbackOriginTab: 1,
                                      outsideQueue: plIndex < 0
                                          ? TrackOverflowQueueContext(
                                              tracks: ctxTracks,
                                              index: i,
                                              playbackOriginTab: 1,
                                            )
                                          : null,
                                    ),
                                  );
                                },
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
          },
        );
      },
    );
  }

  Widget _buildRecentTab(
    ThemeData theme,
    AppPalette pal,
    String rawQuery,
    PlayerController player,
    List<TrackItem> tracks,
    Set<String>? browsePathKeys,
  ) {
    return FutureBuilder<List<String>>(
      key: ValueKey(_recentListRevision),
      future: RecentlyPlayedStore.loadPaths(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Center(
            child: CircularProgressIndicator(
              color: context.controlAccent,
            ),
          );
        }

        var paths = _pathsMatchingBrowse(snap.data ?? [], browsePathKeys);
        paths = _filterPathsBySearch(paths, rawQuery, tracks);

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
          final hasBrowse = browsePathKeys != null;
          final q = rawQuery.trim();
          final message = hasBrowse && q.isEmpty
              ? 'No recent songs in this folder.'
              : 'No recent songs match your search.';
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                message,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: pal.textMuted,
                ),
              ),
            ),
          );
        }

        return ListenableBuilder(
          listenable: player,
          builder: (context, _) {
            final library = player.metadataLibrary;
            return ListView.separated(
              controller: _recentPlayedScrollController,
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: paths.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: pal.dividerOnHero,
                indent: 88,
              ),
              itemBuilder: (context, i) {
                final path = paths[i];
                final track = _trackForPath(path, library);
                final plIndex = _playlistIndexForPath(player, path);
                final selected = _isCurrentTrackPath(player, path);
                final attachScrollKey =
                    selected && _tabController.index == 4;
                return Material(
                  key: attachScrollKey ? _scrollCurrentTrackKey : null,
                  color: selected
                      ? pal.onScaffold.withValues(alpha: 0.08)
                      : Colors.transparent,
                  child: InkWell(
                    onTap: () => _playOrderedPathsFrom(
                      context,
                      paths,
                      i,
                      playbackOriginTab: 4,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          TrackAlbumArt(
                            track: track,
                            display: TrackArtDisplay.list,
                          ),
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
                                    color:
                                        pal.textSecondary.withValues(alpha: 0.95),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TrackOverflowMenuWithFavourite(
                            pal: pal,
                            track: track,
                            onSelected: (action) {
                              final ctxTracks = paths
                                  .map((p) =>
                                      _trackForPath(p, library))
                                  .toList();
                              unawaited(
                                _onTrackOverflow(
                                  context,
                                  player,
                                  plIndex >= 0 ? plIndex : -1,
                                  action,
                                  playbackOriginTab: 4,
                                  outsideQueue: plIndex < 0
                                      ? TrackOverflowQueueContext(
                                          tracks: ctxTracks,
                                          index: i,
                                          playbackOriginTab: 4,
                                        )
                                      : null,
                                ),
                              );
                            },
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
      controller: _songsScrollController,
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: filteredIndices.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: pal.dividerOnHero,
        indent: 88,
      ),
      itemBuilder: (context, i) {
        final catalogIndex = filteredIndices[i];
        final track = tracks[catalogIndex];
        final path = track.filePath;
        final selected = _isCurrentTrackPath(player, path);
        final plIndex = path != null && path.isNotEmpty
            ? _playlistIndexForPath(player, path)
            : -1;
        final ctxTracks =
            filteredIndices.map((idx) => tracks[idx]).toList();
        return _TrackTile(
          track: track,
          selected: selected,
          rowKey: selected && _tabController.index == 0
              ? _scrollCurrentTrackKey
              : null,
          onTap: () {
            final orderedPaths = filteredIndices
                .map((idx) => tracks[idx].filePath)
                .whereType<String>()
                .toList();
            unawaited(
              _playOrderedPathsFrom(
                context,
                orderedPaths,
                i,
                playbackOriginTab: 0,
                pathKeyScope: browsePathKeys,
              ),
            );
          },
          onOverflowAction: (action) {
            unawaited(
              _onTrackOverflow(
                context,
                player,
                plIndex >= 0 ? plIndex : -1,
                action,
                playbackOriginTab: 0,
                outsideQueue: plIndex < 0
                    ? TrackOverflowQueueContext(
                        tracks: ctxTracks,
                        index: i,
                        playbackOriginTab: 0,
                      )
                    : null,
              ),
            );
          },
        );
      },
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.selected,
    this.rowKey,
    required this.onTap,
    required this.onOverflowAction,
  });

  final TrackItem track;
  final bool selected;
  final Key? rowKey;
  final VoidCallback onTap;
  final void Function(TrackOverflowAction action) onOverflowAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;

    return Material(
      key: rowKey,
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
              TrackOverflowMenuWithFavourite(
                pal: pal,
                track: track,
                onSelected: onOverflowAction,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
