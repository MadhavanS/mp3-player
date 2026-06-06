import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:just_audio_background/just_audio_background.dart';

import '../audio/player_controller.dart';

bool _justAudioBackgroundInitialized = false;
Future<void>? _ensureInFlight;
bool _playbackPlatformReady = false;
Future<void>? _readyFuture;

bool get _mediaNotificationSupported {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

/// Must run before the first [AudioPlayer] load/setAudioSource
/// ([runDeferredAppStartup] / [waitForPlaybackPlatformReady]).
Future<void> ensureJustAudioBackgroundInitialized() async {
  if (_justAudioBackgroundInitialized) return;
  _ensureInFlight ??= _ensureJustAudioBackgroundImpl();
  await _ensureInFlight!;
}

Future<void> _ensureJustAudioBackgroundImpl() async {
  if (_justAudioBackgroundInitialized) return;
  if (!_mediaNotificationSupported) return;

  await PlayerController.shutdownNativePlayer();
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.example.mp3_player.audio',
      androidNotificationChannelName: 'Now playing',
      androidNotificationChannelDescription:
          'Playback controls while the app is in the background.',
      androidNotificationIcon: 'drawable/ic_stat_music',
      // [androidStopForegroundOnPause] must stay false so notification pause is reliable.
      // audio_service forbids [androidNotificationOngoing] when that is false (ongoing
      // would have no effect anyway).
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
      preloadArtwork: true,
      artDownscaleWidth: 512,
      artDownscaleHeight: 512,
    );
    _justAudioBackgroundInitialized = true;
  } catch (e, st) {
    debugPrint('ensureJustAudioBackgroundInitialized: $e\n$st');
    return;
  }
  await PlayerController.rebindActiveCoordinatorToNativePlayer();
}

/// Ensures background playback init finished and yields one event-loop turn so
/// the shared native player bind from [PlayerController] can settle.
Future<void> waitForPlaybackPlatformReady() async {
  if (_playbackPlatformReady) return;
  _readyFuture ??= _markPlaybackPlatformReady();
  await _readyFuture!;
}

Future<void> _markPlaybackPlatformReady() async {
  await ensureJustAudioBackgroundInitialized();
  await Future<void>.delayed(Duration.zero);
  _playbackPlatformReady = true;
}
