import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../audio/player_controller.dart';
import '../../models/library_tab_id.dart';
import '../../models/track_item.dart';
import '../../services/file_path_mtime_sort.dart';
import '../../services/first_run_library_hint_store.dart';
import '../../services/mp3_scanner.dart';
import '../../services/mp3_scanner_types.dart';
import '../../services/playback_session_store.dart';
import '../../services/recently_added_store.dart';
import '../../services/recently_played_store.dart';
import '../../services/saved_music_folders.dart';
import '../../services/song_metadata_cache.dart';
import '../../services/song_metadata_cache_types.dart';
import '../../services/track_metadata.dart';
import '../../theme/accent_color_option.dart';
import '../../theme/app_theme.dart';
import '../library/library_files_page.dart';
import '../library/library_screen.dart';
import '../player/mini_player_bar.dart';
import '../player/now_playing_screen.dart';
import '../player/track_overflow_actions.dart';
import '../settings/settings_screen.dart';

enum _ShellPage { library, settings }

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.themeSetting,
    required this.onThemeSettingChanged,
    required this.accentColorOption,
    required this.customAccentColor,
    required this.onAccentColorOptionChanged,
    required this.onCustomAccentColorChanged,
  });

  final AppThemeSetting themeSetting;
  final ValueChanged<AppThemeSetting> onThemeSettingChanged;
  final AppAccentColorOption accentColorOption;
  final Color customAccentColor;
  final ValueChanged<AppAccentColorOption> onAccentColorOptionChanged;
  final ValueChanged<Color> onCustomAccentColorChanged;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<LibraryScreenState> _libraryScreenKey =
      GlobalKey<LibraryScreenState>();

  /// When non-null from Files browser, Songs tab restricts to paths in this exact set (from scanMp3Files).
  final ValueNotifier<Set<String>?> _songsBrowsePathKeysNotifier =
      ValueNotifier<Set<String>?>(null);
  _ShellPage _page = _ShellPage.library;
  List<String> _folderPaths = [];
  bool _scanning = false;

  /// Set after filesystem scan completes; `null` means still enumerating MP3 paths.
  int? _scanDetectedMp3Count;
  PlayerController? _playerForRecentHistory;
  PlayerController? _playerRef;
  String? _dispatchedRecentPath;
  bool _showingFirstRunHint = false;
  Timer? _idleRescanTimer;
  bool _backgroundSyncInProgress = false;
  bool _backgroundSyncQueued = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_bootstrapShellAsync());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final player = PlayerController.of(context);
    _playerRef = player;
    if (!identical(_playerForRecentHistory, player)) {
      _playerForRecentHistory?.removeListener(_recordRecentlyPlayedTrack);
      _playerForRecentHistory = player;
      player.addListener(_recordRecentlyPlayedTrack);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleIdleRescan();
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _idleRescanTimer?.cancel();
      unawaited(_persistSession());
    }
  }

  Future<void> _bootstrapShellAsync() async {
    final showSettings = await PlaybackSessionStore.loadShellPageIsSettings();
    final browseKeys = await PlaybackSessionStore.loadBrowsePathKeys();
    final paths = await SavedMusicFolders.load();
    if (!mounted) return;
    setState(() {
      _folderPaths = List<String>.from(paths);
      _page = showSettings ? _ShellPage.settings : _ShellPage.library;
      if (browseKeys != null && browseKeys.isNotEmpty) {
        _songsBrowsePathKeysNotifier.value = browseKeys;
      }
    });
    final player = PlayerController.of(context);
    if (browseKeys != null && browseKeys.isNotEmpty) {
      player.setPlaybackPathKeyScope(browseKeys);
    }
    if (paths.isEmpty) {
      unawaited(_maybeShowFirstRunLibraryHint());
      return;
    }
    await _restoreLibraryFromCacheAndSession(player, paths);
    _scheduleBackgroundSync(delay: const Duration(milliseconds: 500));
    _scheduleIdleRescan();
  }

  void _scheduleBackgroundSync({Duration delay = Duration.zero}) {
    final paths = List<String>.from(_folderPaths);
    if (paths.isEmpty) return;
    unawaited(() async {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (!mounted) return;
      final player = PlayerController.of(context);
      await _runBackgroundSyncGuarded(player, paths);
    }());
  }

  void _scheduleIdleRescan() {
    _idleRescanTimer?.cancel();
    if (_folderPaths.isEmpty) return;
    _idleRescanTimer = Timer(const Duration(minutes: 2), () {
      if (!mounted) return;
      _scheduleBackgroundSync();
    });
  }

  Future<void> _runBackgroundSyncGuarded(
    PlayerController player,
    List<String> roots,
  ) async {
    if (_backgroundSyncInProgress) {
      _backgroundSyncQueued = true;
      return;
    }
    _backgroundSyncInProgress = true;
    try {
      await _syncLibraryFromDiskInBackground(player, roots);
    } finally {
      _backgroundSyncInProgress = false;
      if (_backgroundSyncQueued) {
        _backgroundSyncQueued = false;
        _scheduleBackgroundSync();
      }
    }
  }

  Future<void> _maybeShowFirstRunLibraryHint() async {
    if (!mounted || _showingFirstRunHint) return;
    final shouldShow = await FirstRunLibraryHintStore.shouldShowHint();
    if (!mounted || !shouldShow || _folderPaths.isNotEmpty) return;
    _showingFirstRunHint = true;
    try {
      await FirstRunLibraryHintStore.markSeen();
      if (!mounted) return;
      final goToSettings = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          final theme = Theme.of(dialogContext);
          final pal = dialogContext.palette;
          return AlertDialog(
            title: const Text('Add your music folders'),
            content: Text(
              'To build your Music Library, first add one or more folders that contain MP3 files.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: pal.textSecondary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Later'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                icon: const Icon(Icons.settings_rounded),
                label: const Text('Open Settings'),
              ),
            ],
          );
        },
      );
      if (!mounted) return;
      if (goToSettings == true) _goSettings();
    } finally {
      _showingFirstRunHint = false;
    }
  }

  Future<void> _restoreLibraryFromCacheAndSession(
    PlayerController player,
    List<String> roots,
  ) async {
    final cachedByPath = await SongMetadataCache.loadSnapshotsForRoots(roots);
    if (!mounted) return;
    if (cachedByPath.isNotEmpty) {
      final tracks =
          cachedByPath.values.map((s) => s.track).toList(growable: false)
            ..sort((a, b) {
              final am = cachedByPath[a.filePath]?.fileModifiedMs ?? 0;
              final bm = cachedByPath[b.filePath]?.fileModifiedMs ?? 0;
              return bm.compareTo(am);
            });
      player.setLibraryCatalog(tracks);
    }

    final restoreTracks = cachedByPath.values
        .map((s) => s.track)
        .toList(growable: false);
    if (restoreTracks.isNotEmpty) {
      await PlaybackSessionStore.restorePlayer(player, restoreTracks);
    }
  }

  Future<List<ScannedMp3File>> _collectMp3FileStats(List<String> roots) async {
    final seen = <String>{};
    final out = <ScannedMp3File>[];
    for (final root in roots) {
      final files = await scanMp3FilesWithStats(root, recursive: true);
      for (final f in files) {
        if (seen.add(f.path)) out.add(f);
      }
    }
    out.sort((a, b) => b.lastModifiedMs.compareTo(a.lastModifiedMs));
    return out;
  }

  Future<void> _syncLibraryFromDiskInBackground(
    PlayerController player,
    List<String> roots,
  ) async {
    if (kIsWeb) return;
    try {
      final cachedByPath = await SongMetadataCache.loadSnapshotsForRoots(roots);
      final scanned = await _collectMp3FileStats(roots);
      if (!mounted) return;

      final existingPaths = scanned.map((f) => f.path).toSet();
      await SongMetadataCache.deleteMissingPaths(existingPaths);

      final live = <String, TrackItem>{
        for (final e in cachedByPath.entries) e.key: e.value.track,
      };
      final changedPaths = <ScannedMp3File>[];

      for (final f in scanned) {
        final snap = cachedByPath[f.path];
        if (snap == null ||
            snap.fileModifiedMs != f.lastModifiedMs ||
            snap.fileSizeBytes != f.fileSizeBytes) {
          changedPaths.add(f);
        } else {
          live[f.path] = snap.track;
        }
      }

      const batchSize = 4;
      for (var i = 0; i < changedPaths.length; i += batchSize) {
        final batch = changedPaths
            .skip(i)
            .take(batchSize)
            .toList(growable: false);
        final updated = await Future.wait(
          batch.map((f) async {
            final base = live[f.path] ?? TrackItem.fromFilePath(f.path);
            final parsed = await readAudioMetadata(base);
            return CachedTrackSnapshot(
              track: parsed,
              fileModifiedMs: f.lastModifiedMs,
              fileSizeBytes: f.fileSizeBytes,
            );
          }),
        );
        await SongMetadataCache.saveTrackSnapshots(updated);
        for (final s in updated) {
          final p = s.track.filePath;
          if (p != null && p.isNotEmpty) {
            live[p] = s.track;
          }
        }
        if (!mounted) return;
        final partial = scanned
            .map((f) => live[f.path] ?? TrackItem.fromFilePath(f.path))
            .toList(growable: false);
        player.setLibraryCatalog(partial);
      }

      if (!mounted) return;
      final finalTracks = scanned
          .map((f) => live[f.path] ?? TrackItem.fromFilePath(f.path))
          .toList(growable: false);
      player.setLibraryCatalog(finalTracks);

      if (finalTracks.isNotEmpty) {
        await RecentlyAddedStore.mergeScanPaths(
          finalTracks.map((t) => t.filePath).whereType<String>().toList(),
        );
      } else {
        await RecentlyAddedStore.mergeScanPaths(const <String>[]);
      }
    } catch (e, st) {
      debugPrint('_syncLibraryFromDiskInBackground: $e\n$st');
    }
  }

  Future<void> _persistSession() async {
    try {
      final p = _playerRef;
      if (p != null) {
        await PlaybackSessionStore.savePlayer(p);
      }
      await PlaybackSessionStore.saveBrowsePathKeys(
        _songsBrowsePathKeysNotifier.value,
      );
    } catch (e, st) {
      debugPrint('_persistSession: $e\n$st');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idleRescanTimer?.cancel();
    unawaited(_persistSession());
    _playerForRecentHistory?.removeListener(_recordRecentlyPlayedTrack);
    _songsBrowsePathKeysNotifier.dispose();
    super.dispose();
  }

  void _recordRecentlyPlayedTrack() {
    final path = _playerForRecentHistory?.currentTrack?.filePath;
    if (path == null || path.isEmpty) {
      _dispatchedRecentPath = null;
      return;
    }
    if (path == _dispatchedRecentPath) return;
    _dispatchedRecentPath = path;
    unawaited(RecentlyPlayedStore.recordPlay(path));
  }

  /// Merges unique MP3 paths from all roots, then sorts by file last-modified (newest first).
  Future<List<String>> _collectMp3Paths(List<String> roots) async {
    final seen = <String>{};
    final out = <String>[];
    for (final root in roots) {
      final files = await scanMp3Files(root, recursive: true);
      for (final f in files) {
        if (seen.add(f)) out.add(f);
      }
    }
    await sortPathsByModifiedNewestFirst(out);
    return out;
  }

  Future<void> _scanFoldersAndSetPlaylist(
    List<String> paths, {
    required bool playAfter,
    int startIndex = 0,
    bool preservePlaybackAfterRescan = false,
    bool tryPersistedPlayback = false,
    bool keepCurrentQueue = false,
  }) async {
    final player = PlayerController.of(context);
    final pathToPreserve = preservePlaybackAfterRescan
        ? player.currentTrack?.filePath
        : null;
    final wasPlaying = preservePlaybackAfterRescan && player.isPlaying;
    final playbackPosition = preservePlaybackAfterRescan
        ? player.position
        : Duration.zero;

    if (paths.isEmpty) {
      await RecentlyAddedStore.mergeScanPaths([]);
      player.setLibraryCatalog([]);
      await player.setPlaylist(
        [],
        startIndex: 0,
        playbackOriginTab: LibraryTabId.songs,
      );
      return;
    }

    setState(() {
      _scanning = true;
      _scanDetectedMp3Count = null;
    });
    List<String> files;
    try {
      files = await _collectMp3Paths(paths);
      if (!mounted) return;
      if (files.isNotEmpty) {
        setState(() => _scanDetectedMp3Count = files.length);
      }

      await RecentlyAddedStore.mergeScanPaths(files);
      if (!mounted) return;

      if (files.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No .mp3 files found in the saved folders.'),
          ),
        );
        player.setLibraryCatalog([]);
        await player.setPlaylist(
          [],
          startIndex: 0,
          playbackOriginTab: LibraryTabId.songs,
        );
        return;
      }

      final cachedByPath = await SongMetadataCache.loadTracksByPaths(files);
      final tracks = files
          .map((path) => cachedByPath[path] ?? TrackItem.fromFilePath(path))
          .toList(growable: false);
      unawaited(SongMetadataCache.deleteMissingPaths(files.toSet()));
      unawaited(SongMetadataCache.saveTracks(tracks));
      player.setLibraryCatalog(tracks);

      if (preservePlaybackAfterRescan) {
        if (keepCurrentQueue &&
            player.currentTrack != null &&
            player.playlist.isNotEmpty) {
          if (!kIsWeb && mounted) {
            enrichPlaylistTracks(
              tracks: tracks,
              onTrackUpdated: (path, updated) {
                player.updateTrackByPath(path, updated);
                unawaited(SongMetadataCache.saveTracks([updated]));
              },
            ).catchError((Object e, StackTrace st) {
              debugPrint('enrichPlaylistTracks: $e\n$st');
            });
          }
          return;
        }
        var resolvedStart = startIndex.clamp(0, tracks.length - 1);
        if (pathToPreserve != null) {
          final idx = tracks.indexWhere((t) => t.filePath == pathToPreserve);
          if (idx >= 0) resolvedStart = idx;
        }
        await player.setPlaylist(
          tracks,
          startIndex: resolvedStart,
          playbackOriginTab: LibraryTabId.songs,
        );
        if (pathToPreserve != null && tracks.isNotEmpty) {
          final atPath =
              tracks[resolvedStart.clamp(0, tracks.length - 1)].filePath;
          if (atPath == pathToPreserve && playbackPosition > Duration.zero) {
            await player.seek(playbackPosition);
          }
        }
        if (playAfter) {
          await player.play();
        } else {
          if (wasPlaying) {
            await player.play();
          } else {
            await player.pause();
          }
        }
        if (!kIsWeb && mounted) {
          enrichPlaylistTracks(
            tracks: tracks,
            onTrackUpdated: (path, updated) {
              player.updateTrackByPath(path, updated);
              unawaited(SongMetadataCache.saveTracks([updated]));
            },
          ).catchError((Object e, StackTrace st) {
            debugPrint('enrichPlaylistTracks: $e\n$st');
          });
        }
        return;
      }

      if (tryPersistedPlayback) {
        final restored = await PlaybackSessionStore.restorePlayer(
          player,
          tracks,
        );
        if (!mounted) return;
        if (restored) {
          if (playAfter) await player.play();
          if (!kIsWeb && mounted) {
            enrichPlaylistTracks(
              tracks: tracks,
              onTrackUpdated: (path, updated) {
                player.updateTrackByPath(path, updated);
                unawaited(SongMetadataCache.saveTracks([updated]));
              },
            ).catchError((Object e, StackTrace st) {
              debugPrint('enrichPlaylistTracks: $e\n$st');
            });
          }
          return;
        }
      }

      var resolvedStart = startIndex.clamp(0, tracks.length - 1);
      await player.setPlaylist(
        tracks,
        startIndex: resolvedStart,
        playbackOriginTab: LibraryTabId.songs,
      );

      if (playAfter) {
        await player.play();
      }

      if (!kIsWeb && mounted) {
        enrichPlaylistTracks(
          tracks: tracks,
          onTrackUpdated: (path, updated) {
            player.updateTrackByPath(path, updated);
            unawaited(SongMetadataCache.saveTracks([updated]));
          },
        ).catchError((Object e, StackTrace st) {
          debugPrint('enrichPlaylistTracks: $e\n$st');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _scanning = false;
          _scanDetectedMp3Count = null;
        });
      }
    }
  }

  Future<void> _onFoldersChanged(List<String> paths) async {
    await SavedMusicFolders.save(paths);
    if (!mounted) return;
    setState(() => _folderPaths = List<String>.from(paths));
    await _scanFoldersAndSetPlaylist(
      paths,
      playAfter: false,
      preservePlaybackAfterRescan: true,
      keepCurrentQueue: true,
    );
    _scheduleIdleRescan();
  }

  Future<void> _refreshLibraryScan() async {
    if (_folderPaths.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add music folders in Settings first.')),
      );
      return;
    }
    await _scanFoldersAndSetPlaylist(
      _folderPaths,
      playAfter: false,
      preservePlaybackAfterRescan: true,
    );
  }

  void _openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  void _goLibrary() {
    setState(() => _page = _ShellPage.library);
    unawaited(PlaybackSessionStore.saveShellPageIsSettings(false));
  }

  void _goSettings() {
    setState(() => _page = _ShellPage.settings);
    unawaited(PlaybackSessionStore.saveShellPageIsSettings(true));
  }

  void _openNowPlaying() {
    final player = PlayerController.of(context);
    if (player.currentTrack == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing is playing right now.')),
      );
      return;
    }
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: NowPlayingScreen(
              onCollapse: () {
                Navigator.of(context).pop();
                final tabId = player.playbackOriginTab ?? LibraryTabId.songs;
                final userPlaylistId = player.playbackOriginUserPlaylistId;
                _goLibrary();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  WidgetsBinding.instance.addPostFrameCallback((_) async {
                    if (!mounted) return;
                    final st = _libraryScreenKey.currentState;
                    if (st == null) return;
                    await st.switchToTabAndScrollToCurrentTrack(tabId);
                    if (!mounted) return;
                    if (tabId == LibraryTabId.playlist &&
                        userPlaylistId != null) {
                      await st.openUserPlaylistSheetById(userPlaylistId);
                    }
                  });
                });
              },
            ),
          );
        },
      ),
    );
  }

  void _onDrawerNowPlaying() {
    Navigator.pop(context);
    _openNowPlaying();
  }

  Future<void> _onLibraryTrackOverflow(
    BuildContext context,
    PlayerController player,
    int playlistIndex,
    TrackOverflowAction action, {
    LibraryTabId? playbackOriginTab,
    TrackOverflowQueueContext? outsideQueue,
  }) => applyTrackOverflowAction(
    context,
    player,
    playlistIndex,
    action,
    playbackOriginTab: playbackOriginTab,
    outsideQueue: outsideQueue,
  );

  Future<void> _openFilesExplorerScreen() async {
    if (_folderPaths.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add music folders in Settings first.')),
      );
      return;
    }
    final pickedKeys = await Navigator.of(context).push<Set<String>?>(
      MaterialPageRoute(
        builder: (ctx) => LibraryFilesPage(
          musicRoots: _folderPaths,
          onOverflow: _onLibraryTrackOverflow,
        ),
      ),
    );
    if (!mounted) return;
    if (pickedKeys != null) {
      final keys = Set<String>.from(pickedKeys);
      _songsBrowsePathKeysNotifier.value = keys;
      PlayerController.of(context).setPlaybackPathKeyScope(keys);
      unawaited(PlaybackSessionStore.saveBrowsePathKeys(keys));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _libraryScreenKey.currentState?.switchToSongsTab();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final player = PlayerController.of(context);

    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final current = player.currentTrack;

        final pal = context.palette;

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: pal.scaffoldBackground,
          drawer: Drawer(
            backgroundColor: pal.surface,
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: Text(
                      'MP3 Player',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: context.controlAccent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.library_music_rounded),
                    title: const Text('Library'),
                    selected: _page == _ShellPage.library,
                    onTap: () {
                      Navigator.pop(context);
                      _goLibrary();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.folder_rounded),
                    title: const Text('Files'),
                    onTap: () {
                      Navigator.pop(context);
                      _goLibrary();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        unawaited(_openFilesExplorerScreen());
                      });
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.play_circle_rounded),
                    title: const Text('Now playing'),
                    enabled: current != null,
                    onTap: current == null ? null : _onDrawerNowPlaying,
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings_rounded),
                    title: const Text('Settings'),
                    selected: _page == _ShellPage.settings,
                    onTap: () {
                      Navigator.pop(context);
                      _goSettings();
                    },
                  ),
                ],
              ),
            ),
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: _page == _ShellPage.library
                        ? LibraryScreen(
                            key: _libraryScreenKey,
                            folderPaths: _folderPaths,
                            songsBrowsePathKeys: _songsBrowsePathKeysNotifier,
                            onClearSongsBrowseFilter: () {
                              _songsBrowsePathKeysNotifier.value = null;
                              PlayerController.of(
                                context,
                              ).setPlaybackPathKeyScope(null);
                              unawaited(
                                PlaybackSessionStore.saveBrowsePathKeys(null),
                              );
                            },
                            onOpenDrawer: _openDrawer,
                            onRefreshLibrary: _folderPaths.isEmpty || _scanning
                                ? null
                                : () {
                                    unawaited(_refreshLibraryScan());
                                  },
                          )
                        : SettingsScreen(
                            folderPaths: _folderPaths,
                            onFoldersChanged: _onFoldersChanged,
                            onOpenDrawer: _openDrawer,
                            themeSetting: widget.themeSetting,
                            onThemeSettingChanged: widget.onThemeSettingChanged,
                            accentColorOption: widget.accentColorOption,
                            customAccentColor: widget.customAccentColor,
                            onAccentColorOptionChanged:
                                widget.onAccentColorOptionChanged,
                            onCustomAccentColorChanged:
                                widget.onCustomAccentColorChanged,
                          ),
                  ),
                  if (current != null)
                    MiniPlayerBar(controller: player, onTap: _openNowPlaying),
                ],
              ),
              if (_scanning)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: const BoxDecoration(color: Color(0x59000000)),
                    child: Center(
                      child: Material(
                        color: pal.surface,
                        elevation: 6,
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 320),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.library_music_rounded,
                                  size: 40,
                                  color: context.controlAccent,
                                ),
                                const SizedBox(height: 18),
                                SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    color: context.controlAccent,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  _scanDetectedMp3Count == null
                                      ? 'Searching for songs…'
                                      : 'Found $_scanDetectedMp3Count ${_scanDetectedMp3Count == 1 ? 'song' : 'songs'}',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: pal.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _scanDetectedMp3Count == null
                                      ? 'Scanning your music folders for MP3 files. Large libraries can take a moment.'
                                      : 'Loading tags and preparing your library…',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: pal.textSecondary,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
