import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p_path;

import '../../audio/player_controller.dart';
import '../../models/library_tab_id.dart';
import '../../models/youtube_page_id.dart';
import '../../models/track_item.dart';
import '../../services/album_art_cache.dart';
import '../../services/app_data_reset.dart';
import '../../services/folder_count_cache.dart';
import '../../services/first_run_library_hint_store.dart';
import '../../services/mp3_scanner.dart';
import '../../services/storage_access.dart';
import '../../services/mp3_scanner_types.dart';
import '../../services/music_library_path_key.dart';
import '../../services/playback_session_store.dart';
import '../../services/recently_added_store.dart';
import '../../services/recently_played_store.dart';
import '../../services/saved_music_folders.dart';
import '../../services/song_metadata_cache.dart';
import '../../services/song_metadata_cache_types.dart';
import '../../services/track_metadata.dart';
import '../../theme/accent_color_option.dart';
import '../../theme/app_font_option.dart';
import '../../theme/app_theme.dart';
import '../../theme/player_chrome_background.dart';
import '../../widgets/action_pill_toast.dart';
import '../../widgets/daisy_background.dart';
import '../library/library_files_page.dart';
import '../library/library_screen.dart';
import '../player/mini_player_bar.dart';
import '../player/now_playing_screen.dart';
import '../player/track_overflow_actions.dart';
import '../help/help_screen.dart';
import '../settings/settings_screen.dart';
import '../youtube/ui/youtube_hub_screen.dart';
import '../youtube/catalog/youtube_catalog_merge.dart';
import '../youtube/catalog/youtube_library_catalog.dart';
import '../youtube/download/youtube_download_manager.dart';
import 'now_playing_escape_bridge.dart';

/// During folder scan, skip building a huge native playback queue until the user
/// actually plays something (avoids hanging on "Loading tags…" for large libraries).
const int _largeLibraryDeferPlayerQueueThreshold = 200;

/// After [appNavigatorKey] pops to the root route, applies Library › Songs (drawer, shell page, tab).
class EscapeToSongsLibraryHub {
  EscapeToSongsLibraryHub._();

  static void Function()? _complete;

  static void register(void Function() complete) => _complete = complete;

  static void unregister() => _complete = null;

  static void completeNavigationToSongs() => _complete?.call();
}

/// ESC: close pushed routes (Files, Now Playing, dialogs), then Library › Songs.
void dispatchEscapeToSongsLibrary() {
  final nav = appNavigatorKey.currentState;
  if (nav != null && nav.canPop()) {
    // When Now Playing is open, pop once — popUntil can over-pop on some stacks.
    if (NowPlayingRouteMark.isOpen) {
      nav.pop();
    } else {
      nav.popUntil((route) => route.isFirst);
    }
  }
  EscapeToSongsLibraryHub.completeNavigationToSongs();
}

enum _ShellPage { library, youtube, settings }

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.themeSetting,
    required this.onThemeSettingChanged,
    required this.fontOption,
    required this.onFontOptionChanged,
    required this.accentColorOption,
    required this.customAccentColor,
    required this.onAccentColorOptionChanged,
    required this.onCustomAccentColorChanged,
    required this.playerChromeBackgroundKind,
    required this.playerChromeCustomBackground,
    required this.onPlayerChromeBackgroundKindChanged,
    required this.onPlayerChromeCustomBackgroundChanged,
  });

  final AppThemeSetting themeSetting;
  final ValueChanged<AppThemeSetting> onThemeSettingChanged;
  final AppFontOption fontOption;
  final ValueChanged<AppFontOption> onFontOptionChanged;
  final AppAccentColorOption accentColorOption;
  final Color customAccentColor;
  final ValueChanged<AppAccentColorOption> onAccentColorOptionChanged;
  final ValueChanged<Color> onCustomAccentColorChanged;
  final PlayerChromeBackgroundKind playerChromeBackgroundKind;
  final Color? playerChromeCustomBackground;
  final ValueChanged<PlayerChromeBackgroundKind>
  onPlayerChromeBackgroundKindChanged;
  final ValueChanged<Color> onPlayerChromeCustomBackgroundChanged;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<LibraryScreenState> _libraryScreenKey =
      GlobalKey<LibraryScreenState>();
  final GlobalKey<YoutubeHubScreenState> _youtubeHubKey =
      GlobalKey<YoutubeHubScreenState>();

  /// When non-null from Files browser, Songs tab restricts to paths in this exact set (from scanMp3Files).
  final ValueNotifier<Set<String>?> _songsBrowsePathKeysNotifier =
      ValueNotifier<Set<String>?>(null);
  _ShellPage _page = _ShellPage.library;
  List<String> _folderPaths = [];
  bool _scanning = false;
  Timer? _scanningWatchdog;

  /// Set after filesystem scan completes; `null` means still enumerating MP3 paths.
  int? _scanDetectedMp3Count;
  PlayerController? _playerForRecentHistory;
  PlayerController? _playerForPlaybackPersistence;
  PlayerController? _playerRef;
  String? _dispatchedRecentPath;
  bool _showingFirstRunHint = false;
  Timer? _idleRescanTimer;
  Timer? _persistPlaybackDebounceTimer;
  bool _backgroundSyncInProgress = false;
  bool _backgroundSyncQueued = false;
  bool _albumArtWarmupInProgress = false;
  bool _albumArtWarmupQueued = false;
  Timer? _albumArtWarmupRetryTimer;
  bool _refreshInProgress = false;

  /// Whether the user has granted audio/storage read permission (Android).
  /// `null` = not yet checked; `true` = granted; `false` = denied.
  bool? _storagePermissionGranted;

  /// Library tab that was visible when Now Playing was opened (for Windows Escape).
  LibraryTabId? _nowPlayingOpenedFromTab;
  VoidCallback? _youtubeDownloadCompletedListener;

  @override
  void initState() {
    super.initState();
    EscapeToSongsLibraryHub.register(_onEscapeToSongsLibrary);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      NowPlayingWindowsEsc.handler = _windowsEscapeCloseNowPlaying;
    }
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
      _playerForRecentHistory?.track.removeListener(_recordRecentlyPlayedTrack);
      _playerForRecentHistory = player;
      player.track.addListener(_recordRecentlyPlayedTrack);
    }
    if (!identical(_playerForPlaybackPersistence, player)) {
      _playerForPlaybackPersistence?.track.removeListener(
        _schedulePlaybackSessionPersist,
      );
      _playerForPlaybackPersistence?.playback.removeListener(
        _schedulePlaybackSessionPersist,
      );
      _playerForPlaybackPersistence = player;
      player.track.addListener(_schedulePlaybackSessionPersist);
      player.playback.addListener(_schedulePlaybackSessionPersist);
    }
    _wireYoutubeShellHooks(player);
  }

  Future<void> _setPlayerLibraryCatalog(
    PlayerController player,
    List<TrackItem> tracks, {
    CatalogNotifyMode notify = CatalogNotifyMode.immediate,
  }) async {
    final merged = await applyYoutubeCatalogMerge(tracks);
    player.setLibraryCatalog(merged, notify: notify);
  }

  Future<void> _applyYoutubeMergeSetting(PlayerController player) async {
    await _setPlayerLibraryCatalog(
      player,
      stripYoutubeTracksFromCatalog(player.metadataLibrary),
    );
  }

  void _wireYoutubeShellHooks(PlayerController player) {
    if (kIsWeb || _youtubeDownloadCompletedListener != null) return;

    _youtubeDownloadCompletedListener = () {
      final job = YoutubeDownloadManager.instance.lastCompletedJob.value;
      if (job == null || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloaded "${job.title}"')),
      );
      unawaited(_applyYoutubeMergeSetting(player));
    };
    YoutubeDownloadManager.instance.lastCompletedJob.addListener(
      _youtubeDownloadCompletedListener!,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleIdleRescan();
      // Re-check permission when resuming; the user may have just granted it
      // from the system Settings app.  If it was previously denied and is now
      // granted, trigger an immediate rescan so the library populates.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        unawaited(_recheckPermissionOnResume());
        final player = _playerRef;
        if (player != null) {
          unawaited(player.syncPlaybackEnhancements());
        }
      }
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _idleRescanTimer?.cancel();
      _persistPlaybackDebounceTimer?.cancel();
      unawaited(_persistSession());
    }
  }

  Future<void> _recheckPermissionOnResume() async {
    final wasGranted = _storagePermissionGranted;
    // Only check status — don't show a dialog here; the user is returning from
    // somewhere else and we don't want to interrupt their flow.
    final nowGranted = await ensureCanReadMusicFiles(
      context,
      showDialogIfDenied: false,
    );
    if (!mounted) return;
    _storagePermissionGranted = nowGranted;
    // If permission was just granted, kick off a background sync immediately.
    if (wasGranted != true && nowGranted && _folderPaths.isNotEmpty) {
      _scheduleBackgroundSync();
    }
  }

  void _schedulePlaybackSessionPersist() {
    _persistPlaybackDebounceTimer?.cancel();
    _persistPlaybackDebounceTimer = Timer(
      const Duration(milliseconds: 700),
      () {
        final p = _playerRef;
        if (p == null) return;
        unawaited(PlaybackSessionStore.savePlayer(p));
      },
    );
  }

  Future<void> _bootstrapShellAsync() async {
    // Request audio/storage permission before doing any file I/O on Android.
    final permGranted = await ensureCanReadMusicFiles(context);
    if (!mounted) return;
    _storagePermissionGranted = permGranted;

    final showSettings = await PlaybackSessionStore.loadShellPageIsSettings();
    final browseKeys = await PlaybackSessionStore.loadBrowsePathKeys();
    var paths = await SavedMusicFolders.load();
    if (!mounted) return;

    // Prune saved folder paths whose directory no longer exists on disk so that
    // stale cached tracks from deleted folders are never loaded or played.
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows)) {
      final live = <String>[];
      for (final p in paths) {
        try {
          if (await Directory(p).exists()) live.add(p);
        } catch (_) {
          live.add(p); // keep on error — don't silently remove
        }
      }
      if (live.length != paths.length) {
        paths = live;
        await SavedMusicFolders.save(paths);
      }
    }
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
      unawaited(_setPlayerLibraryCatalog(player, tracks));
      unawaited(
        player.prefillArtAvailabilityFromDiskCache(
          tracks.map((t) => t.filePath).whereType<String>(),
        ),
      );
    }

    final restoreTracks = cachedByPath.values
        .map((s) => s.track)
        .toList(growable: false);
    if (restoreTracks.isNotEmpty) {
      await PlaybackSessionStore.restorePlayer(
        player,
        restoreTracks,
        resumePlaying: false,
      );
    }
    _scheduleAlbumArtWarmup(player);
  }

  Future<void> _syncLibraryFromDiskInBackground(
    PlayerController player,
    List<String> roots,
  ) async {
    if (kIsWeb) return;
    try {
      final cachedByPath = await SongMetadataCache.loadSnapshotsForRoots(roots);
      final scanned = await collectMp3FilesMerged(roots);
      if (!mounted) return;

      final existingPaths = scanned.map((f) => f.path).toSet();
      await SongMetadataCache.deleteMissingPaths(existingPaths);

      // Seed `live` from the DB snapshot.  Then overlay the in-memory library:
      // any track whose path the player already knows about (e.g. just edited)
      // is preferred over the DB row so a concurrent sync never reverts a
      // freshly-saved tag edit back to stale data.
      final live = <String, TrackItem>{
        for (final e in cachedByPath.entries) e.key: e.value.track,
      };
      for (final t in player.metadataLibrary) {
        final fp = t.filePath;
        if (fp != null && fp.isNotEmpty) live[fp] = t;
      }
      final changedPaths = <ScannedMp3File>[];

      final repairSnapshots = <CachedTrackSnapshot>[];

      for (final f in scanned) {
        final snap = cachedByPath[f.path];
        if (snap == null) {
          changedPaths.add(f);
        } else if (snap.fileModifiedMs != f.lastModifiedMs) {
          changedPaths.add(f);
        } else if (snap.fileSizeBytes == 0) {
          // Legacy rows from [saveTracks] before fingerprint preservation; repair
          // without re-parsing tags when mtime still matches.
          live[f.path] = snap.track;
          repairSnapshots.add(
            CachedTrackSnapshot(
              track: snap.track,
              fileModifiedMs: f.lastModifiedMs,
              fileSizeBytes: f.fileSizeBytes,
            ),
          );
        } else if (snap.fileSizeBytes != f.fileSizeBytes) {
          changedPaths.add(f);
        } else {
          live[f.path] ??= snap.track;
        }
      }

      if (repairSnapshots.isNotEmpty) {
        await SongMetadataCache.saveTrackSnapshots(repairSnapshots);
      }

      const batchSize = 6;
      for (var i = 0; i < changedPaths.length; i += batchSize) {
        final batch = changedPaths
            .skip(i)
            .take(batchSize)
            .toList(growable: false);
        final updated = await Future.wait(
          batch.map((f) async {
            final base = live[f.path] ?? TrackItem.fromFilePath(f.path);
            TrackItem parsed;
            try {
              parsed = await readAudioMetadata(base);
            } catch (e, st) {
              // Keep library count/path parity with disk even when a file has bad tags.
              debugPrint('readAudioMetadata fallback for ${f.path}: $e\n$st');
              parsed = base;
            }
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
        unawaited(
          _setPlayerLibraryCatalog(
            player,
            partial,
            notify: CatalogNotifyMode.throttled,
          ),
        );
      }

      if (!mounted) return;
      final finalTracks = scanned
          .map((f) => live[f.path] ?? TrackItem.fromFilePath(f.path))
          .toList(growable: false);
      unawaited(_setPlayerLibraryCatalog(player, finalTracks));
      FolderCountCache.instance.clear();
      unawaited(
        player.prefillArtAvailabilityFromDiskCache(
          finalTracks.map((t) => t.filePath).whereType<String>(),
        ),
      );
      _scheduleAlbumArtWarmup(player);

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

  void _scheduleAlbumArtWarmup(PlayerController player) {
    if (kIsWeb) return;
    if (_albumArtWarmupInProgress) {
      _albumArtWarmupQueued = true;
      return;
    }
    _albumArtWarmupInProgress = true;
    unawaited(() async {
      try {
        final candidates = player.metadataLibrary
            .where((t) {
              final p = t.filePath;
              final art = t.albumArtBytes;
              return p != null && p.isNotEmpty && (art == null || art.isEmpty);
            })
            .toList(growable: false);
        if (candidates.isEmpty) return;

        var warmed = 0;
        for (final t in candidates) {
          if (!mounted) return;
          final path = t.filePath!.trim();
          final pathKey = canonicalMusicLibraryPathKey(path);
          if (pathKey.isEmpty) continue;

          if (player.artAvailability.hasArt(pathKey)) continue;
          if (await SongMetadataCache.hasValidArtDiskCacheForPath(path)) {
            player.markAlbumArtAvailable(path);
            continue;
          }
          if (await hasAlbumArtDiskCacheAnyDimension(path)) {
            await SongMetadataCache.markArtDiskCachedForPath(path);
            player.markAlbumArtAvailable(path);
            continue;
          }

          final art = await readCoverBytesOnly(path);
          if (art != null && art.isNotEmpty) {
            await primeAlbumArtDiskCache(path, art);
            await SongMetadataCache.markArtDiskCachedForPath(path);
            player.markAlbumArtAvailable(path);
          }

          warmed++;
          final playing = player.isPlaying;
          if (playing) {
            await Future<void>.delayed(const Duration(milliseconds: 300));
          } else if (warmed % 5 == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        }
      } catch (e, st) {
        debugPrint('_scheduleAlbumArtWarmup: $e\n$st');
      } finally {
        _albumArtWarmupInProgress = false;
        if (_albumArtWarmupQueued) {
          _albumArtWarmupQueued = false;
          _scheduleAlbumArtWarmup(player);
        }
      }
    }());
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

  Future<void> _quitApp() async {
    _scaffoldKey.currentState?.closeDrawer();
    _persistPlaybackDebounceTimer?.cancel();
    final player = _playerRef;
    if (player != null) {
      try {
        await player.pause();
      } catch (e, st) {
        debugPrint('_quitApp pause: $e\n$st');
      }
    }
    await _persistSession();
    if (kIsWeb) {
      SystemNavigator.pop();
      return;
    }
    exit(0);
  }

  @override
  void dispose() {
    EscapeToSongsLibraryHub.unregister();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      NowPlayingWindowsEsc.handler = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _idleRescanTimer?.cancel();
    _scanningWatchdog?.cancel();
    _persistPlaybackDebounceTimer?.cancel();
    _albumArtWarmupRetryTimer?.cancel();
    unawaited(_persistSession());
    _playerForRecentHistory?.track.removeListener(_recordRecentlyPlayedTrack);
    _playerForPlaybackPersistence?.track.removeListener(
      _schedulePlaybackSessionPersist,
    );
    _playerForPlaybackPersistence?.playback.removeListener(
      _schedulePlaybackSessionPersist,
    );
    _songsBrowsePathKeysNotifier.dispose();
    if (_youtubeDownloadCompletedListener != null) {
      YoutubeDownloadManager.instance.lastCompletedJob.removeListener(
        _youtubeDownloadCompletedListener!,
      );
    }
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

  Future<void> _scanFoldersAndSetPlaylist(
    List<String> paths, {
    required bool playAfter,
    int startIndex = 0,
    bool preservePlaybackAfterRescan = false,
    bool tryPersistedPlayback = false,
    bool keepCurrentQueue = false,
    bool showProgressOverlay = true,
    bool backgroundSyncPending = false,
  }) async {
    final player = PlayerController.of(context);
    final pathToPreserve = preservePlaybackAfterRescan
        ? player.currentTrack?.filePath
        : null;
    // Capture before any await — reload paths can make [isPlaying] flicker false.
    final wasPlaying =
        preservePlaybackAfterRescan &&
        (player.isPlaying || player.audioPlayer.playing);
    final playbackPosition = preservePlaybackAfterRescan
        ? player.position
        : Duration.zero;

    if (paths.isEmpty) {
      await RecentlyAddedStore.mergeScanPaths([]);
      unawaited(_setPlayerLibraryCatalog(player, []));
      await player.setPlaylist(
        [],
        startIndex: 0,
        playbackOriginTab: LibraryTabId.songs,
      );
      return;
    }

    if (showProgressOverlay) {
      _scanningWatchdog?.cancel();
      _scanningWatchdog = Timer(const Duration(minutes: 3), () {
        if (!mounted || !_scanning) return;
        debugPrint('Library scan overlay watchdog: clearing stuck scan UI');
        setState(() {
          _scanning = false;
          _scanDetectedMp3Count = null;
        });
      });
      setState(() {
        _scanning = true;
        _scanDetectedMp3Count = null;
      });
    }
    List<String> files;
    try {
      final scanned = await collectMp3FilesMerged(paths);
      files = scanned.map((f) => f.path).toList(growable: false);
      if (!mounted) return;
      if (showProgressOverlay && files.isNotEmpty) {
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
        unawaited(_setPlayerLibraryCatalog(player, []));
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
      final scannedByPath = {for (final f in scanned) f.path: f};
      final snapshotsByPath = await SongMetadataCache.loadSnapshotsForRoots(
        paths,
      );
      unawaited(SongMetadataCache.deleteMissingPaths(files.toSet()));
      unawaited(SongMetadataCache.saveTracks(tracks));
      unawaited(_setPlayerLibraryCatalog(player, tracks));
      FolderCountCache.instance.clear();
      unawaited(
        player.prefillArtAvailabilityFromDiskCache(
          tracks.map((t) => t.filePath).whereType<String>(),
        ),
      );
      _scheduleAlbumArtWarmup(player);

      void startForegroundEnrich() {
        if (kIsWeb || !mounted) return;
        enrichPlaylistTracks(
          tracks: tracks,
          onTrackUpdated: (path, updated) {
            player.updateTrackByPath(
              path,
              updated,
              notify: CatalogNotifyMode.throttled,
              refreshNotificationArt: false,
            );
            unawaited(SongMetadataCache.saveTracks([updated]));
          },
          scannedByPath: scannedByPath,
          snapshotsByPath: snapshotsByPath,
          backgroundSyncPending: backgroundSyncPending,
          isPlaying: player.isPlaying || player.audioPlayer.playing,
          libraryLength: tracks.length,
        ).catchError((Object e, StackTrace st) {
          debugPrint('enrichPlaylistTracks: $e\n$st');
        });
      }

      if (preservePlaybackAfterRescan) {
        if (keepCurrentQueue && player.playlist.isNotEmpty) {
          final keptPlayback = player.refreshLibraryDuringPlayback(tracks);
          if (keptPlayback) {
            startForegroundEnrich();
            return;
          }
          await player.tryResyncQueueWithLibraryScan(
            tracks,
            resumePosition: playbackPosition,
            resumePlaying: wasPlaying,
          );
          startForegroundEnrich();
          return;
        }
        var resolvedStart = startIndex.clamp(0, tracks.length - 1);
        if (pathToPreserve != null && pathToPreserve.trim().isNotEmpty) {
          final key = player.libraryPathKeyForScanMatch(pathToPreserve);
          if (key.isNotEmpty) {
            final idx = tracks.indexWhere(
              (t) =>
                  player.libraryPathKeyForScanMatch(
                    (t.filePath ?? '').trim(),
                  ) ==
                  key,
            );
            if (idx >= 0) resolvedStart = idx;
          }
        }
        final deferHeavyPlayerQueue =
            tracks.length >= _largeLibraryDeferPlayerQueueThreshold &&
            !playAfter &&
            !wasPlaying;
        if (deferHeavyPlayerQueue && player.playlist.isEmpty) {
          startForegroundEnrich();
          return;
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
        startForegroundEnrich();
        return;
      }

      if (tryPersistedPlayback) {
        final restored = await PlaybackSessionStore.restorePlayer(
          player,
          tracks,
          resumePlaying: playAfter,
        );
        if (!mounted) return;
        if (restored) {
          if (playAfter) await player.play();
          startForegroundEnrich();
          return;
        }
      }

      var resolvedStart = startIndex.clamp(0, tracks.length - 1);
      final deferHeavyPlayerQueue =
          tracks.length >= _largeLibraryDeferPlayerQueueThreshold &&
          !playAfter &&
          !wasPlaying;
      if (deferHeavyPlayerQueue && player.playlist.isEmpty) {
        startForegroundEnrich();
        return;
      }
      await player.setPlaylist(
        tracks,
        startIndex: resolvedStart,
        playbackOriginTab: LibraryTabId.songs,
      );

      if (playAfter) {
        await player.play();
      }

      startForegroundEnrich();
    } finally {
      if (showProgressOverlay) {
        _scanningWatchdog?.cancel();
        _scanningWatchdog = null;
        if (mounted) {
          setState(() {
            _scanning = false;
            _scanDetectedMp3Count = null;
          });
        }
      }
    }
  }

  Future<void> _onFoldersChanged(List<String> paths) async {
    FolderCountCache.instance.clear();
    await SavedMusicFolders.save(paths);
    if (!mounted) return;
    setState(() => _folderPaths = List<String>.from(paths));
    await _scanFoldersAndSetPlaylist(
      paths,
      playAfter: false,
      preservePlaybackAfterRescan: true,
      keepCurrentQueue: true,
      backgroundSyncPending: true,
    );
    if (!mounted) return;
    ActionPillToast.showUsingRootNavigator(
      'Library updated',
      icon: Icons.done_all_rounded,
      uppercaseLabel: true,
    );
    _scheduleBackgroundSync(delay: Duration.zero);
    _scheduleIdleRescan();
  }

  Future<void> _eraseAllAppData() async {
    final player = _playerRef ?? PlayerController.of(context);
    await player.prepareForAppDataWipe();
    await PlayerController.shutdownNativePlayer();
    await wipeAllLocalAppData();
    if (!mounted) return;
    setState(() {
      _folderPaths = [];
      _songsBrowsePathKeysNotifier.value = null;
    });
    FolderCountCache.instance.clear();
    SystemNavigator.pop();
  }

  Future<void> _refreshLibraryScan() async {
    if (_refreshInProgress) return;
    if (_folderPaths.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add music folders in Settings first.')),
      );
      return;
    }
    setState(() => _refreshInProgress = true);
    FolderCountCache.instance.clear();
    try {
      final player = PlayerController.of(context);
      final browseKeys = _songsBrowsePathKeysNotifier.value;
      final hasBrowse = !kIsWeb && browseKeys != null && browseKeys.isNotEmpty;

      if (hasBrowse) {
        final subtree = _inferBrowseSubtreeRoot(
          browseKeys,
          player.metadataLibrary,
        );
        if (subtree != null && subtree.trim().isNotEmpty) {
          await _mergeRescanBrowseSubtree(player, subtree);
        } else {
          await _scanFoldersAndSetPlaylist(
            _folderPaths,
            playAfter: false,
            preservePlaybackAfterRescan: true,
            keepCurrentQueue: true,
            showProgressOverlay: false,
            backgroundSyncPending: true,
          );
        }
      } else {
        _songsBrowsePathKeysNotifier.value = null;
        player.setPlaybackPathKeyScope(null, reloadQueue: false);
        unawaited(PlaybackSessionStore.saveBrowsePathKeys(null));
        await _scanFoldersAndSetPlaylist(
          _folderPaths,
          playAfter: false,
          preservePlaybackAfterRescan: true,
          keepCurrentQueue: true,
          showProgressOverlay: false,
          backgroundSyncPending: true,
        );
      }
      if (!mounted) return;
      await _runBackgroundSyncGuarded(player, List<String>.from(_folderPaths));
      if (!mounted) return;
      ActionPillToast.showUsingRootNavigator(
        'Refresh completed',
        icon: Icons.done_all_rounded,
        uppercaseLabel: true,
      );
    } finally {
      if (mounted) {
        setState(() => _refreshInProgress = false);
      }
    }
  }

  bool _pathWithinSubtree(String filePath, String normalizedSubtreeRoot) {
    if (kIsWeb) return false;
    final raw = filePath.trim();
    if (raw.isEmpty) return false;
    final fp = p_path.normalize(File(raw).absolute.path);
    final root = normalizedSubtreeRoot;
    if (fp == root) return true;
    final sep = p_path.separator;
    final prefix = root.endsWith(sep) ? root : '$root$sep';
    if (Platform.isWindows) {
      return fp.toLowerCase().startsWith(prefix.toLowerCase());
    }
    return fp.startsWith(prefix);
  }

  String? _longestCommonDirectoryForFiles(List<String> filePaths) {
    if (filePaths.isEmpty) return null;
    if (filePaths.length == 1) {
      return p_path.dirname(
        p_path.normalize(File(filePaths.first.trim()).absolute.path),
      );
    }
    final splitSegs = filePaths
        .map(
          (e) => p_path.split(p_path.normalize(File(e.trim()).absolute.path)),
        )
        .toList(growable: false);
    final minSegCount = splitSegs.map((s) => s.length).reduce(math.min);
    final common = <String>[];
    for (var i = 0; i < minSegCount - 1; i++) {
      final seg = splitSegs.first[i];
      var allMatch = true;
      for (final segs in splitSegs.skip(1)) {
        final other = segs[i];
        if (Platform.isWindows) {
          if (seg.toLowerCase() != other.toLowerCase()) {
            allMatch = false;
            break;
          }
        } else if (seg != other) {
          allMatch = false;
          break;
        }
      }
      if (!allMatch) break;
      common.add(seg);
    }
    if (common.isEmpty) return null;
    return p_path.joinAll(common);
  }

  String? _inferBrowseSubtreeRoot(
    Set<String> browseKeys,
    List<TrackItem> tracks,
  ) {
    final paths = <String>[];
    for (final t in tracks) {
      final fp = t.filePath?.trim();
      if (fp == null || fp.isEmpty) continue;
      if (!browseKeys.contains(canonicalMusicLibraryPathKey(fp))) continue;
      paths.add(fp);
    }
    if (paths.isEmpty) return null;
    try {
      return _longestCommonDirectoryForFiles(paths);
    } catch (e, st) {
      debugPrint('_inferBrowseSubtreeRoot: $e\n$st');
      return null;
    }
  }

  Future<void> _mergeRescanBrowseSubtree(
    PlayerController player,
    String subtreeRoot,
  ) async {
    final normRoot = p_path.normalize(File(subtreeRoot.trim()).absolute.path);
    final scanned = await collectMp3FilesMerged([normRoot]);
    final scannedPaths = scanned.map((f) => f.path).toSet();
    final scannedByPath = {for (final f in scanned) f.path: f};

    final existing = player.metadataLibrary.toList(growable: false);
    final kept = <TrackItem>[];
    final removedUnderTree = <String>[];
    for (final t in existing) {
      final fp = t.filePath?.trim();
      if (fp == null || fp.isEmpty) continue;
      if (_pathWithinSubtree(fp, normRoot)) {
        if (!scannedPaths.contains(fp)) {
          removedUnderTree.add(fp);
        }
        continue;
      }
      kept.add(t);
    }

    if (removedUnderTree.isNotEmpty) {
      await SongMetadataCache.deletePaths(removedUnderTree);
    }

    final subtreeCached = await SongMetadataCache.loadSnapshotsForRoots([
      normRoot,
    ]);
    final changed = <ScannedMp3File>[];
    final repairSnapshots = <CachedTrackSnapshot>[];

    for (final f in scanned) {
      final snap = subtreeCached[f.path];
      if (snap == null) {
        changed.add(f);
      } else if (snap.fileModifiedMs != f.lastModifiedMs ||
          snap.fileSizeBytes != f.fileSizeBytes) {
        changed.add(f);
      } else if (snap.fileSizeBytes == 0) {
        repairSnapshots.add(
          CachedTrackSnapshot(
            track: snap.track,
            fileModifiedMs: f.lastModifiedMs,
            fileSizeBytes: f.fileSizeBytes,
          ),
        );
      }
    }

    if (repairSnapshots.isNotEmpty) {
      await SongMetadataCache.saveTrackSnapshots(repairSnapshots);
    }

    final newByPath = <String, TrackItem>{};
    const batchSize = 6;
    for (var i = 0; i < changed.length; i += batchSize) {
      final batch = changed.skip(i).take(batchSize).toList(growable: false);
      final batchRows = await Future.wait(
        batch.map((f) async {
          final base = TrackItem.fromFilePath(f.path);
          try {
            final parsed = await readAudioMetadata(base);
            return CachedTrackSnapshot(
              track: parsed,
              fileModifiedMs: f.lastModifiedMs,
              fileSizeBytes: f.fileSizeBytes,
            );
          } catch (e, st) {
            debugPrint('browse subtree rescan metadata ${f.path}: $e\n$st');
            return CachedTrackSnapshot(
              track: base,
              fileModifiedMs: f.lastModifiedMs,
              fileSizeBytes: f.fileSizeBytes,
            );
          }
        }),
      );
      await SongMetadataCache.saveTrackSnapshots(batchRows);
      for (final row in batchRows) {
        final p = row.track.filePath?.trim();
        if (p != null && p.isNotEmpty) {
          newByPath[p] = row.track;
        }
      }
    }

    final subtreeTracksOrdered = <TrackItem>[];
    for (final f in scanned) {
      final p = f.path;
      if (newByPath.containsKey(p)) {
        subtreeTracksOrdered.add(newByPath[p]!);
      } else {
        final snap = subtreeCached[p];
        subtreeTracksOrdered.add(snap?.track ?? TrackItem.fromFilePath(p));
      }
    }

    final merged = <TrackItem>[...kept, ...subtreeTracksOrdered];
    final mergedPaths = merged
        .map((t) => t.filePath)
        .whereType<String>()
        .toSet();

    await RecentlyAddedStore.mergeScanPaths(mergedPaths);
    if (!mounted) return;
    unawaited(SongMetadataCache.deleteMissingPaths(mergedPaths));
    unawaited(SongMetadataCache.saveTracks(merged));

    unawaited(_setPlayerLibraryCatalog(player, merged));
    FolderCountCache.instance.clear();
    unawaited(
      player.prefillArtAvailabilityFromDiskCache(
        subtreeTracksOrdered.map((t) => t.filePath).whereType<String>(),
      ),
    );
    _scheduleAlbumArtWarmup(player);

    final wasPlaying = player.isPlaying || player.audioPlayer.playing;
    final playbackPosition = player.position;
    if (player.playlist.isNotEmpty) {
      if (player.refreshLibraryDuringPlayback(merged)) {
        // ok
      } else {
        await player.tryResyncQueueWithLibraryScan(
          merged,
          resumePosition: playbackPosition,
          resumePlaying: wasPlaying,
        );
      }
    }

    final enrichPlaying = player.isPlaying || player.audioPlayer.playing;
    unawaited(
      enrichPlaylistTracks(
        tracks: subtreeTracksOrdered,
        onTrackUpdated: (path, updated) {
          player.updateTrackByPath(
            path,
            updated,
            notify: CatalogNotifyMode.throttled,
            refreshNotificationArt: false,
          );
          unawaited(SongMetadataCache.saveTracks([updated]));
        },
        scannedByPath: scannedByPath,
        snapshotsByPath: subtreeCached,
        backgroundSyncPending: true,
        isPlaying: enrichPlaying,
        libraryLength: merged.length,
      ).catchError((Object e, StackTrace st) {
        debugPrint('enrichPlaylistTracks (browse subtree): $e\n$st');
      }),
    );
  }

  void _openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  void _goLibrary() {
    setState(() => _page = _ShellPage.library);
    unawaited(PlaybackSessionStore.saveShellPageIsSettings(false));
  }

  void _goYoutube() {
    if (kIsWeb) {
      _goLibrary();
      return;
    }
    setState(() => _page = _ShellPage.youtube);
    unawaited(PlaybackSessionStore.saveShellPageIsSettings(false));
  }

  void _onEscapeToSongsLibrary() {
    if (!mounted) return;
    _scaffoldKey.currentState?.closeDrawer();
    _goLibrary();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _libraryScreenKey.currentState?.switchToSongsTab();
    });
  }

  Future<void> _windowsEscapeCloseNowPlaying() async {
    if (!mounted) return;
    if (!NowPlayingRouteMark.isOpen) return;
    final nav = appNavigatorKey.currentState;
    if (nav == null || !nav.canPop()) return;

    final openedFrom = _nowPlayingOpenedFromTab;
    NowPlayingEscDuplicatePopGuard.blockShortcutCollapse = true;
    try {
      nav.pop();
      _applyLibraryAfterClosingNowPlaying(openedFrom);
      _nowPlayingOpenedFromTab = null;
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NowPlayingEscDuplicatePopGuard.blockShortcutCollapse = false;
      });
    }
  }

  void _applyLibraryAfterClosingNowPlaying(LibraryTabId? openedFromTab) {
    if (!mounted) return;
    final player = PlayerController.of(context);
    final tabId = openedFromTab == LibraryTabId.nowPlayingList
        ? LibraryTabId.nowPlayingList
        : (player.playbackOriginTab ?? LibraryTabId.songs);
    final userPlaylistId = player.playbackOriginUserPlaylistId;

    if (tabId == LibraryTabId.youtube ||
        tabId == LibraryTabId.youtubeSearch) {
      _goYoutube();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _youtubeHubKey.currentState?.switchToPage(
          tabId == LibraryTabId.youtubeSearch
              ? YoutubePageId.find
              : YoutubePageId.library,
        );
      });
      return;
    }

    _goLibrary();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final st = _libraryScreenKey.currentState;
        if (st == null) return;
        await st.switchToTabAndScrollToCurrentTrack(
          tabId,
          scrollToCurrentTrack: tabId != LibraryTabId.songs,
        );
        if (!mounted) return;
        if (tabId == LibraryTabId.playlist && userPlaylistId != null) {
          await st.openUserPlaylistSheetById(userPlaylistId);
        }
      });
    });
  }

  void _goSettings() {
    setState(() => _page = _ShellPage.settings);
    unawaited(PlaybackSessionStore.saveShellPageIsSettings(true));
  }

  void _openNowPlaying() {
    final player = PlayerController.of(context);
    final openedFromTab = _libraryScreenKey.currentState?.currentTabId;
    if (player.currentTrack == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing is playing right now.')),
      );
      return;
    }
    _nowPlayingOpenedFromTab = openedFromTab;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: NowPlayingScreen(
              onCollapse: () {
                final nav = Navigator.of(context);
                if (nav.canPop()) nav.pop();
                _applyLibraryAfterClosingNowPlaying(_nowPlayingOpenedFromTab);
                _nowPlayingOpenedFromTab = null;
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
          onOpenNowPlaying: _openNowPlaying,
          onOpenLibrary: _goLibrary,
          onOpenSettings: _goSettings,
          onOpenHelp: () {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (helpCtx) =>
                    HelpScreen(onBack: () => Navigator.of(helpCtx).pop()),
              ),
            );
          },
          onQuit: () {
            unawaited(_quitApp());
          },
          onRefreshLibrary: _refreshLibraryScan,
        ),
      ),
    );
    if (!mounted) return;
    if (pickedKeys != null) {
      final keys = Set<String>.from(pickedKeys);
      _songsBrowsePathKeysNotifier.value = keys;
      PlayerController.of(
        context,
      ).setPlaybackPathKeyScope(keys, reloadQueue: false);
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
      listenable: player.track,
      builder: (context, _) {
        final current = player.currentTrack;

        final pal = context.palette;

        return PopScope(
          canPop: _page == _ShellPage.library,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_page == _ShellPage.settings || _page == _ShellPage.youtube) {
              _goLibrary();
            }
          },
          child: Scaffold(
            key: _scaffoldKey,
            backgroundColor: pal.scaffoldBackground,
            drawer: _GlossyDrawer(
              currentPage: _page,
              hasCurrentTrack: current != null,
              onNowPlaying: _onDrawerNowPlaying,
              onLibrary: () {
                Navigator.pop(context);
                _goLibrary();
              },
              onFiles: () {
                Navigator.pop(context);
                _goLibrary();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  unawaited(_openFilesExplorerScreen());
                });
              },
              onYoutube: kIsWeb
                  ? null
                  : () {
                      Navigator.pop(context);
                      _goYoutube();
                    },
              onSettings: () {
                Navigator.pop(context);
                _goSettings();
              },
              onHelp: () {
                Navigator.pop(context);
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (ctx) =>
                        HelpScreen(onBack: () => Navigator.of(ctx).pop()),
                  ),
                );
              },
              onQuit: () {
                Navigator.pop(context);
                unawaited(_quitApp());
              },
            ),
            body: Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: switch (_page) {
                        _ShellPage.library => LibraryScreen(
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
                            onRefreshLibrary:
                                _folderPaths.isEmpty ||
                                    _scanning ||
                                    _refreshInProgress
                                ? null
                                : () {
                                    unawaited(_refreshLibraryScan());
                                  },
                          ),
                        _ShellPage.youtube => YoutubeHubScreen(
                            key: _youtubeHubKey,
                            onOpenDrawer: _openDrawer,
                          ),
                        _ShellPage.settings => SettingsScreen(
                              folderPaths: _folderPaths,
                              onFoldersChanged: _onFoldersChanged,
                              onOpenDrawer: _openDrawer,
                              themeSetting: widget.themeSetting,
                              onThemeSettingChanged:
                                  widget.onThemeSettingChanged,
                              fontOption: widget.fontOption,
                              onFontOptionChanged: widget.onFontOptionChanged,
                              accentColorOption: widget.accentColorOption,
                              customAccentColor: widget.customAccentColor,
                              onAccentColorOptionChanged:
                                  widget.onAccentColorOptionChanged,
                              onCustomAccentColorChanged:
                                  widget.onCustomAccentColorChanged,
                              playerChromeBackgroundKind:
                                  widget.playerChromeBackgroundKind,
                              playerChromeCustomBackground:
                                  widget.playerChromeCustomBackground,
                              onPlayerChromeBackgroundKindChanged:
                                  widget.onPlayerChromeBackgroundKindChanged,
                              onPlayerChromeCustomBackgroundChanged:
                                  widget.onPlayerChromeCustomBackgroundChanged,
                              onEraseAllAppData: _eraseAllAppData,
                              onYoutubeMergeIntoSongsChanged: kIsWeb
                                  ? null
                                  : (_) async {
                                      final player = PlayerController.of(
                                        context,
                                      );
                                      await _applyYoutubeMergeSetting(player);
                                    },
                              onYoutubeStorageRefreshed: kIsWeb
                                  ? null
                                  : () async {
                                      try {
                                        await YoutubeLibraryCatalog
                                            .instance
                                            .reload();
                                      } catch (e, st) {
                                        debugPrint(
                                          'onYoutubeStorageRefreshed scan: $e\n$st',
                                        );
                                      }
                                      if (!context.mounted) return;
                                      final player = PlayerController.of(
                                        context,
                                      );
                                      await _applyYoutubeMergeSetting(player);
                                    },
                          ),
                      },
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
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
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
          ),
        );
      },
    );
  }
}

class _GlossyDrawer extends StatelessWidget {
  const _GlossyDrawer({
    required this.onNowPlaying,
    required this.onLibrary,
    required this.onFiles,
    this.onYoutube,
    required this.onSettings,
    required this.onHelp,
    required this.onQuit,
    required this.currentPage,
    required this.hasCurrentTrack,
  });

  final VoidCallback onNowPlaying;
  final VoidCallback onLibrary;
  final VoidCallback onFiles;
  final VoidCallback? onYoutube;
  final VoidCallback onSettings;
  final VoidCallback onHelp;
  final VoidCallback onQuit;
  final _ShellPage currentPage;
  final bool hasCurrentTrack;

  @override
  Widget build(BuildContext context) {
    final pal = context.palette;
    final theme = Theme.of(context);
    final ivy = context.appliedThemePalette == AppThemePalette.ivy;
    final drawerBg = Color.alphaBlend(
      pal.onScaffold.withValues(alpha: 0.04),
      pal.surface,
    );

    return Drawer(
      backgroundColor: drawerBg,
      elevation: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(
                pal.onScaffold.withValues(alpha: 0.05),
                drawerBg,
              ),
              drawerBg,
            ],
          ),
        ),
        child: DaisyBackground(
          baseColor: drawerBg,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: Text(
                    'MadPlayer',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: ivy ? const Color(0xFF1C1C1E) : pal.textPrimary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                Divider(
                  indent: 24,
                  endIndent: 24,
                  thickness: 0.8,
                  color: pal.onScaffold.withValues(alpha: 0.12),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      _GlossyDrawerTile(
                        icon: Icons.play_circle_outline_rounded,
                        label: 'Now playing',
                        onTap: hasCurrentTrack ? onNowPlaying : null,
                        selected: false,
                      ),
                      _GlossyDrawerTile(
                        icon: Icons.library_music_outlined,
                        label: 'Library',
                        onTap: onLibrary,
                        selected: currentPage == _ShellPage.library,
                      ),
                      if (onYoutube != null)
                        _GlossyDrawerTile(
                          icon: Icons.video_library_outlined,
                          label: 'YouTube',
                          onTap: onYoutube,
                          selected: currentPage == _ShellPage.youtube,
                        ),
                      _GlossyDrawerTile(
                        icon: Icons.folder_open_rounded,
                        label: 'Files',
                        onTap: onFiles,
                        selected: false,
                      ),
                      _GlossyDrawerTile(
                        icon: Icons.settings_outlined,
                        label: 'Settings',
                        onTap: onSettings,
                        selected: currentPage == _ShellPage.settings,
                      ),
                      _GlossyDrawerTile(
                        icon: Icons.help_outline_rounded,
                        label: 'Help',
                        onTap: onHelp,
                        selected: false,
                      ),
                    ],
                  ),
                ),
                Divider(
                  indent: 24,
                  endIndent: 24,
                  thickness: 0.8,
                  color: pal.onScaffold.withValues(alpha: 0.12),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                  child: _GlossyDrawerTile(
                    icon: Icons.power_settings_new_rounded,
                    label: 'Quit',
                    onTap: onQuit,
                    selected: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlossyDrawerTile extends StatelessWidget {
  const _GlossyDrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final pal = context.palette;
    final ivy = context.appliedThemePalette == AppThemePalette.ivy;
    final baseTextColor = pal.textPrimary;
    final mutedTextColor = pal.textSecondary;
    final selectedTextColor = ivy ? const Color(0xFF1C1C1E) : baseTextColor;
    final unselectedTextColor = ivy ? const Color(0xFF48484A) : mutedTextColor;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: selected
                  ? (ivy
                        ? Colors.white.withValues(alpha: 0.5)
                        : pal.onScaffold.withValues(alpha: 0.1))
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: selected
                      ? (ivy ? const Color(0xFF1C1C1E) : context.controlAccent)
                      : unselectedTextColor,
                  size: 26,
                ),
                const SizedBox(width: 16),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? selectedTextColor : unselectedTextColor,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
