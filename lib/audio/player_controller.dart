import 'dart:async';

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
import '../services/music_library_path_key.dart';
import '../services/track_metadata.dart';
import '../services/volume_settings_store.dart';
import 'notification_art_uri.dart';

enum PlaylistRepeatMode { off, all, one }

/// How [PlayerController] notifies listeners after catalog or in-memory track updates.
///
/// Use [throttled] for high-frequency background work (disk sync, cover warmup) so
/// Library / mini-player do not rebuild on every row.
enum CatalogNotifyMode {
  /// One [notifyListeners] immediately.
  immediate,

  /// At most one [notifyListeners] per ~200ms while updates keep arriving.
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

/// Local playback + playlist index. Exposes [audioPlayer] for streams in the UI.
class PlayerController extends ChangeNotifier {
  bool _isInterruptedAbort(Object error) {
    if (error is! PlatformException) return false;
    final code = error.code.toLowerCase();
    final message = (error.message ?? '').toLowerCase();
    return code == 'abort' && message.contains('loading interrupted');
  }

  Future<void> _playSafely({String context = 'play'}) async {
    try {
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
  Future<void> _resumePlaybackAfterLoad({
    String context = 'resumeAfterLoad',
  }) async {
    if (_playbackPausedByUser) return;
    _invalidatePlayResumeRetries();
    final generation = _playControlGeneration;
    await _waitForPlayerPreparedAfterSourceChange();
    if (_playbackPausedByUser || _playControlGeneration != generation) return;
    // One event-loop turn; helps desktop embedders finish native load callbacks.
    await Future<void>.delayed(Duration.zero);
    if (_playbackPausedByUser || _playControlGeneration != generation) return;
    await _ensurePlayingWithRetries(
      context: context,
      generation: generation,
    );
  }

  Future<void> _waitForPlayerPreparedAfterSourceChange() async {
    const step = Duration(milliseconds: 40);
    final deadline = DateTime.now().add(const Duration(seconds: 8));
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
    unawaited(_loadPersistedVolume());
    unawaited(_initAudioSessionInterruptions());
    // Single subscription: listening to [processingStateStream] and
    // [playerStateStream] both triggered platform init; concurrent inits caused
    // "Platform player … already exists" on some devices (just_audio / Android).
    _playerStateSub = _player.playerStateStream.listen((state) {
      _onProcessingState(state.processingState);
      final playing = state.playing;
      final proc = state.processingState;

      // When the player becomes paused (e.g. via notification button or auto-pause),
      // invalidate any in-flight retry loops so they don't overwrite the pause.
      if (!playing && _lastDispatchedPlaying) {
        _invalidatePlayResumeRetries();
        _playbackPausedByUser = true;
      }
      if (playing && !_lastDispatchedPlaying) {
        _playbackPausedByUser = false;
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
  late final StreamSubscription<PlayerState> _playerStateSub;
  StreamSubscription<int?>? _concatIndexSub;
  StreamSubscription<AudioInterruptionEvent>? _audioInterruptionSub;
  StreamSubscription<void>? _becomingNoisySub;
  StreamSubscription<AudioDevicesChangedEvent>? _devicesChangedSub;
  Timer? _notificationArtRefreshDebounce;
  bool _notificationArtRefreshInProgress = false;

  /// Set when the user explicitly pauses; blocks [_resumePlaybackAfterLoad] until play.
  bool _playbackPausedByUser = false;

  /// True when we paused because another app (or the OS) took transient audio focus
  /// (e.g. phone call). Cleared after we attempt resume.
  bool _shouldResumeAfterTransientFocusLoss = false;

  List<TrackItem> _playlist = [];
  int _index = 0;

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
  double _preferredVolume = 1.0;

  /// While rebuilding [ConcatenatingAudioSource] for shuffle, [AudioPlayer.stop] makes
  /// `playing` false briefly; UI uses [isPlaying] which ORs this in so play/pause
  /// doesn't flash (repeat never reloads the source, so it has no such gap).
  bool _retainPlayingUiForShuffleReload = false;

  Timer? _catalogNotifyThrottleTimer;
  bool _catalogNotifyThrottlePending = false;

  /// Avoid rebuilding the whole app (Library lists, etc.) on every [playerStateStream]
  /// tick — only notify when play/pause or processing state actually changes.
  bool _playerUiDispatchInitialized = false;
  bool _lastDispatchedPlaying = false;
  ProcessingState _lastDispatchedProcessing = ProcessingState.idle;
  bool _playerUiNotifyScheduled = false;

  void _notifyCatalogListeners(CatalogNotifyMode mode) {
    switch (mode) {
      case CatalogNotifyMode.immediate:
        _catalogNotifyThrottleTimer?.cancel();
        _catalogNotifyThrottleTimer = null;
        _catalogNotifyThrottlePending = false;
        notifyListeners();
      case CatalogNotifyMode.throttled:
        _catalogNotifyThrottlePending = true;
        _catalogNotifyThrottleTimer ??= Timer(
          const Duration(milliseconds: 200),
          () {
            _catalogNotifyThrottleTimer = null;
            if (_catalogNotifyThrottlePending) {
              _catalogNotifyThrottlePending = false;
              notifyListeners();
            }
          },
        );
    }
  }

  /// When non-null, [skipNext], [skipPrevious], [upcomingTrack], and repeat-all wrap
  /// only among tracks whose path key is in this set (same as Songs tab folder filter).
  Set<String>? _playbackPathKeysScope;

  /// Last full-library scan (Songs tab + metadata); not cleared when the queue is
  /// replaced by Favourites / a user playlist / etc.
  List<TrackItem> _libraryCatalog = [];

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
    notifyListeners();
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
    notifyListeners();
  }

  List<TrackItem> get libraryCatalog =>
      List<TrackItem>.unmodifiable(_libraryCatalog);

  /// Use for tag resolution in Library: full scan when available, else active queue.
  List<TrackItem> get metadataLibrary =>
      _libraryCatalog.isNotEmpty ? _libraryCatalog : _playlist;

  LibraryTabId? get playbackOriginTab => _playbackOriginTab;

  /// Set when playback started from Library → Playlist and a user playlist sheet.
  String? get playbackOriginUserPlaylistId => _playbackOriginUserPlaylistId;

  /// Called after a folder scan with the complete track list.
  void setLibraryCatalog(
    List<TrackItem> tracks, {
    CatalogNotifyMode notify = CatalogNotifyMode.immediate,
  }) {
    _libraryCatalog = List<TrackItem>.from(tracks);
    _notifyCatalogListeners(notify);
  }

  void removeFromLibraryCatalogByPath(String path) {
    if (path.isEmpty) return;
    final before = _libraryCatalog.length;
    _libraryCatalog.removeWhere((t) => t.filePath == path);
    if (_libraryCatalog.length != before) notifyListeners();
  }

  List<TrackItem> get playlist => _playlist;

  /// Index into [playlist] for the currently playing file (list row / highlight).
  int get currentIndex {
    if (_playlist.isEmpty) return 0;
    return _shuffle ? _shuffleOrder[_shufflePos] : _index;
  }

  TrackItem? get currentTrack => _playlist.isEmpty
      ? null
      : _playlist[currentIndex.clamp(0, _playlist.length - 1)];

  /// Track that will play after the current one ([skipNext] semantics), or `null`
  /// when nothing follows (end of queue without [PlaylistRepeatMode.all] wrap).
  TrackItem? get upcomingTrack {
    if (_playlist.isEmpty) return null;
    if (_shuffle) {
      if (_shuffleOrder.isEmpty) return null;
      if (_shufflePos < _shuffleOrder.length - 1) {
        return _playlist[_shuffleOrder[_shufflePos + 1]];
      }
      if (_repeat == PlaylistRepeatMode.all) {
        return _playlist[_shuffleOrder.first];
      }
      return null;
    }

    final ordered = _playbackScopedIndices();
    if (ordered.isEmpty) return null;
    final p = ordered.indexOf(_index);

    /// Stale folder filter vs queue — fall back to full-library sequence once.
    if (p < 0) {
      if (_playbackPathKeysScope != null) {
        final n = _playlist.length;
        final i = _index;
        if (i >= 0 && i < n - 1) {
          return _playlist[i + 1];
        }
        if (_repeat == PlaylistRepeatMode.all) {
          return _playlist.first;
        }
      }
      return null;
    }

    if (p < ordered.length - 1) {
      return _playlist[ordered[p + 1]];
    }
    if (_repeat == PlaylistRepeatMode.all) {
      return _playlist[ordered.first];
    }
    return null;
  }

  /// Whether [skipNext] will advance to another item (shuffle, scoped order,
  /// repeat-all). When false, skip only pauses or no-ops at the queue end.
  bool get canSkipNext => upcomingTrack != null;

  bool get shuffleEnabled => _shuffle;

  /// Playlist indices in the order the player will play them (respects shuffle and folder scope).
  List<int> get playbackOrderIndices => List<int>.from(_effectiveQueueOrder());

  /// Whether the queue tab may reorder rows (folder filter + non-shuffle uses a non-contiguous subset).
  bool get canReorderPlaybackQueue {
    if (_playlist.length < 2) return false;
    if (_playbackPathKeysScope != null && !_shuffle) return false;
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
    notifyListeners();
    if (!reloadQueue) return;
    unawaited(_loadCurrent(initialPosition: _player.position));
  }

  bool _playlistIndexMatchesScope(int i) {
    if (_playbackPathKeysScope == null) return true;
    if (i < 0 || i >= _playlist.length) return false;
    final fp = _playlist[i].filePath;
    if (fp == null || fp.trim().isEmpty) return false;
    final k = canonicalMusicLibraryPathKey(fp);
    return k.isNotEmpty && _playbackPathKeysScope!.contains(k);
  }

  List<int> _playbackScopedIndices() {
    final n = _playlist.length;
    if (n == 0) return [];
    final scope = _playbackPathKeysScope;
    if (scope == null) {
      return List<int>.generate(n, (i) => i);
    }
    final out = <int>[];
    for (var i = 0; i < n; i++) {
      final fp = _playlist[i].filePath;
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

  static PlayerController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<PlayerControllerScope>();
    assert(scope != null, 'PlayerControllerScope not found above MaterialApp');
    return scope!.controller;
  }

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
    if (_playlist.isEmpty) return;
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
      
      notifyListeners();
      return;
    }
    if (_repeat == PlaylistRepeatMode.one) {
      await _player.seek(Duration.zero);
      await _playSafely(context: 'repeat-one play');
      return;
    }
    await skipNext();
  }

  void _resetShuffleState() {
    _shuffle = false;
    _shuffleOrder = [];
    _shufflePos = 0;
  }

  /// Playback order mirrored as [ConcatenatingAudioSource] children (shuffle or scoped).
  List<int> _effectiveQueueOrder() {
    if (_playlist.isEmpty) return [];
    if (_shuffle) return List<int>.from(_shuffleOrder);
    final scoped = _playbackScopedIndices();
    if (scoped.isNotEmpty) return scoped;
    return List<int>.generate(_playlist.length, (i) => i);
  }

  int _logicalPlaylistIndex() => _shuffle ? _shuffleOrder[_shufflePos] : _index;

  bool _applyConcatIndexChanged(int concatIdx) {
    if (_playlist.isEmpty) return false;
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
        debugPrint('Sleep timer (end of song) intercepting auto-advance: '
            'from $currentConcatIdx to $concatIdx');
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
              await _player.seek(const Duration(seconds: 1), index: currentConcatIdx);
            }
            
            // Final safety pause.
            await _player.pause();
            notifyListeners();
          } catch (e) {
            debugPrint('Sleep timer stop failed: $e');
          }
        });

        notifyListeners();
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
    notifyListeners();
  }

  void _prewarmPlaybackAlbumArt() {
    final tracks = <TrackItem>[
      if (currentTrack != null) currentTrack!,
      if (upcomingTrack != null) upcomingTrack!,
    ];
    if (tracks.isEmpty) return;
    prewarmAlbumArtCache(tracks, maxCount: tracks.length);
  }

  /// Playlist indices in [sourceOrder] that should get [MediaItem.artUri] when
  /// building a concat source. Large libraries only tag the current item so
  /// scan/load does not rasterize thousands of covers.
  List<int> _notificationArtPlaylistIndices(
    List<int> sourceOrder,
    int logical,
  ) {
    if (sourceOrder.isEmpty) return const <int>[];
    if (_playlist.length <= 80) return List<int>.from(sourceOrder);
    final pos = sourceOrder.indexOf(logical);
    if (pos < 0) return <int>[logical];
    const radius = 2;
    final out = <int>{};
    for (var d = -radius; d <= radius; d++) {
      final i = pos + d;
      if (i >= 0 && i < sourceOrder.length) {
        out.add(sourceOrder[i]);
      }
    }
    return out.toList();
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
    if (pl < 0 || pl >= _playlist.length) return false;
    final fp = _playlist[pl].filePath?.trim();
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
    _playlist = List<TrackItem>.from(tracks);
    _index = _playlist.isEmpty ? 0 : startIndex.clamp(0, _playlist.length - 1);
    if (preserveShuffle) {
      final cur = _index;
      final order = List<int>.generate(_playlist.length, (j) => j)..shuffle();
      order.remove(cur);
      _shuffleOrder = [cur, ...order];
      _shufflePos = 0;
      _shuffle = true;
    } else if (enableShuffle && tracks.length > 1) {
      final cur = _index;
      final order = List<int>.generate(_playlist.length, (j) => j)..shuffle();
      order.remove(cur);
      _shuffleOrder = [cur, ...order];
      _shufflePos = 0;
      _shuffle = true;
    } else {
      _resetShuffleState();
    }
    notifyListeners();
    await _loadCurrent();
    _sourceNeedsReload = false;
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
    if (_playlist.isEmpty) return false;

    final byKey = <String, TrackItem>{};
    for (final t in catalogTracks) {
      final fp = t.filePath?.trim();
      if (fp == null || fp.isEmpty) continue;
      final k = canonicalMusicLibraryPathKey(fp);
      if (k.isNotEmpty) byKey[k] = t;
    }
    if (byKey.isEmpty) return true;

    var changed = false;
    for (var i = 0; i < _playlist.length; i++) {
      final fp = _playlist[i].filePath?.trim();
      if (fp == null || fp.isEmpty) continue;
      final k = canonicalMusicLibraryPathKey(fp);
      final fresh = byKey[k];
      if (fresh != null && fresh != _playlist[i]) {
        _playlist[i] = fresh;
        changed = true;
      }
    }
    if (changed) notifyListeners();
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

    final pathPreserve = currentTrack?.filePath?.trim();
    final keepShuffle = _shuffle && tracks.length > 1;
    _playlist = List<TrackItem>.from(tracks);

    var newIndex = 0;
    if (pathPreserve != null && pathPreserve.isNotEmpty) {
      final preserveKey = canonicalMusicLibraryPathKey(pathPreserve);
      if (preserveKey.isNotEmpty) {
        final ix = _playlist.indexWhere(
          (t) =>
              canonicalMusicLibraryPathKey((t.filePath ?? '').trim()) ==
              preserveKey,
        );
        if (ix >= 0) newIndex = ix;
      }
    }

    if (keepShuffle) {
      final cur = newIndex;
      final order = List<int>.generate(_playlist.length, (j) => j)..shuffle();
      order.remove(cur);
      _shuffleOrder = [cur, ...order];
      _shufflePos = 0;
      _index = cur;
      _shuffle = true;
    } else {
      _resetShuffleState();
      _index = newIndex;
    }

    notifyListeners();
    await _loadCurrent(initialPosition: resumePosition, stopBeforeLoad: false);
    _sourceNeedsReload = false;
    if (resumePlaying) {
      _playbackPausedByUser = false;
      await _resumePlaybackAfterLoad(
        context: 'tryResyncQueueWithLibraryScan.play',
      );
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
    final wasEmpty = _playlist.isEmpty;
    final resumePos = wasEmpty ? Duration.zero : _player.position;
    if (_shuffle && _playlist.isNotEmpty) {
      _index = _shuffleOrder[_shufflePos].clamp(0, _playlist.length - 1);
      _shuffle = false;
      _shuffleOrder = [];
      _shufflePos = 0;
    }
    _playlist = [..._playlist, ...items];
    notifyListeners();
    if (wasEmpty) {
      _index = 0;
      await _loadCurrent();
      await _resumePlaybackAfterLoad(
        context: 'appendToPlaylist.play',
      );
    } else {
      await _loadCurrent(initialPosition: resumePos);
    }
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
    await _resumePlaybackAfterLoad(
      context: 'setPlaylistAndPlay.play',
    );
  }

  static bool _sameQueuedIdentity(TrackItem a, TrackItem b) {
    final pa = a.filePath;
    final pb = b.filePath;
    if (pa != null && pa.isNotEmpty && pb != null && pb.isNotEmpty) {
      return pa == pb;
    }
    return a.title == b.title && a.artist == b.artist;
  }

  /// Whether [track] is already in the queue (same path or same title + artist).
  bool isTrackInPlaylist(TrackItem track) =>
      _playlist.any((t) => _sameQueuedIdentity(t, track));

  /// Appends [track] to the end of the queue only if it is not already present.
  /// Returns `false` if it was already queued (same file path, or same title + artist
  /// when paths are missing). Starts playback if the queue was empty and the track
  /// was added.
  Future<bool> addToPlaylistIfAbsent(TrackItem track) async {
    if (_playlist.any((t) => _sameQueuedIdentity(t, track))) {
      return false;
    }
    await appendToPlaylist([track]);
    return true;
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
    if (_playlist.isEmpty) {
      await setPlaylistAndPlay([track], playbackOriginTab: playbackOriginTab);
      return true;
    }

    int? existingIx;
    for (var i = 0; i < _playlist.length; i++) {
      if (_sameQueuedIdentity(_playlist[i], track)) {
        existingIx = i;
        break;
      }
    }

    if (!_shuffle) {
      if (existingIx == _index) {
        return false;
      }
      if (existingIx != null) {
        _playlist.removeAt(existingIx);
        if (existingIx < _index) {
          _index--;
        }
      }
      final insertAt = (_index + 1).clamp(0, _playlist.length);
      _playlist.insert(insertAt, track);
      _sourceNeedsReload = true;
      notifyListeners();
      return true;
    }

    final curPl = _logicalPlaylistIndex();
    if (existingIx != null && existingIx == curPl) {
      return false;
    }
    if (existingIx != null) {
      _removePlaylistIndexWhileShuffling(existingIx);
    }
    if (!_shuffle) {
      int? ex;
      for (var i = 0; i < _playlist.length; i++) {
        if (_sameQueuedIdentity(_playlist[i], track)) {
          ex = i;
          break;
        }
      }
      if (ex == _index) {
        return false;
      }
      if (ex != null) {
        _playlist.removeAt(ex);
        if (ex < _index) {
          _index--;
        }
      }
      final insertAt = (_index + 1).clamp(0, _playlist.length);
      _playlist.insert(insertAt, track);
      _sourceNeedsReload = true;
      notifyListeners();
      return true;
    }

    _playlist.add(track);
    final newIx = _playlist.length - 1;
    final insertPos = (_shufflePos + 1).clamp(0, _shuffleOrder.length);
    _shuffleOrder.insert(insertPos, newIx);

    _sourceNeedsReload = true;
    notifyListeners();
    return true;
  }

  void _removePlaylistIndexWhileShuffling(int rm) {
    final curKey = canonicalMusicLibraryPathKey(
      (currentTrack?.filePath ?? '').trim(),
    );
    _playlist.removeAt(rm);
    final nextOrder = <int>[];
    for (final oi in _shuffleOrder) {
      if (oi == rm) continue;
      nextOrder.add(oi > rm ? oi - 1 : oi);
    }
    _shuffleOrder = nextOrder;
    if (_shuffleOrder.isEmpty) {
      if (_playlist.isEmpty) {
        _resetShuffleState();
        return;
      }
      _shuffle = false;
      _shuffleOrder = [];
      _shufflePos = 0;
      _index = _index.clamp(0, _playlist.length - 1);
      return;
    }
    if (curKey.isEmpty) {
      _shufflePos = _shufflePos.clamp(0, _shuffleOrder.length - 1);
      _index = _shuffleOrder[_shufflePos].clamp(0, _playlist.length - 1);
      return;
    }
    var found = false;
    for (var i = 0; i < _shuffleOrder.length; i++) {
      final pi = _shuffleOrder[i];
      if (pi < 0 || pi >= _playlist.length) continue;
      final fp = _playlist[pi].filePath?.trim() ?? '';
      if (fp.isNotEmpty && canonicalMusicLibraryPathKey(fp) == curKey) {
        _shufflePos = i;
        _index = pi;
        found = true;
        break;
      }
    }
    if (!found) {
      _shufflePos = 0;
      _index = _shuffleOrder[0].clamp(0, _playlist.length - 1);
    }
  }

  /// Resolves [filePath] to a library row when possible (same rules as Library sheets).
  TrackItem trackForLibraryPath(String filePath) {
    final raw = filePath.trim();
    if (raw.isEmpty) return TrackItem.fromFilePath(filePath);
    final key = canonicalMusicLibraryPathKey(raw);
    if (key.isNotEmpty) {
      for (final t in _libraryCatalog) {
        final fp = t.filePath;
        if (fp == null || fp.isEmpty) continue;
        if (canonicalMusicLibraryPathKey(fp) == key) return t;
      }
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
    final shouldRefreshNotificationArt = curKey == key &&
        cur != null &&
        updated.albumArtBytes != null &&
        updated.albumArtBytes!.isNotEmpty &&
        (cur.albumArtBytes == null ||
            cur.albumArtBytes!.isEmpty ||
            !listEquals(cur.albumArtBytes, updated.albumArtBytes));

    var changed = false;
    for (var i = 0; i < _playlist.length; i++) {
      final fp = _playlist[i].filePath;
      if (fp != null && canonicalMusicLibraryPathKey(fp) == key) {
        _playlist[i] = updated;
        changed = true;
      }
    }
    for (var c = 0; c < _libraryCatalog.length; c++) {
      final fp = _libraryCatalog[c].filePath;
      if (fp != null && canonicalMusicLibraryPathKey(fp) == key) {
        _libraryCatalog[c] = updated;
        changed = true;
      }
    }
    if (changed) {
      _notifyCatalogListeners(notify);
      if (!_isLoadingSource &&
          (shouldRefreshNotificationArt ||
              (refreshNotificationArt && curKey == key))) {
        _scheduleNotificationArtRefresh();
      }
    }
  }

  /// Re-push notification [MediaItem.artUri] (e.g. after theme change).
  void scheduleNotificationArtRefresh() => _scheduleNotificationArtRefresh();

  void _scheduleNotificationArtRefresh() {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    if (_isLoadingSource || _notificationArtRefreshInProgress) return;
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
    if (_playlist.isEmpty) return;
    if (_notificationArtRefreshInProgress) return;
    _notificationArtRefreshInProgress = true;
    try {
      final track = currentTrack;
      final fp = track?.filePath?.trim();
      if (track == null || fp == null || fp.isEmpty) return;
      final trackKey = canonicalMusicLibraryPathKey(fp);
      final artUri = await uriForNotificationAlbumArt(track);
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
      notifyListeners();
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
  void replaceTrackPath(
    String oldPath,
    TrackItem updated, {
    Duration? resumePosition,
    bool? resumePlaying,
  }) {
    final currentPathBeforeReplace = currentTrack?.filePath;
    final isCurrentTrackPathBeingReplaced =
        currentPathBeforeReplace != null &&
        canonicalMusicLibraryPathKey(currentPathBeforeReplace) ==
            canonicalMusicLibraryPathKey(oldPath);
    final resumePlayingAfterReload =
        resumePlaying ?? (isCurrentTrackPathBeingReplaced && _player.playing);
    final resumePositionAfterReload =
        resumePosition ??
        (isCurrentTrackPathBeingReplaced ? _player.position : Duration.zero);
    final oldKey = canonicalMusicLibraryPathKey(oldPath);
    var changed = false;
    for (var i = 0; i < _playlist.length; i++) {
      final fp = _playlist[i].filePath;
      if (fp != null && canonicalMusicLibraryPathKey(fp) == oldKey) {
        _playlist[i] = updated;
        changed = true;
      }
    }
    for (var c = 0; c < _libraryCatalog.length; c++) {
      final fp = _libraryCatalog[c].filePath;
      if (fp != null && canonicalMusicLibraryPathKey(fp) == oldKey) {
        _libraryCatalog[c] = updated;
        changed = true;
      }
    }
    if (!changed) return;
    // The currently loaded audio source still points to old file URIs.
    _sourceNeedsReload = true;
    notifyListeners();

    // Only reload the audio pipeline when the renamed/replaced file is the
    // track currently loaded in the player.  For any other track in the queue,
    // just leave _sourceNeedsReload = true so the pipeline is rebuilt lazily
    // on the next skip/play — calling _loadCurrent for a non-current entry
    // would hit setAudioSource and interrupt the currently playing song.
    if (!isCurrentTrackPathBeingReplaced) return;

    unawaited(() async {
      await _loadCurrent(
        initialPosition: resumePositionAfterReload,
        stopBeforeLoad: false, // already stopped by stopForExternalFileEdit
      );
      if (resumePlayingAfterReload) {
        _playbackPausedByUser = false;
        await _resumePlaybackAfterLoad(
          context: 'replaceTrackPath.resumePlay',
        );
      }
    }());
  }

  bool _prunePlaylistPathsNotInCatalog() {
    if (_libraryCatalog.isEmpty || _playlist.isEmpty) return false;
    final validKeys = <String>{};
    for (final t in _libraryCatalog) {
      final fp = t.filePath?.trim();
      if (fp == null || fp.isEmpty) continue;
      final k = canonicalMusicLibraryPathKey(fp);
      if (k.isNotEmpty) validKeys.add(k);
    }
    if (validKeys.isEmpty) return false;

    final before = _playlist.length;
    _playlist.removeWhere((t) {
      final fp = t.filePath;
      if (fp == null || fp.trim().isEmpty) return true;
      final k = canonicalMusicLibraryPathKey(fp);
      if (k.isEmpty) return true;
      return !validKeys.contains(k);
    });
    if (_playlist.length == before) return false;

    if (_playlist.isEmpty) {
      _index = 0;
      _resetShuffleState();
    } else {
      _index = _index.clamp(0, _playlist.length - 1);
      if (_shuffle) {
        _shuffleOrder = List<int>.generate(_playlist.length, (i) => i);
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
    if (_playlist.isEmpty || i < 0 || i >= _playlist.length) return;

    if (_shuffle) {
      _index = currentIndex.clamp(0, _playlist.length - 1);
      _resetShuffleState();
    }

    final isCurrent = i == _index;
    if (isCurrent) {
      await stopForExternalFileEdit();
    }

    _playlist.removeAt(i);

    final len = _playlist.length;
    if (len == 0) {
      _index = 0;
      notifyListeners();
      return;
    }

    if (i < _index) {
      _index--;
    } else if (isCurrent) {
      _index = i.clamp(0, len - 1);
    }

    notifyListeners();
    if (isCurrent) {
      await _loadCurrent();
      if (resumePlayingIfCurrentRemoved) {
        await _resumePlaybackAfterLoad(
          context: 'removePlaylistEntryAt.resume',
        );
      }
    } else {
      await _loadCurrent(initialPosition: _player.position);
    }
  }

  Future<void> jumpToIndex(int i, {bool autoPlay = true}) async {
    if (i < 0 || i >= _playlist.length) return;
    if (autoPlay) {
      _playbackPausedByUser = false;
    }
    if (_playbackPathKeysScope != null && !_playlistIndexMatchesScope(i)) {
      _playbackPathKeysScope = null;
    }
    if (_shuffle) {
      _shuffleOrder.remove(i);
      final rest = List<int>.generate(_playlist.length, (j) => j)
        ..remove(i)
        ..shuffle();
      _shuffleOrder = [i, ...rest];
      _shufflePos = 0;
    } else {
      _index = i;
    }
    notifyListeners();
    await _loadCurrent();
    if (autoPlay) {
      await _resumePlaybackAfterLoad(
        context: 'jumpToIndex.play',
      );
    }
  }

  /// Reorders [playbackOrderIndices] without interrupting the loaded current source.
  void reorderPlaybackQueue(int oldOrderIndex, int newOrderIndex) {
    if (!canReorderPlaybackQueue) return;
    final order = _effectiveQueueOrder();
    if (order.isEmpty) return;
    if (oldOrderIndex < 0 || oldOrderIndex >= order.length) return;
    newOrderIndex = newOrderIndex.clamp(0, order.length - 1);
    if (oldOrderIndex == newOrderIndex) return;

    if (_shuffle) {
      final curPl = _logicalPlaylistIndex();
      final perm = List<int>.from(_shuffleOrder);
      final moved = perm.removeAt(oldOrderIndex);
      perm.insert(newOrderIndex, moved);
      _shuffleOrder = perm;
      _shufflePos = _shuffleOrder.indexOf(curPl);
      if (_shufflePos < 0) _shufflePos = 0;
    } else {
      final moving = _playlist.removeAt(oldOrderIndex);
      _playlist.insert(newOrderIndex, moving);
      if (oldOrderIndex == _index) {
        _index = newOrderIndex;
      } else if (oldOrderIndex < _index && newOrderIndex >= _index) {
        _index--;
      } else if (oldOrderIndex > _index && newOrderIndex <= _index) {
        _index++;
      }
    }

    _sourceNeedsReload = true;
    notifyListeners();
  }

  Future<void> _loadCurrent({
    Duration initialPosition = Duration.zero,
    bool stopBeforeLoad = true,
    bool retryAfterMissingPath = true,
  }) async {
    final preview = currentTrack;
    final pathPreview = preview?.filePath;
    if (preview == null || pathPreview == null || pathPreview.isEmpty) {
      _suppressTrackCompletedAdvance = false;
      if (stopBeforeLoad) {
        try {
          await _player.stop();
        } catch (_) {}
      }
      _activeSourceOrder = <int>[];
      notifyListeners();
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
      if (_prunePlaylistPathsNotInCatalog() && _playlist.isNotEmpty) {
        notifyListeners();
      }
      final order = _effectiveQueueOrder();
      if (order.isEmpty || _playlist.isEmpty) {
        try {
          await _player.stop();
        } catch (_) {}
        _activeSourceOrder = <int>[];
        notifyListeners();
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
      if (logical < 0 || logical >= _playlist.length) {
        logical = order.first.clamp(0, _playlist.length - 1);
        _index = logical;
        if (_shuffle) {
          final spi = _shuffleOrder.indexOf(logical);
          _shufflePos = spi >= 0 ? spi : 0;
        }
      }

      final enrichPath = _playlist[logical].filePath?.trim();
      if (enrichPath != null &&
          enrichPath.isNotEmpty &&
          (_playlist[logical].albumArtBytes == null ||
              _playlist[logical].albumArtBytes!.isEmpty)) {
        final enriched = await readAudioMetadata(_playlist[logical]);
        if (enriched.albumArtBytes != null &&
            enriched.albumArtBytes!.isNotEmpty) {
          updateTrackByPath(
            enrichPath,
            enriched,
            refreshNotificationArt: false,
          );
        }
      }

      final children = <AudioSource>[];
      final loadedOrder = <int>[];
      var initialConcatIndex = 0;
      var concatPos = 0;
      final sourceOrder = _useSingleTrackAudioSourceForPlatform()
          ? <int>[logical]
          : order;

      final logicalTrack = logical >= 0 && logical < _playlist.length
          ? _playlist[logical]
          : preview;
      final artIndices = _notificationArtPlaylistIndices(sourceOrder, logical);
      final notificationArtUris = <int, Uri?>{};
      await Future.wait(
        artIndices.map((pi) async {
          if (pi < 0 || pi >= _playlist.length) return;
          notificationArtUris[pi] =
              await uriForNotificationAlbumArt(_playlist[pi]);
        }),
      );
      if (logical >= 0 &&
          logical < _playlist.length &&
          !notificationArtUris.containsKey(logical)) {
        notificationArtUris[logical] =
            await uriForNotificationAlbumArt(logicalTrack);
      }

      for (final pi in sourceOrder) {
        if (pi < 0 || pi >= _playlist.length) continue;
        final t = _playlist[pi];
        final fp = t.filePath?.trim();
        if (fp == null || fp.isEmpty) continue;

        final artUri = notificationArtUris[pi];
        children.add(
          AudioSource.uri(
            Uri.file(fp),
            tag: MediaItem(
              id: fp,
              title: t.title,
              artist: t.artist,
              album: t.metaLine,
              artUri: artUri,
            ),
          ),
        );
        loadedOrder.add(pi);
        if (pi == logical) {
          initialConcatIndex = concatPos;
        }
        concatPos++;
      }

      if (children.isEmpty) {
        _activeSourceOrder = <int>[];
        notifyListeners();
        return;
      }
      initialConcatIndex = initialConcatIndex.clamp(0, children.length - 1);
      _activeSourceOrder = loadedOrder;

      if (_useSingleTrackAudioSourceForPlatform()) {
        await _player.setAudioSource(
          children.single,
          initialPosition: initialPosition,
        );
      } else {
        await _player.setAudioSource(
          ConcatenatingAudioSource(
            useLazyPreparation: _concatUseLazyPreparationForPlatform(),
            children: children,
          ),
          initialIndex: initialConcatIndex,
          initialPosition: initialPosition,
        );
      }
      await _applyPreferredVolume();
      _postLoadExpectedConcatIndex = initialConcatIndex;
      _postLoadConcatGuardUntil = DateTime.now().add(
        const Duration(milliseconds: 650),
      );
      _sourceNeedsReload = false;
    } catch (e, st) {
      debugPrint('Playback load error: $e\n$st');
      if (retryAfterMissingPath) {
        final missingPath = _extractMissingPathFromLoadError(e);
        if (missingPath != null && missingPath.isNotEmpty) {
          final removed = _removeMissingTrackPath(missingPath);
          if (removed && _playlist.isNotEmpty) {
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
        notifyListeners();
      }
    }
    _prewarmPlaybackAlbumArt();
    notifyListeners();
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
    final beforePlaylist = _playlist.length;
    _playlist.removeWhere((t) => t.filePath == path);
    final beforeCatalog = _libraryCatalog.length;
    _libraryCatalog.removeWhere((t) => t.filePath == path);

    if (_playlist.isEmpty) {
      _index = 0;
      _resetShuffleState();
    } else {
      if (_index >= _playlist.length) {
        _index = _playlist.length - 1;
      }
      if (_shuffle) {
        _shuffleOrder = List<int>.generate(_playlist.length, (i) => i);
        if (_shufflePos >= _shuffleOrder.length) {
          _shufflePos = _shuffleOrder.length - 1;
        }
      }
    }

    final changed =
        _playlist.length != beforePlaylist ||
        _libraryCatalog.length != beforeCatalog;
    if (changed) notifyListeners();
    return changed;
  }

  /// Whether [path] refers to the same file as the current queue item (normalized).
  bool isCurrentTrackFilePath(String path) {
    final cur = currentTrack?.filePath;
    if (cur == null || cur.trim().isEmpty || path.trim().isEmpty) {
      return false;
    }
    return canonicalMusicLibraryPathKey(cur) ==
        canonicalMusicLibraryPathKey(path);
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
      await _resumePlaybackAfterLoad(
        context: 'reloadCurrentSource.play',
      );
    }
  }

  /// Reload after [stopForExternalFileEdit] rewrote tags on the playing file.
  Future<void> reloadCurrentSourceAfterTagWrite({
    required Duration resumePosition,
    required bool resumePlaying,
  }) =>
      reloadCurrentSource(
        initialPosition: resumePosition,
        resumePlaying: resumePlaying,
        stopBeforeLoad: false,
      );

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
    try {
      await _player.stop();
    } catch (_) {}
  }

  /// Coalesce stream-driven UI updates (e.g. notification play/pause) to one frame.
  void _schedulePlayerUiNotify() {
    if (_playerUiNotifyScheduled) return;
    _playerUiNotifyScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _playerUiNotifyScheduled = false;
      notifyListeners();
    });
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

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> _seekToPlaylistIndexFast(
    int playlistIndex, {
    required String playContext,
  }) async {
    if (_sourceNeedsReload || _useSingleTrackAudioSourceForPlatform()) {
      await _loadCurrent();
      _sourceNeedsReload = false;
      await _resumePlaybackAfterLoad(context: playContext);
      return;
    }
    final order = _activeSourceOrder.isNotEmpty
        ? _activeSourceOrder
        : _effectiveQueueOrder();
    final concatIndex = order.indexOf(playlistIndex);
    if (concatIndex < 0) {
      await _loadCurrent();
      _sourceNeedsReload = false;
      await _resumePlaybackAfterLoad(context: playContext);
      return;
    }
    try {
      await _player.seek(Duration.zero, index: concatIndex);
      await _waitForPlayerPreparedAfterSourceChange();
      final actual = _player.currentIndex;
      if (actual != null && actual != concatIndex) {
        await _loadCurrent();
        _sourceNeedsReload = false;
        await _resumePlaybackAfterLoad(context: playContext);
        return;
      }
      await _playSafely(context: playContext);
    } catch (_) {
      await _loadCurrent();
      _sourceNeedsReload = false;
      await _resumePlaybackAfterLoad(context: playContext);
    }
  }

  /// Next track; at end pauses unless [PlaylistRepeatMode.all].
  Future<void> skipNext() async {
    if (_playlist.isEmpty) return;
    _playbackPausedByUser = false;
    _manualQueueAdvance = true;
    try {
      await _skipNextImpl();
    } finally {
      _manualQueueAdvance = false;
      notifyListeners();
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
    if (_playlist.isEmpty) return;
    _playbackPausedByUser = false;
    _manualQueueAdvance = true;
    try {
      await _skipPreviousImpl();
    } finally {
      _manualQueueAdvance = false;
      notifyListeners();
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
    if (_playlist.length < 2) return;
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
      final order = List<int>.generate(_playlist.length, (j) => j)..shuffle();
      order.remove(cur);
      _shuffleOrder = [cur, ...order];
      _shufflePos = 0;
      _shuffle = true;
    }
    notifyListeners();
  }

  void cycleRepeatMode() {
    _repeat = switch (_repeat) {
      PlaylistRepeatMode.off => PlaylistRepeatMode.all,
      PlaylistRepeatMode.all => PlaylistRepeatMode.one,
      PlaylistRepeatMode.one => PlaylistRepeatMode.off,
    };
    notifyListeners();
  }

  /// Persisted playback snapshot (`PlaybackSessionStore` v2 schema).
  Map<String, dynamic> buildPlaybackPersistenceJson() {
    final paths = _playlist.map((t) => t.filePath).whereType<String>().toList();
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

    _playlist = List<TrackItem>.from(queue);

    if (_playlist.isEmpty) {
      _resetShuffleState();
      _index = 0;
      try {
        await _player.stop();
      } catch (_) {}
      notifyListeners();
      return;
    }

    final n = _playlist.length;
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

    notifyListeners();

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
    notifyListeners();
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

  @override
  void dispose() {
    _catalogNotifyThrottleTimer?.cancel();
    _catalogNotifyThrottleTimer = null;
    _catalogNotifyThrottlePending = false;
    _notificationArtRefreshDebounce?.cancel();
    _notificationArtRefreshDebounce = null;
    _audioInterruptionSub?.cancel();
    _audioInterruptionSub = null;
    _becomingNoisySub?.cancel();
    _becomingNoisySub = null;
    _devicesChangedSub?.cancel();
    _devicesChangedSub = null;
    _concatIndexSub?.cancel();
    _playerStateSub.cancel();
    unawaited(() async {
      try {
        await _player.dispose();
      } catch (e, st) {
        debugPrint('AudioPlayer dispose error: $e\n$st');
      }
    }());
    super.dispose();
  }
}

/// Holds [PlayerController] above [MaterialApp]. `InheritedNotifier` is abstract in
/// current Flutter SDKs, so this uses a plain [InheritedWidget] instead.
class PlayerControllerScope extends InheritedWidget {
  const PlayerControllerScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final PlayerController controller;

  @override
  bool updateShouldNotify(PlayerControllerScope oldWidget) =>
      controller != oldWidget.controller;
}
