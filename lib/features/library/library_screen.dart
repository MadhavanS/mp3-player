import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../audio/player_controller.dart';
import '../../models/library_tab_id.dart';
import '../../models/track_item.dart';
import '../../services/favorite_songs_store.dart';
import '../../services/library_tabs_store.dart';
import '../../services/library_track_sort.dart';
import '../../services/music_library_path_key.dart';
import '../../services/recent_list_limits_store.dart';
import '../../services/recently_added_store.dart';
import '../../services/recently_played_store.dart';
import '../../services/user_playlists_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/daisy_background.dart';
import '../../widgets/track_album_art.dart';
import '../../widgets/create_playlist_name_dialog.dart';
import '../player/track_overflow_actions.dart';
import 'playing_queue_tab.dart';

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
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;
  List<LibraryTabId> _visibleTabs = List<LibraryTabId>.from(
    LibraryTabId.values,
  );
  List<UserPlaylistEntry> _userPlaylists = const <UserPlaylistEntry>[];
  bool _userPlaylistsLoading = true;
  int _recentListRevision = 0;

  /// Stable [Future]s so parent rebuilds (e.g. [PlayerController]) do not reset
  /// [FutureBuilder] to `waiting` and flash the loading indicator.
  Future<List<String>>? _cachedFavouritePathsFuture;
  int _cachedFavouritePathsRev = -1;

  Future<List<String>>? _cachedRecentlyAddedPathsFuture;
  int _cachedRecentlyAddedStoreRev = -1;
  int _cachedRecentlyAddedTracksIdentity = -1;

  Future<List<String>>? _cachedRecentlyPlayedPathsFuture;
  int _cachedRecentlyPlayedStoreRev = -1;
  int _cachedRecentlyPlayedTabRev = -1;

  final GlobalKey _scrollAnchorSongs = GlobalKey(debugLabel: 'libScrollSongs');
  final GlobalKey _scrollAnchorRecentAdded = GlobalKey(
    debugLabel: 'libScrollRecentAdded',
  );
  final GlobalKey _scrollAnchorPlaylist = GlobalKey(
    debugLabel: 'libScrollPlaylist',
  );
  final GlobalKey _scrollAnchorFavorites = GlobalKey(
    debugLabel: 'libScrollFavorites',
  );
  final GlobalKey _scrollAnchorRecentPlayed = GlobalKey(
    debugLabel: 'libScrollRecentPlayed',
  );
  final GlobalKey _scrollAnchorNowPlayingList = GlobalKey(
    debugLabel: 'libScrollNowPlayingList',
  );

  final ScrollController _songsScrollController = ScrollController();
  final ScrollController _recentAddedScrollController = ScrollController();
  final ScrollController _playlistScrollController = ScrollController();
  final ScrollController _favoritesScrollController = ScrollController();
  final ScrollController _recentPlayedScrollController = ScrollController();
  final ScrollController _nowPlayingListScrollController = ScrollController();

  static const double _kLibraryListRowStride = 88;
  static const double _kQueueListRowStride = 64;

  /// Search text shorter than this (after trim) does not filter library lists.
  static const int _kLibrarySearchMinChars = 3;

  /// Returns trimmed [raw], or empty when fewer than [_kLibrarySearchMinChars] characters.
  static String _effectiveLibrarySearchQuery(String raw) {
    final t = raw.trim();
    if (t.length < _kLibrarySearchMinChars) return '';
    return t;
  }

  Future<List<String>> _favouritePathsFuture() {
    final r = FavoriteSongsStore.revision.value;
    if (_cachedFavouritePathsFuture == null || _cachedFavouritePathsRev != r) {
      _cachedFavouritePathsRev = r;
      _cachedFavouritePathsFuture = FavoriteSongsStore.loadPaths();
    }
    return _cachedFavouritePathsFuture!;
  }

  Future<List<String>> _recentlyAddedPathsFuture(List<TrackItem> tracks) {
    final r = RecentlyAddedStore.revision.value;
    final id = identityHashCode(tracks);
    if (_cachedRecentlyAddedPathsFuture == null ||
        _cachedRecentlyAddedStoreRev != r ||
        _cachedRecentlyAddedTracksIdentity != id) {
      _cachedRecentlyAddedStoreRev = r;
      _cachedRecentlyAddedTracksIdentity = id;
      _cachedRecentlyAddedPathsFuture =
          RecentlyAddedStore.orderedPathsForLibrary(tracks);
    }
    return _cachedRecentlyAddedPathsFuture!;
  }

  Future<List<String>> _recentlyPlayedPathsFuture() {
    final sr = RecentlyPlayedStore.revision.value;
    final tr = _recentListRevision;
    if (_cachedRecentlyPlayedPathsFuture == null ||
        _cachedRecentlyPlayedStoreRev != sr ||
        _cachedRecentlyPlayedTabRev != tr) {
      _cachedRecentlyPlayedStoreRev = sr;
      _cachedRecentlyPlayedTabRev = tr;
      _cachedRecentlyPlayedPathsFuture = RecentlyPlayedStore.loadPaths();
    }
    return _cachedRecentlyPlayedPathsFuture!;
  }

  LibraryTrackSortMode _songSortMode = LibraryTrackSortMode.modifiedNewest;

  /// After returning from Files, focus the Songs tab.
  void switchToSongsTab() {
    if (!mounted) return;
    final ix = _visibleTabs.indexOf(LibraryTabId.songs);
    if (ix >= 0) _tabController.index = ix;
    setState(() {});
  }

  /// Used when closing Now Playing to restore the library section that started playback.
  Future<void> switchToTabAndScrollToCurrentTrack(LibraryTabId tabId) async {
    if (!mounted) return;
    var ix = _visibleTabs.indexOf(tabId);
    if (ix < 0) {
      ix = _visibleTabs.indexOf(LibraryTabId.songs);
      if (ix < 0) ix = 0;
    }
    _tabController.index = ix;
    setState(() {});
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await _scrollActiveTabToCurrentTrack();
  }

  /// Active library tab in the current UI.
  LibraryTabId get currentTabId => _currentLibraryTabId;

  LibraryTabId get _currentLibraryTabId =>
      _visibleTabs[_tabController.index.clamp(0, _visibleTabs.length - 1)];

  bool _isActiveTab(LibraryTabId id) =>
      _tabController.index >= 0 &&
      _tabController.index < _visibleTabs.length &&
      _visibleTabs[_tabController.index] == id;

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
    _tabController = TabController(length: _visibleTabs.length, vsync: this);
    _searchController.addListener(() => setState(() {}));
    _tabController.addListener(_onTabChanged);
    LibraryTabsStore.revision.addListener(_onLibraryTabsRevision);
    LibraryTrackSortStore.revision.addListener(_onSongSortStoreRevision);
    RecentListLimitsStore.revision.addListener(_onRecentLimitsRevision);
    UserPlaylistsStore.revision.addListener(_onUserPlaylistsRevision);
    unawaited(FavoriteSongsStore.ensureLoaded());
    unawaited(_reloadSongSortMode());
    unawaited(_syncTabsFromStore());
    unawaited(_reloadUserPlaylists());
  }

  Future<void> _syncTabsFromStore() async {
    final next = await LibraryTabsStore.loadVisibleOrdered();
    if (!mounted) return;
    _replaceVisibleTabs(next.isEmpty ? [LibraryTabId.songs] : next);
  }

  void _onLibraryTabsRevision() {
    unawaited(_syncTabsFromStore());
  }

  void _replaceVisibleTabs(List<LibraryTabId> next) {
    final use = next.isEmpty ? [LibraryTabId.songs] : next;
    if (listEquals(_visibleTabs, use)) return;
    final oldLen = _visibleTabs.length;
    final oldIx = oldLen == 0 ? 0 : _tabController.index.clamp(0, oldLen - 1);
    final oldId = _visibleTabs.isEmpty
        ? LibraryTabId.songs
        : _visibleTabs[oldIx];
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _visibleTabs = List<LibraryTabId>.from(use);
    var initialIx = _visibleTabs.indexOf(oldId);
    if (initialIx < 0) {
      initialIx = oldIx.clamp(0, _visibleTabs.length - 1);
    }
    _tabController = TabController(
      length: _visibleTabs.length,
      vsync: this,
      initialIndex: initialIx.clamp(0, _visibleTabs.length - 1),
    );
    _tabController.addListener(_onTabChanged);
    setState(() {});
  }

  Future<void> _reloadSongSortMode() async {
    final m = await LibraryTrackSortStore.load();
    if (mounted) setState(() => _songSortMode = m);
  }

  void _onSongSortStoreRevision() {
    unawaited(_reloadSongSortMode());
  }

  void _onRecentLimitsRevision() {
    if (!mounted) return;
    setState(() => _recentListRevision++);
  }

  void _onUserPlaylistsRevision() {
    unawaited(_reloadUserPlaylists());
  }

  Future<void> _reloadUserPlaylists() async {
    final all = await UserPlaylistsStore.loadAll();
    if (!mounted) return;
    setState(() {
      _userPlaylists = all;
      _userPlaylistsLoading = false;
    });
  }

  void _onTabChanged() {
    if (!mounted) return;
    if (_tabController.indexIsChanging) return;
    setState(() {
      if (_currentLibraryTabId == LibraryTabId.recentlyPlayed) {
        _recentListRevision++;
      }
    });
    if (_currentLibraryTabId == LibraryTabId.favourites) {
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
    _nowPlayingListScrollController.dispose();
    LibraryTabsStore.revision.removeListener(_onLibraryTabsRevision);
    LibraryTrackSortStore.revision.removeListener(_onSongSortStoreRevision);
    RecentListLimitsStore.revision.removeListener(_onRecentLimitsRevision);
    UserPlaylistsStore.revision.removeListener(_onUserPlaylistsRevision);
    super.dispose();
  }

  List<int> _sortedSongsTabIndices(
    List<TrackItem> tracks,
    String query,
    Set<String>? browsePathKeys,
  ) {
    final baseFilteredIndices = tracks.isEmpty
        ? <int>[]
        : _filteredPlaylistIndices(tracks, query);
    final scoped = _playlistIndicesInPathKeySet(
      baseFilteredIndices,
      tracks,
      browsePathKeys,
    );
    return sortFilteredTrackIndices(scoped, tracks, _songSortMode);
  }

  bool _userPlaylistContainsCurrentPath(UserPlaylistEntry pl, String pathKey) {
    for (final p in pl.paths) {
      if (canonicalMusicLibraryPathKey(p) == pathKey) return true;
    }
    return false;
  }

  /// Visible row index in Songs list (after search + folder filter) and row count.
  (int? index, int total) _songsListIndexAndTotalForPathKey(
    List<TrackItem> tracks,
    Set<String>? browsePathKeys,
    String query,
    String pathKey,
  ) {
    final songsTabIndices = _sortedSongsTabIndices(
      tracks,
      query,
      browsePathKeys,
    );
    for (var i = 0; i < songsTabIndices.length; i++) {
      final fp = tracks[songsTabIndices[i]].filePath;
      if (fp != null && canonicalMusicLibraryPathKey(fp) == pathKey) {
        return (i, songsTabIndices.length);
      }
    }
    return (null, songsTabIndices.length);
  }

  void _scheduleScrollAnchorIntoView(GlobalKey anchorKey) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = anchorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0,
          duration: Duration.zero,
          curve: Curves.linear,
        );
      }
    });
  }

  /// Lazy [ListView] may not build the target row until scroll offset is near it.
  /// Uses proportional and fixed strides so the anchor [GlobalKey] mounts, then
  /// snaps the row to the top of the viewport.
  Future<void> _coaxLazyListThenEnsureVisible(
    ScrollController controller,
    int index,
    int totalItems,
    GlobalKey anchorKey, {
    double rowStride = _kLibraryListRowStride,
  }) async {
    if (!mounted) return;
    final clampedIndex = index.clamp(0, totalItems > 0 ? totalItems - 1 : 0);

    for (var attempt = 0; attempt < 45; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;

      final mountedCtx = anchorKey.currentContext;
      if (mountedCtx != null && mountedCtx.mounted) {
        _scheduleScrollAnchorIntoView(anchorKey);
        return;
      }

      if (!controller.hasClients) continue;

      final pos = controller.position;
      final maxExtent = pos.maxScrollExtent;
      double target;
      if (maxExtent <= 0) {
        target = 0;
      } else {
        final scale = totalItems <= 1 ? 0.0 : (clampedIndex / (totalItems - 1));
        final proportional = scale * maxExtent;
        final linear = (index * rowStride).clamp(0.0, maxExtent);
        target = switch (attempt % 3) {
          0 => proportional.clamp(0.0, maxExtent),
          1 => linear,
          _ => (proportional * 0.55 + linear * 0.45).clamp(0.0, maxExtent),
        };
      }
      controller.jumpTo(target);
    }
  }

  Future<void> _scrollNowPlayingQueueToCurrentTrack() async {
    if (!mounted) return;
    final player = PlayerController.of(context);
    final playlist = player.playlist;
    if (playlist.isEmpty) return;
    final currentPl = player.currentIndex;
    if (currentPl < 0 || currentPl >= playlist.length) return;

    final searchQuery = _effectiveLibrarySearchQuery(_searchController.text);
    final order = player.playbackOrderIndices;

    var listIndex = -1;
    var visibleCount = 0;
    for (var r = 0; r < order.length; r++) {
      final pl = order[r];
      if (pl < 0 || pl >= playlist.length) continue;
      final t = playlist[pl];
      if (!PlayingQueueTab.matchesSearchFilter(t, searchQuery)) continue;
      if (pl == currentPl) listIndex = visibleCount;
      visibleCount++;
    }
    if (listIndex < 0) return;

    await _coaxLazyListThenEnsureVisible(
      _nowPlayingListScrollController,
      listIndex,
      visibleCount,
      _scrollAnchorNowPlayingList,
      rowStride: _kQueueListRowStride,
    );
  }

  Future<void> _scrollActiveTabToCurrentTrack() async {
    if (!mounted) return;
    final player = PlayerController.of(context);
    final cur = player.currentTrack?.filePath;
    if (cur == null || cur.isEmpty) return;
    final pathKey = canonicalMusicLibraryPathKey(cur);
    if (pathKey.isEmpty) return;

    final tracks = player.metadataLibrary;
    final searchQuery = _effectiveLibrarySearchQuery(_searchController.text);
    final browsePathKeys = widget.songsBrowsePathKeys.value;

    switch (_currentLibraryTabId) {
      case LibraryTabId.songs:
        final (idx, total) = _songsListIndexAndTotalForPathKey(
          tracks,
          browsePathKeys,
          searchQuery,
          pathKey,
        );
        if (idx == null) return;
        await _coaxLazyListThenEnsureVisible(
          _songsScrollController,
          idx,
          total,
          _scrollAnchorSongs,
        );
        return;
      case LibraryTabId.recentlyAdded:
        final ordered = await RecentlyAddedStore.orderedPathsForLibrary(tracks);
        if (!mounted) return;
        var paths = _pathsMatchingBrowse(ordered, browsePathKeys);
        paths = _filterPathsBySearch(paths, searchQuery, tracks);
        final idx = paths.indexWhere(
          (p) => canonicalMusicLibraryPathKey(p) == pathKey,
        );
        if (idx < 0) return;
        await _coaxLazyListThenEnsureVisible(
          _recentAddedScrollController,
          idx,
          paths.length,
          _scrollAnchorRecentAdded,
        );
        return;
      case LibraryTabId.playlist:
        final all = await UserPlaylistsStore.loadAll();
        if (!mounted) return;
        final filtered = _filterPlaylistsBySearch(all, searchQuery);
        final idx = filtered.indexWhere(
          (pl) => _userPlaylistContainsCurrentPath(pl, pathKey),
        );
        if (idx < 0) return;
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        var ctx = _scrollAnchorPlaylist.currentContext;
        if (ctx == null) {
          if (_playlistScrollController.hasClients) {
            final max = _playlistScrollController.position.maxScrollExtent;
            _playlistScrollController.jumpTo(
              (120.0 + idx * 80).clamp(0.0, max),
            );
            await WidgetsBinding.instance.endOfFrame;
            if (!mounted) return;
            ctx = _scrollAnchorPlaylist.currentContext;
          }
        }
        if (ctx != null && ctx.mounted) {
          _scheduleScrollAnchorIntoView(_scrollAnchorPlaylist);
        }
        return;
      case LibraryTabId.favourites:
        final favPaths = await FavoriteSongsStore.loadPaths();
        if (!mounted) return;
        var paths = _pathsMatchingBrowse(favPaths, null);
        paths = _filterPathsBySearch(paths, searchQuery, tracks);
        final idx = paths.indexWhere(
          (p) => canonicalMusicLibraryPathKey(p) == pathKey,
        );
        if (idx < 0) return;
        await _coaxLazyListThenEnsureVisible(
          _favoritesScrollController,
          idx,
          paths.length,
          _scrollAnchorFavorites,
        );
        return;
      case LibraryTabId.recentlyPlayed:
        final played = await RecentlyPlayedStore.loadPaths();
        if (!mounted) return;
        var paths = _pathsMatchingBrowse(played, browsePathKeys);
        paths = _filterPathsBySearch(paths, searchQuery, tracks);
        final idx = paths.indexWhere(
          (p) => canonicalMusicLibraryPathKey(p) == pathKey,
        );
        if (idx < 0) return;
        await _coaxLazyListThenEnsureVisible(
          _recentPlayedScrollController,
          idx,
          paths.length,
          _scrollAnchorRecentPlayed,
        );
        return;
      case LibraryTabId.nowPlayingList:
        final order = player.playbackOrderIndices;
        final playlist = player.playlist;
        var orderPos = -1;
        for (var r = 0; r < order.length; r++) {
          final pl = order[r];
          if (pl < 0 || pl >= playlist.length) continue;
          final fp = playlist[pl].filePath;
          if (fp != null && canonicalMusicLibraryPathKey(fp) == pathKey) {
            orderPos = r;
            break;
          }
        }
        if (orderPos < 0) return;
        var listIndex = orderPos;
        var listTotal = order.length;
        if (searchQuery.isNotEmpty) {
          listIndex = -1;
          var vis = 0;
          for (var r = 0; r < order.length; r++) {
            final pl = order[r];
            if (pl < 0 || pl >= playlist.length) continue;
            final t = playlist[pl];
            if (!PlayingQueueTab.matchesSearchFilter(t, searchQuery)) {
              continue;
            }
            if (r == orderPos) listIndex = vis;
            vis++;
          }
          listTotal = vis;
          if (listIndex < 0) return;
        }
        await _coaxLazyListThenEnsureVisible(
          _nowPlayingListScrollController,
          listIndex,
          listTotal,
          _scrollAnchorNowPlayingList,
          rowStride: _kQueueListRowStride,
        );
        return;
    }
  }

  static bool _trackMatchesQuery(TrackItem t, String q) {
    if (q.isEmpty) return true;
    return t.title.toLowerCase().contains(q);
  }

  String _searchHintForTab(LibraryTabId id) => switch (id) {
    LibraryTabId.songs ||
    LibraryTabId.recentlyAdded ||
    LibraryTabId.playlist => 'Search by title (min. 3 characters)',
    LibraryTabId.nowPlayingList => 'Search queue (min. 3 characters)',
    LibraryTabId.favourites => 'Search favourites (min. 3 characters)',
    LibraryTabId.recentlyPlayed => 'Search RecentlyPlayed (min. 3 characters)',
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
    required LibraryTabId playbackOriginTab,
    Set<String>? pathKeyScope,
    String? playbackOriginUserPlaylistId,
  }) async {
    if (orderedPaths.isEmpty) return;
    final player = PlayerController.of(context);
    final library = player.metadataLibrary;
    final tracks = orderedPaths
        .map((path) => _trackForPath(path, library))
        .toList();
    if (pathKeyScope != null) {
      player.setPlaybackPathKeyScope(pathKeyScope, reloadQueue: false);
    } else {
      player.setPlaybackPathKeyScope(null, reloadQueue: false);
    }
    await player.setPlaylistAndPlay(
      tracks,
      startIndex: startIndex.clamp(0, tracks.length - 1),
      playbackOriginTab: playbackOriginTab,
      playbackOriginUserPlaylistId: playbackOriginUserPlaylistId,
      keepShuffleMode: true,
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

  /// Used after closing Now Playing when playback started from a user playlist.
  Future<void> openUserPlaylistSheetById(String playlistId) async {
    if (!mounted) return;
    final player = PlayerController.of(context);
    final all = await UserPlaylistsStore.loadAll();
    UserPlaylistEntry? found;
    for (final p in all) {
      if (p.id == playlistId) {
        found = p;
        break;
      }
    }
    if (!mounted || found == null) return;
    final playlistIx = _visibleTabs.indexOf(LibraryTabId.playlist);
    if (playlistIx >= 0) {
      _tabController.index = playlistIx;
      setState(() {});
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    await _showUserPlaylistSheet(
      context,
      found,
      player.metadataLibrary,
      player,
    );
  }

  Future<void> _showCreatePlaylistDialog(BuildContext context) async {
    final existing = await UserPlaylistsStore.loadAll();
    if (!context.mounted) return;
    final name = await showCreatePlaylistNameDialogWithExistingNames(
      context,
      existingNames: existing.map((e) => e.name).toSet(),
    );
    if (!context.mounted || name == null || name.trim().isEmpty) return;
    final created = await UserPlaylistsStore.createPlaylist(name.trim());
    if (created == null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Playlist name already exists. Please rename it.'),
        ),
      );
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

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: pal.surface,
      showDragHandle: true,
      builder: (ctx) {
        return ValueListenableBuilder<int>(
          valueListenable: UserPlaylistsStore.revision,
          builder: (context, _, __) {
            return FutureBuilder<List<UserPlaylistEntry>>(
              future: UserPlaylistsStore.loadAll(),
              builder: (context, snap) {
                final all = snap.data;
                UserPlaylistEntry? resolved;
                if (all != null) {
                  for (final e in all) {
                    if (e.id == playlist.id) {
                      resolved = e;
                      break;
                    }
                  }
                }
                if (snap.connectionState == ConnectionState.done &&
                    all != null &&
                    resolved == null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  });
                  return const SizedBox.shrink();
                }
                final sheetPlaylist = resolved ?? playlist;
                final paths = sheetPlaylist.paths;

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
                                  sheetPlaylist.name,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: pal.textPrimary,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Delete playlist',
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  color: pal.textSecondary,
                                ),
                                onPressed: () async {
                                  final confirmed = await showDialog<bool>(
                                    context: ctx,
                                    builder: (dialogCtx) {
                                      final scheme = Theme.of(
                                        dialogCtx,
                                      ).colorScheme;
                                      return AlertDialog(
                                        backgroundColor: pal.surface,
                                        title: Text(
                                          'Delete playlist?',
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                                color: pal.textPrimary,
                                              ),
                                        ),
                                        content: Text(
                                          'Remove “${sheetPlaylist.name}” '
                                          'from your playlists? '
                                          'Your music files stay on the device.',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: pal.textSecondary,
                                              ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.of(
                                              dialogCtx,
                                            ).pop(false),
                                            child: const Text('Cancel'),
                                          ),
                                          FilledButton(
                                            onPressed: () => Navigator.of(
                                              dialogCtx,
                                            ).pop(true),
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
                                  if (confirmed != true) return;
                                  await UserPlaylistsStore.deletePlaylist(
                                    sheetPlaylist.id,
                                  );
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
                                    playbackOriginTab: LibraryTabId.playlist,
                                    playbackOriginUserPlaylistId:
                                        sheetPlaylist.id,
                                  );
                                },
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: const Text('Play all'),
                              ),
                            ),
                          ),
                          Builder(
                            builder: (_) {
                              final resolvedTracks = paths
                                  .map((p) => _trackForPath(p, library))
                                  .toList();
                              return SizedBox(
                                height: min(
                                  MediaQuery.sizeOf(ctx).height * 0.55,
                                  24 + paths.length * 76.0,
                                ),
                                child: ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                    8,
                                    8,
                                    8,
                                    24,
                                  ),
                                  itemCount: paths.length,
                                  separatorBuilder: (_, __) => Divider(
                                    height: 1,
                                    color: pal.dividerOnHero,
                                    indent: 88,
                                  ),
                                  itemBuilder: (context, i) {
                                    final path = paths[i];
                                    final track = resolvedTracks[i];
                                    final selected = _isCurrentTrackPath(
                                      player,
                                      path,
                                    );
                                    return Material(
                                      color: selected
                                          ? pal.onScaffold.withValues(
                                              alpha: 0.06,
                                            )
                                          : Colors.transparent,
                                      child: ListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
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
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                color: pal.textPrimary,
                                                fontSize: 15,
                                              ),
                                        ),
                                        subtitle: Text(
                                          track.artist,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: pal.textSecondary,
                                              ),
                                        ),
                                        trailing: IconButton(
                                          tooltip: 'Remove from playlist',
                                          icon: Icon(
                                            Icons.playlist_remove_rounded,
                                            color: pal.textSecondary,
                                          ),
                                          onPressed: () {
                                            unawaited(
                                              _onTrackOverflow(
                                                context,
                                                player,
                                                -1,
                                                TrackOverflowAction
                                                    .removeFromPlaylist,
                                                playbackOriginTab:
                                                    LibraryTabId.playlist,
                                                outsideQueue:
                                                    TrackOverflowQueueContext(
                                                      tracks: resolvedTracks,
                                                      index: i,
                                                      playbackOriginTab:
                                                          LibraryTabId.playlist,
                                                    ),
                                                userPlaylistId:
                                                    sheetPlaylist.id,
                                              ),
                                            );
                                          },
                                        ),
                                        onTap: () {
                                          Navigator.of(ctx).pop();
                                          _playOrderedPathsFrom(
                                            context,
                                            paths,
                                            i,
                                            playbackOriginTab:
                                                LibraryTabId.playlist,
                                            playbackOriginUserPlaylistId:
                                                sheetPlaylist.id,
                                          );
                                        },
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        ],
                      ],
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

  Widget _buildPlaylistTab(
    ThemeData theme,
    BuildContext context,
    AppPalette pal,
    String query,
    List<TrackItem> tracks,
    PlayerController player,
  ) {
    final filteredPlaylists = _filterPlaylistsBySearch(_userPlaylists, query);

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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: context.controlAccent.withValues(alpha: 0.18),
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
                            color: pal.textSecondary.withValues(alpha: 0.9),
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
        if (_userPlaylistsLoading)
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
              style: theme.textTheme.bodyMedium?.copyWith(color: pal.textMuted),
            ),
          )
        else
          ...() {
            var anchorIndex = -1;
            if (_isActiveTab(LibraryTabId.playlist) && curKey.isNotEmpty) {
              for (var j = 0; j < filteredPlaylists.length; j++) {
                if (_userPlaylistContainsCurrentPath(
                  filteredPlaylists[j],
                  curKey,
                )) {
                  anchorIndex = j;
                  break;
                }
              }
            }
            return List.generate(filteredPlaylists.length, (i) {
              final pl = filteredPlaylists[i];
              final attachScrollKey =
                  _isActiveTab(LibraryTabId.playlist) && anchorIndex == i;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (i > 0)
                    Divider(height: 1, color: pal.dividerOnHero, indent: 56),
                  Material(
                    key: attachScrollKey ? _scrollAnchorPlaylist : null,
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        _showUserPlaylistSheet(context, pl, tracks, player);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: pal.onScaffold.withValues(
                                alpha: 0.1,
                              ),
                              child: Icon(
                                Icons.queue_music_rounded,
                                color: pal.onScaffold.withValues(alpha: 0.75),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: pal.textMuted.withValues(
                                        alpha: 0.92,
                                      ),
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
            });
          }(),
      ],
    );
  }

  Future<void> _onTrackOverflow(
    BuildContext context,
    PlayerController player,
    int playlistIndex,
    TrackOverflowAction action, {
    LibraryTabId? playbackOriginTab,
    TrackOverflowQueueContext? outsideQueue,
    String? userPlaylistId,
  }) async {
    await applyTrackOverflowAction(
      context,
      player,
      playlistIndex,
      action,
      playbackOriginTab: playbackOriginTab,
      outsideQueue: outsideQueue,
      userPlaylistId: userPlaylistId,
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
            final rawSearch = _searchController.text.trim();
            final searchQuery = _effectiveLibrarySearchQuery(rawSearch);
            final songsTabIndices = _sortedSongsTabIndices(
              tracks,
              searchQuery,
              browsePathKeys,
            );

            final pal = context.palette;
            final hint = _searchHintForTab(_currentLibraryTabId);

            return DaisyBackground(
              baseColor: pal.scaffoldBackground,
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
                              onSubmitted: (_) =>
                                  FocusManager.instance.primaryFocus?.unfocus(),
                              onTapOutside: (_) =>
                                  FocusManager.instance.primaryFocus?.unfocus(),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: pal.onScaffold,
                                fontSize: 15,
                              ),
                              decoration: _searchDecoration(
                                pal,
                                theme,
                                hintText: hint,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh_rounded),
                            color: pal.onScaffold,
                            tooltip: 'Refresh library',
                            onPressed: widget.onRefreshLibrary,
                          ),
                          if (_currentLibraryTabId == LibraryTabId.songs)
                            PopupMenuButton<LibraryTrackSortMode>(
                              tooltip: 'Sort songs',
                              icon: Icon(
                                Icons.sort_rounded,
                                color: pal.onScaffold,
                              ),
                              padding: EdgeInsets.zero,
                              onSelected: (mode) async {
                                await LibraryTrackSortStore.save(mode);
                              },
                              itemBuilder: (context) => [
                                for (final mode in LibraryTrackSortMode.values)
                                  CheckedPopupMenuItem<LibraryTrackSortMode>(
                                    value: mode,
                                    checked: mode == _songSortMode,
                                    child: Text(mode.menuLabel),
                                  ),
                              ],
                            )
                          else
                            const SizedBox(width: 48),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: TabBar(
                        key: ObjectKey(_tabController),
                        controller: _tabController,
                        isScrollable: true,
                        padding: const EdgeInsets.only(left: 2, right: 8),
                        labelPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                        ),
                        tabAlignment: TabAlignment.start,
                        indicatorColor: pal.onScaffold,
                        indicatorWeight: 2.8,
                        indicatorSize: TabBarIndicatorSize.label,
                        labelColor: pal.onScaffold,
                        unselectedLabelColor: pal.textMuted.withValues(
                          alpha: 0.76,
                        ),
                        dividerColor: pal.onScaffold.withValues(alpha: 0.14),
                        dividerHeight: 1,
                        labelStyle: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          fontSize: 15,
                        ),
                        unselectedLabelStyle: theme.textTheme.titleSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w500,
                              letterSpacing: -0.2,
                              fontSize: 15,
                            ),
                        splashFactory: NoSplash.splashFactory,
                        overlayColor: WidgetStateProperty.all<Color>(
                          Colors.transparent,
                        ),
                        tabs: [
                          for (final id in _visibleTabs)
                            Tab(text: id.shortTitle),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        key: ObjectKey(_tabController),
                        controller: _tabController,
                        children: [
                          for (final id in _visibleTabs)
                            _libraryTabPage(
                              id,
                              theme,
                              context,
                              pal,
                              tracks,
                              songsTabIndices,
                              player,
                              browsePathKeys,
                              searchQuery,
                            ),
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

  Widget _libraryTabPage(
    LibraryTabId id,
    ThemeData theme,
    BuildContext context,
    AppPalette pal,
    List<TrackItem> tracks,
    List<int> songsTabIndices,
    PlayerController player,
    Set<String>? browsePathKeys,
    String searchQuery,
  ) {
    return switch (id) {
      LibraryTabId.songs => _buildTracksTab(
        theme,
        context,
        tracks,
        songsTabIndices,
        player,
        searchQuery,
        browsePathKeys: browsePathKeys,
        onClearBrowseFolder: browsePathKeys == null
            ? null
            : widget.onClearSongsBrowseFilter,
      ),
      LibraryTabId.nowPlayingList => PlayingQueueTab(
        theme: theme,
        pal: pal,
        player: player,
        searchQuery: searchQuery,
        scrollController: _nowPlayingListScrollController,
        scrollAnchorKey: _scrollAnchorNowPlayingList,
        onScrollToCurrentPlaying: _scrollNowPlayingQueueToCurrentTrack,
        onOverflow: (playlistIndex, action) => _onTrackOverflow(
          context,
          player,
          playlistIndex,
          action,
          playbackOriginTab: LibraryTabId.nowPlayingList,
        ),
        onReorder: (oldOrder, newOrder) {
          player.reorderPlaybackQueue(oldOrder, newOrder);
        },
      ),
      LibraryTabId.recentlyAdded => _buildRecentlyAddedTab(
        theme,
        pal,
        searchQuery,
        player,
        tracks,
        browsePathKeys,
      ),
      LibraryTabId.playlist => _buildPlaylistTab(
        theme,
        context,
        pal,
        searchQuery,
        tracks,
        player,
      ),
      LibraryTabId.favourites => _buildFavoritesTab(
        theme,
        pal,
        searchQuery,
        player,
        tracks,
        null,
      ),
      LibraryTabId.recentlyPlayed => _buildRecentTab(
        theme,
        pal,
        searchQuery,
        player,
        tracks,
        browsePathKeys,
      ),
    };
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
          future: _favouritePathsFuture(),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return Center(
                child: CircularProgressIndicator(color: context.controlAccent),
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

            final library = player.metadataLibrary;
            return ListView.separated(
              controller: _favoritesScrollController,
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: paths.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: pal.dividerOnHero, indent: 88),
              itemBuilder: (context, i) {
                final path = paths[i];
                final track = _trackForPath(path, library);
                final plIndex = _playlistIndexForPath(player, path);
                final selected = _isCurrentTrackPath(player, path);
                final attachScrollKey =
                    selected && _isActiveTab(LibraryTabId.favourites);
                return Material(
                  key: attachScrollKey ? _scrollAnchorFavorites : null,
                  color: selected
                      ? pal.onScaffold.withValues(alpha: 0.08)
                      : Colors.transparent,
                  child: InkWell(
                    onTap: () => _playOrderedPathsFrom(
                      context,
                      paths,
                      i,
                      playbackOriginTab: LibraryTabId.favourites,
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
                                    color: pal.textSecondary.withValues(
                                      alpha: 0.95,
                                    ),
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
                              final resolvedTracks = paths
                                  .map((p) => _trackForPath(p, library))
                                  .toList();
                              unawaited(
                                _onTrackOverflow(
                                  context,
                                  player,
                                  plIndex >= 0 ? plIndex : -1,
                                  action,
                                  playbackOriginTab: LibraryTabId.favourites,
                                  outsideQueue: plIndex < 0
                                      ? TrackOverflowQueueContext(
                                          tracks: resolvedTracks,
                                          index: i,
                                          playbackOriginTab:
                                              LibraryTabId.favourites,
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
          future: _recentlyAddedPathsFuture(tracks),
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
                        'Nothing new yet',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: pal.onScaffold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'RecentlyAdded lists tracks added after your library was first scanned, or copied into your Settings folders later. Refresh rescans folders.',
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
                  ? 'No RecentlyAdded songs in this folder.'
                  : 'No RecentlyAdded songs match your search.';
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

            final library = player.metadataLibrary;
            return ListView.separated(
              controller: _recentAddedScrollController,
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: paths.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: pal.dividerOnHero, indent: 88),
              itemBuilder: (context, i) {
                final path = paths[i];
                final track = _trackForPath(path, library);
                final plIndex = _playlistIndexForPath(player, path);
                final selected = _isCurrentTrackPath(player, path);
                final attachScrollKey =
                    selected && _isActiveTab(LibraryTabId.recentlyAdded);
                return Material(
                  key: attachScrollKey ? _scrollAnchorRecentAdded : null,
                  color: selected
                      ? pal.onScaffold.withValues(alpha: 0.08)
                      : Colors.transparent,
                  child: InkWell(
                    onTap: () => _playOrderedPathsFrom(
                      context,
                      paths,
                      i,
                      playbackOriginTab: LibraryTabId.recentlyAdded,
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
                                    color: pal.textSecondary.withValues(
                                      alpha: 0.95,
                                    ),
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
                              final resolvedTracks = paths
                                  .map((p) => _trackForPath(p, library))
                                  .toList();
                              unawaited(
                                _onTrackOverflow(
                                  context,
                                  player,
                                  plIndex >= 0 ? plIndex : -1,
                                  action,
                                  playbackOriginTab: LibraryTabId.recentlyAdded,
                                  outsideQueue: plIndex < 0
                                      ? TrackOverflowQueueContext(
                                          tracks: resolvedTracks,
                                          index: i,
                                          playbackOriginTab:
                                              LibraryTabId.recentlyAdded,
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

  Widget _buildRecentTab(
    ThemeData theme,
    AppPalette pal,
    String rawQuery,
    PlayerController player,
    List<TrackItem> tracks,
    Set<String>? browsePathKeys,
  ) {
    return ValueListenableBuilder<int>(
      valueListenable: RecentlyPlayedStore.revision,
      builder: (context, _, __) {
        return FutureBuilder<List<String>>(
          future: _recentlyPlayedPathsFuture(),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return Center(
                child: CircularProgressIndicator(color: context.controlAccent),
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
                  ? 'No RecentlyPlayed songs in this folder.'
                  : 'No RecentlyPlayed songs match your search.';
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

            final library = player.metadataLibrary;
            return ListView.separated(
              controller: _recentPlayedScrollController,
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: paths.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: pal.dividerOnHero, indent: 88),
              itemBuilder: (context, i) {
                final path = paths[i];
                final track = _trackForPath(path, library);
                final plIndex = _playlistIndexForPath(player, path);
                final selected = _isCurrentTrackPath(player, path);
                final attachScrollKey =
                    selected && _isActiveTab(LibraryTabId.recentlyPlayed);
                return Material(
                  key: attachScrollKey ? _scrollAnchorRecentPlayed : null,
                  color: selected
                      ? pal.onScaffold.withValues(alpha: 0.08)
                      : Colors.transparent,
                  child: InkWell(
                    onTap: () => _playOrderedPathsFrom(
                      context,
                      paths,
                      i,
                      playbackOriginTab: LibraryTabId.recentlyPlayed,
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
                                    color: pal.textSecondary.withValues(
                                      alpha: 0.95,
                                    ),
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
                              final resolvedTracks = paths
                                  .map((p) => _trackForPath(p, library))
                                  .toList();
                              unawaited(
                                _onTrackOverflow(
                                  context,
                                  player,
                                  plIndex >= 0 ? plIndex : -1,
                                  action,
                                  playbackOriginTab:
                                      LibraryTabId.recentlyPlayed,
                                  outsideQueue: plIndex < 0
                                      ? TrackOverflowQueueContext(
                                          tracks: resolvedTracks,
                                          index: i,
                                          playbackOriginTab:
                                              LibraryTabId.recentlyPlayed,
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
    PlayerController player,
    String searchQuery, {
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
      final title = hasBrowseFilter && searchQuery.isEmpty
          ? 'No songs in this folder'
          : 'No matches';
      final detail = hasBrowseFilter && searchQuery.isEmpty
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
              if (searchQuery.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '"$searchQuery"',
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

    final filteredTracks = filteredIndices.map((idx) => tracks[idx]).toList();
    final orderedPaths = filteredTracks
        .map((t) => t.filePath)
        .whereType<String>()
        .toList();

    return ListView.separated(
      controller: _songsScrollController,
      cacheExtent: 4000,
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: filteredIndices.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: pal.dividerOnHero, indent: 88),
      itemBuilder: (context, i) {
        final catalogIndex = filteredIndices[i];
        final track = tracks[catalogIndex];
        final path = track.filePath;
        final selected = _isCurrentTrackPath(player, path);
        final plIndex = path != null && path.isNotEmpty
            ? _playlistIndexForPath(player, path)
            : -1;
        return _TrackTile(
          track: track,
          selected: selected,
          showPlayingIcon: selected,
          rowKey: selected && _isActiveTab(LibraryTabId.songs)
              ? _scrollAnchorSongs
              : null,
          onTap: () {
            unawaited(
              _playOrderedPathsFrom(
                context,
                orderedPaths,
                i,
                playbackOriginTab: LibraryTabId.songs,
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
                playbackOriginTab: LibraryTabId.songs,
                outsideQueue: plIndex < 0
                    ? TrackOverflowQueueContext(
                        tracks: filteredTracks,
                        index: i,
                        playbackOriginTab: LibraryTabId.songs,
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
    this.showPlayingIcon = false,
    this.rowKey,
    required this.onTap,
    required this.onOverflowAction,
  });

  final TrackItem track;
  final bool selected;

  /// When true (Songs tab), shows a play icon next to the title for the now-playing row.
  final bool showPlayingIcon;
  final Key? rowKey;
  final VoidCallback onTap;
  final void Function(TrackOverflowAction action) onOverflowAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;

    return Material(
      key: rowKey,
      color: selected
          ? pal.onScaffold.withValues(alpha: 0.08)
          : Colors.transparent,
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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (showPlayingIcon) ...[
                          Icon(
                            Icons.play_arrow_rounded,
                            size: 22,
                            color: context.controlAccent,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: pal.onScaffold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
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
