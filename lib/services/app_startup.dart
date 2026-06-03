import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:just_audio_background/just_audio_background.dart';

import '../platform/windows_window.dart';
import 'metadata_god_init_stub.dart'
    if (dart.library.io) 'metadata_god_init_io.dart';

bool _justAudioBackgroundInitialized = false;
bool _deferredStartupStarted = false;

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

  if (_mediaNotificationSupported && !_justAudioBackgroundInitialized) {
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
      debugPrint('runDeferredAppStartup JustAudioBackground: $e\n$st');
    }
  }
}

bool get _mediaNotificationSupported {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}
