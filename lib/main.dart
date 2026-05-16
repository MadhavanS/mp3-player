import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'app.dart';
import 'platform/windows_window.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initWindowsWindowOnLaunch();
  if (_mediaNotificationSupported) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.example.mp3_player.audio',
      androidNotificationChannelName: 'Now playing',
      androidNotificationChannelDescription:
          'Playback controls while the app is in the background.',
      // PNG mipmaps are reliable as FGS small icons; vectors can fail on some OEMs.
      androidNotificationIcon: 'mipmap/ic_launcher',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      preloadArtwork: true,
      // Large embedded movie-poster art can fail or OOM in the Android notification pipeline.
      artDownscaleWidth: 512,
      artDownscaleHeight: 512,
    );
  }
  runApp(const MadPlayerApp());
}

bool get _mediaNotificationSupported {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}
