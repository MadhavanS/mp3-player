import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

import '../models/track_item.dart';

enum PlaylistRepeatMode { off, all, one }

/// Local playback + playlist index. Exposes [audioPlayer] for streams in the UI.
class PlayerController extends ChangeNotifier {
  PlayerController() {
    _playerStateSub = _player.playerStateStream.listen((_) => notifyListeners());
    _processingSub = _player.processingStateStream.listen(_onProcessingState);
  }

  final AudioPlayer _player = AudioPlayer();
  late final StreamSubscription<PlayerState> _playerStateSub;
  late final StreamSubscription<ProcessingState> _processingSub;

  List<TrackItem> _playlist = [];
  int _index = 0;

  bool _shuffle = false;
  List<int> _shuffleOrder = [];
  int _shufflePos = 0;

  PlaylistRepeatMode _repeat = PlaylistRepeatMode.off;
  ProcessingState? _previousProcessing;
  bool _isLoadingSource = false;

  AudioPlayer get audioPlayer => _player;

  List<TrackItem> get playlist => _playlist;

  /// Index into [playlist] for the currently playing file (list row / highlight).
  int get currentIndex {
    if (_playlist.isEmpty) return 0;
    return _shuffle ? _shuffleOrder[_shufflePos] : _index;
  }

  TrackItem? get currentTrack =>
      _playlist.isEmpty ? null : _playlist[currentIndex.clamp(0, _playlist.length - 1)];

  bool get shuffleEnabled => _shuffle;
  PlaylistRepeatMode get repeatMode => _repeat;

  bool get isPlaying => _player.playing;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;

  static PlayerController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PlayerControllerScope>();
    assert(scope != null, 'PlayerControllerScope not found above MaterialApp');
    return scope!.controller;
  }

  void _onProcessingState(ProcessingState state) {
    if (_isLoadingSource) {
      _previousProcessing = state;
      return;
    }
    final enteredComplete = _previousProcessing != ProcessingState.completed &&
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
      await _player.play();
      return;
    }
    await skipNext();
  }

  void _resetShuffleState() {
    _shuffle = false;
    _shuffleOrder = [];
    _shufflePos = 0;
  }

  Future<void> setPlaylist(List<TrackItem> tracks, {int startIndex = 0}) async {
    _playlist = List<TrackItem>.from(tracks);
    _resetShuffleState();
    _index = _playlist.isEmpty ? 0 : startIndex.clamp(0, _playlist.length - 1);
    notifyListeners();
    await _loadCurrent();
  }

  void updateTrackByPath(String path, TrackItem updated) {
    final i = _playlist.indexWhere((t) => t.filePath == path);
    if (i < 0) return;
    _playlist[i] = updated;
    notifyListeners();
  }

  /// Replace the playlist entry for [oldPath] with [updated] (new path + tags).
  /// Reloads the audio source when the renamed file is currently playing.
  void replaceTrackPath(String oldPath, TrackItem updated) {
    final i = _playlist.indexWhere((t) => t.filePath == oldPath);
    if (i < 0) return;
    final currentPath = currentTrack?.filePath;
    _playlist[i] = updated;
    notifyListeners();
    if (currentPath == oldPath) {
      unawaited(_loadCurrent());
    }
  }

  Future<void> jumpToIndex(int i, {bool autoPlay = true}) async {
    if (i < 0 || i >= _playlist.length) return;
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
      await _player.play();
    }
  }

  Future<void> _loadCurrent() async {
    final path = currentTrack?.filePath;
    if (path == null || path.isEmpty) {
      try {
        await _player.stop();
      } catch (_) {}
      notifyListeners();
      return;
    }
    _isLoadingSource = true;
    try {
      await _player.setFilePath(path);
    } catch (e, st) {
      debugPrint('Playback load error: $e\n$st');
    } finally {
      _isLoadingSource = false;
    }
    notifyListeners();
  }

  /// Reload the current file from disk (e.g. after embedded tags were rewritten).
  Future<void> reloadCurrentSource() async {
    await _loadCurrent();
  }

  /// Release the open audio file so another process (or this app) can rewrite it.
  Future<void> stopForExternalFileEdit() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> play() => _player.play();

  Future<void> pause() => _player.pause();

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> seek(Duration position) => _player.seek(position);

  /// Next track; at end pauses unless [PlaylistRepeatMode.all].
  Future<void> skipNext() async {
    if (_playlist.isEmpty) return;

    final atLast = _shuffle
        ? _shufflePos >= _shuffleOrder.length - 1
        : _index >= _playlist.length - 1;

    if (atLast) {
      if (_repeat == PlaylistRepeatMode.all) {
        if (_shuffle) {
          _shufflePos = 0;
        } else {
          _index = 0;
        }
      } else {
        await _player.pause();
        notifyListeners();
        return;
      }
    } else {
      if (_shuffle) {
        _shufflePos++;
      } else {
        _index++;
      }
    }

    notifyListeners();
    await _loadCurrent();
    await _player.play();
  }

  Future<void> skipPrevious() async {
    if (_playlist.isEmpty) return;

    final atFirst = _shuffle ? _shufflePos <= 0 : _index <= 0;

    if (atFirst) {
      if (_repeat == PlaylistRepeatMode.all) {
        if (_shuffle) {
          _shufflePos = _shuffleOrder.length - 1;
        } else {
          _index = _playlist.length - 1;
        }
      } else {
        await _player.seek(Duration.zero);
        notifyListeners();
        return;
      }
    } else {
      if (_shuffle) {
        _shufflePos--;
      } else {
        _index--;
      }
    }

    notifyListeners();
    await _loadCurrent();
    await _player.play();
  }

  void toggleShuffle() {
    if (_playlist.length < 2) return;
    if (_shuffle) {
      _index = _shuffleOrder[_shufflePos];
      _shuffle = false;
      _shuffleOrder = [];
      _shufflePos = 0;
    } else {
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

  @override
  void dispose() {
    _playerStateSub.cancel();
    _processingSub.cancel();
    _player.dispose();
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
