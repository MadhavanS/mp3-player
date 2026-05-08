import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../audio/player_controller.dart';
import '../../models/library_tab_id.dart';
import '../../models/track_item.dart';
import '../../services/favorite_songs_store.dart';
import '../../services/folder_browser.dart';
import '../../services/library_track_sort.dart';
import '../../services/mp3_scanner.dart';
import '../../services/music_library_path_key.dart';
import '../../theme/app_theme.dart';
import '../../widgets/track_album_art.dart';
import '../player/track_overflow_actions.dart';

/// Hierarchical "Files" browser for saved library roots (see design reference).
class LibraryFilesExplorer extends StatefulWidget {
  const LibraryFilesExplorer({
    super.key,
    required this.musicRoots,
    required this.query,
    required this.onOverflow,
    this.onSongChosenFromExplorer,
  });

  final List<String> musicRoots;
  final String query;

  final Future<void> Function(
    BuildContext context,
    PlayerController player,
    int playlistIndex,
    TrackOverflowAction action, {
    LibraryTabId? playbackOriginTab,
    TrackOverflowQueueContext? outsideQueue,
  }) onOverflow;

  /// After playback starts: on IO, [explicitTrackPathKeys] is the scanned set of `.mp3`
  /// under the open folder (recursive). On web pass `null` — Library keeps full list.
  final Future<void> Function(Set<String>? explicitTrackPathKeys)? onSongChosenFromExplorer;

  @override
  State<LibraryFilesExplorer> createState() => LibraryFilesExplorerState();
}

class LibraryFilesExplorerState extends State<LibraryFilesExplorer> {
  /// Each entry is absolute; [last] is current folder. Empty = show all roots.
  final List<String> _browseStack = [];

  Future<({List<String> dirs, List<String> mp3Paths})>? _childrenFuture;
  Future<int>? _headerSongsFuture;

  LibraryTrackSortMode _sortMode = LibraryTrackSortMode.modifiedNewest;

  @override
  void initState() {
    super.initState();
    LibraryTrackSortStore.revision.addListener(_onSortStoreRevision);
    unawaited(FavoriteSongsStore.ensureLoaded());
    unawaited(_bootstrapSortMode());
  }

  Future<void> _bootstrapSortMode() async {
    final m = await LibraryTrackSortStore.load();
    if (!mounted) return;
    setState(() {
      _sortMode = m;
      _reloadCurrentFutures();
    });
  }

  void _onSortStoreRevision() {
    unawaited(_bootstrapSortMode());
  }

  Future<({List<String> dirs, List<String> mp3Paths})> _fetchSortedListing(
    String dir,
  ) async {
    final listing = await listFolderChildrenSorted(dir);
    final mp3 =
        await sortMp3PathsForFilesExplorer(listing.mp3Paths, _sortMode);
    return (dirs: listing.dirs, mp3Paths: mp3);
  }

  @override
  void dispose() {
    LibraryTrackSortStore.revision.removeListener(_onSortStoreRevision);
    super.dispose();
  }

  @override
  void didUpdateWidget(LibraryFilesExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(widget.musicRoots, oldWidget.musicRoots)) {
      resetToRoots();
    }
  }

  void resetToRoots() {
    setState(() {
      _browseStack.clear();
      _childrenFuture = null;
      _headerSongsFuture = null;
    });
  }

  bool get _atRoots => _browseStack.isEmpty;

  String? get _currentDir => _browseStack.isEmpty ? null : _browseStack.last;

  void _reloadCurrentFutures() {
    final d = _currentDir;
    if (d != null) {
      _childrenFuture = _fetchSortedListing(d);
      _headerSongsFuture = totalMp3CountUnderFolder(d);
    } else {
      _childrenFuture = null;
      _headerSongsFuture = null;
    }
  }

  Widget _sortMenuButton(AppPalette pal) {
    return PopupMenuButton<LibraryTrackSortMode>(
      tooltip: 'Sort songs',
      icon: Icon(
        Icons.sort_rounded,
        color: pal.onScaffold.withValues(alpha: 0.85),
      ),
      padding: EdgeInsets.zero,
      onSelected: (m) async => LibraryTrackSortStore.save(m),
      itemBuilder: (context) => [
        for (final mode in LibraryTrackSortMode.values)
          CheckedPopupMenuItem<LibraryTrackSortMode>(
            value: mode,
            checked: mode == _sortMode,
            child: Text(mode.menuLabel),
          ),
      ],
    );
  }

  void _pushDir(String absolutePath) {
    if (!pathIsInsideAllowedRoots(absolutePath, widget.musicRoots)) return;
    setState(() {
      _browseStack.add(absolutePath);
      _reloadCurrentFutures();
    });
  }

  void _goBack() {
    if (_browseStack.isEmpty) return;
    setState(() {
      _browseStack.removeLast();
      _reloadCurrentFutures();
    });
  }

  Future<void> _openPathChain(String absolutePath) async {
    if (!pathIsInsideAllowedRoots(absolutePath, widget.musicRoots)) return;
    final root = _closestMusicRootPrefix(absolutePath);
    if (root == null) return;
    final rel = p.relative(p.normalize(absolutePath), from: p.normalize(root));
    final parts =
        p.split(rel).where((s) => s.isNotEmpty && s != '.').toList();

    final newStack = <String>[root];
    var cursor = root;
    for (final part in parts) {
      cursor = p.join(cursor, part);
      newStack.add(cursor);
    }
    if (!mounted) return;
    setState(() {
      _browseStack
        ..clear()
        ..addAll(newStack);
      _reloadCurrentFutures();
    });
  }

  String? _closestMusicRootPrefix(String path) {
    final normPath = p.normalize(path).toLowerCase();
    String? best;
    var bestLen = -1;
    final sep = p.separator;
    for (final r in widget.musicRoots) {
      final nr = p.normalize(r).toLowerCase();
      final rootWithSep =
          nr.endsWith(sep) ? nr.substring(0, nr.length - 1) : nr;
      final underThis = normPath == rootWithSep ||
          normPath.startsWith('$rootWithSep$sep');
      if (underThis) {
        if (r.length > bestLen) {
          bestLen = r.length;
          best = r;
        }
      }
    }
    return best;
  }

  List<String> _relativeSegmentsFromRoot(String dir) {
    final root = _closestMusicRootPrefix(dir);
    if (root == null) return [p.basename(dir)];
    final rel = p.relative(p.normalize(dir), from: p.normalize(root));
    if (rel == '.') return [];
    return p.split(rel).where((s) => s.isNotEmpty).toList();
  }

  Widget _filesHeader({
    required ThemeData theme,
    required AppPalette pal,
    String? title,
    required bool showBack,
    required VoidCallback? onBack,
    required Widget subtitleWidget,
    required VoidCallback? onHomeRoots,
    Widget? trailingActions,
  }) {
    final showTitle = title != null && title.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (showBack)
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: 'Back',
                  color: pal.onScaffold,
                  onPressed: onBack,
                )
              else
                const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showTitle) ...[
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: pal.onScaffold,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    subtitleWidget,
                  ],
                ),
              ),
              if (!_atRoots && onHomeRoots != null)
                IconButton(
                  tooltip: 'All folders',
                  icon: Icon(
                    Icons.home_rounded,
                    color: pal.onScaffold.withValues(alpha: 0.85),
                  ),
                  onPressed: onHomeRoots,
                ),
              if (trailingActions != null) trailingActions,
            ],
          ),
        ],
      ),
    );
  }

  Widget _breadcrumb(ThemeData theme, AppPalette pal) {
    final dir = _currentDir;
    if (dir == null) return const SizedBox.shrink();

    final root = _closestMusicRootPrefix(dir);
    final segs = _relativeSegmentsFromRoot(dir);

    final items = <Widget>[];
    if (root != null) {
      items.add(
        TextButton(
          onPressed: () {
            setState(() {
              _browseStack
                ..clear()
                ..add(root);
              _reloadCurrentFutures();
            });
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            p.basename(root).toUpperCase(),
            style: theme.textTheme.labelLarge?.copyWith(
              color: pal.onScaffold,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    var walk = root ?? dir;
    for (var i = 0; i < segs.length; i++) {
      final segment = segs[i];
      walk = p.join(walk, segment);
      final targetPath = walk;
      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: pal.textMuted.withValues(alpha: 0.7),
          ),
        ),
      );
      final isLast = i == segs.length - 1;
      items.add(
        TextButton(
          onPressed:
              isLast ? null : () => unawaited(_openPathChain(targetPath)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            segment.toUpperCase(),
            style: theme.textTheme.labelLarge?.copyWith(
              color: isLast
                  ? pal.textMuted.withValues(alpha: 0.85)
                  : pal.onScaffold,
              letterSpacing: 0.5,
              fontWeight: isLast ? FontWeight.w500 : FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: items),
        ),
      ),
    );
  }

  List<String> _filteredRoots() {
    final q = widget.query.trim().toLowerCase();
    if (q.isEmpty) return List<String>.from(widget.musicRoots);
    return widget.musicRoots
        .where(
          (path) =>
              p.basename(path).toLowerCase().contains(q) ||
              path.toLowerCase().contains(q),
        )
        .toList();
  }

  Future<String> _folderRowSubtitle(String folderPath) async {
    final listing = await listFolderChildrenSorted(folderPath);
    final subFolders = listing.dirs.length;
    final songsTotal = await totalMp3CountUnderFolder(folderPath);
    if (subFolders == 0) {
      return '$songsTotal Songs';
    }
    return '$subFolders folders • $songsTotal Songs';
  }

  Future<int> _totalSongsAcrossRoots(List<String> roots) async {
    var sum = 0;
    for (final r in roots) {
      sum += await totalMp3CountUnderFolder(r);
    }
    return sum;
  }

  TrackItem _displayTrack(PlayerController player, String filePath) {
    final lib = player.metadataLibrary;
    final i = lib.indexWhere((t) => t.filePath == filePath);
    if (i >= 0) return lib[i];
    return TrackItem.fromFilePath(filePath);
  }

  Future<void> _onTapMp3(BuildContext context, String filePath) async {
    final folderScope = _currentDir;
    if (folderScope == null) return;

    final player = PlayerController.of(context);
    final cb = widget.onSongChosenFromExplorer;

    if (kIsWeb) {
      player.setPlaybackPathKeyScope(null, reloadQueue: false);
      if (cb != null) await cb(null);
      await player.setPlaylistAndPlay(
        [TrackItem.fromFilePath(filePath)],
        playbackOriginTab: LibraryTabId.songs,
      );
      return;
    }

    final scanned = await scanMp3Files(folderScope, recursive: true);
    final keys = <String>{
      for (final path in scanned) canonicalMusicLibraryPathKey(path),
    }..removeWhere((k) => k.isEmpty);
    player.setPlaybackPathKeyScope(keys, reloadQueue: false);
    if (cb != null) await cb(keys);

    final library = player.metadataLibrary;
    final tracks = scanned
        .map((path) {
          final j = library.indexWhere((t) => t.filePath == path);
          return j >= 0 ? library[j] : TrackItem.fromFilePath(path);
        })
        .toList();
    final startIndex = tracks.indexWhere((t) => t.filePath == filePath);
    await player.setPlaylistAndPlay(
      tracks,
      startIndex: startIndex >= 0 ? startIndex : 0,
      playbackOriginTab: LibraryTabId.songs,
    );
  }

  String _durationSuffix(PlayerController player, String filePath) {
    if (player.currentTrack?.filePath == filePath && player.duration != null) {
      return _fmt(player.duration!);
    }
    return '--:--';
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.palette;
    final player = PlayerController.of(context);

    if (kIsWeb || widget.musicRoots.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.folder_off_rounded,
                size: 56,
                color: pal.onScaffold.withValues(alpha: 0.45),
              ),
              const SizedBox(height: 14),
              Text(
                widget.musicRoots.isEmpty
                    ? 'No folders yet'
                    : 'Files are unavailable in this environment.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: pal.onScaffold,
                ),
              ),
              if (widget.musicRoots.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Open Settings from the menu to add music folders.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: pal.textSecondary.withValues(alpha: 0.92),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (_atRoots) {
      final roots = _filteredRoots();
      if (roots.isEmpty) {
        return Center(
          child: Text(
            'No folder matches',
            style:
                theme.textTheme.titleMedium?.copyWith(color: pal.onScaffold),
          ),
        );
      }

      final songsSumFuture = _totalSongsAcrossRoots(roots);
      final headerSubtitle = FutureBuilder<int>(
        future: songsSumFuture,
        builder: (ctx, snap) {
          final n = snap.data;
          final text = snap.connectionState != ConnectionState.done || n == null
              ? '…'
              : '${roots.length} folders • $n Songs';
          return Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: pal.textMuted.withValues(alpha: 0.92),
            ),
          );
        },
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _filesHeader(
            theme: theme,
            pal: pal,
            showBack: false,
            onBack: null,
            subtitleWidget: headerSubtitle,
            onHomeRoots: null,
            trailingActions: _sortMenuButton(pal),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: roots.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: pal.dividerOnHero, indent: 54),
              itemBuilder: (ctx, i) {
                final r = roots[i];
                final name = p.basename(r);
                return InkWell(
                  onTap: () => _pushDir(r),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    child: Row(
                      children: [
                        Icon(Icons.folder_rounded,
                            size: 36,
                            color: pal.onScaffold.withValues(alpha: 0.65)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: pal.onScaffold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              FutureBuilder<String>(
                                future: _folderRowSubtitle(r),
                                builder: (_, s) => Text(
                                  s.data ?? '…',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: pal.textMuted.withValues(alpha: 0.93),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.more_vert_rounded,
                            color: pal.textMuted.withValues(alpha: 0.4)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    final dir = _currentDir!;
    _childrenFuture ??= _fetchSortedListing(dir);
    _headerSongsFuture ??= totalMp3CountUnderFolder(dir);

    return FutureBuilder<({List<String> dirs, List<String> mp3Paths})>(
      future: _childrenFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Center(child: CircularProgressIndicator(color: pal.primary));
        }
        final listing = snap.data ??
            (dirs: <String>[], mp3Paths: <String>[]);

        final q = widget.query.trim().toLowerCase();
        final dirsFiltered = listing.dirs.where((d) {
          if (q.isEmpty) return true;
          final b = p.basename(d).toLowerCase();
          return b.contains(q) || d.toLowerCase().contains(q);
        }).toList();

        final mp3sFiltered = listing.mp3Paths.where((fp) {
          if (q.isEmpty) return true;
          final b = p.basenameWithoutExtension(fp).toLowerCase();
          return b.contains(q) || fp.toLowerCase().contains(q);
        }).toList();

        final headerSubtitle = FutureBuilder<int>(
          future: _headerSongsFuture,
          builder: (ctx, s) {
            final totalSongs =
                s.connectionState != ConnectionState.done ? null : s.data;
            final text = totalSongs == null
                ? '…'
                : '${listing.dirs.length} folders • $totalSongs Songs';
            return Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: pal.textMuted.withValues(alpha: 0.92),
              ),
            );
          },
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _filesHeader(
              theme: theme,
              pal: pal,
              showBack: true,
              onBack: _goBack,
              subtitleWidget: headerSubtitle,
              onHomeRoots: resetToRoots,
              trailingActions: _sortMenuButton(pal),
            ),
            _breadcrumb(theme, pal),
            Expanded(
              child: ListenableBuilder(
                listenable: player,
                builder: (context, _) {
                  if (dirsFiltered.isEmpty && mp3sFiltered.isEmpty) {
                    return Center(
                      child: Text(
                        q.isEmpty
                            ? 'This folder is empty.'
                            : 'No matches.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: pal.textMuted,
                        ),
                      ),
                    );
                  }
                  final mp3QueueTracks =
                      mp3sFiltered.map((p) => _displayTrack(player, p)).toList();
                  return ListView(
                    padding: const EdgeInsets.only(bottom: 20),
                    children: [
                      ...dirsFiltered.map(
                        (folderPath) => InkWell(
                          onTap: () => _pushDir(folderPath),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 10),
                            child: Row(
                              children: [
                                Icon(Icons.folder_rounded,
                                    size: 38,
                                    color:
                                        pal.onScaffold.withValues(alpha: 0.62)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.basename(folderPath),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            theme.textTheme.titleMedium?.copyWith(
                                          color: pal.onScaffold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      FutureBuilder<String>(
                                        future: _folderRowSubtitle(folderPath),
                                        builder: (_, s) => Text(
                                          s.data ?? '…',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: pal.textMuted
                                                .withValues(alpha: 0.93),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.more_vert_rounded,
                                    color:
                                        pal.textMuted.withValues(alpha: 0.42)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      ...mp3sFiltered.asMap().entries.map((e) {
                        final rowIx = e.key;
                        final fp = e.value;
                        final idx = player.playlist
                            .indexWhere((t) => t.filePath == fp);
                        final t = _displayTrack(player, fp);
                        final cur = player.currentTrack?.filePath;
                        final sel = cur != null &&
                            fp.isNotEmpty &&
                            canonicalMusicLibraryPathKey(cur) ==
                                canonicalMusicLibraryPathKey(fp);
                        return Material(
                          color: sel
                              ? pal.onScaffold.withValues(alpha: 0.06)
                              : Colors.transparent,
                          child: InkWell(
                            onTap: () => _onTapMp3(context, fp),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 6),
                              child: Row(
                                children: [
                                  TrackAlbumArt(
                                    track: t,
                                    display: TrackArtDisplay.list,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          t.title,
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
                                          '${t.artist} · ${_durationSuffix(player, fp)}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style:
                                              theme.textTheme.bodySmall?.copyWith(
                                            color: pal.textMuted
                                                .withValues(alpha: 0.93),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  TrackOverflowMenuWithFavourite(
                                    pal: pal,
                                    track: t,
                                    overflowIcon: Icons.more_vert_rounded,
                                    iconSize: 22,
                                    menuIconColor: pal.onScaffold
                                        .withValues(alpha: 0.75),
                                    onSelected: (a) {
                                      unawaited(
                                        widget.onOverflow(
                                          context,
                                          player,
                                          idx >= 0 ? idx : -1,
                                          a,
                                          playbackOriginTab: LibraryTabId.songs,
                                          outsideQueue: idx < 0
                                              ? TrackOverflowQueueContext(
                                                  tracks: mp3QueueTracks,
                                                  index: rowIx,
                                                  playbackOriginTab: LibraryTabId.songs,
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
                      }),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
