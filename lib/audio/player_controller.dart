import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../models/library_tab_id.dart';
import '../models/track_item.dart';
import '../services/music_library_path_key.dart';
import '../services/track_metadata.dart';
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

  /// After [setAudioSource], lazy [ConcatenatingAudioSource] can still be
  /// [ProcessingState.loading] when [_loadCurrent] returns — [play] then no-ops
  /// or fails on some devices. Wait for [ProcessingState.ready] when needed.
  Future<void> _resumePlaybackAfterLoad({
    String context = 'resumeAfterLoad',
  }) async {
    try {
      if (_player.processingState != ProcessingState.ready) {
        await _player.processingStateStream
            .where((s) => s == ProcessingState.ready)
            .first
            .timeout(const Duration(seconds: 8));
      }
    } catch (e, st) {
      debugPrint('_resumePlaybackAfterLoad wait: $e\n$st');
    }
    await _playSafely(context: context);
  }

  PlayerController() {
    // Single subscription: listening to [processingStateStream] and
    // [playerStateStream] both triggered platform init; concurrent inits caused
    // "Platform player … already exists" on some devices (just_audio / Android).
    _playerStateSub = _player.playerStateStream.listen((state) {
      _onProcessingState(state.processingState);
      final playing = state.playing;
      final proc = state.processingState;
      if (!_playerUiDispatchInitialized ||
          playing != _lastDispatchedPlaying ||
          proc != _lastDispatchedProcessing) {
        _playerUiDispatchInitialized = true;
        _lastDispatchedPlaying = playing;
        _lastDispatchedProcessing = proc;
        notifyListeners();
      }
    });
    _concatIndexSub = _player.currentIndexStream.listen(_onConcatIndexChanged);
  }

  final AudioPlayer _player = AudioPlayer();
  late final StreamSubscription<PlayerState> _playerStateSub;
  StreamSubscription<int?>? _concatIndexSub;

  List<TrackItem> _playlist = [];
  int _index = 0;

  bool _shuffle = false;
  List<int> _shuffleOrder = [];
  int _shufflePos = 0;

  PlaylistRepeatMode _repeat = PlaylistRepeatMode.off;
  ProcessingState? _previousProcessing;
  bool _isLoadingSource = false;
  int? _pendingConcatIndexWhileLoading;
  bool _sourceNeedsReload = false;
  List<int> _activeSourceOrder = <int>[];

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
    _previousProcessing = state;
    if (enteredComplete) {
      unawaited(_handleTrackCompleted());
    }
  }

  Future<void> _handleTrackCompleted() async {
    if (_playlist.isEmpty) return;
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
    if (_isLoadingSource) {
      _pendingConcatIndexWhileLoading = concatIdx;
      return;
    }
    if (_applyConcatIndexChanged(concatIdx)) {
      notifyListeners();
    }
  }

  Future<void> setPlaylist(
    List<TrackItem> tracks, {
    int startIndex = 0,
    LibraryTabId? playbackOriginTab,
    String? playbackOriginUserPlaylistId,
    bool keepShuffleMode = false,
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
    } else {
      _resetShuffleState();
    }
    notifyListeners();
    await _loadCurrent();
    _sourceNeedsReload = false;
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
      final ix = _playlist.indexWhere(
        (t) => (t.filePath ?? '').trim() == pathPreserve,
      );
      if (ix >= 0) newIndex = ix;
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
      await _playSafely(context: 'tryResyncQueueWithLibraryScan.play');
    } else {
      try {
        await _player.pause();
      } catch (_) {}
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
      await _playSafely(context: 'appendToPlaylist.play');
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
  }) async {
    await setPlaylist(
      tracks,
      startIndex: startIndex,
      playbackOriginTab: playbackOriginTab,
      playbackOriginUserPlaylistId: playbackOriginUserPlaylistId,
      keepShuffleMode: keepShuffleMode,
    );
    await _playSafely(context: 'setPlaylistAndPlay.play');
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
  }) {
    final key = canonicalMusicLibraryPathKey(path);
    if (key.isEmpty) return;
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
    if (changed) _notifyCatalogListeners(notify);
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
    unawaited(() async {
      await _loadCurrent(
        initialPosition: isCurrentTrackPathBeingReplaced
            ? resumePositionAfterReload
            : _player.position,
        stopBeforeLoad: isCurrentTrackPathBeingReplaced,
      );
      if (resumePlayingAfterReload) {
        await _resumePlaybackAfterLoad(context: 'replaceTrackPath.resumePlay');
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
      await _playSafely(context: 'jumpToIndex.play');
    }
  }

  Future<void> _loadCurrent({
    Duration initialPosition = Duration.zero,
    bool stopBeforeLoad = true,
    bool retryAfterMissingPath = true,
  }) async {
    final preview = currentTrack;
    final pathPreview = preview?.filePath;
    if (preview == null || pathPreview == null || pathPreview.isEmpty) {
      if (stopBeforeLoad) {
        try {
          await _player.stop();
        } catch (_) {}
      }
      _activeSourceOrder = <int>[];
      notifyListeners();
      return;
    }

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
          updateTrackByPath(enrichPath, enriched);
        }
      }

      final children = <AudioSource>[];
      final loadedOrder = <int>[];
      var initialConcatIndex = 0;
      var concatPos = 0;
      final logicalTrack = logical >= 0 && logical < _playlist.length
          ? _playlist[logical]
          : preview;
      final logicalArtUri = await uriForNotificationAlbumArt(logicalTrack);

      for (final pi in order) {
        if (pi < 0 || pi >= _playlist.length) continue;
        final t = _playlist[pi];
        final fp = t.filePath?.trim();
        if (fp == null || fp.isEmpty) continue;

        final artUri = pi == logical ? logicalArtUri : null;
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

      await _player.setAudioSource(
        ConcatenatingAudioSource(useLazyPreparation: true, children: children),
        initialIndex: initialConcatIndex,
        initialPosition: initialPosition,
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
      _isLoadingSource = false;
      final pending = _pendingConcatIndexWhileLoading;
      _pendingConcatIndexWhileLoading = null;
      if (pending != null && _applyConcatIndexChanged(pending)) {
        notifyListeners();
      }
    }
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
  Future<void> reloadCurrentSource({
    Duration? initialPosition,
    bool resumePlaying = false,
  }) async {
    final pos = initialPosition ?? _player.position;
    await _loadCurrent(initialPosition: pos);
    if (resumePlaying) {
      await _resumePlaybackAfterLoad(context: 'reloadCurrentSource.play');
    }
  }

  /// Same as [reloadCurrentSource] but does not block — for UI flows (tag sheets)
  /// where awaiting lazy [setAudioSource] prep can strand the sheet on “saving”.
  void reloadCurrentSourceUnawaited({
    Duration? initialPosition,
    bool resumePlaying = false,
  }) {
    unawaited(() async {
      try {
        await reloadCurrentSource(
          initialPosition: initialPosition,
          resumePlaying: resumePlaying,
        );
      } catch (e, st) {
        debugPrint('reloadCurrentSourceUnawaited: $e\n$st');
      }
    }());
  }

  /// Release the open audio file so another process (or this app) can rewrite it.
  Future<void> stopForExternalFileEdit() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> play() => _playSafely(context: 'play');

  Future<void> pause() => _player.pause();

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _playSafely(context: 'togglePlayPause.play');
    }
  }

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> _seekToPlaylistIndexFast(
    int playlistIndex, {
    required String playContext,
  }) async {
    if (_sourceNeedsReload) {
      await _loadCurrent();
      _sourceNeedsReload = false;
      await _playSafely(context: playContext);
      return;
    }
    final order = _activeSourceOrder.isNotEmpty
        ? _activeSourceOrder
        : _effectiveQueueOrder();
    final concatIndex = order.indexOf(playlistIndex);
    if (concatIndex < 0) {
      await _loadCurrent();
      _sourceNeedsReload = false;
      await _playSafely(context: playContext);
      return;
    }
    try {
      await _player.seek(Duration.zero, index: concatIndex);
      await _playSafely(context: playContext);
    } catch (_) {
      await _loadCurrent();
      _sourceNeedsReload = false;
      await _playSafely(context: playContext);
    }
  }

  /// Next track; at end pauses unless [PlaylistRepeatMode.all].
  Future<void> skipNext() async {
    if (_playlist.isEmpty) return;

    if (_shuffle) {
      final atLast = _shufflePos >= _shuffleOrder.length - 1;

      if (atLast) {
        if (_repeat == PlaylistRepeatMode.all) {
          _shufflePos = 0;
        } else {
          await _player.pause();
          notifyListeners();
          return;
        }
      } else {
        _shufflePos++;
      }

      notifyListeners();
      await _seekToPlaylistIndexFast(
        _shuffleOrder[_shufflePos],
        playContext: 'skipNext.shuffle play',
      );
      return;
    }

    final ordered = _playbackScopedIndices();
    if (ordered.isEmpty) {
      await _player.pause();
      notifyListeners();
      return;
    }

    final p = ordered.indexOf(_index);
    if (p < 0) {
      if (_playbackPathKeysScope != null) {
        _playbackPathKeysScope = null;
        await skipNext();
        return;
      }
      await _player.pause();
      notifyListeners();
      return;
    }

    if (p < ordered.length - 1) {
      _index = ordered[p + 1];
    } else if (_repeat == PlaylistRepeatMode.all) {
      _index = ordered.first;
    } else {
      await _player.pause();
      notifyListeners();
      return;
    }

    notifyListeners();
    await _seekToPlaylistIndexFast(_index, playContext: 'skipNext.play');
  }

  Future<void> skipPrevious() async {
    if (_playlist.isEmpty) return;

    if (_shuffle) {
      final atFirst = _shufflePos <= 0;

      if (atFirst) {
        if (_repeat == PlaylistRepeatMode.all) {
          _shufflePos = _shuffleOrder.length - 1;
        } else {
          await _player.seek(Duration.zero);
          notifyListeners();
          return;
        }
      } else {
        _shufflePos--;
      }

      notifyListeners();
      await _seekToPlaylistIndexFast(
        _shuffleOrder[_shufflePos],
        playContext: 'skipPrevious.shuffle play',
      );
      return;
    }

    final ordered = _playbackScopedIndices();
    if (ordered.isEmpty) {
      await _player.seek(Duration.zero);
      notifyListeners();
      return;
    }

    final p = ordered.indexOf(_index);
    if (p < 0) {
      if (_playbackPathKeysScope != null) {
        _playbackPathKeysScope = null;
        await skipPrevious();
        return;
      }
      await _player.seek(Duration.zero);
      notifyListeners();
      return;
    }

    if (p > 0) {
      _index = ordered[p - 1];
    } else if (_repeat == PlaylistRepeatMode.all) {
      _index = ordered.last;
    } else {
      await _player.seek(Duration.zero);
      notifyListeners();
      return;
    }

    notifyListeners();
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
      await _playSafely(context: 'applyRestoredPlayback.play');
    } else {
      await _player.pause();
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
