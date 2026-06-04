import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:just_audio_background/just_audio_background.dart';

import '../audio/player_controller.dart';
import '../platform/windows_window.dart';
import 'metadata_god_init_stub.dart'
    if (dart.library.io) 'metadata_god_init_io.dart';

bool _justAudioBackgroundInitialized = false;
bool _deferredStartupStarted = false;

/// Must run before the first [AudioPlayer] is constructed (see [main]).
///
/// Deferred init after [runApp] races [PlayerController]'s constructor and leaves
/// `just_audio_background supports only a single player instance` on load.
Future<void> ensureJustAudioBackgroundInitialized() async {
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
      androidNotificationOngoing: true,
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

/// Runs after [runApp] so the first Flutter frame is not blocked on I/O.
Future<void> runDeferredAppStartup() async {
  if (_deferredStartupStarted) return;
  _deferredStartupStarted = true;

  try {
    await initMetadataGodIfEnabled();
  } catch (e, st) {
    debugPrint('runDeferredAppStartup metadata_god: $e\n$st');
  }

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    try {
      await showWindowsWindowWhenReady();
    } catch (e, st) {
      debugPrint('runDeferredAppStartup windows window: $e\n$st');
    }
  }

  await ensureJustAudioBackgroundInitialized();
}

bool get _mediaNotificationSupported {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}
