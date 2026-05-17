import 'dart:async';

import 'package:flutter/foundation.dart';
import 'player_controller.dart';

enum SleepTimerMode { duration, endOfSong }

/// Stops playback after a delay or when the current track finishes.
class SleepTimerController extends ChangeNotifier {
  SleepTimerController._();
  static final SleepTimerController instance = SleepTimerController._();

  Timer? _timer;
  PlayerController? _player;
  SleepTimerMode? _mode;
  DateTime? _endsAt;
  DateTime? _startedAt;
  Duration? _totalDuration;
  bool _active = false;

  bool get isActive => _active;
  SleepTimerMode? get mode => _mode;
  DateTime? get endsAt => _endsAt;
  Duration? get totalDuration => _totalDuration;

  Duration? get elapsed {
    final start = _startedAt;
    if (!_active || start == null) return null;
    return DateTime.now().difference(start);
  }

  Duration? get remaining {
    final end = _endsAt;
    if (!_active || end == null || _mode != SleepTimerMode.duration) {
      return null;
    }
    final left = end.difference(DateTime.now());
    if (left.isNegative) return Duration.zero;
    return left;
  }

  /// Compact label for the Now Playing status pill (minutes only).
  String get pillLabel {
    if (!_active) return '';
    if (_mode == SleepTimerMode.endOfSong) return 'Song end';
    final left = remaining;
    if (left == null) return '';
    final mins = (left.inSeconds + 59) ~/ 60;
    if (mins <= 0) return '<1 min';
    return mins == 1 ? '1 min' : '$mins min';
  }

  void startDuration(PlayerController player, Duration duration) {
    cancel();
    if (duration <= Duration.zero) return;
    _player = player;
    player.setStopAtTrackEndForSleepTimer(false);
    _mode = SleepTimerMode.duration;
    _active = true;
    _startedAt = DateTime.now();
    _totalDuration = duration;
    _endsAt = _startedAt!.add(duration);
    _timer = Timer(duration, () => unawaited(_expire(player)));
    notifyListeners();
  }

  void startEndOfSong(PlayerController player) {
    cancel();
    _player = player;
    _mode = SleepTimerMode.endOfSong;
    _active = true;
    _startedAt = DateTime.now();
    _totalDuration = null;
    _endsAt = null;
    player.registerSleepTimerTrackEndNotifier(_onSleepTimerTrackEndFired);
    player.setStopAtTrackEndForSleepTimer(true);
    notifyListeners();
  }

  void _onSleepTimerTrackEndFired() {
    if (!_active || _mode != SleepTimerMode.endOfSong) return;
    _timer?.cancel();
    _timer = null;
    _player?.registerSleepTimerTrackEndNotifier(null);
    _player = null;
    _mode = null;
    _endsAt = null;
    _startedAt = null;
    _totalDuration = null;
    _active = false;
    notifyListeners();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _player?.setStopAtTrackEndForSleepTimer(false);
    _player?.registerSleepTimerTrackEndNotifier(null);
    _player = null;
    _mode = null;
    _endsAt = null;
    _startedAt = null;
    _totalDuration = null;
    if (_active) {
      _active = false;
      notifyListeners();
    }
  }

  Future<void> _expire(PlayerController player) async {
    if (!_active) return;
    final target = _player ?? player;
    cancel();
    try {
      await target.pause();
    } catch (e, st) {
      debugPrint('SleepTimerController: pause failed: $e\n$st');
    }
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }
}
