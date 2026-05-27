import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data';

// audio_session exposes output device types as experimental, but this is the
// supported way to pause on Bluetooth output removal in the current package.
// ignore_for_file: experimental_member_use

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, listEquals;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../models/library_tab_id.dart';
import '../models/track_item.dart';
import '../services/album_art_cache.dart';
import '../services/album_art_dimensions.dart';
import '../services/library_path_migration.dart';
import '../services/music_library_path_key.dart';
import '../services/song_metadata_cache.dart';
import '../services/track_metadata.dart';
import '../services/volume_settings_store.dart';
import 'art_availability_notifier.dart';
import 'notification_art_uri.dart';
import 'album_art_resolver.dart';
import 'library_catalog.dart';
import 'player_notifiers.dart';

enum PlaylistRepeatMode { off, all, one }

/// How [PlayerController] notifies listeners after catalog or in-memory track updates.
///
/// Use [throttled] for high-frequency background work (disk sync, cover warmup) so
/// Library / mini-player do not rebuild on every row.
enum CatalogNotifyMode {
  /// One [notifyListeners] immediately.
  immediate,

  /// At most one [notifyListeners] per ~300ms while updates keep arriving.
  throttled,
}

/// `just_audio_windows` currently logs "Failed to seek to item" during
/// [setAudioSource] with a concatenated source and can ignore [initialIndex],
/// causing item 0 to play regardless of the selected Dart queue index.
bool _useSingleTrackAudioSourceForPlatform() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.windows;
}

/// [ConcatenatingAudioSource] with lazy preparation makes [setAudioSource]'s
/// [initialIndex] unreliable on desktop Windows. Other platforms keep lazy prep.
bool _concatUseLazyPreparationForPlatform() {
  if (kIsWeb) return true;
  return defaultTargetPlatform != TargetPlatform.windows;
}

/// Local playback coordinator. UI listens to [position], [track], [playback], [queue]
/// notifiers — not this class — to avoid whole-tree rebuilds.
class PlayerController {
  bool _isInterruptedAbort(Object error) {
    if (error is! PlatformException) return false;
    final code = error.code.toLowerCase();
    final message = (error.message ?? '').toLowerCase();
    return code == 'abort' && message.contains('loading interrupted');
  }

  Future<void> _playSafely({String context = 'play'}) async {
    try {
      await _activateAudioSessionForPlayback();
      await _player.play();
    } catch (e, st) {
      if (_isInterruptedAbort(e)) return;
      debugPrint('$context error: $e\n$st');
      rethrow;
    }
  }

  /// After [setAudioSource], the native player may still be [ProcessingState.loading]
  /// when [_loadCurrent] returns — [play] then no-ops on some platforms.
  ///
  /// We **poll** [processingState] instead of subscribing to [processingStateStream]:
  /// a fast `loading → ready` transition can happen between the synchronous `!= ready`
  /// check and subscribing, so the stream never emits `ready` and playback never starts
  /// until a long timeout (or never, if [play] keeps no-op'ing).
  /// While > 0, [playerStateStream] must not treat [stop] / load pauses as user pause.
  int _transportPauseGuardDepth = 0;

  bool get _ignoreSpuriousTransportPause => _transportPauseGuardDepth > 0;

  Future<void> _guardedTransport(Future<void> Function() action) async {
    _transportPauseGuardDepth++;
    try {
      await action();
    } finally {
      _transportPauseGuardDepth--;
    }
  }

  Future<void>? _audioSessionInit;

  Future<void> _ensureAudioSessionReady() async {
    final init = _audioSessionInit;
    if (init != null) await init;
  }

  Future<void> _activateAudioSessionForPlayback() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    try {
      await _ensureAudioSessionReady();
      final session = await AudioSession.instance;
      await session.setActive(true);
    } catch (e, st) {
      debugPrint('AudioSession.setActive: $e\n$st');
    }
  }

  Future<void> _resumePlaybackAfterLoad({
    String context = 'resumeAfterLoad',
  }) async {
    // Explicit play-after-load (tap track, setPlaylistAndPlay, skip, …). Clear stale
    // pause flag from a late stop() event that arrived after [_loadCurrent] finished.
    _playbackPausedByUser = false;
    final generation = _playControlGeneration;
    await _waitForPlayerPreparedAfterSourceChange();
    if (_playbackPausedByUser || _playControlGeneration != generation) return;
    // One event-loop turn; helps desktop embedders finish native load callbacks.
    await Future<void>.delayed(Duration.zero);
    if (_playbackPausedByUser || _playControlGeneration != generation) return;
    await _ensurePlayingWithRetries(context: context, generation: generation);
  }

  Future<void> _waitForPlayerPreparedAfterSourceChange() async {
    const step = Duration(milliseconds: 40);
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline)) {
      switch (_player.processingState) {
        case ProcessingState.ready:
        case ProcessingState.buffering:
          return;
        case ProcessingState.completed:
          return;
        case ProcessingState.idle:
        case ProcessingState.loading:
          break;
      }
      await Future<void>.delayed(step);
    }
    debugPrint(
      '_waitForPlayerPreparedAfterSourceChange: timeout '
      'processingState=${_player.processingState}',
    );
  }

  /// Bumped when the user pauses and at the start of each [_resumePlaybackAfterLoad].
  /// In-flight [_ensurePlayingWithRetries] loops exit when this no longer matches
  /// their captured value so a user pause cannot be overwritten by a late [play].
  int _playControlGeneration = 0;

  void _invalidatePlayResumeRetries() {
    _playControlGeneration++;
  }

  /// Calls [play] until [AudioPlayer.playing] is true or attempts are exhausted.
  Future<void> _ensurePlayingWithRetries({
    required String context,
    required int generation,
    int attempts = 5,
  }) async {
    for (var i = 0; i < attempts; i++) {
      if (_playbackPausedByUser || _playControlGeneration != generation) return;
      try {
        if (_player.processingState == ProcessingState.completed) {
          await _player.seek(Duration.zero);
        }
        await _playSafely(context: context);
      } catch (e, st) {
        if (_isInterruptedAbort(e)) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
          continue;
        }
        debugPrint('$context attempt $i: $e\n$st');
      }
      // Wait longer between retries to avoid overwhelming the audio engine
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (_playbackPausedByUser || _playControlGeneration != generation) {
        return;
      }
      if (_player.playing) return;
    }
    debugPrint(
      '$context: still not playing (attempts exhausted); '
      'playing=${_player.playing} processingState=${_player.processingState}',
    );
  }

  PlayerController() {
    positionNotifier.attach();
    unawaited(_loadPersistedVolume());
    _audioSessionInit = _initAudioSessionInterruptions();
    // Single subscription: listening to [processingStateStream] and
    // [playerStateStream] both triggered platform init; concurrent inits caused
    // "Platform player … already exists" on some devices (just_audio / Android).
    _playerStateSub = _player.playerStateStream.listen((state) {
      _onProcessingState(state.processingState);
      final playing = state.playing;
      final proc = state.processingState;

      // When the player becomes paused (e.g. via notification button or auto-pause),
      // invalidate any in-flight retry loops so they don't overwrite the pause.
      // Ignore pauses caused by [_loadCurrent]'s stop() or manual skip seeks — those
      // emit playing=false after load and used to set [_playbackPausedByUser], so
      // [_resumePlaybackAfterLoad] never called [play] (songs appeared "stuck").
      // Natural track end reports playing=false + completed; must not look like a
      // user pause or repeat-one / skipNext will not call [play].
      if (!playing &&
          _lastDispatchedPlaying &&
          !_isLoadingSource &&
          !_manualQueueAdvance &&
          !_ignoreSpuriousTransportPause &&
          proc != ProcessingState.completed) {
        _invalidatePlayResumeRetries();
        _playbackPausedByUser = true;
        if (!kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS)) {
          unawaited(JustAudioBackground.ensureNativePaused());
        }
      }
      if (playing && !_lastDispatchedPlaying) {
        _playbackPausedByUser = false;
        unawaited(_activateAudioSessionForPlayback());
      }

      if (!_playerUiDispatchInitialized ||
          playing != _lastDispatchedPlaying ||
          proc != _lastDispatchedProcessing) {
        _playerUiDispatchInitialized = true;
        _lastDispatchedPlaying = playing;
        _lastDispatchedProcessing = proc;
        _schedulePlayerUiNotify();
      }
    });
    _concatIndexSub = _player.currentIndexStream.listen(_onConcatIndexChanged);
  }

  /// [just_audio] can subscribe to [AudioSession] interruptions internally, but
  /// we disable that and handle focus here so phone calls / mic use reliably pause
  /// and transient focus loss can resume after the call.
  final AudioPlayer _player = AudioPlayer(handleInterruptions: false);
  late final PositionNotifier positionNotifier = PositionNotifier(_player);
  final TrackNotifier track = TrackNotifier();
  final PlaybackNotifier playback = PlaybackNotifier();
  final QueueNotifier queue = QueueNotifier();

  /// List rows subscribe to retry art loads when disk/hot cache is filled.
  final ArtAvailabilityNotifier artAvailability = ArtAvailabilityNotifier();

  /// Track + playback + queue updates only (excludes [position] ticks).
  Listenable get uiListenable => Listenable.merge([track, playback, queue]);

  /// Play/pause and processing UI only.
  Listenable get playbackListenable => playback;

  /// Queue, shuffle, repeat, and upcoming-track UI.
  Listenable get queueListenable => queue;

  /// [canSkipNext] / [canSkipPrevious] depend on queue boundaries and current index.
  Listenable get trackAndQueueListenable => Listenable.merge([track, queue]);
  late final StreamSubscription<PlayerState> _playerStateSub;
  StreamSubscription<int?>? _concatIndexSub;
  StreamSubscription<AudioInterruptionEvent>? _audioInterruptionSub;
  StreamSubscription<void>? _becomingNoisySub;
  StreamSubscription<AudioDevicesChangedEvent>? _devicesChangedSub;
  Timer? _notificationArtRefreshDebounce;
  Timer? _notificationArtRetryTimer;
  int _notificationArtRetryCount = 0;
  static const int _kNotificationArtRetryMax = 8;
  bool _notificationArtRefreshInProgress = false;

  /// Set when the user explicitly pauses; blocks [_resumePlaybackAfterLoad] until play.
  bool _playbackPausedByUser = false;

  /// True when we paused because another app (or the OS) took transient audio focus
  /// (e.g. phone call). Cleared after we attempt resume.
  bool _shouldResumeAfterTransientFocusLoss = false;

  /// Playback queue as file paths; [TrackItem] rows resolve from [LibraryCatalog].
  List<String> _playlistPaths = [];
  List<TrackItem>? _playlistCache;
  int _index = 0;

  void _invalidatePlaylistCache() => _playlistCache = null;

  TrackItem _trackAt(int playlistIndex) {
    final path = _playlistPaths[playlistIndex];
    return _libraryCatalog.trackForPath(path) ?? TrackItem.fromFilePath(path);
  }

  void _setPlaylistPaths(List<String> paths) {
    _playlistPaths = List<String>.from(paths);
    _invalidatePlaylistCache();
  }

  void _assignPlaylistFromTracks(List<TrackItem> tracks) {
    _playlistPaths = [
      for (final t in tracks)
        if (t.filePath != null && t.filePath!.trim().isNotEmpty)
          t.filePath!.trim(),
    ];
    _invalidatePlaylistCache();
  }

  String? _pathAt(int playlistIndex) {
    if (playlistIndex < 0 || playlistIndex >= _playlistPaths.length) {
      return null;
    }
    return _playlistPaths[playlistIndex];
  }

  bool _anyQueuePath(bool Function(String path) test) =>
      _playlistPaths.any(test);

  static String? _pathForTrack(TrackItem track) {
    final p = track.filePath?.trim();
    if (p == null || p.isEmpty) return null;
    return p;
  }

  List<String> _pathsForTracks(List<TrackItem> tracks) => [
    for (final t in tracks)
      if (_pathForTrack(t) != null) _pathForTrack(t)!,
  ];

  static bool _sameQueuePaths(String a, String b) {
    final ka = canonicalMusicLibraryPathKey(a);
    final kb = canonicalMusicLibraryPathKey(b);
    if (ka.isNotEmpty && kb.isNotEmpty) return ka == kb;
    return a == b;
  }

  static bool _sameQueuePathAndTrack(String queuePath, TrackItem track) {
    final pb = _pathForTrack(track);
    if (pb == null) return false;
    return _sameQueuePaths(queuePath, pb);
  }

  bool _shuffle = false;
  List<int> _shuffleOrder = [];
  int _shufflePos = 0;

  PlaylistRepeatMode _repeat = PlaylistRepeatMode.off;
  ProcessingState? _previousProcessing;
  bool _isLoadingSource = false;
  int _loadCurrentDepth = 0;
  int? _pendingConcatIndexWhileLoading;

  /// After [setAudioSource], [currentIndexStream] can still emit `0` once loading
  /// ends even when [initialIndex] was non-zero — that would overwrite [_index] via
  /// [_onConcatIndexChanged]. Ignore that specific stray event for a short window.
  DateTime? _postLoadConcatGuardUntil;
  int? _postLoadExpectedConcatIndex;
  bool _sourceNeedsReload = false;

  /// Windows uses a single [AudioSource] for the current row only. After a successful
  /// [setAudioSource], this holds that file’s key so queue-only edits (reorder, play
  /// next, append) can skip reloading the same URI and avoid a multi-second gap.
  String? _loadedWindowsSingleTrackPathKey;

  /// After an on-disk rename, maps pre-rename [canonicalMusicLibraryPathKey] → new path.
  final Map<String, String> _libraryPathMigrations = {};

  /// While set, [_loadCurrent] uses this row for the logical track (post-rename reload).
  TrackItem? _loadCurrentPathOverride;

  /// While [skipNext]/[skipPrevious] update [_index] and reload/seek, ignore
  /// [currentIndexStream] so the UI is not advanced before audio catches up.
  bool _manualQueueAdvance = false;

  /// [AudioPlayer.stop] can report [ProcessingState.completed] on some platforms.
  /// That must not run [skipNext] while we only released the decoder for a disk edit.
  bool _suppressTrackCompletedAdvance = false;

  /// [processingStateStream] may deliver [ProcessingState.completed] late; ignore briefly
  /// after [stopForExternalFileEdit] even after [_suppressTrackCompletedAdvance] clears.
  DateTime? _ignoreSpuriousPlaybackCompletedUntil;

  /// When true, the next natural track completion pauses instead of advancing the queue.
  bool _stopAtTrackEndForSleepTimer = false;
  VoidCallback? _sleepTimerTrackEndNotifier;
  List<int> _activeSourceOrder = <int>[];
  ConcatenatingAudioSource? _concatSource;
  double _preferredVolume = 1.0;

  /// Whether the loaded [ConcatenatingAudioSource] can be mutated with [add]/[insert]/[removeAt].
  bool get _canMutateConcatInPlace =>
      !_useSingleTrackAudioSourceForPlatform() &&
      _concatSource != null &&
      !_sourceNeedsReload &&
      !_isLoadingSource;

  /// While rebuilding [ConcatenatingAudioSource] for shuffle, [AudioPlayer.stop] makes
  /// `playing` false briefly; UI uses [isPlaying] which ORs this in so play/pause
  /// doesn't flash (repeat never reloads the source, so it has no such gap).
  bool _retainPlayingUiForShuffleReload = false;

  /// Dedupes [repeat-one] replay when both [currentIndexStream] and completion fire.
  bool _repeatOneReplayScheduled = false;

  /// Load the current track first, then [add]/[insert] the rest in the background.
  static const int _fastStartConcatThreshold = 2;

  int _concatExpandGeneration = 0;

  /// Avoid rebuilding the whole app (Library lists, etc.) on every [playerStateStream]
  /// tick — only notify when play/pause or processing state actually changes.
  bool _playerUiDispatchInitialized = false;
  bool _lastDispatchedPlaying = false;
  ProcessingState _lastDispatchedProcessing = ProcessingState.idle;
  void _notifyCatalogListeners(CatalogNotifyMode mode) {
    switch (mode) {
      case CatalogNotifyMode.immediate:
        queue.notifyImmediate();
      case CatalogNotifyMode.throttled:
        queue.notifyThrottled();
    }
  }

  void _notifyTrack() => track.notifyNow();

  void _notifyPlayback() => playback.notifyCoalesced();

  void _notifyTrackAndPlayback() {
    _notifyTrack();
    _notifyPlayback();
  }

  void _notifyTrackPlaybackQueue() {
    _notifyTrack();
    _notifyPlayback();
    queue.notifyNow();
  }

  /// When non-null, [skipNext], [skipPrevious], [upcomingTrack], and repeat-all wrap
  /// only among tracks whose path key is in this set (same as Songs tab folder filter).
  Set<String>? _playbackPathKeysScope;

  /// Last full-library scan (Songs tab + metadata); not cleared when the queue is
  /// replaced by Favourites / a user playlist / etc.
  final LibraryCatalog _libraryCatalog = LibraryCatalog();

  /// Library tab where the current queue was started; used when closing Now Playing.
  LibraryTabId? _playbackOriginTab;

  /// When origin is [LibraryTabId.playlist], optional user-saved playlist to reopen.
  String? _playbackOriginUserPlaylistId;

  AudioPlayer get audioPlayer => _player;

  Stream<double> get volumeStream => _player.volumeStream;

  double get volume => _preferredVolume;

  Future<void> _loadPersistedVolume() async {
    final volume = await VolumeSettingsStore.load();
    _preferredVolume = volume;
    await _applyPreferredVolume();
    _notifyPlayback();
  }

  Future<void> _initAudioSessionInterruptions() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      await _audioInterruptionSub?.cancel();
      await _becomingNoisySub?.cancel();
      await _devicesChangedSub?.cancel();
      _audioInterruptionSub = session.interruptionEventStream.listen(
        _onAudioSessionInterruption,
      );
      _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
        _pauseForExternalOutputDisconnect();
      });
      _devicesChangedSub = session.devicesChangedEventStream.listen(
        _onAudioOutputDevicesChanged,
      );
    } catch (e, st) {
      debugPrint('Audio session interruption setup failed: $e\n$st');
    }
  }

  static bool _isBluetoothOutputDevice(AudioDevice device) {
    if (!device.isOutput) return false;
    switch (device.type) {
      case AudioDeviceType.bluetoothA2dp:
      case AudioDeviceType.bluetoothSco:
      case AudioDeviceType.bluetoothLe:
        return true;
      default:
        return false;
    }
  }

  void _onAudioOutputDevicesChanged(AudioDevicesChangedEvent event) {
    if (!_player.playing) return;
    if (event.devicesRemoved.any(_isBluetoothOutputDevice)) {
      _pauseForExternalOutputDisconnect();
    }
  }

  /// Headphones unplugged, Bluetooth A2DP lost, etc.
  void _pauseForExternalOutputDisconnect() {
    if (!_player.playing) return;
    _shouldResumeAfterTransientFocusLoss = false;
    _invalidatePlayResumeRetries();
    unawaited(_player.pause());
  }

  void _onAudioSessionInterruption(AudioInterruptionEvent event) {
    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.duck:
          break;
        case AudioInterruptionType.pause:
          if (_player.playing) {
            _shouldResumeAfterTransientFocusLoss = true;
            _invalidatePlayResumeRetries();
            unawaited(_player.pause());
          }
          break;
        case AudioInterruptionType.unknown:
          if (_player.playing) {
            _invalidatePlayResumeRetries();
            unawaited(_player.pause());
          }
          _shouldResumeAfterTransientFocusLoss = false;
          break;
      }
    } else {
      switch (event.type) {
        case AudioInterruptionType.duck:
          break;
        case AudioInterruptionType.pause:
          if (_shouldResumeAfterTransientFocusLoss) {
            _shouldResumeAfterTransientFocusLoss = false;
            unawaited(_playSafely(context: 'audioFocusResume'));
          }
          break;
        case AudioInterruptionType.unknown:
          _shouldResumeAfterTransientFocusLoss = false;
          break;
      }
    }
  }

  Future<void> _applyPreferredVolume() => _player.setVolume(_preferredVolume);

  Future<void> setVolume(double volume) async {
    final next = volume.clamp(0.0, 1.0).toDouble();
    _preferredVolume = next;
    await _player.setVolume(next);
    await VolumeSettingsStore.save(next);
    _notifyPlayback();
  }

  List<TrackItem> get libraryCatalog => _libraryCatalog.tracks;

  /// In-memory list art from [LibraryCatalog] hot LRU (no disk read).
  Uint8List? hotArtBytesForPath(String filePath, {int minPixelSize = 0}) {
    final key = canonicalMusicLibraryPathKey(filePath.trim());
    if (key.isEmpty) return null;
    return _libraryCatalog.hotArtBytesForPathKey(
      key,
      minPixelSize: minPixelSize,
    );
  }

  void promoteArtBytesForPath(
    String filePath,
    Uint8List art, {
    int pixelSize = 0,
  }) {
    final key = canonicalMusicLibraryPathKey(filePath.trim());
    if (key.isEmpty) return;
    evictPathAlbumArtMemory(filePath);
    _libraryCatalog.promoteArtBytes(key, art, pixelSize: pixelSize);
    markAlbumArtAvailable(filePath);
  }

  /// Signals that [filePath] has cover art in hot LRU and/or path disk cache.
  void markAlbumArtAvailable(String filePath) {
    final key = canonicalMusicLibraryPathKey(filePath.trim());
    if (key.isEmpty) return;
    artAvailability.markAvailable(key);
  }

  /// Clears list, notification, and hot LRU art for [filePath] (rename/delete).
  Future<void> evictArtCachesForPath(String filePath) async {
    final path = filePath.trim();
    if (path.isEmpty) return;
    final key = canonicalMusicLibraryPathKey(path);
    _libraryCatalog.evictArtHotAtPath(path);
    await evictPathAlbumArtCaches(path);
    await evictNotificationArtCacheForPath(path);
    await SongMetadataCache.clearArtDiskCacheFlagForPath(path);
    if (key.isNotEmpty) artAvailability.revoke(key);
  }

  /// Marks paths with valid Isar art-disk flags (no cache directory scan).
  Future<void> prefillArtAvailabilityFromDiskCache(
    Iterable<String> filePaths,
  ) async {
    final keys = await SongMetadataCache.pathKeysWithValidArtDiskCache(
      filePaths,
    );
    if (keys.isEmpty) return;
    artAvailability.beginBatch();
    artAvailability.markAvailableAll(keys);
    artAvailability.endBatch();
  }

  /// Use for tag resolution in Library: full scan when available, else active queue.
  List<TrackItem> get metadataLibrary =>
      _libraryCatalog.isNotEmpty ? _libraryCatalog.tracks : playlist;

  /// Path keys for the active queue (for O(1) library row ↔ queue mapping).
  List<String> get playlistPaths => List<String>.unmodifiable(_playlistPaths);

  LibraryTabId? get playbackOriginTab => _playbackOriginTab;

  /// Set when playback started from Library → Playlist and a user playlist sheet.
  String? get playbackOriginUserPlaylistId => _playbackOriginUserPlaylistId;

  /// Called after a folder scan with the complete track list.
  void setLibraryCatalog(
    List<TrackItem> tracks, {
    CatalogNotifyMode notify = CatalogNotifyMode.immediate,
  }) {
    _libraryCatalog.setAll(tracks);
    for (final t in tracks) {
      final art = t.albumArtBytes;
      final path = t.filePath?.trim();
      if (path != null && path.isNotEmpty && art != null && art.isNotEmpty) {
        markAlbumArtAvailable(path);
      }
    }
    if (_playlistPaths.isNotEmpty) _invalidatePlaylistCache();
    _notifyCatalogListeners(notify);
  }

  void removeFromLibraryCatalogByPath(String path) {
    if (path.isEmpty) return;
    if (_libraryCatalog.removeAtPath(path)) queue.notifyNow();
  }

  List<TrackItem> get playlist {
    final cached = _playlistCache;
    if (cached != null) return cached;
    final resolved = List<TrackItem>.generate(
      _playlistPaths.length,
      _trackAt,
      growable: false,
    );
    _playlistCache = List<TrackItem>.unmodifiable(resolved);
    return _playlistCache!;
  }

  /// Index into [playlist] for the currently playing file (list row / highlight).
  int get currentIndex {
    if (_playlistPaths.isEmpty) return 0;
    return _shuffle ? _shuffleOrder[_shufflePos] : _index;
  }

  TrackItem? get currentTrack => _playlistPaths.isEmpty
      ? null
      : _trackAt(currentIndex.clamp(0, _playlistPaths.length - 1));

  /// Track that will play after the current one ([skipNext] semantics), or `null`
  /// when nothing follows (end of queue without [PlaylistRepeatMode.all] wrap).
  TrackItem? get upcomingTrack {
    if (_playlistPaths.isEmpty) return null;
    if (_shuffle) {
      if (_shuffleOrder.isEmpty) return null;
      if (_shufflePos < _shuffleOrder.length - 1) {
        return _trackAt(_shuffleOrder[_shufflePos + 1]);
      }
      if (_repeat == PlaylistRepeatMode.all) {
        return _trackAt(_shuffleOrder.first);
      }
      return null;
    }

    final ordered = _playbackScopedIndices();
    if (ordered.isEmpty) return null;
    final p = ordered.indexOf(_index);

    /// Stale folder filter vs queue — fall back to full-library sequence once.
    if (p < 0) {
      if (_playbackPathKeysScope != null) {
        final n = _playlistPaths.length;
        final i = _index;
        if (i >= 0 && i < n - 1) {
          return _trackAt(i + 1);
        }
        if (_repeat == PlaylistRepeatMode.all) {
          return _trackAt(0);
        }
      }
      return null;
    }

    if (p < ordered.length - 1) {
      return _trackAt(ordered[p + 1]);
    }
    if (_repeat == PlaylistRepeatMode.all) {
      return _trackAt(ordered.first);
    }
    return null;
  }

  /// Whether [skipNext] will advance to another item (shuffle, scoped order,
  /// repeat-all). When false, skip only pauses or no-ops at the queue end.
  bool get canSkipNext => upcomingTrack != null;

  bool get shuffleEnabled => _shuffle;

  /// Playlist indices in the order the player will play them (respects shuffle and folder scope).
  List<int> get playbackOrderIndices => List<int>.from(_effectiveQueueOrder());

  /// Whether the queue tab may reorder rows.
  ///
  /// When a path-key scope is active but the queue contains tracks outside that
  /// scope, reorder is disabled — [reorderPlaybackQueue] only permutes the scoped
  /// playback order, which would not match the full playlist layout.
  bool get canReorderPlaybackQueue {
    if (_playlistPaths.length < 2) return false;
    if (_playbackPathKeysScope != null && !_shuffle) {
      for (var i = 0; i < _playlistPaths.length; i++) {
        if (!_playlistIndexMatchesScope(i)) return false;
      }
    }
    return true;
  }

  PlaylistRepeatMode get repeatMode => _repeat;

  /// Limits next/previous and repeat-all to tracks inside the scoped folder (see Files flow).
  ///
  /// When [reloadQueue] is false, only updates scope (and shuffle reset when scope is non-null).
  /// Call this before [setPlaylist]/[setPlaylistAndPlay] so a single [_loadCurrent] runs with
  /// the new queue instead of racing a reload that preserves the old playback position.
  void setPlaybackPathKeyScope(
    Set<String>? pathKeys, {
    bool reloadQueue = true,
  }) {
    _playbackPathKeysScope = pathKeys == null
        ? null
        : Set<String>.from(pathKeys);
    if (_playbackPathKeysScope != null) {
      _resetShuffleState();
    }
    _notifyTrackPlaybackQueue();
    if (!reloadQueue) return;
    unawaited(_loadCurrent(initialPosition: _player.position));
  }

  bool _playlistIndexMatchesScope(int i) {
    if (_playbackPathKeysScope == null) return true;
    if (i < 0 || i >= _playlistPaths.length) return false;
    final fp = _pathAt(i);
    if (fp == null || fp.trim().isEmpty) return false;
    final k = canonicalMusicLibraryPathKey(fp);
    return k.isNotEmpty && _playbackPathKeysScope!.contains(k);
  }

  List<int> _playbackScopedIndices() {
    final n = _playlistPaths.length;
    if (n == 0) return [];
    final scope = _playbackPathKeysScope;
    if (scope == null) {
      return List<int>.generate(n, (i) => i);
    }
    final out = <int>[];
    for (var i = 0; i < n; i++) {
      final fp = _pathAt(i);
      if (fp == null || fp.trim().isEmpty) continue;
      final k = canonicalMusicLibraryPathKey(fp);
      if (k.isNotEmpty && scope.contains(k)) {
        out.add(i);
      }
    }
    return out;
  }

  bool get isPlaying => _player.playing || _retainPlayingUiForShuffleReload;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;

  /// Resolves the app-wide [PlayerController] from [PlayerControllerScope].
  static PlayerController of(BuildContext context) =>
      PlayerControllerScope.of(context);

  void _onProcessingState(ProcessingState state) {
    if (_isLoadingSource) {
      _previousProcessing = state;
      return;
    }
    final enteredComplete =
        _previousProcessing != ProcessingState.completed &&
        state == ProcessingState.completed;
    final ignoreCompleted =
        _suppressTrackCompletedAdvance ||
        (_ignoreSpuriousPlaybackCompletedUntil != null &&
            DateTime.now().isBefore(_ignoreSpuriousPlaybackCompletedUntil!));
    if (enteredComplete && ignoreCompleted) {
      // Do not assign completed to [_previousProcessing] — would block real track-end.
      return;
    }
    _previousProcessing = state;
    if (enteredComplete) {
      // Use a short delay to avoid re-entrancy issues where calling player
      // methods from within a stream listener context crashes or no-ops.
      Future.delayed(const Duration(milliseconds: 50), () {
        if (_isLoadingSource) return;
        _handleTrackCompleted();
      });
    }
  }

  void setStopAtTrackEndForSleepTimer(bool enabled) {
    _stopAtTrackEndForSleepTimer = enabled;
  }

  void registerSleepTimerTrackEndNotifier(VoidCallback? notifier) {
    _sleepTimerTrackEndNotifier = notifier;
  }

  Future<void> _handleTrackCompleted() async {
    if (_suppressTrackCompletedAdvance || _isLoadingSource) return;
    if (_playlistPaths.isEmpty) return;
    if (_stopAtTrackEndForSleepTimer) {
      debugPrint('Sleep timer (end of song) triggered by natural completion');
      _stopAtTrackEndForSleepTimer = false;
      final notifier = _sleepTimerTrackEndNotifier;
      _sleepTimerTrackEndNotifier = null;
      notifier?.call();

      try {
        _invalidatePlayResumeRetries();
        await _player.pause();
      } catch (e) {
        debugPrint('Sleep timer natural stop failed: $e');
      }

      _notifyTrackAndPlayback();
      return;
    }
    if (_repeat == PlaylistRepeatMode.one) {
      final concatIndex = _concatIndexForLogical(_logicalPlaylistIndex());
      if (concatIndex != null) {
        _scheduleRepeatOneReplay(concatIndex);
      } else {
        unawaited(_replayCurrentTrackAtStart(context: 'repeat-one play'));
      }
      return;
    }
    if (_sourceNeedsReload) {
      await _rebuildAudioSourceForQueueMutation();
    }
    await skipNext();
  }

  void _resetShuffleState() {
    _shuffle = false;
    _shuffleOrder = [];
    _shufflePos = 0;
  }

  bool _isNativeShuffleIndexRangeError(Object e) {
    if (e is! RangeError) return false;
    final msg = e.toString();
    return msg.contains('Not in inclusive range') ||
        msg.contains('Invalid value');
  }

  void _sanitizeShuffleState() {
    if (!_shuffle || _playlistPaths.isEmpty) return;
    final n = _playlistPaths.length;
    final valid = _shuffleOrder.where((i) => i >= 0 && i < n).toList();
    if (valid.length != n) {
      final cur = _index.clamp(0, n - 1);
      final order = List<int>.generate(n, (j) => j)..shuffle();
      order.remove(cur);
      _shuffleOrder = [cur, ...order];
    } else {
      _shuffleOrder = valid;
    }
    _shufflePos = _shufflePos.clamp(0, _shuffleOrder.length - 1);
    _index = _shuffleOrder[_shufflePos].clamp(0, n - 1);
  }

  Future<void> _prepareAudioSourceLoad() async {
    _concatExpandGeneration++;
    _sanitizeShuffleState();
  }

  /// Serializes [setAudioSource] so tag reload / concat expand cannot interrupt
  /// each other ("Loading interrupted").
  Future<void>? _exclusiveSourceTail;

  Future<T> _runExclusiveSourceMutation<T>(Future<T> Function() action) async {
    final previous = _exclusiveSourceTail ?? Future<void>.value();
    final gate = Completer<void>();
    _exclusiveSourceTail = gate.future;
    await previous;
    try {
      return await action();
    } finally {
      if (!gate.isCompleted) gate.complete();
    }
  }

  /// Cancels in-flight concat expansion and waits for the native player to settle.
  Future<void> _stabilizePlayerBeforeSourceMutation({
    bool stopPlayer = true,
  }) async {
    _concatExpandGeneration++;
    _concatSource = null;
    if (stopPlayer) {
      try {
        await _player.stop();
      } catch (_) {}
    }
    final deadline = DateTime.now().add(const Duration(milliseconds: 700));
    while (DateTime.now().isBefore(deadline)) {
      final ps = _player.processingState;
      if (ps != ProcessingState.loading) {
        await Future<void>.delayed(const Duration(milliseconds: 35));
        if (_player.processingState != ProcessingState.loading) return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 45));
    }
  }

  Future<void> _setPlayerAudioSource(
    AudioSource source, {
    int? initialIndex,
    required Duration initialPosition,
    String context = 'setAudioSource',
    bool stopBeforeLoad = true,
  }) async {
    await _runExclusiveSourceMutation(() async {
      for (var attempt = 0; attempt < 4; attempt++) {
        try {
          await _stabilizePlayerBeforeSourceMutation(
            stopPlayer: stopBeforeLoad || attempt > 0,
          );
          if (initialIndex != null) {
            await _player.setAudioSource(
              source,
              initialIndex: initialIndex,
              initialPosition: initialPosition,
            );
          } else {
            await _player.setAudioSource(
              source,
              initialPosition: initialPosition,
            );
          }
          return;
        } catch (e, st) {
          if (_isInterruptedAbort(e) && attempt < 3) {
            await Future<void>.delayed(
              Duration(milliseconds: 100 * (attempt + 1)),
            );
            continue;
          }
          debugPrint('$context: $e\n$st');
          rethrow;
        }
      }
    });
  }

  /// After tag edit / failed reload the handler can still reference a shrunken
  /// concat; reload one track without [ConcatenatingAudioSource] shuffle state.
  Future<bool> _recoverFromBrokenNativeShuffle({
    required Duration initialPosition,
    required bool resumePlaying,
    String context = 'shuffleRecovery',
  }) async {
    if (_playlistPaths.isEmpty) return false;
    debugPrint('$context: rebuilding single-track source');
    _concatExpandGeneration++;
    _concatSource = null;
    _activeSourceOrder = <int>[];
    try {
      await _player.stop();
    } catch (_) {}
    await _reloadPlayingTrackOnly(
      initialPosition: initialPosition,
      resumePlaying: resumePlaying,
      context: context,
      allowShuffleRecovery: false,
    );
    return true;
  }

  /// Playback order mirrored as [ConcatenatingAudioSource] children (shuffle or scoped).
  List<int> _effectiveQueueOrder() {
    if (_playlistPaths.isEmpty) return [];
    if (_shuffle) return List<int>.from(_shuffleOrder);
    final scoped = _playbackScopedIndices();
    if (scoped.isNotEmpty) return scoped;
    return List<int>.generate(_playlistPaths.length, (i) => i);
  }

  int _logicalPlaylistIndex() {
    if (!_shuffle || _shuffleOrder.isEmpty) {
      return _index.clamp(
        0,
        _playlistPaths.isEmpty ? 0 : _playlistPaths.length - 1,
      );
    }
    return _shuffleOrder[_shufflePos.clamp(0, _shuffleOrder.length - 1)].clamp(
      0,
      _playlistPaths.isEmpty ? 0 : _playlistPaths.length - 1,
    );
  }

  /// When the native player is still serving the same file as [currentTrack], queue
  /// mutations do not need [setAudioSource] on Windows (single-track workaround).
  bool _windowsSingleTrackReloadWouldBeNoOp() {
    if (!_useSingleTrackAudioSourceForPlatform()) return false;
    if (_loadCurrentPathOverride != null) return false;
    final loaded = _loadedWindowsSingleTrackPathKey;
    if (loaded == null || loaded.isEmpty) return false;
    final cur = currentTrack;
    final fp = cur?.filePath?.trim();
    if (fp == null || fp.isEmpty) return false;
    final resolved = _resolveMigratedFilePath(fp);
    return canonicalMusicLibraryPathKey(resolved) == loaded;
  }

  /// Syncs in-memory concat bookkeeping with the queue without touching the decoder.
  /// Returns `true` when the reload was skipped.
  bool _skipWindowsSingleTrackReloadIfCurrentUnchanged() {
    if (!_windowsSingleTrackReloadWouldBeNoOp()) return false;
    final logical = _logicalPlaylistIndex();
    if (_playlistPaths.isEmpty ||
        logical < 0 ||
        logical >= _playlistPaths.length) {
      return false;
    }
    _concatExpandGeneration++;
    _activeSourceOrder = [logical];
    _sourceNeedsReload = false;
    _notifyTrackPlaybackQueue();
    positionNotifier.flush();
    return true;
  }

  bool _applyConcatIndexChanged(int concatIdx) {
    if (_playlistPaths.isEmpty) return false;
    final order = _activeSourceOrder.isNotEmpty
        ? _activeSourceOrder
        : _effectiveQueueOrder();
    if (concatIdx < 0 || concatIdx >= order.length) return false;
    final pl = order[concatIdx];

    if (_shuffle) {
      final nextShufflePos = _shuffleOrder.indexOf(pl);
      if (nextShufflePos < 0) return false;
      if (_shufflePos == nextShufflePos && _index == pl) return false;
      _shufflePos = nextShufflePos;
      _index = pl;
    } else {
      if (_index == pl) return false;
      _index = pl;
    }
    return true;
  }

  List<int> _activeQueueOrder() => _activeSourceOrder.isNotEmpty
      ? _activeSourceOrder
      : _effectiveQueueOrder();

  int? _concatIndexForLogical(int logical) {
    final order = _activeQueueOrder();
    final idx = order.indexOf(logical);
    return idx >= 0 ? idx : null;
  }

  Future<AudioSource?> _audioSourceForPlaylistIndex(
    int playlistIndex, {
    Map<int, Uri?>? notificationArtUris,
    bool resolveArtUri = true,
  }) async {
    if (playlistIndex < 0 || playlistIndex >= _playlistPaths.length)
      return null;
    final logical = _logicalPlaylistIndex();
    final t = playlistIndex == logical && _loadCurrentPathOverride != null
        ? _loadCurrentPathOverride!
        : _trackAt(playlistIndex);
    final fp = t.filePath?.trim();
    if (fp == null || fp.isEmpty) return null;
    final resolved = _resolveMigratedFilePath(fp);
    Uri? artUri;
    if (notificationArtUris != null &&
        notificationArtUris.containsKey(playlistIndex)) {
      artUri = notificationArtUris[playlistIndex];
    } else if (resolveArtUri) {
      artUri = await uriForNotificationAlbumArt(t);
    }
    return AudioSource.uri(
      Uri.file(resolved),
      tag: MediaItem(
        id: resolved,
        title: t.title,
        artist: t.artist,
        album: t.metaLine,
        artUri: artUri,
      ),
    );
  }

  /// Appends [playlistIndices] to the live concat (playback order), updating [_activeSourceOrder].
  Future<bool> _appendPlaylistIndicesToConcat(List<int> playlistIndices) async {
    if (!_canMutateConcatInPlace || playlistIndices.isEmpty) return false;
    final sources = <AudioSource>[];
    final indices = <int>[];
    try {
      for (final pi in playlistIndices) {
        final source = await _audioSourceForPlaylistIndex(pi);
        if (source == null) continue;
        sources.add(source);
        indices.add(pi);
      }
      if (sources.isEmpty) return false;
      await _concatSource!.addAll(sources);
      _activeSourceOrder.addAll(indices);
      return true;
    } catch (e, st) {
      debugPrint('_appendPlaylistIndicesToConcat: $e\n$st');
      return false;
    }
  }

  Future<bool> _removeConcatChildAtPlaylistIndex(int playlistIndex) async {
    if (!_canMutateConcatInPlace) return false;
    final concatIdx = _activeSourceOrder.indexOf(playlistIndex);
    if (concatIdx < 0) return false;
    try {
      await _concatSource!.removeAt(concatIdx);
      _activeSourceOrder.removeAt(concatIdx);
      return true;
    } catch (e, st) {
      debugPrint('_removeConcatChildAtPlaylistIndex: $e\n$st');
      return false;
    }
  }

  void _deferMetadataEnrichForPlaylistIndex(int logical) {
    if (logical < 0 || logical >= _playlistPaths.length) return;
    final track = _trackAt(logical);
    final enrichPath = track.filePath?.trim();
    if (enrichPath == null || enrichPath.isEmpty) return;
    if (track.albumArtBytes != null && track.albumArtBytes!.isNotEmpty) {
      return;
    }
    unawaited(() async {
      try {
        final enriched = await readAudioMetadata(track);
        if (enriched.albumArtBytes != null &&
            enriched.albumArtBytes!.isNotEmpty) {
          updateTrackByPath(
            enrichPath,
            enriched,
            refreshNotificationArt: false,
          );
        }
      } catch (e, st) {
        debugPrint('_deferMetadataEnrichForPlaylistIndex: $e\n$st');
      }
    }());
  }

  Future<void> _expandConcatToFullOrder(
    List<int> fullOrder,
    int logical,
  ) async {
    final gen = ++_concatExpandGeneration;
    final concat = _concatSource;
    if (concat == null) return;
    final pos = fullOrder.indexOf(logical);
    if (pos < 0) return;

    for (var i = pos - 1; i >= 0; i--) {
      if (gen != _concatExpandGeneration || _concatSource != concat) return;
      final pi = fullOrder[i];
      final source = await _audioSourceForPlaylistIndex(
        pi,
        resolveArtUri: false,
      );
      if (source == null) continue;
      try {
        await concat.insert(0, source);
        _activeSourceOrder.insert(0, pi);
      } catch (e, st) {
        debugPrint('_expandConcatToFullOrder insert: $e\n$st');
        return;
      }
      if (i % 8 == 0) await Future<void>.delayed(Duration.zero);
    }

    for (var i = pos + 1; i < fullOrder.length; i++) {
      if (gen != _concatExpandGeneration || _concatSource != concat) return;
      final pi = fullOrder[i];
      final source = await _audioSourceForPlaylistIndex(
        pi,
        resolveArtUri: false,
      );
      if (source == null) continue;
      try {
        await concat.add(source);
        _activeSourceOrder.add(pi);
      } catch (e, st) {
        debugPrint('_expandConcatToFullOrder add: $e\n$st');
        return;
      }
      if (i % 16 == 0) await Future<void>.delayed(Duration.zero);
    }
    _scheduleNotificationArtRefresh();
  }

  Future<void> _loadCurrentFastStart({
    required int logical,
    required List<int> sourceOrder,
    required Duration initialPosition,
  }) async {
    _deferMetadataEnrichForPlaylistIndex(logical);
    final source = await _audioSourceForPlaylistIndex(
      logical,
      resolveArtUri: false,
    );
    if (source == null) {
      debugPrint(
        '_loadCurrentFastStart: no AudioSource for playlist index $logical',
      );
      return;
    }
    final concat = ConcatenatingAudioSource(
      useLazyPreparation: _concatUseLazyPreparationForPlatform(),
      children: [source],
    );
    _activeSourceOrder = [logical];
    await _prepareAudioSourceLoad();
    await _setPlayerAudioSource(
      concat,
      initialIndex: 0,
      initialPosition: initialPosition,
      context: '_loadCurrentFastStart',
      stopBeforeLoad: false,
    );
    _concatSource = concat;
    await _applyPreferredVolume();
    _postLoadExpectedConcatIndex = 0;
    _postLoadConcatGuardUntil = DateTime.now().add(
      const Duration(milliseconds: 650),
    );
    _sourceNeedsReload = false;
    debugPrint(
      '_loadCurrentFastStart: playing index $logical, expanding '
      '${sourceOrder.length - 1} more tracks in background',
    );
    unawaited(_expandConcatToFullOrder(sourceOrder, logical));
  }

  bool _isConcatAutoAdvance(int concatIdx) {
    final currentConcatIdx = _concatIndexForLogical(_logicalPlaylistIndex());
    return currentConcatIdx != null && concatIdx != currentConcatIdx;
  }

  void _scheduleRepeatOneReplay(int concatIndex) {
    if (_repeatOneReplayScheduled) return;
    _repeatOneReplayScheduled = true;
    Future.delayed(const Duration(milliseconds: 20), () {
      _repeatOneReplayScheduled = false;
      unawaited(
        _replayCurrentTrackAtStart(
          context: 'repeat-one replay',
          concatIndex: concatIndex,
        ),
      );
    });
  }

  Future<void> _replayCurrentTrackAtStart({
    required String context,
    int? concatIndex,
  }) async {
    if (_suppressTrackCompletedAdvance || _isLoadingSource) return;
    if (_playlistPaths.isEmpty || _repeat != PlaylistRepeatMode.one) return;
    if (_stopAtTrackEndForSleepTimer) return;

    _playbackPausedByUser = false;
    final idx = concatIndex ?? _concatIndexForLogical(_logicalPlaylistIndex());
    final useConcatIndex =
        idx != null &&
        _concatSource != null &&
        !_useSingleTrackAudioSourceForPlatform();
    try {
      if (useConcatIndex) {
        await _player.seek(Duration.zero, index: idx);
      } else {
        await _player.seek(Duration.zero);
      }
      await _waitForPlayerPreparedAfterSourceChange();
      final proc = _player.processingState;
      _previousProcessing = proc == ProcessingState.completed
          ? ProcessingState.ready
          : proc;
      await _playSafely(context: context);
      positionNotifier.flush();
      _notifyTrackAndPlayback();
    } catch (e, st) {
      debugPrint('$context failed: $e\n$st');
    }
  }

  void _onConcatIndexChanged(int? concatIdx) {
    if (concatIdx == null) return;
    if (_manualQueueAdvance) return;

    if (_postLoadConcatGuardUntil != null &&
        !DateTime.now().isBefore(_postLoadConcatGuardUntil!)) {
      _postLoadConcatGuardUntil = null;
      _postLoadExpectedConcatIndex = null;
    }
    if (_isLoadingSource) {
      _pendingConcatIndexWhileLoading = concatIdx;
      return;
    }
    if (_postLoadConcatGuardUntil != null &&
        DateTime.now().isBefore(_postLoadConcatGuardUntil!) &&
        _postLoadExpectedConcatIndex != null &&
        concatIdx == 0 &&
        _postLoadExpectedConcatIndex != 0) {
      return;
    }

    // Sleep timer "end of song": ConcatenatingAudioSource auto-advances to the
    // next index before ProcessingState.completed arrives, so intercept the
    // advance here and pause before the new track starts.
    if (_stopAtTrackEndForSleepTimer) {
      final order = _activeSourceOrder.isNotEmpty
          ? _activeSourceOrder
          : _effectiveQueueOrder();
      final currentConcatIdx = order.indexOf(_logicalPlaylistIndex());
      final isAutoAdvance =
          currentConcatIdx >= 0 && concatIdx != currentConcatIdx;
      if (isAutoAdvance) {
        debugPrint(
          'Sleep timer (end of song) intercepting auto-advance: '
          'from $currentConcatIdx to $concatIdx',
        );
        _stopAtTrackEndForSleepTimer = false;
        final notifier = _sleepTimerTrackEndNotifier;
        _sleepTimerTrackEndNotifier = null;
        notifier?.call();

        // Authoritative pause and seek back to the end of the previous track
        // so we don't start playing the next one in the background.
        // We use a delay to exit the current stream listener context and avoid
        // "Bad state: Cannot fire new event" while ensure player state has settled.
        Future.delayed(const Duration(milliseconds: 20), () async {
          try {
            _invalidatePlayResumeRetries();
            // Force pause at the platform level bypassing the transport lock.
            await _player.pause();

            // Re-sync logical index if the auto-advance had already moved it
            _applyConcatIndexChanged(currentConcatIdx);

            // Seek to the end of the finish song to ensure we aren't at the
            // beginning of the NEXT song. We seek to the actual duration instead
            // of a placeholder like '1 day' to avoid '1440:00' timer display issues.
            final trackDur = _player.duration;
            if (trackDur != null && trackDur > Duration.zero) {
              await _player.seek(trackDur, index: currentConcatIdx);
            } else {
              // Fallback if duration isn't available yet
              await _player.seek(
                const Duration(seconds: 1),
                index: currentConcatIdx,
              );
            }

            // Final safety pause.
            await _player.pause();
            _notifyTrackAndPlayback();
          } catch (e) {
            debugPrint('Sleep timer stop failed: $e');
          }
        });

        _notifyTrackAndPlayback();
        return;
      }
    }

    // Repeat-one: concat auto-advances before [ProcessingState.completed]. Must run
    // before the [_sourceNeedsReload] guard — auto-advance changes concatIdx.
    if (_repeat == PlaylistRepeatMode.one && _isConcatAutoAdvance(concatIdx)) {
      final currentConcatIdx = _concatIndexForLogical(_logicalPlaylistIndex());
      if (currentConcatIdx != null) {
        _scheduleRepeatOneReplay(currentConcatIdx);
        return;
      }
    }

    // Queue was edited (play next, reorder) but native children are stale until reload.
    if (_sourceNeedsReload) {
      final order = _activeSourceOrder.isNotEmpty
          ? _activeSourceOrder
          : _effectiveQueueOrder();
      final logical = _logicalPlaylistIndex();
      final expectedConcatIdx = order.indexOf(logical);
      if (expectedConcatIdx < 0 || concatIdx != expectedConcatIdx) {
        return;
      }
    }

    if (_applyConcatIndexChanged(concatIdx)) {
      unawaited(_syncUiAfterQueueIndexChange());
    }
  }

  /// Notify UI after the native player has prepared the new queue index.
  Future<void> _syncUiAfterQueueIndexChange() async {
    if (_manualQueueAdvance) return;
    await _waitForPlayerPreparedAfterSourceChange();
    _prewarmPlaybackAlbumArt();
    _scheduleNotificationArtRefresh();
    _notifyTrackPlaybackQueue();
  }

  void _prewarmPlaybackAlbumArt() {
    final tracks = <TrackItem>[
      if (currentTrack != null) currentTrack!,
      if (upcomingTrack != null) upcomingTrack!,
    ];
    if (tracks.isEmpty) return;
    prewarmAlbumArtCache(
      tracks,
      maxCount: tracks.length,
      maxDimension: kAlbumArtPrimeDimension,
    );
  }

  /// During [setAudioSource] with lazy preparation, [currentIndexStream] can briefly
  /// report index `0`. That value is queued as [_pendingConcatIndexWhileLoading] and
  /// would otherwise overwrite [_index] in [_loadCurrent]'s `finally`, switching the
  /// queue to the wrong song (e.g. after tag / cover edits that reload the source).
  bool _pendingConcatIndexMatchesLoadedPath(
    int concatIdx,
    String loadTargetKey,
  ) {
    if (loadTargetKey.isEmpty) return true;
    final order = _activeSourceOrder.isNotEmpty
        ? _activeSourceOrder
        : _effectiveQueueOrder();
    if (concatIdx < 0 || concatIdx >= order.length) return false;
    final pl = order[concatIdx];
    if (pl < 0 || pl >= _playlistPaths.length) return false;
    final fp = _pathAt(pl)?.trim();
    if (fp == null || fp.isEmpty) return false;
    return canonicalMusicLibraryPathKey(fp) == loadTargetKey;
  }

  Future<void> setPlaylist(
    List<TrackItem> tracks, {
    int startIndex = 0,
    LibraryTabId? playbackOriginTab,
    String? playbackOriginUserPlaylistId,
    bool keepShuffleMode = false,
    bool enableShuffle = false,
  }) async {
    if (playbackOriginTab != null) {
      _playbackOriginTab = playbackOriginTab;
      _playbackOriginUserPlaylistId = playbackOriginTab == LibraryTabId.playlist
          ? playbackOriginUserPlaylistId
          : null;
    }
    final preserveShuffle = keepShuffleMode && _shuffle && tracks.length > 1;
    _assignPlaylistFromTracks(tracks);
    _index = _playlistPaths.isEmpty
        ? 0
        : startIndex.clamp(0, _playlistPaths.length - 1);
    if (preserveShuffle) {
      final cur = _index;
      final order = List<int>.generate(_playlistPaths.length, (j) => j)
        ..shuffle();
      order.remove(cur);
      _shuffleOrder = [cur, ...order];
      _shufflePos = 0;
      _shuffle = true;
    } else if (enableShuffle && tracks.length > 1) {
      final cur = _index;
      final order = List<int>.generate(_playlistPaths.length, (j) => j)
        ..shuffle();
      order.remove(cur);
      _shuffleOrder = [cur, ...order];
      _shufflePos = 0;
      _shuffle = true;
    } else {
      _resetShuffleState();
    }
    _notifyTrackPlaybackQueue();
    await _loadCurrent();
    _sourceNeedsReload = false;
  }

  /// Canonical path key for matching library scan rows after an on-disk rename.
  String libraryPathKeyForScanMatch(String rawPath) {
    final k = canonicalMusicLibraryPathKey(rawPath);
    if (k.isEmpty) return k;
    return _resolveMigratedLibraryPathKey(k);
  }

  /// Call as soon as the file is renamed on disk so concurrent loads resolve the new path.
  void registerLibraryPathRename(String oldPath, String newPath) {
    _registerLibraryPathMigration(oldPath, newPath);
    _syncPlaylistPathsFromMigrations();
    _notifyTrackPlaybackQueue();
  }

  void _registerLibraryPathMigration(String oldPath, String newPath) {
    final oldKey = canonicalMusicLibraryPathKey(oldPath);
    final newKey = canonicalMusicLibraryPathKey(newPath);
    if (oldKey.isEmpty || newKey.isEmpty || oldKey == newKey) return;
    _libraryPathMigrations[oldKey] = kIsWeb
        ? newPath.trim()
        : _normalizeLocalFilePath(newPath);
  }

  String _normalizeLocalFilePath(String path) {
    try {
      return File(path.trim()).absolute.path;
    } catch (_) {
      return path.trim();
    }
  }

  String _resolveMigratedFilePath(String rawPath) {
    var key = canonicalMusicLibraryPathKey(rawPath);
    if (key.isEmpty) return rawPath.trim();
    final seen = <String>{};
    var resolved = rawPath.trim();
    while (_libraryPathMigrations.containsKey(key)) {
      if (!seen.add(key)) break;
      resolved = _libraryPathMigrations[key]!;
      key = canonicalMusicLibraryPathKey(resolved);
    }
    return resolved;
  }

  String _resolveMigratedLibraryPathKey(String pathKey) {
    return canonicalMusicLibraryPathKey(_resolveMigratedFilePath(pathKey));
  }

  void _syncPlaylistPathsFromMigrations() {
    if (_libraryPathMigrations.isEmpty) return;
    var changed = false;
    for (var i = 0; i < _playlistPaths.length; i++) {
      final fp = _playlistPaths[i].trim();
      if (fp.isEmpty) continue;
      final migrated = _resolveMigratedFilePath(fp);
      if (migrated != fp) {
        _playlistPaths[i] = migrated;
        changed = true;
      }
    }
    if (changed) _invalidatePlaylistCache();
  }

  TrackItem? _catalogTrackForPathKey(
    String pathKey,
    Map<String, TrackItem> byKey,
  ) {
    if (pathKey.isEmpty) return null;
    final direct = byKey[pathKey];
    if (direct != null) return direct;
    final migrated = _resolveMigratedLibraryPathKey(pathKey);
    if (migrated != pathKey) return byKey[migrated];
    return null;
  }

  /// Updates library rows and in-queue metadata after a rescan without reloading
  /// [AudioPlayer]'s source — use for manual refresh while music is playing.
  ///
  /// Returns `true` when playback was left untouched (Songs-origin queue). Returns
  /// `false` when the caller should use [tryResyncQueueWithLibraryScan] instead.
  bool refreshLibraryDuringPlayback(List<TrackItem> catalogTracks) {
    final origin = _playbackOriginTab;
    if (origin != null && origin != LibraryTabId.songs) {
      return false;
    }
    if (_playlistPaths.isEmpty) return false;

    final byKey = <String, TrackItem>{};
    for (final t in catalogTracks) {
      final fp = t.filePath?.trim();
      if (fp == null || fp.isEmpty) continue;
      final k = canonicalMusicLibraryPathKey(fp);
      if (k.isNotEmpty) byKey[k] = t;
    }
    if (byKey.isEmpty) return true;

    var changed = false;
    for (final path in _playlistPaths) {
      final k = canonicalMusicLibraryPathKey(path);
      if (k.isEmpty) continue;
      if (_catalogTrackForPathKey(k, byKey) != null) {
        changed = true;
        break;
      }
    }
    if (changed) {
      _invalidatePlaylistCache();
      queue.notifyNow();
    }
    return true;
  }

  /// After a disk scan, replace the queue with [tracks] when playback was started from
  /// the main Songs library (full-library queue). Preserves the current file, playback
  /// position, playing/paused state, and shuffle mode (rebuilding shuffle so new indices
  /// are included). No-op when playback was started from another tab (playlist, favourites,
  /// etc.) so those queues are not replaced by the full library scan.
  Future<void> tryResyncQueueWithLibraryScan(
    List<TrackItem> tracks, {
    required Duration resumePosition,
    required bool resumePlaying,
  }) async {
    final origin = _playbackOriginTab;
    if (origin != null && origin != LibraryTabId.songs) {
      return;
    }
    if (tracks.isEmpty) {
      await setPlaylist(
        [],
        startIndex: 0,
        playbackOriginTab: LibraryTabId.songs,
      );
      return;
    }

    final newPaths = _pathsForTracks(tracks);
    if (listEquals(_playlistPaths, newPaths)) return;

    final pathPreserve = currentTrack?.filePath?.trim();
    final keepShuffle = _shuffle && tracks.length > 1;
    _assignPlaylistFromTracks(tracks);

    var newIndex = 0;
    if (pathPreserve != null && pathPreserve.isNotEmpty) {
      final preserveKey = libraryPathKeyForScanMatch(pathPreserve);
      if (preserveKey.isNotEmpty) {
        final ix = _playlistPaths.indexWhere(
          (p) => libraryPathKeyForScanMatch(p) == preserveKey,
        );
        if (ix >= 0) newIndex = ix;
      }
    }

    if (keepShuffle) {
      final cur = newIndex;
      final order = List<int>.generate(_playlistPaths.length, (j) => j)
        ..shuffle();
      order.remove(cur);
      _shuffleOrder = [cur, ...order];
      _shufflePos = 0;
      _index = cur;
      _shuffle = true;
    } else {
      _resetShuffleState();
      _index = newIndex;
    }

    _notifyTrackPlaybackQueue();
    await _loadCurrent(initialPosition: resumePosition, stopBeforeLoad: false);
    _sourceNeedsReload = false;
    if (resumePlaying) {
      await _guardedTransport(() async {
        _playbackPausedByUser = false;
        await _resumePlaybackAfterLoad(
          context: 'tryResyncQueueWithLibraryScan.play',
        );
      });
    } else {
      await pause();
    }
  }

  /// Appends [items] to the current queue. If the queue was empty, loads and starts
  /// playback at the first appended item.
  ///
  /// Shuffle is turned off so indices stay consistent (current song keeps playing).
  Future<void> appendToPlaylist(List<TrackItem> items) async {
    if (items.isEmpty) return;
    final wasEmpty = _playlistPaths.isEmpty;
    final resumePos = wasEmpty ? Duration.zero : _player.position;
    if (_shuffle && _playlistPaths.isNotEmpty) {
      _index = _shuffleOrder[_shufflePos].clamp(0, _playlistPaths.length - 1);
      _shuffle = false;
      _shuffleOrder = [];
      _shufflePos = 0;
    }
    final oldLen = _playlistPaths.length;
    _playlistPaths = [..._playlistPaths, ..._pathsForTracks(items)];
    _invalidatePlaylistCache();
    _notifyTrackPlaybackQueue();
    if (wasEmpty) {
      _index = 0;
      await _guardedTransport(() async {
        await _loadCurrent();
        await _resumePlaybackAfterLoad(context: 'appendToPlaylist.play');
      });
      return;
    }
    final newIndices = List<int>.generate(items.length, (i) => oldLen + i);
    final order = _effectiveQueueOrder();
    final toAppend = order.where(newIndices.contains).toList();
    if (await _appendPlaylistIndicesToConcat(toAppend)) {
      return;
    }
    if (_skipWindowsSingleTrackReloadIfCurrentUnchanged()) return;
    final resumeAfterReload = _player.playing && !_playbackPausedByUser;
    await _guardedTransport(() async {
      await _loadCurrent(initialPosition: resumePos, stopBeforeLoad: false);
      if (resumeAfterReload) {
        _playbackPausedByUser = false;
        await _resumePlaybackAfterLoad(
          context: 'appendToPlaylist.resumeAfterReload',
        );
      }
    });
  }

  /// Sets the queue from [paths] (tags resolved from [LibraryCatalog]) and loads audio.
  Future<void> setPlaylistPaths(
    List<String> paths, {
    int startIndex = 0,
    LibraryTabId? playbackOriginTab,
    String? playbackOriginUserPlaylistId,
    bool keepShuffleMode = false,
    bool enableShuffle = false,
  }) async {
    if (playbackOriginTab != null) {
      _playbackOriginTab = playbackOriginTab;
      _playbackOriginUserPlaylistId = playbackOriginTab == LibraryTabId.playlist
          ? playbackOriginUserPlaylistId
          : null;
    }
    final trackCount = paths.length;
    final preserveShuffle = keepShuffleMode && _shuffle && trackCount > 1;
    _setPlaylistPaths(paths);
    _index = _playlistPaths.isEmpty
        ? 0
        : startIndex.clamp(0, _playlistPaths.length - 1);
    if (preserveShuffle) {
      final cur = _index;
      final order = List<int>.generate(_playlistPaths.length, (j) => j)
        ..shuffle();
      order.remove(cur);
      _shuffleOrder = [cur, ...order];
      _shufflePos = 0;
      _shuffle = true;
    } else if (enableShuffle && trackCount > 1) {
      final cur = _index;
      final order = List<int>.generate(_playlistPaths.length, (j) => j)
        ..shuffle();
      order.remove(cur);
      _shuffleOrder = [cur, ...order];
      _shufflePos = 0;
      _shuffle = true;
    } else {
      _resetShuffleState();
    }
    _notifyTrackPlaybackQueue();
    await _loadCurrent();
    _sourceNeedsReload = false;
  }

  /// Replaces the queue with [tracks] and starts playback at [startIndex].
  Future<void> setPlaylistAndPlay(
    List<TrackItem> tracks, {
    int startIndex = 0,
    LibraryTabId? playbackOriginTab,
    String? playbackOriginUserPlaylistId,
    bool keepShuffleMode = false,
    bool enableShuffle = false,
  }) async {
    await _guardedTransport(() async {
      _playbackPausedByUser = false;
      await setPlaylist(
        tracks,
        startIndex: startIndex,
        playbackOriginTab: playbackOriginTab,
        playbackOriginUserPlaylistId: playbackOriginUserPlaylistId,
        keepShuffleMode: keepShuffleMode,
        enableShuffle: enableShuffle,
      );
      // Lazy [ConcatenatingAudioSource] may still be loading when [_loadCurrent]
      // returns; [play] can no-op until [ProcessingState.ready].
      await _resumePlaybackAfterLoad(context: 'setPlaylistAndPlay.play');
    });
  }

  /// Path-key queue + play (avoids copying [TrackItem] rows from the catalog).
  Future<void> setPlaylistPathsAndPlay(
    List<String> paths, {
    int startIndex = 0,
    LibraryTabId? playbackOriginTab,
    String? playbackOriginUserPlaylistId,
    bool keepShuffleMode = false,
    bool enableShuffle = false,
  }) async {
    await _guardedTransport(() async {
      _playbackPausedByUser = false;
      await setPlaylistPaths(
        paths,
        startIndex: startIndex,
        playbackOriginTab: playbackOriginTab,
        playbackOriginUserPlaylistId: playbackOriginUserPlaylistId,
        keepShuffleMode: keepShuffleMode,
        enableShuffle: enableShuffle,
      );
      await _resumePlaybackAfterLoad(context: 'setPlaylistPathsAndPlay.play');
    });
  }

  /// Whether [track] is already in the queue (same path or same title + artist).
  bool isTrackInPlaylist(TrackItem track) =>
      _anyQueuePath((p) => _sameQueuePathAndTrack(p, track));

  /// Appends [track] to the end of the queue only if it is not already present.
  /// Returns `false` if it was already queued (same file path, or same title + artist
  /// when paths are missing). Starts playback if the queue was empty and the track
  /// was added.
  Future<bool> addToPlaylistIfAbsent(TrackItem track) async {
    if (isTrackInPlaylist(track)) {
      return false;
    }
    await appendToPlaylist([track]);
    return true;
  }

  /// Playlist index to insert a path so it plays immediately after the current song.
  int _insertPlaylistIndexAfterCurrent() {
    final logical = _logicalPlaylistIndex();
    final scope = _playbackPathKeysScope;
    if (scope != null && scope.isNotEmpty) {
      final ordered = _playbackScopedIndices();
      if (ordered.isEmpty) {
        return (logical + 1).clamp(0, _playlistPaths.length);
      }
      final p = ordered.indexOf(logical);
      if (p < 0) {
        return (logical + 1).clamp(0, _playlistPaths.length);
      }
      if (p < ordered.length - 1) {
        return ordered[p + 1];
      }
      return _playlistPaths.length;
    }
    return (logical + 1).clamp(0, _playlistPaths.length);
  }

  /// Rebuilds [ConcatenatingAudioSource] after queue edits while keeping the current song.
  Future<void> _rebuildAudioSourceForQueueMutation({
    bool stopBeforeLoad = false,
  }) async {
    if (_playlistPaths.isEmpty) return;
    if (_skipWindowsSingleTrackReloadIfCurrentUnchanged()) return;
    _concatExpandGeneration++;
    final pos = _player.position;
    final resumeAfterReload = _player.playing && !_playbackPausedByUser;
    await _guardedTransport(() async {
      await _loadCurrent(initialPosition: pos, stopBeforeLoad: stopBeforeLoad);
      if (resumeAfterReload) {
        _playbackPausedByUser = false;
        await _resumePlaybackAfterLoad(context: 'queueMutation.play');
      }
    });
  }

  /// Reorders concat children around the playing index without [AudioPlayer.stop].
  ///
  /// Works when the current track's playback position is unchanged (typical
  /// "move another song to play next"). Returns false if a full reload is needed.
  Future<bool> _tryResyncConcatAfterQueueReorder() async {
    if (!_canMutateConcatInPlace) return false;
    if (_useSingleTrackAudioSourceForPlatform()) return false;

    final target = _effectiveQueueOrder();
    if (target.isEmpty || _concatSource == null || _activeSourceOrder.isEmpty) {
      return false;
    }
    if (_activeSourceOrder.length != target.length) return false;
    if (listEquals(_activeSourceOrder, target)) {
      _sourceNeedsReload = false;
      return true;
    }

    final curPl = _logicalPlaylistIndex();
    final curConcat = _activeSourceOrder.indexOf(curPl);
    if (curConcat < 0) return false;

    final newCurConcat = target.indexOf(curPl);
    if (newCurConcat < 0 || newCurConcat != curConcat) return false;

    _concatExpandGeneration++;
    try {
      final concat = _concatSource!;

      while (_activeSourceOrder.length > curConcat + 1) {
        await concat.removeAt(curConcat + 1);
        _activeSourceOrder.removeAt(curConcat + 1);
      }
      while (_activeSourceOrder.isNotEmpty &&
          _activeSourceOrder.first != curPl) {
        await concat.removeAt(0);
        _activeSourceOrder.removeAt(0);
      }

      final curNow = _activeSourceOrder.indexOf(curPl);
      if (curNow < 0) return false;

      for (var i = curNow - 1; i >= 0; i--) {
        final pi = target[i];
        final source = await _audioSourceForPlaylistIndex(
          pi,
          resolveArtUri: false,
        );
        if (source == null) return false;
        await concat.insert(0, source);
        _activeSourceOrder.insert(0, pi);
      }

      for (var i = curNow + 1; i < target.length; i++) {
        final pi = target[i];
        final source = await _audioSourceForPlaylistIndex(
          pi,
          resolveArtUri: false,
        );
        if (source == null) return false;
        await concat.add(source);
        _activeSourceOrder.add(pi);
      }

      if (!listEquals(_activeSourceOrder, target)) return false;

      _sourceNeedsReload = false;
      return true;
    } catch (e, st) {
      debugPrint('_tryResyncConcatAfterQueueReorder: $e\n$st');
      return false;
    }
  }

  /// Inserts [track] so it plays immediately after the current song.
  ///
  /// Returns `false` only when [track] is already the current queue item.
  /// With shuffle on, an existing non-current copy is removed first, then the track
  /// is queued after the current position in the shuffle order.
  Future<bool> playTrackNext(
    TrackItem track, {
    LibraryTabId? playbackOriginTab,
  }) async {
    if (_playlistPaths.isEmpty) {
      await setPlaylistAndPlay([track], playbackOriginTab: playbackOriginTab);
      return true;
    }

    final trackPath = _pathForTrack(track);
    if (trackPath == null) return false;

    int? existingIx;
    for (var i = 0; i < _playlistPaths.length; i++) {
      if (_sameQueuePathAndTrack(_playlistPaths[i], track)) {
        existingIx = i;
        break;
      }
    }

    final curPl = _logicalPlaylistIndex();

    if (!_shuffle) {
      if (existingIx == curPl) {
        return false;
      }
      if (existingIx != null) {
        _playlistPaths.removeAt(existingIx);
        _invalidatePlaylistCache();
        if (existingIx < _index) {
          _index--;
        }
      }
      var insertAt = _insertPlaylistIndexAfterCurrent();
      if (existingIx != null && existingIx < insertAt) {
        insertAt--;
      }
      _playlistPaths.insert(
        insertAt.clamp(0, _playlistPaths.length),
        trackPath,
      );
      _invalidatePlaylistCache();
      _sourceNeedsReload = true;
      _notifyTrackPlaybackQueue();
      if (!await _tryResyncConcatAfterQueueReorder()) {
        await _rebuildAudioSourceForQueueMutation();
      }
      return true;
    }

    if (existingIx != null && existingIx == curPl) {
      return false;
    }
    if (existingIx != null) {
      _removePlaylistIndexWhileShuffling(existingIx);
    }
    _playlistPaths.add(trackPath);
    _invalidatePlaylistCache();
    final newIx = _playlistPaths.length - 1;
    final insertPos = (_shufflePos + 1).clamp(0, _shuffleOrder.length);
    _shuffleOrder.insert(insertPos, newIx);

    _sourceNeedsReload = true;
    _notifyTrackPlaybackQueue();
    if (!await _tryResyncConcatAfterQueueReorder()) {
      await _rebuildAudioSourceForQueueMutation();
    }
    return true;
  }

  void _removePlaylistIndexWhileShuffling(int rm) {
    final curKey = canonicalMusicLibraryPathKey(
      (currentTrack?.filePath ?? '').trim(),
    );
    _playlistPaths.removeAt(rm);
    _invalidatePlaylistCache();
    final nextOrder = <int>[];
    for (final oi in _shuffleOrder) {
      if (oi == rm) continue;
      nextOrder.add(oi > rm ? oi - 1 : oi);
    }
    _shuffleOrder = nextOrder;
    if (_shuffleOrder.isEmpty) {
      if (_playlistPaths.isEmpty) {
        _resetShuffleState();
        return;
      }
      _shuffle = false;
      _shuffleOrder = [];
      _shufflePos = 0;
      _index = _index.clamp(0, _playlistPaths.length - 1);
      return;
    }
    if (curKey.isEmpty) {
      _shufflePos = _shufflePos.clamp(0, _shuffleOrder.length - 1);
      _index = _shuffleOrder[_shufflePos].clamp(0, _playlistPaths.length - 1);
      return;
    }
    var found = false;
    for (var i = 0; i < _shuffleOrder.length; i++) {
      final pi = _shuffleOrder[i];
      if (pi < 0 || pi >= _playlistPaths.length) continue;
      final fp = _pathAt(pi)?.trim() ?? '';
      if (fp.isNotEmpty && canonicalMusicLibraryPathKey(fp) == curKey) {
        _shufflePos = i;
        _index = pi;
        found = true;
        break;
      }
    }
    if (!found) {
      _shufflePos = 0;
      _index = _shuffleOrder[0].clamp(0, _playlistPaths.length - 1);
    }
  }

  /// Resolves [filePath] to a library row when possible (same rules as Library sheets).
  TrackItem trackForLibraryPath(String filePath) {
    final raw = filePath.trim();
    if (raw.isEmpty) return TrackItem.fromFilePath(filePath);
    final key = canonicalMusicLibraryPathKey(raw);
    if (key.isNotEmpty) {
      final hit = _libraryCatalog.trackForPath(raw);
      if (hit != null) return hit;
    }
    return TrackItem.fromFilePath(raw);
  }

  /// After [UserPlaylistsStore.addPathToPlaylist], call when the storage add
  /// succeeded so the Now Playing queue matches the saved playlist when playback
  /// was started from that playlist (`playbackOriginUserPlaylistId`).
  Future<void> syncAddedSongToActiveUserPlaylistQueue(
    String userPlaylistId,
    String filePath,
  ) async {
    if (_playbackOriginUserPlaylistId != userPlaylistId) return;
    final track = trackForLibraryPath(filePath);
    await addToPlaylistIfAbsent(track);
  }

  void updateTrackByPath(
    String path,
    TrackItem updated, {
    CatalogNotifyMode notify = CatalogNotifyMode.immediate,
    bool refreshNotificationArt = true,
  }) {
    final key = canonicalMusicLibraryPathKey(path);
    if (key.isEmpty) return;
    final cur = currentTrack;
    final curKey = cur?.filePath != null
        ? canonicalMusicLibraryPathKey(cur!.filePath!.trim())
        : '';
    final shouldRefreshNotificationArt =
        curKey == key &&
        cur != null &&
        updated.albumArtBytes != null &&
        updated.albumArtBytes!.isNotEmpty &&
        (cur.albumArtBytes == null ||
            cur.albumArtBytes!.isEmpty ||
            !listEquals(cur.albumArtBytes, updated.albumArtBytes));

    var changed = false;
    for (var i = 0; i < _playlistPaths.length; i++) {
      if (canonicalMusicLibraryPathKey(_playlistPaths[i]) == key) {
        changed = true;
        final newPath = updated.filePath?.trim();
        if (newPath != null && newPath.isNotEmpty) {
          _playlistPaths[i] = newPath;
        }
      }
    }
    if (changed) _invalidatePlaylistCache();
    if (_libraryCatalog.updateAtPath(path, updated)) {
      changed = true;
      final art = updated.albumArtBytes;
      if (art != null && art.isNotEmpty) {
        markAlbumArtAvailable(path);
      }
    }
    if (changed) {
      _notifyCatalogListeners(notify);
      final artArrived =
          updated.albumArtBytes != null && updated.albumArtBytes!.isNotEmpty;
      if (curKey == key && artArrived) {
        _notifyTrack();
        _scheduleNotificationArtRefresh(retryIfLoading: true);
      } else if (!_isLoadingSource &&
          (shouldRefreshNotificationArt ||
              (refreshNotificationArt && curKey == key))) {
        _scheduleNotificationArtRefresh();
      }
    }
  }

  /// Re-push notification [MediaItem.artUri] (e.g. after theme change).
  void scheduleNotificationArtRefresh() => _scheduleNotificationArtRefresh();

  void _scheduleNotificationArtRefresh({bool retryIfLoading = false}) {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    if (_notificationArtRefreshInProgress) return;

    if (_isLoadingSource && retryIfLoading) {
      if (_notificationArtRetryCount >= _kNotificationArtRetryMax) return;
      _notificationArtRetryTimer?.cancel();
      _notificationArtRetryTimer = Timer(const Duration(seconds: 2), () {
        _notificationArtRetryTimer = null;
        _notificationArtRetryCount++;
        _scheduleNotificationArtRefresh(retryIfLoading: true);
      });
      return;
    }

    if (_isLoadingSource) return;

    _notificationArtRetryCount = 0;
    _notificationArtRetryTimer?.cancel();
    _notificationArtRefreshDebounce?.cancel();
    _notificationArtRefreshDebounce = Timer(
      const Duration(milliseconds: 280),
      () {
        _notificationArtRefreshDebounce = null;
        unawaited(_refreshNotificationAlbumArt());
      },
    );
  }

  /// Pushes late artwork to the Android/iOS media notification without
  /// reloading the audio source or resetting the native decoder.
  Future<void> _refreshNotificationAlbumArt() async {
    if (_playlistPaths.isEmpty) return;
    if (_notificationArtRefreshInProgress) return;
    _notificationArtRefreshInProgress = true;
    try {
      final track = currentTrack;
      final fp = track?.filePath?.trim();
      if (track == null || fp == null || fp.isEmpty) return;
      final trackKey = canonicalMusicLibraryPathKey(fp);
      final bytes = await resolveAlbumArtBytes(
        track,
        player: this,
        targetDimension: 512,
      );
      final trackForArt = bytes != null && bytes.isNotEmpty
          ? track.withEmbeddedMetadata(
              albumArtBytes: bytes,
              replaceAlbumArtFromFile: true,
            )
          : track;
      final artUri = await uriForNotificationAlbumArt(trackForArt);
      if (artUri == null) return;

      await _waitForNotificationMetadataWindow();
      final latestPath = currentTrack?.filePath?.trim() ?? '';
      if (trackKey.isNotEmpty &&
          canonicalMusicLibraryPathKey(latestPath) != trackKey) {
        return;
      }

      await JustAudioBackground.updateCurrentMediaItem(
        MediaItem(
          id: fp,
          title: track.title,
          artist: track.artist,
          album: track.metaLine,
          artUri: artUri,
          duration: _player.duration,
        ),
      );
      _notifyTrack();
    } catch (e, st) {
      debugPrint('_refreshNotificationAlbumArt: $e\n$st');
    } finally {
      _notificationArtRefreshInProgress = false;
    }
  }

  /// Avoid metadata/art updates during the brief codec reset window after
  /// source changes, skips, or seeks. This does not touch playback.
  Future<void> _waitForNotificationMetadataWindow() async {
    const step = Duration(milliseconds: 80);
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(deadline)) {
      switch (_player.processingState) {
        case ProcessingState.ready:
        case ProcessingState.completed:
          return;
        case ProcessingState.buffering:
          if (!_player.playing) return;
          break;
        case ProcessingState.idle:
        case ProcessingState.loading:
          break;
      }
      await Future<void>.delayed(step);
    }
  }

  /// Replace the playlist entry for [oldPath] with [updated] (new path + tags).
  /// Reloads the audio source when the renamed file is currently playing.
  ///
  /// Callers that invoke [stopForExternalFileEdit] before this must pass
  /// [resumePlaying] / [resumePosition] — after a stop, [isPlaying] and
  /// [position] are no longer the pre-edit values.
  bool _playlistPathMatchesReplaceKey(String path, String oldKey) {
    if (path.trim().isEmpty || oldKey.isEmpty) return false;
    return canonicalMusicLibraryPathKey(path) == oldKey;
  }

  Future<void> replaceTrackPath(
    String oldPath,
    TrackItem updated, {
    Duration? resumePosition,
    bool? resumePlaying,
  }) async {
    final oldKey = canonicalMusicLibraryPathKey(oldPath);
    final newPath = updated.filePath?.trim() ?? '';
    final newKey = newPath.isNotEmpty
        ? canonicalMusicLibraryPathKey(newPath)
        : '';
    if (oldKey.isEmpty) return;
    if (newKey.isNotEmpty && newKey != oldKey) {
      _registerLibraryPathMigration(oldPath, newPath);
    }

    final isCurrentTrackPathBeingReplaced = isCurrentTrackFilePath(oldPath);
    final resumePlayingAfterReload =
        resumePlaying ?? (isCurrentTrackPathBeingReplaced && _player.playing);
    final resumePositionAfterReload =
        resumePosition ??
        (isCurrentTrackPathBeingReplaced ? _player.position : Duration.zero);

    var changed = false;
    for (var i = 0; i < _playlistPaths.length; i++) {
      if (_playlistPathMatchesReplaceKey(_playlistPaths[i], oldKey)) {
        if (newPath.isNotEmpty) {
          _playlistPaths[i] = newPath;
        }
        changed = true;
      }
    }
    if (changed) _invalidatePlaylistCache();
    if (_libraryCatalog.replacePath(oldPath, updated) ||
        _libraryCatalog.updateAtPath(oldPath, updated)) {
      changed = true;
    }
    _syncPlaylistPathsFromMigrations();

    final pathUnchanged = newKey.isNotEmpty && newKey == oldKey;
    if (pathUnchanged) {
      _notifyTrack();
      if (isCurrentTrackPathBeingReplaced) {
        _scheduleNotificationArtRefresh();
      }
      return;
    }

    if (newPath.isNotEmpty) {
      unawaited(() async {
        await migrateLibraryPathReferences(oldPath, newPath);
        await evictArtCachesForPath(oldPath);
      }());
    }

    final shouldReloadPlayer =
        isCurrentTrackPathBeingReplaced ||
        await shouldRewirePlaybackForRenamedFile(oldPath, newPath);
    if (!changed && !shouldReloadPlayer) {
      _notifyTrackPlaybackQueue();
      return;
    }

    _sourceNeedsReload = true;
    if (!shouldReloadPlayer) {
      _notifyTrackPlaybackQueue();
      return;
    }

    // Reload only the playing row — rebuilding a large concat can still open the
    // pre-rename URI (ENOENT) while the native player is settling after [stop].
    _loadCurrentPathOverride = updated;
    try {
      await _reloadPlayingTrackOnly(
        initialPosition: resumePositionAfterReload,
        resumePlaying: resumePlayingAfterReload,
        context: 'replaceTrackPath',
        stopBeforeLoad: true,
      );
    } finally {
      _loadCurrentPathOverride = null;
      _notifyTrackPlaybackQueue();
    }
  }

  bool _prunePlaylistPathsNotInCatalog() {
    if (_libraryCatalog.isEmpty || _playlistPaths.isEmpty) return false;
    if (_libraryPathMigrations.isNotEmpty || _loadCurrentPathOverride != null) {
      return false;
    }
    final validKeys = Set<String>.from(_libraryCatalog.canonicalPathKeys);
    for (final migrated in _libraryPathMigrations.values) {
      final k = canonicalMusicLibraryPathKey(migrated);
      if (k.isNotEmpty) validKeys.add(k);
    }
    if (validKeys.isEmpty) return false;

    final before = _playlistPaths.length;
    _playlistPaths.removeWhere((path) {
      final k = canonicalMusicLibraryPathKey(path);
      if (k.isEmpty) return true;
      return !validKeys.contains(k);
    });
    if (_playlistPaths.length == before) return false;
    _invalidatePlaylistCache();

    if (_playlistPaths.isEmpty) {
      _index = 0;
      _resetShuffleState();
    } else {
      _index = _index.clamp(0, _playlistPaths.length - 1);
      if (_shuffle) {
        _shuffleOrder = List<int>.generate(_playlistPaths.length, (i) => i);
        _shufflePos = _shufflePos.clamp(0, _shuffleOrder.length - 1);
      }
    }
    return true;
  }

  /// Removes one queue entry and keeps playback coherent. Shuffle is turned off.
  ///
  /// When the removed row was the current track, pass [resumePlayingIfCurrentRemoved]
  /// if playback had been active (e.g. delete-while-playing) so the next queue item
  /// loads and starts — callers often [stopForExternalFileEdit] first, so the
  /// player is no longer “playing” when this runs.
  Future<void> removePlaylistEntryAt(
    int i, {
    bool resumePlayingIfCurrentRemoved = false,
  }) async {
    if (_playlistPaths.isEmpty || i < 0 || i >= _playlistPaths.length) return;

    if (_shuffle) {
      _index = currentIndex.clamp(0, _playlistPaths.length - 1);
      _resetShuffleState();
    }

    final isCurrent = i == _index;
    if (isCurrent) {
      await stopForExternalFileEdit();
    }

    final removedViaConcat =
        !isCurrent && await _removeConcatChildAtPlaylistIndex(i);

    _playlistPaths.removeAt(i);
    _invalidatePlaylistCache();

    final len = _playlistPaths.length;
    if (len == 0) {
      _index = 0;
      _concatSource = null;
      _activeSourceOrder = <int>[];
      _notifyTrackPlaybackQueue();
      return;
    }

    if (i < _index) {
      _index--;
    } else if (isCurrent) {
      _index = i.clamp(0, len - 1);
    }

    _notifyTrackPlaybackQueue();
    if (isCurrent) {
      await _guardedTransport(() async {
        await _loadCurrent();
        if (resumePlayingIfCurrentRemoved) {
          await _resumePlaybackAfterLoad(
            context: 'removePlaylistEntryAt.resume',
          );
        }
      });
    } else if (removedViaConcat) {
      return;
    } else {
      if (_skipWindowsSingleTrackReloadIfCurrentUnchanged()) return;
      await _loadCurrent(
        initialPosition: _player.position,
        stopBeforeLoad: false,
      );
    }
  }

  Future<void> jumpToIndex(int i, {bool autoPlay = true}) async {
    if (i < 0 || i >= _playlistPaths.length) return;
    if (autoPlay) {
      _playbackPausedByUser = false;
    }
    if (_playbackPathKeysScope != null && !_playlistIndexMatchesScope(i)) {
      _playbackPathKeysScope = null;
    }
    if (_shuffle) {
      _shuffleOrder.remove(i);
      final rest = List<int>.generate(_playlistPaths.length, (j) => j)
        ..remove(i)
        ..shuffle();
      _shuffleOrder = [i, ...rest];
      _shufflePos = 0;
    } else {
      _index = i;
    }
    _notifyTrackPlaybackQueue();
    if (autoPlay) {
      await _guardedTransport(() async {
        await _loadCurrent();
        await _resumePlaybackAfterLoad(context: 'jumpToIndex.play');
      });
    } else {
      await _loadCurrent();
    }
  }

  /// Reorders [playbackOrderIndices] and rebuilds the native concat to match.
  Future<void> reorderPlaybackQueue(
    int oldOrderIndex,
    int newOrderIndex,
  ) async {
    if (!canReorderPlaybackQueue) return;
    final order = _effectiveQueueOrder();
    if (order.isEmpty) return;
    if (oldOrderIndex < 0 || oldOrderIndex >= order.length) return;
    newOrderIndex = newOrderIndex.clamp(0, order.length - 1);
    if (oldOrderIndex == newOrderIndex) return;

    final curPl = _logicalPlaylistIndex();

    if (_shuffle) {
      final perm = List<int>.from(_shuffleOrder);
      final moved = perm.removeAt(oldOrderIndex);
      perm.insert(newOrderIndex, moved);
      _shuffleOrder = perm;
      _shufflePos = _shuffleOrder.indexOf(curPl);
      if (_shufflePos < 0) _shufflePos = 0;
    } else {
      final paths = List<String>.from(_playlistPaths);
      final perm = List<int>.from(order);
      final movedPl = perm.removeAt(oldOrderIndex);
      perm.insert(newOrderIndex, movedPl);
      _playlistPaths = perm.map((i) => paths[i]).toList(growable: false);
      _invalidatePlaylistCache();
      final newPos = perm.indexOf(curPl);
      _index = newPos >= 0
          ? newPos
          : _index.clamp(0, _playlistPaths.length - 1);
    }

    _sourceNeedsReload = true;
    _notifyTrackPlaybackQueue();
    if (!await _tryResyncConcatAfterQueueReorder()) {
      await _rebuildAudioSourceForQueueMutation();
    }
  }

  Future<void> _loadCurrent({
    Duration initialPosition = Duration.zero,
    bool stopBeforeLoad = true,
    bool retryAfterMissingPath = true,
  }) async {
    final preview = _loadCurrentPathOverride ?? currentTrack;
    final pathPreview = preview?.filePath;
    if (preview == null || pathPreview == null || pathPreview.isEmpty) {
      _suppressTrackCompletedAdvance = false;
      if (stopBeforeLoad) {
        try {
          await _player.stop();
        } catch (_) {}
      }
      _concatSource = null;
      _activeSourceOrder = <int>[];
      _loadedWindowsSingleTrackPathKey = null;
      _notifyTrackPlaybackQueue();
      return;
    }

    final loadTargetPathKey = canonicalMusicLibraryPathKey(pathPreview.trim());

    _postLoadConcatGuardUntil = null;
    _postLoadExpectedConcatIndex = null;

    // Set before any await so [stop]-driven [ProcessingState.completed] cannot
    // run [skipNext] in the gap after [stopForExternalFileEdit] (see [_suppressTrackCompletedAdvance]).
    _loadCurrentDepth++;
    _isLoadingSource = true;
    try {
      _syncPlaylistPathsFromMigrations();
      if (_prunePlaylistPathsNotInCatalog() && _playlistPaths.isNotEmpty) {
        _notifyTrackPlaybackQueue();
      }
      final order = _effectiveQueueOrder();
      if (order.isEmpty || _playlistPaths.isEmpty) {
        debugPrint(
          '_loadCurrent: no playable order (playlist=${_playlistPaths.length} '
          'scope=${_playbackPathKeysScope?.length})',
        );
        try {
          await _player.stop();
        } catch (_) {}
        _concatSource = null;
        _activeSourceOrder = <int>[];
        _loadedWindowsSingleTrackPathKey = null;
        _notifyTrackPlaybackQueue();
        return;
      }
      if (stopBeforeLoad) {
        try {
          await _player.stop();
        } catch (_) {}
      }

      var logical = _logicalPlaylistIndex();
      if (!order.contains(logical)) {
        logical = order.first;
        _index = logical;
        if (_shuffle) {
          final spi = _shuffleOrder.indexOf(logical);
          _shufflePos = spi >= 0 ? spi : 0;
        }
      }
      if (logical < 0 || logical >= _playlistPaths.length) {
        logical = order.first.clamp(0, _playlistPaths.length - 1);
        _index = logical;
        if (_shuffle) {
          final spi = _shuffleOrder.indexOf(logical);
          _shufflePos = spi >= 0 ? spi : 0;
        }
      }

      _deferMetadataEnrichForPlaylistIndex(logical);

      final sourceOrder = _useSingleTrackAudioSourceForPlatform()
          ? <int>[logical]
          : order;

      final useFastStart =
          !_useSingleTrackAudioSourceForPlatform() &&
          sourceOrder.length > _fastStartConcatThreshold &&
          !_shuffle;
      if (useFastStart) {
        await _loadCurrentFastStart(
          logical: logical,
          sourceOrder: sourceOrder,
          initialPosition: initialPosition,
        );
      } else {
        final children = <AudioSource>[];
        final loadedOrder = <int>[];
        var initialConcatIndex = 0;
        var concatPos = 0;

        var built = 0;
        for (final pi in sourceOrder) {
          if (pi < 0 || pi >= _playlistPaths.length) continue;
          final source = await _audioSourceForPlaylistIndex(
            pi,
            resolveArtUri: false,
          );
          if (source == null) continue;

          children.add(source);
          loadedOrder.add(pi);
          if (pi == logical) {
            initialConcatIndex = concatPos;
          }
          concatPos++;
          built++;
          // Yield so very large queues do not freeze the UI isolate.
          if (built % 64 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }

        if (children.isEmpty) {
          _concatSource = null;
          _activeSourceOrder = <int>[];
          _loadedWindowsSingleTrackPathKey = null;
          _notifyTrackPlaybackQueue();
          return;
        }
        initialConcatIndex = initialConcatIndex.clamp(0, children.length - 1);
        _activeSourceOrder = loadedOrder;

        await _prepareAudioSourceLoad();
        if (_useSingleTrackAudioSourceForPlatform()) {
          _concatSource = null;
          await _setPlayerAudioSource(
            children.single,
            initialPosition: initialPosition,
            context: '_loadCurrent.single',
            stopBeforeLoad: false,
          );
          final fp = _trackAt(logical).filePath?.trim() ?? '';
          final resolved = fp.isEmpty ? '' : _resolveMigratedFilePath(fp);
          _loadedWindowsSingleTrackPathKey = resolved.isEmpty
              ? null
              : canonicalMusicLibraryPathKey(resolved);
        } else {
          _loadedWindowsSingleTrackPathKey = null;
          final concat = ConcatenatingAudioSource(
            useLazyPreparation: _concatUseLazyPreparationForPlatform(),
            children: children,
          );
          await _setPlayerAudioSource(
            concat,
            initialIndex: initialConcatIndex,
            initialPosition: initialPosition,
            context: '_loadCurrent.concat',
            stopBeforeLoad: false,
          );
          _concatSource = concat;
        }
        await _applyPreferredVolume();
        _postLoadExpectedConcatIndex = initialConcatIndex;
        _postLoadConcatGuardUntil = DateTime.now().add(
          const Duration(milliseconds: 650),
        );
        _sourceNeedsReload = false;
      } // !useFastStart
    } catch (e, st) {
      _loadedWindowsSingleTrackPathKey = null;
      debugPrint('Playback load error: $e\n$st');
      if (retryAfterMissingPath) {
        final missingPath = _extractMissingPathFromLoadError(e);
        if (missingPath != null && missingPath.isNotEmpty) {
          final removed = _removeMissingTrackPath(missingPath);
          if (removed && _playlistPaths.isNotEmpty) {
            await _loadCurrent(
              initialPosition: Duration.zero,
              stopBeforeLoad: true,
              retryAfterMissingPath: false,
            );
            return;
          }
        }
      }
    } finally {
      _loadCurrentDepth--;
      if (_loadCurrentDepth <= 0) {
        _loadCurrentDepth = 0;
        _isLoadingSource = false;
        _suppressTrackCompletedAdvance = false;
        _ignoreSpuriousPlaybackCompletedUntil = null;
        _scheduleNotificationArtRefresh();
      }
      final pending = _pendingConcatIndexWhileLoading;
      _pendingConcatIndexWhileLoading = null;
      if (pending != null &&
          _pendingConcatIndexMatchesLoadedPath(pending, loadTargetPathKey) &&
          _applyConcatIndexChanged(pending)) {
        _notifyTrackPlaybackQueue();
      }
    }
    _prewarmPlaybackAlbumArt();
    _notifyTrack();
    positionNotifier.flush();
  }

  String? _extractMissingPathFromLoadError(Object error) {
    final s = error.toString();
    final marker = 'FileNotFoundException:';
    final at = s.indexOf(marker);
    if (at < 0) return null;
    final tail = s.substring(at + marker.length).trim();
    final end = tail.indexOf(': open failed');
    if (end <= 0) return null;
    final path = tail.substring(0, end).trim();
    if (path.isEmpty) return null;
    return path;
  }

  bool _removeMissingTrackPath(String path) {
    final beforePlaylist = _playlistPaths.length;
    _playlistPaths.removeWhere(
      (p) =>
          canonicalMusicLibraryPathKey(p) == canonicalMusicLibraryPathKey(path),
    );
    _invalidatePlaylistCache();
    final beforeCatalog = _libraryCatalog.length;
    _libraryCatalog.removeAtPath(path);

    if (_playlistPaths.isEmpty) {
      _index = 0;
      _resetShuffleState();
    } else {
      if (_index >= _playlistPaths.length) {
        _index = _playlistPaths.length - 1;
      }
      if (_shuffle) {
        _shuffleOrder = List<int>.generate(_playlistPaths.length, (i) => i);
        if (_shufflePos >= _shuffleOrder.length) {
          _shufflePos = _shuffleOrder.length - 1;
        }
      }
    }

    final changed =
        _playlistPaths.length != beforePlaylist ||
        _libraryCatalog.length != beforeCatalog;
    if (changed) queue.notifyNow();
    return changed;
  }

  /// Whether [path] refers to the same file as the current queue item (normalized).
  bool isCurrentTrackFilePath(String path) {
    final cur = currentTrack?.filePath;
    if (cur == null || cur.trim().isEmpty || path.trim().isEmpty) {
      return false;
    }
    final pathKey = canonicalMusicLibraryPathKey(path);
    final curKey = canonicalMusicLibraryPathKey(cur);
    if (pathKey == curKey) return true;
    return _resolveMigratedLibraryPathKey(cur) == pathKey ||
        _resolveMigratedLibraryPathKey(path) == curKey;
  }

  /// True when the playing row still points at a file that was renamed on disk.
  Future<bool> shouldRewirePlaybackForRenamedFile(
    String oldPath,
    String newPath,
  ) async {
    if (isCurrentTrackFilePath(oldPath)) return true;
    if (kIsWeb || newPath.trim().isEmpty) return false;
    final cur = currentTrack?.filePath?.trim();
    if (cur == null || cur.isEmpty) return false;
    try {
      if (await File(cur).exists()) return false;
      return await File(_normalizeLocalFilePath(newPath)).exists();
    } catch (_) {
      return false;
    }
  }

  /// Reload the current file from disk (e.g. after embedded tags were rewritten).
  ///
  /// [initialPosition] defaults to the player’s current offset when omitted.
  ///
  /// Pass [stopBeforeLoad] false when the native player was already stopped to
  /// release the file for an external tag write — avoids a redundant [stop] that
  /// can leave playback paused after the sheet closes.
  Future<void> reloadCurrentSource({
    Duration? initialPosition,
    bool resumePlaying = false,
    bool stopBeforeLoad = true,
  }) async {
    final pos = initialPosition ?? _player.position;
    await _loadCurrent(initialPosition: pos, stopBeforeLoad: stopBeforeLoad);
    if (resumePlaying) {
      _playbackPausedByUser = false;
      await _resumePlaybackAfterLoad(context: 'reloadCurrentSource.play');
    }
  }

  /// Reload only the playing file after a tag write (same path). Avoids rebuilding
  /// a thousand-track concat (and native shuffle index crashes).
  Future<void> _reloadPlayingTrackOnly({
    required Duration initialPosition,
    required bool resumePlaying,
    String context = 'reloadPlayingTrackOnly',
    bool allowShuffleRecovery = true,
    bool stopBeforeLoad = true,
  }) async {
    if (_playlistPaths.isEmpty) return;

    _loadCurrentDepth++;
    _isLoadingSource = true;
    try {
      final logical = _logicalPlaylistIndex();
      final source = await _audioSourceForPlaylistIndex(logical);
      if (source == null) {
        debugPrint('$context: no AudioSource for playlist index $logical');
        return;
      }

      await _prepareAudioSourceLoad();
      _concatSource = null;
      _activeSourceOrder = [logical];
      await _setPlayerAudioSource(
        source,
        initialPosition: initialPosition,
        context: context,
        stopBeforeLoad: stopBeforeLoad,
      );
      await _applyPreferredVolume();
      if (_useSingleTrackAudioSourceForPlatform()) {
        final fp = _trackAt(logical).filePath?.trim() ?? '';
        final resolved = fp.isEmpty ? '' : _resolveMigratedFilePath(fp);
        _loadedWindowsSingleTrackPathKey = resolved.isEmpty
            ? null
            : canonicalMusicLibraryPathKey(resolved);
      }
      _postLoadExpectedConcatIndex = 0;
      _postLoadConcatGuardUntil = DateTime.now().add(
        const Duration(milliseconds: 650),
      );
      // Next skip rebuilds the full queue (shuffle-safe full [_loadCurrent]).
      _sourceNeedsReload = true;
      _notifyTrack();
      if (resumePlaying) {
        _playbackPausedByUser = false;
        await _guardedTransport(() async {
          await _resumePlaybackAfterLoad(context: '$context.play');
        });
      }
    } catch (e, st) {
      if (!_isInterruptedAbort(e)) {
        debugPrint('$context: $e\n$st');
      }
      if (allowShuffleRecovery && _isNativeShuffleIndexRangeError(e)) {
        await _recoverFromBrokenNativeShuffle(
          initialPosition: initialPosition,
          resumePlaying: resumePlaying,
          context: '$context.recover',
        );
        return;
      }
    } finally {
      _loadCurrentDepth--;
      if (_loadCurrentDepth <= 0) {
        _loadCurrentDepth = 0;
        _isLoadingSource = false;
        _suppressTrackCompletedAdvance = false;
        _ignoreSpuriousPlaybackCompletedUntil = null;
        _scheduleNotificationArtRefresh();
      }
    }
  }

  /// Reload after [stopForExternalFileEdit] rewrote tags on the playing file.
  Future<void> reloadCurrentSourceAfterTagWrite({
    required Duration resumePosition,
    required bool resumePlaying,
  }) => _reloadPlayingTrackOnly(
    initialPosition: resumePosition,
    resumePlaying: resumePlaying,
    context: 'reloadCurrentSourceAfterTagWrite',
  );

  /// Tag sheets must not [await] reload — [setAudioSource] can wait on the audio
  /// lock or native prep and strand the save spinner even though the file is written.
  void reloadCurrentSourceAfterTagWriteUnawaited({
    required Duration resumePosition,
    required bool resumePlaying,
  }) {
    unawaited(() async {
      try {
        await reloadCurrentSourceAfterTagWrite(
          resumePosition: resumePosition,
          resumePlaying: resumePlaying,
        ).timeout(const Duration(seconds: 25));
      } on TimeoutException {
        debugPrint(
          'reloadCurrentSourceAfterTagWriteUnawaited: timed out; '
          'playback may need play/skip to resync',
        );
      } catch (e, st) {
        debugPrint('reloadCurrentSourceAfterTagWriteUnawaited: $e\n$st');
      }
    }());
  }

  /// Same as [reloadCurrentSource] but does not block — for UI flows (tag sheets)
  /// where awaiting lazy [setAudioSource] prep can strand the sheet on “saving”.
  void reloadCurrentSourceUnawaited({
    Duration? initialPosition,
    bool resumePlaying = false,
    bool stopBeforeLoad = true,
  }) {
    unawaited(() async {
      try {
        await reloadCurrentSource(
          initialPosition: initialPosition,
          resumePlaying: resumePlaying,
          stopBeforeLoad: stopBeforeLoad,
        );
      } catch (e, st) {
        debugPrint('reloadCurrentSourceUnawaited: $e\n$st');
      }
    }());
  }

  /// Release the open audio file so another process (or this app) can rewrite it.
  Future<void> stopForExternalFileEdit() async {
    _suppressTrackCompletedAdvance = true;
    _ignoreSpuriousPlaybackCompletedUntil = DateTime.now().add(
      const Duration(milliseconds: 900),
    );
    _concatExpandGeneration++;
    _concatSource = null;
    _loadedWindowsSingleTrackPathKey = null;
    try {
      await _player.stop();
    } catch (_) {}
  }

  /// Coalesce stream-driven UI updates (e.g. notification play/pause) to one frame.
  void _schedulePlayerUiNotify() {
    _notifyPlayback();
  }

  Future<void> play() async {
    _playbackPausedByUser = false;
    _invalidatePlayResumeRetries();
    _schedulePlayerUiNotify();
    final generation = _playControlGeneration;
    try {
      await _playSafely(context: 'play');
      if (_playbackPausedByUser || _playControlGeneration != generation) return;
      if (!_player.playing) {
        await _waitForPlayerPreparedAfterSourceChange();
        if (_playbackPausedByUser || _playControlGeneration != generation) {
          return;
        }
        await _playSafely(context: 'play.confirm');
      }
    } catch (e, st) {
      debugPrint('play error: $e\n$st');
      if (_isNativeShuffleIndexRangeError(e)) {
        final pos = _player.position;
        await _recoverFromBrokenNativeShuffle(
          initialPosition: pos,
          resumePlaying: true,
          context: 'play.recover',
        );
      }
    }
    _schedulePlayerUiNotify();
  }

  Future<void> pause() async {
    _playbackPausedByUser = true;
    _invalidatePlayResumeRetries();
    try {
      // [AudioPlayer.pause] no-ops when [playing] is already false, but ExoPlayer
      // can still be outputting audio after a handler/UI desync.
      if (_player.playing) {
        await _player.pause();
      }
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        await JustAudioBackground.ensureNativePaused();
      }
      if (_player.playing) {
        await _player.pause();
      }
    } catch (e, st) {
      debugPrint('pause error: $e\n$st');
      if (_isNativeShuffleIndexRangeError(e)) {
        await _recoverFromBrokenNativeShuffle(
          initialPosition: _player.position,
          resumePlaying: false,
          context: 'pause.recover',
        );
      }
    }
    _schedulePlayerUiNotify();
  }

  Future<void> togglePlayPause() async {
    if (isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
    positionNotifier.flush();
  }

  Future<void> _seekToPlaylistIndexFast(
    int playlistIndex, {
    required String playContext,
  }) async {
    Future<void> reloadAndPlay() => _guardedTransport(() async {
      await _loadCurrent();
      _sourceNeedsReload = false;
      await _resumePlaybackAfterLoad(context: playContext);
    });

    if (_sourceNeedsReload || _useSingleTrackAudioSourceForPlatform()) {
      await reloadAndPlay();
      return;
    }
    final order = _activeSourceOrder.isNotEmpty
        ? _activeSourceOrder
        : _effectiveQueueOrder();
    final concatIndex = order.indexOf(playlistIndex);
    if (concatIndex < 0) {
      await reloadAndPlay();
      return;
    }
    try {
      await _player.seek(Duration.zero, index: concatIndex);
      await _waitForPlayerPreparedAfterSourceChange();
      final actual = _player.currentIndex;
      if (actual != null && actual != concatIndex) {
        await reloadAndPlay();
        return;
      }
      await _playSafely(context: playContext);
    } catch (_) {
      await reloadAndPlay();
    }
  }

  /// Next track; at end pauses unless [PlaylistRepeatMode.all].
  Future<void> skipNext() async {
    if (_playlistPaths.isEmpty) return;
    _playbackPausedByUser = false;
    _manualQueueAdvance = true;
    try {
      await _skipNextImpl();
    } finally {
      _manualQueueAdvance = false;
      _notifyTrackPlaybackQueue();
      positionNotifier.flush();
    }
  }

  Future<void> _skipNextImpl() async {
    if (_shuffle) {
      final atLast = _shufflePos >= _shuffleOrder.length - 1;

      if (atLast) {
        if (_repeat == PlaylistRepeatMode.all) {
          _shufflePos = 0;
        } else {
          await _player.pause();
          return;
        }
      } else {
        _shufflePos++;
      }

      await _seekToPlaylistIndexFast(
        _shuffleOrder[_shufflePos],
        playContext: 'skipNext.shuffle play',
      );
      return;
    }

    final ordered = _playbackScopedIndices();
    if (ordered.isEmpty) {
      await _player.pause();
      return;
    }

    final p = ordered.indexOf(_index);
    if (p < 0) {
      if (_playbackPathKeysScope != null) {
        _playbackPathKeysScope = null;
        await _skipNextImpl();
        return;
      }
      await _player.pause();
      return;
    }

    if (p < ordered.length - 1) {
      _index = ordered[p + 1];
    } else if (_repeat == PlaylistRepeatMode.all) {
      _index = ordered.first;
    } else {
      await _player.pause();
      return;
    }

    await _seekToPlaylistIndexFast(_index, playContext: 'skipNext.play');
  }

  Future<void> skipPrevious() async {
    if (_playlistPaths.isEmpty) return;
    _playbackPausedByUser = false;
    _manualQueueAdvance = true;
    try {
      await _skipPreviousImpl();
    } finally {
      _manualQueueAdvance = false;
      _notifyTrackPlaybackQueue();
      positionNotifier.flush();
    }
  }

  Future<void> _skipPreviousImpl() async {
    if (_shuffle) {
      final atFirst = _shufflePos <= 0;

      if (atFirst) {
        if (_repeat == PlaylistRepeatMode.all) {
          _shufflePos = _shuffleOrder.length - 1;
        } else {
          await _player.seek(Duration.zero);
          return;
        }
      } else {
        _shufflePos--;
      }

      await _seekToPlaylistIndexFast(
        _shuffleOrder[_shufflePos],
        playContext: 'skipPrevious.shuffle play',
      );
      return;
    }

    final ordered = _playbackScopedIndices();
    if (ordered.isEmpty) {
      await _player.seek(Duration.zero);
      return;
    }

    final p = ordered.indexOf(_index);
    if (p < 0) {
      if (_playbackPathKeysScope != null) {
        _playbackPathKeysScope = null;
        await _skipPreviousImpl();
        return;
      }
      await _player.seek(Duration.zero);
      return;
    }

    if (p > 0) {
      _index = ordered[p - 1];
    } else if (_repeat == PlaylistRepeatMode.all) {
      _index = ordered.last;
    } else {
      await _player.seek(Duration.zero);
      return;
    }

    await _seekToPlaylistIndexFast(_index, playContext: 'skipPrevious.play');
  }

  void toggleShuffle() {
    if (_playlistPaths.length < 2) return;
    if (_shuffle) {
      _index = _shuffleOrder[_shufflePos];
      _shuffle = false;
      _shuffleOrder = [];
      _shufflePos = 0;
    } else {
      if (_playbackPathKeysScope != null) {
        _playbackPathKeysScope = null;
      }
      final cur = _index;
      final order = List<int>.generate(_playlistPaths.length, (j) => j)
        ..shuffle();
      order.remove(cur);
      _shuffleOrder = [cur, ...order];
      _shufflePos = 0;
      _shuffle = true;
    }
    _sourceNeedsReload = true;
    _notifyTrackPlaybackQueue();
  }

  void cycleRepeatMode() {
    _repeat = switch (_repeat) {
      PlaylistRepeatMode.off => PlaylistRepeatMode.all,
      PlaylistRepeatMode.all => PlaylistRepeatMode.one,
      PlaylistRepeatMode.one => PlaylistRepeatMode.off,
    };
    _notifyTrackPlaybackQueue();
  }

  /// Persisted playback snapshot (`PlaybackSessionStore` v2 schema).
  Map<String, dynamic> buildPlaybackPersistenceJson() {
    final paths = List<String>.from(_playlistPaths);
    final ct = currentTrack;
    final curKey = ct?.filePath == null
        ? ''
        : canonicalMusicLibraryPathKey(ct!.filePath!);
    return <String, dynamic>{
      'v': 2,
      'paths': paths,
      'index': _index,
      'shuffle': _shuffle,
      'shuffleOrder': List<int>.from(_shuffleOrder),
      'shufflePos': _shufflePos,
      'repeat': _repeat.name,
      'originTab': _playbackOriginTab?.wireValue,
      'originPlaylistId': _playbackOriginUserPlaylistId,
      'scopeKeys': _playbackPathKeysScope?.toList(),
      'positionMs': _player.position.inMilliseconds,
      'wasPlaying': _player.playing,
      'currentKey': curKey,
    };
  }

  /// Applies a restored snapshot after the library catalog is available.
  Future<void> applyRestoredPlayback({
    required List<TrackItem> queue,
    required int sequentialIndex,
    required bool shuffle,
    required List<int> shuffleOrder,
    required int shufflePos,
    required PlaylistRepeatMode repeat,
    Set<String>? pathScopeKeys,
    LibraryTabId? originTab,
    String? originUserPlaylistId,
    required Duration position,
    required bool resumePlaying,
  }) async {
    _playbackOriginTab = originTab;
    _playbackOriginUserPlaylistId = originTab == LibraryTabId.playlist
        ? originUserPlaylistId
        : null;

    _playbackPathKeysScope = pathScopeKeys == null
        ? null
        : Set<String>.from(pathScopeKeys);

    _repeat = repeat;

    _assignPlaylistFromTracks(queue);

    if (_playlistPaths.isEmpty) {
      _resetShuffleState();
      _index = 0;
      try {
        await _player.stop();
      } catch (_) {}
      _notifyTrackPlaybackQueue();
      return;
    }

    final n = _playlistPaths.length;
    bool validShuffle =
        shuffle &&
        shuffleOrder.length == n &&
        _isValidShufflePermutation(shuffleOrder, n);

    if (validShuffle) {
      _shuffle = true;
      _shuffleOrder = List<int>.from(shuffleOrder);
      _shufflePos = shufflePos.clamp(0, n - 1);
      final at = _shuffleOrder[_shufflePos];
      _index = at.clamp(0, n - 1);
    } else {
      _resetShuffleState();
      _index = sequentialIndex.clamp(0, n - 1);
    }

    _notifyTrackPlaybackQueue();

    await _loadCurrent();

    Duration seekTo = Duration.zero;
    if (currentTrack?.filePath != null) {
      final d = _player.duration;
      seekTo = position;
      if (d != null && d > Duration.zero && seekTo > d) seekTo = d;
      if (seekTo < Duration.zero) seekTo = Duration.zero;
      try {
        await _player.seek(seekTo);
      } catch (_) {}
    }

    if (resumePlaying) {
      _playbackPausedByUser = false;
      await _playSafely(context: 'applyRestoredPlayback.play');
    } else {
      await pause();
    }
    _notifyTrackPlaybackQueue();
  }

  static bool _isValidShufflePermutation(List<int> order, int n) {
    if (order.length != n) return false;
    final seen = List<bool>.filled(n, false);
    for (final x in order) {
      if (x < 0 || x >= n) return false;
      if (seen[x]) return false;
      seen[x] = true;
    }
    return true;
  }

  void dispose() {
    artAvailability.dispose();
    queue.cancelThrottle();
    _notificationArtRefreshDebounce?.cancel();
    _notificationArtRefreshDebounce = null;
    _notificationArtRetryTimer?.cancel();
    _notificationArtRetryTimer = null;
    _audioInterruptionSub?.cancel();
    _audioInterruptionSub = null;
    _becomingNoisySub?.cancel();
    _becomingNoisySub = null;
    _devicesChangedSub?.cancel();
    _devicesChangedSub = null;
    _concatIndexSub?.cancel();
    _playerStateSub.cancel();
    positionNotifier.dispose();
    track.dispose();
    playback.dispose();
    queue.dispose();
    unawaited(() async {
      try {
        await _player.dispose();
      } catch (e, st) {
        debugPrint('AudioPlayer dispose error: $e\n$st');
      }
    }());
  }
}

/// Holds [PlayerController] and sub-notifiers above [MaterialApp].
class PlayerControllerScope extends InheritedWidget {
  const PlayerControllerScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final PlayerController controller;

  PositionNotifier get positionNotifier => controller.positionNotifier;
  TrackNotifier get track => controller.track;
  PlaybackNotifier get playback => controller.playback;
  QueueNotifier get queue => controller.queue;

  static PlayerControllerScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<PlayerControllerScope>();
  }

  /// Playback coordinator; prefer [trackOf], [playbackOf], [queueOf] in UI.
  static PlayerController of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'PlayerControllerScope not found above context');
    return scope!.controller;
  }

  static PositionNotifier positionOf(BuildContext context) =>
      of(context).positionNotifier;

  static TrackNotifier trackOf(BuildContext context) => of(context).track;

  static PlaybackNotifier playbackOf(BuildContext context) =>
      of(context).playback;

  static QueueNotifier queueOf(BuildContext context) => of(context).queue;

  @override
  bool updateShouldNotify(PlayerControllerScope oldWidget) =>
      controller != oldWidget.controller;
}
