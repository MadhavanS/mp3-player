import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

import '../models/track_item.dart';

/// Local playback + playlist index. Exposes [audioPlayer] for streams in the UI.
class PlayerController extends ChangeNotifier {
  PlayerController() {
    _playerStateSub = _player.playerStateStream.listen((_) => notifyListeners());
  }

  final AudioPlayer _player = AudioPlayer();
  late final StreamSubscription<PlayerState> _playerStateSub;

  List<TrackItem> _playlist = [];
  int _index = 0;

  AudioPlayer get audioPlayer => _player;

  List<TrackItem> get playlist => _playlist;
  int get currentIndex => _index;
  TrackItem? get currentTrack =>
      _playlist.isEmpty ? null : _playlist[_index.clamp(0, _playlist.length - 1)];

  bool get isPlaying => _player.playing;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;

  static PlayerController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PlayerControllerScope>();
    assert(scope != null, 'PlayerControllerScope not found above MaterialApp');
    return scope!.controller;
  }

  Future<void> setPlaylist(List<TrackItem> tracks, {int startIndex = 0}) async {
    _playlist = List<TrackItem>.from(tracks);
    _index = _playlist.isEmpty ? 0 : startIndex.clamp(0, _playlist.length - 1);
    notifyListeners();
    await _loadCurrent();
  }

  Future<void> jumpToIndex(int i, {bool autoPlay = true}) async {
    if (i < 0 || i >= _playlist.length) return;
    _index = i;
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
    try {
      await _player.setFilePath(path);
    } catch (e, st) {
      debugPrint('Playback load error: $e\n$st');
    }
    notifyListeners();
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

  Future<void> skipNext() async {
    if (_playlist.isEmpty) return;
    _index = (_index + 1) % _playlist.length;
    notifyListeners();
    await _loadCurrent();
    await _player.play();
  }

  Future<void> skipPrevious() async {
    if (_playlist.isEmpty) return;
    _index = (_index - 1 + _playlist.length) % _playlist.length;
    notifyListeners();
    await _loadCurrent();
    await _player.play();
  }

  @override
  void dispose() {
    _playerStateSub.cancel();
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
