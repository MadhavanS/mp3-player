import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:just_audio/just_audio.dart';

/// Throttled position/duration for seek bars (~2 updates/sec).
class PositionNotifier extends ChangeNotifier {
  PositionNotifier(this._player);

  final AudioPlayer _player;
  static const _notifyInterval = Duration(milliseconds: 500);

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  Timer? _pendingNotify;
  Duration _lastNotifiedPosition = Duration.zero;
  Duration? _lastNotifiedDuration;

  Duration get position => _player.position;
  Duration? get duration => _player.duration;

  void attach() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _positionSub = _player.positionStream.listen(_onPosition);
    _durationSub = _player.durationStream.listen(_onDuration);
  }

  void detach() {
    _pendingNotify?.cancel();
    _pendingNotify = null;
    _positionSub?.cancel();
    _positionSub = null;
    _durationSub?.cancel();
    _durationSub = null;
  }

  void _onPosition(Duration value) {
    if (value == _lastNotifiedPosition) return;
    _scheduleThrottledNotify(() {
      _lastNotifiedPosition = value;
    });
  }

  void _onDuration(Duration? value) {
    if (value == _lastNotifiedDuration) {
      return;
    }
    _lastNotifiedDuration = value;
    notifyListeners();
  }

  /// After seek/skip, refresh the bar immediately.
  void flush() {
    _pendingNotify?.cancel();
    _pendingNotify = null;
    _lastNotifiedPosition = _player.position;
    _lastNotifiedDuration = _player.duration;
    notifyListeners();
  }

  void _scheduleThrottledNotify(void Function() beforeNotify) {
    if (_pendingNotify != null) return;
    _pendingNotify = Timer(_notifyInterval, () {
      _pendingNotify = null;
      beforeNotify();
      notifyListeners();
    });
  }

  @override
  void dispose() {
    detach();
    super.dispose();
  }
}

/// Current track identity / tags / art (changes on skip or metadata enrich).
class TrackNotifier extends ChangeNotifier {
  void notifyNow() => notifyListeners();
}

/// Play/pause, processing, volume UI.
class PlaybackNotifier extends ChangeNotifier {
  void notifyNow() => notifyListeners();

  void notifyCoalesced() {
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _scheduled = false;
      notifyListeners();
    });
  }

  bool _scheduled = false;
}

/// Playlist, shuffle, repeat, library catalog.
class QueueNotifier extends ChangeNotifier {
  Timer? _throttle;
  bool _pending = false;

  void notifyNow() => notifyListeners();

  void notifyThrottled() {
    _pending = true;
    _throttle ??= Timer(const Duration(milliseconds: 200), () {
      _throttle = null;
      if (_pending) {
        _pending = false;
        notifyListeners();
      }
    });
  }

  void cancelThrottle() {
    _throttle?.cancel();
    _throttle = null;
    _pending = false;
  }

  @override
  void dispose() {
    cancelThrottle();
    super.dispose();
  }
}

/// Merges notifiers for widgets that need multiple signals (not position).
Listenable mergeTrackPlaybackQueue(
  TrackNotifier track,
  PlaybackNotifier playback,
  QueueNotifier queue,
) {
  return Listenable.merge([track, playback, queue]);
}
