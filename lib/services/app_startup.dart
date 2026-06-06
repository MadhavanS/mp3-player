import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;

import '../platform/windows_window.dart';
import 'metadata_god_init_stub.dart'
    if (dart.library.io) 'metadata_god_init_io.dart';
import 'playback_platform_gate.dart';

export 'playback_platform_gate.dart'
    show ensureJustAudioBackgroundInitialized, waitForPlaybackPlatformReady;

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

  await ensureJustAudioBackgroundInitialized();
}
