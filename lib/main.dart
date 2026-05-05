import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_mediaNotificationSupported) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.example.mp3_player.audio',
      androidNotificationChannelName: 'Now playing',
      androidNotificationChannelDescription:
          'Playback controls while the app is in the background.',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      preloadArtwork: true,
    );
  }
  runApp(const Mp3PlayerApp());
}

bool get _mediaNotificationSupported {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}
