import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../audio/player_controller.dart';
import '../../models/library_tab_id.dart';
import '../../models/track_item.dart';
import '../../models/youtube_channel_ref.dart';
import '../../services/file_path_mtime_sort.dart';
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
import '../../platform/android_app_task_bridge.dart';
import '../../platform/android_home_widget_bridge.dart';
import '../../platform/android_widget_launch_bridge.dart';
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
import '../../platform/youtube_platform_support.dart';
import '../youtube/youtube_search_screen.dart';
import 'now_playing_escape_bridge.dart';
import 'shell_navigation_hub.dart';

/// During folder scan, skip building a huge native playback queue until the user
/// actually plays something (avoids hanging on "Loading tags…" for large libraries).
const int _largeLibraryDeferPlayerQueueThreshold = 200;

/// Cap per-pass cover extraction so opening a large library cannot ANR the UI.
const int _albumArtWarmupBatchSize = 16;

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
    nav.popUntil((route) => route.isFirst);
  }
  EscapeToSongsLibraryHub.completeNavigationToSongs();
}

enum _ShellPage { library, settings, onlineSearch }

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

  /// When non-null from Files browser, Songs tab restricts to paths in this exact set (from scanMp3Files).
  final ValueNotifier<Set<String>?> _songsBrowsePathKeysNotifier =
      ValueNotifier<Set<String>?>(null);
  _ShellPage _page = _ShellPage.library;
  int _onlineSearchOpenToken = 0;
  YoutubeChannelRef? _onlineSearchInitialChannel;
  List<String> _folderPaths = [];
  bool _scanning = false;

  /// Set after filesystem scan completes; `null` means still enumerating MP3 paths.
  int? _scanDetectedMp3Count;
  PlayerController? _playerForRecentHistory;
  PlayerController? _playerForPlaybackPersistence;
  PlayerController? _playerRef;
  String? _dispatchedRecentPath;
  bool _showingFirstRunHint = false;
  bool _openMusicFoldersInSettings = false;
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

  @override
  void initState() {
    super.initState();
    EscapeToSongsLibraryHub.register(_onEscapeToSongsLibrary);
    ShellNavigationHub.goOnlineSearch = _goOnlineSearch;
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
      _playerForRecentHistory?.removeListener(_recordRecentlyPlayedTrack);
      _playerForRecentHistory = player;
      player.addListener(_recordRecentlyPlayedTrack);
    }
    if (!identical(_playerForPlaybackPersistence, player)) {
      _playerForPlaybackPersistence?.removeListener(
        _schedulePlaybackSessionPersist,
      );
      _playerForPlaybackPersistence = player;
      player.addListener(_schedulePlaybackSessionPersist);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleIdleRescan();
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final player = _playerRef;
        if (player != null) {
          unawaited(_applyWidgetLaunchAction(player));
        }
      }
      // Re-check permission when resuming; the user may have just granted it
      // from the system Settings app.  If it was previously denied and is now
      // granted, trigger an immediate rescan so the library populates.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        unawaited(_recheckPermissionOnResume());
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
    // Skip while bootstrap is already showing the permission dialog.
    if (_storagePermissionGranted == null) return;
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

    final bootData = await Future.wait<dynamic>([
      PlaybackSessionStore.loadShellPageIsSettings(),
      PlaybackSessionStore.loadBrowsePathKeys(),
      SavedMusicFolders.load(),
    ]);
    if (!mounted) return;
    final showSettings = bootData[0] as bool;
    final browseKeys = bootData[1] as Set<String>?;
    var paths = List<String>.from(bootData[2] as List<String>);

    // Prune saved folder paths whose directory no longer exists on disk so that
    // stale cached tracks from deleted folders are never loaded or played.
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows)) {
      final existence = await Future.wait<bool>(
        paths.map((folder) async {
          try {
            return await Directory(folder).exists();
          } catch (_) {
            return true;
          }
        }),
      );
      final live = <String>[];
      for (var i = 0; i < paths.length; i++) {
        if (existence[i]) live.add(paths[i]);
      }
      if (live.length != paths.length) {
        paths = live;
        unawaited(SavedMusicFolders.save(paths));
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
    if (!mounted) return;
    unawaited(_applyWidgetLaunchAction(player));
    _scheduleBackgroundSync(delay: const Duration(seconds: 4));
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
      final goToSettings = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          final theme = Theme.of(dialogContext);
          final pal = dialogContext.palette;
          return AlertDialog(
            backgroundColor: pal.surface,
            title: Text(
              'Welcome to MadPlayer',
              style: theme.textTheme.titleLarge?.copyWith(
                color: pal.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your library is empty because no music folders are set up yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: pal.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '1. Open Settings → Music folders\n'
                    '2. Tap Add folder and choose a folder with MP3 files\n'
                    '3. Return to Library — songs appear after scanning',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: pal.textPrimary,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(
                  'Later',
                  style: TextStyle(color: pal.textPrimary),
                ),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Add music folders'),
              ),
            ],
          );
        },
      );
      if (!mounted) return;
      if (goToSettings == false) {
        await FirstRunLibraryHintStore.markDismissed();
      } else if (goToSettings == true) {
        _goSettings(openMusicFolders: true);
      }
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

      // Show the library immediately; restore queue/position without blocking first paint.
      unawaited(
        PlaybackSessionStore.restorePlayer(
          player,
          tracks,
          resumePlaying: false,
        ),
      );
    }
    _scheduleAlbumArtWarmup(player, delay: const Duration(seconds: 5));
  }

  Future<void> _applyWidgetLaunchAction(PlayerController player) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final action = await AndroidWidgetLaunchBridge.consumeLaunchAction();
    if (!mounted || action == null) return;

    Future<void> ensureQueueRestored({required bool resumePlaying}) async {
      if (player.playlist.isNotEmpty) return;
      final catalog = player.metadataLibrary;
      if (catalog.isEmpty) return;
      await PlaybackSessionStore.restorePlayer(
        player,
        catalog,
        resumePlaying: resumePlaying,
      );
    }

    switch (action) {
      case AndroidWidgetLaunchBridge.actionPlay:
        await ensureQueueRestored(resumePlaying: true);
        if (!mounted || player.playlist.isEmpty) return;
        if (!player.isPlaying) await player.play();
      case AndroidWidgetLaunchBridge.actionSkipNext:
        await ensureQueueRestored(resumePlaying: false);
        if (!mounted || player.playlist.isEmpty) return;
        await player.skipNext();
      case AndroidWidgetLaunchBridge.actionSkipPrevious:
        await ensureQueueRestored(resumePlaying: false);
        if (!mounted || player.playlist.isEmpty) return;
        await player.skipPrevious();
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
    if (player.isPlaying) {
      _scheduleBackgroundSync(delay: const Duration(seconds: 30));
      return;
    }
    try {
      final cachedByPath = await SongMetadataCache.loadSnapshotsForRoots(roots);
      final scanned = await _collectMp3FileStats(roots);
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

      for (final f in scanned) {
        final snap = cachedByPath[f.path];
        if (snap == null ||
            snap.fileModifiedMs != f.lastModifiedMs ||
            snap.fileSizeBytes != f.fileSizeBytes) {
          changedPaths.add(f);
        } else {
          // Keep in-memory version if already seeded above (may be fresher).
          live[f.path] ??= snap.track;
        }
      }

      const batchSize = 4;
      for (var i = 0; i < changedPaths.length; i += batchSize) {
        if (!mounted || player.isPlaying) return;
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
            live[p] = TrackItem.mergePreservedAlbumArt(s.track, live[p]);
          }
        }
        if (!mounted) return;
        final partial = scanned
            .map((f) {
              final base = live[f.path] ?? TrackItem.fromFilePath(f.path);
              return TrackItem.mergePreservedAlbumArt(
                base,
                player.trackForLibraryPath(f.path),
              );
            })
            .toList(growable: false);
        player.setLibraryCatalog(partial, notify: CatalogNotifyMode.throttled);
      }

      if (!mounted) return;
      final finalTracks = scanned
          .map((f) {
            final base = live[f.path] ?? TrackItem.fromFilePath(f.path);
            return TrackItem.mergePreservedAlbumArt(
              base,
              player.trackForLibraryPath(f.path),
            );
          })
          .toList(growable: false);
      player.setLibraryCatalog(finalTracks);
      _scheduleAlbumArtWarmup(player, delay: const Duration(seconds: 4));

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

  List<TrackItem> _tracksNeedingArtPrioritized(PlayerController player) {
    final needing = <TrackItem>[];
    final seen = <String>{};

    void add(TrackItem? track) {
      if (track == null) return;
      final path = track.filePath?.trim();
      if (path == null || path.isEmpty) return;
      final art = track.albumArtBytes;
      if (art != null && art.isNotEmpty) return;
      final key = canonicalMusicLibraryPathKey(path);
      if (key.isEmpty || !seen.add(key)) return;
      needing.add(track);
    }

    add(player.currentTrack);
    for (final track in player.playlist) {
      add(track);
    }
    for (final track in player.metadataLibrary) {
      add(track);
    }
    return needing;
  }

  bool _canRunAlbumArtWarmup(PlayerController player) =>
      mounted && !player.isPlaying;

  Future<void> _enrichLibraryWhenIdle(
    PlayerController player,
    List<TrackItem> tracks,
  ) async {
    if (kIsWeb || !mounted || player.isPlaying) return;
    await enrichPlaylistTracks(
      tracks: tracks,
      maxTracks: _albumArtWarmupBatchSize,
      batchSize: 1,
      interBatchDelay: const Duration(milliseconds: 120),
      shouldContinue: () => _canRunAlbumArtWarmup(player),
      onTrackUpdated: (path, updated) {
        if (!_canRunAlbumArtWarmup(player)) return;
        player.updateTrackByPath(
          path,
          updated,
          notify: CatalogNotifyMode.throttled,
          refreshNotificationArt: false,
        );
        unawaited(SongMetadataCache.saveTracks([updated]));
      },
    );
    if (mounted && _canRunAlbumArtWarmup(player)) {
      _scheduleAlbumArtWarmup(player);
    }
  }

  void _scheduleAlbumArtWarmup(
    PlayerController player, {
    Duration delay = Duration.zero,
  }) {
    if (kIsWeb) return;
    if (delay > Duration.zero) {
      _albumArtWarmupRetryTimer?.cancel();
      _albumArtWarmupRetryTimer = Timer(delay, () {
        if (!mounted) return;
        _scheduleAlbumArtWarmup(player);
      });
      return;
    }
    // Bulk warmup waits for idle; still load art for now-playing + next while playing.
    if (player.isPlaying) {
      final priority = _tracksNeedingArtPrioritized(player)
          .take(3)
          .toList(growable: false);
      if (priority.isNotEmpty) {
        unawaited(
          player.enrichTracksArtIfMissing(
            priority,
            maxTracks: 3,
            refreshNotificationArt: true,
          ),
        );
      }
      _albumArtWarmupQueued = true;
      _albumArtWarmupRetryTimer?.cancel();
      _albumArtWarmupRetryTimer = Timer(const Duration(seconds: 20), () {
        if (!mounted) return;
        _scheduleAlbumArtWarmup(player);
      });
      return;
    }
    if (_albumArtWarmupInProgress) {
      _albumArtWarmupQueued = true;
      return;
    }
    _albumArtWarmupInProgress = true;
    unawaited(() async {
      try {
        final tracksNeedingArt = _tracksNeedingArtPrioritized(player);
        if (tracksNeedingArt.isEmpty) return;
        final batch = tracksNeedingArt
            .take(_albumArtWarmupBatchSize)
            .toList(growable: false);
        await enrichPlaylistTracks(
          tracks: batch,
          batchSize: 1,
          interBatchDelay: const Duration(milliseconds: 120),
          shouldContinue: () => _canRunAlbumArtWarmup(player),
          onTrackUpdated: (path, updated) {
            if (!_canRunAlbumArtWarmup(player)) return;
            player.updateTrackByPath(
              path,
              updated,
              notify: CatalogNotifyMode.throttled,
              refreshNotificationArt: false,
            );
            unawaited(SongMetadataCache.saveTracks([updated]));
          },
        );
        if (tracksNeedingArt.length > batch.length &&
            _canRunAlbumArtWarmup(player)) {
          _albumArtWarmupQueued = true;
        }
      } catch (e, st) {
        debugPrint('_scheduleAlbumArtWarmup: $e\n$st');
      } finally {
        _albumArtWarmupInProgress = false;
        if (_albumArtWarmupQueued) {
          _albumArtWarmupQueued = false;
          if (_canRunAlbumArtWarmup(player)) {
            _albumArtWarmupRetryTimer?.cancel();
            _albumArtWarmupRetryTimer = Timer(const Duration(seconds: 8), () {
              if (!mounted) return;
              _scheduleAlbumArtWarmup(player);
            });
          }
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
        await player.releaseAudioForAppExit();
      } catch (e, st) {
        debugPrint('_quitApp releaseAudio: $e\n$st');
      }
    }
    await _persistSession();
    if (kIsWeb) {
      SystemNavigator.pop();
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      await AndroidHomeWidgetBridge.markStoppedOnQuit();
      await AndroidAppTaskBridge.finishAndRemoveTask();
      return;
    }
    exit(0);
  }

  @override
  void dispose() {
    EscapeToSongsLibraryHub.unregister();
    ShellNavigationHub.goOnlineSearch = null;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      NowPlayingWindowsEsc.handler = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _idleRescanTimer?.cancel();
    _persistPlaybackDebounceTimer?.cancel();
    _albumArtWarmupRetryTimer?.cancel();
    unawaited(_persistSession());
    _playerForRecentHistory?.removeListener(_recordRecentlyPlayedTrack);
    _playerForPlaybackPersistence?.removeListener(
      _schedulePlaybackSessionPersist,
    );
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
    bool showProgressOverlay = true,
  }) async {
    final player = PlayerController.of(context);
    final pathToPreserve = preservePlaybackAfterRescan
        ? player.currentTrack?.filePath
        : null;
    // Capture before any await — reload paths can make [isPlaying] flicker false.
    final wasPlaying = preservePlaybackAfterRescan &&
        (player.isPlaying || player.audioPlayer.playing);
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

    if (showProgressOverlay) {
      setState(() {
        _scanning = true;
        _scanDetectedMp3Count = null;
      });
    }
    List<String> files;
    try {
      files = await _collectMp3Paths(paths);
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
        if (keepCurrentQueue && player.playlist.isNotEmpty) {
          final keptPlayback = player.refreshLibraryDuringPlayback(tracks);
          if (keptPlayback) {
            if (!kIsWeb && mounted) {
              unawaited(_enrichLibraryWhenIdle(player, tracks));
            }
            return;
          }
          await player.tryResyncQueueWithLibraryScan(
            tracks,
            resumePosition: playbackPosition,
            resumePlaying: wasPlaying,
          );
          if (!kIsWeb && mounted) {
            unawaited(_enrichLibraryWhenIdle(player, tracks));
          }
          return;
        }
        var resolvedStart = startIndex.clamp(0, tracks.length - 1);
        if (pathToPreserve != null && pathToPreserve.trim().isNotEmpty) {
          final key = player.libraryPathKeyForScanMatch(pathToPreserve);
          if (key.isNotEmpty) {
            final idx = tracks.indexWhere(
              (t) =>
                  canonicalMusicLibraryPathKey((t.filePath ?? '').trim()) ==
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
          if (!kIsWeb && mounted) {
            unawaited(_enrichLibraryWhenIdle(player, tracks));
          }
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
        if (!kIsWeb && mounted) {
          unawaited(_enrichLibraryWhenIdle(player, tracks));
        }
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
          if (!kIsWeb && mounted) {
            unawaited(_enrichLibraryWhenIdle(player, tracks));
          }
          return;
        }
      }

      var resolvedStart = startIndex.clamp(0, tracks.length - 1);
      final deferHeavyPlayerQueue =
          tracks.length >= _largeLibraryDeferPlayerQueueThreshold &&
          !playAfter &&
          !wasPlaying;
      if (deferHeavyPlayerQueue && player.playlist.isEmpty) {
        if (!kIsWeb && mounted) {
          unawaited(_enrichLibraryWhenIdle(player, tracks));
        }
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

      if (!kIsWeb && mounted) {
        unawaited(_enrichLibraryWhenIdle(player, tracks));
      }
    } finally {
      if (showProgressOverlay && mounted) {
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
    final hadFolders = _folderPaths.isNotEmpty;
    setState(() => _folderPaths = List<String>.from(paths));
    if (paths.isNotEmpty) {
      await FirstRunLibraryHintStore.markDismissed();
    }
    await _scanFoldersAndSetPlaylist(
      paths,
      playAfter: false,
      preservePlaybackAfterRescan: true,
      keepCurrentQueue: true,
    );
    if (!mounted) return;
    ActionPillToast.showUsingRootNavigator(
      'Library updated',
      icon: Icons.done_all_rounded,
      uppercaseLabel: true,
    );
    _scheduleIdleRescan();
    if (!hadFolders && paths.isNotEmpty && _page == _ShellPage.settings) {
      _goLibrary();
    }
  }

  Future<void> _refreshLibraryScan() async {
    if (_refreshInProgress) return;
    if (_folderPaths.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Add music folders before refreshing.'),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () => _goSettings(openMusicFolders: true),
          ),
        ),
      );
      return;
    }
    setState(() => _refreshInProgress = true);
    try {
      final player = PlayerController.of(context);
      // Refresh should reflect full library changes immediately (not a stale Files scope).
      _songsBrowsePathKeysNotifier.value = null;
      player.setPlaybackPathKeyScope(null, reloadQueue: false);
      unawaited(PlaybackSessionStore.saveBrowsePathKeys(null));
      await _scanFoldersAndSetPlaylist(
        _folderPaths,
        playAfter: false,
        preservePlaybackAfterRescan: true,
        keepCurrentQueue: true,
        showProgressOverlay: false,
      );
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

  void _openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  void _goLibrary() {
    setState(() {
      _page = _ShellPage.library;
      _openMusicFoldersInSettings = false;
    });
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
    if (player.playbackOriginTab == LibraryTabId.onlineSearch) {
      return;
    }
    final tabId = openedFromTab == LibraryTabId.nowPlayingList
        ? LibraryTabId.nowPlayingList
        : (player.playbackOriginTab ?? LibraryTabId.songs);
    final userPlaylistId = player.playbackOriginUserPlaylistId;
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

  void _goSettings({bool openMusicFolders = false}) {
    setState(() {
      _page = _ShellPage.settings;
      _openMusicFoldersInSettings = openMusicFolders;
    });
    unawaited(PlaybackSessionStore.saveShellPageIsSettings(true));
  }

  void _goOnlineSearch({YoutubeChannelRef? initialChannel}) {
    if (!YoutubePlatformSupport.isOnlinePlaybackSupported) {
      ActionPillToast.showUsingRootNavigator(
        'Online search is available on Android only',
        icon: Icons.info_outline_rounded,
      );
      return;
    }
    setState(() {
      _page = _ShellPage.onlineSearch;
      _openMusicFoldersInSettings = false;
      if (initialChannel != null) {
        _onlineSearchOpenToken++;
        _onlineSearchInitialChannel = initialChannel;
      }
    });
    unawaited(PlaybackSessionStore.saveShellPageIsSettings(false));
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
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: NowPlayingScreen(
              onCollapse: () {
                Navigator.of(context).pop();
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
        SnackBar(
          content: const Text('Add music folders before browsing files.'),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () => _goSettings(openMusicFolders: true),
          ),
        ),
      );
      return;
    }
    final pickedKeys = await Navigator.of(context).push<Set<String>?>(
      MaterialPageRoute(
        builder: (ctx) => LibraryFilesPage(
          musicRoots: _folderPaths,
          onOverflow: _onLibraryTrackOverflow,
          onOpenNowPlaying: _openNowPlaying,
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
      listenable: player,
      builder: (context, _) {
        final current = player.currentTrack;

        final pal = context.palette;

        return PopScope(
          canPop: _page == _ShellPage.library,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_page == _ShellPage.settings ||
                _page == _ShellPage.onlineSearch) {
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
              onYoutubeSearch: () {
                Navigator.pop(context);
                _goOnlineSearch();
              },
              onFiles: () {
                Navigator.pop(context);
                _goLibrary();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  unawaited(_openFilesExplorerScreen());
                });
              },
              onSettings: () {
                Navigator.pop(context);
                _goSettings();
              },
              onHelp: () {
                Navigator.pop(context);
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (ctx) => HelpScreen(
                      onBack: () => Navigator.of(ctx).pop(),
                    ),
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
                            onOpenMusicFolderSettings: () =>
                                _goSettings(openMusicFolders: true),
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
                        _ShellPage.settings => SettingsScreen(
                            folderPaths: _folderPaths,
                            onFoldersChanged: _onFoldersChanged,
                            openMusicFoldersSection: _openMusicFoldersInSettings,
                            onOpenMusicFoldersSectionHandled: () {
                              if (mounted) {
                                setState(
                                  () => _openMusicFoldersInSettings = false,
                                );
                              }
                            },
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
                          ),
                        _ShellPage.onlineSearch => YoutubeSearchScreen(
                            key: ValueKey(
                              'online-search-$_onlineSearchOpenToken',
                            ),
                            onOpenDrawer: _openDrawer,
                            initialChannel: _onlineSearchInitialChannel,
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

/// Drawer uses [AppPalette.surface]; [onScaffold] is for the navy hero, not white panels.
bool _drawerSurfaceIsLight(AppPalette pal) => pal.surface.computeLuminance() > 0.55;

Color _drawerPrimaryFg(AppPalette pal) =>
    _drawerSurfaceIsLight(pal) ? pal.textPrimary : pal.onScaffold;

Color _drawerMutedFg(AppPalette pal) =>
    _drawerSurfaceIsLight(pal)
        ? pal.textSecondary
        : pal.onScaffold.withValues(alpha: 0.75);

Color _drawerSelectedTileBg(AppPalette pal) =>
    _drawerSurfaceIsLight(pal)
        ? pal.textPrimary.withValues(alpha: 0.08)
        : pal.onScaffold.withValues(alpha: 0.1);

class _GlossyDrawer extends StatelessWidget {
  const _GlossyDrawer({
    required this.onNowPlaying,
    required this.onLibrary,
    required this.onYoutubeSearch,
    required this.onFiles,
    required this.onSettings,
    required this.onHelp,
    required this.onQuit,
    required this.currentPage,
    required this.hasCurrentTrack,
  });

  final VoidCallback onNowPlaying;
  final VoidCallback onLibrary;
  final VoidCallback onYoutubeSearch;
  final VoidCallback onFiles;
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

    return Drawer(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: DaisyBackground(
        baseColor: pal.surface,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Text(
                  'MadPlayer',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: ivy ? const Color(0xFF1C1C1E) : _drawerPrimaryFg(pal),
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              Divider(
                indent: 24,
                endIndent: 24,
                thickness: 0.8,
                color: ivy
                    ? pal.onScaffold.withValues(alpha: 0.12)
                    : _drawerMutedFg(pal).withValues(alpha: 0.35),
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
                    if (YoutubePlatformSupport.isOnlinePlaybackSupported)
                      _GlossyDrawerTile(
                        icon: Icons.search_rounded,
                        label: 'Online search',
                        onTap: onYoutubeSearch,
                        selected: currentPage == _ShellPage.onlineSearch,
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
                color: ivy
                    ? pal.onScaffold.withValues(alpha: 0.12)
                    : _drawerMutedFg(pal).withValues(alpha: 0.35),
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
    final ivy = context.appliedThemePalette == AppThemePalette.ivy;
    final pal = context.palette;

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
                      : _drawerSelectedTileBg(pal))
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: selected
                      ? (ivy
                          ? const Color(0xFF1C1C1E)
                          : context.controlAccent)
                      : (ivy
                          ? const Color(0xFF48484A)
                          : _drawerMutedFg(pal)),
                  size: 26,
                ),
                const SizedBox(width: 16),
                Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? (ivy
                            ? const Color(0xFF1C1C1E)
                            : _drawerPrimaryFg(pal))
                        : (ivy
                            ? const Color(0xFF48484A)
                            : _drawerMutedFg(pal)),
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
